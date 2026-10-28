<img src="https://cdn.simpleicons.org/claude/FF6200" width="80" align="left" alt="" />

### Your Claude DevOps

**A ready-to-use, shareable Claude Code configuration for Dev and Ops work.**

<br clear="all" />

Global rules, 32 skills, hooks and memory scaffolding. Everything here is generic: no personal data, no secrets, no machine-specific paths. Install it on any machine, then customize it.

> The **[wiki](https://github.com/WhiteMuush/Your-Claude-DevOps/wiki)** explains how this is built and why: which of the four channels each rule belongs to, how the skills trigger, and how the memory scaffold is meant to be used.

## Quick install

- Interactive: `bash install.sh` explains each of its 5 steps, offers to back up your current config to `~/.claude-backups/`, and asks before replacing any file that differs (replace, keep, show the diff, or merge for `settings.json`). Existing memory notes are never replaced. It asks about the herdr workspace at the end, see below.
- Without questions: `bash install.sh --yes` backs up, installs what is missing and keeps every file you already have. Add `--herdr` to install herdr too.
- Undo: `bash restore.sh` lists your backups, shows exactly what will change, and puts `~/.claude` back as it was, removing what was added since (including the herdr line in `~/.zshrc`). It saves your current config first, so a restore can be undone too. Memory notes and the herdr program are never touched.
- Tests: `bash tests/install_test.sh` and `bash tests/restore_test.sh` run both scripts in throwaway home folders, your real `~/.claude` is never touched.
- Claude-guided: see `INSTALL.md` for a prompt to paste into Claude Code.
- Manual: see "Install on a new machine" below.

## Contents

- `CLAUDE.md`: global rules covering adaptive teaching mode, visual clarity, response format, git conventions and token economy. Customize this file after install.
- `skills/`: 32 skills, 17 for DevOps (Ansible, ArgoCD, Azure, Docker, Docker Swarm, GitHub Actions, GitLab CI, Helm, Prometheus and Grafana, Terraform, shell scripts, Makefiles, architecture diagrams with tool logos, an Obsidian documentation vault with a fixed graph, plus logging, metrics and tracing design) and 15 for development methodology (brainstorming, planning, TDD, debugging, code review, git worktrees, cleaning user-facing text).
- `hooks/`: hook directory, shipped with its CommonJS manifest. Output shaping now comes from the `i-have-adhd` plugin, which registers its own hooks.
- `settings.json`: Claude Code configuration (model, effort level, permissions with explicit deny rules, theme, `i-have-adhd` marketplace).
- `install.sh`, `restore.sh` and `install/`: the interactive installer and its undo, one file per role (screens, checks, backup, file handling, settings merge, herdr, restore).
- `tests/`: plain Bash tests for both scripts, run in throwaway home folders.
- `memory/`: persistent memory scaffolding, empty by default (index plus one example file).
- `shell/claude-herdr.zsh`: optional zsh wrapper that makes `claude` open a [herdr](https://herdr.dev) workspace, Claude on the left and a shell on the right.

## What is deliberately not here

Secrets and private data are excluded and must never be committed: `.credentials.json`, `history.jsonl`, session transcripts, caches, and the real `memory/` files, which hold personal notes.

The `autoMode` block of the source `settings.json` is excluded too: it pins local filesystem paths, a private remote and the location of credential files.

## Install on a new machine

These manual steps overwrite your files without a backup. On a machine that already has a configuration, prefer `bash install.sh`, which asks first.

1. Clone this repository, then copy the files into `~/.claude/`:

   ```bash
   cp CLAUDE.md ~/.claude/
   cp -r skills/. ~/.claude/skills/
   cp -r hooks/. ~/.claude/hooks/
   cp settings.json ~/.claude/settings.json
   ```

2. The `settings.json` shipped here holds no machine-specific path, so it copies as is. It does carry `deny` rules blocking `gh repo delete`, `gh repo edit` and force pushes; drop them if you want those commands back.

3. Copy the memory scaffolding. The project key is derived from your home directory, so `/home/alice` becomes `-home-alice`:

   ```bash
   MEMKEY="$(echo "$HOME" | tr '/' '-')"
   mkdir -p "$HOME/.claude/projects/$MEMKEY/memory"
   cp memory/*.md "$HOME/.claude/projects/$MEMKEY/memory/"
   ```

4. The `i-have-adhd` plugin reinstalls itself: `settings.json` declares the `ayghri/i-have-adhd` marketplace and enables the plugin, which is fetched on the next Claude Code launch. To do it manually:

   ```
   /plugin marketplace add ayghri/i-have-adhd
   /plugin install i-have-adhd
   ```

5. Restart Claude Code. The plugin registers its own hooks at session start.

## Optional: herdr workspace

With [herdr](https://herdr.dev) installed, typing `claude` opens a herdr workspace in the current directory, with Claude on the left and an empty shell on the right.

Answer yes at the last step of `bash install.sh`, or pass `--herdr` to skip the question. This:

1. Checks for `curl`, `jq` and `zsh`. If one is missing, it prints the `apt`, `dnf` and `pacman` command to install it and skips herdr, the rest of the install is kept.
2. Installs herdr if it is not there yet: with Homebrew when available, otherwise with the [official installer](https://herdr.dev/docs/install/), which checks the SHA-256 and puts the binary in `~/.local/bin` (that directory must be in your `PATH`).
3. Copies the wrapper to `~/.claude/shell/claude-herdr.zsh` and sources it from `~/.zshrc`, once. Moving or deleting the clone afterwards does not break your shell.
4. Runs `herdr integration install claude`, which writes `~/.claude/hooks/herdr-agent-state.sh` and its `SessionStart` entry in `settings.json`.

Step 4 only runs when you choose herdr. If you replace `settings.json` later, answer yes to herdr again to put its hook back, or pick merge, which keeps it.

The wrapper falls back to the plain `claude` binary when herdr or `jq` is missing, when already inside herdr, when stdin or stdout is not a terminal, and for non-interactive flags and subcommands (`-p`, `--bg`, `--version`, `mcp`, `agents`, `logs`, `doctor`...). To bypass it once, run `command claude`.

## Notes

Everything in this repository is written in English, including the rules in `CLAUDE.md`, the DevOps skills and the memory templates.

Em dashes were removed throughout, which is a personal formatting preference carried over from `CLAUDE.md`.

## Credits

This configuration assembles work from other people. None of it is sold or claimed as original, and all of it is worth visiting at the source.

- DevOps skills, adapted from [khalilbenaz/claude-skills-collection](https://github.com/khalilbenaz/claude-skills-collection), folder `devops-skills`.
- Development and methodology skills, adapted from [obra/superpowers](https://github.com/obra/superpowers), folder `skills`. The upstream hooks are not included here.
- Output shaping plugin, from [ayghri/i-have-adhd](https://github.com/ayghri/i-have-adhd).

Adaptations are limited to formatting and language conventions. If you are one of the authors and want a credit changed or the content removed, open an issue and it will be handled.
