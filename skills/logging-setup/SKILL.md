---
name: logging-setup
description: Mise en place et revue des logs d'infrastructure et d'application, format de présentation console imposé (contrat Ansible : TASK, issues, PLAY RECAP), destination stdout/stderr, journal de run, niveaux, redaction des secrets, rotation et rétention. Couvre les spécificités Ansible, systemd et CI/CD, et renvoie à collecte.md pour les logs agrégés. Se déclenche avec "logs", "logging", "journalisation", "log_path", "no_log", "logrotate", "journald", "structured logging", "agrégation de logs", "rétention", "observabilité".
---

# Mise en place des logs

## Ce que ce skill n'enseigne pas

Un agent compétent horodate déjà ses lignes, met un niveau devant, et n'écrit pas `print()` partout. Ne pas dépenser de lignes là-dessus.

Ce skill couvre les décisions qui se prennent au moment du branchement, celles qu'on ne peut plus corriger sans migration une fois que le collecteur ingère.

## Présentation de la sortie : contrat Ansible

**Cette section n'est pas une suggestion.** La sortie console suit le contrat d'Ansible décrit dans `makefile-builder` (section « Contrat de sortie ») : un opérateur qui a lu un `ansible-playbook` sait lire tous les scripts. **REQUIRED BACKGROUND :** lire cette section de `makefile-builder`, y compris « Les mots viennent de l'outil, la forme vient d'Ansible ».

### Rendu attendu

```
TASK [aks : API server IP allowlist] *******************************************
    current allowlist: 10.0.0.0/8
    requested        : 10.0.0.0/8,203.0.113.7/32
[WARNING]: 203.0.113.7 is not listed explicitly
changed:     [aks] allowlist applied, rules take up to 2 minutes to propagate

PLAY RECAP *********************************************************************
aks         : ok=4   changed=1   unreachable=0   failed=0   skipped=0
```

| Élément | Rôle | Flux |
|---|---|---|
| `TASK [role : action]` | Ouverture d'une étape, ligne d'étoiles jusqu'à 80 colonnes | stdout |
| (indentation seule) | Détail, contexte, valeur lue | stdout |
| Issue par ligne (`ok:`, `changed:`, ou le mot de l'outil) | Résultat de l'étape | stdout |
| `[WARNING]:` | Anomalie absorbée, l'exécution continue | **stderr** |
| `fatal:` / `unreachable:` | Échec, suivi d'une sortie non nulle | **stderr** |
| `PLAY RECAP` | Compteurs de fin, nommés d'après l'outil | stdout |

Règles de forme :

- **La couleur est un bonus, jamais l'information.** Le mot de l'issue reste lisible une fois les couleurs retirées.
- **Couleurs désactivées** si la sortie n'est pas un terminal, ou si `NO_COLOR` est défini.
- **Pas de niveau supplémentaire visible.** Pas de `DEBUG` à l'écran, pas d'émoji.

Dans un autre langage, transposer la même forme. Le rendu ne change pas, seul le véhicule change.

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

Choisir le niveau selon qui doit réagir. Côté console, `fatal:` et `unreachable:` portent ERROR, `[WARNING]:` porte WARN, `TASK`, les issues et l'indentation portent INFO.

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
| Marqueurs maison inventés à chaque projet | Chaque log se relit différemment | Le contrat Ansible de `makefile-builder`, sans exception |
| Tronquer le fichier de log au démarrage | Perte de l'historique, y compris du run qui a échoué | Ouverture en append |
| `trap ... EXIT` posé sans chaînage | Le nettoyage précédent est écrasé silencieusement | Chaîner sur le trap existant |

## Checklist de revue

1. La sortie console respecte le contrat Ansible (TASK, issues nommées d'après l'outil, PLAY RECAP), couleurs désactivables.
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
