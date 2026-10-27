---
name: helm-chart-builder
description: Use when the user creates or modifies Helm charts, configures K8s deployments or manages releases. Covers Helm chart design for Kubernetes, templates, values, dependencies and deployment strategies. Also triggers on "helm", "helm chart", "helm template", "values.yaml", "helm install", "helm upgrade", "kubernetes helm".
---

# Helm Chart Builder

## Step-by-step workflow

1. **Analyze**, identify: app type (stateless/stateful), external dependencies, target environments, ingress/secret/HPA needs.
2. **Scaffold**, `helm create mychart` then clean up the useless examples.
3. **Model `values.yaml`**, define defaults that work in dev without overrides. Everything that varies per env = exposed as a value.
4. **Write the templates**, use `_helpers.tpl` for labels/names; add `checksum/config` to force the rollout when the ConfigMap changes.
5. **Validate locally**, `helm lint`, `helm template`, `helm diff` (plugin) before any push.
6. **Deploy per env**, `helm upgrade --install` with `-f values-prod.yaml` and `--set image.tag=$TAG`.
7. **Post-deploy operations**, check `helm status`, inspect the logs, plan for `helm rollback` if needed.

## Typical structure

```
mychart/
├── Chart.yaml              # Metadata + dependencies
├── values.yaml             # Defaults (working dev without override)
├── values-staging.yaml
├── values-prod.yaml
├── templates/
│   ├── _helpers.tpl        # reusable includes (labels, fullname…)
│   ├── deployment.yaml
│   ├── service.yaml
│   ├── ingress.yaml
│   ├── hpa.yaml
│   ├── configmap.yaml
│   ├── secret.yaml         # or ExternalSecret if ESO
│   ├── serviceaccount.yaml
│   └── NOTES.txt           # displayed after install
└── charts/                 # downloaded dependencies
```

## Chart.yaml

```yaml
apiVersion: v2
name: payment-api
description: Payment management API
type: application          # or "library" for a utility chart
version: 1.3.0             # chart SemVer (independent from the app)
appVersion: "3.2.0"        # version of the application image
dependencies:
  - name: cloudnative-pg
    version: "0.x.x"               # check: helm search repo cnpg
    repository: "https://cloudnative-pg.github.io/charts"
    condition: cloudnative-pg.enabled   # can be disabled through values
```

> **Bitnami pitfall**: most online tutorials declare their dependencies on
> `oci://registry-1.docker.io/bitnamicharts`. Broadcom removed this public catalog on
> September 29, 2025: the versioned charts moved behind a subscription, only
> 44 "development-only" images remain, tagged `latest`. These examples fail at
> `helm dependency update`. Alternatives: the official chart of the upstream project when it exists,
> otherwise the maintained forks (Chainguard, RapidFort).

> **Criterion**: bump `version` on every template change; bump `appVersion` on every application release.

## `_helpers.tpl`, minimal base

```yaml
{{- define "mychart.fullname" -}}
{{- printf "%s-%s" .Release.Name .Chart.Name | trunc 63 | trimSuffix "-" }}
{{- end }}

{{- define "mychart.labels" -}}
helm.sh/chart: {{ .Chart.Name }}-{{ .Chart.Version }}
app.kubernetes.io/name: {{ .Chart.Name }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{- define "mychart.selectorLabels" -}}
app.kubernetes.io/name: {{ .Chart.Name }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}
```

## Deployment, reference template

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: {{ include "mychart.fullname" . }}
  labels:
    {{- include "mychart.labels" . | nindent 4 }}
spec:
  {{- if not .Values.autoscaling.enabled }}
  replicas: {{ .Values.replicaCount }}
  {{- end }}
  selector:
    matchLabels:
      {{- include "mychart.selectorLabels" . | nindent 6 }}
  template:
    metadata:
      labels:
        {{- include "mychart.selectorLabels" . | nindent 8 }}
      annotations:
        checksum/config: {{ include (print $.Template.BasePath "/configmap.yaml") . | sha256sum }}
    spec:
      serviceAccountName: {{ include "mychart.fullname" . }}
      securityContext:
        runAsNonRoot: true
        runAsUser: 1000
      containers:
        - name: {{ .Chart.Name }}
          image: "{{ .Values.image.repository }}:{{ .Values.image.tag | default .Chart.AppVersion }}"
          imagePullPolicy: {{ .Values.image.pullPolicy }}
          ports:
            - name: http
              containerPort: {{ .Values.service.targetPort }}
          envFrom:
            - configMapRef:
                name: {{ include "mychart.fullname" . }}
          {{- if .Values.secret.enabled }}
          env:
            - name: DB_PASSWORD
              valueFrom:
                secretKeyRef:
                  name: {{ include "mychart.fullname" . }}
                  key: db-password
          {{- end }}
          resources:
            {{- toYaml .Values.resources | nindent 12 }}
          livenessProbe:
            httpGet:
              path: {{ .Values.probes.liveness.path }}
              port: http
            initialDelaySeconds: 10
            periodSeconds: 15
          readinessProbe:
            httpGet:
              path: {{ .Values.probes.readiness.path }}
              port: http
            initialDelaySeconds: 5
            periodSeconds: 10
