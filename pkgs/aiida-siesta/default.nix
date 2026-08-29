{
  lib,
  buildPythonPackage,
  fetchFromGitHub,

  # build-system
  flit-core,

  # dependencies
  aiida-core,
  aiida-optimize,
  aiida-pseudo,
  ase,
  seekpath,
  sisl,

  # tests
  pytestCheckHook,
  pytest-regressions,
  pgtest,
  postgresql,
  coreutils,
  stdenv,
  glibcLocalesUtf8,
}:

buildPythonPackage rec {
  # The distribution is `aiida-siesta` and the repository is
  # `aiida_siesta_plugin`, with the module a third spelling again,
  # `aiida_siesta`.  The attribute follows the distribution, like every other
  # plugin here.
  pname = "aiida-siesta";
  version = "2.0.0-unstable-2022-10-30";
  pyproject = true;

  src = fetchFromGitHub {
    owner = "siesta-project";
    repo = "aiida_siesta_plugin";
    rev = "76d04250504638d8edc88a2f915690af9ff3796b";
    hash = "sha256-jHb9taaYV7JcxcZPdVnH7GuNo/Q/nObqnUbKq80N8HE=";
  };

  build-system = [ flit-core ];

  # aiida-core for the usual pre-release reason, and seekpath because the pin
  # is `~=1.9,>=1.9.3` against nixpkgs' 2.2.1 — a major behind, though the two
  # entry points this plugin uses, `get_path` and `get_explicit_k_path`, are
  # unchanged.  `ase~=3.18` is satisfied by 3.29 under compatible-release
  # rules, and sisl and aiida-optimize are ours.
  pythonRelaxDeps = [
    "aiida-core"
    "seekpath"
  ];

  dependencies = [
    aiida-core
    aiida-optimize
    aiida-pseudo
    ase
    seekpath
    sisl
  ];

  # `remote_computer_exec=[fixture_localhost, '/bin/true']` in tests/conftest.py,
  # against a sandbox with only /bin/sh.  See ../aiida-orca/default.nix.
  #
  # The second is sisl's rename.  `SislAtomicOrbital` subclasses
  # `sisl.AtomicOrbital` and copies its quantum numbers into a dictionary, and
  # the zeta index is no longer spelled `Z`:
  #
  #   orbital_dict["Z"] = self.Z
  #   AttributeError: 'SislAtomicOrbital' object has no attribute 'Z'
  #
  # ../sisl 0.16.4 stores it as `_zeta` behind a `zeta` property; this plugin
  # was written against a 2022 sisl that still had `Z`.  Only the attribute
  # moves — the dictionary key stays `"Z"`, because that is this package's own
  # output format, which pao_manager and five tests read back.  Its neighbours
  # `n`, `l`, `m`, `P`, `R` and `q0` all still exist under those names, so this
  # one line is the whole of the name drift.
  #
  # The third and fourth substitutions are the *value* half of the same sisl
  # drift, and it is the dangerous half.  `IonData.get_orbitals` throws away
  # the orbital sisl just read and rebuilds it from the bare radial grid,
  # passing no `R`:
  #
  #   SislAtomicOrbital(orb.name(), (r, f), q0=orb.q0)
  #
  # Against the 2022 sisl that was harmless.  `set_radial(r, f)` built the
  # spline and then recursed into its own callable branch, which scanned for
  # the last point with `f**2 > 0` and stepped one grid point past it, on a
  # 0.0001 Ang grid — so R came back as the ion file's `<cutoff>` rounded up.
  # Since 0.14 (`fabca5759` and `4a4a96327`, both June 2023) `set_radial` only
  # builds the spline — its own comment says it "will defer the actual R
  # designation" — and `Orbital.__init__`, seeing `R is None`, re-derives it
  # through `radial_minimize_range`: the radius holding 99.99% of the
  # integrated `|f|`.  That is 1.5-2% *shorter* than the cutoff:
  #
  #   3s Z1  3.1566 -> 3.0901     3p Z1  4.0531 -> 3.9736
  #   3s Z2  2.3384 -> 2.2327     3p Z2  2.7169 -> 2.6023
  #
  # Those numbers are what `PaoManager` puts in `_gen_dict` and `_pol_dict`,
  # and `get_pao_block` converts them to Bohr and emits them as a `PAO.Basis`
  # block for a real SIESTA run.  So this is not test-only drift: unpatched,
  # every generated basis is uniformly short.  Only three tests noticed, and
  # only through `_pol_dict` — the `_gen_dict` assertions are `is not None`.
  #
  # sisl's ion reader is not at fault and needs no patch of its own: the
  # orbital it hands back still carries the file's cutoff as `orb.R`.  Giving
  # that back to the constructor is the whole fix, and it repairs `_gen_dict`
  # too.
  #
  # The four reference numbers then move in their last four digits, because
  # the old ones carried that 2022 round-up-to-0.0001 overshoot and the cutoff
  # itself does not — 4.0531999999999995 against 4.053122790900083 is the
  # size of it.  Rewriting them rather than deselecting the tests keeps them
  # covering what they were written to cover; see ../aiida-octopus for the
  # same call.
  postPatch = ''
    substituteInPlace tests/conftest.py \
      --replace-fail "'/bin/true'" "'${coreutils}/bin/true'"

    substituteInPlace aiida_siesta/data/atomic_orbitals.py \
      --replace-fail 'orbital_dict["Z"] = self.Z' 'orbital_dict["Z"] = self.zeta'

    substituteInPlace aiida_siesta/data/ion.py \
      --replace-fail 'q0=orb.q0)' 'q0=orb.q0, R=orb.R)'

    substituteInPlace tests/utils/test_pao_manager.py \
      --replace-fail '{3: {1: {1: 4.0531999999999995, 2: 3.1566}}}' \
                     '{3: {1: {1: 4.053122790900083, 2: 3.15655447866091}}}' \
      --replace-fail '{3: {1: {1: 4.0531999999999995}}}' \
                     '{3: {1: {1: 4.053122790900083}}}' \
      --replace-fail ' 5.965078\t 4.419101' ' 5.964992\t 4.418929' \
      --replace-fail ' 7.659398\t 5.13417' ' 7.659252\t 5.134092'
  '';

  preCheck = lib.optionalString stdenv.hostPlatform.isLinux ''
    export LOCALE_ARCHIVE="${glibcLocalesUtf8}/lib/locale/locale-archive"
  '';

  nativeCheckInputs = [
    pytestCheckHook
    pytest-regressions

    # tests/conftest.py names `aiida.manage.tests.pytest_fixtures`, the
    # deprecated module; see ../aiida-core/default.nix for what that needs
    # patched, and ../pgtest for why postgresql accompanies pgtest.
    pgtest
    postgresql
  ];

  # See ../aiida-core/default.nix for why this is preBuild and not preCheck.
  preBuild = ''
    export HOME="$(mktemp -d)"
    export AIIDA_PATH="$HOME"
  '';

  # No SIESTA binary: the calculation tests assert on generated input and the
  # parser tests replay the outputs under tests/parsers/fixtures/.
  pythonImportsCheck = [
    "aiida_siesta"
    "aiida_siesta.calculations"
    "aiida_siesta.data"
    "aiida_siesta.parsers"
    "aiida_siesta.workflows"
  ];

  meta = {
    description = "AiiDA plugin for the SIESTA DFT code";
    homepage = "https://github.com/siesta-project/aiida_siesta_plugin";
    license = lib.licenses.mit;
    maintainers = with lib.maintainers; [ berquist ];
  };
}
