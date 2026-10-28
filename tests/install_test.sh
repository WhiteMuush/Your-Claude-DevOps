#!/usr/bin/env bash
# Runs install.sh against throwaway home folders and checks what it leaves behind.
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly REPO_DIR

# shellcheck source=tests/lib.sh
source "${REPO_DIR}/tests/lib.sh"

test_fresh_install() {
  printf '\nFresh install\n'
  new_home
  run_install 'y\nn\n'
  local skills_repo skills_installed
  skills_repo=$(find "${REPO_DIR}/skills" -mindepth 1 -maxdepth 1 | wc -l)
  skills_installed=$(find "${TEST_HOME}/.claude/skills" -mindepth 1 -maxdepth 1 | wc -l)
  check "exits with 0" test "${STATUS}" -eq 0
  check "installs CLAUDE.md" cmp -s "${REPO_DIR}/CLAUDE.md" "${TEST_HOME}/.claude/CLAUDE.md"
  check "installs settings.json" cmp -s "${REPO_DIR}/settings.json" "${TEST_HOME}/.claude/settings.json"
  check "installs every skill" test "${skills_repo}" -eq "${skills_installed}"
  check "installs the memory templates" test -f "${TEST_HOME}/.claude/projects/$(printf '%s' "${TEST_HOME}" | tr '/' '-')/memory/MEMORY.md"
  check "does not ask for a backup when nothing exists" test -z "$(grep 'Back up your current config' <<<"${OUTPUT}" || true)"
  check "does not touch .zshrc" test ! -e "${TEST_HOME}/.zshrc"
}

test_second_run_changes_nothing() {
  printf '\nSecond run\n'
  new_home
  run_install 'y\nn\n'
  local before after
  before=$(tree_checksum "${TEST_HOME}/.claude")
  run_install 'y\nn\nn\n'
  after=$(tree_checksum "${TEST_HOME}/.claude")
  check "exits with 0" test "${STATUS}" -eq 0
  check "changes no file" test "${before}" == "${after}"
  check "reports nothing installed or replaced" test -z "$(grep -E '^  (Installed|Replaced) ' <<<"${OUTPUT}" || true)"
}

test_keep_existing_file() {
  printf '\nKeep a CLAUDE.md that differs\n'
  new_home
  mkdir -p "${TEST_HOME}/.claude"
  printf 'my own rules\n' >"${TEST_HOME}/.claude/CLAUDE.md"
  run_install 'y\nn\n\nn\n'
  check "exits with 0" test "${STATUS}" -eq 0
  check "leaves the file unchanged" test "$(cat "${TEST_HOME}/.claude/CLAUDE.md")" == "my own rules"
}

test_show_diff_then_keep() {
  printf '\nShow the diff, then keep\n'
  new_home
  mkdir -p "${TEST_HOME}/.claude"
  printf 'my own rules\n' >"${TEST_HOME}/.claude/CLAUDE.md"
  run_install 'y\nn\nd\nk\nn\n'
  check "exits with 0" test "${STATUS}" -eq 0
  check "shows the user's line in the diff" grep -q -- '-my own rules' <<<"${OUTPUT}"
  check "asks again after the diff" test "$(grep -c '\[r\] replace' <<<"${OUTPUT}")" -eq 2
  check "leaves the file unchanged" test "$(cat "${TEST_HOME}/.claude/CLAUDE.md")" == "my own rules"
}

test_replace_with_backup() {
  printf '\nReplace a CLAUDE.md that differs, after a backup\n'
  new_home
  mkdir -p "${TEST_HOME}/.claude"
  printf 'my own rules\n' >"${TEST_HOME}/.claude/CLAUDE.md"
  run_install 'y\ny\nr\nn\n'
  local backup
  backup=$(find "${TEST_HOME}/.claude-backups" -name CLAUDE.md 2>/dev/null | head -1)
  check "exits with 0" test "${STATUS}" -eq 0
  check "installs the repository version" cmp -s "${REPO_DIR}/CLAUDE.md" "${TEST_HOME}/.claude/CLAUDE.md"
  check "keeps the old version in the backup" test "$(cat "${backup}" 2>/dev/null)" == "my own rules"
  check "prints how to restore the backup" grep -q './restore.sh' <<<"${OUTPUT}"
}

test_merge_settings() {
  printf '\nMerge a settings.json that differs\n'
  new_home
  mkdir -p "${TEST_HOME}/.claude"
  printf '{"theme":"dark","permissions":{"deny":["Bash(rm:*)"]},"mine":1}\n' >"${TEST_HOME}/.claude/settings.json"
  run_install 'y\nn\nm\nn\n'
  local merged="${TEST_HOME}/.claude/settings.json"
  check "exits with 0" test "${STATUS}" -eq 0
  check "keeps the user's theme" test "$(jq -r .theme "${merged}")" == "dark"
  check "keeps the user's own key" test "$(jq -r .mine "${merged}")" == "1"
  check "keeps the user's deny rule" jq -e '.permissions.deny | index("Bash(rm:*)")' "${merged}"
  check "adds the repository deny rules" jq -e '.permissions.deny | index("Bash(git push --force:*)")' "${merged}"
  check "adds the missing model key" test "$(jq -r .model "${merged}")" == "opus"
  check "keeps the file private" test "$(stat -c %a "${merged}")" == "600"
}

