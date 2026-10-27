#!/usr/bin/env bash
# Installs this repository's Claude Code configuration into ~/.claude.
# Idempotent: safe to run again.
# Usage: bash install.sh [--herdr]
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLAUDE_DIR="$HOME/.claude"
ZSHRC="$HOME/.zshrc"
WRAPPER="$CLAUDE_DIR/shell/claude-herdr.zsh"
readonly REPO_DIR CLAUDE_DIR ZSHRC WRAPPER

usage() {
  echo "Usage: bash install.sh [--herdr]"
  echo "  --herdr  also installs herdr and the wrapper that opens claude in a herdr workspace"
}

die() {
  echo "  [error] $*" >&2
  exit 1
}

install_config() {
  echo "==> Installing the Claude Code configuration into $CLAUDE_DIR"
  mkdir -p "$CLAUDE_DIR/skills" "$CLAUDE_DIR/hooks"

  cp "$REPO_DIR/CLAUDE.md" "$CLAUDE_DIR/CLAUDE.md"
  echo "  [ok] CLAUDE.md"

  # settings.json holds no machine path, so it is copied as is
  cp "$REPO_DIR/settings.json" "$CLAUDE_DIR/settings.json"
  echo "  [ok] settings.json"

  cp -r "$REPO_DIR/skills/." "$CLAUDE_DIR/skills/"
  echo "  [ok] skills ($(find "$CLAUDE_DIR/skills" -mindepth 1 -maxdepth 1 -type d | wc -l) folders)"

  cp -r "$REPO_DIR/hooks/." "$CLAUDE_DIR/hooks/"
  echo "  [ok] hooks"
}

install_memory() {
  # Project key derived from HOME (/home/alice -> -home-alice)
  local memkey mem_dir
  memkey="$(echo "$HOME" | tr '/' '-')"
  mem_dir="$CLAUDE_DIR/projects/$memkey/memory"
  mkdir -p "$mem_dir"
  cp "$REPO_DIR/memory/"*.md "$mem_dir/"
  echo "  [ok] memory -> projects/$memkey/memory"
}

check_herdr_deps() {
  local missing=() dep
  for dep in curl jq zsh; do
    command -v "$dep" >/dev/null 2>&1 || missing+=("$dep")
  done
  [[ ${#missing[@]} -eq 0 ]] && return 0

  {
    echo "  [error] missing dependencies for herdr: ${missing[*]}"
    echo "    Debian / Ubuntu: sudo apt update && sudo apt install -y ${missing[*]}"
    echo "    Fedora:          sudo dnf install -y ${missing[*]}"
    echo "    Arch:            sudo pacman -S --needed ${missing[*]}"
    echo "    Then run again: bash install.sh --herdr"
  } >&2
  exit 1
}

ensure_herdr() {
  if command -v herdr >/dev/null 2>&1; then
    echo "  [ok] herdr already installed ($(herdr --version))"
  elif command -v brew >/dev/null 2>&1; then
    brew install herdr
    echo "  [ok] herdr installed with Homebrew"
  else
    # Official script: checks the SHA-256 and puts the binary in ~/.local/bin
    curl -fsSL https://herdr.dev/install.sh | sh
    export PATH="$HOME/.local/bin:$PATH"
    command -v herdr >/dev/null 2>&1 || die "herdr not found after install, check that ~/.local/bin is in PATH"
    echo "  [ok] herdr installed in ~/.local/bin"
  fi
}

install_wrapper() {
  mkdir -p "$(dirname "$WRAPPER")"
  cp "$REPO_DIR/shell/claude-herdr.zsh" "$WRAPPER"
  echo "  [ok] wrapper -> ${WRAPPER/#$HOME/\~}"

  if grep -qF "$WRAPPER" "$ZSHRC" 2>/dev/null; then
    echo "  [ok] ~/.zshrc already sources the wrapper"
  else
    {
      echo ""
      echo "# claude opens a herdr workspace (Your-Claude-DevOps)"
      echo "[ -f \"$WRAPPER\" ] && source \"$WRAPPER\""
    } >>"$ZSHRC"
    echo "  [ok] wrapper sourced from ~/.zshrc"
  fi
}

# The herdr hook lives in settings.json, which install_config has just overwritten,
# so it is written again on every run as soon as herdr is present.
ensure_herdr_hook() {
  command -v herdr >/dev/null 2>&1 || return 0
  herdr integration install claude >/dev/null
  echo "  [ok] herdr hook in settings.json"
}

print_next_steps() {
  echo ""
  echo "==> Configuration copied. One thing left: the i-have-adhd plugin."
  echo "    settings.json already declares the marketplace, it installs itself when Claude Code starts."
  echo "    Otherwise, by hand in Claude Code:"
  echo "      /plugin marketplace add ayghri/i-have-adhd"
  echo "      /plugin install i-have-adhd"
  echo ""
  if [[ $1 == 1 ]]; then
    echo "==> Open a new terminal: 'claude' now starts herdr."
  fi
  echo "==> Restart Claude Code. The plugin loads at startup."
}

main() {
  local with_herdr=0
  while [[ $# -gt 0 ]]; do
    case $1 in
      --herdr) with_herdr=1 ;;
      -h|--help) usage; exit 0 ;;
      *) usage >&2; exit 2 ;;
    esac
    shift
  done

  # Check before writing anything, so an install is never left half done
  [[ $with_herdr == 1 ]] && check_herdr_deps

  install_config
  install_memory
  if [[ $with_herdr == 1 ]]; then
    ensure_herdr
    install_wrapper
  fi
  ensure_herdr_hook
  print_next_steps "$with_herdr"
}

main "$@"
