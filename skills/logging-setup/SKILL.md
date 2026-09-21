---
name: logging-setup
description: Mise en place et revue des logs d'infrastructure et d'application, format de présentation console imposé (==> / OK / WARN / FAIL), destination stdout/stderr, journal de run, niveaux, redaction des secrets, rotation et rétention. Couvre les spécificités Ansible, systemd et CI/CD, et renvoie à collecte.md pour les logs agrégés. Se déclenche avec "logs", "logging", "journalisation", "log_path", "no_log", "logrotate", "journald", "structured logging", "agrégation de logs", "rétention", "observabilité".
---

# Mise en place des logs

## Ce que ce skill n'enseigne pas

Un agent compétent horodate déjà ses lignes, met un niveau devant, et n'écrit pas `print()` partout. Ne pas dépenser de lignes là-dessus.

Ce skill couvre les décisions qui se prennent au moment du branchement, celles qu'on ne peut plus corriger sans migration une fois que le collecteur ingère.

## Présentation de la sortie : format imposé

**Cette section n'est pas une suggestion. La sortie a toujours cette allure, sur tous les projets.** Le reste du skill donne des bonnes pratiques à adapter, celle-ci est un invariant : un opérateur qui a lu un log d'un projet sait lire ceux des autres.

### Rendu attendu

```
==> Step 1: API server IP allowlist
    current allowlist: 10.0.0.0/8
    requested         : 10.0.0.0/8,203.0.113.7/32
  OK  allowlist applied, rules take up to 2 minutes to propagate
  WARN 203.0.113.7 is not listed explicitly
  FAIL could not reach the API server
```

Quatre marqueurs, jamais plus :

| Marqueur | Rôle | Flux | Couleur |
|---|---|---|---|
| `==>` | Ouverture d'une étape, précédée d'une ligne vide | stdout | bleu gras |
| (indentation seule) | Détail, contexte, valeur lue | stdout | aucune |
| `OK` | L'étape a abouti ou était déjà dans l'état voulu | stdout | vert |
| `WARN` | Anomalie absorbée, l'exécution continue | **stderr** | jaune |
| `FAIL` | Échec, suivi d'une sortie non nulle | **stderr** | rouge |

Règles de forme :

- **L'indentation porte la hiérarchie.** Étape à la colonne 0, détails à 4 espaces, marqueurs à 2 espaces. Un log qui se scanne à la verticale.
- **Pas de niveau supplémentaire.** Pas de `DEBUG` visible, pas de `NOTICE`, pas d'émoji. Ce qui ne rentre pas dans les quatre marqueurs n'a rien à faire dans la sortie.
- **La couleur est un bonus, jamais l'information.** Le texte `WARN` doit rester lisible une fois les couleurs retirées.
- **Couleurs désactivées** si la sortie n'est pas un terminal, ou si `NO_COLOR` est défini.

### Implémentation de référence

```bash
if [[ -t 1 && -z "${NO_COLOR:-}" ]]; then
    readonly C_RESET=$'\033[0m' C_RED=$'\033[31m' C_GREEN=$'\033[32m'
    readonly C_YELLOW=$'\033[33m' C_BLUE=$'\033[34m' C_BOLD=$'\033[1m'
else
    readonly C_RESET='' C_RED='' C_GREEN='' C_YELLOW='' C_BLUE='' C_BOLD=''
fi

log_step() { printf '\n%s==> %s%s\n' "${C_BOLD}${C_BLUE}" "$*" "${C_RESET}"; }
log_info() { printf '    %s\n' "$*"; }
log_ok()   { printf '  %sOK%s  %s\n' "${C_GREEN}" "${C_RESET}" "$*"; }
log_warn() { printf '  %sWARN%s %s\n' "${C_YELLOW}" "${C_RESET}" "$*" >&2; }
log_err()  { printf '  %sFAIL%s %s\n' "${C_RED}" "${C_RESET}" "$*" >&2; }
```

Dans un autre langage, transposer les mêmes quatre marqueurs et la même indentation. Le rendu ne change pas, seul le véhicule change.

## 1. Décider la destination avant le format

La première question n'est pas "quel format" mais **qui possède le fichier de log**.

