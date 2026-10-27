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
> 2. The script writes to `~/.claude/`, so the safety gate will stop you from running it yourself. Do not force it: give me the exact command to run myself, prefixed with `!`, that is `! bash install.sh`.
> 3. Once I have run it, check that the install is correct: `~/.claude/CLAUDE.md` is present, `~/.claude/skills` contains 30 folders, and the memory is in `~/.claude/projects/<key>/memory`.
> 4. Tell me whether the `i-have-adhd` plugin is active. If it is not, remind me of the commands `/plugin marketplace add ayghri/i-have-adhd` then `/plugin install i-have-adhd`.
> 5. Ask me whether I want the herdr workspace (`claude` opens Claude on the left and a shell on the right). If so, the command becomes `! bash install.sh --herdr`, and then check that `~/.claude/shell/claude-herdr.zsh` exists and that `~/.zshrc` sources it only once.
> 6. Confirm when everything is in place and tell me to restart Claude Code to load the plugin.

---

## Alternative without Claude

You can do everything yourself, without a prompt:

```bash
bash install.sh          # config only
bash install.sh --herdr  # config + herdr workspace
```

Then restart Claude Code.
