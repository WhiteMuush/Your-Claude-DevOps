# shellcheck shell=bash
# Compares and installs files or folders, asking the user before replacing a copy that differs.

readonly DIFF_EXCLUDES=(--exclude=__pycache__ --exclude=node_modules)

# Prints missing, same or different, stdout is the return value.
item_state() {
  local src=$1 dst=$2 changes
  if [[ ! -e ${dst} ]]; then
    printf 'missing'
  elif [[ -d ${src} ]]; then
    # Extra files that exist only in the installed copy do not count as a difference.
    changes=$(diff -rq "${DIFF_EXCLUDES[@]}" "${src}" "${dst}" 2>&1 | grep -vF "Only in ${dst}" || true)
    if [[ -z ${changes} ]]; then printf 'same'; else printf 'different'; fi
  elif cmp -s "${src}" "${dst}"; then
    printf 'same'
  else
    printf 'different'
  fi
}

# Copies next to the target first, then swaps, so a stop never leaves a half-written copy.
copy_into_place() {
  local src=$1 dst=$2 tmp
  tmp="$(dirname "${dst}")/.$(basename "${dst}").installing.$$"
  mkdir -p "$(dirname "${dst}")"
  TMP_PATHS+=("${tmp}")
  rm -rf "${tmp}"
  cp -a "${src}" "${tmp}"
  NOTHING_WRITTEN=0
  if [[ -d ${dst} && ! -L ${dst} ]]; then
    RESTORE_FROM="${tmp}.old" RESTORE_TO=${dst}
    mv "${dst}" "${RESTORE_FROM}"
    mv "${tmp}" "${dst}"
    rm -rf "${RESTORE_FROM}"
    RESTORE_FROM="" RESTORE_TO=""
  else
    mv -f "${tmp}" "${dst}"
  fi
}

cleanup_temp_paths() {
  local path
  if [[ -n ${RESTORE_FROM} && -e ${RESTORE_FROM} && ! -e ${RESTORE_TO} ]]; then
    mv "${RESTORE_FROM}" "${RESTORE_TO}"
  fi
  (( ${#TMP_PATHS[@]} )) || return 0
  for path in "${TMP_PATHS[@]}"; do
    rm -rf "${path}"
  done
}

show_diff() {
  local src=$1 dst=$2 line
  ui_explain "Lines starting with - are yours, lines starting with + come from the repository."
  printf '\n'
  # diff exits with 1 when the files differ, which pipefail would treat as a failure.
  { diff -ru "${DIFF_EXCLUDES[@]}" "${dst}" "${src}" 2>&1 || true; } | while IFS= read -r line; do
    case ${line} in
      ---*|+++*) printf '    %s%s%s\n' "${C_BOLD}" "${line}" "${C_RESET}" ;;
      -*) printf '    %s%s%s\n' "${C_RED}" "${line}" "${C_RESET}" ;;
      +*) printf '    %s%s%s\n' "${C_GREEN}" "${line}" "${C_RESET}" ;;
      *) printf '    %s\n' "${line}" ;;
    esac
  done
  printf '\n'
}

# Asks replace, keep or diff for one item that differs from the repository.
ask_replace() {
  local name=$1 src=$2 dst=$3
  ui_info "Your ${name} is different from the repository version."
  while true; do
    ui_ask "[r] replace  [k] keep  [d] diff  (Enter = keep) ?" rkd k
    case ${UI_ANSWER} in
      r) copy_into_place "${src}" "${dst}"; ui_ok "Replaced ${name}"; record replaced "${name}"; return 0 ;;
      k) ui_kept "Kept your ${name}"; record kept "${name}"; return 0 ;;
      d) show_diff "${src}" "${dst}" ;;
    esac
  done
}

handle_item() {
  local name=$1 src=$2 dst=$3 state
  state=$(item_state "${src}" "${dst}")
  case ${state} in
    missing) copy_into_place "${src}" "${dst}"; ui_ok "Installed ${name}"; record installed "${name}" ;;
    same) ui_ok "${name} is already up to date"; record unchanged "${name}" ;;
    different) ask_replace "${name}" "${src}" "${dst}" ;;
  esac
}

# Installs every entry of a repository folder, with one question for all the entries that differ.
handle_group() {
  local label=$1 src_dir=$2 dst_dir=$3 path name state
  local new=0 same=0 differing=()
  for path in "${src_dir}"/*; do
    [[ -e ${path} ]] || continue
    name=$(basename "${path}")
    state=$(item_state "${path}" "${dst_dir}/${name}")
    case ${state} in
      missing) copy_into_place "${path}" "${dst_dir}/${name}"; record installed "${label}/${name}"; new=$((new + 1)) ;;
      same) record unchanged "${label}/${name}"; same=$((same + 1)) ;;
      different) differing+=("${name}") ;;
    esac
  done

  (( new )) && ui_ok "${label}: ${new} installed"
  (( same )) && ui_ok "${label}: ${same} already up to date"
  (( ${#differing[@]} )) || return 0

  ui_info "${#differing[@]} ${label} differ from your installed version:"
  for name in "${differing[@]}"; do
    ui_info "  - ${name}"
  done
  ui_ask "[a] replace all  [k] keep all  [o] one by one  (Enter = keep all) ?" ako k
  case ${UI_ANSWER} in
    a)
      for name in "${differing[@]}"; do
        copy_into_place "${src_dir}/${name}" "${dst_dir}/${name}"
        record replaced "${label}/${name}"
      done
      ui_ok "Replaced ${#differing[@]} ${label}"
      ;;
    k)
      for name in "${differing[@]}"; do
        record kept "${label}/${name}"
      done
      ui_kept "Kept your ${#differing[@]} ${label}"
      ;;
    o)
      for name in "${differing[@]}"; do
        ask_replace "${label}/${name}" "${src_dir}/${name}" "${dst_dir}/${name}"
      done
      ;;
  esac
}
