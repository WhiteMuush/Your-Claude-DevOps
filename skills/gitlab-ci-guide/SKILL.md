---
name: gitlab-ci-guide
description: Use when working with GitLab CI/CD pipelines, stages, jobs, runners, artifacts, environments and Auto DevOps. Triggers on "GitLab CI", "gitlab-ci.yml", "GitLab pipeline", "GitLab runner", "GitLab CD".
---

# GitLab CI/CD Guide

## 1. Design the pipeline structure

Define the stages in logical execution order. Jobs in the same stage run in parallel; `needs:` breaks this constraint for a DAG.

```yaml
stages:
  - build
  - test
  - analyze
  - deploy
```

**Splitting criteria:**
- One stage = one responsibility (do not mix build and test).
- If a job must start before its stage ends, use `needs:` (DAG).
- Limit to 6-7 stages max, beyond that, refactor into child pipelines.

## 2. Write the jobs

Minimal structure of a reference job:

```yaml
build:app:
  stage: build
  image: node:22-alpine
  before_script:
    - npm ci --cache .npm --prefer-offline
  script:
    - npm run build
  artifacts:
    paths:
      - dist/
    expire_in: 1 day
  cache:
    key:
      files:
        - package-lock.json
    paths:
      - .npm/
```

**Execution rules, prefer `rules:` over `only/except`**:

```yaml
deploy:production:
  stage: deploy
  rules:
    - if: $CI_COMMIT_BRANCH == $CI_DEFAULT_BRANCH
      when: manual
    - if: $CI_PIPELINE_SOURCE == "merge_request_event"
      when: never
  environment:
    name: production
    url: https://app.example.com
```

## 3. Manage the runners

| Type | Use case | Key config |
|------|------------|------------|
| Shared runners | Standard CI, public projects | Empty tags or `saas-linux-*` |
| Group runners | Team sharing infra secrets | `group_runners_enabled: true` |
| Project runners | Internal network access, GPU, Windows | Runner registered with a dedicated tag |

**Register a runner (GitLab 17+):**
```bash
gitlab-runner register \
  --url https://gitlab.example.com \
  --token $RUNNER_TOKEN \
  --executor docker \
  --docker-image alpine:latest \
  --tag-list "docker,linux,build"
```

**Auto-scaling (on-premise):** use the **GitLab Runner Autoscaler** (Fleeting + Taskscaler), with the AWS EC2, Google Compute Engine or Azure plugins. For Kubernetes: the official runner Helm chart.

> The old `executor = "docker+machine"` has been deprecated since GitLab 17.5 and will be removed in 20.0 (May 2027): Docker abandoned Docker Machine, the component it relied on. The `config.toml` configurations found online still use it heavily.

## 4. Cache and artifacts

```yaml
# Cache shared between branches, key on the lock file
cache:
  key:
    files:
      - yarn.lock
  paths:
    - node_modules/
  policy: pull-push   # pull-push by default; "pull" for read-only jobs

# Test coverage artifact
test:unit:
  script: pytest --cov=src --cov-report=xml
  artifacts:
    reports:
      coverage_report:
        coverage_format: cobertura
        path: coverage.xml
    expire_in: 7 days
```

**Rule:** always set `expire_in` on artifacts, without it, GitLab keeps them by default according to the instance config (can fill up the storage).

**`dependencies: []`** on deployment jobs to avoid downloading useless artifacts.

## 5. Advanced pipelines

### DAG with `needs:`
```yaml
test:unit:
  stage: test
  needs: [build:app]   # starts as soon as build:app is done, not the whole build stage

test:e2e:
  stage: test
  needs: [build:app, build:docker]
```

### Child pipelines (monorepo)
```yaml
trigger:backend:
  trigger:
    include: backend/.gitlab-ci.yml
    strategy: depend   # the parent waits for the child pipeline to finish
  rules:
    - changes:
        - backend/**/*
```

### Shared templates
```yaml
include:
  - project: 'infra/ci-templates'
    ref: main
    file: '/templates/docker-build.yml'
  - template: 'Security/SAST.gitlab-ci.yml'
```

## 6. Environments and deployments

```yaml
deploy:review:
  stage: deploy
  script: ./scripts/deploy-review.sh $CI_ENVIRONMENT_SLUG
  environment:
    name: review/$CI_COMMIT_REF_SLUG
    url: https://$CI_ENVIRONMENT_SLUG.preview.example.com
    on_stop: stop:review
  rules:
    - if: $CI_PIPELINE_SOURCE == "merge_request_event"

stop:review:
  stage: deploy
  script: ./scripts/teardown-review.sh $CI_ENVIRONMENT_SLUG
  environment:
    name: review/$CI_COMMIT_REF_SLUG
    action: stop
  when: manual
  rules:
    - if: $CI_PIPELINE_SOURCE == "merge_request_event"
```

## 7. Built-in security

Enable the native scanners through the official templates:
```yaml
include:
  - template: Security/SAST.gitlab-ci.yml
  - template: Security/Dependency-Scanning.gitlab-ci.yml
  - template: Security/Container-Scanning.gitlab-ci.yml
  - template: Security/Secret-Detection.gitlab-ci.yml
```

**Sensitive variables:**
```bash
# Through the CLI
glab variable set MY_SECRET "valeur" --masked --protected --project monprojet
```
In the UI: Settings > CI/CD > Variables → check `Masked` + `Protected`.

## Guardrails and anti-patterns

| Anti-pattern | Consequence | Fix |
|---|---|---|
| Using `only/except` | Unpredictable behavior on MRs | Migrate to `rules:` |
| Artifacts without `expire_in` | Storage saturation | Always set `expire_in` |
| Plain-text secrets in the script | Leak in the logs | Masked + protected variables |
| A single 500-line `.gitlab-ci.yml` | Unreadable, impossible to maintain | `include:local:` per domain |
| Cache without `key:files:` | Cache invalidated or wrongly reused | Key on the lock file |
| `when: always` on cleanup jobs | Runs even when upstream fails | `when: on_failure` or explicit `needs:` |
| No `interruptible: true` on build jobs | Saturated runner queues | Mark the jobs as cancellable |

## 2026 best practices

- **Pipeline Component Catalog** (GitLab 16.9+): publish reusable components in the Catalog rather than `include:remote` templates.
- **CI/CD Catalog**: prefer `component:` over `include:project:` for semantic versioning.
- **`id_tokens:`** (OIDC): replace static tokens for cloud auth (AWS, Azure, GCP) with short-lived OIDC tokens.
- **Merge Train**: enable it on high-traffic protected branches to avoid post-merge regressions.
- **`dast_configuration:`**: point to a review environment for DAST rather than a hard-coded URL.
- Validate the pipeline before pushing: the GitLab **pipeline editor** (*Validate* tab) simulates the syntax and the rules. For a real local run, the third-party tool `gitlab-ci-local`.

> `gitlab-runner exec` was **removed** in GitLab Runner 16.0. The command no longer exists; it is still quoted in a lot of outdated documentation.
