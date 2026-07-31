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
# To interactively debug a failing test, set the QEMU_OPTS / nixos-test
# driver into interactive mode:
#   $(nix-build tests/vm.nix -A server-local-db.driver)/bin/nixos-test-driver

{
  pkgs ? import <nixpkgs> { },
}:

let
  inherit (pkgs) lib;

  # Common module included in every test VM: cuts boot time significantly.
  minimalVM = {
    # No bootloader needed in a VM test.
    boot.loader.grub.enable = false;
    # Smaller disk image.
    virtualisation.diskSize = 1024; # MiB
    virtualisation.memorySize = 512; # MiB
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
  server-local-db = pkgs.nixosTest {
    name = "qcfractal-server-local-db";

    nodes.machine =
      { config, pkgs, ... }:
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

      # The API must respond on port 7777.
      # /api/v1/information is an unauthenticated endpoint that returns
      # server metadata as JSON.
      machine.wait_for_open_port(7777)
      response = machine.succeed("curl -sf http://localhost:7777/api/v1/information")
      import json
      info = json.loads(response)
      assert "server_name" in info, f"unexpected response: {info}"
      print(f"Server info: {info}")
    '';
  };

  # ==========================================================================
  # Test 2: server with openFirewall = true.
  #
  # Verifies that the firewall rule is applied and the port is reachable from
  # a second VM acting as a remote client.
  # ==========================================================================
  server-open-firewall = pkgs.nixosTest {
    name = "qcfractal-server-open-firewall";

    nodes = {
      server =
        { config, pkgs, ... }:
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
      client.wait_for_unit("network.target")
      client.succeed(
          "curl -sf http://server:7777/api/v1/information"
      )
    '';
  };

  # ==========================================================================
  # Test 3: server with a remote PostgreSQL instance.
  #
  # Verifies that createLocally = false works: the server connects to
  # PostgreSQL over TCP rather than via the Unix socket.
  # ==========================================================================
  server-remote-db = pkgs.nixosTest {
    name = "qcfractal-server-remote-db";

    nodes = {
      db =
        { config, pkgs, ... }:
        {
          imports = [ minimalVM ];
          services.postgresql = {
            enable = true;
            enableTCPIP = true;
            authentication = lib.mkForce ''
              local all all              trust
              host  all all 0.0.0.0/0   trust
            '';
            initialScript = pkgs.writeText "qcfractal-db-init.sql" ''
              CREATE USER qcfractal;
              CREATE DATABASE qcfractal OWNER qcfractal;
            '';
          };
          networking.firewall.allowedTCPPorts = [ 5432 ];
        };

      server =
        { config, pkgs, ... }:
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

    testScript = ''
      db.start()
      server.start()

      db.wait_for_unit("postgresql.service")
      # Give the server time to connect and initialise the schema.
      server.wait_for_unit("qcfractal-init-db.service")
      server.wait_for_unit("qcfractal.service")
      server.wait_for_open_port(7777)
      server.succeed("curl -sf http://localhost:7777/api/v1/information")
    '';
  };

  # ==========================================================================
  # Test 4: compute worker connects to the server.
  #
  # Verifies that qcfractalcompute starts and successfully registers itself
  # with the QCFractal server.  No QC programs are installed; we just check
  # that the worker comes up and the server acknowledges it.
  # ==========================================================================
  compute-connects = pkgs.nixosTest {
    name = "qcfractal-compute-connects";

    nodes.machine =
      { config, pkgs, ... }:
      {
        imports = [
          minimalVM
          serverModule
          computeModule
        ];

        # Give the VM a bit more memory: running both services simultaneously.
        virtualisation.memorySize = 768;

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
        };
      };

    testScript = ''
      machine.start()
      machine.wait_for_unit("qcfractal.service")
      machine.wait_for_open_port(7777)
      machine.wait_for_unit("qcfractalcompute.service")

      # Give the manager a moment to register with the server.
      machine.sleep(5)

      # The server's managers endpoint should list our worker.
      response = machine.succeed(
          "curl -sf http://localhost:7777/api/v1/managers"
      )
      import json
      managers = json.loads(response)
      assert len(managers) > 0, f"no managers registered: {managers}"
      print(f"Registered managers: {managers}")
    '';
  };
}
