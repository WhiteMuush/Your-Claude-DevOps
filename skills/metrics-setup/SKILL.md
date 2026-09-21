---
name: metrics-setup
description: Conception des métriques applicatives et d'infrastructure, convention de nommage imposée, choix du type (counter, gauge, histogram), maîtrise de la cardinalité des labels, méthodes RED et USE, buckets et quantiles. Complète prometheus-grafana-setup qui couvre l'outillage. Se déclenche avec "métriques", "metrics", "instrumenter", "cardinalité", "labels", "counter", "gauge", "histogram", "quantile", "p95", "RED", "USE", "SLI", "SLO", "observabilité".
---

# Conception des métriques

## Ce que ce skill n'enseigne pas

Installer Prometheus, écrire un `scrape_config`, brancher Grafana, rédiger une règle Alertmanager : c'est le skill `prometheus-grafana-setup`. Ici on décide **quoi mesurer et sous quel nom**, avant de toucher à l'outillage.

Le corollaire vaut aussi : une métrique mal nommée ou trop cardinale ne se corrige pas, elle se remplace, et l'historique est perdu.

## Nommage : convention imposée

**La même convention sur tous les projets**, comme le format console de `logging-setup`. Un nom de métrique se lit sans documentation.

```
<namespace>_<sujet>_<unité>[_total]
```

```
http_requests_total                     compteur de requêtes
http_request_duration_seconds           histogramme de latence
queue_messages_pending                  jauge de profondeur de file
process_resident_memory_bytes           jauge de mémoire
```

Règles de forme :

| Règle | Détail |
|---|---|
| **Unités de base uniquement** | `seconds`, `bytes`, `ratio`. Jamais `ms`, `mb`, `percent` |
| **L'unité est dans le nom** | Un nom sans unité oblige à ouvrir le code pour savoir ce qu'on lit |
| **Suffixe `_total`** sur tout compteur | Rend le type lisible à l'œil et dans les requêtes |
| **Pas de suffixe de type** ailleurs | Pas de `_gauge`, pas de `_histogram` |
| **Namespace = le service ou le composant** | `checkout_`, `ingest_`, pas l'équipe ni l'environnement |
| **Snake case, en anglais, au pluriel pour ce qui se compte** | `requests`, `errors`, `messages` |

Ce qui identifie une instance (environnement, région, hôte, version) est un **label**, jamais une partie du nom. Un nom par environnement rend toute agrégation impossible.

## Choisir le type

| Type | Quand | Piège |
|---|---|---|
| **Counter** | Une quantité qui ne fait que croître : requêtes, erreurs, octets envoyés | Se lit toujours en taux, jamais en valeur brute. La valeur absolue ne veut rien dire après un redémarrage |
| **Gauge** | Une valeur instantanée qui monte et descend : connexions ouvertes, profondeur de file, mémoire | Une jauge échantillonnée toutes les 30 secondes rate les pics. Si le pic compte, compter l'événement |
| **Histogram** | Une distribution : latence, taille de réponse | Coûteux, voir la section buckets |

**Compter les erreurs comme un label du compteur principal**, pas comme un compteur séparé : `http_requests_total{status="500"}`. Sinon le taux d'erreur devient une division entre deux séries qui ne s'alignent pas toujours.

Règle de décision rapide : si la question est "combien de fois", c'est un counter. Si c'est "combien en ce moment", une gauge. Si c'est "à quelle vitesse pour la plupart des cas", un histogram.

## Cardinalité : la seule erreur qui coûte vraiment

**Une série temporelle est créée pour chaque combinaison de valeurs de labels.** La cardinalité est un produit, pas une somme : 5 méthodes × 40 routes × 8 statuts = 1600 séries pour une seule métrique. Ajouter un label à 1000 valeurs la multiplie par 1000.

Interdits de fait comme valeurs de label :

- Identifiant utilisateur, de commande, de session, de requête
- Adresse IP, adresse email
- **URL brute** : templatiser le chemin (`/orders/{id}`), sinon chaque identifiant crée une série
- Message d'erreur ou trace d'exception
- Horodatage sous n'importe quelle forme

Ces informations existent déjà ailleurs : elles appartiennent aux logs et aux traces, pas aux métriques. C'est la répartition des rôles entre les trois signaux.

