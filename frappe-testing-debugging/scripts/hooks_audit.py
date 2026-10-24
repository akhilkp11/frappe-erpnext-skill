#!/usr/bin/env python3
"""Static audit of hooks.py across all apps in a bench (no imports executed, read-only).

Usage: hooks_audit.py [bench_path]
Reports:
  - doc_events registered by several apps for the same DocType/event
  - override_doctype_class / extend_doctype_class / override_whitelisted_methods collisions
  - wildcard ("*") doc_events handlers (performance risk)
  - scheduler_events summary
"""
import ast
import sys
from collections import defaultdict
from pathlib import Path

WATCHED = ("doc_events", "override_doctype_class", "extend_doctype_class",
           "override_whitelisted_methods", "scheduler_events", "permission_query_conditions",
           "has_permission")


def find_hooks_files(bench: Path):
    for app_dir in sorted((bench / "apps").iterdir()):
        if not app_dir.is_dir():
            continue
        candidate = app_dir / app_dir.name / "hooks.py"
        if candidate.exists():
            yield app_dir.name, candidate


def literal(node):
    try:
        return ast.literal_eval(node)
    except Exception:
        return None


def read_hooks(path: Path):
    """Return {hook_name: value} for simple literal assignments."""
    result = {}
    tree = ast.parse(path.read_text(encoding="utf-8"), filename=str(path))
    for node in tree.body:
        targets = []
        if isinstance(node, ast.Assign):
            targets = [t.id for t in node.targets if isinstance(t, ast.Name)]
        elif isinstance(node, ast.AnnAssign) and isinstance(node.target, ast.Name):
            targets = [node.target.id]
        for name in targets:
            if name in WATCHED:
                value = literal(node.value)
                result[name] = value if value is not None else "<non-literal>"
    return result


def as_list(v):
    if v is None:
        return []
    return list(v) if isinstance(v, (list, tuple)) else [v]


def main():
    bench = Path(sys.argv[1] if len(sys.argv) > 1 else ".").resolve()
    if not (bench / "apps").is_dir():
        print(f"Not a bench: {bench} (no apps/ directory)")
        return 2

    doc_events = defaultdict(list)           # (doctype, event) -> [(app, handler)]
    overrides = defaultdict(list)            # (hook, target)   -> [(app, handler)]
    wildcards = []
    non_literal = []
    sched = {}

    for app, path in find_hooks_files(bench):
        try:
            hooks = read_hooks(path)
        except SyntaxError as e:
            print(f"!! {app}: cannot parse hooks.py ({e})")
            continue
        for name, value in hooks.items():
            if value == "<non-literal>":
                non_literal.append((app, name))
                continue
            if name == "doc_events" and isinstance(value, dict):
                for doctype, events in value.items():
                    if not isinstance(events, dict):
                        continue
                    for event, handlers in events.items():
                        for h in as_list(handlers):
                            doc_events[(doctype, event)].append((app, h))
                            if doctype == "*":
                                wildcards.append((app, event, h))
            elif name in ("override_doctype_class", "override_whitelisted_methods") and isinstance(value, dict):
                for target, handler in value.items():
                    overrides[(name, target)].append((app, handler))
            elif name == "extend_doctype_class" and isinstance(value, dict):
                for target, handlers in value.items():
                    for h in as_list(handlers):
                        overrides[(name, target)].append((app, h))
            elif name == "scheduler_events":
                sched[app] = value

    print(f"Bench: {bench}\n")

    print("== doc_events handled by more than one app (order = app install order; all run)")
    found = False
    for (doctype, event), items in sorted(doc_events.items()):
        if len({a for a, _ in items}) > 1:
            found = True
            print(f"  {doctype} :: {event}")
            for app, h in items:
                print(f"      [{app}] {h}")
    if not found:
        print("  none")

    print("\n== Overrides: only ONE override_doctype_class / override_whitelisted_methods wins per target")
    found = False
    for (hook, target), items in sorted(overrides.items()):
        multi = len(items) > 1
        if multi and hook != "extend_doctype_class":
            found = True
            print(f"  CONFLICT {hook}: {target}")
            for app, h in items:
                print(f"      [{app}] {h}")
        elif multi:
            found = True
            print(f"  note {hook} stacks for {target}: " + ", ".join(f"[{a}] {h}" for a, h in items))
    if not found:
        print("  none")

    print("\n== Targets that mix override_doctype_class with extend_doctype_class")
    mixed = False
    ov = {t for (h, t) in overrides if h == "override_doctype_class"}
    ex = {t for (h, t) in overrides if h == "extend_doctype_class"}
    for t in sorted(ov & ex):
        mixed = True
        print(f"  {t}: verify resolution order in the installed Frappe version")
    if not mixed:
        print("  none")

    print("\n== Wildcard doc_events (run for every DocType; keep cheap)")
    if wildcards:
        for app, event, h in wildcards:
            print(f"  [{app}] {event} -> {h}")
    else:
        print("  none")

    if non_literal:
        print("\n== Hooks built dynamically (not analyzable statically)")
        for app, name in non_literal:
            print(f"  [{app}] {name}")

    print("\n== scheduler_events keys per app")
    for app, value in sched.items():
        if isinstance(value, dict):
            print(f"  [{app}] " + ", ".join(sorted(value)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
