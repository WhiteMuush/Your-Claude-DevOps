---
name: docker-swarm-guide
description: Use when orchestrating with Docker Swarm, including services, stacks, overlay networks, secrets, rolling updates and high availability. Triggers on "Docker Swarm", "swarm mode", "docker service", "docker stack", "overlay network"
---

# Docker Swarm Guide

## Selection criteria: Swarm vs Kubernetes

| Criterion | Swarm | Kubernetes |
|---|---|---|
| Team < 5 devops | ✅ | ❌ operational complexity |
| Simple on-premise infra | ✅ | possible but heavy |
| Advanced multitenancy | ❌ | ✅ |
| Fine-grained RBAC, CRDs, Operators | ❌ | ✅ |
| Existing Docker Compose stack | ✅ easy migration | conversion required |

Choose Swarm if you already have Compose files, a small team, and no need for horizontal scaling to 100+ nodes.

---

## Step-by-step workflow

### 1. Initialize the cluster

```bash
# On the first manager (replace the IP with the private inter-node network IP)
docker swarm init --advertise-addr 192.168.1.10

# Get the tokens
docker swarm join-token manager   # to add a manager
docker swarm join-token worker    # to add a worker

# Join from another node
docker swarm join --token SWMTKN-1-xxx 192.168.1.10:2377

# Check the cluster state
docker node ls
```

**Raft quorum rule**: always an odd number of managers.
- 3 managers → tolerates 1 failure
- 5 managers → tolerates 2 failures
- Never go beyond 7 managers (consensus latency)

```bash
# Promote a worker to manager
docker node promote <node-id>

# Check Raft health
docker node inspect self --format '{{ .ManagerStatus.Reachability }}'
```

---

### 2. Configure the overlay networks

```bash
# Encrypted network for sensitive data
docker network create \
  --driver overlay \
  --opt encrypted \
  --subnet 10.0.1.0/24 \
  backend-net

# Unencrypted frontend network (less CPU)
docker network create --driver overlay frontend-net
```

**Recommended isolation pattern**:
- `frontend-net`: load balancer ↔ app
- `backend-net`: app ↔ database
- `monitoring-net`: monitoring agents (attachable)

```bash
# Attachable network for ad hoc debug/tests
docker network create --driver overlay --attachable debug-net
```

---

### 3. Deploy a service

```bash
# Minimal service with replicas
docker service create \
  --name api \
  --replicas 3 \
  --network backend-net \
  --publish published=8080,target=3000 \
  --limit-cpu 0.5 \
  --limit-memory 256M \
  --reserve-cpu 0.25 \
  --reserve-memory 128M \
  --health-cmd "curl -f http://localhost:3000/health || exit 1" \
  --health-interval 10s \
  --health-retries 3 \
  myrepo/api:1.2.0

# Inspect the tasks and their state
docker service ps api --no-trunc
```

**Placement constraints**:
```bash
# Force onto nodes labeled SSD
docker node update --label-add disk=ssd worker-1

docker service create \
  --constraint 'node.labels.disk == ssd' \
  --name db \
  postgres:16
```

---

### 4. Stacks with docker-compose (recommended method)

```yaml
# docker-compose.prod.yml
services:
  api:
    image: myrepo/api:${API_VERSION:-latest}
    networks:
      - frontend-net
      - backend-net
    secrets:
      - db_password
    environment:
      DB_HOST: db
    deploy:
      replicas: 3
      update_config:
        parallelism: 1
        delay: 15s
        failure_action: rollback
        monitor: 30s
        order: start-first       # zero-downtime: new container before the old one stops
      rollback_config:
        parallelism: 1
        delay: 10s
        failure_action: pause
      restart_policy:
        condition: on-failure
        delay: 5s
        max_attempts: 3
      resources:
        limits:
          cpus: "0.5"
          memory: 256M
        reservations:
          cpus: "0.25"
          memory: 128M
      placement:
        constraints:
          - node.role == worker
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:3000/health"]
      interval: 10s
      timeout: 5s
      retries: 3
      start_period: 20s

  db:
    image: postgres:16
    networks:
      - backend-net
    secrets:
      - db_password
    environment:
      POSTGRES_PASSWORD_FILE: /run/secrets/db_password
    volumes:
      - db-data:/var/lib/postgresql/data
    deploy:
      replicas: 1
      placement:
        constraints:
          - node.labels.disk == ssd

networks:
  frontend-net:
    driver: overlay
  backend-net:
    driver: overlay
    driver_opts:
      encrypted: "true"

volumes:
  db-data:

secrets:
  db_password:
    external: true
```

