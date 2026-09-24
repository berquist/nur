"""Run FireWorks' suite under the 'fork' start method, as it did before 3.14.

Copied to the source root by the derivation's `preCheck`; upstream ships no
conftest.py at all.

Python 3.14 changed the default multiprocessing start method on Linux from
`fork` to `forkserver` (gh-84559), and that breaks `test_tracker_mlaunch` here
in a way that reports nothing at all: `launch_multiprocess` returns cleanly,
logs nothing, raises nothing, and runs no rockets, leaving

    AssertionError: assert '' == '48\\n49'

as the only symptom.

The cause is this repository's mongomock stand-in meeting upstream's launcher,
and neither half is wrong on its own.  `DataServer.setup()` pickles a
`_LaunchPadCallable` into the manager's server process -- deliberately, and
upstream's own comment says it is "for spawn-based multiprocessing
compatibility".  That is correct against a real MongoDB, where the
reconstructed LaunchPad reconnects to the same server and sees the same data.
It is not correct against mongomock, whose "server" is process-local memory: a
LaunchPad pickles to 274 bytes of connection parameters, so the rebuilt one
opens an *empty* database.  Measured on 3.14, with a workflow already added:

    parent                                  fw_ids == [1]
    MONGOMOCK_SERVERSTORE_FILE on disk      {}
    rebuilt from pickle (forkserver/spawn)  fw_ids == []
    forked child                            fw_ids == [1]

The serverstore file is the only cross-process channel mongomock has, and the
derivation's note above `preCheck` says when it is written: a client reads it
when built and rewrites it when finalised.  The parent's client is still live
while the launcher runs, so the file is still `{}` and the child sees nothing.
Under fork none of this arose -- the server process inherited live memory and
never unpickled anything.

The rapidfire children then ask an empty LaunchPad for fireworks, get none, and
exit cleanly.  Nothing raises: `launch_multiprocess` ends in
`for p in processes: p.join()`, and a child that finds no work -- or dies -- is
not an exception in the parent.

So restore the start method the suite was written against, for the whole
session rather than for one test: every FireWorks test that crosses a process
boundary shares the constraint, because they all share the mock database.  This
is a property of building without a real MongoDB, not of FireWorks, which is
why it belongs here and not in a patch to upstream's code.  A real server is
not an option -- every mongodb-ce in the locked nixpkgs is SSPL and so
`meta.license.free = false`, which `ci.nix` filters on.

`force=True` because pytest may already have touched the default context, and
the platform guard because fork is neither available nor safe everywhere:
macOS moved off it as a default in 3.8 for the same reason 3.14 moved Linux off
it now, that running arbitrary code after fork() in a threaded process is
unsafe.  This suite does run threads -- `ping_launch` is one -- so this is
knowingly buying back the old hazard in exchange for the old behaviour.  It is
what every green FireWorks build before 3.14 was doing.
"""

import multiprocessing
import sys

if sys.platform == "linux" and "fork" in multiprocessing.get_all_start_methods():
    multiprocessing.set_start_method("fork", force=True)
