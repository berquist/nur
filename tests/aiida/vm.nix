# tests/aiida/vm.nix
#
# VM-based integration tests for the AiiDA NixOS module.  These boot a real
# NixOS VM, so the real aiida-core — and, for the plugin test, the real
# aiida-cp2k and cp2k — have to be buildable.
#
#   nix build .#checks.x86_64-linux.vm-aiida-daemon-local-db
#   just vm-test aiida-daemon-local-db
#   just vm-test aiida-daemon-sqlite
#   $(nix-build tests/aiida/vm.nix -A daemon-local-db.driver)/bin/nixos-test-driver
#
# pkgs must arrive with the aiida overlay already applied, for the same reason
# spelled out at the top of ../qcarchive/vm.nix: testers.nixosTest uses the pkgs
# argument directly as the package set for VM nodes, so nixpkgs.overlays inside
# a node module comes too late.  From the command line that takes
#
#   nix-build tests/aiida/vm.nix -A daemon-local-db \
#     --arg pkgs 'import <nixpkgs> { overlays = [ (import ./overlays).aiida ]; }'
{
  pkgs ? import <nixpkgs> {
    overlays = [ (import ../../overlays).aiida ];
  },
}:

let
  inherit (pkgs) lib;

  aiidaModule = ../../nixos-modules/aiida.nix;

  # PostgreSQL, a Python interpreter carrying numpy and pymatgen, and a circus
  # arbiter supervising worker processes do not fit in the 512 MiB default.
  # mkDefault so the CP2K node can raise both without a conflict.
  minimalVM = {
    boot.loader.grub.enable = false;
    virtualisation.diskSize = lib.mkDefault 4096; # MiB
    virtualisation.memorySize = lib.mkDefault 2048; # MiB
  };

  # Run something as the daemon's own user, with the same environment the units
  # get.  `verdi` reads AIIDA_PATH to find the profile, and aiida-core touches
  # $HOME at import time (see pkgs/aiida-core/default.nix), so both have to be
  # set for a command run outside systemd.  The cd matters too: sudo keeps the
  # caller's working directory, and the test driver starts in one the aiida user
  # cannot read.
  asAiida =
    command:
    "cd /var/lib/aiida && sudo -u aiida env AIIDA_PATH=/var/lib/aiida HOME=/var/lib/aiida ${command}";

  verdi = "verdi -p main";

  # Scripts are run through `verdi run` rather than a bare python3.  That picks
  # the interpreter verdi itself is running under — the withPackages environment
  # the module built, holding aiida-core *and* the plugins — and loads the
  # profile before executing, so nothing here has to guess at a path or repeat
  # load_profile().
  runScript = script: asAiida "${verdi} run ${script}";

  # The daemon worker's own log.  A process wedged in WAITING writes nothing to
  # the journal, nothing to its own node report and nothing to the broker's log
  # — the worker's log file is the only place that says what it was doing.  The
  # path follows AiiDA's own layout under AIIDA_PATH: `.aiida/daemon/log/` plus
  # the profile name, both fixed here for the same reason `verdi` is.
  daemonLog = "/var/lib/aiida/.aiida/daemon/log/aiida-main.log";

  # A code node for /bin/bash, which is what ArithmeticAddCalculation actually
  # executes: its input file is a shell script computing x + y.  pkgs.bash
  # rather than /bin/bash, which NixOS does not provide.
  createBashCode = asAiida ''
    ${verdi} code create core.code.installed \
      --non-interactive \
      --label add \
      --computer localhost \
      --default-calc-job-plugin core.arithmetic.add \
      --filepath-executable ${lib.getExe pkgs.bash}
  '';

  # Submit MultiplyAddWorkChain and print its pk.
  #
  # `core.arithmetic.multiply_add` rather than the `core.arithmetic.add_multiply`
  # workfunction: a process *function* can only be run in the caller's own
  # process, never submitted, so it would prove nothing about the daemon.  The
  # WorkChain is submitted, picked up by a daemon worker, and itself submits an
  # ArithmeticAddCalculation — so a pass exercises the broker, the worker, the
  # scheduler and the local transport, which is everything the module wires up.
  submitWorkchain = pkgs.writeText "submit-multiply-add.py" ''
    from aiida import orm
    from aiida.engine import submit
    from aiida.plugins import WorkflowFactory

    MultiplyAdd = WorkflowFactory("core.arithmetic.multiply_add")

    node = submit(
        MultiplyAdd,
        x=orm.Int(3),
        y=orm.Int(5),
        z=orm.Int(4),
        code=orm.load_code("add@localhost"),
    )
    print(node.pk)
  '';

  # Report on a submitted process, with three distinct exit codes, because the
  # poller below has to tell "not yet" apart from "never".  Shared by the
  # workchain and the CP2K tests, which differ only in which output they read.
  #
  #   0  finished OK, and the named output is on stdout
  #   1  not terminated yet — keep polling
  #   3  terminated without finishing OK — stop, the diagnosis is on stdout
  #
  # Everything goes to stdout rather than stderr because the test driver pipes
  # only stdout back to itself; stderr reaches the console log, but not the
  # string the poller can quote in the error it raises.
  checkProcess =
    outputExpression:
    pkgs.writeText "check-process.py" ''
      import sys

      from aiida import orm

      node = orm.load_node(int(sys.argv[1]))

      if not node.is_terminated:
          sys.exit(f"still running: {node.process_state}")

      if not node.is_finished_ok:
          print(f"process failed: state={node.process_state} exit={node.exit_status} {node.exit_message}")

          # EXCEPTED carries no exit code at all — the traceback is here and
          # nowhere else, which is what a bare `exit=None None` was hiding.
          print(f"exception: {node.exception}")

          from aiida.cmdline.utils.common import (
              get_calcjob_report,
              get_process_function_report,
              get_workchain_report,
          )

          # The dispatch `verdi process report` itself does: no single helper
          # covers every process class.  For a WorkChain this descends into the
          # children, so a calcjob that failed under it reports here too.
          if isinstance(node, orm.CalcJobNode):
              print(get_calcjob_report(node))
          elif isinstance(node, orm.WorkChainNode):
              print(get_workchain_report(node, "REPORT"))
          elif isinstance(node, (orm.CalcFunctionNode, orm.WorkFunctionNode)):
              print(get_process_function_report(node))

          sys.exit(3)

      print(${outputExpression})
    '';

  # MultiplyAddWorkChain's single output.  Bound once so the two tests that
  # submit it agree on the checker, and so it is one derivation rather than two
  # identical ones.
  checkResult = checkProcess "node.outputs.result.value";

  # Poll until a submitted process reaches a terminal state, then read its
  # result back.  `retry` comes from the NixOS test driver.
  #
  # Exit code 3 is re-raised rather than polled through.  A process that has
  # terminated without finishing OK will not change state again, so continuing
  # to ask can only burn the whole timeout and then report the timeout instead
  # of the fault — which is exactly what happened to daemon-rabbitmq: it knew
  # at 78 seconds that the workchain had EXCEPTED, then spent 911 more seconds
  # printing the same line 150 times and died claiming it had timed out.
  # `retry` calls this predicate directly, so an exception here propagates out
  # of it untouched, and the report goes into the failure message.
  # A process that never leaves WAITING is the other half of the problem, and
  # the checker cannot speak to it: it reports only on terminal states, so a
  # hang produces 150 identical "still running" lines and then a bare timeout.
  # Dumping these three on the way out covers it — `process status` gives the
  # tree and each node's state, which is what says whether the child calcjob
  # was ever created and where it stopped; `process report` gives the log
  # entries; the daemon log gives the worker's side.  They run on the way out
  # of both failure paths, so the terminal case gets them too.
  awaitProcess = checker: pk: ''
    import datetime

    def process_finished(_):
        status, output = machine.execute(${builtins.toJSON (runScript checker)} + f" {${pk}}")
        if status == 3:
            raise Exception(
                f"process {${pk}} reached a terminal state without finishing OK:\n" + output
            )
        return status == 0

    def dump_process_diagnostics():
        for label, command in [
            ("verdi process status", ${builtins.toJSON (asAiida "${verdi} process status")} + f" {${pk}}"),
            ("verdi process report", ${builtins.toJSON (asAiida "${verdi} process report")} + f" {${pk}}"),
            ("verdi process list -a", ${builtins.toJSON (asAiida "${verdi} process list -a")}),
            ("daemon log", ${builtins.toJSON (asAiida "tail -n 400 ${daemonLog}")}),
        ]:
            # Status ignored on purpose: this runs while something has already
            # gone wrong, and a diagnostic that raises would replace the fault
            # with itself.
            _status, out = machine.execute(command)
            print(f"----- {label} -----")
            print(out)

    with machine.nested("waiting for process ${pk} to finish"):
        try:
            retry(process_finished, timeout = datetime.timedelta(seconds = 900))
        except Exception:
            dump_process_diagnostics()
            raise
  '';

