---
name: bash-script-builder
description: Use when writing infrastructure and DevOps automation shell scripts, with mandatory splitting into functions and files, stdout/stderr contract, idempotence, guardrails on operations that cut off access, log files and exit codes. Triggers on "bash script", "shell script", ".sh", "Makefile", "automate", "deployment script", "admin script", "shellcheck".
---

# DevOps bash scripts

## What this skill does not teach

A competent agent already writes `set -euo pipefail`, an ERR trap, distinct exit codes, input validation, idempotence by reading the current state, `--dry-run`, `usage()` and timestamped logs on its own. Do not waste lines on that.

This skill covers the observed blind spots, the ones that pass review and break in production.

## Structure: everything in functions, then in files

**Non-negotiable rule: no business code at file level.** Each step is a function named after what it guarantees (`ensure_role`, `check_token`), and the script ends with `main "$@"`.

At file level, only these remain:

1. the shebang and `set -euo pipefail`;
2. the `source` of the libraries;
3. the validation of input variables and the `readonly` declarations;
4. the function definitions;
5. the `main "$@"` call.

`main` reads like a table of contents: a series of function calls, with no logic.

**Reuse before writing.** Before coding a helper (log, report, recap, reading a token), look for the library already present in the repository (`lib.sh`, `scripts/*/lib.sh`) and source it. Never redefine a helper that already exists.

**Split into files** as soon as one of these cases comes up:

| Case | Split |
|---|---|
| The script goes beyond about 150 lines | One file per group of functions, sourced by the main script |
| It covers distinct features (identity, network, CI...) | One script per feature, each with its own `main` |
| Several scripts need the same helper | The helper goes into the shared library |

Each sourced file gets its `# shellcheck source=path` above the `source`. If a Makefile exists, each feature script has its own target.

**Pitfall specific to functions: the subshell.** A function called through `$(...)` runs in a subshell. The counters and global variables it modifies are lost on return. A function that updates state (recap, counters) is called directly and writes to a global variable; it is never captured.

## The stdout / stderr contract

**stdout carries the data, stderr carries the diagnostics.** This is not a style preference, it is what makes a script composable.

The concrete pitfall: a function that returns a value through capture, and that logs to the same place.

```bash
# BROKEN: the variable gets the logs stuck to the value
ensure_group() {
    local id; id=$(lookup "$1")
    log_ok "group '$1' found"        # goes to stdout
    printf '%s' "${id}"
}
group_id=$(ensure_group admins)       # contains the log AND the id

# CORRECT: everything that is not the return value goes to stderr
ensure_group() {
    local id; id=$(lookup "$1")
    log_ok "group '$1' found" >&2
    printf '%s' "${id}"
}
```

Simple rule: **in a function whose output is captured, stdout is reserved for the return value.** A comment above the function reminds the reviewer of this.

Corollary: the WARN and ERROR levels always go to stderr, including when the script has no return value.

## Guardrails: prove the new path before cutting the old one

The most costly mistake in a hardening script is not a syntax bug, it is **removing the last access you have**.

Two families of operations require an explicit guardrail:

**Network filters.** Before applying an allowlist, check that the current outbound address is covered by it. Otherwise, warn and require a confirmation.

```bash
my_ip=$(curl -fsS --max-time 10 https://api.ipify.org || true)
if [[ -n "${my_ip}" && ",${ALLOWED_CIDR}," != *",${my_ip}/32,"* ]]; then
    log_warn "${my_ip} is not in the list, you will lose access"
    confirm "apply anyway?" || die "aborted"
fi
```

**Removing an authentication method.** Never disable the old one before checking that the new one is **operational**, not just created. An empty identity group, or one that is created but not attached to the resource, is not an access path.

```bash
members=$(count_members "${ADMIN_GROUP}")
[[ "${members}" -gt 0 ]] || die "admin group is empty, refusing to disable local accounts"
```

