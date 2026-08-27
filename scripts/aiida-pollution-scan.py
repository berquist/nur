#!/usr/bin/env python3
"""Find cross-test pollution hazards in aiida-core's test suite, statically.

    scripts/aiida-pollution-scan.py <aiida-core-source> [<archive-fixture-root>...]

Background: the suite runs under 128 xdist workers, and `--dist load` gives each
worker a sparse *subsequence* of the collection order.  A test that leaves state
behind therefore meets a later test that cannot tolerate it only when the two
happen to draw the same worker -- about a 1-in-128 event per pair.  Twelve such
bugs have been found in this repo, every one by losing that draw on an unrelated
run, and each was invisible until it fired.

Sampling harder does not help.  With c = the fraction of tests that reset the
profile at setup (12% here) and d = the collection distance between the two,

    P(collision) ~ (1/W) * (1 - c)^(d/W)

so lowering the worker count raises co-location but also hands the worker more
intervening tests, any one of which cleans up the evidence.  For a
cross-directory pair (d ~ 2000) that reads 8 -> ~0%, 128 -> 0.11%, 256 -> 0.14%.
128 is already near the optimum.  Enumerating the pairs beats drawing for them,
which is what this script is for; ../tests/aiida/ordering.nix then turns each
pair it finds into a build that passes or fails.

Three scans, because there are three ways the state gets there:

  literals   A test writes a literal into a UNIQUE column (db_dbuser.email,
             db_dbgroup.label, db_dbcomputer.label) and another test writes the
             same literal.  Reported when at least one of them does not ask for
             a cleaning fixture.  This is the shape behind all twelve so far.

  archives   The same columns, but read out of the .aiida fixture files rather
             than out of test source.  import_archive() re-creates every row the
             archive carries, so these enter a profile with nothing in tests/
             mentioning them -- `testing2` is the known case, and grepping the
             suite for it finds nothing.

  globals    Unguarded tests that assert over an *unfiltered* table query.
             These are the victims the archive rows actually claim: the failure
             is not a UniqueViolation but an assertion over a total that a
             stranger's row moved, e.g. assert {'family', 'testing2'} ==
             {'family'}.

             Four things are excluded because they look like whole-table scans
             and are not: a reset_storage() before the assertion, a query
             against an opened archive rather than the profile, an append
             constrained through a relationship (with_node=, with_group=, ...)
             rather than filters=, and a builder that is populated but never
             run -- the graph explorer takes one as a traversal template.
             Without those four the first run reported 24 candidates and every
             one was safe; with them it reports 2.

             Both survivors compare two counts *of the same table* against each
             other -- Node.collection.count() against `verdi devel run-sql`, and
             User.collection.count() against a QueryBuilder. A leftover row
             moves both sides equally, so they are immune by construction. They
             are left in the report rather than special-cased, because the shape
             that makes them safe is not one an AST check should be trusted to
             recognise.

Exit status is 0 whatever it finds: this reports hazards for a human to judge,
and several entries are legitimately safe for reasons no AST can see.
"""

from __future__ import annotations

import ast
import collections
import json
import pathlib
import sqlite3
import sys
import tempfile
import zipfile

# Columns with a UNIQUE constraint in the psql_dos schema, by the ORM
# constructor that writes them.  uq_db_dbuser_email and
# uq_db_dbgroup_label_type_string are the two that have actually fired.
UNIQUE = {
    "User": "email",
    "Group": "label",
    "Computer": "label",
    "UpfFamily": "label",
    "AutoGroup": "label",
}

CLEANERS = {"aiida_profile_clean", "aiida_profile_clean_class"}

ENTITIES = set(UNIQUE) | {"Node"}


def is_autouse_fixture(fn: ast.AST) -> bool:
    return any(
        "fixture" in ast.dump(d) and "autouse" in ast.dump(d) for d in fn.decorator_list
    )


def usefixtures_names(decorators) -> set[str]:
    """Fixture names named by a @pytest.mark.usefixtures(...) decorator."""
    names = set()
    for dec in decorators:
        if not isinstance(dec, ast.Call):
            continue
        func = dec.func
        if isinstance(func, ast.Attribute) and func.attr == "usefixtures":
            for arg in dec.args:
                if isinstance(arg, ast.Constant) and isinstance(arg.value, str):
                    names.add(arg.value)
    return names


