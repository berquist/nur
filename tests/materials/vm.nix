# tests/materials/vm.nix
#
# VM-based integration tests for the materials overlay.  These exist for one
# reason: **a test that needs a live database server belongs in a VM, not in a
# package's check phase.**  A check phase can only skip such a test, and a
# skipped test looks exactly like a passing one in a build log.
#
#   nix build .#checks.x86_64-linux.vm-materials-ase-db-backends
#   just vm-test materials-ase-db-backends
#   $(nix-build tests/materials/vm.nix -A ase-db-backends.driver)/bin/nixos-test-driver
#
# pkgs must arrive with the materials overlay already applied, for the reason
# spelled out at the top of ../qcarchive/vm.nix: testers.nixosTest uses the pkgs
# argument directly as the package set for VM nodes, so nixpkgs.overlays inside
# a node module comes too late.  From the command line that takes
#
#   nix-build tests/materials/vm.nix -A ase-db-backends \
#     --arg pkgs 'import <nixpkgs> { overlays = [ (import ./overlays).materials ]; }'
{
  pkgs ? import <nixpkgs> {
    overlays = [ (import ../../overlays).materials ];
  },
}:

let
  inherit (pkgs) lib;

  minimalVM = {
    boot.loader.grub.enable = false;
    virtualisation.diskSize = lib.mkDefault 4096; # MiB
    virtualisation.memorySize = lib.mkDefault 2048; # MiB
  };

  # pytest and the package under test in one interpreter.  ase-db-backends
  # propagates ase, psycopg2 and pymysql, so the PostgreSQL and MySQL drivers
  # come along without being named — and so does ase's `bin/ase`, which
  # `test_db` shells out to.  See the `nativeCheckInputs` note in
  # ../../pkgs/ase-db-backends: that test runs a nine-stage `ase` pipeline under
  # `shell=True` and never checks the return code, so an absent CLI shows up
  # only as a much later `KeyError: 'no match'`.
  pythonEnv = pkgs.python313.withPackages (ps: [
    ps.ase-db-backends
    ps.pytest
  ]);

  pgUrl = "postgresql://ase:ase@127.0.0.1:5432/testase";
  mysqlUrl = "mysql://ase:ase@127.0.0.1:3306/testase_mysql";

  # The conftest reads exactly these two variables, and falls back to
  # `pytest.skip` when they are unset — which is what makes the whole of this
  # suite invisible during an ordinary build.
  testEnv = "ASE_TEST_POSTGRES_URL=${pgUrl} MYSQL_DB_URL=${mysqlUrl}";
in
{
  ase-db-backends = pkgs.testers.nixosTest {
    name = "materials-ase-db-backends";

    nodes.machine = {
      imports = [ minimalVM ];

      # Password authentication over TCP, because that is the shape of URL the
      # test suite builds.  The default NixOS `authentication` block trusts
      # local socket connections only, so `host` lines have to be added; the
      # `local all all trust` line is kept so `sudo -u postgres psql` still
      # works from the test script.
      services.postgresql = {
        enable = true;
        enableTCPIP = true;
        authentication = lib.mkForce ''
          local all all trust
          host  all all 127.0.0.1/32 scram-sha-256
          host  all all ::1/128      scram-sha-256
        '';
        # `ensureUsers` cannot set a password, so the role and its database are
        # created here instead.  initialScript runs once, on the first start of
        # a fresh data directory, which is every boot of a VM test.
        initialScript = pkgs.writeText "ase-db-backends-postgres-init.sql" ''
          CREATE ROLE ase LOGIN PASSWORD 'ase';
          CREATE DATABASE testase OWNER ase;
        '';
      };

      # MariaDB rather than MySQL proper, and it answers for both `mysql` and
      # `mariadb` in the suite's parameterisation — the conftest reads one
      # `MYSQL_DB_URL` for the two of them, so they exercise the same server
      # through the same pymysql driver.
      services.mysql = {
        enable = true;
        package = pkgs.mariadb;
        # Two grants for one user: MariaDB matches `localhost` as its own host
        # value rather than folding it into `%`, and a TCP connection to
        # 127.0.0.1 resolves to `localhost` here.
        initialScript = pkgs.writeText "ase-db-backends-mysql-init.sql" ''
          CREATE DATABASE IF NOT EXISTS testase_mysql;
          CREATE USER 'ase'@'localhost' IDENTIFIED BY 'ase';
          CREATE USER 'ase'@'%' IDENTIFIED BY 'ase';
          GRANT ALL PRIVILEGES ON testase_mysql.* TO 'ase'@'localhost';
          GRANT ALL PRIVILEGES ON testase_mysql.* TO 'ase'@'%';
          FLUSH PRIVILEGES;
        '';
      };

      environment.systemPackages = [ pythonEnv ];
    };

    testScript = ''
      machine.start()
      machine.wait_for_unit("multi-user.target")

      machine.wait_for_unit("postgresql.service")
      machine.wait_for_unit("mysql.service")
      machine.wait_for_open_port(5432)
      machine.wait_for_open_port(3306)

      # Prove the credentials before pytest does, so that a broken grant reads
      # as a broken grant rather than as thirty skipped tests.
      machine.succeed(
          "PGPASSWORD=ase psql -h 127.0.0.1 -U ase -d testase -c 'SELECT 1'"
      )
      machine.succeed(
          "mysql -h 127.0.0.1 -u ase -pase testase_mysql -e 'SELECT 1'"
      )

      # A writable working directory: `test_db` drives the `ase` CLI, which
      # writes its intermediate files relative to the current directory.
      machine.succeed("mkdir -p /tmp/adb")

      # The parameterised modules, restricted to the three server-backed
      # parameters.  `aselmdb` and `json` are left to the package's own check
      # phase -- and `test_db2[aselmdb]` and `test_aselmdb_concurrency` are
      # deselected there for reasons that do not apply to a real server: both
      # open one LMDB path twice in a process, which py-lmdb refuses and
      # PostgreSQL and MySQL do not care about.  So `test_db2` runs here.
      result = machine.succeed(
          "cd /tmp/adb && ${testEnv} ${pythonEnv}/bin/pytest -v -p no:cacheprovider "
          "--pyargs ase_db_backends.tests.test_db "
          "ase_db_backends.tests.test_db2 "
          "ase_db_backends.tests.test_sql_db_ext_tables "
          "-k 'postgresql or mysql or mariadb' 2>&1"
      )
      print(result)
      # The point of the whole test: these must *run*, not skip.  A skip here
      # means a URL never reached the conftest, which is precisely the failure
      # an ordinary build cannot tell from success.
      summary = result.strip().splitlines()[-1]
      assert "skipped" not in summary, (
          f"a server-backed test skipped, so a URL did not reach it: {summary}"
      )
      assert "passed" in summary, f"nothing passed: {summary}"

      # test_mysql.py is not parameterised -- it takes a `db` fixture built
      # straight from MYSQL_DB_URL -- so it runs as a whole module.
      result = machine.succeed(
          "cd /tmp/adb && ${testEnv} ${pythonEnv}/bin/pytest -v -p no:cacheprovider "
          "--pyargs ase_db_backends.tests.test_mysql 2>&1"
      )
      print(result)
    '';
  };
}
