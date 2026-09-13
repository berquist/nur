# enumlib — derivative-superstructure enumeration, as Fortran executables.
#
# Not a Python package and not in nixpkgs.  It is here because pymatgen shells
# out to it: `pymatgen/command_line/enumlib_caller.py` resolves `enum.x` and
# `makestr.x` off PATH at *import* time and `EnumlibAdaptor` refuses to run
# without both, so every `MagneticStructureEnumerator` user needs them present
# — atomate2's `test_magnetic_orderings` being the one in this repo.
#
# pymatgen will warn that this is "the legacy Fortran enum.x" and suggest
# Enumlib.jl instead.  That is advisory only; the probe behind it runs
# `enum.x --version`, which this binary does not understand, and pymatgen
# treats any failure as "not the Julia engine".
{
  lib,
  stdenv,
  fetchFromGitHub,

  gfortran,
}:

let
  # enumlib carries symlib as a git submodule and `src/Makefile` builds it in
  # place at `../symlib/src`, so the contents have to be there before make runs.
  #
  # Fetched separately rather than with `fetchSubmodules = true` because a
  # submodule-bearing hash cannot be computed offline — see the header of
  # ../../scripts/offline-src-hash.sh, which is where both hashes here came
  # from.  The tag is what the submodule pointer names, so this stays in step
  # with `src` by pinning the same commit upstream does.
  symlib = fetchFromGitHub {
    owner = "msg-byu";
    repo = "symlib";
    tag = "v2.0.2";
    hash = "sha256-IZH1RMHVxjmRJqMi/hzZ58tXch/YdW71k1UaMkeksHk=";
  };
in