def cleaning_fixtures(tree: ast.AST) -> set[str]:
    """Locally defined fixtures that reach a cleaner, transitively.

    A test is just as protected by a fixture that itself asks for
    `aiida_profile_clean_class` as by asking directly, and upstream does exactly
    that:

        @pytest.fixture(scope='class')
        def create_nodes_verdi_node_list(aiida_profile_clean_class): ...

        @pytest.mark.usefixtures('create_nodes_verdi_node_list')
        class TestNodeList: ...

    Not following that link reports TestNodeList as an unguarded whole-table
    scan, which it is not.  One indirection is enough for this suite, but the
    closure below is iterated to a fixed point rather than assuming so.
    """
    deps: dict[str, set[str]] = {}
    for node in ast.walk(tree):
        if not isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef)):
            continue
        if not any("fixture" in ast.dump(d) for d in node.decorator_list):
            continue
        deps[node.name] = {
            a.arg for a in node.args.args + node.args.kwonlyargs
        } | usefixtures_names(node.decorator_list)

    clean = set(CLEANERS)
    changed = True
    while changed:
        changed = False
        for name, requires in deps.items():
            if name not in clean and requires & clean:
                clean.add(name)
                changed = True
    return clean


def iter_tests(path: pathlib.Path):
    """Yield (node, guarded) for each test function, resolving the fixture.

    `guarded` means the test resets the profile at *setup*, by any of the five
    routes upstream actually uses: naming a cleaner in its signature, a
    usefixtures mark on the test or on its class, an autouse fixture on the
    class, a module-level pytestmark, or a local fixture that reaches a cleaner
    itself.  Missing any one of them turns a safe test into a false positive,
    which is how a report like this loses its readers -- the first run of this
    scan produced 24 candidates, of which every one was safe for a reason above.
    """
    try:
        tree = ast.parse(path.read_text())
    except SyntaxError:
        return
    text = path.read_text()
    module_guard = "aiida_profile_clean" in text.split("def test_")[0]
    clean = cleaning_fixtures(tree)

    def walk(body, class_guard):
        for node in body:
            if isinstance(node, ast.ClassDef):
                inner = any(
                    "aiida_profile_clean" in ast.dump(f)
                    for f in node.body
                    if isinstance(f, (ast.FunctionDef, ast.AsyncFunctionDef))
                    and is_autouse_fixture(f)
                )
                inner = inner or bool(usefixtures_names(node.decorator_list) & clean)
                yield from walk(node.body, class_guard or inner)
            elif isinstance(
                node, (ast.FunctionDef, ast.AsyncFunctionDef)
            ) and node.name.startswith("test_"):
                names = {a.arg for a in node.args.args + node.args.kwonlyargs}
                names |= usefixtures_names(node.decorator_list)
                guarded = module_guard or class_guard or bool(names & clean)
                yield node, guarded

    yield from walk(tree.body, False)


def literal_creations(node: ast.AST):
    for sub in ast.walk(node):
        if not isinstance(sub, ast.Call):
            continue
        func = sub.func
        name = func.attr if isinstance(func, ast.Attribute) else getattr(func, "id", None)
        if name not in UNIQUE:
            continue
        for kw in sub.keywords:
            if (
                kw.arg == UNIQUE[name]
                and isinstance(kw.value, ast.Constant)
                and isinstance(kw.value.value, str)
            ):
                yield name, kw.value.value


def scan_literals(root: pathlib.Path):
    index = collections.defaultdict(list)
    for path in sorted((root / "tests").rglob("test_*.py")):
        rel = path.relative_to(root)
        for node, guarded in iter_tests(path):
            for kind, value in literal_creations(node):
                index[(kind, value)].append((str(rel), node.name, node.lineno, guarded))

    shared = {
        key: uses
        for key, uses in index.items()
        if len({(p, n) for p, n, _, _ in uses}) > 1 and any(not g for *_, g in uses)
    }
    return shared


