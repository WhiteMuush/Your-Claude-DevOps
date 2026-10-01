#!/usr/bin/env bash
# Installe la config Claude Code de ce repo dans ~/.claude
# Idempotent : peut être relancé sans casser.
# Usage : bash install.sh [--herdr]
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLAUDE_DIR="$HOME/.claude"
ZSHRC="$HOME/.zshrc"
WRAPPER="$CLAUDE_DIR/shell/claude-herdr.zsh"
readonly REPO_DIR CLAUDE_DIR ZSHRC WRAPPER

usage() {
  echo "Usage : bash install.sh [--herdr]"
  echo "  --herdr  installe aussi herdr et le wrapper qui ouvre claude dans un workspace herdr"
}

die() {
  echo "  [erreur] $*" >&2
  exit 1
}

install_config() {
  echo "==> Installation de la config Claude Code dans $CLAUDE_DIR"
  mkdir -p "$CLAUDE_DIR/skills" "$CLAUDE_DIR/hooks"

  cp "$REPO_DIR/CLAUDE.md" "$CLAUDE_DIR/CLAUDE.md"
  echo "  [ok] CLAUDE.md"

  # settings.json : aucun chemin machine, copie directe
  cp "$REPO_DIR/settings.json" "$CLAUDE_DIR/settings.json"
  echo "  [ok] settings.json"

  cp -r "$REPO_DIR/skills/." "$CLAUDE_DIR/skills/"
  echo "  [ok] skills ($(find "$CLAUDE_DIR/skills" -mindepth 1 -maxdepth 1 -type d | wc -l) dossiers)"

  cp -r "$REPO_DIR/hooks/." "$CLAUDE_DIR/hooks/"
  echo "  [ok] hooks"
}

install_memory() {
  # Clé de projet dérivée du HOME (/home/alice -> -home-alice)
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
    echo "  [erreur] dépendances manquantes pour herdr : ${missing[*]}"
    echo "    Debian / Ubuntu : sudo apt update && sudo apt install -y ${missing[*]}"
    echo "    Fedora          : sudo dnf install -y ${missing[*]}"
    echo "    Arch            : sudo pacman -S --needed ${missing[*]}"
    echo "    Puis relancer : bash install.sh --herdr"
  } >&2
  exit 1
}

ensure_herdr() {
  if command -v herdr >/dev/null 2>&1; then
    echo "  [ok] herdr déjà installé ($(herdr --version))"
  elif command -v brew >/dev/null 2>&1; then
    brew install herdr
    echo "  [ok] herdr installé via Homebrew"
  else
    # Script officiel : vérifie le SHA-256 et pose le binaire dans ~/.local/bin
    curl -fsSL https://herdr.dev/install.sh | sh
    export PATH="$HOME/.local/bin:$PATH"
    command -v herdr >/dev/null 2>&1 || die "herdr introuvable après installation, vérifier que ~/.local/bin est dans le PATH"
    echo "  [ok] herdr installé dans ~/.local/bin"
  fi
}

install_wrapper() {
  mkdir -p "$(dirname "$WRAPPER")"
  cp "$REPO_DIR/shell/claude-herdr.zsh" "$WRAPPER"
  echo "  [ok] wrapper -> ${WRAPPER/#$HOME/\~}"

  if grep -qF "$WRAPPER" "$ZSHRC" 2>/dev/null; then
    echo "  [ok] ~/.zshrc source déjà le wrapper"
  else
    {
      echo ""
      echo "# claude ouvre un workspace herdr (Your-Claude-DevOps)"
      echo "[ -f \"$WRAPPER\" ] && source \"$WRAPPER\""
    } >>"$ZSHRC"
    echo "  [ok] wrapper sourcé depuis ~/.zshrc"
  fi
}

# Le hook herdr vit dans settings.json, que install_config vient d'écraser :
# on le réécrit à chaque passage dès que herdr est présent.
ensure_herdr_hook() {
  command -v herdr >/dev/null 2>&1 || return 0
  herdr integration install claude >/dev/null
  echo "  [ok] hook herdr dans settings.json"
}

print_next_steps() {
  echo ""
  echo "==> Config copiée. Il reste 1 chose : le plugin i-have-adhd."
  echo "    settings.json déclare déjà le marketplace, il s'installe seul au lancement de Claude Code."
  echo "    Sinon, manuel dans Claude Code :"
  echo "      /plugin marketplace add ayghri/i-have-adhd"
  echo "      /plugin install i-have-adhd"
  echo ""
  if [[ $1 == 1 ]]; then
    echo "==> Ouvre un nouveau terminal : 'claude' lance maintenant herdr."
  fi
  echo "==> Relance Claude Code. Le plugin se charge au démarrage."
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

  # Vérifier avant d'écrire quoi que ce soit, pour ne pas laisser une install à moitié faite
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
