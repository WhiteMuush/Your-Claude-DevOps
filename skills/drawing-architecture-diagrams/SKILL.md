---
name: drawing-architecture-diagrams
description: Use when a README, a doc or a presentation needs a readable architecture diagram with the tools' logos, in the draw.io style, or when a Mermaid diagram is considered too technical or unclear. Triggers on "schematic", "diagram", "architecture", "draw.io", "logos", "README image", "simpler diagram".
---

# Architecture diagrams with logos

## Principle

A single diagram that tells the system's story from left to right, with the **official logos**. The result is a **self-contained SVG** (logos embedded as data URIs): it renders the same on GitLab and GitHub, which block external links inside an SVG.

**The mandatory style:**

- white background, logos in the brand's color, size 56 (50 for cloud services);
- under each logo: a black title, then a short grey caption;
- black right-angle arrows, label in **bold**;
- rounded frames: `cloud` (dashed blue), `cluster` (solid blue), `zone` (dashed grey);
- external actors (people, SaaS, Terraform) **outside** the frames, on the edges.

## Tool

```bash
~/.claude/skills/drawing-architecture-diagrams/setup.sh     # once, creates the venv
~/.cache/drawing-architecture-diagrams/venv/bin/python spec.py docs/architecture.svg
```

`diagram.py` provides `Diagram(w, h)` with `frame`, `node`, `person`, `arrow`, `text`, `save`, and `zoom(png, box)`. The docstring at the top of the file gives a complete example. `save` also writes a PNG to `~/.cache/drawing-architecture-diagrams/`: **that is the one you look at** with the Read tool.

## Steps

1. **List** the components and the flows, then write the story in one sentence from left to right.
2. **Place on a grid**: columns spaced 150 to 160 px apart, rows 100 to 190 px apart. Starting canvas 1280 x 720.
3. **Choose the logos** (table below).
4. **Write the spec** in Python in the scratchpad, not in the repository.
5. **Render, then look at the PNG.** Zoom with `zoom` on each busy area.
6. **Fix** using the checklist, then repeat step 5.
7. **Deliver** the SVG in `docs/`, and in the README: `![Architecture](docs/architecture.svg)`.

## Logo sources

| Source | For | Pitfall |
|---|---|---|
| `simple:<slug>` | Brands (gitlab, kubernetes, grafana, argo, traefikproxy, victoriametrics, terraform) | No Microsoft or Azure logos. Test the slug: `curl -I https://cdn.simpleicons.org/<slug>` must return 200 |
| `azure:<Nom>` | Official Azure services (Kubernetes-Services, Storage-Accounts, Monitor, Managed-Identities) | Exact file name, without the numeric prefix |
| `url:<svg>` | Official logo in the project's repository (cert-manager, Velero) | Check that it is a logo and not a banner or a logo with text |
| `crop="x y w h"` | Keep only the icon of a logo with text | Velero: `url:.../site/static/img/Velero.svg` with `crop="8 8 184 184"` |

skillicons.dev returns an **empty 256-byte** icon for an unknown name (argocd, helm), with no error: do not rely on it.

## Checklist after each render

- A logo is empty: its SVG had no `viewBox` or the slug does not exist.
- A logo is cut off or keeps a piece of text: adjust `crop`.
- A label touches an arrow, a logo or a frame border: move it with `at=`.
- An arrow crosses a caption: change its path or shift the node.
- An arrow comes in from below: the caption takes about 45 px under the logo, so the tip stops lower, or the arrow comes in from the side.
- An arrow touches the logo: leave 2 to 4 px between the tip and the edge of the logo.
- More than 20 nodes: the diagram is no longer readable, make two of them or merge nodes.

## Common mistakes

| Mistake | Consequence |
|---|---|
| Delivering without looking at the PNG | Invisible logo or unreadable label discovered by the user |
| Mermaid when you want logos | Text boxes, different rendering between GitLab and GitHub |
| `<image href="https://...">` in the SVG | Logo missing on GitLab and GitHub |
| All the technical details in the diagram | Unreadable: details go in a table under the diagram |