def archive_rows(roots):
    """UNIQUE-constrained values carried inside .aiida fixtures.

    Modern archives hold a db.sqlite3; the 0.x formats hold a data.json with an
    `export_data` map.  Both are read here, because the migration fixtures --
    which is where `testing2` lives -- are the old kind.
    """
    found = collections.defaultdict(set)
    for root in roots:
        for path in sorted(pathlib.Path(root).rglob("*.aiida")):
            try:
                zf = zipfile.ZipFile(path)
            except (zipfile.BadZipFile, OSError):
                continue
            names = set(zf.namelist())
            if "db.sqlite3" in names:
                with tempfile.NamedTemporaryFile(suffix=".sqlite3") as tmp:
                    tmp.write(zf.read("db.sqlite3"))
                    tmp.flush()
                    con = sqlite3.connect(tmp.name)
                    for table, col, kind in (
                        ("db_dbuser", "email", "User"),
                        ("db_dbgroup", "label", "Group"),
                        ("db_dbcomputer", "label", "Computer"),
                    ):
                        try:
                            for (value,) in con.execute(f"SELECT {col} FROM {table}"):
                                found[(kind, value)].add(path.name)
                        except sqlite3.Error:
                            pass
                    con.close()
            elif "data.json" in names:
                data = json.loads(zf.read("data.json"))
                for entity, rows in (data.get("export_data") or {}).items():
                    if entity not in UNIQUE:
                        continue
                    for row in rows.values():
                        value = row.get(UNIQUE[entity])
                        if value:
                            found[(entity, value)].add(path.name)
    return found


def _archive_builders(node: ast.AST) -> set[str]:
    """Names bound to an archive's querybuilder rather than the profile's.

    `archive.querybuilder()` queries the *file* just opened, so an unfiltered
    append against it says nothing about the profile and is never a pollution
    hazard.  Missing this was most of the first report's noise: three of the
    loudest candidates -- test_create_basic, test_write_read, test_querybuilder
    -- query an archive they wrote moments earlier.
    """
    names = set()
    for sub in ast.walk(node):
        if not isinstance(sub, ast.Assign):
            continue
        value = sub.value
        while isinstance(value, ast.Call) and isinstance(value.func, ast.Attribute):
            if value.func.attr == "querybuilder":
                for target in sub.targets:
                    if isinstance(target, ast.Name):
                        names.add(target.id)
                break
            value = value.func.value
    return names


# Terminals that actually run a QueryBuilder against the backend.  An append
# that never reaches one of these was not a query.
RUNNERS = {"all", "count", "first", "one", "iterall", "iterdict", "dict"}


def _executed_builders(node: ast.AST) -> set[str]:
    """Names bound to a QueryBuilder that is later run.

    AiiDA's graph explorer takes a *populated but unexecuted* builder and uses it
    as a traversal template, seeded from an explicit set of pks:

        queryb = orm.QueryBuilder()
        queryb.append(orm.Node, tag='nodes_in_set')
        queryb.append(orm.Node, with_incoming='nodes_in_set')
        UpdateRule(queryb, max_iterations=10).run(basket.copy())

    The first append has no constraint, but the rule starts from `basket` and
    follows links, so a stranger's rows are unreachable and cannot move the
    result.  Seven of tests/tools/graph/test_age.py's tests are this shape, and
    they were the bulk of the first report.
    """
    names = set()
    for sub in ast.walk(node):
        if (
            isinstance(sub, ast.Call)
            and isinstance(sub.func, ast.Attribute)
            and sub.func.attr in RUNNERS
        ):
            inner = sub.func.value
            while isinstance(inner, ast.Call) and isinstance(inner.func, ast.Attribute):
                inner = inner.func.value
            if isinstance(inner, ast.Name):
                names.add(inner.id)
    return names


def _is_executed(call: ast.AST, executed: set[str]) -> bool:
    """True if this append's builder is run somewhere in the test."""
    node = call
    while isinstance(node, ast.Call) and isinstance(node.func, ast.Attribute):
        if node.func.attr in RUNNERS:
            return True
        node = node.func.value
    if isinstance(node, ast.Name):
        return node.id in executed
    # A bare `QueryBuilder().append(...)` chain: executed only if a terminal sits
    # on the chain, which the walk above would already have found.
    return False


