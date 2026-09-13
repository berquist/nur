{
  lib,
  buildPythonPackage,
  fetchFromGitHub,
  runtimeShell,

  bc,

  # build-system
  setuptools,

  # dependencies
  ase,
  click,
  doped,
  hiphive,
  importlib-metadata,
  matplotlib,
  monty,
  numpy,
  pandas,
  pymatgen,
  pymatgen-analysis-defects,
  seaborn,
  tqdm,

  # tests
  pytestCheckHook,
  pytest-mpl,
}:

# ShakeNBreak — defect structure-searching by bond distortion and rattling, and
# the target of the `quacc[defects]` chain.  Everything under it is packaged for
# its sake: ../doped, ../pydefect, ../vise, ../hiphive, ../trainstation,
# ../cmcrameri and ../matplotlib-label-lines.
#
# Distribution and import are both `shakenbreak`; the CLI is `snb`.
buildPythonPackage {
  pname = "shakenbreak";
  version = "3.4.4-unstable-2026-04-14";
  pyproject = true;
  __structuredAttrs = true;

  # Seven commits past the v3.4.4 tag; `setup.py` still declares 3.4.4.
  src = fetchFromGitHub {
    owner = "SMTG-Bham";
    repo = "ShakeNBreak";
    rev = "8d715442ab4452cf4d15e5413465d75a0938c0e3";
    hash = "sha256-PsRtN6W/tFnZAHhJly8nXJpkaGfw48PMd7D+rE1M8hY=";
  };

  # `snb-run` is not a Python entry point that does the work itself: it hands
  # off to a shell script shipped inside the package, with
  #
  #   subprocess.call(f"{os.path.dirname(__file__)}/SnB_run.sh ...", shell=True)
  #
  # and that script opens `#!/bin/bash`.  Nothing provides `/bin/bash` here —
  # the build sandbox has only `/bin/sh`, and neither does NixOS — so the script
  # never executes, `snb-run` produces nothing at all, and the only sign of it
  # is `test_run` asserting against an empty string.  That is a real defect for
  # anyone running this on NixOS, not merely a test artefact.
  #
  # `runtimeShell` rather than `stdenv.shell`, this being a script that ships
  # and runs on the host; the reverse of ../enumlib, where the same `/bin/bash`
  # problem is in a Makefile read only at build time.  Its git mode is 100755
  # and setuptools keeps that, so nothing needs to restore the execute bit.
  postPatch = ''
    substituteInPlace shakenbreak/SnB_run.sh \
      --replace-fail '#!/bin/bash' '#!${runtimeShell}'
  '';

  # That script also needs `bc`, which it uses seven times to compare energies —
  # `if (($(echo "$energy_diff_to_unperturbed > 2" | bc -l)))` and the like.
  # Everything else it reaches for is grep, awk, sed, wc, tail, cp, mv, rm, ls,
  # head, date and basename, all of which stdenv supplies during the build and
  # any normal environment supplies afterwards; `bc` is the one that is usually
  # absent from both.
  #
  # The failure is silent, which is why it is wrapped rather than left to the
  # user: with no `bc` the command substitution yields an empty string, the
  # arithmetic test around it is simply false, and the branch is skipped.  No
  # error is printed and `snb-run` reports success having quietly declined to
  # filter the distortions stuck in high-energy basins.
  # One element per argv entry, as ../dotdrop does — `__structuredAttrs` passes
  # this list through without word-splitting, so the whole flag written as a
  # single string reaches makeWrapper as one argument and it dies with
  # "makeWrapper doesn't understand the arg --prefix PATH : /nix/store/...".
  makeWrapperArgs = [
    "--suffix"
    "PATH"
    ":"
    (lib.makeBinPath [ bc ])
  ];

  build-system = [ setuptools ];

  # This is the half of the doped cycle that declares the other, and it has to
  # be: shakenbreak imports doped at module scope in five of its modules — cli,
  # plotting, analysis, input, energy_lowering_distortions — so there is no
  # shakenbreak without doped.  ../doped has the requirement in the other
  # direction removed, and its note explains the whole arrangement.
  #
  # hiphive is a real dependency but a lazy one: `distortions.py` imports it
  # inside the rattle function, with the comment "restrict hiphive import to
  # within rattle function here, to minimise dependencies (namely numba)".
  #
  # tqdm is imported at module scope and declared by nobody — the fourth package
  # in this cluster with that habit, after vise, pydefect and doped.
  dependencies = [
    ase
    click
    doped
    hiphive
    importlib-metadata
    matplotlib
    monty
    numpy
    pandas
    pymatgen
    pymatgen-analysis-defects
    seaborn
    tqdm
  ];

  # pytest-mpl registers the `mpl_image_compare` marker that 35 tests carry;
  # `--mpl` is deliberately not passed, so the plotting runs and the pixels go
  # uncompared.  Same decision as ../doped and ../matplotlib-label-lines.
  #
  # **No pytest-xdist**, for the reason ../doped documents at length and this
  # suite shares: five of its eight modules `os.chdir`, `shutil.move` or
  # `shutil.rmtree` their way around the working tree, which parallel workers
  # cannot survive.  Here it is known in advance rather than diagnosed from a
  # wrecked build log.
  nativeCheckInputs = [
    pytestCheckHook
    pytest-mpl
  ];

  # `test_run` shells out to the `snb-run` console script by name, so the
  # package's own scripts have to be findable while its tests run.  Same
  # one-line fix as ../aiida-pseudo and ../aiida-gromacs; `$out/bin` is already
  # populated, the install phase having run before this one.
  preCheck = ''
    export PATH="$out/bin:$PATH"
  '';

  # 42 MB of reference distortion output under `tests/data`.  As in ../doped,
  # the suite does not need VASP: its POTCAR-dependent assertions sit behind a
  # `_potcars_available()` check of the same shape, by the same authors.
  enabledTestPaths = [ "tests" ];

  disabledTests = [
    # pandas 3 moved under this one.  `energy_lowering_distortions.py` keeps
    # floats and strings in one "Bond Distortion" column, picks the numeric rows
    # back out with `isinstance(x, float)`, and sorts them with
    # `sort_values(by="Bond Distortion", key=abs)`.  pandas 3 stores that column
    # Arrow-backed, so `abs` reaches pyarrow rather than numpy and raises
    # `ArrowNotImplementedError: Function 'abs_checked' has no kernel matching
    # input types (large_string)`.
    #
    # Upstream is already uneasy about this code — the comment twenty lines
    # below the failure reads "needs to be done this way because 'key' in
    # pd.sort_values() needs to be vectorised..." — so leave it to them rather
    # than patching the dtype handling from here.
    "test_compare_struct_to_distortions"
  ];

  pythonImportsCheck = [
    "shakenbreak"
    "shakenbreak.analysis"
    "shakenbreak.cli"
    "shakenbreak.distortions"
    "shakenbreak.energy_lowering_distortions"
    "shakenbreak.input"
    "shakenbreak.io"
    "shakenbreak.plotting"
  ];

  meta = {
    description = "Defect structure searching by bond distortion and rattling";
    homepage = "https://github.com/SMTG-Bham/ShakeNBreak";
    changelog = "https://github.com/SMTG-Bham/ShakeNBreak/blob/main/CHANGELOG.rst";
    license = lib.licenses.mit;
    mainProgram = "snb";
    maintainers = with lib.maintainers; [ berquist ];
  };
}
