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
  #
  # The second substituteInPlace is a different bug in the same file.
  # Process.spec() uses two pieces of shared mutable state to run what is really
  # a per-call handshake:
  #
  #     cls._spec = cls._spec_class()   # published half-built
  #     cls.__called = False            # one flag for every caller
  #     cls.define(cls._spec)           # sets cls.__called = True
  #     assert cls.__called, 'Process.define() was not called by ...'
  #
  # A second caller entering for the same class resets __called between the
  # first's define() and its assert, and the first dies on a message naming
  # define().  That reads like a plugin that forgot `super().define(spec)`,
  # which sends you looking in the wrong place -- every AiiDA process class does
  # call it.  ../aiida-core carries `--only-rerun Process.define...was.not.called`
  # for it, and `just ci-matrix` still lost three attempts in a row on
  # tests/parsers/test_parser.py::TestParser::test_parse_from_node.
  #
  # A threading.RLock around the rebuild was tried first and is not enough,
  # which is the whole reason this patch has the shape it does.  An RLock
  # excludes other *threads* and is transparent to the one already holding it,
  # so two parties interleaving on a single thread -- an asyncio task switch, or
  # a greenlet, and plumpy depends on both greenback and greenlet -- walk
  # straight through it.  The failure came back with the lock in place.  No lock
  # is the right answer to shared state that can be reached without threads.
  #
  # So the *flag* goes instead.  `spec` becomes a local and the flag moves onto
  # that spec object, so two concurrent builders each get their own flag and
  # both asserts pass.  The last assignment to cls._spec wins, exactly as
  # upstream.
  #
  # **cls._spec is still published before define() runs, and that is not an
  # oversight.** Assigning it afterwards was tried, on the reasoning that no
  # caller should be able to observe a half-built spec, and it broke plugins
  # that read the spec they are in the middle of defining.  aiida-siesta's
  # `BaseIterator.iteration_input` is the example — called from inside
  # `define()`, its first line is
  #
  #     if name in cls._spec.inputs.ports:
  #
  # which is an AttributeError the moment `cls._spec` is not there yet.  That is
  # ten of its tests, and it would be every user of that workchain too, not just
  # the suite.  The half-built spec is part of the contract whether or not it
  # ought to be, so the fix keeps it and takes only the shared flag away.
  #
  # `spec.__called` inside the Process body mangles to `spec._Process__called`,
  # in the assignment and in define() alike, so the two still agree.  It is
  # initialised on the local rather than left to define(), so a subclass that
  # really does forget super() still gets the assertion and its message rather
  # than an AttributeError.
  #
  # Upstream's `except Exception: del cls._spec; ...; raise` stays, minus the
  # flag reset that no longer has anything to reset.  Dropping it was tried
  # while cls._spec was being assigned late, where there was nothing to undo;
  # once the spec is published before define() again there is, and plumpy's own
  # suite says so:
  #
  #   tests/test_processes.py::TestProcess::test_raise_in_define
  #   AssertionError: ValueError not raised
  #
  # That test calls `spec()` twice on a class whose define() raises, and
  # requires the error both times.  Without the cleanup the first call leaves
  # the half-built spec published, so the second returns it instead of raising.
  # `del cls._spec` is safe here precisely because the assignment above always
  # happened first.
  #
  # Three behaviours have to hold at once, and they are what this shape is
  # tuned to: a define() that raises leaves no spec behind and raises again on
  # the next call (plumpy's test_raise_in_define); a define() that reads
  # `cls._spec` while building finds it (aiida-siesta's iteration_input); and a
  # subclass that really does forget `super().define(spec)` still gets the
  # assertion rather than an AttributeError.
  #
  # This keeps the property the aiida-core rerun comment leans on, so leave
  # `--only-rerun Process.define...was.not.called` there as a backstop and
  # expect it to stop firing.
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

    substituteInPlace src/plumpy/processes.py \
      --replace-fail \
        "            try:
                    cls._spec: ProcessSpec = cls._spec_class()  # type: ignore
                    cls.__called: bool = False  # type: ignore
                    cls.define(cls._spec)  # type: ignore
                    assert cls.__called, (
                        f'Process.define() was not called by {cls}\nHint: Did you forget to call the superclass method in '
                        'your define? Try: super().define(spec)'
                    )
                    return cls._spec  # type: ignore
                except Exception:
                    del cls._spec  # type: ignore
                    cls.__called = False
                    raise" \
        "            spec: ProcessSpec = cls._spec_class()  # type: ignore
                spec.__called = False  # type: ignore
                cls._spec = spec  # type: ignore
                try:
                    cls.define(spec)  # type: ignore
                    assert spec.__called, (  # type: ignore
                        f'Process.define() was not called by {cls}\nHint: Did you forget to call the superclass method in '
                        'your define? Try: super().define(spec)'
                    )
                except Exception:
                    del cls._spec  # type: ignore
                    raise
                return spec" \
      --replace-fail \
        "        cls.__called = True" \
        "        _spec.__called = True  # type: ignore"
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
