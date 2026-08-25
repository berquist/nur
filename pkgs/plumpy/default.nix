{
  lib,
  buildPythonPackage,
  fetchFromGitHub,

  # build-system
  flit-core,

  # dependencies
  greenback,
  greenlet,
  kiwipy,
  pyyaml,

  # tests
  pytestCheckHook,
  pytest-asyncio,
  shortuuid,
}:

buildPythonPackage rec {
  pname = "plumpy";
  version = "0.26.0";
  pyproject = true;

  # `[tool.flit.sdist]` excludes `tests/`, as in ../kiwipy.
  src = fetchFromGitHub {
    owner = "aiidateam";
    repo = "plumpy";
    tag = "v${version}";
    hash = "sha256-dxd0gDe0pvte84U/gfSrp40fTvymzhPqNh8a2dsYpg4=";
  };

  # A process state broadcast is best-effort by construction, and upstream
  # already treats it that way: `on_entered` warns and carries on for
  # ConnectionClosed, ChannelInvalidStateError and kiwipy.TimeoutError, because
  # the state change itself is already committed to storage and only the
  # notification is lost.  kiwipy publishes these `mandatory=False` for the same
  # reason, with the comment "we don't expect the message to be routable to
  # anyone".  This adds the fourth way delivery can fail rather than inventing a
  # new policy for it.
  #
  # DeliveryError is what RabbitMQ 4 produces here.  It nacks a confirmed
  # publish whose target queue is being torn down, and the `verdi run` that
  # submits a workchain drops its exclusive broadcast queue the moment it exits
  # -- so the daemon worker's very next state broadcast is nacked and the whole
  # process EXCEPTS with the arithmetic already done and correct.  nixpkgs
  # carries RabbitMQ 4.2.5 and aiida-core claims support only below 3.8.15, so
  # every NixOS deployment on the RabbitMQ broker is exposed to this; see
  # tests/aiida/vm.nix (daemon-rabbitmq), which is where it was caught.
  #
  # aio_pika.exceptions is already the module the two names above come from, and
  # aio-pika is already a dependency through kiwipy's `rmq` extra, so this costs
  # no new input.  Worth dropping once upstream handles it.
  #
  # DeliveryError joins the existing tuple rather than getting an `except` clause
  # of its own, and that is not a style preference: a replacement string spanning
  # more than one line cannot survive a Nix indented string.  `''` strips the
  # common leading whitespace from every line it contains, and for a Python
  # suite embedded in a shell argument that whitespace *is* the indentation --
  # the body of a new clause loses four columns and the build dies with
  # "expected an indented block after 'except' statement".  Same trap as the
  # heredoc ../aiida-cp2k/default.nix avoids, and the same answer: keep every
  # --replace-fail on one line.  The message is widened to cover all four cases,
  # since upstream's "no connection available" would send anyone reading the
  # daemon log after a nack looking for a network fault that is not there.
  postPatch = ''
    substituteInPlace src/plumpy/processes.py \
      --replace-fail \
        "from aio_pika.exceptions import ChannelInvalidStateError, ConnectionClosed" \
        "from aio_pika.exceptions import ChannelInvalidStateError, ConnectionClosed, DeliveryError" \
      --replace-fail \
        "            except (ConnectionClosed, ChannelInvalidStateError):" \
        "            except (ConnectionClosed, ChannelInvalidStateError, DeliveryError):" \
      --replace-fail \
        "                message = 'Process<%s>: no connection available to broadcast state change from %s to %s'" \
        "                message = 'Process<%s>: could not broadcast state change from %s to %s'"
  '';

  build-system = [ flit-core ];

  dependencies = [
    greenback
    greenlet
    kiwipy
    pyyaml
  ]
  ++ kiwipy.optional-dependencies.rmq;

  # Upstream's `tests` extra also lists pytest-cov, which only the coverage
  # addopts below want.  pytest-notebook and ipykernel were never in it at all.
  nativeCheckInputs = [
    pytestCheckHook
    pytest-asyncio
    shortuuid
  ];

  # `--cov-report xml --cov-append` without pytest-cov is an "unrecognized
  # arguments" abort, the same one ../disk-objectstore hit.
  pytestFlags = [ "--override-ini=addopts=" ];

  # The RabbitMQ-backed communicator tests need a live broker on localhost.
  # Everything else — the process state machine, which is what aiida-core
  # actually depends on — runs in-process and is exercised here.
  #
  # Note `tests/`, not `test/`: plumpy names the directory differently from
  # ../kiwipy, and a glob that matches nothing aborts the phase outright rather
  # than being ignored.
  disabledTestPaths = [ "tests/rmq" ];

  pythonImportsCheck = [
    "plumpy"
    "plumpy.processes"
  ];

  meta = {
    description = "A python workflow library, providing the process state machine used by AiiDA";
    homepage = "https://github.com/aiidateam/plumpy";
    license = lib.licenses.mit;
    maintainers = with lib.maintainers; [ berquist ];
  };
}