test_invalid_settings_kept() {
  printf '\nMerge a settings.json that is not valid JSON\n'
  new_home
  mkdir -p "${TEST_HOME}/.claude"
  printf '{ not json\n' >"${TEST_HOME}/.claude/settings.json"
  run_install 'y\nn\nm\nn\n'
  check "exits with 0" test "${STATUS}" -eq 0
  check "leaves the file unchanged" test "$(cat "${TEST_HOME}/.claude/settings.json")" == "{ not json"
}

test_skills_group() {
  printf '\nSkills that differ, replaced all at once\n'
  new_home
  run_install 'y\nn\n'
  printf 'edited\n' >>"${TEST_HOME}/.claude/skills/docker-guide/SKILL.md"
  printf 'edited\n' >>"${TEST_HOME}/.claude/skills/terraform-guide/SKILL.md"
  mkdir -p "${TEST_HOME}/.claude/skills/my-own-skill"
  run_install 'y\nn\na\nn\n'
  check "exits with 0" test "${STATUS}" -eq 0
  check "lists the skills that differ" grep -q '2 skills differ' <<<"${OUTPUT}"
  check "replaces them" cmp -s "${REPO_DIR}/skills/docker-guide/SKILL.md" "${TEST_HOME}/.claude/skills/docker-guide/SKILL.md"
  check "leaves the user's own skill alone" test -d "${TEST_HOME}/.claude/skills/my-own-skill"
}

test_memory_never_replaced() {
  printf '\nExisting memory notes\n'
  new_home
  local mem_dir
  mem_dir="${TEST_HOME}/.claude/projects/$(printf '%s' "${TEST_HOME}" | tr '/' '-')/memory"
  mkdir -p "${mem_dir}"
  printf 'my notes\n' >"${mem_dir}/MEMORY.md"
  run_install 'y\nn\n'
  check "exits with 0" test "${STATUS}" -eq 0
  check "keeps the user's MEMORY.md" test "$(cat "${mem_dir}/MEMORY.md")" == "my notes"
}

test_no_terminal() {
  printf '\nNo terminal and no --yes\n'
  new_home
  STATUS=0
  OUTPUT=$(HOME="${TEST_HOME}" NO_COLOR=1 bash "${REPO_DIR}/install.sh" </dev/null 2>&1) || STATUS=$?
  check "exits with 1" test "${STATUS}" -eq 1
  check "writes nothing" test ! -e "${TEST_HOME}/.claude"
}

test_cancel() {
  printf '\nAnswer no to Continue\n'
  new_home
  run_install 'n\n'
  check "exits with 3" test "${STATUS}" -eq 3
  check "writes nothing" test ! -e "${TEST_HOME}/.claude"
}

test_yes_mode() {
  printf '\n--yes with a CLAUDE.md that differs\n'
  new_home
  mkdir -p "${TEST_HOME}/.claude"
  printf 'my own rules\n' >"${TEST_HOME}/.claude/CLAUDE.md"
  STATUS=0
  OUTPUT=$(HOME="${TEST_HOME}" NO_COLOR=1 bash "${REPO_DIR}/install.sh" --yes </dev/null 2>&1) || STATUS=$?
  check "exits with 0" test "${STATUS}" -eq 0
  check "keeps the file" test "$(cat "${TEST_HOME}/.claude/CLAUDE.md")" == "my own rules"
  check "makes a backup" test -d "${TEST_HOME}/.claude-backups"
  check "skips herdr" test ! -e "${TEST_HOME}/.zshrc"
}

test_bad_option() {
  printf '\nUnknown option\n'
  new_home
  run_install '' --nope
  check "exits with 2" test "${STATUS}" -eq 2
}

test_colors() {
  printf '\nColors\n'
  if ! command -v script >/dev/null 2>&1; then
    printf '  skipped (the script command is not available)\n'
    return 0
  fi
  local escape=$'\033['
  new_home
  OUTPUT=$(printf 'n\n' | HOME="${TEST_HOME}" script -qec "bash '${REPO_DIR}/install.sh'" /dev/null 2>&1 || true)
  check "uses colors in a terminal" grep -qF "${escape}" <<<"${OUTPUT}"
  OUTPUT=$(printf 'n\n' | HOME="${TEST_HOME}" NO_COLOR=1 script -qec "bash '${REPO_DIR}/install.sh'" /dev/null 2>&1 || true)
  check "uses no colors with NO_COLOR" test -z "$(grep -F "${escape}" <<<"${OUTPUT}" || true)"
}

main() {
  test_fresh_install
  test_second_run_changes_nothing
  test_keep_existing_file
  test_show_diff_then_keep
  test_replace_with_backup
  test_merge_settings
  test_invalid_settings_kept
  test_skills_group
  test_memory_never_replaced
  test_no_terminal
  test_cancel
  test_yes_mode
  test_bad_option
  test_colors
  finish
}

main "$@"