Order the steps accordingly: **establish and test the new access, then remove the old one.** Never the other way around.

## Idempotence: it is proven, not assumed

Reading the current state before writing is not enough. The classic flaw is an `if` that observes and then acts anyway:

```bash
# BROKEN: log then unconditional execution
if [[ "$(current_state)" == "enabled" ]]; then
    log_ok "already enabled"
fi
run enable-the-thing        # the API refuses: already enabled

# CORRECT
if [[ "$(current_state)" == "enabled" ]]; then
    log_ok "already enabled"
else
    run enable-the-thing
fi
```

**The check is to run the script twice in a row.** The second run must finish without error and without changing anything. Until that has been done, idempotence is an intention, not a property.

Also watch out for APIs that refuse an enable flag on a resource that is already enabled: the flag is only passed the first time, later updates only touch the attributes.

## Log file

A badly done `--log-file` destroys the information it claims to keep.

| Rule | Why |
|---|---|
| Open in **append** mode, never truncate | `: > "$LOG_FILE"` erases the history, and the lines already written during validation |
| Timestamped header per run | Separates runs in a cumulative file |
| Timestamp **per line** | A log is used to correlate with an incident |
| Strip ANSI sequences | The terminal keeps its colors, the file stays readable and copyable |
| `chmod 600` | A log of infra operations has no reason to be readable by everyone |
| Never log a sensitive value | A helper that prints the full command line captures tokens passed as arguments |

If the redirection goes through `tee` and a process substitution, plan for draining before the shell exits, otherwise the end of the log is missing.

## Output readable by a human and by a machine

**The exit code is the machine interface**: 0 if everything is compliant, non-zero otherwise. This is what lets you plug the script into a CI.

**The report is for the human.** Its console output follows the Ansible contract described in `makefile-builder` (section "Output contract"): `TASK [...]`, one outcome per line, Ansible palette, numbered `PLAY RECAP`. The words for outcomes and counters are those of the tool that runs, not a fixed list. **REQUIRED BACKGROUND:** read that section of `makefile-builder` before writing a script's output, even without a Makefile.

Confusing "broken" and "not verifiable" produces false alerts: a `skipped` state distinct from `failed` remains mandatory.

Use colors only if the output is a terminal, and respect `NO_COLOR`. Avoid `clear` and cursor manipulation: it breaks piping and pollutes CI logs.

## Syntax and lint pitfalls

Run `shellcheck -x` every time, and wire it into a `make lint` target. The `-x` follows sourced files, without it the shared libraries are not analyzed. Add `# shellcheck source=path/lib.sh` above each `source`.

| Pitfall | Fix |
|---|---|
| `local x="$(cmd)"` (SC2155) | Declare then assign: `local x; x="$(cmd)"` |
| `.*?` in `grep -E` or `awk` | PCRE syntax in an ERE context. Use `[^x]*` or an `awk` with a suitable `FS` |
| `sed -u` | GNU-specific, does not run on BSD or macOS |
| A single `trap ... EXIT` | Bash keeps only one. The second silently replaces the first |
| CIDR regex that validates the shape | `999.999.999.999/99` passes. Also validate the values if it matters |

On the Makefile side: variables coming from an `include` become Make variables and **win over the environment**. `VAR=x make target` has no effect, you must write `make target VAR=x`. And `$(MAKEFILE_LIST)` contains the included files, not only the Makefile.

## Common mistakes

| Mistake | Consequence |
|---|---|
| Logging to stdout in a captured function | The return value contains the log |
| Cutting the old access before testing the new one | Locked out of the managed resource |
| Creating an identity and considering it operational | An empty or unattached group opens no access |
| `if` without `else` before an enable command | The API refuses on the second pass, the script breaks |
| Truncating the log file at startup | Loss of the history and of the lines already written |
| Confirming at every step of a batch | The operator ends up approving without reading |
| `exit 0` when the user refuses | The caller can no longer tell "done" from "refused" |
