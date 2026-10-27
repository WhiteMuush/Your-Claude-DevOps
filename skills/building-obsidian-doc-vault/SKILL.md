---
name: building-obsidian-doc-vault
description: À utiliser quand on crée, réorganise ou complète un vault Obsidian de documentation technique (antisèches, procédures, notes "comment faire"), quand le graphe Obsidian est illisible, mal coloré ou change de disposition à chaque ouverture, ou quand Claude doit retrouver les méthodes habituelles de l'utilisateur dans ses notes. Se déclenche avec "Obsidian", "vault", "coffre", "graphe", "graph.json", "antisèche", "doc rapide".
---

# Vault Obsidian de doc rapide

Un arbre strict : hub, thèmes, sous-thèmes, notes. Le graphe reste lisible tant qu'une note ne pointe **que vers son parent et ses enfants**.

## Structure

- Un dossier par thème ou sous-thème, avec une note au nom **identique** au dossier (`Kubernetes/Manifests/Manifests.md`) qui liste ses enfants en `[[...]]`.
- Le hub, à la racine, ne liste que les thèmes de premier niveau.
- Nom de note préfixé par son thème (`Terraform State GitLab`), donc unique dans tout le vault.
- Rien d'autre : ni frontmatter, ni modèles, ni `CLAUDE.md`. Le pointeur vers le vault va dans la mémoire de Claude, qui cherche par nom de dossier et de note.

## Format d'une note

````markdown
Thème : [[Parent]]

# Terraform State GitLab

Une phrase qui dit à quoi ça sert, avec des mots simples.

1. L'étape, puis le bloc à copier :
   ```bash
   terraform init -migrate-state
   ```
   - `-migrate-state` : copie le state local vers le nouveau backend.
````

Un renvoi vers une autre branche s'écrit en texte ("voir la note X"), jamais en `[[lien]]`.

## Contrôle

`check-vault.sh <vault> [hub]` après chaque ajout (1 000 notes en moins de 0,1 s). Il signale tout écart aux règles ci-dessus, et ignore comme Obsidian les liens dans un bloc de code.

## Couleurs du graphe

`colorGroups` dans `.obsidian/graph.json`, une entrée par dossier :

```json
{ "query": "path:\"Terraform/\"", "color": { "a": 1, "rgb": 9133302 } }
```

- Le `/` final est obligatoire : `path:"Terraform"` colore aussi `Secrets/Secrets Terraform.md`.
- `rgb` est en décimal : `0x8B5CF6` = `9133302`.
- Obsidian réécrit ce fichier : vérifier qu'il est fermé avant d'écrire (sous WSL, `tasklist.exe | grep -i obsidian`).
- Le bouton "Restaurer les paramètres par défaut" du graphe efface aussi les couleurs.

## Positions figées

Obsidian ne garde pas les positions. Sans plugin tiers : copier `graphe-fige/` dans `.obsidian/plugins/` (un fichier lisible, sans dépendance ni réseau).

- Commandes "Figer le graphe" et "Libérer le graphe". Tirer une note libère le graphe, la lâcher refige tout.
- API interne non documentée (`renderer.worker.postMessage({ forceNode })`) : une mise à jour d'Obsidian peut le désactiver, sans rien casser.
- L'activer oblige à quitter le mode restreint d'Obsidian : relire `main.js` avant, et n'installer aucun autre plugin.
- Tests : `node --test graphe-fige/main.test.js`.

## Git

```gitignore
.obsidian/workspace*.json
.trash/
.obsidian/plugins/*
!.obsidian/plugins/graphe-fige/
.obsidian/community-plugins.json
```

Un clone n'active aucun plugin et ne synchronise rien. Poste en lecture seule : `git remote set-url --push origin no_push`. Avant de publier : `gitleaks git .`.

## Erreurs fréquentes

| Erreur | Effet |
|---|---|
| `[[lien]]` vers une autre branche | Graphe emmêlé |
| `path:"Nom"` sans `/` | Notes d'autres branches mal colorées |
| `graph.json` modifié avec Obsidian ouvert | Modification écrasée |
| Plugin communautaire pour figer le graphe | Code tiers non relu |
