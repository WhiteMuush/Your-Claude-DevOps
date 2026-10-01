# claude-herdr: `claude` opens herdr with Claude on the left and an empty shell on the right.
_claude_herdr_layout() {
  local root i
  for i in {1..50}; do
    root=$(herdr workspace create --cwd "$PWD" --label "${PWD:t}" --focus 2>/dev/null | jq -r '.result.root_pane.pane_id // empty')
    [[ -n $root ]] && break
    sleep 0.2
  done
  [[ -z $root ]] && return 1
  herdr pane split "$root" --direction right --cwd "$PWD" --no-focus >/dev/null
  herdr pane run "$root" "claude ${(j: :)${(q)@}}" >/dev/null
  sleep 1
  herdr workspace focus "${root%%:*}" >/dev/null
}

claude() {
  if [[ $HERDR_ENV == 1 || ! -t 0 || ! -t 1 ]] || (( ! $+commands[herdr] || ! $+commands[jq] )) \
    || (( ${argv[(I)(-p|--print|-v|--version|-h|--help|--bg|--output-format(|=*)|--input-format(|=*))]} )) \
    || [[ $1 == (agents|attach|auth|auto-mode|config|doctor|gateway|import|install|kill|logs|mcp|migrate-installer|plugin|plugins|project|respawn|rm|setup-token|stop|ultrareview|update|upgrade) ]]; then
    command claude "$@"
    return
  fi
  _claude_herdr_layout "$@" &>/dev/null &!
  herdr
}
