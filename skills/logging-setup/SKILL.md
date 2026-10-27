---
name: logging-setup
description: Use when setting up or reviewing infrastructure and application logs, with a mandatory console presentation format (Ansible contract: TASK, outcomes, PLAY RECAP), stdout/stderr destination, run log, levels, secret redaction, rotation and retention. Covers Ansible, systemd and CI/CD specifics, and points to collecte.md for aggregated logs. Triggers on "logs", "logging", "journaling", "log_path", "no_log", "logrotate", "journald", "structured logging", "log aggregation", "retention", "observability".
---

# Setting up logs

## What this skill does not teach

A competent agent already timestamps its lines, puts a level in front, and does not write `print()` everywhere. Do not spend lines on that.

This skill covers the decisions made at wiring time, the ones that can no longer be corrected without a migration once the collector is ingesting.

## Output presentation: the Ansible contract

**This section is not a suggestion.** Console output follows the Ansible contract described in `makefile-builder` (section "Output contract"): an operator who has read an `ansible-playbook` run can read every script. **REQUIRED BACKGROUND:** read that section of `makefile-builder`, including "The words come from the tool, the form comes from Ansible".

### Expected rendering

```
TASK [aks : API server IP allowlist] *******************************************
    current allowlist: 10.0.0.0/8
    requested        : 10.0.0.0/8,203.0.113.7/32
[WARNING]: 203.0.113.7 is not listed explicitly
changed:     [aks] allowlist applied, rules take up to 2 minutes to propagate

PLAY RECAP *********************************************************************
aks         : ok=4   changed=1   unreachable=0   failed=0   skipped=0
```

