# shellcheck shell=bash
# The installer's screens, in the order main runs them.

count_entries() {
  local path count=0
  for path in "$1"/*; do
    [[ -e ${path} ]] && count=$((count + 1))
  done
  printf '%s' "${count}"
}

show_welcome() {
  local skills
  skills=$(count_entries "${REPO_DIR}/skills")
  ui_title "Your Claude DevOps installer"
  ui_explain "This copies the Claude Code configuration from this repository into ~/.claude."
  printf '\n'
  ui_info "It goes through 5 steps:"
  ui_info "  1. CLAUDE.md       the rules Claude follows in every project"
  ui_info "  2. settings.json   permissions, model, theme and plugins"
  ui_info "  3. Skills          ${skills} guides Claude reads before a task"
  ui_info "  4. Hooks, memory   automatic scripts and the notes folder"
  ui_info "  5. herdr           an optional workspace, asked at the end"
  printf '\n'
  ui_explain "Nothing is replaced without asking you first."
  ui_explain "Never touched: your credentials, your history and your existing memory notes."
  printf '\n'
}

confirm_start() {
  CURRENT_STEP="the confirmation"
  if ! ui_confirm "Continue?" y; then
    ui_info "Cancelled. Nothing was changed."
    exit 3
  fi
}

step_claude_md() {
  CURRENT_STEP="step 1, CLAUDE.md"
  ui_title "Step 1/5: CLAUDE.md"
  ui_explain "This file holds the rules Claude follows in every project."
  ui_explain "It is copied to ~/.claude/CLAUDE.md."
  printf '\n'
  handle_item CLAUDE.md "${REPO_DIR}/CLAUDE.md" "${CLAUDE_DIR}/CLAUDE.md"
}

step_settings() {
  CURRENT_STEP="step 2, settings.json"
  ui_title "Step 2/5: settings.json"
  ui_explain "This file holds Claude Code's settings: permissions, model, theme and plugins."
  ui_explain "It is copied to ~/.claude/settings.json."
  printf '\n'
  install_settings "${REPO_DIR}/settings.json" "${CLAUDE_DIR}/settings.json"
}

step_skills() {
  CURRENT_STEP="step 3, skills"
  ui_title "Step 3/5: Skills"
  ui_explain "Skills are guides Claude reads before a task, for example Docker or Terraform."
  ui_explain "They are copied to ~/.claude/skills/. Skills you added yourself are left alone."
  printf '\n'
  handle_group skills "${REPO_DIR}/skills" "${CLAUDE_DIR}/skills"
}

step_hooks_and_memory() {
  CURRENT_STEP="step 4, hooks and memory"
  ui_title "Step 4/5: Hooks and memory"
  ui_explain "Hooks are small scripts Claude Code runs automatically, like the skill reminder."
  ui_explain "They are copied to ~/.claude/hooks/."
  printf '\n'
  handle_group hooks "${REPO_DIR}/hooks" "${CLAUDE_DIR}/hooks"
  printf '\n'
  ui_explain "Memory is where Claude keeps notes between sessions. Existing notes are never replaced."
  printf '\n'
  install_memory_templates
}

install_memory_templates() {
  local memkey mem_dir file name
  # The project key is the home folder with slashes turned into dashes, /home/alice gives -home-alice.
  memkey=$(printf '%s' "${HOME}" | tr '/' '-')
  mem_dir="${CLAUDE_DIR}/projects/${memkey}/memory"
  for file in "${REPO_DIR}"/memory/*.md; do
    name=$(basename "${file}")
    if [[ -e ${mem_dir}/${name} ]]; then
      ui_kept "Kept your existing memory/${name}"
      record kept "memory/${name}"
    else
      copy_into_place "${file}" "${mem_dir}/${name}"
      ui_ok "Installed memory/${name}"
      record installed "memory/${name}"
    fi
  done
}

step_herdr() {
  CURRENT_STEP="step 5, herdr"
  ui_title "Step 5/5: herdr (optional)"
  ui_explain "herdr opens Claude on the left and a shell on the right when you type claude."
  ui_explain "It adds one line to ~/.zshrc and only works with zsh."
  printf '\n'

  if (( WANT_HERDR )); then
    ui_info "--herdr was given, installing herdr."
  elif ! ui_confirm "Install herdr?" n; then
    ui_kept "Skipped herdr"
    record skipped herdr
    return 0
  fi

  if ! check_herdr_dependencies; then
    record skipped herdr
    return 0
  fi
  ensure_herdr
  install_wrapper
  ensure_herdr_hook
  record installed herdr
}

show_summary() {
  CURRENT_STEP="the summary"
  ui_title "Done"
  ui_summary_line installed "Installed" 0
  ui_summary_line replaced "Replaced" 1
  ui_summary_line merged "Merged" 1
  ui_summary_line kept "Kept" 1
  ui_summary_line unchanged "Unchanged" 0
  ui_summary_line skipped "Skipped" 1

  if [[ -n ${BACKUP_DIR} ]]; then
    printf '\n'
    ui_info "Your backup is in $(pretty_path "${BACKUP_DIR}")"
    ui_explain "To restore it: cp -a \"${BACKUP_DIR}/.\" ~/.claude/"
  fi

  printf '\n'
  ui_info "Restart Claude Code to load the new configuration."
  ui_explain "The i-have-adhd plugin installs itself on the next start. If it does not, run in Claude Code:"
  ui_explain "  /plugin marketplace add ayghri/i-have-adhd"
  ui_explain "  /plugin install i-have-adhd"
  if [[ $(summary_names installed) == *herdr* ]]; then
    ui_explain "Open a new terminal: typing claude now starts herdr."
  fi
  printf '\n'
}
