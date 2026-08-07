# tests/qcarchive/vm.nix
#
# VM-based integration tests for the QCFractal NixOS modules.
# These tests actually boot a NixOS VM and verify that the services start,
# PostgreSQL is initialised, and the API responds.
#
# Prerequisites
# -------------
# The real qcfractal and qcfractalcompute packages must be buildable.
# Apply the NUR overlay before running these tests:
#
#   nix-build tests/qcarchive/vm.nix \
#     --arg pkgs 'import <nixpkgs> { overlays = [ (import ../../overlays).qcfractal ]; }'
#
# Or from the flake:
#   nix build .#checks.x86_64-linux.vm-server-local-db
#
# Run options
# -----------
# Run a specific test:
#   nix-build tests/qcarchive/vm.nix -A server-local-db
#
# All tests via the flake:
#   nix build .#checks.x86_64-linux.vm-server-local-db
#
# Interactive debugging:
#   $(nix-build tests/qcarchive/vm.nix -A server-local-db.driver)/bin/nixos-test-driver

# pkgs must already have the qcfractal overlay applied, because
# testers.nixosTest uses the pkgs argument directly as the package set for
# VM nodes — nixpkgs.overlays inside a node module is evaluated too late to
# affect the pkgs instance the test framework has already constructed.
#
# From the command line:
#   nix-build tests/qcarchive/vm.nix \
#     --arg pkgs 'import <nixpkgs> { overlays = [ (import ./overlays).qcfractal ]; }'
#
# From the flake, pkgs' is already overlaid before being passed here.
{
  pkgs ? import <nixpkgs> {
    overlays = [ (import ../../overlays).qcfractal ];
  },

  # A real QC program for the compute-worker tests.  qcfractalcompute refuses
  # to start an executor with no discoverable programs, so these tests cannot
  # run with an empty PATH.
  #
  # Psi4 comes from NixOS-QChem, which is a *flake input* — ../../overlays cannot
  # provide it, so the default argument above has no pkgs.qchem.  The
  # psi4-backed tests are therefore reachable only through the flake, or by
  # supplying this argument explicitly.  Everything else in this file works
  # either way.
  #
  # The flake passes qchem.psi4 from its own instantiation of the nixpkgs
  # revision NixOS-QChem pins, with NixOS-QChem's config — only that matches
  # what nix-qchem.cachix.org holds, and it is deliberately *not*
  # nixos-qchem.packages.<system>.psi4.  See the comment in flake.nix for both
  # halves of that.  Falling back to pkgs.qchem.psi4 here still works if the
  # caller happens to have the overlay applied, it just will not hit the cache.
  psi4 ?
    pkgs.qchem.psi4 or (throw ''
      tests/vm.nix: the compute tests need Psi4, which comes from the
      nixos-qchem flake input.  Use the flake:
        nix build .#checks.x86_64-linux.vm-compute-connects
      or pass one in:
        nix-build tests/vm.nix -A compute-connects --arg psi4 '<derivation>'
    ''),
}:

let
  inherit (pkgs) lib;

  # Common settings for every test VM.  mkDefault so that individual nodes can
  # raise the limits (compute-connects needs more RAM) without a conflicting
  # definition error.
  minimalVM = {
    # No bootloader needed in a VM test.
    boot.loader.grub.enable = false;
    virtualisation.diskSize = lib.mkDefault 1024; # MiB
    # 512 MiB is not enough once PostgreSQL and a Python server that pulls in
    # numpy/pandas are both resident; 1024 matches the nixos-test default.
    virtualisation.memorySize = lib.mkDefault 1024; # MiB
  };

  # Import our NixOS modules.
  serverModule = ../../nixos-modules/qcfractal-server.nix;
  computeModule = ../../nixos-modules/qcfractal-compute.nix;

