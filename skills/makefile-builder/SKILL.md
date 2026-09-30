---
name: makefile-builder
description: À utiliser quand un Makefile devient le point d'entrée d'un projet, orchestre plusieurs composants ou dépôts, ou dépasse quelques cibles. Se déclenche avec "Makefile", "make", "cible make", "point d'entrée unique", "orchestrer le déploiement", "make deploy", "make help", "un seul endroit pour tout lancer".
---

# Makefile d'orchestration

## Principe

Un Makefile d'orchestration **déclare et câble, il n'exécute pas**. Chaque décision descend dans un script, qui se lit sans connaître Make et se débogue en le lançant seul.

Dès qu'il dépasse quelques cibles, il se découpe en fragments inclus, un par composant.

## Structure

```
Makefile                 configuration, includes, rien d'autre
makefiles/
  common.mk              ce qui n'appartient à aucun composant
  component.mk           ce que les composants partagent
  infra.mk               un fragment par composant
  backend.mk
  frontend.mk
scripts/
  lib.sh                 sourcé par les autres : sortie, log, garde-fous
  <action>.sh            une action, un script
```

Racine :

```make
SHELL := /usr/bin/env bash
.SHELLFLAGS := -euo pipefail -c
.DEFAULT_GOAL := help

ORG      ?= my-org
LOG_FILE ?= .logs/pipeline.log
PIPELINE := scripts

# Exporté, jamais passé en positionnel : les scripts lisent l'environnement.
export ORG LOG_FILE

include makefiles/component.mk
include makefiles/backend.mk
include makefiles/common.mk
```

`help` en cible par défaut : un `make` nu liste, il ne déploie pas.

## Configuration : exporter, pas passer en positionnel

L'erreur la plus coûteuse observée. Les scripts finissent avec `(( $# == 7 ))` et `repos=("$1" "$3" "$5")`, et ajouter un composant casse l'arité de tous les appelants.

```make
# NON : arité fragile, illisible, ne passe pas à l'échelle
check:
	@scripts/check.sh "$(R1)" "$(W1)" "$(R2)" "$(W2)" "$(R3)" "$(W3)" "$(REF)"

# OUI : exporté une fois à la racine, lu par le script
check:
	@scripts/check.sh
```

Les arguments restent pour ce qui varie **par appel**, pas pour la configuration.

## Factoriser sans casser l'aide

Six cibles `deploy-*` et `teardown-*` quasi identiques, c'est le défaut classique. Mais **une cible générée par `$(eval)` est invisible dans l'aide**, parce que l'aide lit le texte source des fichiers.

La factorisation se met donc dans l'appel, pas dans la déclaration :

```make
# component.mk
run = $(PIPELINE)/dispatch.sh --repo "$(ORG)/$(1)" --workflow "$(2)" --label "$(3)"

# backend.mk
backend: ## Build and deploy the backend
	@$(call run,$(BACKEND_REPO),ci-cd.yml,backend)
```

Trois lignes lisibles par composant, une seule définition de la commande.

## Aide auto-documentée

Jamais une liste de `@echo` : elle dérive des cibles réelles. Sections `##@`, descriptions `##`, un script qui parse le Makefile et ses includes.

```make
##@ Deploy

deploy: ## Deploy everything in order
	@$(MAKE) infra
```

Le script **collecte puis regroupe** avant d'imprimer : une section est déclarée dans le fragment qui possède la cible, donc elle apparaît dans plusieurs fichiers et une impression au fil de l'eau répète ses en-têtes. Piloter couleur **et** ordre depuis une seule liste `Section=couleur`.

## Ordre : make récursif, pas des prérequis

```make
# NON : make peut réordonner ou paralléliser. .NOTPARALLEL est un marteau global.
deploy: infra backend frontend

# OUI : l'ordre est le sujet, il s'écrit
deploy:
	@$(MAKE) infra
	@$(MAKE) backend
	@$(MAKE) frontend
```

## Contrat de sortie : celui d'Ansible

Reprendre son vocabulaire, sa palette et son `PLAY RECAP`. Il répond déjà aux questions qu'un opérateur pose.

| Issue | Sens | Couleur |
|---|---|---|
| `ok` | déjà dans l'état voulu, rien fait | vert |
| `changed` | ne l'était pas, ce run l'a changé | jaune |
| `skipping` | ne s'applique pas, ou non évaluable ici | cyan |
| `unreachable` | la chose n'a pas pu être contactée | rouge vif |
| `fatal` | contactée, évaluée, et elle est fausse | rouge |

Les deux que tout le monde oublie sont les deux qui comptent :

