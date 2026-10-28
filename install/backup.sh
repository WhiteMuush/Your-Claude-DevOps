# shellcheck shell=bash
# Optional backup of the existing configuration into ~/.claude-backups before anything is replaced.

readonly BACKUP_ITEMS=(CLAUDE.md settings.json skills hooks shell)

offer_backup() {
  CURRENT_STEP="the backup"
  local found=() name
  for name in "${BACKUP_ITEMS[@]}"; do
    [[ -e ${CLAUDE_DIR}/${name} ]] && found+=("${name}")
  done

  ui_title "Before you start: backup"
  if (( ! ${#found[@]} )); then
    ui_explain "No existing configuration was found in ~/.claude, so there is nothing to back up."
    return 0
  fi

  ui_explain "A backup copies your current files to ~/.claude-backups/ so you can put them back later."
  ui_info "Found in ~/.claude: ${found[*]}"
  if ui_confirm "Back up your current config first?" y; then
    create_backup "${found[@]}"
  else
    ui_kept "No backup made."
  fi
}

create_backup() {
  local name
  mkdir -p "${BACKUP_ROOT}"
  chmod 700 "${BACKUP_ROOT}"
  BACKUP_DIR=$(mktemp -d "${BACKUP_ROOT}/$(date +%Y-%m-%d_%H%M%S).XXXX")
  NOTHING_WRITTEN=0
  for name in "$@"; do
    cp -a "${CLAUDE_DIR}/${name}" "${BACKUP_DIR}/"
  done
  ui_ok "Backup saved to $(pretty_path "${BACKUP_DIR}")"
}