| Contexte d'exécution | Le process écrit sur | Qui fait la rotation |
|---|---|---|
| Conteneur | stdout / stderr, rien d'autre | Le runtime |
| Service systemd | stdout / stderr | journald |
| Script cron ou one-shot | stdout / stderr, redirigés par l'appelant | L'appelant ou logrotate |
| Binaire legacy non modifiable | Son fichier | logrotate |

**Règle :** une application sous orchestrateur n'ouvre pas de fichier et ne gère pas sa rotation. Le contrat des flux est celui de `bash-script-builder` : stdout les données, stderr les diagnostics. Un log est un diagnostic.

### Garder une trace fichier d'un run

Le fichier est **opt-in** (`LOG_FILE=chemin`), jamais imposé par défaut. Ce qui est bien de faire :

| Pratique | Raison |
|---|---|
| Ouvrir en **append** | Une troncature efface l'historique, dont le run qui vient d'échouer |
| **Horodater** dans le fichier, pas à l'écran | L'écran se lit en direct, le fichier se corrèle à un incident |
| **Retirer les codes ANSI** | Sinon illisible et ingrat à grepper |
| **En-tête de run** : date UTC, script, PID | Sépare les exécutions et sert d'identifiant de corrélation |
| **`umask 077`, permissions 600** | Le journal nomme des ressources, des comptes, des adresses |
| **Créer le répertoire parent** | Sinon échec sur le chemin fourni par l'utilisateur |
| **Drainer avant de sortir** | Avec `tee`, la fin du run manque si le shell part avant les sinks |
| **Chaîner le trap EXIT** | Bash n'en garde qu'un : le suivant écrase silencieusement le précédent |

Le fichier reçoit les deux flux, mais **stdout et stderr restent séparés** à l'écran. Et ceci ne dispense pas d'une rotation, voir la section 4.

## 2. Niveaux : la règle du destinataire

Choisir le niveau selon qui doit réagir. Côté console, `FAIL` porte ERROR, `WARN` porte WARN, `==>` et l'indentation portent INFO.

| Niveau | Destinataire | Test de validation |
|---|---|---|
| ERROR | Une astreinte, potentiellement de nuit | Si personne ne doit être réveillé, ce n'est pas ERROR |
| WARN | Quelqu'un qui relit les logs demain matin | Dégradation absorbée, mais anormale |
| INFO | Une enquête post-incident | Transitions d'état, pas les boucles |
| DEBUG | Le développeur, en local | Désactivé en production par défaut |

- **Une erreur rattrapée et relancée est loguée deux fois.** Loguer à l'endroit où l'on décide quoi faire, propager ailleurs.
- **ERROR dans une boucle de retry** : le collecteur reçoit des milliers de lignes et l'alerte devient inexploitable. Loguer WARN sur chaque tentative, ERROR une seule fois à l'abandon.

Le niveau doit se changer **sans redéploiement** : variable d'environnement lue au démarrage au minimum, endpoint d'administration si le service est long à redémarrer.

## 3. Secrets et données personnelles

Le point le plus coûteux à corriger : un secret logué est répliqué, indexé et sauvegardé.

