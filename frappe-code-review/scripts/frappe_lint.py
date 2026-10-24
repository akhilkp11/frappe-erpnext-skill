#!/usr/bin/env python3
"""Lightweight static lint for Frappe/ERPNext custom apps.

Usage: frappe_lint.py PATH [--json] [--include-tests]
Exit code 1 when any ERROR finding exists.
Findings are leads to verify, not proofs.
"""
import argparse
import ast
import json
import re
import sys
from pathlib import Path

SKIP_DIRS = {"node_modules", ".git", "__pycache__", "dist", "build", "env", ".venv", "venv", "locale"}
LEDGER_TABLES = re.compile(r"`?tab(GL Entry|Stock Ledger Entry|Payment Ledger Entry)`?", re.I)
WRITE_SQL = re.compile(r"^\s*(update|delete)\b", re.I)
PERM_CALLS = {"has_permission", "check_permission", "only_for", "get_roles", "get_list",
              "validate_permission", "has_website_permission", "throw_permission_error"}
LOOP_CALLS = {"get_doc", "get_cached_doc", "get_all", "get_list", "get_value"}


class Finding(dict):
    pass


def attr_chain(node):
    """frappe.db.sql -> 'frappe.db.sql'"""
    parts = []
    while isinstance(node, ast.Attribute):
        parts.append(node.attr)
        node = node.value
    if isinstance(node, ast.Name):
        parts.append(node.id)
    return ".".join(reversed(parts))


def is_dynamic_string(node):
    if isinstance(node, ast.JoinedStr):
        return any(isinstance(v, ast.FormattedValue) for v in node.values)
    if isinstance(node, ast.BinOp) and isinstance(node.op, (ast.Mod, ast.Add)):
        # "..." % x  or "..." + x   (only flag when a string constant is involved)
        def has_str(n):
            return (isinstance(n, ast.Constant) and isinstance(n.value, str)) or \
                   (isinstance(n, ast.BinOp) and (has_str(n.left) or has_str(n.right)))
        return has_str(node.left) or has_str(node.right)
    if isinstance(node, ast.Call) and isinstance(node.func, ast.Attribute) and node.func.attr == "format":
        return True
    return False


def const_text(node):
    if isinstance(node, ast.Constant) and isinstance(node.value, str):
        return node.value
    if isinstance(node, ast.JoinedStr):
        return "".join(v.value for v in node.values if isinstance(v, ast.Constant) and isinstance(v.value, str))
    if isinstance(node, ast.BinOp):
        return (const_text(node.left) or "") + (const_text(node.right) or "")
    return None


class PyVisitor(ast.NodeVisitor):
    def __init__(self, path, rel, add):
        self.path, self.rel, self.add = path, rel, add
        self.loop_depth = 0
        self.func_stack = []
        self.is_patch = "/patches/" in rel or rel.endswith("patches.py")
        self.is_test = Path(rel).name.startswith("test_") or "/tests/" in rel

    # ---- helpers
    def emit(self, node, code, sev, msg):
        self.add(Finding(file=self.rel, line=getattr(node, "lineno", 0), code=code, severity=sev, message=msg))

    def decorators(self, fn):
        out = []
        for d in fn.decorator_list:
            target = d.func if isinstance(d, ast.Call) else d
            out.append((attr_chain(target), d))
        return out

    # ---- visits
    def visit_ImportFrom(self, node):
        if node.module and node.module.startswith("frappe.tests") and any(a.name == "FrappeTestCase" for a in node.names):
            self.emit(node, "F010", "INFO", "FrappeTestCase is deprecated in current Frappe; prefer IntegrationTestCase/UnitTestCase if available in your target version")
        self.generic_visit(node)

    def visit_FunctionDef(self, node):
        # mutable defaults
        for d in list(node.args.defaults) + [d for d in node.args.kw_defaults if d is not None]:
            if isinstance(d, (ast.List, ast.Dict, ast.Set)):
                self.emit(d, "F011", "WARN", f"Mutable default argument in {node.name}()")
        decs = self.decorators(node)
        whitelisted = [(n, d) for n, d in decs if n.endswith("whitelist")]
        for _, d in whitelisted:
            if isinstance(d, ast.Call):
                for kw in d.keywords:
                    if kw.arg == "allow_guest" and isinstance(kw.value, ast.Constant) and kw.value.value is True:
                        self.emit(d, "F003", "WARN", f"{node.name}() is callable by guests (allow_guest=True): validate input, rate-limit, avoid private data")
        if whitelisted:
            calls = {attr_chain(n.func).split(".")[-1] for n in ast.walk(node) if isinstance(n, ast.Call)}
            if not (calls & PERM_CALLS):
                self.emit(node, "F007", "INFO", f"Whitelisted {node.name}() shows no permission check (has_permission/check_permission/only_for/get_list); confirm authorization")
        self.func_stack.append(node.name)
        saved = self.loop_depth
        self.loop_depth = 0
        self.generic_visit(node)
        self.loop_depth = saved
        self.func_stack.pop()

    visit_AsyncFunctionDef = visit_FunctionDef

    def visit_For(self, node):
        self.visit(node.iter)
        self.loop_depth += 1
        for n in node.body + node.orelse:
            self.visit(n)
        self.loop_depth -= 1

    visit_While = visit_For
    visit_AsyncFor = visit_For

    def visit_ListComp(self, node):
        self.loop_depth += 1
        self.generic_visit(node)
        self.loop_depth -= 1

    visit_SetComp = visit_DictComp = visit_GeneratorExp = visit_ListComp

    def visit_ExceptHandler(self, node):
        body_is_pass = all(isinstance(b, ast.Pass) for b in node.body)
        broad = node.type is None or (isinstance(node.type, ast.Name) and node.type.id in ("Exception", "BaseException"))
        if node.type is None:
            self.emit(node, "F008", "WARN", "Bare except: catches SystemExit/KeyboardInterrupt and hides errors")
        elif broad and body_is_pass:
            self.emit(node, "F008", "WARN", "except Exception: pass swallows errors silently; log with frappe.log_error or re-raise")
        self.generic_visit(node)

    def visit_Call(self, node):
        name = attr_chain(node.func)
        # F001 commit
        if name in ("frappe.db.commit",) and not self.is_patch and not self.is_test:
            self.emit(node, "F001", "WARN", "frappe.db.commit() outside a patch/job: Frappe commits per request; mid-request commits break atomicity (acceptable in batched background jobs)")
        # F002 ignore_permissions
        for kw in node.keywords:
            if kw.arg == "ignore_permissions" and isinstance(kw.value, ast.Constant) and kw.value.value is True:
                self.emit(node, "F002", "INFO", "ignore_permissions=True: confirm the caller is authorized by another mechanism")
        # F004 / F009 SQL
        if name in ("frappe.db.sql", "frappe.db.multisql", "frappe.db.sql_list") and node.args:
            q = node.args[0]
            if is_dynamic_string(q):
                self.emit(node, "F004", "ERROR", "SQL built dynamically (f-string/%/+/format): use parameters (%s / %(name)s) or frappe.qb; escape identifiers with frappe.db.escape only when unavoidable")
            text = const_text(q) or ""
            if WRITE_SQL.search(text) and LEDGER_TABLES.search(text):
                self.emit(node, "F009", "ERROR", "Direct UPDATE/DELETE on a ledger table: use cancel/amend or Repost Item Valuation / Repost Accounting Ledger")
        # F005 N+1
        if self.loop_depth and name.startswith("frappe.") and name.split(".")[-1] in LOOP_CALLS \
                and name in ("frappe.get_doc", "frappe.get_cached_doc", "frappe.get_all", "frappe.get_list",
                             "frappe.db.get_value", "frappe.db.get_all", "frappe.db.get_list"):
            self.emit(node, "F005", "WARN", f"{name}() inside a loop: possible N+1; batch with one query and map by key")
        # F006 recursion
        fn = self.func_stack[-1] if self.func_stack else ""
        if fn in ("validate", "on_update", "before_save", "after_insert", "on_change") and isinstance(node.func, ast.Attribute) \
                and node.func.attr == "save" and isinstance(node.func.value, ast.Name) and node.func.value.id in ("self", "doc"):
            self.emit(node, "F006", "WARN", f"{node.func.value.id}.save() inside {fn}(): recursion/duplicate-event risk; use db_set or flags")
        self.generic_visit(node)