- **`changed` rend l'idempotence visible.** Un second run à `changed=0` la prouve, là où un commentaire ne fait que l'affirmer.
- **`unreachable` sépare le réseau de la configuration.** Sans lui, une API muette est rapportée comme une config cassée, et c'est la fausse alerte qui fait cesser de lire la sortie.

```
TASK [github : workflows can be triggered by hand] *****************
fatal:       [backend] ci-cd.yml has no workflow_dispatch
             add it, and widen the 'if: github.event_name' guards

PLAY RECAP ********************************************************
doctor      : ok=11  unreachable=0   failed=4   skipped=0
```

### Les mots viennent de l'outil, la forme vient d'Ansible

Ansible fournit la **forme** : `TASK [...]`, une issue par ligne, la palette, le `PLAY RECAP`, le code de sortie. Les **mots** des issues et des compteurs se choisissent d'après ce qui tourne, pour que chaque chiffre réponde à une question que l'opérateur se pose sur cet outil.

La recette :

1. Lister ce que l'opérateur veut savoir après un run de cet outil précis.
2. Un compteur par réponse, nommé avec le vocabulaire de l'outil.
3. Rattacher chaque compteur à une couleur de la palette : vert = état voulu, jaune = quelque chose change ou va changer, cyan = non applicable, rouge vif = injoignable, rouge = faux ou en échec.
4. Garder un seul compteur qui prouve l'idempotence : celui des changements, qui doit valoir 0 au second run, quel que soit son nom.
5. Un compteur qui ne peut jamais dépasser 0 pour cet outil n'apparaît pas.

| Ce qui tourne | Recap adapté |
|---|---|
| Diagnostic en lecture seule | `doctor : ok=11  unreachable=0  failed=4  skipped=0` |
| Terraform plan / apply | `terraform : checked=3  add=1  change=0  destroy=0  applied=1  failed=0` |
| Déploiement Helm | `helm : installed=1  upgraded=2  unchanged=3  failed=0` |
| Suite de tests | `tests : passed=42  failed=1  skipped=3` |

Les issues par ligne suivent la même logique : `to add:`, `applied:`, `upgraded:`, `passed:` quand ces mots disent mieux ce qui s'est passé que `ok:` ou `changed:`.

Le code de sortie est l'interface machine : non nul si `failed` ou `unreachable`. **`skipped` ne fait jamais échouer** : non applicable n'est pas faux.

Prévoir une cible `doctor` qui ne s'arrête pas au premier problème : tout savoir en un passage est son intérêt. Toutes les autres s'arrêtent au premier.

## Fichier de log obligatoire

```make
LOG_FILE ?= .logs/pipeline.log
export LOG_FILE
```

- **Append**, jamais troncature : la tentative précédente explique celle-ci
- En-tête horodaté par exécution, **et horodatage par ligne**
- **Sans séquences ANSI** : le terminal garde ses couleurs, le fichier reste greppable
- `chmod 600`, et jamais un token dedans
- **Écrire directement, pas via `tee` et substitution de processus** : ce montage perd sa fin quand le shell sort avant que l'écrivain ait drainé, et la fin du log est justement ce qu'on vient y chercher
- Ajouter `.logs/` au `.gitignore`

## Erreurs fréquentes

| Erreur | Conséquence |
|---|---|
| Tout dans un seul Makefile | Illisible dès la dixième cible, aucune séparation par composant |
| Configuration en arguments positionnels | Arité fragile, un composant de plus casse tous les appelants |
| Cibles générées par `$(eval)` | Invisibles dans une aide qui lit le source |
| `help` en `@echo` | Dérive des cibles réelles en silence |
| Ordre exprimé en prérequis | Make est libre de réordonner, `.NOTPARALLEL` masque le problème |
| `A && B \|\| C` comme if-then-else | C s'exécute aussi si B échoue, les compteurs deviennent faux |
| Pas de compteur de changements | L'idempotence reste une intention invisible |
| Pas de fichier de log | La sortie de l'incident a disparu avec le terminal |
| Dépendre de `jq` | `gh --jq` et `az --query` le font déjà |

## Vérifier

```bash
make            # liste, ne déploie pas
make lint       # shellcheck -x, avec # shellcheck source= au-dessus de chaque source
<script>        # se lance seul, hors de make
<script>        # deux fois : au second run, le compteur de changements vaut 0
```

**REQUIRED BACKGROUND :** pour le contenu des scripts eux-mêmes, contrat stdout/stderr, garde-fous, idempotence, utiliser `bash-script-builder`.