def _rooted_in_archive(call: ast.AST, archive_names: set[str]) -> bool:
    node = call
    while isinstance(node, ast.Call) and isinstance(node.func, ast.Attribute):
        if node.func.attr == "querybuilder":
            return True
        node = node.func.value
    return isinstance(node, ast.Name) and node.id in archive_names


def unfiltered_queries(node: ast.AST):
    """Entities queried with nothing narrowing them, i.e. over the whole table.

    `filters=` is not the only constraint that counts: `with_node=`,
    `with_group=`, `with_user=` and the rest scope an append through a
    relationship just as effectively, and a query pinned to one node's
    AutoGroups cannot be moved by a stranger's row.
    """
    archive_names = _archive_builders(node)
    executed = _executed_builders(node)
    for sub in ast.walk(node):
        if not isinstance(sub, ast.Call):
            continue
        func = sub.func
        if isinstance(func, ast.Attribute) and func.attr == "append":
            if _rooted_in_archive(sub, archive_names):
                continue
            if not _is_executed(sub, executed):
                continue
            entity = None
            for arg in sub.args:
                name = arg.attr if isinstance(arg, ast.Attribute) else getattr(arg, "id", None)
                if name in ENTITIES:
                    entity = name
            constrained = any(
                kw.arg == "filters" or (kw.arg or "").startswith("with_")
                for kw in sub.keywords
            )
            if entity and not constrained:
                yield entity
        elif (
            isinstance(func, ast.Attribute)
            and func.attr in {"all", "count"}
            and not sub.args
            and not sub.keywords
            and isinstance(func.value, ast.Attribute)
            and func.value.attr == "collection"
        ):
            owner = func.value.value
            name = owner.attr if isinstance(owner, ast.Attribute) else getattr(owner, "id", None)
            if name in ENTITIES:
                yield name


def resets_storage(node: ast.AST) -> bool:
    return any(
        isinstance(sub, ast.Call)
        and isinstance(sub.func, ast.Attribute)
        and sub.func.attr == "reset_storage"
        for sub in ast.walk(node)
    )


def scan_globals(root: pathlib.Path):
    out = []
    for path in sorted((root / "tests").rglob("test_*.py")):
        rel = path.relative_to(root)
        for node, guarded in iter_tests(path):
            if guarded or resets_storage(node):
                continue
            if not any(isinstance(s, ast.Assert) for s in ast.walk(node)):
                continue
            entities = sorted(set(unfiltered_queries(node)))
            if entities:
                out.append((str(rel), node.name, node.lineno, entities))
    return out


def main() -> int:
    if len(sys.argv) < 2:
        print(__doc__.strip().splitlines()[2], file=sys.stderr)
        return 2
    root = pathlib.Path(sys.argv[1])
    archive_roots = sys.argv[2:] or [root / "tests"]

    print("=" * 72)
    print("literals  shared UNIQUE literal, at least one writer unguarded")
    print("=" * 72)
    shared = scan_literals(root)
    if not shared:
        print("\n  none — every victim asks for a cleaning fixture\n")
    for (kind, value), uses in sorted(shared.items()):
        print(f"\n{kind}({value!r})")
        for path, name, lineno, guarded in sorted(set(uses)):
            print(f"    {'clean ' if guarded else 'OPEN  '} {path}:{lineno}  {name}")

    print()
    print("=" * 72)
    print("archives  UNIQUE values that import_archive() brings in from fixtures")
    print("=" * 72)
    found = archive_rows(archive_roots)
    print()
    for (kind, value), archives in sorted(found.items()):
        print(f"  {kind:<9} {value:<28} {len(archives):>3} archive(s)  e.g. {sorted(archives)[0]}")
    collide = sorted(set(found) & set(shared))
    print(
        f"\n  overlapping with a test-created literal: {len(collide)}"
        + (f" — {collide}" if collide else " (so no UniqueViolation from these)")
    )

    print()
    print("=" * 72)
    print("globals   unguarded tests asserting over an unfiltered table query")
    print("=" * 72)
    rows = scan_globals(root)
    print(f"\n  {len(rows)} candidate(s) — these are what the archive rows above claim\n")
    for path, name, lineno, entities in rows:
        print(f"    {path}:{lineno}  {name}   [{', '.join(entities)}]")
    return 0


if __name__ == "__main__":
    sys.exit(main())
