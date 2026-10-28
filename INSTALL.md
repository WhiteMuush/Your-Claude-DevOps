# Installation guided by Claude

On the new machine:

1. Clone this repo and open a terminal in it:

   ```bash
   git clone https://github.com/WhiteMuush/Your-Claude-DevOps.git
   cd Your-Claude-DevOps
   ```

2. Start Claude Code in this folder.

3. Paste this prompt:

---

> You are in my Claude Code config repo (`Your-Claude-DevOps`). Install this config on the current machine.
>
> Steps:
> 1. Read the `README.md` and the `install.sh` script to understand what needs to be copied into `~/.claude/`.
> 2. The script writes to `~/.claude/` and asks questions, so do not run it yourself. Tell me to run `./install.sh` in a separate terminal, in this folder. If I prefer to stay here, give me `! ./install.sh --yes`, which asks nothing, makes a backup and keeps every file I already have.
> 3. Once I have run it, check that the install is correct: `~/.claude/CLAUDE.md` is present, `~/.claude/skills` contains 32 folders, and the memory is in `~/.claude/projects/<key>/memory`.
> 4. Tell me whether the `i-have-adhd` plugin is active. If it is not, remind me of the commands `/plugin marketplace add ayghri/i-have-adhd` then `/plugin install i-have-adhd`.
> 5. If I chose herdr (the installer asks at its last step, or `--herdr` with `--yes`), check that `~/.claude/shell/claude-herdr.zsh` exists and that `~/.zshrc` sources it only once.
> 6. Confirm when everything is in place and tell me to restart Claude Code to load the plugin.

---

## Alternative without Claude

You can do everything yourself, without a prompt:

```bash
./install.sh                # guided install, asks before replacing anything
./install.sh --yes          # no questions, keeps your existing files
./install.sh --yes --herdr  # same, plus the herdr workspace
./restore.sh                # put back one of the backups made by the installer
```

Then restart Claude Code.
