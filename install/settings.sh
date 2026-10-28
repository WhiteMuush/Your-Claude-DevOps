# shellcheck shell=bash
# Installs settings.json, with a merge that keeps every user value and adds only what is missing.

# User values win on conflict, objects merge key by key, arrays gain the repository items they lack.
# shellcheck disable=SC2016
readonly SETTINGS_MERGE_JQ='
def merge($user; $repo):
  if ($user | type) == "object" and ($repo | type) == "object" then
    reduce (($user | keys_unsorted) + [$repo | keys_unsorted[] | select(. as $k | $user | has($k) | not)])[] as $k
      ({}; .[$k] = if ($user | has($k)) and ($repo | has($k)) then merge($user[$k]; $repo[$k])
                   elif ($user | has($k)) then $user[$k]
                   else $repo[$k] end)
  elif ($user | type) == "array" and ($repo | type) == "array" then
    $user + [$repo[] | select(. as $item | any($user[]; . == $item) | not)]
  else $user end;
merge(.[0]; .[1])
'

merge_settings() {
  local src=$1 dst=$2 tmp
  tmp=$(mktemp "${CLAUDE_DIR}/.settings.json.merging.XXXX")
  TMP_PATHS+=("${tmp}")
  if ! jq -s "${SETTINGS_MERGE_JQ}" "${dst}" "${src}" >"${tmp}" 2>/dev/null || ! jq empty "${tmp}" 2>/dev/null; then
    ui_error "Your settings.json could not be read as JSON, so it was left unchanged."
    record kept settings.json
    return 0
  fi
  chmod 600 "${tmp}"
  NOTHING_WRITTEN=0
  mv -f "${tmp}" "${dst}"
  ui_ok "Merged settings.json: your values were kept and the missing ones were added"
  record merged settings.json
}

install_settings() {
  local src=$1 dst=$2 state
  state=$(item_state "${src}" "${dst}")
  case ${state} in
    missing)
      copy_into_place "${src}" "${dst}"
      chmod 600 "${dst}"
      ui_ok "Installed settings.json"
      record installed settings.json
      return 0
      ;;
    same)
      ui_ok "settings.json is already up to date"
      record unchanged settings.json
      return 0
      ;;
  esac

  ui_info "Your settings.json is different from the repository version."
  while true; do
    ui_ask "[m] merge  [r] replace  [k] keep  [d] diff  (Enter = keep) ?" mrkd k
    case ${UI_ANSWER} in
      m) merge_settings "${src}" "${dst}"; return 0 ;;
      r) copy_into_place "${src}" "${dst}"; chmod 600 "${dst}"; ui_ok "Replaced settings.json"; record replaced settings.json; return 0 ;;
      k) ui_kept "Kept your settings.json"; record kept settings.json; return 0 ;;
      d) show_diff "${src}" "${dst}" ;;
    esac
  done
}
