# shellcheck shell=bash
# Backups of the configuration in ~/.claude-backups, each with a backup.info file that restore.sh reads.

readonly BACKUP_ITEMS=(CLAUDE.md settings.json skills hooks shell)
readonly BACKUP_INFO=backup.info
readonly ZSHRC_MARKER="# claude opens a herdr workspace (Your-Claude-DevOps)"

offer_backup() {
  CURRENT_STEP="the backup"
  existing_items

  ui_title "Before you start: backup"
  if (( ! ${#EXISTING_ITEMS[@]} )); then
    ui_explain "No existing configuration was found in ~/.claude, so there is nothing to back up."
    return 0
  fi

  ui_explain "A backup copies your current files to ~/.claude-backups/ so you can put them back later."
  ui_info "Found in ~/.claude: ${EXISTING_ITEMS[*]}"
  if ui_confirm "Back up your current config first?" y; then
    create_backup install "${EXISTING_ITEMS[@]}"
  else
    ui_kept "No backup made."
  fi
}

# Sets EXISTING_ITEMS to the backup items that exist in ~/.claude right now.
existing_items() {
  local name
  EXISTING_ITEMS=()
  for name in "${BACKUP_ITEMS[@]}"; do
    [[ -e ${CLAUDE_DIR}/${name} ]] && EXISTING_ITEMS+=("${name}")
  done
  return 0
}

zshrc_loads_wrapper() { grep -qF "${WRAPPER}" "${ZSHRC}" 2>/dev/null; }

# Copies the given items into a new backup folder, the first argument says why the backup was made.
create_backup() {
  local reason=$1 name wrapper=0 stamp count=1
  shift
  mkdir -p "${BACKUP_ROOT}"
  chmod 700 "${BACKUP_ROOT}"
  # A counter instead of random letters keeps two backups made in the same second in the right order.
  stamp=$(date +%Y-%m-%d_%H%M%S)
  until mkdir "${BACKUP_ROOT}/${stamp}-$(printf '%02d' "${count}")" 2>/dev/null; do
    count=$((count + 1))
    (( count < 100 )) || die "Could not create a backup folder in ~/.claude-backups."
  done
  BACKUP_DIR="${BACKUP_ROOT}/${stamp}-$(printf '%02d' "${count}")"
  chmod 700 "${BACKUP_DIR}"
  NOTHING_WRITTEN=0
  for name in "$@"; do
    cp -a "${CLAUDE_DIR}/${name}" "${BACKUP_DIR}/"
  done
  zshrc_loads_wrapper && wrapper=1
  {
    printf 'date=%s\n' "$(date '+%Y-%m-%d %H:%M')"
    printf 'reason=%s\n' "${reason}"
    printf 'items=%s\n' "$*"
    printf 'zshrc_wrapper=%s\n' "${wrapper}"
  } >"${BACKUP_DIR}/${BACKUP_INFO}"
  ui_ok "Backup saved to $(pretty_path "${BACKUP_DIR}")"
}

# Prints one value from a backup's backup.info, or the given fallback when it is missing.
backup_value() {
  local dir=$1 key=$2 fallback=$3 line
  line=$(grep -m1 "^${key}=" "${dir}/${BACKUP_INFO}" 2>/dev/null || true)
  if [[ -n ${line} ]]; then printf '%s' "${line#*=}"; else printf '%s' "${fallback}"; fi
}
