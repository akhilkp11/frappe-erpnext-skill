#!/usr/bin/env bash
# Install the Frappe/ERPNext skills for Claude Code.
#
#   bash install.sh                 # user-level:    ~/.claude/skills
#   bash install.sh --project DIR   # project-level: DIR/.claude/skills (commit it for your team)
#   bash install.sh --dry-run       # show what would happen
#   bash install.sh --only frappe-core,frappe-api
#
# Existing skills with the same name are moved to a backup folder OUTSIDE the skills
# directory (so Claude Code never loads old copies as duplicate skills).
set -euo pipefail

SOURCE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET_DIR="${HOME}/.claude/skills"
BACKUP_ROOT=""
DRY=0
ONLY=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --project) [[ $# -ge 2 ]] || { echo "--project needs a directory"; exit 2; }
               TARGET_DIR="$(cd "$2" && pwd)/.claude/skills"; shift 2 ;;
    --dry-run) DRY=1; shift ;;
    --only)    [[ $# -ge 2 ]] || { echo "--only needs a comma-separated list"; exit 2; }
               ONLY=",$2,"; shift 2 ;;
    -h|--help) sed -n '2,12p' "$0"; exit 0 ;;
    *) echo "Unknown option: $1"; exit 2 ;;
  esac
done

STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP_ROOT="$(dirname "$TARGET_DIR")/skills-backup/${STAMP}"
run() { if [[ $DRY -eq 1 ]]; then echo "[dry-run] $*"; else "$@"; fi; }

run mkdir -p "$TARGET_DIR"
count=0
for skill_dir in "$SOURCE_DIR"/*/; do
  [[ -f "${skill_dir}SKILL.md" ]] || continue
  name="$(basename "$skill_dir")"
  if [[ -n "$ONLY" && "$ONLY" != *",$name,"* ]]; then continue; fi
  target="${TARGET_DIR}/${name}"

  if [[ -e "$target" ]]; then
    echo "Backing up existing ${name} -> ${BACKUP_ROOT}/${name}"
    run mkdir -p "$BACKUP_ROOT"
    run mv "$target" "${BACKUP_ROOT}/${name}"
  fi
  echo "Installing ${name}"
  run cp -R "$skill_dir" "$target"
  # keep helper scripts executable
  if [[ $DRY -eq 0 && -d "$target/scripts" ]]; then chmod +x "$target"/scripts/* 2>/dev/null || true; fi
  count=$((count + 1))
done

echo
echo "Installed ${count} skill(s) to: ${TARGET_DIR}"
[[ -d "$BACKUP_ROOT" ]] && echo "Previous versions saved in: ${BACKUP_ROOT}"
echo "Start a new Claude Code session to load them."
