#!/usr/bin/env bash
# Vérifie en un seul passage awk que chaque note du vault est reliée à son seul parent et que tous les liens résolvent.
set -euo pipefail

usage() {
    printf 'usage: %s <vault> [hub, défaut My-Brain]\n' "${0##*/}" >&2
    exit 2
}

# Écrit sur stdout la liste des notes, séparées par un octet nul, README de la racine exclu.
list_notes() {
    local vault="$1"
    find "${vault}/" -name '*.md' -not -path '*/.obsidian/*' -not -path '*/.git/*' \
        -not -path "${vault}/README.md" -print0 | sort -z
}

# Affiche PASS sur stdout, chaque erreur sur stderr, et sort en 1 au moindre problème.
check_notes() {
    local hub="$1"
    shift
    awk -v hub="${hub}" '
    function err(msg) { print "FAIL " msg > "/dev/stderr"; errors++ }

    FNR == 1 {
        name = FILENAME; sub(/.*\//, "", name); sub(/\.md$/, "", name)
        if (name in seen) err(name " : nom en double, les liens [[" name "]] deviennent ambigus")
        seen[name] = 1; total++; code = 0
        if ($0 == "---") err(name " : frontmatter interdit")
        if (name != hub) {
            if ($0 ~ /^Thème : \[\[[^]]+\]\]$/) {
                p = $0; sub(/^Thème : \[\[/, "", p); sub(/\]\]$/, "", p); parent[name] = p
            } else err(name " : ligne 1 différente de \"Thème : [[Parent]]\"")
        }
    }

    # Le tiret cadratin est écrit en octets UTF-8 pour ne jamais apparaître dans ce fichier.
    /\342\200\224/ && !(name in dash) { dash[name] = 1; err(name " : tiret cadratin") }

    # Obsidian ignore les liens dans un bloc de code, le contrôle aussi.
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
        if (!(hub in seen)) err(hub ".md absent")
        for (i = 1; i <= links; i++) {
            s = from[i]; t = to[i]; linked[s SUBSEP t] = 1
            if (!(t in seen)) err(s " : lien cassé [[" t "]]")
            # Tester avec "in" avant de lire : en awk, lire parent[x] crée une entrée vide.
            else if (!((s in parent) && t == parent[s]) && !((t in parent) && parent[t] == s))
                err(s " : lien croisé vers [[" t "]], seuls le parent et les enfants sont permis")
        }
        for (n in parent) {
            if (!(parent[n] in seen)) err(n " : parent [[" parent[n] "]] introuvable")
            else if (!((parent[n] SUBSEP n) in linked)) err(n " : absent de la liste de [[" parent[n] "]]")
        }
        if (errors) { print errors " erreur(s)" > "/dev/stderr"; exit 1 }
        print "PASS " total " notes"
    }
    ' "$@"
}

main() {
    [[ $# -ge 1 && $# -le 2 ]] || usage
    local vault="${1%/}" hub="${2:-My-Brain}"
    [[ -d "${vault}" ]] || { printf 'FAIL %s n'\''est pas un dossier\n' "${vault}" >&2; exit 2; }

    local -a notes
    mapfile -d '' notes < <(list_notes "${vault}")
    [[ ${#notes[@]} -gt 0 ]] || { printf 'FAIL aucune note dans %s\n' "${vault}" >&2; exit 1; }

    check_notes "${hub}" "${notes[@]}"
}

main "$@"