stdenv.mkDerivation (finalAttrs: {
  pname = "enumlib";
  version = "2.0.6-unstable-2024-11-15";

  # HEAD rather than v2.0.6, three commits past it.  Two are comment fixes; the
  # third repairs `get_gspace_representation`, which used the wrong basis for
  # non-cubic cells — precisely the case a magnetic-ordering enumeration hits.
  src = fetchFromGitHub {
    owner = "msg-byu";
    repo = "enumlib";
    rev = "67217859c1cfe6e1d8cfe25b76a1d14a28c6030e";
    hash = "sha256-jqwoiXL6dzHS5kBUKOpIdQWC5veuKR58xF/DSOzmPWo=";
  };

  nativeBuildInputs = [ gfortran ];

  # `src/Makefile`'s `pre_comp` rule stamps a version into
  # derivative_structure_generator.f90, which writes it to a `VERSION.enum`
  # file beside every enumeration.  It gets that string from a shell
  # substitution of `git describe`, and there is no git and no repository here:
  # the backticks would expand to nothing and every run would report an empty
  # version.  Substituting the literal keeps the file meaningful and
  # deterministic — this is what upstream's own command prints at this rev.
  #
  # The other rewrite is `src/Makefile`'s own `SHELL = /bin/bash`, which the
  # build sandbox does not have — nix binds `/bin/sh` and nothing else, so make
  # echoes the first compile line and then dies with
  #
  #   make: /bin/bash: No such file or directory
  #   make: *** [Makefile:129: sorting.o] Error 127
  #
  # `stdenv.shell` rather than `/bin/sh`.  `/bin/sh` would work, because that is
  # the one path nix binds into the sandbox and it is bash there — but it is
  # furniture the sandbox lends, not an input this derivation declares, and with
  # the sandbox off it is whatever the host has.  A store path is the same fix
  # without the impurity, and costs no new build input: stdenv already closes
  # over its own shell.  Only the build reads this file, so `stdenv.shell` is
  # the right one of the two spellings; nothing installed refers back to it.
  #
  # symlib's Makefile sets no SHELL and so needs nothing.
  postPatch = ''
    cp -r ${symlib}/. symlib/
    chmod -R u+w symlib

    substituteInPlace src/Makefile \
      --replace-fail '`git describe --tags --dirty --abbrev=4`' 'v2.0.6-3-g6721' \
      --replace-fail '/bin/bash' '${stdenv.shell}'
  '';

  # Two hand-written Makefiles, no configure and no install target, so both
  # phases are spelled out.
  #
  # The target list is upstream's own .travis.yml minus two entries, and both
  # are upstream code that no longer compiles rather than anything about this
  # build:
  #
  #   `2Dplot.x` links aux_src/splot.f, which calls `sind`/`cosd`, and gfortran
  #   provides neither.  Upstream knows: .travis.yml says so in a comment, which
  #   is why its own list omits this one too.
  #
  #   `compare_enum_files.x` compiles aux_src/compare_two_enum_files.f90, and
  #   that file has rotted.  Four `write` statements have their format string's
  #   continuation line commented out with the `&` left behind (557db14, 2019),
  #   and `get_dvector_permutations` is called with eight arguments against the
  #   seven-argument interface it has had since f6694db (2021), so `LatDim1`
  #   lands in the `eps` slot.  Nothing about this build: upstream's .travis.yml
  #   is older than both, which is why its own CI never caught them.
  #
  #   Both fixes are determined rather than guesses, and neither is applied
  #   here.  The file has not compiled since 2019, mid-rewrite of its own
  #   algorithm, so making it build says nothing about whether it works — and
  #   nothing in this repo runs it.  ../../docs/TODO.md carries the diagnosis
  #   and what verifying it would take.
  #
  # The two that remain past `enum.x` and `makestr.x` cost nothing and do build,
  # so they are kept — but they are extras, not the point of the package.
  #
  # Serial on purpose.  `src/Makefile` declares no dependencies between its
  # object files, and Fortran modules must be compiled in use order, so `-j`
  # fails outright rather than merely being unreproducible.  `enum.x` also
  # depends on the phony `pre_comp`, which is what descends into symlib — under
  # `-j` that races the objects that `-I../symlib/src` needs.
  #
  # `enum.x` is asked for first, and `libenum.a` is not asked for at all
  # (`makestr.x` pulls it in as a prerequisite).  Order matters because
  # `pre_comp` is what runs the version substitution above, and only `enum.x`
  # and the other executables list it: naming `libenum.a` first — as upstream's
  # .travis.yml does — compiles every object before the rewrite happens, and in
  # a single make run they are not compiled twice.
  buildPhase = ''
    runHook preBuild

    make -C symlib/src F90=gfortran
    make -C src F90=gfortran DEBUG=false \
      enum.x makestr.x find_structure_in_list.x polya.x

    runHook postBuild
  '';

  # Executables only.  Nothing here links against libenum.a, and its `.mod`
  # files would bind consumers to this exact gfortran; the two programs pymatgen
  # names are the whole point of the package, and the other two come along
  # because they build and cost nothing.
  installPhase = ''
    runHook preInstall

    install -Dm755 -t "$out/bin" \
      src/enum.x src/makestr.x \
      src/find_structure_in_list.x src/polya.x

    runHook postInstall
  '';

  doCheck = true;

  # Upstream runs no tests: `tests/` is recorded fortpy fixture data for a
  # Python 2 harness that is not in the repository, and .travis.yml's `script:`
  # is `echo 0`.  So this check is ours, built out of the one recorded answer
  # upstream does ship.
  #
  # `support/input/out.fcc.binary.17` is a saved enumeration of the binary fcc
  # derivative superstructures for cell sizes 2 through 4, and its name is the
  # invariant: there are 17 of them (2 + 3 + 12, by the `#size` column).  That
  # is a property of the lattice, not of the recording, so it survives the
  # output-format drift that makes the file itself undiffable — the header this
  # version writes carries four columns the recording does not have.
  #
  # `struct_enum.in.fcc` is the same lattice with a different search range, so
  # the two lines that differ are edited rather than a new input written by
  # hand; `--replace-fail` is what notices if upstream changes the example.
  checkPhase = ''
    runHook preCheck

    mkdir enum-check
    cp support/input/struct_enum.in.fcc enum-check/struct_enum.in
    substituteInPlace enum-check/struct_enum.in \
      --replace-fail '    1 8   # Starting and ending cell sizes' \
                     '    2 4   # Starting and ending cell sizes' \
      --replace-fail '0.10000000E-06 # Epsilon' \
                     '0.10000000E-03 # Epsilon'

    pushd enum-check
    ../src/enum.x struct_enum.in

    # Everything after the "start #tot ..." column header is one structure.
    found=$(awk '/^start/ { seen = 1; next } seen && NF { n++ } END { print n + 0 }' \
      struct_enum.out)
    if [ "$found" != 17 ]; then
      echo "enum.x found $found binary fcc superstructures for n=2..4, expected 17"
      exit 1
    fi

    # The other half of what EnumlibAdaptor drives: makestr.x turns one of those
    # labelings into a POSCAR.
    ../src/makestr.x struct_enum.out 1
    test -s vasp.000001
    popd

    runHook postCheck
  '';

  meta = {
    description = "Generator of derivative superstructures of a parent lattice";
    homepage = "https://github.com/msg-byu/enumlib";
    changelog = "https://github.com/msg-byu/enumlib/blob/${finalAttrs.src.rev}/HISTORY.md";
    license = lib.licenses.mit;
    platforms = lib.platforms.unix;
    mainProgram = "enum.x";
    maintainers = with lib.maintainers; [ berquist ];
  };
})
