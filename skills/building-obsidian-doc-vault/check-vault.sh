#!/usr/bin/env bash
# Checks in a single awk pass that every vault note links to its one parent and that every link resolves.
set -euo pipefail

usage() {
    printf 'usage: %s <vault> [hub, default Home]\n' "${0##*/}" >&2
    exit 2
}

# Writes the note list on stdout, NUL separated, without the root README.
list_notes() {
    local vault="$1"
    find "${vault}/" -name '*.md' -not -path '*/.obsidian/*' -not -path '*/.git/*' \
        -not -path "${vault}/README.md" -print0 | sort -z
}

# Prints PASS on stdout, each error on stderr, and exits 1 on the first problem found.
check_notes() {
    local hub="$1"
    shift
    awk -v hub="${hub}" '
    function err(msg) { print "FAIL " msg > "/dev/stderr"; errors++ }

    FNR == 1 {
        name = FILENAME; sub(/.*\//, "", name); sub(/\.md$/, "", name)
        if (name in seen) err(name ": duplicate name, [[" name "]] links become ambiguous")
        seen[name] = 1; total++; code = 0
        if ($0 == "---") err(name ": frontmatter is not allowed")
        if (name != hub) {
            # Any label works ("Theme: [[X]]", "Thème : [[X]]"), only the link matters.
            if ($0 ~ /^[^[]+: \[\[[^]]+\]\]$/) {
                p = $0; sub(/^[^[]+: \[\[/, "", p); sub(/\]\]$/, "", p); parent[name] = p
            } else err(name ": line 1 is not \"Theme: [[Parent]]\"")
        }
    }

    # The em dash is written as UTF-8 bytes so it never appears in this file.
    /\342\200\224/ && !(name in dash) { dash[name] = 1; err(name ": em dash") }

    # Obsidian ignores links inside code blocks, so does this check.
    /^[[:space:]]*```/ { code = !code; next }

    !code {
        line = $0
        while (match(line, /\[\[[^]]+\]\]/)) {
            target = substr(line, RSTART + 2, RLENGTH - 4)
            line = substr(line, RSTART + RLENGTH)
            sub(/\|.*/, "", target); sub(/#.*/, "", target)
            links++; from[links] = name; to[links] = target
        }
    }

    END {
        if (!(hub in seen)) err(hub ".md is missing")
        for (i = 1; i <= links; i++) {
            s = from[i]; t = to[i]; linked[s SUBSEP t] = 1
            if (!(t in seen)) err(s ": broken link [[" t "]]")
            # Test with "in" before reading: in awk, reading parent[x] creates an empty entry.
            else if (!((s in parent) && t == parent[s]) && !((t in parent) && parent[t] == s))
                err(s ": cross link to [[" t "]], only the parent and the children are allowed")
        }
        for (n in parent) {
            if (!(parent[n] in seen)) err(n ": parent [[" parent[n] "]] not found")
            else if (!((parent[n] SUBSEP n) in linked)) err(n ": missing from the list in [[" parent[n] "]]")
        }
        if (errors) { print errors " error(s)" > "/dev/stderr"; exit 1 }
        print "PASS " total " notes"
    }
    ' "$@"
}

main() {
    [[ $# -ge 1 && $# -le 2 ]] || usage
    local vault="${1%/}" hub="${2:-Home}"
    [[ -d "${vault}" ]] || { printf 'FAIL %s is not a directory\n' "${vault}" >&2; exit 2; }

    local -a notes
    mapfile -d '' notes < <(list_notes "${vault}")
    [[ ${#notes[@]} -gt 0 ]] || { printf 'FAIL no note in %s\n' "${vault}" >&2; exit 1; }

    check_notes "${hub}" "${notes[@]}"
}

main "$@"
