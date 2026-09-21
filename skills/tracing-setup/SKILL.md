---
name: tracing-setup
description: Mise en place du tracing distribué avec OpenTelemetry, propagation du contexte W3C traceparent, nommage et découpage des spans, attributs, gestion des erreurs, échantillonnage head et tail, corrélation avec les logs et les métriques. Se déclenche avec "trace", "tracing", "traces distribuées", "OpenTelemetry", "OTel", "span", "traceparent", "trace_id", "échantillonnage", "sampling", "Jaeger", "Tempo", "latence entre services", "observabilité".
---

# Tracing distribué

## Ce que ce skill n'enseigne pas

Déployer un collecteur OpenTelemetry, configurer un backend Jaeger ou Tempo, lire une cascade dans une interface : ce sont des tâches d'outillage bien documentées. Ici on décide **ce qu'on trace, comment on le nomme et ce qu'on garde**.

La règle de base : **le tracing répond à "où le temps est parti", pas à "combien" ni à "quoi exactement".** Ces deux questions appartiennent à `metrics-setup` et `logging-setup`.

## La propagation d'abord, tout le reste ensuite

**Une trace interrompue ne vaut rien.** Un span orphelin est pire qu'une absence de trace : il donne l'illusion d'une couverture. C'est le seul point à valider avant d'investir dans le nommage ou les attributs.

Le contexte voyage dans l'en-tête **W3C `traceparent`** (format standard, à préférer aux formats propriétaires). Il doit traverser :

| Frontière | Point de vigilance |
|---|---|
| Appel HTTP sortant | Le client instrumenté injecte l'en-tête. Un client construit à la main ne le fait pas |
| Message en file | Le contexte se met dans les **en-têtes du message**, pas dans son corps métier |
| Job asynchrone ou batch | Le contexte du producteur doit être sérialisé avec la tâche, sinon la trace s'arrête à l'enqueue |
| Passerelle, proxy, load balancer | Vérifier que l'en-tête est transmis et non filtré |
| Frontière d'équipe ou de prestataire | Se mettre d'accord sur le format en amont, pas après |

Test de validation : prendre un `trace_id` réel et vérifier qu'il apparaît **dans tous les services traversés**. Tant que ce test échoue, ne pas affiner le reste.

## Nommage et découpage des spans

Le nom d'un span est **à faible cardinalité**, comme un nom de métrique. Ce qui varie va dans les attributs.

```
GET /orders/{id}          correct
GET /orders/48213         faux, un nom de span par commande
db.query orders           correct
SELECT * FROM orders ...  faux, et fuite potentielle de données
```

Que découper :

- **Une frontière de processus** : requête entrante, appel sortant, publication ou consommation de message. Non négociable.
- **Une opération d'entrée-sortie** : requête base de données, appel de cache, lecture de fichier volumineux.
- **Un bloc de calcul significatif**, seulement s'il est soupçonné de coûter du temps.

Ce qu'il ne faut pas découper : chaque fonction. Une trace à 400 spans est illisible, coûteuse, et ne dit rien de plus qu'une trace à 20 spans bien placés. Le découpage se resserre là où une enquête a réellement manqué d'information.

Suivre les **conventions sémantiques OpenTelemetry** pour les attributs standard (`http.request.method`, `server.address`, `db.system`). Un attribut maison là où une convention existe coûte la compatibilité avec tout l'outillage.

## Attributs, événements, erreurs

- **Les attributs décrivent le span**, les événements horodatent un fait à l'intérieur. Une exception est un événement, pas un attribut.
- **Un span en échec porte un statut d'erreur explicite.** Sans cela, il est compté comme réussi dans toutes les statistiques dérivées.
- **L'erreur est marquée là où elle est traitée**, pas à chaque niveau qui la relaie. Sinon une seule panne apparaît comme dix.
- Les mêmes interdits que pour les logs s'appliquent aux attributs : **pas de secret, pas de jeton, pas de donnée personnelle, pas de corps de requête entier**. Les traces sont exportées vers un backend tiers, souvent moins protégé que les logs.
- Une requête SQL en attribut expose les valeurs. Loguer l'opération et la table, pas la requête complète.

