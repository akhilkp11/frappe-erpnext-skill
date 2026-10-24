#!/usr/bin/env bash
# Read-only: show the newest backups per site with age and size, to check before risky changes.
# Usage: backup_status.sh [bench_path] [max_age_hours=24]
set -u
BENCH="${1:-$PWD}"
MAX_AGE_H="${2:-24}"
[[ -d "$BENCH/sites" ]] || { echo "No sites/ under $BENCH"; exit 1; }
now=$(date +%s); status=0
for s in "$BENCH"/sites/*/; do
  [[ -f "$s/site_config.json" ]] || continue
  site="$(basename "$s")"; dir="$s/private/backups"
  echo "== $site"
  if [[ ! -d "$dir" ]]; then echo "  no backups directory"; status=2; continue; fi
  for pattern in "*database.sql.gz" "*-files.tar" "*private-files.tar" ; do
    if [[ "$pattern" == "*-files.tar" ]]; then
      f="$(ls -1t "$dir"/$pattern 2>/dev/null | grep -v private | head -1)"   # public files only
    else
      f="$(ls -1t "$dir"/$pattern 2>/dev/null | head -1)"
    fi
    if [[ -z "$f" ]]; then echo "  $pattern: none"; [[ "$pattern" == "*database.sql.gz" ]] && status=2; continue; fi
    age_h=$(( (now - $(stat -c %Y "$f")) / 3600 ))
    printf '  %-45s %6s  %4sh old' "$(basename "$f")" "$(du -h "$f" | cut -f1)" "$age_h"
    if [[ "$pattern" == "*database.sql.gz" ]] && (( age_h > MAX_AGE_H )); then printf '  <-- OLDER than %sh' "$MAX_AGE_H"; status=2; fi
    if [[ ! -s "$f" ]]; then printf '  <-- EMPTY FILE'; status=2; fi
    echo
  done
done
echo; echo "Disk free for bench: $(df -h "$BENCH" | awk 'NR==2{print $4" free ("$5" used)"}')"
echo "Reminder: confirm a copy exists OFF this server, and test-restore periodically."
exit $status