| Element | Role | Stream |
|---|---|---|
| `TASK [role : action]` | Opens a step, line of asterisks up to 80 columns | stdout |
| (indentation only) | Detail, context, value read | stdout |
| One outcome per line (`ok:`, `changed:`, or the tool's word) | Result of the step | stdout |
| `[WARNING]:` | Absorbed anomaly, execution continues | **stderr** |
| `fatal:` / `unreachable:` | Failure, followed by a non-zero exit | **stderr** |
| `PLAY RECAP` | End counters, named after the tool | stdout |

Formatting rules:

- **Color is a bonus, never the information.** The outcome word stays readable once colors are removed.
- **Colors are disabled** if the output is not a terminal, or if `NO_COLOR` is set.
- **No extra visible level.** No `DEBUG` on screen, no emoji.

In another language, transpose the same form. The rendering does not change, only the vehicle does.

## 1. Decide the destination before the format

The first question is not "which format" but **who owns the log file**.

| Execution context | The process writes to | Who handles rotation |
|---|---|---|
| Container | stdout / stderr, nothing else | The runtime |
| systemd service | stdout / stderr | journald |
| Cron or one-shot script | stdout / stderr, redirected by the caller | The caller or logrotate |
| Legacy binary that cannot be modified | Its own file | logrotate |

**Rule:** an application under an orchestrator does not open a file and does not manage its rotation. The stream contract is the one from `bash-script-builder`: stdout for data, stderr for diagnostics. A log is a diagnostic.

### Keeping a file record of a run

The file is **opt-in** (`LOG_FILE=path`), never imposed by default. Good practice:

| Practice | Reason |
|---|---|
| Open in **append** mode | Truncation erases the history, including the run that just failed |
| **Timestamp** in the file, not on screen | The screen is read live, the file is correlated with an incident |
| **Strip ANSI codes** | Otherwise unreadable and painful to grep |
| **Run header**: UTC date, script, PID | Separates executions and serves as a correlation identifier |
| **`umask 077`, permissions 600** | The log names resources, accounts, addresses |
| **Create the parent directory** | Otherwise it fails on the path supplied by the user |
| **Drain before exiting** | With `tee`, the end of the run is missing if the shell exits before the sinks |
| **Chain the EXIT trap** | Bash keeps only one: the next one silently overwrites the previous one |

The file receives both streams, but **stdout and stderr stay separate** on screen. And this does not remove the need for rotation, see section 4.

## 2. Levels: the recipient rule

Choose the level according to who must react. On the console side, `fatal:` and `unreachable:` carry ERROR, `[WARNING]:` carries WARN, `TASK`, outcomes and indentation carry INFO.

| Level | Recipient | Validation test |
|---|---|---|
| ERROR | An on-call engineer, potentially at night | If nobody needs to be woken up, it is not ERROR |
| WARN | Someone rereading the logs tomorrow morning | Absorbed degradation, but abnormal |
| INFO | A post-incident investigation | State transitions, not loops |
| DEBUG | The developer, locally | Disabled in production by default |

- **An error caught and rethrown is logged twice.** Log where you decide what to do, propagate elsewhere.
- **ERROR in a retry loop**: the collector receives thousands of lines and the alert becomes unusable. Log WARN on each attempt, ERROR only once when giving up.

The level must be changeable **without redeployment**: an environment variable read at startup at minimum, an admin endpoint if the service is slow to restart.

## 3. Secrets and personal data

The most expensive point to fix: a logged secret is replicated, indexed and backed up.

- **Filter at emission, not at ingestion.** An allowlist of permitted fields holds up better over time than a denylist of forbidden fields.
- **Never log an entire object** (HTTP request, API response, config structure). It is the number one vector for token leaks.
- **`Authorization`, `Cookie`, `Set-Cookie`** and authentication request bodies are excluded by default.
- **A URL contains secrets** in its query string. Log the path, not the full URL.
- **Personal data**: log an internal identifier, not an email or a name. Otherwise log retention becomes a GDPR issue.

If a secret has already been logged, treat it as compromised: revocation and rotation, not just deleting the line.

## 4. Rotation and retention

| Decision | Reasonable starting value |
|---|---|
| Max file size | 100 MB |
| Number of files kept | 5 to 10 |
| Hot retention (fast search) | 7 to 15 days |
| Cold retention (archive) | 90 days, more if legally required |
| Compression | Yes, except on the current file |

`logrotate` trap: **`copytruncate` loses the lines written between the copy and the truncation**, and fixes nothing if the process keeps the descriptor open. Prefer a reopen signal (`postrotate` with `kill -HUP` or `systemctl reload`), and keep `copytruncate` only if the process cannot reopen its file.

## Technology specifics

### Ansible

The official reference doc is the appendix [Logging Ansible output](https://docs.ansible.com/projects/ansible/latest/reference_appendices/logging.html).

- `log_path` in `ansible.cfg`: a single log on the control node. The file is not rotated by default, plan for logrotate.
- `no_target_syslog` and `syslog_facility`: one log per managed machine, instead.
- **`no_log: true` on every task that handles a secret.** Beware, it does not cover `debug` output, so do not debug a playbook in production.
- `display_args_to_stdout`: adds variable values to the output, useful for telling identical tasks apart in a loop.
- Callback plugins: `log_plays` writes events to a file, `mail` notifies on failure, `profile_tasks` times tasks. Enable them via `callbacks_enabled` in `ansible.cfg`.
- The Vault password is never passed as a command-line argument, it ends up in the shell history and in the CI logs.

### systemd

- `StandardOutput=journal`, read with `journalctl -u <unit> -o json`.
- `SystemMaxUse=` in `journald.conf` caps the space used, otherwise journald takes up to 10% of the file system.

### CI/CD

- Secrets are masked by the platform only if they are declared as such. A derived value (base64-encoded, concatenated) is no longer masked.
- Do not enable maximum verbosity (Ansible `-vvv`, `set -x`, `CI_DEBUG_TRACE`) on a run that handles credentials.
- Job logs have a short retention: archive as an artifact whatever must serve a post-mortem.

## Anti-patterns

| Anti-pattern | Consequence | Fix |
|---|---|---|
| Logging the entire request or response object | Token and personal data leaks | Field allowlist |
| `copytruncate` by default | Lines lost at every rotation | Reopen signal in `postrotate` |
| DEBUG left active in production | Volume, cost, exposed secrets | Level driven by an environment variable |
| Timestamps in local time | Correlation impossible across regions | ISO 8601 UTC with milliseconds |
| Home-made markers invented for each project | Every log reads differently | The Ansible contract from `makefile-builder`, no exceptions |
| Truncating the log file at startup | Loss of history, including the run that failed | Open in append mode |
| `trap ... EXIT` set without chaining | The previous cleanup is silently overwritten | Chain onto the existing trap |

## Review checklist

1. Console output follows the Ansible contract (TASK, outcomes named after the tool, PLAY RECAP), and colors can be disabled.
2. The destination is consistent with the execution context, and the process does not own a file it should not own.
3. If a collector ingests, the format is structured, one line per event, UTC timestamp.
4. Levels follow the recipient rule, and can be controlled without redeployment.
5. No secret or personal data can reach the output, filtering happens at emission.
6. Rotation and retention are defined, including on the runtime driver.
7. A correlation identifier crosses services or runs.
8. Collector unavailability does not degrade the service.

## The other signals

A log says what happened for a specific case. For "how many and how fast", see `metrics-setup`. For "where the time went between services", see `tracing-setup`. The `trace_id` field is what links the three.

## Service with a collector

As soon as logs go to a collector (long-running application, container, centralized aggregation), read `collecte.md` in this folder: structured JSON format, correlation, aggregation, containers and Kubernetes.
