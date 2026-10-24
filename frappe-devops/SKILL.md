---
name: frappe-devops
description: Operate and troubleshoot Frappe/ERPNext benches and servers - bench commands, production setup with Supervisor/Nginx, multiple benches on one VPS, DNS multitenancy and Let's Encrypt, workers/scheduler/Redis/MariaDB, backups and restores, migrations, v15 to v16 upgrades, Git deployment, and Frappe Cloud constraints. Use for deployment, server errors (502/504), site not loading, restore, upgrade, or "bench migrate fails" questions.
---

# Frappe DevOps

## Safety rules
- Establish first: environment (dev/staging/production), bench path, site, Frappe/ERPNext/app versions (`frappe-dev-workflow/scripts/detect_env.sh`), and how processes are managed (Supervisor, systemd, Docker, Frappe Cloud).
- Label every command: **[READ-ONLY]**, **[CHANGES STATE]** (restarts, migrate, config), or **[DESTRUCTIVE]** (drop-site, restore --force, reset, delete). Never run the last two on production without explicit user approval and a verified, recent backup.
- Never print or paste `site_config.json`, `common_site_config.json`, `bench show-config`, or env files; they contain DB passwords, API secrets, and the `encryption_key`.
- Do not assume layout (Redis ports, service names, Python path). Inspect.

## Version baseline (verify against official docs for your exact release)
| | Frappe v15 | Frappe v16 |
|---|---|---|
| Python | 3.10 - 3.13 | 3.14 |
| Node | 18+ (20 common) | 24 |
| MariaDB | 10.6+ | 11.8 |
| Bench install | `pip`/pipx or `uv tool install frappe-bench` | `uv tool install frappe-bench` (recommended) |
A v15 bench environment cannot simply be reused for v16; plan a new env (rebuild `env/`, rebuild assets) and rehearse on staging first.

## Diagnostic sequence (read-only first)
1. `bench version`, `bench --site SITE list-apps`, `git -C apps/APP status && git -C apps/APP log -1`.
2. Services: `sudo supervisorctl status` (or `systemctl status`), look for `web`, `socketio`, `schedule`, `worker` (short/default/long) and Redis processes.
3. Logs in `bench/logs/` (web, worker, scheduler error logs) and Nginx/Supervisor logs; for a 502 check gunicorn alive and the upstream port in the Nginx config; for 504 check long requests and timeouts.
4. `bench doctor`, `bench --site SITE scheduler status`.
5. Resources: `df -h` (disk and inodes), `free -h`, `top`/`htop`, MariaDB `SHOW PROCESSLIST`, Redis `INFO memory` for the right Redis instance.
6. Version alignment: Frappe/ERPNext/HRMS/India Compliance branches must match (all `version-15` or all `version-16`).

## Migrations and updates
- Backup first: `bench --site SITE backup --with-files` **[CHANGES STATE: writes files]**; confirm the files exist and sizes are sane (`scripts/backup_status.sh`).
- `bench --site SITE migrate` applies patches, syncs DocTypes/fixtures, and rebuilds hooks-dependent caches. Run during a maintenance window; it may take minutes and lock tables. Check pending patches in Desk (Patch Log) and app compatibility beforehand.
- `bench update` pulls every app, installs requirements, migrates, builds, and restarts; prefer explicit steps on production (`git pull` per app, `bench setup requirements`, `bench --site SITE migrate`, `bench build --app APP`, `bench restart`) so you control and can pause between stages.
- After changing hooks.py: restart web/workers. After JS/CSS changes: `bench build`. Cache oddities: `bench --site SITE clear-cache` and `clear-website-cache`.
- Major upgrades (for example `bench switch-to-branch version-16 frappe erpnext --upgrade`) are staged projects: backup, restore to staging, resolve custom app compatibility, run tests, then schedule production. Never do them as an ad-hoc fix.

## Backups and restores
- Backups live under `sites/SITE/private/backups/` (database `.sql.gz`, plus public/private file tarballs, plus `site_config` backup). Copy them off the server; a backup on the same disk is not a backup.
- Restore to a **different** site name for rehearsal when possible. Restoring into an existing site overwrites it **[DESTRUCTIVE]**: `bench --site SITE --force restore DB.sql.gz --with-public-files PUB.tar --with-private-files PRIV.tar` (flags vary; check `bench restore --help`).
- Encrypted fields (Password fields, stored credentials) need the original `encryption_key`; if the target site has a different key those values become unreadable. Carry the key over deliberately (do not echo it).
- Verify after restore: login, a few documents, attachments open, scheduler state (`bench --site SITE scheduler status`), outgoing email disabled on staging copies, integrations pointed at sandboxes.

## Multiple benches on one VPS
- Each bench needs unique ports (web, socketio, redis_cache/queue/socketio) in its `sites/common_site_config.json`, its own Supervisor program group names, and its own Nginx config. Collisions here cause one bench to serve or kill another's processes.
- Generate configs per bench (`bench setup supervisor`, `bench setup nginx`) then include them in the system Supervisor/Nginx; avoid running `bench setup production` on a second bench blindly because it rewrites shared system files; inspect what it would change first.
- Size MariaDB and Redis memory for the sum of benches. One heavy report can starve every client on a shared VPS; use per-bench worker limits and watch swap.

## DNS multitenancy and TLS
- Host-based routing: `bench config dns_multitenant on` **[CHANGES STATE]**, then `bench setup add-domain DOMAIN --site SITE` and `bench setup nginx`, then reload Nginx. The DNS A record must point at the server first.
- Let's Encrypt: `sudo bench setup lets-encrypt SITE [--custom-domain DOMAIN]`; renewals run by cron/certbot timer; failures are usually DNS not propagated, port 80 blocked, or Nginx not serving the challenge path. Rate limits apply; test with staging when experimenting.
- After domain changes verify `host_name` in site config and that emails/links use the right URL.

## Git workflow
Inspect branch, status, diff, remotes, and uncommitted changes before pull/reset/rebase/deploy. Servers should have clean app checkouts: changes made on the server are lost or conflict on update. Track a branch per Frappe major (`version-15`, `version-16`); pin custom apps to a branch/tag. Export fixtures and review the diff before committing.

## Frappe Cloud notes (managed hosting)
No arbitrary shell, Nginx, or Supervisor access on shared benches: deploy by updating the Bench Group (apps come from GitHub branches), then migrate runs as part of deploy; site config, domains, backups, and logs are managed in the dashboard; custom Python dependencies and system packages are constrained by the platform. Check which console/SQL tools your plan exposes before proposing server-side fixes, and keep custom apps compatible with the platform's branch and Python version.

## Output
Commands in safe order, expected output, downtime risk, verification steps, rollback. Keep development-bench commands and production commands separate.
