#!/usr/bin/env bash
# Installe la config Claude Code de ce repo dans ~/.claude
# Idempotent : peut être relancé sans casser.
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLAUDE_DIR="$HOME/.claude"

echo "==> Installation de la config Claude Code dans $CLAUDE_DIR"
mkdir -p "$CLAUDE_DIR/skills" "$CLAUDE_DIR/hooks"

cp "$REPO_DIR/CLAUDE.md" "$CLAUDE_DIR/CLAUDE.md"
echo "  [ok] CLAUDE.md"

# settings.json : adapter les chemins /home/white -> home réel de cette machine
sed "s#/home/white#$HOME#g" "$REPO_DIR/settings.json" > "$CLAUDE_DIR/settings.json"
echo "  [ok] settings.json (chemins adaptés à $HOME)"

cp -r "$REPO_DIR/skills/." "$CLAUDE_DIR/skills/"
echo "  [ok] skills ($(ls "$CLAUDE_DIR/skills" | wc -l) dossiers)"

cp -r "$REPO_DIR/hooks/." "$CLAUDE_DIR/hooks/"
echo "  [ok] hooks"

# Mémoire : clé de projet dérivée du HOME (/home/white -> -home-white)
MEMKEY="$(echo "$HOME" | tr '/' '-')"
MEM_DIR="$CLAUDE_DIR/projects/$MEMKEY/memory"
mkdir -p "$MEM_DIR"
cp "$REPO_DIR/memory/"*.md "$MEM_DIR/"
echo "  [ok] memory -> projects/$MEMKEY/memory"

echo ""
echo "==> Config copiée. Il reste 1 chose : le plugin caveman."
echo "    settings.json déclare déjà le marketplace, il s'installe seul au lancement de Claude Code."
echo "    Sinon, manuel dans Claude Code :"
echo "      /plugin marketplace add JuliusBrussee/caveman"
echo "      /plugin install caveman"
echo ""
echo "==> Relance Claude Code. Le mode caveman s'active au démarrage."
