#!/usr/bin/env bash
# Runs restore.sh against throwaway home folders and checks that it puts the old configuration back exactly.
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly REPO_DIR

# shellcheck source=tests/lib.sh
source "${REPO_DIR}/tests/lib.sh"

count_backups() {
  find "${TEST_HOME}/.claude-backups" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | wc -l | tr -d ' '
}

# Builds a home with its own CLAUDE.md and skill, then installs over it with a backup and a replace.
home_with_install() {
  new_home
  mkdir -p "${TEST_HOME}/.claude/skills/only-mine"
  printf 'my own rules\n' >"${TEST_HOME}/.claude/CLAUDE.md"
  printf 'mine\n' >"${TEST_HOME}/.claude/skills/only-mine/SKILL.md"
  run_install 'y\ny\nr\nn\n'
}

test_restore_after_install() {
  printf '\nRestore the backup made by the installer\n'
  home_with_install
  check "the install made one backup" test "$(count_backups)" -eq 1
  check "the backup has its info file" test -f "$(find "${TEST_HOME}/.claude-backups" -name backup.info | head -1)"

  run_restore '1\ny\n'
  check "exits with 0" test "${STATUS}" -eq 0
  check "puts the old CLAUDE.md back" test "$(cat "${TEST_HOME}/.claude/CLAUDE.md")" == "my own rules"
  check "keeps only the old skill" test "$(ls "${TEST_HOME}/.claude/skills")" == "only-mine"
  check "removes settings.json, which did not exist" test ! -e "${TEST_HOME}/.claude/settings.json"
  check "removes hooks, which did not exist" test ! -e "${TEST_HOME}/.claude/hooks"
  check "saves the current config first" test "$(count_backups)" -eq 2
  check "lists the removed skills before asking" grep -q 'removes 32 added since that date' <<<"${OUTPUT}"

  run_restore '2\n'
  check "says nothing to do when the config already matches" grep -q 'Nothing to do' <<<"${OUTPUT}"
  check "exits with 0 when there is nothing to do" test "${STATUS}" -eq 0

  run_restore '1\ny\n'
  check "can undo the restore" cmp -s "${REPO_DIR}/CLAUDE.md" "${TEST_HOME}/.claude/CLAUDE.md"
  check "brings settings.json back with the undo" test -f "${TEST_HOME}/.claude/settings.json"
}

test_restore_cancel() {
  printf '\nAnswer no to the restore\n'
  home_with_install
  local before after
  before=$(tree_checksum "${TEST_HOME}/.claude")
  run_restore '1\n\n'
  after=$(tree_checksum "${TEST_HOME}/.claude")
  check "exits with 3" test "${STATUS}" -eq 3
  check "changes no file" test "${before}" == "${after}"
  check "makes no new backup" test "$(count_backups)" -eq 1
}

test_restore_zshrc() {
  printf '\nRemove the herdr line added after the backup\n'
  new_home
  mkdir -p "${TEST_HOME}/.claude"
  printf 'my own rules\n' >"${TEST_HOME}/.claude/CLAUDE.md"
  printf 'alias ll="ls -l"\n' >"${TEST_HOME}/.zshrc"
  run_install 'y\ny\n\nn\n'
  local wrapper="${TEST_HOME}/.claude/shell/claude-herdr.zsh"
  printf '\n# claude opens a herdr workspace (Your-Claude-DevOps)\n[ -f "%s" ] && source "%s"\n' "${wrapper}" "${wrapper}" >>"${TEST_HOME}/.zshrc"

  run_restore '1\ny\n'
  check "exits with 0" test "${STATUS}" -eq 0
  check "removes the herdr line" test -z "$(grep -F "${wrapper}" "${TEST_HOME}/.zshrc" || true)"
  check "keeps the user's own lines" grep -qF 'alias ll="ls -l"' "${TEST_HOME}/.zshrc"
}

test_no_backup() {
  printf '\nNo backup at all\n'
  new_home
  run_restore '\n'
  check "exits with 1" test "${STATUS}" -eq 1
  check "says no backup was found" grep -q 'No backup found' <<<"${OUTPUT}"
}

test_restore_no_terminal() {
  printf '\nNo terminal\n'
  home_with_install
  STATUS=0
  OUTPUT=$(HOME="${TEST_HOME}" NO_COLOR=1 bash "${REPO_DIR}/restore.sh" </dev/null 2>&1) || STATUS=$?
  check "exits with 1" test "${STATUS}" -eq 1
  check "says it needs a terminal" grep -q 'needs a terminal' <<<"${OUTPUT}"
}

test_same_second_order() {
  printf '\nTwo backups made in the same second\n'
  new_home
  mkdir -p "${TEST_HOME}/.claude-backups/2026-01-01_000000-01" "${TEST_HOME}/.claude-backups/2026-01-01_000000-02"
  printf 'date=first\n' >"${TEST_HOME}/.claude-backups/2026-01-01_000000-01/backup.info"
  printf 'date=second\n' >"${TEST_HOME}/.claude-backups/2026-01-01_000000-02/backup.info"
  run_restore '\n\n'
  check "lists the second one as the latest" grep -q '1\. second' <<<"${OUTPUT}"
}

main() {
  test_same_second_order
  test_restore_after_install
  test_restore_cancel
  test_restore_zshrc
  test_no_backup
  test_restore_no_terminal
  finish
}

main "$@"
