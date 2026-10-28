# shellcheck shell=bash
# Terminal output helpers for the installer: colors, step titles, questions and the final summary.

ui_init() {
  if [[ -t 1 && -z ${NO_COLOR:-} ]]; then
    C_RESET=$'\033[0m' C_BOLD=$'\033[1m' C_DIM=$'\033[90m'
    C_GREEN=$'\033[32m' C_YELLOW=$'\033[33m' C_RED=$'\033[31m' C_BLUE=$'\033[34m'
  else
    C_RESET='' C_BOLD='' C_DIM='' C_GREEN='' C_YELLOW='' C_RED='' C_BLUE=''
  fi
}

ui_title() { printf '\n%s%s%s%s\n\n' "${C_BOLD}" "${C_BLUE}" "$1" "${C_RESET}"; }
ui_explain() { printf '  %s%s%s\n' "${C_DIM}" "$1" "${C_RESET}"; }
ui_info() { printf '  %s\n' "$1"; }
ui_ok() { printf '  %s✔%s %s\n' "${C_GREEN}" "${C_RESET}" "$1"; }
ui_kept() { printf '  %s•%s %s\n' "${C_YELLOW}" "${C_RESET}" "$1"; }
ui_warn() { printf '  %s! %s%s\n' "${C_YELLOW}" "$1" "${C_RESET}" >&2; }
ui_error() { printf '  %s✖ %s%s\n' "${C_RED}" "$1" "${C_RESET}" >&2; }

die() {
  ui_error "$1"
  exit 1
}

# Prints the path with the home folder shown as ~, stdout is the return value.
pretty_path() { printf '%s' "${1/#${HOME}/\~}"; }

# Sets UI_ANSWER to one of the allowed letters, taking the default on Enter or with --yes.
ui_ask() {
  local prompt=$1 allowed=$2 default=$3 reply
  if (( ASSUME_YES )); then
    UI_ANSWER=${default}
    printf '  %s %s(--yes: %s)%s\n' "${prompt}" "${C_DIM}" "${default}" "${C_RESET}"
    return 0
  fi
  while true; do
    printf '  %s%s%s ' "${C_YELLOW}" "${prompt}" "${C_RESET}"
    IFS= read -r reply || die "No answer received, stopping."
    reply=$(printf '%s' "${reply}" | tr '[:upper:]' '[:lower:]')
    reply=${reply:-${default}}
    if [[ ${#reply} -eq 1 && ${allowed} == *"${reply}"* ]]; then
      UI_ANSWER=${reply}
      return 0
    fi
    ui_warn "Please type $(printf '%s' "${allowed}" | sed 's/./& or /g; s/ or $//')."
  done
}

# Asks a yes/no question and succeeds when the answer is yes.
ui_confirm() {
  local question=$1 default=$2 hint="[Y/n]"
  [[ ${default} == n ]] && hint="[y/N]"
  ui_ask "${question} ${hint}" yn "${default}"
  [[ ${UI_ANSWER} == y ]]
}

# Records one outcome for the final summary, called directly so the array survives.
record() { SUMMARY+=("$1|$2"); }

summary_names() {
  local outcome=$1 entry names=()
  (( ${#SUMMARY[@]} )) || return 0
  for entry in "${SUMMARY[@]}"; do
    [[ ${entry%%|*} == "${outcome}" ]] && names+=("${entry#*|}")
  done
  (( ${#names[@]} )) || return 0
  printf '%s' "${names[*]}"
}

summary_count() {
  local outcome=$1 entry count=0
  (( ${#SUMMARY[@]} )) || { printf '0'; return 0; }
  for entry in "${SUMMARY[@]}"; do
    [[ ${entry%%|*} == "${outcome}" ]] && count=$((count + 1))
  done
  printf '%s' "${count}"
}

ui_summary_line() {
  local outcome=$1 label=$2 with_names=$3 count names
  count=$(summary_count "${outcome}")
  (( count )) || return 0
  if (( with_names )); then
    names=$(summary_names "${outcome}")
    printf '  %-10s %3s  %s%s%s\n' "${label}" "${count}" "${C_DIM}" "${names}" "${C_RESET}"
  else
    printf '  %-10s %3s\n' "${label}" "${count}"
  fi
}
