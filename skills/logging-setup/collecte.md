# Logs ingérés par un collecteur

Complément du skill `logging-setup`. À lire quand les logs quittent la machine : service longue durée, conteneur, agrégation centralisée. Pour un script d'exploitation lancé à la main, le format console du SKILL.md suffit.

## Une ligne, un événement, un objet JSON

Cette section vise **ce qu'un collecteur ingère**, pas la sortie console : le format imposé plus haut reste celui que lit un humain. Un script d'exploitation lancé à la main s'arrête au format console. Un service dont les logs partent vers un collecteur émet du JSON, et garde un rendu humain en local derrière une variable (`LOG_FORMAT=pretty`).

Le format texte lisible à l'œil coûte cher dès qu'il y a un collecteur : chaque évolution de message casse le parsing en amont.

```json
{"ts":"2026-09-21T14:03:11.482Z","level":"error","msg":"payment declined","service":"checkout","env":"prod","trace_id":"3f9a2c","order_id":"A-12094","err":"card_expired"}
```

Contraintes non négociables :

- **Une ligne par événement.** Une stack trace sur 30 lignes devient 30 événements chez le collecteur si elle n'est pas encapsulée dans un champ.
- **Horodatage ISO 8601 en UTC, avec les millisecondes.** L'heure locale rend la corrélation multi-régions impossible.
- **Le message est stable, le contexte est dans les champs.** Écrire `msg:"payment declined"` plus `order_id`, jamais `msg:"payment declined for order A-12094"` : sinon aucun regroupement par type d'erreur n'est possible.
- **Un identifiant de corrélation** (`trace_id` ou `request_id`) propagé de bout en bout. C'est la seule chose qui permet de reconstituer un parcours entre services.

## Agrégation

- **Le log ne doit jamais bloquer l'application.** Écriture asynchrone, buffer borné, et perte de lignes assumée plutôt que requêtes en attente. Un collecteur indisponible ne fait pas tomber le service.
- **L'agent collecteur tourne à côté**, il lit les fichiers du runtime ou le journal. L'application n'envoie pas elle-même vers le collecteur réseau.
- **Budget de volume** : décider ce qu'on échantillonne. Les logs d'accès en succès sont les premiers candidats.
- **Les logs ne remplacent pas les métriques.** Compter des événements avec des requêtes de logs coûte cher et répond lentement. Un compteur Prometheus répond en millisecondes (voir `prometheus-grafana-setup`).

## Conteneurs et Kubernetes

- Driver de logs configuré explicitement avec `max-size` et `max-file`, sinon disque saturé.
- Pas de sidecar d'écriture de fichier si stdout suffit.
- Les logs d'un pod supprimé disparaissent : l'agrégation n'est pas optionnelle en production.


Sans `max-size` et `max-file` sur le driver `json-file` de Docker, le disque de l'hôte se remplit jusqu'à saturation : la rotation ne se fait pas toute seule.

## Anti-patterns propres à la collecte

| Anti-pattern | Conséquence | Correction |
|---|---|---|
| Message dynamique avec les valeurs dedans | Impossible de regrouper par type d'erreur | Message stable plus champs structurés |
| Log multi-lignes non encapsulé | Une stack trace devient N événements | Stack dans un champ, une ligne |
| Écriture synchrone vers le collecteur | Le service tombe quand le collecteur tombe | Buffer borné, asynchrone, perte assumée |
| Pas de `max-size` sur le driver Docker | Disque de l'hôte plein | `max-size` et `max-file` explicites |
| Aucun identifiant de corrélation | Parcours non reconstituable entre services | `trace_id` propagé de bout en bout |
| Compter des événements via requêtes de logs | Lent et cher | Métrique dédiée |
