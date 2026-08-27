# Adversarial ordering checks for aiida-core's test suite.
#
#   nix-build tests/aiida/ordering.nix -A all --no-out-link
#   nix-build tests/aiida/ordering.nix -A archive-comments-user
#
# The suite's cross-test pollution bugs — a test that leaves a row behind, and a
# later test that creates the same row from a literal — are invisible under
# `just check`.  xdist's --dist load hands each test to whichever worker is free,
# so whether the two ever meet is a lottery, and with 128 workers it is roughly a
# one-in-128 draw per pair.  Six of them have been found here so far, every one
# by losing that draw on an unrelated run.
#
# This turns each known pair into a build that either passes or fails.  Each
# derivation runs one *polluter* and then its *victims*, in that order, with
# nothing in between to clean up after them.
#
# Green on its own proves nothing — it is equally consistent with the guards
# working and with the harness being unable to see the bug at all.  The `unguard`
# argument below is what tells the two apart, and every entry must be red under
# it:
#
#   nix-build tests/aiida/ordering.nix --arg unguard true -A group-agroup
#
# archive-comments-user has been confirmed this way: 2 failed, 1 passed, with
# `uq_db_dbuser_email … Key (email)=(commenting@user.s) already exists`.  Both of
# its victims failed, so both guards on that file are load-bearing.
#
# Serial is safe *here* and only here.  The note above `postPatch` in
# pkgs/aiida-core/default.nix records that `dontUsePytestXdist` over the whole
# suite hangs — tests/engine/test_launch.py sits until pytest-timeout's 240s
# fires and takes the session down.  None of the node ids below is in that
# module, so a handful of tests with no workers is exactly the case that does
# work, and it is what makes the ordering deterministic rather than sampled.
#
# For finding *unknown* pairs, do not bother turning the worker count down.  The
# obvious argument — two tests land together with probability about 1/W, so fewer
# workers means more collisions — is wrong, because it ignores the other half:
# a worker holding both also holds the tests *between* them, and 12% of this
# suite (318 of 2753) resets the profile at setup.  Any one of those wipes the
# leftover row before the victim reaches it.  With d the collection distance
# between polluter and victim,
#
#     P(collision) ~ (1/W) * 0.88^(d/W)
#
# which for a cross-directory pair (d ~ 2000, e.g. tests/cmdline/... into
# tests/test_nodes.py) reads:
#
#     W:      8      32     64     128    256    512
#     P:   ~0%   0.001%  0.029%  0.106% 0.144% 0.119%
#
# So 128 is already near the optimum, 256 buys a third more at twice the
# clusters, and 8 detects nothing at all.  Turning it down does not make the
# suite more adversarial — it gives the pollution time to be cleaned up.
#
# The worker count is still a build flag rather than a derivation edit, since
# nixpkgs' pytest-xdist hook appends `--numprocesses=$NIX_BUILD_CORES` and that
# is not part of the derivation hash — `nix build --rebuild --cores 256 ...`.
# It is just not a lever worth pulling.  Repeat runs at 128 are the honest way
# to buy more tickets, and this file is the way to stop buying tickets at all.

# pkgs must arrive with the aiida overlay already applied, for the same reason
# as ./vm.nix: what is under test is *this repo's* aiida-core, and a plain
# <nixpkgs> has no such attribute.  Taking a real nixpkgs and extending it here,
# rather than importing ../.., is what keeps `linkFarm` and the rest of the
# builders in reach — the NUR entry point exports packages, not a package set.
{
  pkgs ? import <nixpkgs> {
    overlays = [ (import ../../overlays).aiida ];
  },

  # The negative control.  With this set, each check has its victim's guard
  # *undone* again after ../../pkgs/aiida-core/default.nix's postPatch has
  # applied it, and the build is then expected to FAIL.  A check that stays
  # green under `--arg unguard true` is not reproducing the bug it claims to,
  # which is the one way a harness like this can be quietly worthless.
  #
  #   nix-build tests/aiida/ordering.nix --arg unguard true -A group-agroup
  #
  # It lives here rather than in a hand-edit of the package because a hand-edit
  # leaves the tree unguarded until someone remembers to put it back — which is
  # exactly what happened the first time this control was run.
  unguard ? false,
}:

