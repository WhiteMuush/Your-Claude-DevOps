# shellcheck shell=bash
# Screens of restore.sh: pick a backup, show what will change, then put ~/.claude back exactly as it was.

show_restore_intro() {
  ui_title "Restore a backup"
  ui_explain "This puts ~/.claude back exactly as it was in one of your backups."
  ui_explain "Never touched: your memory notes and the herdr program itself."
}

# Fills BACKUPS with the backup folders, newest first, keeping 9 so each one fits a single key.
find_backups() {
  CURRENT_STEP="looking for backups"
  local all=() dir i
  for dir in "${BACKUP_ROOT}"/*/; do
    [[ -d ${dir} ]] && all+=("${dir%/}")
  done
  BACKUPS=()
  i=${#all[@]}
  while (( i > 0 && ${#BACKUPS[@]} < 9 )); do
    i=$((i - 1))
    BACKUPS+=("${all[i]}")
  done
  (( ${#BACKUPS[@]} )) || die "No backup found in ~/.claude-backups. The installer makes one when you answer yes to its backup question."
}

# Prints a one-line description of a backup, stdout is the return value.
describe_backup() {
  local dir=$1 date reason items name
  date=$(backup_value "${dir}" date "$(basename "${dir}")")
  case $(backup_value "${dir}" reason unknown) in
    install) reason="made by the installer" ;;
    before-restore) reason="your config just before a restore" ;;
    *) reason="origin unknown" ;;
  esac
  items=""
  for name in "${BACKUP_ITEMS[@]}"; do
    [[ -e ${dir}/${name} ]] && items+="${name} "
  done
  printf '%s, %s  %s(%s)%s' "${date}" "${reason}" "${C_DIM}" "${items% }" "${C_RESET}"
}

choose_backup() {
  CURRENT_STEP="step 1, choosing a backup"
  local i=0 keys="" dir label
  ui_title "Step 1/3: Choose a backup"
  ui_explain "Each backup is a copy of ~/.claude taken at the date shown. The newest is first."
  printf '\n'
  for dir in "${BACKUPS[@]}"; do
    i=$((i + 1))
    keys+=${i}
    label=$(describe_backup "${dir}")
    (( i == 1 )) && label="${label}  latest"
    ui_info "${i}. ${label}"
  done
  printf '\n'
  ui_ask "Which one? (Enter = 1)" "${keys}" 1
  SOURCE_DIR=${BACKUPS[UI_ANSWER - 1]}
}

same_as_backup() {
  [[ -e $2 ]] && diff -rq "${DIFF_EXCLUDES[@]}" "$1" "$2" >/dev/null 2>&1
}

# Prints the entries of a current folder that the backup does not have, stdout is the return value.
added_since() {
  local saved=$1 current=$2 path names=""
  [[ -d ${saved} && -d ${current} ]] || return 0
  for path in "${current}"/*; do
    [[ -e ${path} && ! -e ${saved}/$(basename "${path}") ]] && names+="$(basename "${path}") "
  done
  printf '%s' "${names% }"
}

plan_restore() {
  CURRENT_STEP="preparing the restore"
  local name saved current wrapper_then
  PLAN_PUT_BACK=()
  PLAN_REMOVE=()
  PLAN_ZSHRC=""
  for name in "${BACKUP_ITEMS[@]}"; do
    saved="${SOURCE_DIR}/${name}"
    current="${CLAUDE_DIR}/${name}"
    if [[ -e ${saved} ]]; then
      same_as_backup "${saved}" "${current}" || PLAN_PUT_BACK+=("${name}")
    elif [[ -e ${current} ]]; then
      PLAN_REMOVE+=("${name}")
    fi
  done

  # Backups made before backup.info existed say nothing about ~/.zshrc, so it is left alone.
  wrapper_then=$(backup_value "${SOURCE_DIR}" zshrc_wrapper unknown)
  if [[ ${wrapper_then} == 0 ]] && zshrc_loads_wrapper; then
    PLAN_ZSHRC=remove
  elif [[ ${wrapper_then} == 1 ]] && ! zshrc_loads_wrapper; then
    PLAN_ZSHRC=add
  fi
}

# Lists at most 5 of the entries that the restore removes, one per line, so the list stays readable.
show_added() {
  local names=() name shown=0
  read -r -a names <<<"$1"
  ui_explain "            removes ${#names[@]} added since that date:"
  for name in "${names[@]}"; do
    (( shown == 5 )) && break
    ui_explain "              - ${name}"
    shown=$((shown + 1))
  done
  (( ${#names[@]} > 5 )) && ui_explain "              and $(( ${#names[@]} - 5 )) more"
  return 0
}

show_plan() {
  CURRENT_STEP="step 2, showing the changes"
  local name added
  ui_title "Step 2/3: What will change"
  ui_explain "Your ~/.claude goes back to how it was on $(backup_value "${SOURCE_DIR}" date "$(basename "${SOURCE_DIR}")")."
  printf '\n'

  if (( ! ${#PLAN_PUT_BACK[@]} && ! ${#PLAN_REMOVE[@]} )) && [[ -z ${PLAN_ZSHRC} ]]; then
    ui_ok "Your config already matches this backup. Nothing to do."
    exit 0
  fi

  if (( ${#PLAN_PUT_BACK[@]} )); then
    for name in "${PLAN_PUT_BACK[@]}"; do
      ui_info "Put back  ${name}"
      added=$(added_since "${SOURCE_DIR}/${name}" "${CLAUDE_DIR}/${name}")
      [[ -n ${added} ]] && show_added "${added}"
    done
  fi
  if (( ${#PLAN_REMOVE[@]} )); then
    for name in "${PLAN_REMOVE[@]}"; do
      ui_info "Remove    ${name}  (it did not exist at that date)"
    done
  fi
  [[ ${PLAN_ZSHRC} == remove ]] && ui_info "Remove    the herdr line in ~/.zshrc"
  [[ ${PLAN_ZSHRC} == add ]] && ui_info "Add back  the herdr line in ~/.zshrc"
  printf '\n'
  ui_explain "Your current config is saved first, so you can undo this restore."
  return 0
}

confirm_restore() {
  CURRENT_STEP="the confirmation"
  printf '\n'
  if ! ui_confirm "Restore this backup?" n; then
    ui_info "Cancelled. Nothing was changed."
    exit 3
  fi
}

remove_zshrc_wrapper() {
  local tmp
  tmp=$(mktemp "${TMPDIR:-/tmp}/zshrc.XXXX")
  TMP_PATHS+=("${tmp}")
  grep -vF -e "${ZSHRC_MARKER}" -e "source \"${WRAPPER}\"" "${ZSHRC}" >"${tmp}" || true
  NOTHING_WRITTEN=0
  # Writing through cat keeps the file's permissions and any symlink to a dotfiles repository.
  cat "${tmp}" >"${ZSHRC}"
}

add_zshrc_wrapper() {
  NOTHING_WRITTEN=0
  {
    printf '\n%s\n' "${ZSHRC_MARKER}"
    printf '[ -f "%s" ] && source "%s"\n' "${WRAPPER}" "${WRAPPER}"
  } >>"${ZSHRC}"
}

apply_restore() {
  CURRENT_STEP="step 3, restoring"
  local name
  ui_title "Step 3/3: Restore"
  existing_items
  if (( ${#EXISTING_ITEMS[@]} )); then
    create_backup before-restore "${EXISTING_ITEMS[@]}"
  fi

  if (( ${#PLAN_PUT_BACK[@]} )); then
    for name in "${PLAN_PUT_BACK[@]}"; do
      copy_into_place "${SOURCE_DIR}/${name}" "${CLAUDE_DIR}/${name}"
      ui_ok "Put back ${name}"
    done
  fi
  if (( ${#PLAN_REMOVE[@]} )); then
    for name in "${PLAN_REMOVE[@]}"; do
      NOTHING_WRITTEN=0
      rm -rf "${CLAUDE_DIR:?}/${name}"
      ui_ok "Removed ${name}"
    done
  fi
  case ${PLAN_ZSHRC} in
    remove) remove_zshrc_wrapper; ui_ok "Removed the herdr line from ~/.zshrc" ;;
    add) add_zshrc_wrapper; ui_ok "Added the herdr line back to ~/.zshrc" ;;
  esac
}

show_restore_summary() {
  CURRENT_STEP="the summary"
  ui_title "Done"
  ui_info "Your ~/.claude is back to how it was on $(backup_value "${SOURCE_DIR}" date "$(basename "${SOURCE_DIR}")")."
  if [[ -n ${BACKUP_DIR} ]]; then
    ui_explain "The config you had just before is saved in $(pretty_path "${BACKUP_DIR}")."
    ui_explain "To undo this restore, run bash restore.sh again and pick choice 1."
  fi
  printf '\n'
  ui_info "Restart Claude Code to load it."
  printf '\n'
}
