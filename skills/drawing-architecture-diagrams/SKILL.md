---
name: drawing-architecture-diagrams
description: À utiliser quand un README, une doc ou une présentation a besoin d'un schéma d'architecture lisible avec les logos des outils, dans le style draw.io, ou quand un schéma Mermaid est jugé trop technique ou peu clair. Se déclenche avec "schéma", "diagramme", "architecture", "draw.io", "logos", "image du README", "schéma plus simple".
---

# Schémas d'architecture avec logos

## Principe

Un seul schéma qui raconte le système de gauche à droite, avec les **logos officiels**. Le résultat est un **SVG autonome** (logos intégrés en data URI) : il s'affiche pareil sur GitLab et GitHub, qui bloquent les liens externes dans un SVG.

**Le style imposé :**

- fond blanc, logos en couleur de la marque, taille 56 (50 pour les services cloud) ;
- sous chaque logo : un titre noir, puis une sous-légende grise courte ;
- flèches noires à angle droit, label en **gras** ;
- cadres arrondis : `cloud` (bleu pointillé), `cluster` (bleu plein), `zone` (gris pointillé) ;
- acteurs externes (personnes, SaaS, Terraform) **hors** des cadres, sur les bords.

## Outil

```bash
~/.claude/skills/drawing-architecture-diagrams/setup.sh     # une fois, crée le venv
~/.cache/drawing-architecture-diagrams/venv/bin/python spec.py docs/architecture.svg
```

`diagram.py` fournit `Diagram(w, h)` avec `frame`, `node`, `person`, `arrow`, `text`, `save`, et `zoom(png, box)`. La docstring en haut du fichier donne un exemple complet. `save` écrit aussi un PNG dans `~/.cache/drawing-architecture-diagrams/` : **c'est lui qu'on regarde** avec l'outil Read.

## Étapes

1. **Lister** les composants et les flux, puis écrire l'histoire en une phrase de gauche à droite.
2. **Placer sur une grille** : colonnes espacées de 150 à 160 px, lignes de 100 à 190 px. Canvas de départ 1280 x 720.
3. **Choisir les logos** (tableau ci-dessous).
4. **Écrire la spec** en Python dans le scratchpad, pas dans le dépôt.
5. **Rendre, puis regarder le PNG.** Zoomer avec `zoom` sur chaque zone chargée.
6. **Corriger** avec la checklist, puis recommencer l'étape 5.
7. **Livrer** le SVG dans `docs/`, et dans le README : `![Architecture](docs/architecture.svg)`.

## Sources de logos

| Source | Pour | Piège |
|---|---|---|
| `simple:<slug>` | Marques (gitlab, kubernetes, grafana, argo, traefikproxy, victoriametrics, terraform) | Pas de logos Microsoft ni Azure. Tester le slug : `curl -I https://cdn.simpleicons.org/<slug>` doit répondre 200 |
| `azure:<Nom>` | Services Azure officiels (Kubernetes-Services, Storage-Accounts, Monitor, Managed-Identities) | Nom exact du fichier, sans le préfixe numérique |
| `url:<svg>` | Logo officiel dans le dépôt du projet (cert-manager, Velero) | Vérifier que c'est un logo et pas une bannière ou un logo avec texte |
| `crop="x y w h"` | Garder seulement l'icône d'un logo avec texte | Velero : `url:.../site/static/img/Velero.svg` avec `crop="8 8 184 184"` |

skillicons.dev renvoie une icône **vide de 256 octets** pour un nom inconnu (argocd, helm), sans erreur : ne pas s'y fier.

## Checklist après chaque rendu

- Un logo est vide : son SVG n'avait pas de `viewBox` ou le slug n'existe pas.
- Un logo est coupé ou garde un bout de texte : ajuster `crop`.
- Un label touche une flèche, un logo ou la bordure d'un cadre : le déplacer avec `at=`.
- Une flèche traverse une légende : changer son trajet ou décaler le nœud.
- Une flèche arrive par le bas : la légende occupe environ 45 px sous le logo, la pointe s'arrête plus bas, ou la flèche arrive par le côté.
- Une flèche touche le logo : laisser 2 à 4 px entre la pointe et le bord du logo.
- Plus de 20 nœuds : le schéma n'est plus lisible, en faire deux ou fusionner des nœuds.

## Erreurs fréquentes

| Erreur | Conséquence |
|---|---|
| Livrer sans regarder le PNG | Logo invisible ou label illisible découvert par l'utilisateur |
| Mermaid quand on veut des logos | Boîtes de texte, rendu différent entre GitLab et GitHub |
| `<image href="https://...">` dans le SVG | Logo absent sur GitLab et GitHub |
| Tous les détails techniques dans le schéma | Illisible : les détails vont dans un tableau sous le schéma |
