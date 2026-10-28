# shellcheck shell=bash
# Requirement checks that run before the installer writes anything.

check_terminal() {
  CURRENT_STEP="checking the terminal"
  (( ASSUME_YES )) && return 0
  # INSTALL_ASSUME_TTY is reserved for tests/install_test.sh, which pipes its answers in.
  [[ -t 0 || ${INSTALL_ASSUME_TTY:-0} == 1 ]] && return 0
  ui_error "This installer asks questions, so it needs a terminal."
  ui_info "Run it in a terminal, or use: bash install.sh --yes" >&2
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
    ui_info "Then run again:  bash install.sh"
  } >&2
  exit 1
}

# Tells the user what state the machine is in after an early stop.
explain_state_after_stop() {
  if (( NOTHING_WRITTEN )); then
    ui_info "Nothing was changed." >&2
  elif [[ -n ${BACKUP_DIR} ]]; then
    ui_info "Your backup is in $(pretty_path "${BACKUP_DIR}")" >&2
    ui_info "To restore it: cp -a \"${BACKUP_DIR}/.\" ~/.claude/" >&2
  fi
}
