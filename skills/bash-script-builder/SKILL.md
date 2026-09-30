---
name: bash-script-builder
description: Scripts shell d'infrastructure et d'automatisation DevOps, découpage obligatoire en fonctions et en fichiers, contrat stdout/stderr, idempotence, garde-fous sur les opérations qui coupent l'accès, fichiers de log et codes de sortie. Se déclenche avec "script bash", "script shell", ".sh", "Makefile", "automatiser", "script de déploiement", "script d'admin", "shellcheck".
---

# Scripts bash DevOps

## Ce que ce skill n'enseigne pas

Un agent compétent écrit déjà spontanément `set -euo pipefail`, un trap ERR, des codes de sortie distincts, la validation des entrées, l'idempotence par lecture de l'état courant, `--dry-run`, `usage()` et des logs horodatés. Ne pas perdre de lignes là-dessus.

Ce skill couvre les angles morts observés, ceux qui passent la relecture et cassent en production.

## Structure : tout en fonctions, puis en fichiers

**Règle non négociable : aucun code métier au niveau du fichier.** Chaque étape est une fonction nommée par ce qu'elle garantit (`ensure_role`, `check_token`), et le script se termine par `main "$@"`.

Au niveau du fichier, il ne reste que :

1. le shebang et `set -euo pipefail` ;
2. le `source` des bibliothèques ;
3. la validation des variables d'entrée et les `readonly` ;
4. les définitions de fonctions ;
5. l'appel `main "$@"`.

`main` se lit comme un sommaire : une suite d'appels de fonctions, sans logique.

**Réutiliser avant d'écrire.** Avant de coder un helper (log, rapport, recap, lecture d'un token), chercher la bibliothèque déjà présente dans le dépôt (`lib.sh`, `scripts/*/lib.sh`) et la sourcer. Ne jamais redéfinir un helper qui existe déjà.

**Découper en fichiers** dès que l'un de ces cas se présente :

| Cas | Découpage |
|---|---|
| Le script dépasse environ 150 lignes | Un fichier par groupe de fonctions, sourcé par le script principal |
| Il couvre des fonctionnalités distinctes (identité, réseau, CI...) | Un script par fonctionnalité, chacun avec son `main` |
| Plusieurs scripts ont besoin du même helper | Le helper va dans la bibliothèque partagée |

Chaque fichier sourcé reçoit son `# shellcheck source=chemin` au-dessus du `source`. Si un Makefile existe, chaque script de fonctionnalité a sa propre cible.

**Piège propre aux fonctions : le sous-shell.** Une fonction appelée via `$(...)` tourne dans un sous-shell. Les compteurs et les variables globales qu'elle modifie sont perdus au retour. Une fonction qui met à jour un état (recap, compteurs) s'appelle directement et écrit dans une variable globale ; elle n'est jamais capturée.

## Le contrat stdout / stderr

**stdout porte les données, stderr porte les diagnostics.** Ce n'est pas une préférence de style, c'est ce qui rend un script composable.

Le piège concret : une fonction qui renvoie une valeur par capture, et qui logue au même endroit.

```bash
# CASSÉ : la variable récupère les logs collés à la valeur
ensure_group() {
    local id; id=$(lookup "$1")
    log_ok "groupe '$1' trouvé"      # part sur stdout
    printf '%s' "${id}"
}
group_id=$(ensure_group admins)       # contient le log ET l'id

# CORRECT : tout ce qui n'est pas la valeur de retour part sur stderr
ensure_group() {
    local id; id=$(lookup "$1")
    log_ok "groupe '$1' trouvé" >&2
    printf '%s' "${id}"
}
```

Règle simple : **dans une fonction dont la sortie est capturée, stdout est réservé à la valeur de retour.** Un commentaire au-dessus de la fonction le rappelle au relecteur.

Corollaire : les niveaux WARN et ERROR vont toujours sur stderr, y compris quand le script n'a pas de valeur de retour.

## Garde-fous : prouver le nouveau chemin avant de couper l'ancien

L'erreur la plus coûteuse d'un script de durcissement n'est pas un bug de syntaxe, c'est de **supprimer le dernier accès dont on dispose**.

Deux familles d'opérations demandent un garde-fou explicite :

**Les filtres réseau.** Avant d'appliquer une allowlist, vérifier que l'adresse de sortie courante y est couverte. Sinon, avertir et exiger une confirmation.

```bash
my_ip=$(curl -fsS --max-time 10 https://api.ipify.org || true)
if [[ -n "${my_ip}" && ",${ALLOWED_CIDR}," != *",${my_ip}/32,"* ]]; then
    log_warn "${my_ip} n'est pas dans la liste, vous allez perdre l'accès"
    confirm "appliquer quand même ?" || die "abandon"
fi
```

**Le retrait d'un moyen d'authentification.** Ne jamais désactiver l'ancien avant d'avoir vérifié que le nouveau est **opérationnel**, pas seulement créé. Un groupe d'identité vide, ou créé mais non rattaché à la ressource, n'est pas un chemin d'accès.

```bash
members=$(count_members "${ADMIN_GROUP}")
[[ "${members}" -gt 0 ]] || die "groupe admin vide, refus de désactiver les comptes locaux"
```

