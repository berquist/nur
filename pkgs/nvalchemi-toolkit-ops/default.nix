{
  lib,
  buildPythonPackage,
  fetchFromGitHub,

  # build-system
  hatchling,

  # dependencies
  numpy,
  warp-lang,

  # optional-dependencies
  jax,
  torch,

  # tests
  pytestCheckHook,
  pytest-asyncio,
  pytest-xdist,
  torch-pme,
  vesin,
}:

# nvalchemi-toolkit-ops — NVIDIA's Warp primitives for atomistic simulation:
# neighbour lists, segment reductions, MD integrators and optimisers,
# Lennard-Jones and Ewald/PME electrostatics, written as `warp` kernels with
# optional Torch and JAX bindings over the same code.
#
# **This is the package four others were written off for**, and it turns out to
# need nothing.  ../../docs/TODO.md called it "the NVIDIA wall" blocking
# `torch-sim`, `orb-models`, `mattersim` and `pet-mad`, on the strength of the
# name and the vendor rather than the metadata — the same reasoning that had
# ../deepmd-kit and ../fairchem-core recorded as blocked for months.  Reading
# `pyproject.toml`: Apache-2.0, hatchling, pure Python, and two dependencies,
# `numpy` and `warp-lang >= 1.13.0`.  nixpkgs has warp-lang at 1.15.0.
#
# There is no compiled extension here at all.  Warp kernels are ordinary Python
# functions that warp JIT-compiles at *run* time, and nixpkgs builds warp-lang
# with `standaloneSupport = true` — its LLVM-based CPU backend — so they compile
# and run in a build sandbox with no GPU and no CUDA.  nixpkgs proves that for
# itself in `warp-lang.passthru.tests.cpu`.
#
# Internal, not re-exported: nothing here depends on it yet.  `orb-models` is
# the first dependant that would, and it asks for exactly this version —
# `nvalchemi-toolkit-ops[torch]>=0.4.1,<0.5`.
buildPythonPackage (finalAttrs: {
  pname = "nvalchemi-toolkit-ops";
  version = "0.4.1";
  pyproject = true;
  __structuredAttrs = true;

  src = fetchFromGitHub {
    owner = "NVIDIA";
    repo = "nvalchemi-toolkit-ops";
    tag = "v${finalAttrs.version}";
    hash = "sha256-Xv7vo2yib2neIeQWAR9CXmm1D+CmT75z/5XYatEFmX0=";
  };

  # One import escaped upstream's own optional-dependency guard, and the cost is
  # out of all proportion to the mistake.  `test_ewald.py` has the apparatus —
  # a `try: from torchpme import EwaldCalculator` / `except ModuleNotFoundError:
  # HAS_TORCHPME = False`, and every class that needs it carries
  # `@pytest.mark.skipif(not HAS_TORCHPME, ...)` — and then imports one more
  # symbol from torchpme at module scope, outside the try.
  #
  # nixpkgs has no torch-pme, so that module raises at *collection*, and a
  # collection error stops the entire pytest run: 8129 items collected, 5712
  # selected, none of them run.  The module holds 225 tests and exactly 14 touch
  # torchpme, all of them in classes that already skip themselves.
  #
  # Worth sending upstream.  ../torch-pme is packaged now, so the guard is not
  # what makes the module collect any more — it stays because the bug is real,
  # because the patch is what will be sent, and because it keeps the suite
  # collectible on any path where torch-pme is absent.
  #
  # The second patch is the CUDA gate.  The first full run of this suite on a
  # machine with no CUDA device reported 1124 failures, and they divide cleanly:
  # 1087 were a CUDA device asked for and not found, 36 were the torchpme import
  # above, and **one** was a real defect — see `disabledTests`.  This patch is
  # what answers the 1087; the suite assumes a CUDA device in four different
  # ways and checks for one in two of them.  See the patch's own header.
  #
  # The third patch is the one torch-pme's arrival exposed.  This suite could
  # not run at all while ../torch-pme failed to build, because it is a check
  # input; with it building, 73 PME comparison tests ran for the first time and
  # every one of them died on a keyword argument.  torch-pme 0.4.0 moved
  # `prefactor` off the calculators and onto the potentials, and these tests
  # were written against 0.3.x.  See the patch's own header for why removing the
  # argument is exact rather than approximate.
  patches = [
    ./torchpme-import-guard.patch
    ./cuda-gating.patch
    ./torchpme-prefactor-moved.patch
  ];

  # Five modules pick a CUDA device in the test body rather than through a
  # fixture or a parametrisation, so the conftest gate cannot see them: it reads
  # names, parameters and paths, and a literal in a function body is none of
  # those.  Making the literal conditional is what the rest of the suite already
  # does — test/interactions/test_lj.py has a `device` fixture that is exactly
  # `"cuda:0" if wp.is_cuda_available() else "cpu"`, and then six of its tests
  # call a helper whose *default* is the bare string.
  #
  # Better than skipping them: these eighteen tests run on the CPU backend
  # instead of not running at all.  Every one of these modules already imports
  # `warp as wp`.
  #
  # The eight spaces in the second pattern are load-bearing.  `wp_device` ends
  # in `device`, so a bare `device = "cuda:0"` would match the `wp_device` lines
  # too — and, since the first substitution has already rewritten those, would
  # rewrite them a second time.  Anchoring on the indentation separates the two:
  # what precedes `device` on a `wp_device` line is `wp_`, not whitespace.
  postPatch = ''
    substituteInPlace test/neighbors/test_naive_kernels.py \
      --replace-fail \
        '        wp_device = "cuda:0"' \
        '        wp_device = "cuda:0" if wp.is_cuda_available() else "cpu"'

    substituteInPlace \
      test/neighbors/test_naive_kernels.py \
      test/neighbors/test_naive_dual_kernels.py \
      test/neighbors/test_batch_naive_kernels.py \
      test/neighbors/test_batch_naive_dual_kernels.py \
      --replace-fail \
        '        device = "cuda:0"' \
        '        device = "cuda:0" if wp.is_cuda_available() else "cpu"'

    substituteInPlace test/interactions/test_lj.py \
      --replace-fail \
        'dtype=np.float64, device="cuda:0"' \
        'dtype=np.float64, device="cuda:0" if wp.is_cuda_available() else "cpu"'

    # Three more shapes of the same literal, all found once torch-pme let the
    # suite run to the end.  None of them is reachable from the conftest gate or
    # from the four substitutions above.
    #
    # `DEVICE` at module scope in two modules.  Same rewrite as the rest, and
    # simpler, because at column zero there is no indentation to anchor on and
    # no `wp_device` to collide with.  Both modules already `import warp as wp`.
    substituteInPlace \
      test/test_warp_dispatch.py \
      test/dynamics/test_integrator_shared.py \
      --replace-fail \
        'DEVICE = "cuda:0"' \
        'DEVICE = "cuda:0" if wp.is_cuda_available() else "cpu"'

    # `wp.get_device` with the literal passed straight in, twice.
    substituteInPlace test/interactions/electrostatics/test_multipole_kernels.py \
      --replace-fail \
        'wp.get_device("cuda:0")' \
        'wp.get_device("cuda:0" if wp.is_cuda_available() else "cpu")'

    # test/interactions/test_lj.py again, and this one is a *torch* device
    # rather than a warp one, which is why the substitution above does not
    # reach it: six tests build their warp arrays on the `device` fixture and
    # then hard-code `.cuda()` for the torch tensors they hand to `cell_list`.
    # All six already take that fixture, and warp's device strings -- "cuda:0"
    # and "cpu" -- are valid torch device strings too, so routing the torch
    # side through the same value is both the smaller change and the more
    # correct one: `wp.from_torch` further down requires the two to agree, and
    # hard-coding one of them is what stopped them agreeing.
    substituteInPlace test/interactions/test_lj.py \
      --replace-fail '.cuda()' '.to(device)' \
      --replace-fail 'dtype=torch.bool, device="cuda")' 'dtype=torch.bool, device=device)'

    # A genuine defect in upstream's own reference helper rather than a device
    # problem.  `brute_force_neighbors` falls back to `np.eye(3)` when a test
    # passes no cell, which is float64 whatever `positions` is, and vesin 0.6.1
    # rejects a float32 `points` against a float64 `box`.  Only the `no_pbc`
    # float32 parametrisations reach it -- one test in test_naive.py and one in
    # test_naive_dual_cutoff.py.  `positions` is already a numpy array by this
    # line, so its `.dtype` is the one to copy.
    substituteInPlace test/neighbors/test_utils.py \
      --replace-fail \
        'cell = np.eye(3)' \
        'cell = np.eye(3, dtype=positions.dtype)'
  '';

  build-system = [ hatchling ];

  # The whole of upstream's `dependencies`.  hatchling reads the version out of
  # `nvalchemiops/__init__.py`, so there is no setuptools-scm pretend-version to
  # set here — the tarball carries the real number.
  dependencies = [
    numpy
    warp-lang
  ];

  # Upstream declares six extras and they are two packages under
  # CUDA-flavoured names: `torch`, `torch-cu12` and `torch-cu13` are all
  # `torch>=2.8.0`, and `jax`, `jax-cu12`, `jax-cu13` are all `jax[cudaNN]`.
  # The wheel suffixes are a uv-resolver concern — `[tool.uv] conflicts` lists
  # them as mutually exclusive — and mean nothing to a Nix package set, which
  # has one torch and one jax.  So two extras rather than six.
  #
  # The `[cudaNN]` marker on the jax ones has no equivalent here: nixpkgs' jax
  # is the CPU build unless `config.cudaSupport` is on, and that is a consumer's
  # choice made once for the whole package set rather than per dependency.  It
  # is the right jax either way — `nvalchemiops.jax` is a set of `jax.custom_vjp`
  # wrappers around warp kernels, and nothing in it is CUDA-only.
  optional-dependencies = {
    jax = [ jax ];
    torch = [ torch ];
  };

  # warp writes its JIT kernel cache to `$HOME/.cache/warp` the first time a
  # kernel is launched, and every test here launches one.  `preBuild` rather
  # than `preCheck`, for the reason ../aiida-core's own note gives: the import
  # check runs in a later phase than the tests and needs the same writable home.
  preBuild = ''
    export HOME="$(mktemp -d)"
  '';

  nativeCheckInputs = [
    pytestCheckHook
    pytest-asyncio
    pytest-xdist
    jax
    torch
    torch-pme
    vesin
  ];

  # `asyncio_mode = "auto"` in upstream's `[tool.pytest.ini_options]`, which
  # errors as an unknown ini option without the plugin.
  #
  # torch is a check input rather than only an extra because the suite imports
  # it at module scope in about seventy of its modules, `test/neighbors`' plain
  # kernel tests and `test/test_types.py` included — not only under
  # `bindings/torch/`.  Dropping it would cost most of the collection, not the
  # binding tests alone.
  #
  # jax is one for a weaker but sufficient reason: its bindings are about
  # twenty modules under `bindings/jax/`, they import jax at module scope, and
  # without it they would be deselected — which would leave `nvalchemiops.jax`
  # with no coverage at all and no import check.  The three front ends are the
  # same arithmetic through three interfaces, which upstream's own
  # `test/conftest.py` says outright (it orders collection JAX -> Warp -> Torch
  # so each framework's device caches can be released before the next), but
  # "covered elsewhere" is an argument about the kernels, not about the binding
  # layer, and the binding layer is what these modules test.
  #
  # pytest-xdist because this suite is 8129 items and took 1 h 27 m serially,
  # which is not a check phase anyone will wait for.  nixpkgs' hook passes
  # `--numprocesses=$NIX_BUILD_CORES` when the plugin is present.  Nothing here
  # shares state between tests — warp's kernel cache under `$HOME` is the one
  # thing several workers touch at once, and it is content-addressed.
  #
  # ../torch-pme and ../vesin are this repository's own packages, and both are
  # here for the same reason: each is the independent implementation half of a
  # comparison that otherwise skips.  torch-pme answers `HAS_TORCHPME` in four
  # electrostatics modules — the Ewald and PME reference, which is the
  # correctness half of that suite.  vesin answers `requires_vesin` in the two
  # neighbour-list binding conftests, about sixty tests whose whole purpose is
  # checking these neighbour lists against a library that does not share their
  # code.  A suite that only compares a kernel with itself is worth much less.
  pytestFlags = [
    # Upstream's own marker, applied by `test/neighbors/conftest.py` to items
    # whose name mentions cuda or gpu — within that directory only, which is
    # what `patches` above generalises.  Kept because it is upstream's
    # mechanism and it also covers the twenty tests marked `gpu` by hand.
    "-m"
    "not gpu"
  ];

  # One genuine defect rather than a missing device: the test calls `cell_list()`
  # with a `shift_range_per_dimension` keyword that the function does not take at
  # v0.4.1, so it fails with a TypeError on any machine.  It is the only failure
  # in the whole 8129-item suite that a CUDA device would not have fixed.
  disabledTests = [ "test_suggest_then_run_under_torch_compile" ];

  pythonImportsCheck = [
    "nvalchemiops"
    "nvalchemiops.batch_utils"
    "nvalchemiops.dynamics"
    "nvalchemiops.interactions"
    "nvalchemiops.jax"
    "nvalchemiops.math"
    "nvalchemiops.neighbors"
    "nvalchemiops.segment_ops"
    "nvalchemiops.torch"
  ];

  meta = {
    description = "NVIDIA Warp primitives for GPU-enabled computational chemistry and atomistic simulation";
    homepage = "https://github.com/NVIDIA/nvalchemi-toolkit-ops";
    changelog = "https://github.com/NVIDIA/nvalchemi-toolkit-ops/blob/v${finalAttrs.version}/CHANGELOG.md";
    license = lib.licenses.asl20;
    maintainers = with lib.maintainers; [ berquist ];
  };
})
