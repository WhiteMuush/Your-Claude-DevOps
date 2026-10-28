#!/usr/bin/env bash
# Interactive installer that copies this repository's Claude Code configuration into ~/.claude.
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLAUDE_DIR="${HOME}/.claude"
BACKUP_ROOT="${HOME}/.claude-backups"
ZSHRC="${HOME}/.zshrc"
WRAPPER="${CLAUDE_DIR}/shell/claude-herdr.zsh"
readonly REPO_DIR CLAUDE_DIR BACKUP_ROOT ZSHRC WRAPPER

ASSUME_YES=0
WANT_HERDR=0
CURRENT_STEP="starting"
NOTHING_WRITTEN=1
BACKUP_DIR=""
UI_ANSWER=""
SUMMARY=()
TMP_PATHS=()
RESTORE_FROM=""
RESTORE_TO=""

# shellcheck source=install/ui.sh
source "${REPO_DIR}/install/ui.sh"
# shellcheck source=install/checks.sh
source "${REPO_DIR}/install/checks.sh"
# shellcheck source=install/backup.sh
source "${REPO_DIR}/install/backup.sh"
# shellcheck source=install/files.sh
source "${REPO_DIR}/install/files.sh"
# shellcheck source=install/settings.sh
source "${REPO_DIR}/install/settings.sh"
# shellcheck source=install/herdr.sh
source "${REPO_DIR}/install/herdr.sh"
# shellcheck source=install/steps.sh
source "${REPO_DIR}/install/steps.sh"

usage() {
  cat <<'EOF'
Usage: bash install.sh [--yes] [--herdr]

  --yes    answer every question with its safe default: back up, install what
           is missing, keep your existing files, skip herdr
  --herdr  install herdr without asking

Exit codes: 0 done, 1 error, 2 bad option, 3 cancelled, 130 stopped with Ctrl+C
EOF
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case $1 in
      --yes) ASSUME_YES=1 ;;
      --herdr) WANT_HERDR=1 ;;
      -h|--help) usage; exit 0 ;;
      *) usage >&2; exit 2 ;;
    esac
    shift
  done
}

on_exit() {
  local status=$?
  cleanup_temp_paths
  case ${status} in
    0|2|3) ;;
    130) ui_warn "Stopped with Ctrl+C during: ${CURRENT_STEP}."; explain_state_after_stop ;;
    *) ui_error "The installer stopped during: ${CURRENT_STEP}."; explain_state_after_stop ;;
  esac
  exit "${status}"
}

main() {
  parse_args "$@"
  ui_init
  trap on_exit EXIT
  trap 'exit 130' INT

  check_terminal
  check_dependencies
  show_welcome
  confirm_start
  offer_backup
  step_claude_md
  step_settings
  step_skills
  step_hooks_and_memory
  step_herdr
  show_summary
}

main "$@"