```bash
# Deploy / update the stack
docker stack deploy -c docker-compose.prod.yml myapp

# List the services of the stack
docker stack services myapp

# Remove the stack (does not delete the volumes)
docker stack rm myapp
```

---

### 5. Manage secrets and configs

```bash
# Create a secret from stdin (never from a plain-text file in prod)
echo "S3cr3tP@ss" | docker secret create db_password -

# From a file
docker secret create tls_cert ./cert.pem

# List / inspect (the content is never displayed)
docker secret ls
docker secret inspect db_password

# Config (non-sensitive, config files, templates)
docker config create nginx_conf ./nginx.conf

# Usage in a service
docker service update \
  --config-add source=nginx_conf,target=/etc/nginx/nginx.conf \
  nginx
```

Secrets are mounted in RAM (`tmpfs`) in `/run/secrets/<nom>`. They never touch the worker's disk.

---

### 6. Rolling updates and rollbacks

```bash
# Image update (zero-downtime with order: start-first)
docker service update \
  --image myrepo/api:1.3.0 \
  --update-parallelism 1 \
  --update-delay 15s \
  --update-failure-action rollback \
  api

# Follow the progress
docker service ps api --filter desired-state=running

# Immediate manual rollback
docker service rollback api

# Force a restart without changing the image (e.g. modified secrets)
docker service update --force api
```

---

### 7. Global services and monitoring

```bash
# Deploy a Prometheus Node Exporter agent on EVERY node
docker service create \
  --name node-exporter \
  --mode global \
  --network monitoring-net \
  --mount type=bind,src=/proc,dst=/host/proc,ro=true \
  --mount type=bind,src=/sys,dst=/host/sys,ro=true \
  prom/node-exporter:latest
```

---

## Guardrails and anti-patterns

### ❌ Never do

```bash
# DANGER: exposes the secrets in docker inspect / logs
docker service create -e DB_PASSWORD=secret123 myapp

# DANGER: manager used as a worker in prod
# (the manager runs Raft, CPU overload = quorum instability)
docker node update --availability drain manager-1  # ← correct way to drain

# DANGER: local volume shared between replicas without NFS/Ceph
# Each replica on its node has its own local copy → inconsistency
```

### ⚠️ Common pitfalls

| Pitfall | Symptom | Solution |
|---|---|---|
| `update_config.order: stop-first` (default) | Downtime during update | Switch to `start-first` |
| No `healthcheck` | Tasks "Running" but app down | Always define a healthcheck |
| No `resource limits` | One OOM service kills the node | Always limit CPU + RAM |
| Quorum lost (2 of 3 managers down) | Cluster in read-only | Restore with `docker swarm init --force-new-cluster` |
| `latest` image in prod | Rollback impossible | Always tag the versions |
| Draining a node without checking the replicas | Replicas rescheduled onto overloaded nodes | Watch `docker service ps` after the drain |

---

## Diagnostic commands

```bash
# Global cluster state
docker node ls
docker service ls

# Failed tasks
docker service ps <service> --filter desired-state=shutdown

# Logs of a service (all tasks)
docker service logs --follow --tail 100 api

# Inspect a node (labels, resources)
docker node inspect <node-id> --pretty

# CPU/memory stats of the containers on the local node
docker stats --no-stream
```

---

## 2026 best practices

- **Private registry with TLS**: set `--with-registry-auth` on `docker stack deploy` so that the swarm can pull from a private registry.
- **Secret rotation**: create a new versioned secret (`db_password_v2`), update the service, then delete the old one, Swarm does not support in-place update of a secret.
- **Drain before maintenance**: `docker node update --availability drain <node>` cleanly migrates the tasks before you touch the node.
- **Structured labels**: use hierarchical labels (`zone=eu-west`, `disk=ssd`, `gpu=true`) for precise placement constraints.
- **CI/CD**: couple `docker stack deploy` with a GitLab/GitHub Actions pipeline using the commit tag as the image version, never `latest` in production.