Ordonner les étapes en conséquence : **établir et tester le nouvel accès, puis retirer l'ancien.** Jamais l'inverse.

## Idempotence : elle se prouve, elle ne se suppose pas

Lire l'état courant avant d'écrire ne suffit pas. Le défaut classique est un `if` qui constate puis agit quand même :

```bash
# CASSÉ : log puis exécution inconditionnelle
if [[ "$(current_state)" == "enabled" ]]; then
    log_ok "déjà activé"
fi
run enable-the-thing        # l'API refuse : déjà activé

# CORRECT
if [[ "$(current_state)" == "enabled" ]]; then
    log_ok "déjà activé"
else
    run enable-the-thing
fi
```

**La vérification, c'est de lancer le script deux fois de suite.** La seconde exécution doit se terminer sans erreur et sans rien changer. Tant que ça n'a pas été fait, l'idempotence est une intention, pas une propriété.

Attention aussi aux API qui refusent un drapeau d'activation sur une ressource déjà activée : le drapeau ne se passe qu'à la première fois, la mise à jour ultérieure porte sur les attributs seuls.

## Fichier de log

Un `--log-file` mal fait détruit l'information qu'il prétend conserver.

| Règle | Pourquoi |
|---|---|
| Ouvrir en **append**, jamais en troncature | `: > "$LOG_FILE"` efface l'historique, et les lignes déjà écrites pendant la validation |
| En-tête horodaté par exécution | Sépare les runs dans un fichier cumulatif |
| Horodatage **par ligne** | Un log sert à corréler avec un incident |
| Retirer les séquences ANSI | Le terminal garde ses couleurs, le fichier reste lisible et copiable |
| `chmod 600` | Un journal d'opérations d'infra n'a pas à être lisible par tous |
| Ne jamais journaliser une valeur sensible | Un helper qui affiche la ligne de commande complète capture les jetons passés en argument |

Si la redirection passe par `tee` et une substitution de processus, prévoir le drainage avant la sortie du shell, sinon la fin du log manque.

## Sortie lisible par un humain et par une machine

**Le code de sortie est l'interface machine** : 0 si tout est conforme, non nul sinon. C'est ce qui permet de brancher le script dans une CI.

**Le rapport est pour l'humain.** Sa sortie console suit le contrat d'Ansible décrit dans `makefile-builder` (section « Contrat de sortie ») : `TASK [...]`, une issue par ligne, palette Ansible, `PLAY RECAP` chiffré. Les mots des issues et des compteurs sont ceux de l'outil qui tourne, pas une liste figée. **REQUIRED BACKGROUND :** lire cette section de `makefile-builder` avant d'écrire la sortie d'un script, même sans Makefile.

Confondre "cassé" et "non vérifiable" produit de fausses alertes : un état `skipped` distinct de `failed` reste obligatoire.

Colorer seulement si la sortie est un terminal, et respecter `NO_COLOR`. Éviter `clear` et les manipulations de curseur : ça casse le passage dans un pipe et pollue les journaux de CI.

## Pièges de syntaxe et de lint

Passer `shellcheck -x` systématiquement, et le câbler dans une cible `make lint`. Le `-x` suit les fichiers sourcés, sans lui les bibliothèques partagées ne sont pas analysées. Ajouter `# shellcheck source=chemin/lib.sh` au-dessus de chaque `source`.

| Piège | Correction |
|---|---|
| `local x="$(cmd)"` (SC2155) | Déclarer puis affecter : `local x; x="$(cmd)"` |
| `.*?` dans `grep -E` ou `awk` | Syntaxe PCRE dans un contexte ERE. Utiliser `[^x]*` ou un `awk` avec `FS` adapté |
| `sed -u` | Spécifique GNU, ne tourne pas sur BSD ni macOS |
| Un seul `trap ... EXIT` | Bash n'en garde qu'un. Le second remplace le premier en silence |
| Regex de CIDR qui valide la forme | `999.999.999.999/99` passe. Valider aussi les valeurs si ça compte |

Côté Makefile : les variables issues d'un `include` deviennent des variables Make et **gagnent sur l'environnement**. `VAR=x make cible` reste sans effet, il faut écrire `make cible VAR=x`. Et `$(MAKEFILE_LIST)` contient les fichiers inclus, pas seulement le Makefile.

## Erreurs fréquentes

| Erreur | Conséquence |
|---|---|
| Loguer sur stdout dans une fonction capturée | La valeur de retour contient le log |
| Couper l'ancien accès avant de tester le nouveau | Verrouillage hors de la ressource administrée |
| Créer une identité et la considérer opérationnelle | Un groupe vide ou non rattaché n'ouvre aucun accès |
| `if` sans `else` avant une commande d'activation | L'API refuse au second passage, le script casse |
| Tronquer le fichier de log au démarrage | Perte de l'historique et des lignes déjà écrites |
| Confirmer à chaque étape d'un lot | L'opérateur finit par valider sans lire |
| `exit 0` quand l'utilisateur refuse | L'appelant ne distingue plus "fait" de "refusé" |
