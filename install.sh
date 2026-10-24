#!/usr/bin/env bash
# Install Frappe/ERPNext Agent Skills for Claude Code and OpenAI Codex.
#
# Usage:
#   bash install.sh                         # Claude, user-level
#   bash install.sh --agent codex            # Codex, user-level
#   bash install.sh --agent both             # Claude + Codex, user-level
#   bash install.sh --project /path/to/repo  # Claude, project-level
#   bash install.sh --agent both --project /path/to/repo
#   bash install.sh --dry-run [other options]
#   bash install.sh --only frappe-core,frappe-api
#   bash install.sh --list
#
# Claude user skills:  ~/.claude/skills
# Codex user skills:   ~/.agents/skills
# Project skills:      <project>/.claude/skills and/or <project>/.agents/skills
# Existing same-name skills are moved to a timestamped backup outside active skill dirs.
set -Eeuo pipefail

SOURCE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AGENT="claude"
PROJECT_DIR=""
DRY=0
ONLY=""
LIST=0

usage() {
  cat <<'USAGE'
Install Frappe/ERPNext Agent Skills

Options:
  --agent NAME       claude | codex | both (default: claude)
  --project DIR      Install into project-level skill directories; DIR must exist
  --dry-run          Preview actions without creating, moving, or copying files
  --only LIST        Comma-separated skill directory names to install
  --list             List skills found in this repository; do not install
  -h, --help         Show this help

Examples:
  bash install.sh
  bash install.sh --agent both
  bash install.sh --agent codex --dry-run
  bash install.sh --agent both --project "$PWD"
  bash install.sh --only frappe-core,frappe-api
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --agent)
      [[ $# -ge 2 ]] || { echo "ERROR: --agent needs claude, codex, or both" >&2; exit 2; }
      AGENT="$2"; shift 2 ;;
    --project)
      [[ $# -ge 2 ]] || { echo "ERROR: --project needs a directory" >&2; exit 2; }
      PROJECT_DIR="$2"; shift 2 ;;
    --dry-run) DRY=1; shift ;;
    --only)
      [[ $# -ge 2 ]] || { echo "ERROR: --only needs a comma-separated list" >&2; exit 2; }
      ONLY=",$2,"; shift 2 ;;
    --list) LIST=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "ERROR: Unknown option: $1" >&2; usage >&2; exit 2 ;;
  esac
done

case "$AGENT" in
  claude|codex|both) ;;
  *) echo "ERROR: Invalid agent '$AGENT'. Use claude, codex, or both." >&2; exit 2 ;;
esac

if [[ -n "$PROJECT_DIR" ]]; then
  [[ -d "$PROJECT_DIR" ]] || { echo "ERROR: Project directory does not exist: $PROJECT_DIR" >&2; exit 2; }
  PROJECT_DIR="$(cd "$PROJECT_DIR" && pwd)"
fi

mapfile -t SKILL_DIRS < <(find "$SOURCE_DIR" -mindepth 2 -maxdepth 2 -type f -name SKILL.md -printf '%h\n' | sort)
if [[ ${#SKILL_DIRS[@]} -eq 0 ]]; then
  echo "ERROR: No skill directories containing SKILL.md found in $SOURCE_DIR" >&2
  exit 1
fi

if [[ $LIST -eq 1 ]]; then
  printf 'Skills found in %s:\n' "$SOURCE_DIR"
  for path in "${SKILL_DIRS[@]}"; do basename "$path"; done
  exit 0
fi

if [[ -n "$ONLY" ]]; then
  IFS=',' read -r -a requested <<< "${ONLY#,}"
  requested_count=0
  for item in "${requested[@]}"; do
    [[ -n "$item" ]] || continue
    found=0
    for path in "${SKILL_DIRS[@]}"; do
      [[ "$(basename "$path")" == "$item" ]] && found=1
    done
    if [[ $found -eq 0 ]]; then
      echo "ERROR: Requested skill not found: $item" >&2
      exit 2
    fi
    requested_count=$((requested_count + 1))
  done
  [[ $requested_count -gt 0 ]] || { echo "ERROR: --only list is empty" >&2; exit 2; }
fi

STAMP="$(date +%Y%m%d-%H%M%S)"
INSTALLED_TOTAL=0

say_or_run() {
  if [[ $DRY -eq 1 ]]; then
    printf '[dry-run]'
    printf ' %q' "$@"
    printf '\n'
  else
    "$@"
  fi
}

install_to() {
  local target_dir="$1"
  local label="$2"
  local backup_root="$(dirname "$target_dir")/skills-backup/$STAMP"
  local count=0

  echo
  echo "Target ($label): $target_dir"
  say_or_run mkdir -p "$target_dir"

  for skill_path in "${SKILL_DIRS[@]}"; do
    local name target
    name="$(basename "$skill_path")"
    if [[ -n "$ONLY" && "$ONLY" != *",$name,"* ]]; then continue; fi
    target="$target_dir/$name"

    if [[ -e "$target" || -L "$target" ]]; then
      echo "Backup existing skill: $target -> $backup_root/$name"
      say_or_run mkdir -p "$backup_root"
      say_or_run mv "$target" "$backup_root/$name"
    fi

    echo "Install skill: $name"
    say_or_run cp -R "$skill_path" "$target"
    if [[ $DRY -eq 0 && -d "$target/scripts" ]]; then
      find "$target/scripts" -maxdepth 1 -type f -exec chmod u+x {} +
    fi
    count=$((count + 1))
  done

  echo "Planned/installed $count skill(s) for $label."
  if [[ $DRY -eq 0 && -d "$backup_root" ]]; then
    echo "Backup location ($label): $backup_root"
  elif [[ $DRY -eq 1 ]]; then
    echo "Backup location if needed ($label): $backup_root"
  fi
  INSTALLED_TOTAL=$((INSTALLED_TOTAL + count))
}

if [[ "$AGENT" == "claude" || "$AGENT" == "both" ]]; then
  if [[ -n "$PROJECT_DIR" ]]; then
    install_to "$PROJECT_DIR/.claude/skills" "Claude Code project"
  else
    install_to "$HOME/.claude/skills" "Claude Code user"
  fi
fi

if [[ "$AGENT" == "codex" || "$AGENT" == "both" ]]; then
  if [[ -n "$PROJECT_DIR" ]]; then
    install_to "$PROJECT_DIR/.agents/skills" "Codex project"
  else
    install_to "$HOME/.agents/skills" "Codex user"
  fi
fi

echo
echo "Total skill installations planned/completed: $INSTALLED_TOTAL"
if [[ $DRY -eq 1 ]]; then
  echo "Dry run only: no files were changed."
else
  echo "Done. Start a new agent session to discover the installed skills."
fi