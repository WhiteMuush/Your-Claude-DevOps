---
name: github-actions-expert
description: Use when working with GitHub Actions, CI/CD workflows, custom actions, matrix builds, secrets, environments and reusable workflows. Triggers on "GitHub Actions", "GitHub workflow", "actions", "GitHub CI/CD", ".github/workflows".
---

# GitHub Actions Expert

## Workflow

1. **Analyze the required pipeline**, Identify the steps (build, test, lint, SAST, deployment), the suitable triggers and the branches involved.

   | Trigger | When to use it |
   |---------|-----------------|
   | `push` on `main` | Post-merge CI, continuous deployment |
   | `pull_request` | Validation before merge, required checks |
   | `schedule` | Maintenance jobs, nightly security audit |
   | `workflow_dispatch` | Manual deployment with parameters |
   | `release` (published) | Publishing packages, binaries |

2. **Structure the YAML**, Organize the jobs with explicit dependencies and conditions.

   ```yaml
   name: CI
   on:
     push:
       branches: [main]
     pull_request:
       branches: [main]
   permissions:           # Global least-privilege principle
     contents: read
   jobs:
     build:
       runs-on: ubuntu-latest
       permissions:
         contents: read
       steps:
         - uses: actions/checkout@11bd71901bbe5b1630ceea73d27597364c9af683  # v4.2.2
         - uses: actions/setup-node@49933ea5288caeca8642d1e84afbd3f7d6820020  # v4.4.0
           with:
             node-version: '22'
             cache: 'npm'
         - run: npm ci
         - run: npm run build
     test:
       needs: build
       runs-on: ubuntu-latest
       steps:
         - uses: actions/checkout@11bd71901bbe5b1630ceea73d27597364c9af683
         - run: npm ci && npm test
   ```

3. **Configure the matrix builds**, Test several environments without duplication.

   ```yaml
   strategy:
     fail-fast: false        # Do not cancel the other axes if one fails
     matrix:
       node: ['22', '24']
       os: [ubuntu-latest, windows-latest]
       include:
         - node: '24'
           os: ubuntu-latest
           coverage: true     # Custom variable for one specific axis
       exclude:
         - node: '22'
           os: windows-latest
   runs-on: ${{ matrix.os }}
   steps:
     - if: matrix.coverage
       run: npm run test:coverage
   ```

4. **Manage secrets and variables**, Hierarchy: Organization > Repository > Environment.

   ```yaml
   env:
     DATABASE_URL: ${{ vars.DATABASE_URL }}      # Non-sensitive variable
   steps:
     - name: Deploy
       env:
         API_KEY: ${{ secrets.PROD_API_KEY }}    # Secret injected as env, never as a CLI arg
       run: ./deploy.sh
   ```

   **OIDC (recommended on AWS/Azure/GCP)**, removes static cloud secrets:
   ```yaml
   permissions:
     id-token: write
     contents: read
   steps:
     - uses: aws-actions/configure-aws-credentials@e3dd6a429d7300a6a4c196c26e071d42e0343502  # v4
       with:
         role-to-assume: arn:aws:iam::123456789012:role/GitHubActions
         aws-region: eu-west-1
   ```

5. **Cache the dependencies**, Direct impact on pipeline duration.

   ```yaml
   - uses: actions/setup-node@49933ea5288caeca8642d1e84afbd3f7d6820020
     with:
       node-version: '22'
       cache: 'npm'           # Handles the cache automatically (prefer this option)
   # Or manual cache for custom cases:
   - uses: actions/cache@5a3ec84eff668545956fd18022155c47e93e2684  # v4
     with:
       path: ~/.m2/repository
       key: ${{ runner.os }}-maven-${{ hashFiles('**/pom.xml') }}
       restore-keys: |
         ${{ runner.os }}-maven-
   ```

