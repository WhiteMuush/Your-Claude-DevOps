# Claude Code Config 

Ready-to-use, shareable Claude Code config: rules, skills, hooks, memory. Focused on Dev & Ops and on teaching, generic (no personal data). Use it to install the same setup on any machine, then customize.

## Quick install

- Automatic: `bash install.sh` (copies everything and adapts paths to the machine's home).
- Claude-guided: see `INSTALL.md` (a prompt to paste into Claude Code).
- Manual: see "Install on a new machine" below.

## Contents

- `CLAUDE.md`: global rules (adaptive teaching, visual clarity, format, git, token). Customize after install
- `skills/`: 23 skills (9 DevOps + 14 dev/superpowers)
- `hooks/`: caveman mode scripts (activate, mode-tracker, statusline, stats)
- `settings.json`: Claude Code config (model, hooks, theme, caveman marketplace)
- `memory/`: persistent memory, empty by default (index + example file)

## What is NOT here (on purpose)

Secrets and private data are excluded: `.credentials.json`, history, session transcripts, caches. Never commit them.

## Install on a new machine

1. Clone this repo somewhere, then copy the files into `~/.claude/`:

   ```bash
   cp CLAUDE.md ~/.claude/
   cp settings.json ~/.claude/
   cp -r skills/* ~/.claude/skills/       # create ~/.claude/skills first if missing
   cp -r hooks/* ~/.claude/hooks/
   mkdir -p ~/.claude/projects/-home-USER/memory && cp memory/* ~/.claude/projects/-home-USER/memory/
   ```

2. **IMPORTANT, hardcoded paths.** `settings.json` references `/home/white/.claude/hooks/...`.
   If the user on the new machine is not `white`, replace every `/home/white` with the real home:

   ```bash
   sed -i "s#/home/white#$HOME#g" ~/.claude/settings.json
   ```

   Same for the `memory/` path (the `-home-USER` folder is derived from the home).

3. The **caveman** plugin reinstalls itself: `settings.json` declares the `JuliusBrussee/caveman` marketplace and enables it. It is fetched automatically on the next Claude Code launch. Otherwise, manually:

   ```
   /plugin marketplace add JuliusBrussee/caveman
   /plugin install caveman
   ```

4. Restart Claude Code. Caveman mode activates via the SessionStart hook.

## Notes

- DevOps skills source: `khalilbenaz/claude-skills-collection` (folder `devops-skills`)
- Dev skills source: `obra/superpowers` (folder `skills`), superpowers hooks not included
- All "—" (em dashes) were removed from the skills (personal preference)
