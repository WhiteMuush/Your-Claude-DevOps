# Your Claude DevOps

A ready-to-use, shareable Claude Code configuration: global rules, skills, hooks and memory scaffolding. It is oriented towards Dev and Ops work and towards teaching, and it is fully generic: no personal data, no secrets, no machine-specific paths. Install it on any machine, then customize it.

## Quick install

- Automatic: `bash install.sh` copies everything into `~/.claude/` and adapts paths to the machine's home.
- Claude-guided: see `INSTALL.md` for a prompt to paste into Claude Code.
- Manual: see "Install on a new machine" below.

## Contents

- `CLAUDE.md`: global rules covering adaptive teaching mode, visual clarity, response format, git conventions and token economy. Customize this file after install.
- `skills/`: 23 skills, 9 for DevOps (Ansible, ArgoCD, Azure, Docker Swarm, GitHub Actions, GitLab CI, Helm, Prometheus and Grafana, Terraform) and 14 for development methodology (brainstorming, planning, TDD, debugging, code review, git worktrees).
- `hooks/`: caveman mode scripts (activate, mode tracker, status line, stats).
- `settings.json`: Claude Code configuration (model, permissions, theme, status line, caveman marketplace).
- `memory/`: persistent memory scaffolding, empty by default (index plus one example file).

## What is deliberately not here

Secrets and private data are excluded and must never be committed: `.credentials.json`, `history.jsonl`, session transcripts, caches, and the real `memory/` files, which hold personal notes.

Three skills present in the source configuration are also excluded because they describe one specific machine and one specific user rather than a reusable setup.

## Install on a new machine

1. Clone this repository, then copy the files into `~/.claude/`:

   ```bash
   cp CLAUDE.md ~/.claude/
   cp -r skills/. ~/.claude/skills/
   cp -r hooks/. ~/.claude/hooks/
   sed "s#__HOME__#$HOME#g" settings.json > ~/.claude/settings.json
   ```

2. The `settings.json` shipped here uses a `__HOME__` placeholder instead of a hardcoded home directory. The `sed` command above resolves it, and `install.sh` does the same automatically.

3. Copy the memory scaffolding. The project key is derived from your home directory, so `/home/alice` becomes `-home-alice`:

   ```bash
   MEMKEY="$(echo "$HOME" | tr '/' '-')"
   mkdir -p "$HOME/.claude/projects/$MEMKEY/memory"
   cp memory/*.md "$HOME/.claude/projects/$MEMKEY/memory/"
   ```

4. The caveman plugin reinstalls itself: `settings.json` declares the `JuliusBrussee/caveman` marketplace and enables the plugin, which is fetched on the next Claude Code launch. To do it manually:

   ```
   /plugin marketplace add JuliusBrussee/caveman
   /plugin install caveman
   ```

5. Restart Claude Code. Caveman mode activates through the SessionStart hook registered by the plugin.

## Notes

The rules in `CLAUDE.md` and the DevOps skills are written in French, since that is the language of the setup they came from. The structure is language-agnostic, so translating them is a search and replace away.

Em dashes were removed throughout, which is a personal formatting preference carried over from `CLAUDE.md`.

## Credits

This configuration assembles work from other people. None of it is sold or claimed as original, and all of it is worth visiting at the source.

- DevOps skills, adapted from [khalilbenaz/claude-skills-collection](https://github.com/khalilbenaz/claude-skills-collection), folder `devops-skills`.
- Development and methodology skills, adapted from [obra/superpowers](https://github.com/obra/superpowers), folder `skills`. The upstream hooks are not included here.
- Caveman mode hooks and plugin, from [JuliusBrussee/caveman](https://github.com/JuliusBrussee/caveman).

Adaptations are limited to formatting and language conventions. If you are one of the authors and want a credit changed or the content removed, open an issue and it will be handled.
