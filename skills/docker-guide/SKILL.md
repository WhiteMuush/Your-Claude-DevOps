---
name: docker-guide
description: Bonnes pratiques Docker niveau entreprise et sécurité DevSecOps, Dockerfile, multi-stage build, hardening d'image, secrets, scan de vulnérabilités, signature d'image, docker-compose sécurisé. À utiliser dès qu'un Dockerfile ou docker-compose.yml est écrit ou modifié, ou pour du hardening de conteneur. Se déclenche avec "Docker", "Dockerfile", "docker build", "conteneur", "image Docker", "docker-compose", "hardening", "DevSecOps", "Trivy", "cosign", "SBOM", "scan de vulnérabilités".
---

# Docker Guide : bonnes pratiques entreprise et DevSecOps

## Principe directeur

Un Dockerfile de prod n'est jamais un Dockerfile de tuto.

Chaque ligne doit répondre à trois questions :
1. Est-ce que ça réduit la surface d'attaque ?
2. Est-ce que ça réduit la taille de l'image ?
3. Est-ce que ça reste reproductible (build déterministe) ?

---

## 1. Dockerfile : structure de base durcie

### Multi-stage build obligatoire

Le stage de build contient les outils (compilateurs, SDK).
Le stage final ne contient que le binaire ou le runtime.

```dockerfile
# --- Build stage ---
FROM node:20-alpine AS build
WORKDIR /app
COPY package*.json ./
RUN npm ci --omit=dev
COPY . .
RUN npm run build

# --- Final stage ---
FROM node:20-alpine AS final
WORKDIR /app

# create a dedicated non-root user, never reuse an existing broad-privilege one
RUN addgroup -S app && adduser -S app -G app

COPY --from=build --chown=app:app /app/dist ./dist
COPY --from=build --chown=app:app /app/node_modules ./node_modules

USER app
EXPOSE 3000
ENTRYPOINT ["node", "dist/main.js"]
```

### Checklist image de base

- Toujours une image officielle ou vérifiée (pas de repo perso obscur)
- Préférer une variante `alpine`, `slim` ou distroless
- Toujours pin la version exacte (`node:20.11.1-alpine`), jamais `latest`
- Vérifier le digest si l'image est critique (`node:20-alpine@sha256:...`)

### Checklist utilisateur

- Jamais `root` en exécution finale
- Créer un user dédié, pas `nobody` (trop générique, parfois restreint bizarrement)
- `USER` doit apparaître après tous les `COPY`/`RUN` qui ont besoin de droits

### .dockerignore obligatoire

Toujours présent, sinon le contexte de build fuite des fichiers sensibles.

```
.git
.env
.env.*
*.pem
*.key
node_modules
**/*.log
.ssh
```

---

## 2. Secrets : ce qu'il ne faut jamais faire

**Jamais** de secret dans :
- `ENV` ou `ARG` (visible dans `docker history` et dans les layers)
- Un `COPY` de fichier `.env` dans l'image finale
- Un `RUN echo $SECRET > file` (reste dans le layer même si supprimé après)

### La bonne méthode : BuildKit secret mount

Le secret n'est monté que pendant l'exécution du `RUN`, jamais persisté dans un layer.

```dockerfile
# syntax=docker/dockerfile:1
RUN --mount=type=secret,id=npm_token \
    NPM_TOKEN=$(cat /run/secrets/npm_token) npm ci
```

```bash
docker build --secret id=npm_token,src=./npm_token.txt -t app .
```

### En production (runtime)

- Kubernetes : `Secret` monté en volume, jamais en variable d'env en clair dans un manifest commité
- Docker Swarm : `docker secret create`, jamais en `environment:` de compose
- Toujours un gestionnaire externe si dispo (Vault, AWS Secrets Manager, etc.)

---

## 3. Scan de vulnérabilités (obligatoire en CI)

Aucune image ne part en registry sans scan.

### Trivy (référence open source, simple à intégrer)

