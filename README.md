<img src="https://cdn.simpleicons.org/claude/FF6200" width="80" align="left" alt="" />

### Your Claude DevOps

**A ready-to-use, shareable Claude Code configuration for Dev and Ops work.**

<br clear="all" />

Global rules, 30 skills, hooks and memory scaffolding. Everything here is generic: no personal data, no secrets, no machine-specific paths. Install it on any machine, then customize it.

> The **[wiki](https://github.com/WhiteMuush/Your-Claude-DevOps/wiki)** explains how this is built and why: which of the four channels each rule belongs to, how the skills trigger, and how the memory scaffold is meant to be used.

## Quick install

- Automatic: `bash install.sh` copies everything into `~/.claude/`, including the memory scaffolding under the right project key.
- Claude-guided: see `INSTALL.md` for a prompt to paste into Claude Code.
- Manual: see "Install on a new machine" below.

## Contents

- `CLAUDE.md`: global rules covering adaptive teaching mode, visual clarity, response format, git conventions and token economy. Customize this file after install.
- `skills/`: 30 skills, 15 for DevOps (Ansible, ArgoCD, Azure, Docker, Docker Swarm, GitHub Actions, GitLab CI, Helm, Prometheus and Grafana, Terraform, shell scripts, Makefiles, plus logging, metrics and tracing design) and 15 for development methodology (brainstorming, planning, TDD, debugging, code review, git worktrees, cleaning user-facing text).
- `hooks/`: hook directory, shipped with its CommonJS manifest. Output shaping now comes from the `i-have-adhd` plugin, which registers its own hooks.
- `settings.json`: Claude Code configuration (model, effort level, permissions with explicit deny rules, theme, `i-have-adhd` marketplace).
- `memory/`: persistent memory scaffolding, empty by default (index plus one example file).
- `shell/claude-herdr.zsh`: optional zsh wrapper that makes `claude` open a [herdr](https://herdr.dev) workspace, Claude on the left and a shell on the right.

## What is deliberately not here

Secrets and private data are excluded and must never be committed: `.credentials.json`, `history.jsonl`, session transcripts, caches, and the real `memory/` files, which hold personal notes.

The `autoMode` block of the source `settings.json` is excluded too: it pins local filesystem paths, a private remote and the location of credential files.

## Install on a new machine

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

1. Install the dependencies (`curl` for the installer, `jq` and `zsh` for the wrapper):

   ```bash
   # Debian / Ubuntu
   sudo apt update && sudo apt install -y curl jq zsh

   # Fedora
   sudo dnf install -y curl jq zsh

   # Arch
   sudo pacman -S --needed curl jq zsh
   ```

2. Install herdr with its official installer. There is no distro package: the script downloads the release binary, checks its SHA-256 and puts it in `~/.local/bin`, which must be in your `PATH`:

   ```bash
   curl -fsSL https://herdr.dev/install.sh | sh
   herdr --version
   ```

   Homebrew (`brew install herdr`), mise and Nix are also supported, see the [install docs](https://herdr.dev/docs/install/).

3. Let herdr install its Claude Code hook. It writes `~/.claude/hooks/herdr-agent-state.sh` and the matching `SessionStart` entry in `settings.json`, so neither is shipped here:

   ```bash
   herdr integration install claude
   ```

4. Source the wrapper from `~/.zshrc`:

   ```bash
   echo "source $PWD/shell/claude-herdr.zsh" >> ~/.zshrc
   ```

The wrapper falls back to the plain `claude` binary when herdr is missing, when already inside herdr, when stdin or stdout is not a terminal, and for non-interactive flags and subcommands (`-p`, `--version`, `mcp`, `config`, `doctor`...). It needs `jq`.

## Notes

The rules in `CLAUDE.md` and the DevOps skills are written in French, since that is the language of the setup they came from. The structure is language-agnostic, so translating them is a search and replace away.

Em dashes were removed throughout, which is a personal formatting preference carried over from `CLAUDE.md`.

## Credits

This configuration assembles work from other people. None of it is sold or claimed as original, and all of it is worth visiting at the source.

- DevOps skills, adapted from [khalilbenaz/claude-skills-collection](https://github.com/khalilbenaz/claude-skills-collection), folder `devops-skills`.
- Development and methodology skills, adapted from [obra/superpowers](https://github.com/obra/superpowers), folder `skills`. The upstream hooks are not included here.
- Output shaping plugin, from [ayghri/i-have-adhd](https://github.com/ayghri/i-have-adhd).

Adaptations are limited to formatting and language conventions. If you are one of the authors and want a credit changed or the content removed, open an issue and it will be handled.
