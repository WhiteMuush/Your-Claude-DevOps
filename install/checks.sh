# shellcheck shell=bash
# Requirement checks that run before the installer writes anything.

check_terminal() {
  local fallback=${1:-}
  CURRENT_STEP="checking the terminal"
  (( ASSUME_YES )) && return 0
  # INSTALL_ASSUME_TTY is reserved for the tests in tests/, which pipe their answers in.
  [[ -t 0 || ${INSTALL_ASSUME_TTY:-0} == 1 ]] && return 0
  ui_error "This script asks questions, so it needs a terminal."
  if [[ -n ${fallback} ]]; then
    ui_info "Run it in a terminal, or use: ${fallback}" >&2
  else
    ui_info "Run it in a terminal." >&2
  fi
  exit 1
}

check_dependencies() {
  CURRENT_STEP="checking the requirements"
  local missing=() dep
  for dep in jq diff cmp; do
    command -v "${dep}" >/dev/null 2>&1 || missing+=("${dep}")
  done
  (( ${#missing[@]} )) || return 0

  ui_error "Missing tools: ${missing[*]}"
  {
    ui_info "Debian / Ubuntu: sudo apt update && sudo apt install -y jq diffutils"
    ui_info "Fedora:          sudo dnf install -y jq diffutils"
    ui_info "Arch:            sudo pacman -S --needed jq diffutils"
    ui_info "macOS:           brew install jq"
    ui_info "Then run again:  ./install.sh"
  } >&2
  exit 1
}

# Tells the user what state the machine is in after an early stop.
explain_state_after_stop() {
  if (( NOTHING_WRITTEN )); then
    ui_info "Nothing was changed." >&2
  elif [[ -n ${BACKUP_DIR} ]]; then
    ui_info "Your backup is in $(pretty_path "${BACKUP_DIR}")" >&2
    ui_info "To put it back: ./restore.sh" >&2
  fi
}

on_exit() {
  local status=$?
  cleanup_temp_paths
  case ${status} in
    0|2|3) ;;
    130) ui_warn "Stopped with Ctrl+C during: ${CURRENT_STEP}."; explain_state_after_stop ;;
    *) ui_error "Stopped during: ${CURRENT_STEP}."; explain_state_after_stop ;;
  esac
  exit "${status}"
}
