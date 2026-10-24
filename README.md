# Frappe / ERPNext Agent Skills (v15 / v16)

Seventeen reusable skills for Frappe Framework and ERPNext developers. They are agent instructions and helper resources; they are **not Frappe apps** and are not installed into a bench's Python environment.

The skills can be installed for Claude Code and OpenAI Codex. Other agents can use them if they support the Agent Skills `SKILL.md` format or a compatible way to load reusable instructions.

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

## Helper scripts

The repository includes four helper scripts. They are diagnostic aids, not a guarantee that a site is healthy or that a backup is restorable. Review the scripts and run them against a development/staging environment first.

- `frappe-dev-workflow/scripts/detect_env.sh [bench]` — versions, apps/branches, runtime, sites; secret values should not be printed.
- `frappe-testing-debugging/scripts/hooks_audit.py [bench]` — duplicate `doc_events` and override conflicts across apps.
- `frappe-code-review/scripts/frappe_lint.py PATH [--json]` — static checks for risky Frappe patterns.
- `frappe-devops/scripts/backup_status.sh [bench] [max_age_hours]` — newest backups, age, and size.

## Recommended installation on Ubuntu

Keep one clone of this repository as the source of truth, then install copies into each agent's supported skill directory. Do not put skills inside `apps/frappe` or `apps/erpnext`.

```bash
mkdir -p ~/development
cd ~/development
git clone https://github.com/akhilkp11/frappe-erpnext-skill.git
cd frappe-erpnext-skill
bash install.sh --list
```

### Claude Code — user-level (available across your projects)

```bash
bash install.sh --agent claude --dry-run
bash install.sh --agent claude
```

Target: `~/.claude/skills/`.

### OpenAI Codex CLI — user-level

```bash
bash install.sh --agent codex --dry-run
bash install.sh --agent codex
```

Target: `~/.agents/skills/`.

### Install for both agents

```bash
bash install.sh --agent both --dry-run
bash install.sh --agent both
```

Claude and Codex use different global skill directories. The installer backs up an existing same-name skill separately for each target before copying the replacement.

### Project-level installation (for a team repository)

The project directory must already exist. Project-level skills can be committed to Git so teammates can use them, subject to their agent's repository trust and configuration rules.

```bash
cd /path/to/your/custom_app
bash /path/to/frappe-erpnext-skill/install.sh --agent both --project "$PWD" --dry-run
bash /path/to/frappe-erpnext-skill/install.sh --agent both --project "$PWD"
```

Targets:

- Claude Code: `<project>/.claude/skills/`
- Codex: `<project>/.agents/skills/`

### Install only selected skills

```bash
bash install.sh --agent both --only frappe-core,frappe-api --dry-run
bash install.sh --agent both --only frappe-core,frappe-api
```

Use `bash install.sh --help` for all options. `--dry-run` previews operations without making directories or changing files.

## Instructions files are separate from skills

Skills do not automatically create project or global instruction files. Use `CLAUDE.md.example` as a starting point and edit it for your environment.

For Claude Code, copy or merge it into the project as `CLAUDE.md` (or use the instruction filename convention supported by your installed Claude Code version). For Codex, create/maintain `AGENTS.md` with the same shared project rules. Do not overwrite existing instructions blindly.

Example global files:

- Claude Code: `~/.claude/CLAUDE.md`
- Codex: `~/.codex/AGENTS.md` (global Codex instructions; check your installed Codex version's documented convention)

Example project files:

- `CLAUDE.md` for Claude Code project guidance
- `AGENTS.md` for Codex and other agents that support it

Keep common rules aligned, but preserve each agent's supported configuration conventions. The installer installs skills only; it does not install or configure the AI-agent applications themselves.

## Verification

List skills in the source repository:

```bash
bash install.sh --list
```

Check installed skill files:

```bash
find ~/.claude/skills -mindepth 2 -maxdepth 2 -name SKILL.md 2>/dev/null
find ~/.agents/skills -mindepth 2 -maxdepth 2 -name SKILL.md 2>/dev/null
```

Start a new agent session and ask it to list the Frappe/ERPNext skills it can use. Test with a small read-only task before asking the agent to edit code.

For bench diagnostics, replace the example paths with your actual bench directories:

```bash
bash ~/development/frappe-erpnext-skill/frappe-dev-workflow/scripts/detect_env.sh ~/frappe-bench
bash ~/development/frappe-erpnext-skill/frappe-dev-workflow/scripts/detect_env.sh ~/frappe-bench-v16
python3 ~/development/frappe-erpnext-skill/frappe-testing-debugging/scripts/hooks_audit.py ~/frappe-bench
python3 ~/development/frappe-erpnext-skill/frappe-code-review/scripts/frappe_lint.py /path/to/your/custom_app
bash ~/development/frappe-erpnext-skill/frappe-devops/scripts/backup_status.sh ~/frappe-bench
```

These commands inspect local code/environment; they do not replace application tests. Confirm the script arguments and outputs before relying on them.

## Updating

```bash
cd ~/development/frappe-erpnext-skill
git status
git pull --ff-only
bash install.sh --list
bash install.sh --agent both --dry-run
bash install.sh --agent both
```

Review upstream changes before reinstalling. Existing same-name skill folders are moved to timestamped backup directories next to the active skills directory, under `skills-backup/`. Keep those backups until you have verified the updated skills.

## Rollback

The installer prints the backup path when existing skill directories are replaced. To roll back a skill, move the currently installed folder aside and restore that skill's matching backup folder. Example (replace the placeholders with the real paths):

```bash
mv ~/.agents/skills/frappe-core ~/.agents/skills/frappe-core.failed
cp -R ~/.agents/skills-backup/TIMESTAMP/frappe-core ~/.agents/skills/frappe-core
```

For Claude, use the corresponding `~/.claude/skills/` and `~/.claude/skills-backup/` paths. Project installs use backup folders under the project's `.claude/` or `.agents/` directory. Do not delete backups until rollback has been verified.

## Safety and compatibility

- These skills are instructions and helper scripts, not Frappe apps. They do not change bench dependencies or database schemas.
- No destructive command, production migration, restore, or data fix without explicit approval and a verified backup.
- Keep site config, API keys, encryption keys, and other secrets out of prompts and Git.
- Never edit `apps/frappe` or `apps/erpnext` for an app-level customization unless the task explicitly concerns framework development.
- Confirm installed Frappe/ERPNext/app versions and inspect the installed source before version-sensitive changes.
- Validate custom apps on separate development/staging sites for Frappe/ERPNext v15 and v16. The skills do not guarantee cross-version compatibility.
- Helper scripts are best-effort diagnostics; review them and test their results before using them to guide production changes.

See `AUDIT.md` for the package's audit notes and unverified areas.