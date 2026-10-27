---
name: docker-guide
description: Use when a Dockerfile or docker-compose.yml is written or modified, or for container hardening. Covers enterprise-grade Docker best practices and DevSecOps security, Dockerfile, multi-stage build, image hardening, secrets, vulnerability scanning, image signing, secured docker-compose. Triggers on "Docker", "Dockerfile", "docker build", "container", "Docker image", "docker-compose", "hardening", "DevSecOps", "Trivy", "cosign", "SBOM", "vulnerability scan".
---

# Docker Guide: enterprise and DevSecOps best practices

## Guiding principle

A production Dockerfile is never a tutorial Dockerfile.

Every line must answer three questions:
1. Does it reduce the attack surface?
2. Does it reduce the image size?
3. Does it stay reproducible (deterministic build)?

---

## 1. Dockerfile: hardened base structure

### Multi-stage build is mandatory

The build stage contains the tools (compilers, SDK).
The final stage contains only the binary or the runtime.

```dockerfile
# --- Build stage ---
FROM node:24-alpine AS build
WORKDIR /app
COPY package*.json ./
RUN npm ci --omit=dev
COPY . .
RUN npm run build

# --- Final stage ---
FROM node:24-alpine AS final
WORKDIR /app

# create a dedicated non-root user, never reuse an existing broad-privilege one
RUN addgroup -S app && adduser -S app -G app

COPY --from=build --chown=app:app /app/dist ./dist
COPY --from=build --chown=app:app /app/node_modules ./node_modules

USER app
EXPOSE 3000
ENTRYPOINT ["node", "dist/main.js"]
```

### Base image checklist

- Always an official or verified image (no obscure personal repo)
- Prefer an `alpine`, `slim` or distroless variant
- Always pin the exact version (`node:24.x.y-alpine`, taken from Docker Hub), never `latest`
- Pick a version that is still supported: Node 20 has been end of life since April 30, 2026, Node 24 is the active LTS
- Check the digest if the image is critical (`node:24-alpine@sha256:...`)

### User checklist

- Never `root` at final runtime
- Create a dedicated user, not `nobody` (too generic, sometimes oddly restricted)
- `USER` must appear after every `COPY`/`RUN` that needs privileges

### .dockerignore is mandatory

Always present, otherwise the build context leaks sensitive files.

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

## 2. Secrets: what you must never do

**Never** put a secret in:
- `ENV` or `ARG` (visible in `docker history` and in the layers)
- A `COPY` of a `.env` file into the final image
- A `RUN echo $SECRET > file` (stays in the layer even if deleted afterwards)

### The right method: BuildKit secret mount

The secret is mounted only while the `RUN` executes, never persisted in a layer.

```dockerfile
# syntax=docker/dockerfile:1
RUN --mount=type=secret,id=npm_token \
    NPM_TOKEN=$(cat /run/secrets/npm_token) npm ci
```

```bash
docker build --secret id=npm_token,src=./npm_token.txt -t app .
```

### In production (runtime)

- Kubernetes: `Secret` mounted as a volume, never as a plain-text env variable in a committed manifest
- Docker Swarm: `docker secret create`, never in the compose `environment:`
- Always an external manager if available (Vault, AWS Secrets Manager, etc.)

---

## 3. Vulnerability scanning (mandatory in CI)

No image goes to a registry without a scan.

### Trivy (open source reference, easy to integrate)

```bash
# filesystem scan (before build)
trivy fs --severity HIGH,CRITICAL --exit-code 1 .

# scan of the built image
trivy image --severity HIGH,CRITICAL --exit-code 1 monimage:1.0.0
```

`--exit-code 1` makes the pipeline fail if HIGH/CRITICAL CVEs are found.

### CI integration (generic example)

```yaml
- name: Scan image
  run: trivy image --severity HIGH,CRITICAL --exit-code 1 --no-progress monimage:${{ github.sha }}
```

For GitHub Actions or GitLab CI in detail, see the **github-actions-expert** and **gitlab-ci-guide** skills respectively.

---

## 4. SBOM and image signing

### SBOM (Software Bill of Materials)

Lists all the components and dependencies of the image. Required in many enterprise and regulatory contexts.

```bash
trivy image --format cyclonedx --output sbom.json monimage:1.0.0
```

### Image signing (cosign)

Guarantees that the image in the registry is really the one built by the pipeline, not tampered with.

```bash
cosign sign --key cosign.key monimage:1.0.0
cosign verify --key cosign.pub monimage:1.0.0
```

In an enterprise, the private key stays in a CI secret manager, never in plain text in the repo.

---

## 5. docker-compose: hardening

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

### Key points

- `read_only: true`: the container filesystem is read-only, `tmpfs` for occasional write needs
- `cap_drop: ALL` then targeted addition of only the necessary capabilities
- `no-new-privileges`: blocks privilege escalation through setuid
- Never `privileged: true` except for a documented and approved need (direct hardware access)
- Ports bound to loopback (`127.0.0.1:`) unless public exposure is explicitly wanted
- CPU/memory limits always defined (prevents a compromised or buggy container from exhausting the host)
- `healthcheck` every time, to allow automatic restart and monitoring

---

## 6. Runtime security (advanced level)

- **Seccomp**: Docker's default profile is enough in most cases, do not disable it (`--security-opt seccomp=unconfined` = red flag)
- **AppArmor/SELinux**: keep the default profile active, do not run in `unconfined` mode
- **User namespaces**: `--userns-remap` to isolate the container root from the host root
- **Network**: no `network_mode: host` unless truly needed (extreme network performance), otherwise it cancels network isolation

---

## 7. Final checklist before merge

- [ ] Multi-stage build, no build tools in the final image
- [ ] Base image pinned to a specific version
- [ ] Non-root `USER` defined
- [ ] `.dockerignore` present and up to date
- [ ] No secret in `ENV`/`ARG`/layer
- [ ] Trivy scan passed with no unjustified HIGH/CRITICAL CVE
- [ ] `HEALTHCHECK` defined
- [ ] CPU/memory limits defined
- [ ] Ports not publicly exposed without an explicit reason
- [ ] `cap_drop: ALL` in compose, capabilities added one by one if needed

---

## Related skills

- **docker-swarm-guide**: multi-node orchestration, stacks, Swarm secrets
- **helm-chart-builder**: if the final target is Kubernetes
- **github-actions-expert** / **gitlab-ci-guide**: integrating scanning and signing into the pipeline
- **security-review**: overall security review of a branch, not Docker-specific