Test avant d'ajouter un label : **"combien de valeurs distinctes ce label prendra-t-il dans un an, au pire ?"** Si la réponse n'est pas un petit nombre borné et connu, c'est non.

Une explosion de cardinalité ne se voit pas en développement. Elle se voit en production, quand le serveur de métriques sature.

## Quoi mesurer

Deux méthodes complémentaires, à appliquer en entier plutôt qu'à moitié.

**RED, pour tout ce qui traite des requêtes** (API, consommateur de file, job) :

- **Rate** : le débit, requêtes par seconde
- **Errors** : le taux d'échec, en proportion du débit
- **Duration** : la distribution des latences

**USE, pour toute ressource** (CPU, mémoire, disque, pool de connexions, threads) :

- **Utilization** : le taux d'occupation
- **Saturation** : ce qui attend, la file d'attente. Le signal le plus prédictif et le plus souvent oublié
- **Errors** : les échecs de la ressource elle-même

La saturation est ce qui permet d'agir **avant** l'incident. Une utilisation à 100 % n'est pas un problème si rien n'attend.

Ne pas instrumenter ce que personne ne regardera : chaque métrique coûte du stockage et de l'attention. Une métrique qui n'apparaît ni dans un dashboard, ni dans une alerte, ni dans une enquête récente est à supprimer.

## Histogrammes, buckets et quantiles

- **Les buckets se choisissent en fonction de la cible de latence**, pas par défaut. Il faut un bucket exactement à la valeur de l'objectif, sinon le taux de respect du SLO n'est pas calculable.
- **Coût** : une série par bucket et par combinaison de labels. Dix buckets multiplient la cardinalité par dix. Cinq à huit buckets bien placés valent mieux que vingt.
- **La moyenne ne décrit rien.** Une moyenne à 80 ms peut cacher 5 % de requêtes à 4 secondes. Raisonner en p95 et p99.
- **Un quantile ne s'additionne pas et ne se moyenne pas.** Faire la moyenne des p95 de trois instances ne donne pas le p95 global. Agréger les buckets d'abord, calculer le quantile ensuite.
- **Le p99 sur un faible volume est du bruit.** Sur 50 requêtes par minute, il décrit une seule requête.

## Métrique, log ou trace

| Besoin | Signal |
|---|---|
| Combien, à quelle vitesse, quelle proportion | **Métrique** |
| Ce qui s'est passé pour ce cas précis | **Log** (`logging-setup`) |
| Où le temps est parti entre les services | **Trace** (`tracing-setup`) |

Compter des événements en interrogeant des logs coûte cher et répond lentement. À l'inverse, ajouter un label à forte cardinalité pour retrouver un cas précis détruit la métrique. Chaque question a son signal.

## Anti-patterns

| Anti-pattern | Conséquence | Correction |
|---|---|---|
| Identifiant ou URL brute en label | Explosion de cardinalité, serveur saturé | Chemin templatisé, identifiants dans les logs |
| Unité dans le nom absente ou non standard | Lecture ambiguë, conversions silencieuses | `_seconds`, `_bytes`, `_ratio` |
| Environnement inscrit dans le nom | Agrégation impossible | Label `env` |
| Compteur d'erreurs séparé du compteur principal | Taux d'erreur faux ou instable | Label `status` sur le compteur |
| Buckets laissés par défaut | SLO non mesurable | Un bucket sur la valeur de l'objectif |
| Moyenne de quantiles entre instances | Chiffre faux, présenté comme vrai | Agréger les buckets puis calculer |
| Jauge échantillonnée pour détecter un pic | Le pic passe entre deux scrapes | Compter l'événement |
| Saturation non mesurée | On découvre le problème une fois saturé | Mesurer la file d'attente |
| Métriques créées mais jamais regardées | Coût de stockage et bruit | Supprimer ce qui ne sert ni dashboard, ni alerte |

## Checklist de revue

1. Chaque nom suit `<namespace>_<sujet>_<unité>[_total]`, en unité de base.
2. Aucun label ne peut prendre un nombre non borné de valeurs.
3. Les erreurs sont un label du compteur principal, pas une métrique à part.
4. RED est complet sur chaque point d'entrée, USE complet sur chaque ressource critique, saturation comprise.
5. Les buckets d'histogramme encadrent la cible de latence.
6. Aucun quantile n'est moyenné ni additionné.
7. Toute métrique ajoutée sert un dashboard, une alerte ou une enquête identifiée.
