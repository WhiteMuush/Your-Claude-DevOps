---
name: building-obsidian-doc-vault
description: Use when creating, reorganizing or extending an Obsidian vault of technical documentation (cheat sheets, procedures, how-to notes), when the Obsidian graph is unreadable, wrongly colored or rearranges itself on every opening, or when Claude must find the user's usual methods in their notes. Triggers on "Obsidian", "vault", "graph view", "graph.json", "cheat sheet", "quick docs", "knowledge base".
---

# Quick-docs Obsidian vault

A strict tree: hub, themes, sub-themes, notes. The graph stays readable as long as a note links **only to its parent and its children**.

## Structure

- One folder per theme or sub-theme, holding a note named **exactly** like the folder (`Kubernetes/Manifests/Manifests.md`) that lists its children as `[[...]]`.
- The hub, at the root, lists only the top-level themes.
- Note names start with their theme (`Terraform State GitLab`), so they are unique across the vault.
- Nothing else: no frontmatter, no templates, no `CLAUDE.md`. The pointer to the vault goes in Claude's memory, which then searches by folder and note name.

## Note format

````markdown
Theme: [[Parent]]

# Terraform State GitLab

One sentence that says what it is for, in plain words.

1. The step, then the block to copy:
   ```bash
   terraform init -migrate-state
   ```
   - `-migrate-state`: copies the local state to the new backend.
````

A pointer to another branch is plain text ("see the X note"), never a `[[link]]`.

## Check

`check-vault.sh <vault> [hub]` after every change (1,000 notes in under 0.1 s). It reports any break of the rules above and, like Obsidian, ignores links inside code blocks. Any label works on line 1 (`Theme:`, `Thème :`), only the link is checked.

## Graph colors

`colorGroups` in `.obsidian/graph.json`, one entry per folder:

```json
{ "query": "path:\"Terraform/\"", "color": { "a": 1, "rgb": 9133302 } }
```

- The trailing `/` is required: `path:"Terraform"` also colors `Secrets/Secrets Terraform.md`.
- `rgb` is decimal: `0x8B5CF6` = `9133302`.
- Obsidian rewrites this file: make sure it is closed before writing (on WSL, `tasklist.exe | grep -i obsidian`).
- The graph's "Restore default settings" button also wipes the colors.

## Frozen positions

Obsidian does not keep node positions. Without a third-party plugin: copy `frozen-graph/` into `.obsidian/plugins/` (one readable file, no dependency, no network).

- Commands "Freeze the graph" and "Release the graph". Dragging a node releases the graph, dropping it freezes everything again.
- Undocumented internal API (`renderer.worker.postMessage({ forceNode })`): an Obsidian update can disable it, without breaking anything.
- Enabling it means leaving Obsidian's restricted mode: read `main.js` first, and install no other plugin.
- Tests: `node --test frozen-graph/main.test.js`.

## Git

```gitignore
.obsidian/workspace*.json
.trash/
.obsidian/plugins/*
!.obsidian/plugins/frozen-graph/
.obsidian/community-plugins.json
```

A clone enables no plugin and syncs nothing. Read-only machine: `git remote set-url --push origin no_push`. Before publishing: `gitleaks git .`.

## Common mistakes

| Mistake | Effect |
|---|---|
| `[[link]]` to another branch | Tangled graph |
| `path:"Name"` without `/` | Notes from other branches get the wrong color |
| `graph.json` edited while Obsidian is open | Change overwritten |
| Community plugin to freeze the graph | Third-party code nobody reviewed |
