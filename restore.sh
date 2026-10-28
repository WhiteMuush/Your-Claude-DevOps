#!/usr/bin/env bash
# Puts the Claude Code configuration back exactly as it was in one of the backups made by install.sh.
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLAUDE_DIR="${HOME}/.claude"
BACKUP_ROOT="${HOME}/.claude-backups"
ZSHRC="${HOME}/.zshrc"
WRAPPER="${CLAUDE_DIR}/shell/claude-herdr.zsh"
readonly REPO_DIR CLAUDE_DIR BACKUP_ROOT ZSHRC WRAPPER

ASSUME_YES=0
CURRENT_STEP="starting"
NOTHING_WRITTEN=1
BACKUP_DIR=""
UI_ANSWER=""
EXISTING_ITEMS=()
TMP_PATHS=()
RESTORE_FROM=""
RESTORE_TO=""
BACKUPS=()
SOURCE_DIR=""
PLAN_PUT_BACK=()
PLAN_REMOVE=()
PLAN_ZSHRC=""

# shellcheck source=install/ui.sh
source "${REPO_DIR}/install/ui.sh"
# shellcheck source=install/checks.sh
source "${REPO_DIR}/install/checks.sh"
# shellcheck source=install/backup.sh
source "${REPO_DIR}/install/backup.sh"
# shellcheck source=install/files.sh
source "${REPO_DIR}/install/files.sh"
# shellcheck source=install/restore.sh
source "${REPO_DIR}/install/restore.sh"

usage() {
  cat <<'EOF'
Usage: ./restore.sh

  Lists the backups in ~/.claude-backups, shows what will change,
  and asks before putting one back. Your current config is saved first.

Exit codes: 0 done, 1 error, 2 bad option, 3 cancelled, 130 stopped with Ctrl+C
EOF
}

parse_args() {
  case ${1:-} in
    '') ;;
    -h|--help) usage; exit 0 ;;
    *) usage >&2; exit 2 ;;
  esac
}

main() {
  parse_args "$@"
  ui_init
  trap on_exit EXIT
  trap 'exit 130' INT

  check_terminal ""
  check_dependencies
  show_restore_intro
  find_backups
  choose_backup
  plan_restore
  show_plan
  confirm_restore
  apply_restore
  show_restore_summary
}

main "$@"