6. **Create reusable workflows**, Extract common patterns as soon as they repeat.

   ```yaml
   # .github/workflows/reusable-deploy.yml
   on:
     workflow_call:
       inputs:
         environment:
           required: true
           type: string
       secrets:
         DEPLOY_TOKEN:
           required: true
   jobs:
     deploy:
       runs-on: ubuntu-latest
       environment: ${{ inputs.environment }}
       steps:
         - run: echo "Deploying to ${{ inputs.environment }}"
   ```

   Call from another workflow:
   ```yaml
   jobs:
     deploy-prod:
       uses: my-org/.github/.github/workflows/reusable-deploy.yml@main
       with:
         environment: production
       secrets:
         DEPLOY_TOKEN: ${{ secrets.DEPLOY_TOKEN }}
   ```

7. **Secure the pipeline**, Mandatory checklist.

   ```yaml
   # Pin to a SHA (never to a mutable tag)
   - uses: actions/checkout@11bd71901bbe5b1630ceea73d27597364c9af683  # v4.2.2

   # Attest the build provenance
   permissions:
     id-token: write
     attestations: write
   steps:
     - uses: actions/attest-build-provenance@<sha>   # see the box below
       with:
         subject-path: dist/app.tar.gz
   ```

8. **Optimize execution times**, Speed-up techniques.

   ```yaml
   # Skip jobs if the relevant files have not changed
   - uses: dorny/paths-filter@de90cc6fb38fc0963ad72b210f1f284cd68cea36  # v3
     id: changes
     with:
       filters: |
         backend:
           - 'src/**'
   - if: steps.changes.outputs.backend == 'true'
     run: npm run test:backend

   # Share artifacts between jobs
   - uses: actions/upload-artifact@<sha>   # see the box below
     with:
       name: dist
       path: dist/
       retention-days: 1
   ```

> **Getting the SHA of a tag**, the pinning rule applies to *all* actions, including those
> from GitHub itself. To resolve a tag into a SHA:
> ```bash
> gh api repos/actions/upload-artifact/git/ref/tags/v4 --jq .object.sha
> ```
> The SHAs quoted above match `checkout` v4.2.2 and `setup-node` v4.4.0: check them again
> before reuse, these actions have published major versions since.

## Anti-patterns and pitfalls

| Anti-pattern | Risk | Fix |
|---|---|---|
| `uses: actions/checkout@v4` (mutable tag) | Supply chain attack | Pin to the commit SHA |
| Global `permissions: write-all` | Privilege escalation | Declare only the permissions needed per job |
| Secrets displayed in `run` | Leak in the logs | Inject through `env:`, never through `${{ secrets.X }}` in shell commands |
| `continue-on-error: true` without logging | Hiding silent failures | Use with an explicit reporting step |
| No `timeout-minutes` | Job stuck forever = bill | Always set a timeout (GitHub default: 6h) |
| Storing credentials in variables (vars) | Accidental exposure | Vars = public config, secrets = credentials |
| Unmanaged concurrency on deployments | Double deployment | Use `concurrency` with `cancel-in-progress: true` |

```yaml
# Concurrency management for deployments
concurrency:
  group: deploy-${{ github.ref }}
  cancel-in-progress: true
```

## 2026 best practices

- **Dependabot for actions**, Add `.github/dependabot.yml` to keep the SHAs up to date automatically:
  ```yaml
  updates:
    - package-ecosystem: "github-actions"
      directory: "/"
      schedule:
        interval: "weekly"
  ```
- **Required status checks**, Protect `main`: enable branch protection rules with at least one required CI check and `Require branches to be up to date`.
- **Deployment environments**, Always use a GitHub Environment (`Settings > Environments`) with reviewers for production; environment secrets override repo secrets.
- **Self-hosted runners**, Isolate them in ephemeral VMs (or containers); never use them on public repos without `if: github.event.pull_request.head.repo.full_name == github.repository` to block forks.
- **Log auditing**, Enable `ACTIONS_STEP_DEBUG` and `ACTIONS_RUNNER_DEBUG` as secrets (value `true`) for debugging; disable them in production.