let
  inherit (pkgs) lib;

  aiida-core = pkgs.python313Packages.aiida-core;

  # Shared by the two pairs whose victim is the same test.
  #
  # This is the one guard whose inverse is not a lone signature line.  The patch
  # in ../../pkgs/aiida-core/default.nix *renames* the fixture, so undoing it has
  # to put the mid-test `reset_storage()` call back too — and
  # `aiida_profile_clean.reset_storage()` appears four times in that file, three
  # of them belonging to tests that always spelled it that way.  The preceding
  # `create_archive` line pins the substitution to the one occurrence that came
  # from the patch; it occurs exactly once in the file.
  usersGuard = {
    file = "tests/tools/archive/orm/test_users.py";
    undo = [
      {
        patched = "def test_nodes_belonging_to_different_users(aiida_profile_clean, tmp_path, aiida_localhost):";
        original = "def test_nodes_belonging_to_different_users(aiida_profile, tmp_path, aiida_localhost):";
      }
      # Written with an explicit \n rather than as an indented '' string: ''
      # strips the common leading whitespace, which would leave the first of
      # these two lines flush and the second indented, matching nothing.
      {
        patched = "    create_archive([sd3], filename=filename)\n    aiida_profile_clean.reset_storage()";
        original = "    create_archive([sd3], filename=filename)\n    aiida_profile.reset_storage()";
      }
    ];
  };

  # Each entry names the test that leaves state behind, then the tests that
  # would collide with it.  `polluter` runs first because that is the order
  # pytest takes node ids in, and because --dist load preserves collection order
  # within a worker: a worker sees a *subsequence* of the collection, never a
  # reordering.  So reproducing a pair means running it in collection order with
  # the intervening tests removed, which is precisely what this does.
  pairs = {
    # uq_db_dbuser_email.  test_comment_querybuilder cleans at setup and ends
    # with the user still stored; both victims took bare `aiida_profile`.
    archive-comments-user = {
      polluter = "tests/orm/test_comments.py::test_comment_querybuilder";
      victims = [
        "tests/tools/archive/orm/test_comments.py::test_exclude_comments_flag"
        "tests/tools/archive/orm/test_comments.py::test_multiple_user_comments_single_node"
      ];
      guard = {
        file = "tests/tools/archive/orm/test_comments.py";
        undo = [
          {
            patched = "def test_exclude_comments_flag(aiida_profile_clean, tmp_path, aiida_profile):";
            original = "def test_exclude_comments_flag(tmp_path, aiida_profile):";
          }
          {
            patched = "def test_multiple_user_comments_single_node(aiida_profile_clean, tmp_path, aiida_profile):";
            original = "def test_multiple_user_comments_single_node(tmp_path, aiida_profile):";
          }
        ];
      };
    };

    # uq_db_dbuser_email again, and the one that was actually caught in the
    # wild: both siblings re-create `newuser@new.n` through import_archive
    # after their mid-test reset_storage().
    archive-users-user = {
      polluter = "tests/tools/archive/orm/test_users.py::test_non_default_user_nodes";
      victims = [ "tests/tools/archive/orm/test_users.py::test_nodes_belonging_to_different_users" ];
      guard = usersGuard;
    };

    archive-groups-user = {
      polluter = "tests/tools/archive/orm/test_groups.py::test_group_import_existing";
      victims = [ "tests/tools/archive/orm/test_users.py::test_nodes_belonging_to_different_users" ];
      guard = usersGuard;
    };

    # uq_db_dbgroup_label_type_string.  test_group.py's own autouse `groups`
    # fixture deletes every group at setup, so the polluters below are safe
    # coming in and dirty going out.
    group-agroup = {
      polluter = "tests/cmdline/commands/test_group.py::TestVerdiGroup::test_list_order";
      victims = [ "tests/test_nodes.py::TestNodeDeletion::test_delete_group_nodes" ];
      guard = {
        file = "tests/test_nodes.py";
        undo = [
          {
            patched = "    def test_delete_group_nodes(self, aiida_profile_clean):";
            original = "    def test_delete_group_nodes(self):";
          }
        ];
      };
    };

    group-test-args-group = {
      polluter = "tests/cmdline/commands/test_group.py::TestVerdiGroup::test_dump_calls_group_dump_with_correct_args";
      victims = [
        "tests/cmdline/commands/test_profile.py::TestVerdiProfileDumpCLI::test_dump_cli_to_api_mapping"
      ];
      guard = {
        file = "tests/cmdline/commands/test_profile.py";
        undo = [
          {
            patched = "    def test_dump_cli_to_api_mapping(self, mock_dump, aiida_profile_clean, run_cli_command, tmp_path):";
            original = "    def test_dump_cli_to_api_mapping(self, mock_dump, run_cli_command, tmp_path):";
          }
        ];
      };
    };

    group-test-metadata-group = {
      polluter = "tests/cmdline/commands/test_group.py::TestVerdiGroup::test_dump_metadata_inclusion_options";
      victims = [ "tests/orm/test_groups.py::TestGroups::test_dump_attributes_and_extras" ];
      guard = {
        file = "tests/orm/test_groups.py";
        undo = [
          {
            patched = "    def test_dump_attributes_and_extras(self, aiida_profile_clean, tmp_path):";
            original = "    def test_dump_attributes_and_extras(self, tmp_path):";
          }
        ];
      };
    };

    # Ordering-safe in the source rather than correct: the unguarded test is the
    # earlier of the two, so it wins as long as nothing reorders them.  Stated
    # backwards here on purpose, to check the guard rather than the ordering.
    group-test-dump-group = {
      polluter = "tests/orm/test_groups.py::TestGroups::test_dump_basic";
      victims = [ "tests/orm/test_groups.py::TestGroups::test_dump_dry_run" ];
      guard = {
        file = "tests/orm/test_groups.py";
        undo = [
          {
            patched = "    def test_dump_dry_run(self, aiida_profile_clean, tmp_path):";
            original = "    def test_dump_dry_run(self, tmp_path):";
          }
        ];
      };
    };
  };

  check =
    name:
    {
      polluter,
      victims,
      guard,
    }:
    aiida-core.overridePythonAttrs (old: {
      pname = "aiida-core-ordering-${name}" + lib.optionalString unguard "-unguarded";

      # Appended *after* the package's own postPatch, so the guard is applied
      # and then taken away again — rather than removed from the patch, which
      # would silently no-op if the patch text there ever changed.  --replace-fail
      # is what makes that a build error instead.
      postPatch =
        old.postPatch
        + lib.optionalString unguard ''

          substituteInPlace ${guard.file} \
            ${lib.concatMapStringsSep " \\\n  " (
              u: "--replace-fail ${lib.escapeShellArg u.patched} ${lib.escapeShellArg u.original}"
            ) guard.undo}
        '';

      # No workers, so the node ids run in the order given.  --benchmark-skip
      # has to survive this: pytest-benchmark disables itself under xdist and
      # not otherwise, and tests/benchmark would start timing things in a build
      # sandbox.  See the note on that flag in pkgs/aiida-core/default.nix.
      dontUsePytestXdist = true;

      # Replaces the suite's flags rather than adding to them.  The deselect and
      # -k machinery there exists to carve down a whole-suite run and has
      # nothing to carve here; keeping `disabledTests` would also matter, since
      # pytestCheckHook turns it into a -k that would then be the *only* -k.
      pytestFlags = [
        "--override-ini=addopts="
        "--benchmark-skip"
        "--db-backend"
        "psql"
        "--broker-backend"
        "zmq"
      ]
      ++ [ polluter ]
      ++ victims;

      disabledTests = [ ];
      disabledTestPaths = [ ];

      meta = old.meta // {
        description = "Adversarial ordering check: ${name}";
      };
    });

  checks = lib.mapAttrs check pairs;
in
checks
// {
  all = pkgs.linkFarm "aiida-core-ordering-all" (
    lib.mapAttrsToList (name: drv: {
      inherit name;
      path = drv;
    }) checks
  );
}