in
{
  # ==========================================================================
  # Test 1: server with local PostgreSQL (the default configuration).
  #
  # Verifies:
  #   - qcfractal-init-db.service succeeds (schema created)
  #   - qcfractal.service reaches active state
  #   - PostgreSQL role and database exist
  #   - The HTTP API responds on port 7777
  # ==========================================================================
  server-local-db = pkgs.testers.nixosTest {
    name = "qcfractal-server-local-db";

    nodes.machine =
      { ... }:
      {
        imports = [
          minimalVM
          serverModule
        ];

        services.qcfractal = {
          enable = true;
          # Bind to all interfaces so the test script can curl it.
          api.host = "0.0.0.0";
          api.port = 7777;
          # /api/v1/information is behind check_permissions("information",
          # "read"), and check_global_permission rejects the anonymous role
          # outright unless this is set.  Enabling it here also gives the
          # option end-to-end coverage.
          allowUnauthenticatedRead = true;
          # Distinctive value so the assertion below proves the generated
          # qcf_config.yaml is what the server actually loaded.
          serverName = "nixos-vm-test-server";
          # Exercise the migration unit.  On a freshly bootstrapped database
          # init-db has already stamped the alembic head, so upgrade-db should
          # be a successful no-op — which is exactly the property worth
          # checking, since it runs on every boot in this mode and must not
          # fail or re-bootstrap.
          database.autoUpgrade = true;
          # Defaults: createLocally = true, peer auth via Unix socket.
        };
      };

    testScript = ''
      machine.start()
      machine.wait_for_unit("multi-user.target")

      # Schema initialisation must complete before the server starts.
      machine.wait_for_unit("qcfractal-init-db.service")
      machine.wait_for_unit("qcfractal-upgrade-db.service")
      machine.wait_for_unit("qcfractal.service")

      # upgrade-db must have exited cleanly rather than merely been reached.
      machine.succeed(
          "systemctl show -p Result --value qcfractal-upgrade-db.service | grep -x success"
      )

      # PostgreSQL role and database should exist.
      machine.succeed(
          "sudo -u postgres psql -c '\\du' | grep qcfractal"
      )
      machine.succeed(
          "sudo -u postgres psql -c '\\l' | grep qcfractal"
      )

      # The API must respond on port 7777.  /api/v1/information returns
      # server metadata as JSON; it is readable without logging in only
      # because allowUnauthenticatedRead is set on this node.
      machine.wait_for_open_port(7777)
      response = machine.succeed("curl -sf http://localhost:7777/api/v1/information")
      import json
      info = json.loads(response)
      # get_public_server_information returns the configured server name
      # under "name" (not "server_name"), sourced from qcf_config.yaml.
      assert info["name"] == "nixos-vm-test-server", f"unexpected response: {info}"
      print(f"Server info: {info}")
    '';
  };

  # ==========================================================================
  # Test 2: openFirewall = true — port reachable from a second VM.
  # ==========================================================================
  server-open-firewall = pkgs.testers.nixosTest {
    name = "qcfractal-server-open-firewall";

    nodes = {
      server =
        { ... }:
        {
          imports = [
            minimalVM
            serverModule
          ];
          services.qcfractal = {
            enable = true;
            api.host = "0.0.0.0";
            api.port = 7777;
            openFirewall = true;
          };
        };

      client =
        { ... }:
        {
          imports = [ minimalVM ];
        };
    };

    testScript = ''
      server.start()
      client.start()

      server.wait_for_unit("qcfractal.service")
      server.wait_for_open_port(7777)

      # Client must be able to reach the server across the virtual network.
      # This node keeps the module's secure defaults (enableSecurity = true,
      # allowUnauthenticatedRead = false), so use /api/v1/ping: it is the
      # health-check route carrying @no_permission_required(), whereas
      # /api/v1/information would answer 401 to an anonymous client.
      # What is under test here is reachability, not authorization.
      client.wait_for_unit("network.target")
      import json
      pong = json.loads(client.succeed("curl -sf http://server:7777/api/v1/ping"))
      assert pong["success"], f"unexpected response: {pong}"
    '';
  };

  # ==========================================================================
  # Test 3: server with a remote PostgreSQL instance.
  #
  # Verifies that createLocally = false works: the server connects to
  # PostgreSQL over TCP rather than via the Unix socket.
  # ==========================================================================
  server-remote-db = pkgs.testers.nixosTest {
    name = "qcfractal-server-remote-db";

    nodes = {
      db =
        { ... }:
        {
          imports = [ minimalVM ];
          services.postgresql = {
            enable = true;
            enableTCPIP = true;
            # The test framework gives each node both an IPv4 and an IPv6
            # address on vlan1 and puts both in /etc/hosts, and getaddrinfo
            # prefers the IPv6 one — so "db" resolves to 2001:db8:1::1 and the
            # server connects from 2001:db8:1::2.  An IPv4-only pg_hba is
            # therefore never matched.
            authentication = lib.mkForce ''
              local all all             trust
              host  all all 0.0.0.0/0   trust
              host  all all ::/0        trust
            '';
            # Only the role: `init-db` creates the database itself, and it
            # only creates the schema on the branch where it creates the
            # database.  Pre-creating it here leaves an empty, unstamped
            # database and the server then loops on "Database needs
            # migration".
            initialScript = pkgs.writeText "qcfractal-db-init.sql" ''
              CREATE USER qcfractal CREATEDB;
            '';
          };
          networking.firewall.allowedTCPPorts = [ 5432 ];
        };

      server =
        { ... }:
        {
          imports = [
            minimalVM
            serverModule
          ];
          services.qcfractal = {
            enable = true;
            api.host = "0.0.0.0";
            database.createLocally = false;
            database.host = "db";
            database.port = 5432;
            database.name = "qcfractal";
            database.user = "qcfractal";
            # No passwordFile: trust auth is configured on the db node.
          };
        };
    };

    # The database must be accepting connections before the server boots:
    # qcfractal-init-db is a oneshot and systemd forbids Restart= on
    # Type=oneshot, so a failed migration is permanent and takes
    # qcfractal.service (which requires it) down with it.  There is no
    # cross-node ordering in the test framework, so serialise it here.
    testScript = ''
      db.start()
      db.wait_for_unit("postgresql.service")
      db.wait_for_open_port(5432)

      server.start()
      server.wait_for_unit("qcfractal-init-db.service")
      server.wait_for_unit("qcfractal.service")
      server.wait_for_open_port(7777)
      # Secure defaults are in force on this node, so /api/v1/information
      # would 401; /api/v1/ping needs no permissions.  What matters here is
      # that the server came up against the remote database at all.
      server.succeed("curl -sf http://localhost:7777/api/v1/ping")
    '';
  };

  # ==========================================================================
  # Test 4: compute worker installs a QC program and registers.
  #
  # Verifies that qcfractalcompute starts, discovers Psi4 on the PATH the
  # module builds from executor.programs, and registers itself with the
  # server advertising that program.  It deliberately stops there: no
  # calculation is submitted, so this stays the fast check that the
  # module's program wiring works.  See compute-singlepoint for the
  # end-to-end version.
  #
  # A program is not optional here — qcfractalcompute raises
  # "Executor <label> has no available programs" and exits if an executor
  # discovers none, so an empty executor.programs cannot be tested.
  # ==========================================================================
  compute-connects = pkgs.testers.nixosTest {
    name = "qcfractal-compute-connects";

    nodes.machine =
      { ... }:
      {
        imports = [
          minimalVM
          serverModule
          computeModule
        ];
        # Server + PostgreSQL + a Parsl worker pool all on one node.
        virtualisation.memorySize = 2048;

        services.qcfractal = {
          enable = true;
          api.host = "0.0.0.0";
          enableSecurity = false; # skip auth so the worker needs no password
        };

        services.qcfractalCompute = {
          enable = true;
          server.fractalUri = "http://localhost:7777";
          # username / passwordFile omitted: security is disabled on the server.
          executor.maxWorkers = 1;
          # Default is 4 GiB, which this VM does not have.
          executor.memoryPerWorker = 1.0;
          # QCEngine finds programs by probing PATH; the module builds that
          # PATH from this list.
          executor.programs = [ psi4 ];
        };
      };

    # Registration is asynchronous: the manager heartbeats to the server after
    # Parsl has finished spinning up its executor, which takes appreciably
    # longer than a fixed sleep can be relied on.  Poll instead.
    testScript = ''
      machine.start()
      machine.wait_for_unit("qcfractal.service")
      machine.wait_for_open_port(7777)
      machine.wait_for_unit("qcfractalcompute.service")

      import json

      # There is no GET /api/v1/managers route; managers are listed through
      # POST /api/v1/managers/query, whose body is a ManagerQueryFilters
      # model with every field optional, so {} means "no filter".  Responses
      # default to JSON when Accept does not ask for msgpack.
      query_managers = (
          "curl -sf -X POST http://localhost:7777/api/v1/managers/query "
          "-H 'Content-Type: application/json' -d '{}'"
      )

      def managers_registered(_):
          status, output = machine.execute(query_managers)
          if status != 0:
              return False
          return len(json.loads(output)) > 0

      with machine.nested("waiting for the compute manager to register"):
          retry(managers_registered, timeout_seconds = 180)

      # The manager reports what QCEngine found on its PATH.  Psi4 showing up
      # here is what proves executor.programs actually reached the worker,
      # rather than the worker merely having started.
      managers = json.loads(machine.succeed(query_managers))
      print(managers)
      programs = set()
      for m in managers:
          programs.update(m["programs"].keys())
      assert "psi4" in programs, f"psi4 not advertised; manager programs: {programs}"
    '';
  };

  # ==========================================================================
  # Test 5: compute worker authenticates against a secured server.
  #
  # Every other compute test runs with enableSecurity = false, which leaves the
  # module's credential path — server.username plus server.passwordFile, read
  # at start and exported as QCF_COMPUTE_SERVER__PASSWORD for pydantic-settings
  # to map onto server.password — completely uncovered.  This covers it.
  #
  # enableSecurity is on, so the worker cannot register at all without valid
  # credentials.  allowUnauthenticatedRead is also on, purely so the test
  # script can read the manager list without holding a token of its own; the
  # "anonymous" role grants managers:read, while registering a manager needs
  # managers:add, which only an authenticated compute account has.  The
  # assertion is therefore on the manager's recorded username: that field is
  # None for the unauthenticated worker in compute-connects, and must be the
  # worker account here.
  # ==========================================================================
  compute-authenticated =
    let
      workerPassword = "s3cret-worker-password";
    in
    pkgs.testers.nixosTest {
      name = "qcfractal-compute-authenticated";

      nodes.machine =
        { ... }:
        {
          imports = [
            minimalVM
            serverModule
            computeModule
          ];
          virtualisation.memorySize = 2048;

          services.qcfractal = {
            enable = true;
            api.host = "0.0.0.0";
            # enableSecurity defaults to true — stated here because it is the
            # entire point of this test.
            enableSecurity = true;
            allowUnauthenticatedRead = true;
          };

          services.qcfractalCompute = {
            enable = true;
            server.fractalUri = "http://localhost:7777";
            server.username = "worker";
            server.passwordFile = "/run/qcfractal-worker-password";
            executor.maxWorkers = 1;
            executor.memoryPerWorker = 1.0;
            executor.programs = [ psi4 ];
          };

          # A real deployment would place this with systemd credentials, agenix
          # or sops-nix.  What matters for the module is only that the file is
          # read at service start rather than baked into the unit, so a tmpfiles
          # rule is enough here.
          systemd.tmpfiles.rules = [
            "f /run/qcfractal-worker-password 0400 qcfractalcompute qcfractalcompute - ${workerPassword}"
          ];
        };

      testScript = ''
        machine.start()
        machine.wait_for_unit("qcfractal.service")
        machine.wait_for_open_port(7777)

        # The worker account does not exist yet, so qcfractalcompute is
        # expected to be failing/restarting at this point.  Create it.
        #
        # `qcfractal-server user add` validates the whole FractalConfig before
        # it touches the database, so it needs the same secrets the units get:
        # the generated api keys from secrets.env, plus the empty database
        # password that peer authentication ignores but the model requires.
        machine.succeed(
            "sudo -u qcfractal sh -c '"
            "set -a; . /var/lib/qcfractal/secrets.env; set +a; "
            "export QCF_DATABASE__PASSWORD=; "
            "${lib.getExe pkgs.qcfractal} --config=/var/lib/qcfractal/qcf_config.yaml "
            "user add worker --password ${workerPassword} --role compute'"
        )

        # Don't wait out the 30s restart backoff.
        machine.systemctl("restart qcfractalcompute.service")
        machine.wait_for_unit("qcfractalcompute.service")

        import json

        query_managers = (
            "curl -sf -X POST http://localhost:7777/api/v1/managers/query "
            "-H 'Content-Type: application/json' -d '{}'"
        )

        def managers_registered(_):
            status, output = machine.execute(query_managers)
            if status != 0:
                return False
            return len(json.loads(output)) > 0

        with machine.nested("waiting for the authenticated manager to register"):
            retry(managers_registered, timeout_seconds = 180)

        managers = json.loads(machine.succeed(query_managers))
        print(managers)

        # Registration alone proves credentials were accepted — managers:add is
        # denied to the anonymous role — and the username proves the server
        # attributed the manager to the worker account rather than treating the
        # connection as anonymous.
        usernames = {m["username"] for m in managers}
        assert usernames == {"worker"}, f"unexpected manager usernames: {usernames}"

        # The password must reach the worker by being read from the file at
        # start, never by being baked into the unit.  Resolve the actual
        # ExecStart script rather than globbing the store: a glob that matches
        # nothing makes grep exit non-zero, which machine.fail would read as
        # success, so the check would pass without having inspected anything.
        import re

        show = machine.succeed(
            "systemctl show -p ExecStart --value qcfractalcompute.service"
        )
        match = re.search(r"path=(\S+)", show)
        assert match, f"could not parse ExecStart: {show}"
        start_script = match.group(1)

        machine.succeed(f"test -f {start_script}")
        machine.succeed(f"grep -q qcfractal-worker-password {start_script}")
        machine.fail(f"grep -q '${workerPassword}' {start_script}")
      '';
    };

  # ==========================================================================
  # Test 6: end-to-end — submit a calculation and check the stored result.
  #
  # The full round trip: a client submits a singlepoint through qcportal, the
  # server queues it, the worker claims and runs it in Psi4, and the result
  # comes back through the API with a physically sensible energy.
  #
  # This is deliberately separate from compute-connects.  That test answers
  # "is the module's program wiring right?" and fails fast; this one answers
  # "does a calculation actually run and get stored?" and is much slower,
  # since it waits on a real Psi4 execution.
  # ==========================================================================
  compute-singlepoint = pkgs.testers.nixosTest {
    name = "qcfractal-compute-singlepoint";

    nodes.machine =
      { ... }:
      {
        imports = [
          minimalVM
          serverModule
          computeModule
        ];
        # Server, PostgreSQL, a Parsl worker pool and Psi4 all on one node.
        virtualisation.memorySize = 4096;
        virtualisation.diskSize = 8192;

        services.qcfractal = {
          enable = true;
          api.host = "0.0.0.0";
          enableSecurity = false; # the client below connects unauthenticated
        };

        services.qcfractalCompute = {
          enable = true;
          server.fractalUri = "http://localhost:7777";
          executor.maxWorkers = 1;
          executor.memoryPerWorker = 1.0;
          executor.programs = [ psi4 ];
        };

        # qcportal for the submitting client.  This is the same derivation the
        # server uses, reached through the overlay's python package set.
        #
        # python313, not python3: the overlay injects qcportal into *every*
        # interpreter's package set, but on 3.14 it carries meta.broken (see
        # default.nix), so `pkgs.python3` refuses to evaluate here as soon as
        # nixpkgs moves its default past 3.13.
        environment.systemPackages = [
          (pkgs.python313.withPackages (p: [ p.qcportal ]))
        ];
      };

    testScript =
      let
        # H2 at 1.4 bohr, HF/STO-3G: small enough that Psi4 finishes in
        # seconds, and a well-known reference value (about -1.117 Eh) to
        # check the stored result against.
        submitScript = pkgs.writeText "submit.py" ''
          import sys
          from qcportal import PortalClient
          from qcportal.molecules import Molecule

          client = PortalClient("http://localhost:7777")

          # Geometry is in bohr, which is qcelemental's default.
          h2 = Molecule(symbols=["H", "H"], geometry=[0.0, 0.0, 0.0, 0.0, 0.0, 1.4])

          meta, ids = client.add_singlepoints([h2], "psi4", "energy", "hf", "sto-3g")
          if not meta.success:
              sys.exit(f"submission failed: {meta}")
          print(ids[0])
        '';

        collectScript = pkgs.writeText "collect.py" ''
          import sys
          from qcportal import PortalClient

          record_id = int(sys.argv[1])
          client = PortalClient("http://localhost:7777")
          record = client.get_singlepoints(record_id)

          if record.status != "complete":
              # Not done yet, or failed.  Surface the error if there is one so
              # the test log shows why rather than just timing out.
              if record.status == "error":
                  sys.exit(f"record errored: {record.error}")
              sys.exit(f"status={record.status}")

          print(record.return_result)
        '';
      in
      ''
        machine.start()
        machine.wait_for_unit("qcfractal.service")
        machine.wait_for_open_port(7777)
        machine.wait_for_unit("qcfractalcompute.service")

        # Submit one singlepoint and remember the record id.
        record_id = machine.succeed(
            "python3 ${submitScript}"
        ).strip()
        print(f"submitted record {record_id}")

        # The worker has to claim the task, run Psi4 and post the result back.
        def record_complete(_):
            status, _output = machine.execute(
                f"python3 ${collectScript} {record_id}"
            )
            return status == 0

        with machine.nested("waiting for the calculation to complete"):
            retry(record_complete, timeout_seconds = 600)

        energy = float(
            machine.succeed(f"python3 ${collectScript} {record_id}").strip()
        )
        print(f"HF/STO-3G energy for H2: {energy} Eh")

        # Bracket the known reference (about -1.117 Eh) loosely enough to
        # tolerate convergence details, tightly enough that a wrong molecule,
        # method or unit would fail.
        assert -1.3 < energy < -0.9, f"energy out of range: {energy}"
      '';
  };
}
