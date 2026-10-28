<img src="https://cdn.simpleicons.org/claude/FF6200" width="80" align="left" alt="" />

### Your Claude DevOps

**A ready-to-use Claude Code configuration for Dev and Ops work.**

<br clear="all" />

Global rules, 32 skills, hooks and a memory scaffold, all generic: no personal data, no secrets, no machine-specific paths. Install it on any machine, then make it your own.

> The **[wiki](https://github.com/WhiteMuush/Your-Claude-DevOps/wiki)** explains how it is built and why.

## Install

```bash
git clone https://github.com/WhiteMuush/Your-Claude-DevOps.git
cd Your-Claude-DevOps
./install.sh
```

Then **restart Claude Code**.

The installer **never replaces a file without asking**. It first offers to **back up** your current `~/.claude`, then goes through 5 steps:

1. **CLAUDE.md**: the rules Claude follows in every project.
2. **settings.json**: permissions, model, theme and plugins. You can **merge** it with yours instead of replacing it.
3. **Skills**: the guides Claude reads before a task.
4. **Hooks and memory**: your existing memory notes are never replaced.
5. **herdr** (optional): typing `claude` opens Claude on the left and a shell on the right.

When one of your files differs from the repository, you choose: **replace**, **keep**, or **show the diff** first.

### Options

| Command | What it does |
|---|---|
| `./install.sh` | Guided install, asks before every change |
| `./install.sh --yes` | No questions: backs up, installs what is missing, keeps your existing files |
| `./install.sh --yes --herdr` | Same, plus the herdr workspace |
| `./install.sh --help` | Shows the options and exit codes |

### Undo an install

```bash
./restore.sh
```

It lists your backups, shows **exactly what will change**, and asks before doing anything. It then puts `~/.claude` back as it was, and removes what the install added.

Your current config is saved first, so **a restore can be undone too**. Your memory notes and the herdr program are never touched.

### Install with Claude's help

Open Claude Code in the cloned folder and paste the prompt from [`INSTALL.md`](INSTALL.md). Claude checks the result for you.

## What is inside

| Path | Content |
|---|---|
| `CLAUDE.md` | Global rules: adaptive teaching mode, visual clarity, response format, git conventions, token economy |
| `skills/` | 32 skills: 17 for DevOps, 15 for development methodology |
| `settings.json` | Model, effort level, permissions with explicit `deny` rules, theme, `i-have-adhd` plugin |
| `hooks/` | Hook directory, with its CommonJS manifest |
| `memory/` | Memory scaffold: an index and one example file |
| `shell/claude-herdr.zsh` | Optional zsh wrapper for the herdr workspace |
| `install.sh`, `restore.sh`, `install/` | The installer, its undo, and their modules |
| `tests/` | Plain Bash tests for both scripts |

**The 17 DevOps skills** cover Ansible, ArgoCD, Azure, Docker, Docker Swarm, GitHub Actions, GitLab CI, Helm, Prometheus and Grafana, Terraform, shell scripts, Makefiles, architecture diagrams, an Obsidian documentation vault, and the design of logs, metrics and traces.

**The 15 methodology skills** cover brainstorming, planning, TDD, debugging, code review, git worktrees and cleaning user-facing text.

## The herdr workspace

[herdr](https://herdr.dev) splits your terminal: **Claude on the left, a shell on the right**, every time you type `claude`.

The installer asks about it at its last step. If you say yes, it:

1. Checks for `curl`, `jq` and `zsh`, and tells you how to install any that is missing.
2. Installs herdr, with Homebrew when available, otherwise with the [official installer](https://herdr.dev/docs/install/) into `~/.local/bin`.
3. Copies the wrapper to `~/.claude/shell/` and adds one line to `~/.zshrc` to load it.
4. Adds the herdr hook to `settings.json`.

It only works with **zsh**. To skip the wrapper once, run `command claude`.

The wrapper also steps aside on its own: when herdr or `jq` is missing, inside herdr itself, outside a terminal, and for non-interactive commands such as `-p`, `--version`, `mcp` or `doctor`.

## Never included

These stay out of the repository and must never be committed:

- `.credentials.json`, `history.jsonl`, session transcripts and caches
- your real memory notes
- the `autoMode` block of your own `settings.json`, which holds local paths and private remotes

## Tests

```bash
bash tests/install_test.sh
bash tests/restore_test.sh
```

They run both scripts in **throwaway home folders**, so your real `~/.claude` is never touched. No test framework is needed.

<details>
<summary><strong>Manual install, without the script</strong></summary>

These commands **overwrite your files without a backup**. On a machine that already has a configuration, use `./install.sh` instead.

```bash
cp CLAUDE.md ~/.claude/
cp -r skills/. ~/.claude/skills/
cp -r hooks/. ~/.claude/hooks/
cp settings.json ~/.claude/settings.json

MEMKEY="$(echo "$HOME" | tr '/' '-')"
mkdir -p "$HOME/.claude/projects/$MEMKEY/memory"
cp memory/*.md "$HOME/.claude/projects/$MEMKEY/memory/"
```

The memory key comes from your home folder: `/home/alice` becomes `-home-alice`.

The `i-have-adhd` plugin installs itself on the next Claude Code start. If it does not, run this in Claude Code:

```
/plugin marketplace add ayghri/i-have-adhd
/plugin install i-have-adhd
```

</details>

## Credits

This configuration assembles other people's work. None of it is sold or claimed as original, and all of it is worth visiting at the source.

- **DevOps skills**, adapted from [khalilbenaz/claude-skills-collection](https://github.com/khalilbenaz/claude-skills-collection), folder `devops-skills`.
- **Methodology skills**, adapted from [obra/superpowers](https://github.com/obra/superpowers), folder `skills`. The upstream hooks are not included.
- **Output shaping plugin**, from [ayghri/i-have-adhd](https://github.com/ayghri/i-have-adhd).

Adaptations are limited to formatting and language conventions. If you are one of the authors and want a credit changed or the content removed, open an issue.
