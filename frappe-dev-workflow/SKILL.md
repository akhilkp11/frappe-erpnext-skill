---
name: frappe-dev-workflow
description: Entry point for ANY Frappe Framework or ERPNext task (v15/v16) - bug, feature, customization, report, API, upgrade, or "why does X happen". Use it first to detect the installed versions and apps, pick the right specialist skill, and follow the evidence-first workflow. Trigger on any mention of Frappe, ERPNext, bench, DocType, hooks.py, Frappe Cloud, HRMS, or India Compliance, even if the user does not ask for a "skill".
---

# Frappe / ERPNext development workflow

Frappe and ERPNext change between versions (v15 vs v16 differ in Python/Node requirements, test base classes, hook options, and parts of accounting/stock). Answers built from memory of an older version are the most common source of wrong advice, so establish facts about the environment before proposing changes.

## 1. Establish the environment (read-only)
Run `scripts/detect_env.sh` from inside the bench (or pass the bench path). It prints versions, installed apps with git branch/commit, Python/Node/MariaDB/Redis versions, and sites. It never prints secrets or modifies anything. If you cannot run commands (for example on Frappe Cloud or when only code is pasted), ask for: Frappe + ERPNext + custom app versions, the DocType involved, and the full traceback.

## 2. Pick the specialist skill
| Task | Skill |
|---|---|
| Controllers, hooks, queries, patches, fixtures | `frappe-core` |
| New/changed DocTypes, custom fields, naming, permissions model | `frappe-doctype-design` |
| Creating or structuring a custom app, CI, `required_apps` | `frappe-app-structure` |
| Whitelisted methods, REST, mobile/webhook endpoints | `frappe-api` |
| Roles, user permissions, SQL injection/XSS, guest endpoints | `frappe-security-permissions` |
| `frappe.enqueue`, scheduler, long jobs, retries | `frappe-background-jobs` |
| Data fixes, imports, opening balances, migrations | `frappe-data-migration-patches` |
| Form scripts, `set_query`, buttons, child tables | `frappe-client-scripts` |
| Query/Script reports, Jinja print formats | `frappe-reports-print-formats` |
| Slow pages/APIs/reports, N+1, indexes | `frappe-performance` |
| Tracebacks, hook conflicts, writing tests | `frappe-testing-debugging` |
| Reviewing a diff or app for risky patterns | `frappe-code-review` |
| bench, production, backups, upgrades, Frappe Cloud | `frappe-devops` |
| Sales/Purchase/Stock/HR/Project business logic | `erpnext-customization` |
| GL, stock ledger, valuation, payments, TDS mechanics | `erpnext-accounting-stock` |
| GST, e-invoice, e-way bill, GSTR-1/3B, India TDS | `erpnext-india-gst` |

Most real tasks need two or three skills (for example a GST invoice bug touches `erpnext-india-gst`, `erpnext-accounting-stock`, and `frappe-testing-debugging`). Read each that applies.

## 3. Evidence-first loop
1. Reproduce or read the failing path: full traceback, the exact document, the version.
2. Read the installed source for the behavior in question (`apps/frappe/frappe/...`, `apps/erpnext/erpnext/...`, `apps/india_compliance/...`). Do not rely on recall for event order, function signatures, or field names.
3. Search every installed app's `hooks.py` for overrides touching the same DocType (`frappe-testing-debugging/scripts/hooks_audit.py`).
4. Choose the least invasive extension point that belongs in the custom app, never in core.
5. Implement, then run the real tests or a reproduction on a development site. Report only what was actually executed.
6. State deployment steps (migrate, build, restart, clear cache), data-risk, and rollback.

## 4. Answer format
Root cause (or design) first, then exact files, complete code, commands labelled as read-only / changes state / destructive, test steps, and rollback. Separate verified facts from assumptions, and say plainly when a version-specific detail was not checked against the installed source.
