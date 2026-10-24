---
name: frappe-code-review
description: Review Frappe/ERPNext code, diffs, or whole custom apps for correctness, security, performance, and upgrade risk - SQL injection, ignore_permissions, guest endpoints, commits in hooks, N+1 loops, recursion in on_update, direct ledger SQL, deprecated test classes. Includes a static lint script. Use when asked to review, audit, or "check this app/PR", or before releasing a custom app.
---

# Frappe code review

## Step 1: run the linter (cheap, deterministic)
```bash
python scripts/frappe_lint.py path/to/app            # human-readable
python scripts/frappe_lint.py path/to/app --json     # for CI; exit code 1 if any ERROR
```
It uses Python's `ast` for `.py` files and conservative regexes for `.js`. Findings are *leads*, not verdicts: confirm each in context before reporting it. It cannot see runtime behavior, hooks in other apps, or business correctness.

| Code | Severity | Meaning |
|---|---|---|
| F001 | WARN | `frappe.db.commit()` outside patches/jobs (breaks request atomicity) |
| F002 | INFO | `ignore_permissions=True` (confirm the caller is authorized another way) |
| F003 | WARN | `allow_guest=True` endpoint (public) |
| F004 | ERROR | SQL built with f-string/`%`/`+`/`.format` passed to `frappe.db.sql` |
| F005 | WARN | `get_doc`/`get_all`/`db.get_value` inside a loop (N+1 candidate) |
| F006 | WARN | `save()` on the same doc inside `validate`/`on_update` (recursion risk) |
| F007 | INFO | whitelisted function with no visible permission check |
| F008 | WARN | bare `except:` or `except Exception: pass` (swallowed errors) |
| F009 | ERROR | `UPDATE`/`DELETE` SQL against ledger tables (GL, Stock Ledger, Payment Ledger) |
| F010 | INFO | deprecated `FrappeTestCase` import |
| F011 | WARN | mutable default argument |
| F020 | WARN | JS synchronous request (`async: false`) |
| F021 | INFO | JS assigns `frm.doc.<field> =` directly instead of `set_value` |

## Step 2: manual review (what tools miss)
Work through `references/review-checklist.md`, prioritizing in this order: **data integrity** (ledgers, submitted docs, rounding), **security** (authorization on every entry point), **correctness across versions**, **performance** on large data, **operability** (logging, idempotency, rollback), then style.

## Step 3: report
For each finding: severity, file:line, what is wrong, a concrete failure scenario, the fix (code), and how to verify. Group by severity, put verified issues before suspicions, and say what you did **not** review (for example "did not run the app or tests"). Do not invent problems to fill space; "no issues found in X" is a valid result.