in
{
  # ==========================================================================
  # Test 1: the default configuration — local PostgreSQL, the ZeroMQ broker,
  # a localhost computer, one worker.
  #
  # Verifies:
  #   - aiida-init.service creates the profile and its storage
  #   - aiida-daemon.service reaches active state under Type=forking
  #   - the PostgreSQL role and database exist
  #   - `verdi status` reports storage and daemon healthy
  #   - the daemon survives a restart, which is what proves the pid file the
  #     unit names is really the one circus writes
  # ==========================================================================
  daemon-local-db = pkgs.testers.nixosTest {
    name = "aiida-daemon-local-db";

    nodes.machine =
      { ... }:
      {
        imports = [
          minimalVM
          aiidaModule
        ];

        services.aiida = {
          enable = true;
          # Distinctive values, so the assertions below prove the profile the
          # daemon loaded is the one this module created rather than a default.
          profileName = "main";
          userEmail = "vm-test@localhost";
          # Exercise the migration unit.  On a freshly created profile the
          # storage is already at the Alembic head, so this must be a
          # successful no-op — the property worth checking, since with
          # autoMigrate set it runs on every boot.
          database.autoMigrate = true;
          configOptions = {
            "warnings.development_version" = false;
          };
          # Defaults elsewhere: createLocally = true, peer auth over the Unix
          # socket, broker.backend = "core.zeromq", setupLocalhost = true.
        };
      };

    testScript = ''
      machine.start()
      machine.wait_for_unit("multi-user.target")

      machine.wait_for_unit("aiida-init.service")
      machine.wait_for_unit("aiida-storage-migrate.service")
      machine.wait_for_unit("aiida-daemon.service")

      # Reaching a oneshot unit is not the same as it having succeeded.
      machine.succeed(
          "systemctl show -p Result --value aiida-storage-migrate.service | grep -x success"
      )

      # PostgreSQL role and database.  Unlike the qcfractal module this one
      # creates both; see the comment on services.postgresql in
      # nixos-modules/aiida.nix for why the two differ.
      machine.succeed("sudo -u postgres psql -c '\\du' | grep aiida")
      machine.succeed("sudo -u postgres psql -c '\\l' | grep aiida")

      # `verdi status` exits non-zero if any component is unreachable, so this
      # single call covers the profile, the storage connection and the daemon.
      status = machine.succeed(${builtins.toJSON (asAiida "${verdi} status")})
      print(status)
      assert "Daemon is running" in status, f"daemon not running: {status}"

      # The profile really is ours, not an implicit default.
      profile = machine.succeed(${builtins.toJSON (asAiida "${verdi} profile show main")})
      assert "vm-test@localhost" in profile, f"unexpected profile: {profile}"

      # A restart has to work.  Type=forking means systemd tracks the circus
      # arbiter through the pid file built by Config.filepaths(); if that path
      # were wrong the unit would come up looking active once and never
      # restart cleanly.
      machine.succeed("systemctl restart aiida-daemon.service")
      machine.wait_for_unit("aiida-daemon.service")
      status = machine.succeed(${builtins.toJSON (asAiida "${verdi} status")})
      assert "Daemon is running" in status, f"daemon did not come back: {status}"
    '';
  };

  # ==========================================================================
  # Test 2: a real process, submitted to the daemon and run to completion on
  # the localhost computer.  Nothing but bash is needed, which makes this the
  # cheap end-to-end check of the whole chain.
  # ==========================================================================
  workchain-arithmetic = pkgs.testers.nixosTest {
    name = "aiida-workchain-arithmetic";

    nodes.machine =
      { ... }:
      {
        imports = [
          minimalVM
          aiidaModule
        ];

        services.aiida.enable = true;
      };

    testScript = ''
      machine.start()
      machine.wait_for_unit("aiida-daemon.service")

      machine.succeed(${builtins.toJSON createBashCode})

      pk = machine.succeed(${builtins.toJSON (runScript submitWorkchain)}).strip().splitlines()[-1]
      print(f"submitted MultiplyAddWorkChain as {pk}")

      ${awaitProcess checkResult "pk"}

      result = int(
          machine.succeed(
              ${builtins.toJSON (runScript checkResult)} + f" {pk}"
          ).strip().splitlines()[-1]
      )

      # 3 * 5 + 4.  Exact, because this is integer arithmetic done by the shell.
      assert result == 19, f"expected 19, got {result}"
    '';
  };

  # ==========================================================================
  # Test 3: the plugin round trip — a real CP2K single-point energy submitted
  # through aiida-cp2k, run by a daemon worker.
  #
  # This is also where aiida-cp2k's examples/ are covered.  The package's own
  # checkPhase deliberately restricts collection to test/, because the examples
  # need a running daemon and a broker; here there is one.  The inputs below
  # are examples/single_calculations/example_dft.py, reading its basis set,
  # pseudopotentials and geometry straight out of ${aiida-cp2k.src}.
  #
  # CP2K rather than Quantum ESPRESSO: this example ships everything it needs as
  # files in the repository, where a QE run would have to fetch SSSP pseudos
  # over the network.
  # ==========================================================================
  plugin-cp2k = pkgs.testers.nixosTest {
    name = "aiida-plugin-cp2k";

    nodes.machine =
      { ... }:
      {
        imports = [
          minimalVM
          aiidaModule
        ];

        # A DFT calculation, even a three-atom one, wants more than the daemon
        # alone; and the CP2K closure is large.
        virtualisation.memorySize = 4096; # MiB
        virtualisation.diskSize = 8192; # MiB

        services.aiida = {
          enable = true;
          # The plugin goes in `plugins`, so it lands in the same Python
          # environment as aiida-core and its entry points become visible.
          plugins = [ pkgs.python313Packages.aiida-cp2k ];
          # The program goes in `extraPackages`, so it lands on the daemon's
          # PATH — a different thing entirely, and the distinction the two
          # options exist to make.
          extraPackages = [ pkgs.cp2k ];
        };
      };

    testScript =
      let
        exampleFiles = "${pkgs.python313Packages.aiida-cp2k.src}/examples/files";

        submitDft = pkgs.writeText "submit-cp2k-dft.py" ''
          import ase.io
          from aiida import orm
          from aiida.engine import submit

          structure = orm.StructureData(ase=ase.io.read("${exampleFiles}/h2o.xyz"))
          basis = orm.SinglefileData(file="${exampleFiles}/BASIS_MOLOPT")
          pseudo = orm.SinglefileData(file="${exampleFiles}/GTH_POTENTIALS")

          parameters = orm.Dict(
              {
                  "FORCE_EVAL": {
                      "METHOD": "Quickstep",
                      "DFT": {
                          "BASIS_SET_FILE_NAME": "BASIS_MOLOPT",
                          "POTENTIAL_FILE_NAME": "GTH_POTENTIALS",
                          "QS": {"EPS_DEFAULT": 1.0e-12},
                          "MGRID": {"NGRIDS": 4, "CUTOFF": 280, "REL_CUTOFF": 30},
                          "XC": {"XC_FUNCTIONAL": {"_": "LDA"}},
                          "POISSON": {"PERIODIC": "none", "PSOLVER": "MT"},
                      },
                      "SUBSYS": {
                          "KIND": [
                              {"_": "O", "BASIS_SET": "DZVP-MOLOPT-SR-GTH", "POTENTIAL": "GTH-LDA-q6"},
                              {"_": "H", "BASIS_SET": "DZVP-MOLOPT-SR-GTH", "POTENTIAL": "GTH-LDA-q1"},
                          ]
                      },
                  }
              }
          )

          builder = orm.load_code("cp2k@localhost").get_builder()
          builder.structure = structure
          builder.parameters = parameters
          builder.file = {"basis": basis, "pseudo": pseudo}
          builder.metadata.options.resources = {
              "num_machines": 1,
              "num_mpiprocs_per_machine": 1,
          }
          builder.metadata.options.max_wallclock_seconds = 600
          builder.metadata.options.withmpi = False

          print(submit(builder).pk)
        '';

        checkEnergy = checkProcess ''node.outputs.output_parameters["energy"]'';

        createCp2kCode = asAiida ''
          ${verdi} code create core.code.installed \
            --non-interactive \
            --label cp2k \
            --computer localhost \
            --default-calc-job-plugin cp2k \
            --filepath-executable ${pkgs.cp2k}/bin/cp2k.psmp
        '';
      in
      ''
        machine.start()
        machine.wait_for_unit("aiida-daemon.service")

        # The plugin must be visible to the daemon's interpreter.  Checking
        # this first turns an entry-point regression into a clear failure here
        # rather than an "Unknown entry point" fifteen minutes into a DFT run.
        plugins = machine.succeed(${builtins.toJSON (asAiida "${verdi} plugin list aiida.calculations")})
        assert "cp2k" in plugins, f"aiida-cp2k entry points not visible: {plugins}"

        machine.succeed(${builtins.toJSON createCp2kCode})

        pk = machine.succeed(${builtins.toJSON (runScript submitDft)}).strip().splitlines()[-1]
        print(f"submitted Cp2kCalculation as {pk}")

        ${awaitProcess checkEnergy "pk"}

        energy = float(
            machine.succeed(
                ${builtins.toJSON (runScript checkEnergy)} + f" {pk}"
            ).strip().splitlines()[-1]
        )
        print(f"CP2K LDA/DZVP-MOLOPT energy for H2O: {energy} Ha")

        # Bracket the known result (about -17.1 Ha) loosely enough to tolerate
        # a CP2K version bump, tightly enough that a wrong molecule, basis set
        # or unit would fail.
        assert -18.0 < energy < -16.0, f"energy out of range: {energy}"
      '';
  };

  # ==========================================================================
  # Test 4: aiida-core's own SSH transport suite, against a real sshd.
  #
  # Unlike every other test in this file, this one is not about the NixOS
  # module.  It exists because these tests cannot run where the rest of
  # aiida-core's suite does — ../../pkgs/aiida-core/default.nix keeps
  # tests/transports/test_all_plugins.py in disabledTestPaths, and this is
  # where it actually runs.
  #
  # The obstacle is not the sshd itself but the *account*.  Nix's build sandbox
  # writes an /etc/passwd giving every user `/noshell` as their login shell,
  # and it is a read-only bind mount that no derivation can amend.  sshd
  # resolves the target user's shell through getpwnam and execs it, and AiiDA's
  # transport runs shell commands rather than only SFTP, so a correctly
  # configured sshd in a check phase would accept the connection and then fail
  # every command.  A booted VM has real accounts, which is the whole fix.
  #
  # The client binaries are a different problem and are solved in the package:
  # 78 of the failures here were a bare `FileNotFoundError: 'ssh'` with no
  # connection attempted, so openssh is a nativeCheckInput there.  What is left
  # for this test is the part that genuinely needs something listening.
  # ==========================================================================
  transports-ssh =
    let
      # tests/conftest.py registers `sphinx.testing.fixtures` as a root pytest
      # plugin and pulls in aiida.tools.pytest_fixtures, so the interpreter
      # running the suite needs the same set ../../pkgs/aiida-core/default.nix
      # lists in nativeCheckInputs — not merely aiida-core.
      pythonEnv = pkgs.python313.withPackages (ps: [
        ps.aiida-core
        ps.pytest
        ps.pytest-asyncio
        ps.pytest-timeout
        ps.pytest-regressions
        ps.pytest-rerunfailures
        ps.pytest-xdist
        ps.psutil
        ps.sphinx

        # tests/engine/test_memory_leaks.py measures live objects through
        # pympler.muppy; without it the module fails to import rather than
        # skipping, which would take the whole file down.
        ps.pympler
      ]);

      # The suite is not installed with the package — buildPythonPackage keeps
      # tests out of $out — so it comes from the same src the derivation built
      # from.  Taking it from the package rather than re-fetching is what keeps
      # the two from drifting to different revisions.
      testSrc = pkgs.python313Packages.aiida-core.src;

      # Upstream's addopts wants pytest-cov and pytest-instafail and writes
      # coverage outside the build; cleared for the same reason the package
      # clears it.
      # tests/conftest.py defaults to the `rmq` broker, and the four non-transport
      # files added below launch processes, so they need one that exists.  This
      # VM runs no RabbitMQ, so it takes the same in-process ZeroMQ broker the
      # package's check phase uses.  Storage stays on conftest's sqlite default:
      # unlike the build there is no pgtest cluster here, and none of these
      # files is about the storage backend.
      #
      # --tb=short instead of the default: the driver logs the whole output of
      # a failed `succeed`, so nothing here needs to trim it, and a run that
      # fails four times out of 498 should say why four times rather than once.
      # An earlier `| tail -40` did trim it, and cost three of four diagnoses —
      # it also handed `succeed` tail's exit status rather than pytest's.
      pytest = "${pythonEnv}/bin/pytest --override-ini=addopts= -p no:cacheprovider --broker-backend zmq --tb=short";
    in
    pkgs.testers.nixosTest {
      name = "aiida-transports-ssh";

      nodes.machine = {
        imports = [ minimalVM ];

        services.openssh = {
          enable = true;
          settings = {
            # The suite authenticates with a key it generates below.  Password
            # auth off keeps a misconfigured key from silently passing by
            # falling back to a prompt.
            PasswordAuthentication = false;
            PermitRootLogin = "no";
          };
        };

        users.users.tester = {
          isNormalUser = true;
          home = "/home/tester";
        };

        environment.systemPackages = [
          pythonEnv
          pkgs.openssh
        ];

        # NixOS puts nothing in /bin but `sh`, and four of these tests want
        # /bin/bash specifically.  Two of them are the memory-leak tests, which
        # install a code whose `filepath_executable` is that literal path; the
        # calcjob then "finishes" with an empty output file and the parser
        # returns 320, which is the same indirect failure
        # ../../pkgs/aiida-core/default.nix works around with a sed over tests/.
        # The other two are TestAuthenticationScript, which writes a script with
        # a `#!/bin/bash` shebang and runs it through `shell=True` — that sed
        # never matched them, since it only rewrites /bin/bash quoted on both
        # sides, and tests/transports/ is held out of the build regardless.  So
        # this VM is the first place they run at all.
        #
        # Supplying the path rather than rewriting the source is what keeps the
        # promise made below: the suite runs here exactly as upstream wrote it,
        # so a pass means the real test passed.  A real cluster has /bin/bash
        # too, which makes this the more faithful environment, not a fudged one.
        systemd.tmpfiles.rules = [
          "L+ /bin/bash - - - - ${lib.getExe pkgs.bash}"
        ];
      };

      testScript = ''
        machine.start()
        machine.wait_for_unit("multi-user.target")
        machine.wait_for_unit("sshd.service")
        machine.wait_for_open_port(22)

        # The keypair is generated in the VM rather than committed here: the
        # tests connect as `tester` to localhost, so the account has to trust
        # itself, and a checked-in private key would be a private key in a
        # public repository for no gain.
        machine.succeed("sudo -u tester mkdir -p /home/tester/.ssh")
        # Single-quoted on the Python side so the empty passphrase can be
        # written with double quotes: a pair of single quotes anywhere in here,
        # in code or in a comment, would close this Nix indented string.
        machine.succeed(
            'sudo -u tester ssh-keygen -t ed25519 -N "" -f /home/tester/.ssh/id_ed25519'
        )
        machine.succeed(
            "sudo -u tester cp /home/tester/.ssh/id_ed25519.pub"
            " /home/tester/.ssh/authorized_keys"
        )
        machine.succeed("sudo -u tester chmod 600 /home/tester/.ssh/authorized_keys")

        # Pre-seed known_hosts.  paramiko is told AutoAddPolicy by the fixture,
        # but the `core.ssh_async` openssh backend shells out to `ssh`, which
        # would sit at an interactive host-key prompt instead, and the asyncssh
        # backend validates against known_hosts by default.
        machine.succeed(
            "sudo -u tester sh -c 'ssh-keyscan -H localhost"
            " >> /home/tester/.ssh/known_hosts'"
        )
        machine.succeed("sudo -u tester chmod 600 /home/tester/.ssh/known_hosts")

        # Prove the account can reach itself before blaming AiiDA for anything.
        machine.succeed(
            "sudo -u tester ssh -o BatchMode=yes localhost true"
        )

        # Likewise for the /bin/bash the node config supplies.  Without it four
        # of these tests fail on a missing interpreter, and neither failure says
        # so: the calcjob ones surface as a parser exit code 320 and the
        # authentication-script ones as a wrong exit code.  Asserting it here
        # turns a silently reintroduced regression into one obvious line.
        machine.succeed("test -x /bin/bash")

        machine.succeed("cp -r ${testSrc} /home/tester/aiida-core")
        machine.succeed("chown -R tester:users /home/tester/aiida-core")

        # -p no:randomly is not needed, but xdist is: the suite is slow enough
        # serially that the default test driver timeout becomes a factor.
        #
        # These are exactly the paths ../../pkgs/aiida-core/default.nix holds
        # back, and they are run *unfiltered* — the four files after
        # tests/transports/ keep their local-transport parametrizations there
        # and give up only their SSH ones, so running them whole here means the
        # VM is a superset of the build rather than a patch over its gaps.
        output = machine.succeed(
            "cd /home/tester/aiida-core && sudo -u tester env HOME=/home/tester"
            " ${pytest} -n 4"
            " tests/transports/"
            " tests/engine/daemon/test_execmanager.py"
            " tests/engine/test_memory_leaks.py"
            " tests/orm/nodes/data/test_remote.py"
            " tests/tools/pytest_fixtures/test_orm.py"
            " tests/orm/data/code/test_installed.py"
            " 2>&1"
        )
        print(output)
      '';
    };

  # ==========================================================================
  # Test 5: the same deployment on RabbitMQ instead of ZeroMQ.  This is the
  # only coverage of broker.backend = "core.rabbitmq", broker.createLocally,
  # and the `verdi profile configure-broker` step in aiida-init that goes with
  # them.
  # ==========================================================================
  daemon-rabbitmq = pkgs.testers.nixosTest {
    name = "aiida-daemon-rabbitmq";

    nodes.machine =
      { ... }:
      {
        imports = [
          minimalVM
          aiidaModule
        ];

        # An Erlang VM alongside PostgreSQL and the daemon.
        virtualisation.memorySize = 3072; # MiB

        services.aiida = {
          enable = true;
          broker.backend = "core.rabbitmq";
          # Default: createLocally = true, so services.rabbitmq is enabled here
          # and the daemon is ordered after it.
          configOptions = {
            # aiida/brokers/rabbitmq/broker.py accepts 3.6.0 <= v < 3.8.15 and
            # nixpkgs is far past that, so without this every `verdi`
            # invocation in this test would print an unsupported-version
            # warning.  Silencing it keeps a real complaint visible.
            #
            # The gap is not only cosmetic.  On 4.2.5 this test also excepted
            # with `aiormq DeliveryError (None, Basic.Nack)` the moment the
            # workchain's first calcfunction broadcast its own state change:
            # the submitting `verdi run` drops its exclusive broadcast queue as
            # it exits, and RabbitMQ 4 nacks a confirmed publish routed at a
            # queue mid-teardown.  ../../pkgs/plumpy/default.nix carries the
            # patch, and this test is what fails if it is ever dropped.
            "warnings.rabbitmq_version" = false;
          };
        };
      };

    testScript = ''
      machine.start()
      machine.wait_for_unit("multi-user.target")
      machine.wait_for_unit("rabbitmq.service")
      machine.wait_for_unit("aiida-init.service")
      machine.wait_for_unit("aiida-daemon.service")

      status = machine.succeed(${builtins.toJSON (asAiida "${verdi} status")})
      print(status)
      assert "Daemon is running" in status, f"daemon not running: {status}"

      # The profile must name RabbitMQ.  Without this the test would pass
      # against a profile that silently fell back to no broker at all, which is
      # exactly what detect_rabbitmq_config() does on a failed probe — and the
      # reason aiida-init pins the connection parameters explicitly.
      profile = machine.succeed(${builtins.toJSON (asAiida "${verdi} profile show main")})
      assert "core.rabbitmq" in profile, f"broker not configured: {profile}"

      # And a process has to actually get through it.
      machine.succeed(${builtins.toJSON createBashCode})
      pk = machine.succeed(${builtins.toJSON (runScript submitWorkchain)}).strip().splitlines()[-1]

      ${awaitProcess checkResult "pk"}

      result = int(
          machine.succeed(
              ${builtins.toJSON (runScript checkResult)} + f" {pk}"
          ).strip().splitlines()[-1]
      )
      assert result == 19, f"expected 19, got {result}"
    '';
  };

  # ==========================================================================
  # Test 6: the same deployment on core.sqlite_dos instead of core.psql_dos.
  # This is the only coverage of storage.backend, and it does the work of
  # tests 1 and 2 together in one boot rather than two, because everything
  # downstream of profile creation is shared with the PostgreSQL path --
  # SqliteDosStorage subclasses PsqlDosBackend, and only the engine and the
  # migrator differ underneath.
  #
  # What genuinely cannot be checked at evaluation time is the negative: that
  # PostgreSQL is not merely unused but absent from the machine, and that
  # `verdi profile setup core.sqlite_dos` accepts the flags the module hands
  # it.  The flag sets of the two storage subcommands do not overlap, so a
  # psql-only option leaking into the sqlite branch is a click error that
  # surfaces here and in aiida-init.service's journal, nowhere else.
  # ==========================================================================
  daemon-sqlite = pkgs.testers.nixosTest {
    name = "aiida-daemon-sqlite";

    nodes.machine =
      { ... }:
      {
        imports = [
          minimalVM
          aiidaModule
        ];

        services.aiida = {
          enable = true;
          storage.backend = "core.sqlite_dos";
          # The migrator is one of the two pieces with a genuinely different
          # implementation under SQLite -- SqliteDosMigrator subclasses
          # PsqlDosMigrator and replaces the Alembic version path -- so running
          # it is worth the ordering edge, exactly as in daemon-local-db.
          database.autoMigrate = true;
          configOptions = {
            "warnings.development_version" = false;
          };
          # Defaults elsewhere: database.createLocally follows storage.backend
          # and is therefore false, broker.backend = "core.zeromq",
          # setupLocalhost = true.  So this machine runs no service at all
          # beyond the daemon itself, which is the whole point of the backend.
        };
      };

    testScript = ''
      machine.start()
      machine.wait_for_unit("multi-user.target")

      machine.wait_for_unit("aiida-init.service")
      machine.wait_for_unit("aiida-storage-migrate.service")
      machine.wait_for_unit("aiida-daemon.service")

      # Reaching a oneshot unit is not the same as it having succeeded.
      machine.succeed(
          "systemctl show -p Result --value aiida-storage-migrate.service | grep -x success"
      )

      # Not "PostgreSQL is unused" but "PostgreSQL is not on this machine".
      # `systemctl cat` on a unit that was never generated exits non-zero, so
      # this fails loudly if any part of the PostgreSQL wiring survived the
      # backend switch.
      machine.fail("systemctl cat postgresql.service")
      machine.fail("systemctl cat aiida-postgresql-setup.service")

      # The storage really landed at the --filepath the module pinned, rather
      # than at the uuid-suffixed directory SqliteDosStorage.CliModel would
      # have picked for itself.
      machine.succeed("test -f /var/lib/aiida/.aiida/storage/main/database.sqlite")
      machine.succeed("test -d /var/lib/aiida/.aiida/storage/main/container")

      # `verdi status` exits non-zero if any component is unreachable, so this
      # single call covers the profile, the storage connection and the daemon.
      status = machine.succeed(${builtins.toJSON (asAiida "${verdi} status")})
      print(status)
      assert "Daemon is running" in status, f"daemon not running: {status}"

      # And the profile is on the backend we asked for, not on a psql_dos one
      # that happened to come up.
      profile = machine.succeed(${builtins.toJSON (asAiida "${verdi} profile show main")})
      assert "core.sqlite_dos" in profile, f"unexpected storage backend: {profile}"

      # Type=forking tracks the circus arbiter through a pid file whose path is
      # built from the profile name, not the storage backend -- but a restart
      # is cheap once the machine is up, and it is what proves the daemon can
      # reopen the SQLite database it just closed.
      machine.succeed("systemctl restart aiida-daemon.service")
      machine.wait_for_unit("aiida-daemon.service")
      status = machine.succeed(${builtins.toJSON (asAiida "${verdi} status")})
      assert "Daemon is running" in status, f"daemon did not come back: {status}"

      # The real end-to-end, and the one risk the backend introduces: the
      # submitting process and a daemon worker write to the same SQLite file
      # concurrently.  aiida-core handles the contention (see the
      # OperationalError note in aiida/engine/utils.py), and this is what says
      # so on a running system.
      machine.succeed(${builtins.toJSON createBashCode})
      pk = machine.succeed(${builtins.toJSON (runScript submitWorkchain)}).strip().splitlines()[-1]
      print(f"submitted MultiplyAddWorkChain as {pk}")

      ${awaitProcess checkResult "pk"}

      result = int(
          machine.succeed(
              ${builtins.toJSON (runScript checkResult)} + f" {pk}"
          ).strip().splitlines()[-1]
      )
      assert result == 19, f"expected 19, got {result}"
    '';
  };
}
