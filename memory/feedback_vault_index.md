---
name: vault-adminsys-update-index
description: Toujours mettre à jour le fichier Index du vault AdminSys après création/suppression de note
metadata: 
  node_type: memory
  type: feedback
  originSessionId: 7247260c-7b58-4803-9cde-45acb01987ed
---

Quand je crée ou supprime une note dans le vault Obsidian AdminSys, mettre à jour `00 - Index et Roadmap.md` (table du bloc concerné) dans le même travail, sans attendre qu'on le demande.

**Why:** L'utilisateur veut que l'index reste synchronisé en permanence avec les notes du vault.
**How to apply:** Après tout Write/suppression de note, éditer la table du bloc correspondant dans `00 - Index et Roadmap.md`. Voir [[obsidian-vault-simplon]].
