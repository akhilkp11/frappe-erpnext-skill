#!/usr/bin/env bash
# Read-only environment report for a Frappe bench. Prints no secrets.
# Usage: detect_env.sh [bench_path]
set -u

find_bench() {
  local d="${1:-$PWD}"
  d="$(cd "$d" 2>/dev/null && pwd)" || return 1
  while [[ "$d" != "/" ]]; do
    if [[ -d "$d/apps/frappe" && -d "$d/sites" ]]; then echo "$d"; return 0; fi
    d="$(dirname "$d")"
  done
  return 1
}

BENCH="$(find_bench "${1:-$PWD}")" || { echo "No bench found (looked for apps/frappe + sites/ upward from ${1:-$PWD})."; exit 1; }
echo "== Bench: $BENCH"

echo; echo "== Apps (version / branch / commit)"
for app in "$BENCH"/apps/*/; do
  name="$(basename "$app")"
  ver="$(grep -hEo "^__version__ *= *['\"][^'\"]+" "$app$name/__init__.py" 2>/dev/null | head -1 | sed -E "s/.*['\"]//")"
  branch="$(git -C "$app" rev-parse --abbrev-ref HEAD 2>/dev/null || echo '-')"
  commit="$(git -C "$app" rev-parse --short HEAD 2>/dev/null || echo '-')"
  if git -C "$app" rev-parse --git-dir >/dev/null 2>&1; then
    dirty="$(git -C "$app" status --porcelain 2>/dev/null | wc -l | tr -d ' ')"
  else
    dirty="-"
  fi
  printf '%-22s version=%-12s branch=%-18s commit=%-9s uncommitted_files=%s\n' "$name" "${ver:-?}" "$branch" "$commit" "$dirty"
done

echo; echo "== Runtime"
BENCH_PY="$BENCH/env/bin/python"
if [[ -x "$BENCH_PY" ]]; then
  echo "bench python: $("$BENCH_PY" --version 2>&1)"
  PY="$BENCH_PY"
else
  echo "bench python: env/bin/python not found (using system python3 for JSON parsing)"
  PY="$(command -v python3 || true)"
fi
[[ -n "${PY:-}" ]] || { echo "no python available to parse config files"; PY=""; }
command -v node >/dev/null && echo "node: $(node --version)" || echo "node: not found"
command -v yarn >/dev/null && echo "yarn: $(yarn --version 2>/dev/null)" || true
command -v bench >/dev/null && echo "bench cli: $(bench --version 2>&1 | head -1)" || echo "bench cli: not on PATH"
if command -v mariadb >/dev/null; then echo "mariadb client: $(mariadb --version)"; elif command -v mysql >/dev/null; then echo "mysql client: $(mysql --version)"; fi
command -v redis-server >/dev/null && echo "redis: $(redis-server --version | head -1)" || true
echo "OS: $(. /etc/os-release 2>/dev/null && echo "$PRETTY_NAME" || uname -sr)"

echo; echo "== Sites"
for s in "$BENCH"/sites/*/; do
  n="$(basename "$s")"
  [[ -f "$s/site_config.json" ]] || continue
  echo "- $n"
  "$PY" - "$s/site_config.json" <<'PYEOF' 2>/dev/null
import json, sys
SAFE = {"developer_mode", "maintenance_mode", "pause_scheduler", "host_name", "disable_website_cache", "allow_tests", "server_script_enabled"}
try:
    cfg = json.load(open(sys.argv[1]))
except Exception as e:
    print("    (unreadable site_config:", e, ")"); raise SystemExit
shown = {k: cfg[k] for k in SAFE if k in cfg}
print("    config flags:", shown or "-")
print("    config keys present (values hidden):", ", ".join(sorted(k for k in cfg if k not in SAFE)) or "-")
PYEOF
done

echo; echo "== common_site_config (non-secret keys only)"
"$PY" - "$BENCH/sites/common_site_config.json" <<'PYEOF' 2>/dev/null
import json, sys
SAFE = {"dns_multitenant", "background_workers", "webserver_port", "socketio_port", "redis_cache", "redis_queue", "redis_socketio", "serve_default_site", "restart_supervisor_on_update", "restart_systemd_on_update", "gunicorn_workers", "developer_mode"}
cfg = json.load(open(sys.argv[1]))
for k in sorted(SAFE & set(cfg)):
    v = cfg[k]
    if isinstance(v, str) and "@" in v:  # redis URLs may embed credentials
        v = v.split("@")[-1]
    print(f"  {k}: {v}")
PYEOF

echo; echo "== Process managers (best effort)"
command -v supervisorctl >/dev/null && (supervisorctl status 2>/dev/null | head -20 || echo "supervisorctl: no permission/none") || echo "supervisorctl: not installed"
echo; echo "Done. This script made no changes."