- **Filtrer à l'émission, pas à l'ingestion.** Une allowlist de champs autorisés tient mieux dans le temps qu'une denylist de champs interdits.
- **Ne jamais loguer un objet entier** (requête HTTP, réponse d'API, structure de config). C'est le vecteur numéro un de fuite de token.
- **`Authorization`, `Cookie`, `Set-Cookie`** et les corps de requête d'authentification sont exclus par défaut.
- **Une URL contient des secrets** dans sa query string. Loguer le chemin, pas l'URL complète.
- **Données personnelles** : loguer un identifiant interne, pas un email ni un nom. La rétention des logs devient sinon un sujet RGPD.

Si un secret a déjà été logué, le traiter comme compromis : révocation et rotation, pas seulement suppression de la ligne.

## 4. Rotation et rétention

| Décision | Valeur de départ raisonnable |
|---|---|
| Taille max d'un fichier | 100 Mo |
| Nombre de fichiers conservés | 5 à 10 |
| Rétention chaude (recherche rapide) | 7 à 15 jours |
| Rétention froide (archive) | 90 jours, davantage si contrainte légale |
| Compression | Oui, sauf sur le fichier courant |

Piège `logrotate` : **`copytruncate` perd les lignes écrites entre la copie et la troncature**, et ne corrige rien si le process garde le descripteur ouvert. Préférer un signal de réouverture (`postrotate` avec `kill -HUP` ou `systemctl reload`), et ne garder `copytruncate` que si le process ne sait pas rouvrir son fichier.

## Spécificités par techno

### Ansible

La doc officielle de référence est l'annexe [Logging Ansible output](https://docs.ansible.com/projects/ansible/latest/reference_appendices/logging.html).

- `log_path` dans `ansible.cfg` : un journal unique sur le nœud de contrôle. Fichier non tourné par défaut, prévoir logrotate.
- `no_target_syslog` et `syslog_facility` : un journal par machine gérée, à la place.
- **`no_log: true` sur toute tâche qui manipule un secret.** Attention, il ne couvre pas la sortie de `debug`, donc ne pas débugger un playbook en production.
- `display_args_to_stdout` : ajoute les valeurs des variables dans la sortie, utile pour distinguer des tâches identiques dans une boucle.
- Callback plugins : `log_plays` écrit les événements dans un fichier, `mail` notifie sur échec, `profile_tasks` chronomètre. Les activer via `callbacks_enabled` dans `ansible.cfg`.
- Le mot de passe Vault ne passe jamais en argument de ligne de commande, il finit dans l'historique shell et dans les logs du CI.

### systemd

- `StandardOutput=journal`, lecture avec `journalctl -u <unité> -o json`.
- `SystemMaxUse=` dans `journald.conf` borne la place occupée, sinon journald prend jusqu'à 10 % du système de fichiers.

### CI/CD

- Les secrets sont masqués par la plateforme uniquement s'ils sont déclarés comme tels. Une valeur dérivée (encodée en base64, concaténée) n'est plus masquée.
- Ne pas activer la verbosité maximale (`-vvv` Ansible, `set -x`, `CI_DEBUG_TRACE`) sur une exécution qui manipule des identifiants.
- Les logs de job ont une rétention courte : archiver en artefact ce qui doit servir à un post-mortem.

## Anti-patterns

| Anti-pattern | Conséquence | Correction |
|---|---|---|
| Loguer l'objet requête ou réponse entier | Fuite de tokens et de données personnelles | Allowlist de champs |
| `copytruncate` par défaut | Lignes perdues à chaque rotation | Signal de réouverture en `postrotate` |
| DEBUG laissé actif en production | Volume, coût, secrets exposés | Niveau piloté par variable d'environnement |
| Horodatage en heure locale | Corrélation impossible entre régions | ISO 8601 UTC avec millisecondes |
| Marqueurs maison inventés à chaque projet | Chaque log se relit différemment | Les quatre marqueurs imposés, sans exception |
| Tronquer le fichier de log au démarrage | Perte de l'historique, y compris du run qui a échoué | Ouverture en append |
| `trap ... EXIT` posé sans chaînage | Le nettoyage précédent est écrasé silencieusement | Chaîner sur le trap existant |

## Checklist de revue

1. La sortie console respecte les quatre marqueurs et l'indentation imposés, couleurs désactivables.
2. La destination est cohérente avec le contexte d'exécution, et le process ne possède pas de fichier qu'il ne devrait pas posséder.
3. Si un collecteur ingère, le format est structuré, une ligne par événement, horodatage UTC.
4. Les niveaux respectent la règle du destinataire, et sont pilotables sans redéploiement.
5. Aucun secret ni donnée personnelle ne peut atteindre la sortie, filtrage à l'émission.
6. Rotation et rétention définies, y compris sur le driver du runtime.
7. Un identifiant de corrélation traverse les services ou les runs.
8. L'indisponibilité du collecteur ne dégrade pas le service.

## Les autres signaux

Un log dit ce qui s'est passé pour un cas précis. Pour « combien et à quelle vitesse », voir `metrics-setup`. Pour « où le temps est parti entre les services », voir `tracing-setup`. Le champ `trace_id` est ce qui relie les trois.

## Service avec collecteur

Dès que les logs partent vers un collecteur (application longue durée, conteneur, agrégation centralisée), lire `collecte.md` dans ce dossier : format JSON structuré, corrélation, agrégation, conteneurs et Kubernetes.