## Échantillonnage

Tout tracer coûte trop cher, ne rien tracer ne sert à rien. La décision se prend explicitement.

| Stratégie | Principe | Quand |
|---|---|---|
| **Head-based** | La décision est prise au début, à la racine, et propagée | Défaut simple, volume prévisible |
| **Tail-based** | Le collecteur garde la trace complète une fois terminée, selon ce qui s'y est passé | Quand on veut 100 % des erreurs et des traces lentes |
| **Parent-based** | Un service suit la décision reçue de son parent | À activer partout, quelle que soit la stratégie |

Deux règles :

- **La décision doit être cohérente sur toute la trace.** Si chaque service décide pour lui-même, on obtient des traces à trous, inexploitables. D'où `parent-based` partout.
- **Garder tout ce qui est anormal** : erreurs et latences hautes échantillonnées à 100 %, trafic nominal échantillonné bas. C'est l'argument principal du tail-based, qui coûte en mémoire au collecteur.

Un taux de 1 à 10 % sur le trafic nominal suffit presque toujours pour du diagnostic.

## Corrélation entre les trois signaux

C'est ce qui transforme trois outils séparés en une chaîne d'enquête.

1. **Injecter `trace_id` et `span_id` dans chaque ligne de log** émise dans le contexte d'un span. Le parcours devient : alerte sur métrique, puis trace lente, puis logs exacts de cette trace.
2. **Exemplars** : attacher un `trace_id` à un point de métrique permet de sauter d'un pic de latence à une trace réelle de ce pic.
3. Le même identifiant de corrélation traverse donc les trois signaux. Sans lui, chaque outil se fouille à la main.

Voir `logging-setup` pour le champ `trace_id` côté logs, et `metrics-setup` pour la répartition des rôles.

## Anti-patterns

| Anti-pattern | Conséquence | Correction |
|---|---|---|
| Propagation cassée sur une frontière | Traces orphelines, illusion de couverture | Valider un `trace_id` de bout en bout |
| Contexte dans le corps du message | Couplage métier, oublié par les autres producteurs | En-têtes du message |
| Identifiant dans le nom du span | Cardinalité ingérable côté backend | Nom templatisé, identifiant en attribut |
| Un span par fonction | Traces illisibles, coût élevé | Frontières de processus et entrées-sorties |
| Erreur marquée à chaque niveau | Une panne compte pour dix | Marquer là où elle est traitée |
| Statut d'erreur non positionné | Le span en échec passe pour un succès | Statut explicite plus événement d'exception |
| Requête SQL ou corps entier en attribut | Fuite de données vers un backend tiers | Opération et table seulement |
| Échantillonnage décidé par service | Traces à trous | `parent-based` partout |
| Échantillonnage uniforme | Les incidents rares ne sont jamais capturés | 100 % des erreurs et des traces lentes |
| Aucun `trace_id` dans les logs | Aucun lien entre les signaux | Injecter le contexte dans le logger |

## Checklist de revue

1. Un `trace_id` réel se retrouve dans tous les services traversés, y compris derrière une file et un job asynchrone.
2. Les noms de spans sont à faible cardinalité, ce qui varie est en attribut.
3. Les attributs standard suivent les conventions sémantiques OpenTelemetry.
4. Aucun secret ni donnée personnelle ne part dans un attribut ou un événement.
5. Les spans en échec portent un statut d'erreur, marqué une seule fois.
6. `parent-based` est actif partout et la stratégie d'échantillonnage est écrite quelque part.
7. Les erreurs et les traces lentes sont conservées intégralement.
8. `trace_id` et `span_id` apparaissent dans les logs applicatifs.