```

## `values.yaml`, complete defaults

```yaml
replicaCount: 1   # override to 2+ in prod

image:
  repository: myregistry.azurecr.io/payment-api
  tag: ""          # empty = Chart.AppVersion
  pullPolicy: IfNotPresent

service:
  type: ClusterIP
  port: 80
  targetPort: 8080

ingress:
  enabled: false   # enabled by values-prod.yaml
  className: nginx
  annotations:
    nginx.ingress.kubernetes.io/rewrite-target: /
  hosts:
    - host: api.company.com
      paths:
        - path: /
          pathType: Prefix

resources:
  requests:
    cpu: 100m
    memory: 256Mi
  limits:
    cpu: 500m
    memory: 512Mi

autoscaling:
  enabled: false
  minReplicas: 2
  maxReplicas: 10
  targetCPUUtilizationPercentage: 70

probes:
  liveness:
    path: /health/live
  readiness:
    path: /health/ready

secret:
  enabled: false

cloudnative-pg:
  enabled: false   # enable locally if needed
```

## Essential commands

```bash
# Scaffolding
helm create mychart

# Local validation (always before push)
helm lint mychart
helm template myrelease mychart -f values-prod.yaml | kubectl apply --dry-run=client -f -

# Deployment, with automatic rollback on failure (--rollback-on-failure in Helm 4, --atomic in Helm 3)
helm upgrade --install myrelease ./mychart \
  -f values-prod.yaml \
  --set image.tag=v3.2.0 \
  --namespace prod \
  --create-namespace \
  --rollback-on-failure \
  --timeout 5m

# Differences before upgrade (helm-diff plugin required)
helm diff upgrade myrelease ./mychart -f values-prod.yaml --set image.tag=v3.2.0

# Rollback
helm rollback myrelease 1   # revision 1

# Dependencies
helm dependency update mychart

# Inspect a release
helm status myrelease -n prod
helm get values myrelease -n prod
helm history myrelease -n prod

# OCI registry (Helm 3.8+)
helm push mychart-1.3.0.tgz oci://myregistry.azurecr.io/charts
helm install myrelease oci://myregistry.azurecr.io/charts/mychart --version 1.3.0
```

## Decision criteria

| Need | Recommended solution |
|---|---|
| Sensitive secret in prod | ExternalSecret (ESO) or Vault Agent Injector, not a plain-text `kind: Secret` |
| Multiple environments | `values-<env>.yaml` + `-f` at install, no excessive conditional Helm templating |
| Local DB dependency in dev | `cloudnative-pg.enabled: true` in `values-dev.yaml` |
| Stateful app (DB, Kafka…) | `StatefulSet` + PVC in the template, not `Deployment` |
| Chart reused across teams | `library` type chart in a shared OCI registry |
| Zero-downtime rollout | `strategy.type: RollingUpdate` + `minReadySeconds` + correct probes |

## Anti-patterns / pitfalls

- **`image.tag: latest`**, not reproducible. Always pass `--set image.tag=$CI_SHA`.
- **Plain-text secrets in values.yaml**, never commit credentials; use ESO, Vault or `--set secret.password=$VAR` from CI.
- **`helm install` without `--rollback-on-failure`**, leaves a release in `FAILED` state; prefer `--rollback-on-failure` in CI/CD. Helm 4 renamed `--atomic` to `--rollback-on-failure` and `--force` to `--force-replace`: the old names still work but print a deprecation warning.
- **Omitting `checksum/config`**, the pod does not restart when the ConfigMap changes without this annotation.
- **Forgetting `helm dependency update`**, empty `charts/` folder → install fails silently.
- **Poorly separated versioning**, do not sync `version` (chart) and `appVersion` (image): the two move independently.
- **Overly conditional templates**, `{{- if .Values.featureX }}…{{- end }}` everywhere makes the chart unreadable; prefer separate charts or Kustomize overlays for major variants.
- **No `NOTES.txt`**, deprives users of the post-install instructions.

## 2026 best practices

- Publish to an **OCI registry** (ACR, ECR, GHCR) rather than a classic HTTP chart repo.
- Use **`helm diff`** in CI to generate a readable summary in the PR before merge.
- Pair with **`ct` (chart-testing)** for linting and automated integration tests.
- Enable **`NetworkPolicy`** by default in the chart to limit the blast radius.
- Generate the values **documentation** with `helm-docs` (`# -- description` annotations).
- Prefer **`--rollback-on-failure --timeout`** in CD to guarantee an automatic rollback when a rollout fails (`--atomic` on a Helm 3 client).