JS_RULES = [
    (re.compile(r"async\s*:\s*false"), "F020", "WARN", "Synchronous request blocks the UI; use async/await or promises"),
    (re.compile(r"\bfrm\.doc\.[A-Za-z_]\w*\s*=(?!=)"), "F021", "INFO", "Direct assignment to frm.doc.<field>; prefer frm.set_value so triggers and form state update"),
]


def iter_files(root: Path, include_tests: bool):
    if root.is_file():
        yield root
        return
    for p in root.rglob("*"):
        if any(part in SKIP_DIRS for part in p.parts):
            continue
        if p.suffix in (".py", ".js") and p.is_file():
            if p.suffix == ".js" and (p.name.endswith(".min.js") or "/public/dist/" in p.as_posix()):
                continue
            if not include_tests and p.name.startswith("test_"):
                continue
            yield p


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("path")
    ap.add_argument("--json", action="store_true")
    ap.add_argument("--include-tests", action="store_true")
    args = ap.parse_args()

    root = Path(args.path).resolve()
    base = root if root.is_dir() else root.parent
    findings = []
    parse_errors = []

    for f in iter_files(root, args.include_tests):
        rel = f.relative_to(base).as_posix()
        try:
            text = f.read_text(encoding="utf-8", errors="replace")
        except OSError as e:
            parse_errors.append((rel, str(e)))
            continue
        if f.suffix == ".py":
            try:
                tree = ast.parse(text, filename=str(f))
            except SyntaxError as e:
                parse_errors.append((rel, f"syntax error line {e.lineno}"))
                continue
            PyVisitor(f, "/" + rel, findings.append).visit(tree)
        else:
            for i, line in enumerate(text.splitlines(), 1):
                stripped = line.strip()
                if stripped.startswith("//"):
                    continue
                for rx, code, sev, msg in JS_RULES:
                    if rx.search(line):
                        findings.append(Finding(file="/" + rel, line=i, code=code, severity=sev, message=msg))

    order = {"ERROR": 0, "WARN": 1, "INFO": 2}
    findings.sort(key=lambda x: (order[x["severity"]], x["file"], x["line"]))

    if args.json:
        print(json.dumps({"findings": findings, "parse_errors": parse_errors}, indent=2))
    else:
        for x in findings:
            print(f'{x["severity"]:5} {x["code"]} {x["file"].lstrip("/")}:{x["line"]}  {x["message"]}')
        for rel, err in parse_errors:
            print(f"SKIP  {rel}: {err}")
        counts = {s: sum(1 for x in findings if x["severity"] == s) for s in order}
        print(f'\n{len(findings)} finding(s): {counts["ERROR"]} error, {counts["WARN"]} warn, {counts["INFO"]} info')
    return 1 if any(x["severity"] == "ERROR" for x in findings) else 0


if __name__ == "__main__":
    sys.exit(main())
