# Frappe / ERPNext Skills for Claude Code (v15 / v16)

Seventeen skills for Frappe Framework and ERPNext developers, with three tested helper scripts.
Skills load automatically when a request matches their description; `frappe-dev-workflow` is the entry point that routes to the others.

## Skills

| Area | Skill | What it covers |
|---|---|---|
| Start here | `frappe-dev-workflow` | Environment detection, skill routing, evidence-first loop, answer format |
| Framework | `frappe-core` | Controllers, hooks, queries, flags, transactions, fixtures, patches, event order |
| | `frappe-doctype-design` | Custom Field vs Property Setter vs new DocType, naming, permissions, safe schema change |
| | `frappe-app-structure` | App layout, hooks, CI, branches per version, Frappe Cloud readiness |
| | `frappe-api` | Whitelisted methods, REST, auth, errors, idempotency, webhooks |
| | `frappe-security-permissions` | Roles/permlevels/user permissions, row-level hooks, SQLi/XSS, guest endpoints |
| | `frappe-background-jobs` | enqueue, queues, scheduler, idempotent jobs, diagnosing stuck jobs |
| | `frappe-data-migration-patches` | Bulk fixes, patches, Data Import, opening balances, dry runs |
| Desk / output | `frappe-client-scripts` | Form JS, set_query, child tables, buttons, frappe.call |
| | `frappe-reports-print-formats` | Script/Query reports, Jinja print formats, reconciliation |
| Quality | `frappe-performance` | Recorder/EXPLAIN, N+1, indexes, caching |
| | `frappe-testing-debugging` | Tracebacks, hook-conflict audit, IntegrationTestCase tests |
| | `frappe-code-review` | Lint script + review checklist |
| Operations | `frappe-devops` | bench, production, multi-bench VPS, backups/restores, upgrades, Frappe Cloud |
| ERPNext | `erpnext-customization` | Business logic, mapping, workflows, tasks, reminders |
| | `erpnext-accounting-stock` | GL/SLE/payment ledger, valuation, reposting, reconciliation |
| | `erpnext-india-gst` | India Compliance: GST, e-invoice, e-way bill, GSTR, TDS |

## Helper scripts (all read-only)
- `frappe-dev-workflow/scripts/detect_env.sh [bench]` - versions, apps/branches, runtime, sites (secret values never printed)
- `frappe-testing-debugging/scripts/hooks_audit.py [bench]` - duplicate `doc_events`, override conflicts across apps
- `frappe-code-review/scripts/frappe_lint.py PATH [--json]` - static checks for risky Frappe patterns (CI-friendly exit code)
- `frappe-devops/scripts/backup_status.sh [bench] [max_age_hours]` - newest backups, age, size

## Install
```bash
unzip frappe-erpnext-claude-skills.zip && cd frappe-erpnext-claude-skills
bash install.sh                      # ~/.claude/skills (all your projects)
bash install.sh --project /path/to/repo   # repo-level, commit .claude/skills for the team
bash install.sh --dry-run            # preview
bash install.sh --only frappe-core,frappe-api
```
Existing copies are moved to `~/.claude/skills-backup/<timestamp>/` (outside the skills folder, so they are never loaded as duplicates). Start a new Claude Code session afterwards, and check with `/skills` or by asking Claude to list its skills.

Copy `CLAUDE.md.example` to your repo as `CLAUDE.md` and fill in your versions and test command.

## How to use
Open Claude Code in the custom app or bench repository and describe the task normally. Ask it to inspect the installed source and version first. The skills are guidance, not a substitute for source inspection, tests, backups and review.

## Safety
- No destructive command, production migration, restore, or data fix without your explicit approval and a verified backup.
- Keep secrets (site config, API keys, encryption key) out of prompts and Git.
- Version-specific statements (v15 vs v16, India Compliance behavior) are flagged "verify in installed source" on purpose; keep it that way.

## Maintenance
Re-verify version-specific claims at each Frappe/ERPNext major release: test base classes, `extend_doctype_class`, cache API, enqueue options, system requirements (v16 currently documents Python 3.14, Node 24, MariaDB 11.8), and India Compliance behavior. See `AUDIT.md` for what was checked and what remains unverified.