```bash
# scan filesystem (avant build)
trivy fs --severity HIGH,CRITICAL --exit-code 1 .

# scan de l'image construite
trivy image --severity HIGH,CRITICAL --exit-code 1 monimage:1.0.0
```

`--exit-code 1` fait échouer le pipeline si des CVE HIGH/CRITICAL sont trouvées.

### Intégration CI (exemple générique)

```yaml
- name: Scan image
  run: trivy image --severity HIGH,CRITICAL --exit-code 1 --no-progress monimage:${{ github.sha }}
```

Pour GitHub Actions ou GitLab CI en détail, consulter respectivement les skills **github-actions-expert** et **gitlab-ci-guide**.

---

## 4. SBOM et signature d'image

### SBOM (Software Bill of Materials)

Liste tous les composants et dépendances de l'image. Exigé dans beaucoup de contextes entreprise et réglementaires.

```bash
trivy image --format cyclonedx --output sbom.json monimage:1.0.0
```

### Signature d'image (cosign)

Garantit que l'image en registry est bien celle buildée par le pipeline, pas altérée.

```bash
cosign sign --key cosign.key monimage:1.0.0
cosign verify --key cosign.pub monimage:1.0.0
```

En entreprise, la clé privée reste dans un secret manager CI, jamais en clair dans le repo.

---

## 5. docker-compose : durcissement

```yaml
services:
  app:
    image: monimage:1.0.0
    read_only: true
    tmpfs:
      - /tmp
    cap_drop:
      - ALL
    cap_add:
      - NET_BIND_SERVICE
    security_opt:
      - no-new-privileges:true
    user: "1000:1000"
    deploy:
      resources:
        limits:
          cpus: "0.50"
          memory: 256M
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:3000/health"]
      interval: 30s
      timeout: 5s
      retries: 3
    ports:
      - "127.0.0.1:3000:3000"
```

### Points clés

- `read_only: true` : le filesystem du conteneur est en lecture seule, `tmpfs` pour les besoins d'écriture ponctuels
- `cap_drop: ALL` puis ajout ciblé seulement des capabilities nécessaires
- `no-new-privileges` : bloque l'escalade de privilèges via setuid
- Jamais `privileged: true` sauf besoin documenté et validé (accès matériel direct)
- Ports bindés en loopback (`127.0.0.1:`) sauf si exposition publique explicitement voulue
- Limites CPU/mémoire toujours définies (évite qu'un conteneur compromis ou buggé épuise l'hôte)
- `healthcheck` systématique pour permettre restart automatique et supervision

---

## 6. Runtime security (niveau avancé)

- **Seccomp** : profil par défaut de Docker suffit dans la majorité des cas, ne pas désactiver (`--security-opt seccomp=unconfined` = drapeau rouge)
- **AppArmor/SELinux** : garder le profil par défaut actif, ne pas lancer en mode `unconfined`
- **User namespaces** : `--userns-remap` pour isoler le root du conteneur du root de l'hôte
- **Réseau** : pas de `network_mode: host` sauf nécessité réelle (perf réseau extrême), sinon ça annule l'isolation réseau

---

## 7. Checklist finale avant merge

- [ ] Multi-stage build, pas d'outils de build dans l'image finale
- [ ] Image de base pinnée à une version précise
- [ ] `USER` non-root défini
- [ ] `.dockerignore` présent et à jour
- [ ] Aucun secret en `ENV`/`ARG`/layer
- [ ] Scan Trivy passé sans CVE HIGH/CRITICAL non justifiée
- [ ] `HEALTHCHECK` défini
- [ ] Limites CPU/mémoire définies
- [ ] Ports non exposés publiquement sans raison explicite
- [ ] `cap_drop: ALL` en compose, capabilities ajoutées une par une si besoin

---

## Skills complémentaires

- **docker-swarm-guide** : orchestration multi-nœuds, stacks, secrets Swarm
- **helm-chart-builder** : si la cible finale est Kubernetes
- **github-actions-expert** / **gitlab-ci-guide** : intégration du scan et de la signature en pipeline
- **security-review** : revue de sécurité globale d'une branche, pas spécifique Docker
