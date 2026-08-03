# tests/vm.nix
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
#   nix-build tests/vm.nix \
#     --arg pkgs 'import <nixpkgs> { overlays = [ (import ../overlays).qcfractal ]; }'
#
# Or from the flake:
#   nix build .#checks.x86_64-linux.vm-server-local-db
#
# Run options
# -----------
# Run a specific test:
#   nix-build tests/vm.nix -A server-local-db
#
# All tests via the flake:
#   nix build .#checks.x86_64-linux.vm-server-local-db
#
# Interactive debugging:
#   $(nix-build tests/vm.nix -A server-local-db.driver)/bin/nixos-test-driver

# pkgs must already have the qcfractal overlay applied, because
# testers.nixosTest uses the pkgs argument directly as the package set for
# VM nodes — nixpkgs.overlays inside a node module is evaluated too late to
# affect the pkgs instance the test framework has already constructed.
#
# From the command line:
#   nix-build tests/vm.nix \
#     --arg pkgs 'import <nixpkgs> { overlays = [ (import ./overlays).qcfractal ]; }'
#
# From the flake, pkgs' is already overlaid before being passed here.
{
  pkgs ? import <nixpkgs> {
    overlays = [ (import ../overlays).qcfractal ];
  },
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
  serverModule = ../nixos-modules/qcfractal-server.nix;
  computeModule = ../nixos-modules/qcfractal-compute.nix;

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
          # Defaults: createLocally = true, peer auth via Unix socket.
        };
      };

    testScript = ''
      machine.start()
      machine.wait_for_unit("multi-user.target")

      # Schema initialisation must complete before the server starts.
      machine.wait_for_unit("qcfractal-init-db.service")
      machine.wait_for_unit("qcfractal.service")

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
      assert "server_name" in info, f"unexpected response: {info}"
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
  # Test 4: compute worker connects to the server.
  #
  # Verifies that qcfractalcompute starts and successfully registers itself
  # with the QCFractal server.  No QC programs are installed; we just check
  # that the worker comes up and the server acknowledges it.
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

      print(machine.succeed(query_managers))
    '';
  };
}
