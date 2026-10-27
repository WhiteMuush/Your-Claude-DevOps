#!/usr/bin/env bash
# Creates the Python environment of the diagram tool, once.
set -euo pipefail

readonly VENV="${HOME}/.cache/drawing-architecture-diagrams/venv"

main() {
    if [[ -x "${VENV}/bin/python" ]] && "${VENV}/bin/python" -c "import cairosvg, PIL" 2>/dev/null; then
        printf 'ok: %s\n' "${VENV}/bin/python"
        return 0
    fi
    python3 -m venv "${VENV}"
    "${VENV}/bin/pip" -q install cairosvg pillow
    printf 'changed: %s\n' "${VENV}/bin/python"
}

main "$@"
