# shellcheck shell=bash
# Optional herdr setup: the binary, the zsh wrapper and the Claude Code hook.

# Succeeds when curl, jq and zsh are present, otherwise prints how to get them.
check_herdr_dependencies() {
  local missing=() dep
  for dep in curl jq zsh; do
    command -v "${dep}" >/dev/null 2>&1 || missing+=("${dep}")
  done
  (( ${#missing[@]} )) || return 0

  ui_warn "herdr needs these tools, which are missing: ${missing[*]}"
  {
    ui_info "Debian / Ubuntu: sudo apt update && sudo apt install -y ${missing[*]}"
    ui_info "Fedora:          sudo dnf install -y ${missing[*]}"
    ui_info "Arch:            sudo pacman -S --needed ${missing[*]}"
    ui_info "Then run again:  bash install.sh --herdr"
  } >&2
  return 1
}

ensure_herdr() {
  if command -v herdr >/dev/null 2>&1; then
    ui_ok "herdr is already installed ($(herdr --version))"
  elif command -v brew >/dev/null 2>&1; then
    brew install herdr
    ui_ok "Installed herdr with Homebrew"
  else
    # The official script checks the SHA-256 and puts the binary in ~/.local/bin.
    curl -fsSL https://herdr.dev/install.sh | sh
    export PATH="${HOME}/.local/bin:${PATH}"
    command -v herdr >/dev/null 2>&1 || die "herdr was not found after the install, check that ~/.local/bin is in your PATH."
    ui_ok "Installed herdr in ~/.local/bin"
  fi
}

install_wrapper() {
  copy_into_place "${REPO_DIR}/shell/claude-herdr.zsh" "${WRAPPER}"
  ui_ok "Copied the wrapper to $(pretty_path "${WRAPPER}")"

  if grep -qF "${WRAPPER}" "${ZSHRC}" 2>/dev/null; then
    ui_ok "$(pretty_path "${ZSHRC}") already loads the wrapper"
  else
    {
      printf '\n%s\n' "${ZSHRC_MARKER}"
      printf '[ -f "%s" ] && source "%s"\n' "${WRAPPER}" "${WRAPPER}"
    } >>"${ZSHRC}"
    ui_ok "Added one line to $(pretty_path "${ZSHRC}") to load the wrapper"
  fi
}

ensure_herdr_hook() {
  herdr integration install claude >/dev/null
  ui_ok "Added the herdr hook to ~/.claude/settings.json"
}
