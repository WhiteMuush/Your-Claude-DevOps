---
name: obsidian-vault-simplon
description: "Chemins des vaults Obsidian de l'utilisateur (AdminSys et DevSecOps)"
metadata: 
  node_type: memory
  type: reference
  originSessionId: 0eec97a7-fd01-49d6-b19e-7c1acab6cfbb
---

Vaults déplacés vers Google Drive (2026-06-15). Ancien emplacement `/mnt/c/.../CoffreObsidian/` abandonné.

Racine Windows : `G:\Mon Drive\vault-share`
Racine WSL : `/mnt/g/Mon Drive/vault-share`

Vault AdminSys : `/mnt/g/Mon Drive/vault-share/AdminSys`
Vault DevSecOps : `/mnt/g/Mon Drive/vault-share/DevSecOps`
Vault AZ-900 : `/mnt/g/Mon Drive/vault-share/AZ-900` (cert Azure Fundamentals, ajouté 2026-06-19)

Note : G: (Google Drive for Desktop) n'est pas auto-monté dans WSL. Monter avant accès :
`sudo mkdir -p /mnt/g && sudo mount -t drvfs G: /mnt/g`
