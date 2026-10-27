---
name: terraform-guide
description: Terraform guide for Infrastructure as Code, modules, state management, workspaces and best practices. Use when the user writes Terraform, designs modules or manages cloud infrastructure. Also triggers on "terraform", "infrastructure as code", "terraform plan", "terraform apply", "terraform module", "tfstate", "HCL".
---

# Terraform guide

## 1. Operational workflow (numbered steps)

1. **Initialize**, configure the backend and download the providers.
   ```bash
   terraform init -upgrade          # first time or provider update
   terraform init -reconfigure      # change backend without migrating the state
   ```
2. **Validate**, check the syntax before planning.
   ```bash
   terraform validate
   terraform fmt -recursive         # format the whole directory
   ```
3. **Plan**, always save the plan for a deterministic apply.
   ```bash
   terraform plan -out=tfplan.bin
   terraform show -json tfplan.bin | jq '.resource_changes[] | select(.change.actions != ["no-op"])'
   ```
4. **Apply**, only from the saved plan.
   ```bash
   terraform apply tfplan.bin
   ```
5. **Check for drift**, detect divergences between state and reality.
   ```bash
   terraform plan -refresh-only     # see what changed outside Terraform
   terraform apply -refresh-only    # resync the state without modifying resources
   ```
6. **Destroy cleanly**, target first, never in bulk without review.
   ```bash
   terraform destroy -target=module.networking.azurerm_subnet.main
   ```

---

## 2. Recommended project structure

```
infrastructure/
├── environments/
│   ├── dev/
│   │   ├── main.tf          # module calls
│   │   ├── variables.tf
│   │   ├── terraform.tfvars
│   │   └── backend.tf
│   ├── staging/
│   └── production/
├── modules/
│   ├── networking/          # one module = one responsibility
│   │   ├── main.tf
│   │   ├── variables.tf
│   │   └── outputs.tf
│   ├── database/
│   └── app-service/
└── shared/
    └── versions.tf          # provider version constraints
```

**Splitting criterion**: one module per "functional domain" (network, storage, compute). Avoid 1-resource modules (over-splitting) and "all-in-one" modules (tight coupling).

---

## 3. Reusable module, complete example

```hcl
# modules/app-service/variables.tf
variable "app_name"           { type = string }
variable "environment"        {
  type    = string
  validation {
    condition     = contains(["dev", "staging", "production"], var.environment)
    error_message = "Accepted values: dev, staging, production."
  }
}
variable "sku"                { type = string; default = "B1" }
variable "location"           { type = string }
variable "resource_group_name"{ type = string }
variable "app_settings"       { type = map(string); default = {} }

# modules/app-service/main.tf
locals {
  common_tags = {
    Environment = var.environment
    ManagedBy   = "terraform"
    Application = var.app_name
  }
}

resource "azurerm_service_plan" "this" {
  name                = "plan-${var.app_name}-${var.environment}"
  location            = var.location
  resource_group_name = var.resource_group_name
  os_type             = "Linux"
  sku_name            = var.sku
  tags                = local.common_tags
}

resource "azurerm_linux_web_app" "this" {
  name                = "app-${var.app_name}-${var.environment}"
  location            = var.location
  resource_group_name = var.resource_group_name
  service_plan_id     = azurerm_service_plan.this.id
  tags                = local.common_tags

  site_config {
    always_on = var.environment == "production"
    application_stack { dotnet_version = "8.0" }
  }

  app_settings = var.app_settings
}

# modules/app-service/outputs.tf
output "app_url"     { value = "https://${azurerm_linux_web_app.this.default_hostname}" }
output "app_id"      { value = azurerm_linux_web_app.this.id }
output "plan_id"     { value = azurerm_service_plan.this.id }
```

Call from an environment:
```hcl
module "api" {
  source              = "../../modules/app-service"
  app_name            = "myapi"
  environment         = "production"
  sku                 = "P1v3"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
}
```

---

## 4. State management

### Remote backend with locking (Azure)
```hcl
# environments/production/backend.tf
terraform {
  backend "azurerm" {
    resource_group_name  = "rg-terraform-state"
    storage_account_name = "stterraformstprod"
    container_name       = "tfstate"
    key                  = "myapp.production.tfstate"
    use_azuread_auth     = true   # avoids account keys (2025+)
  }
}
```

### S3 + DynamoDB backend (AWS)
```hcl
terraform {
  backend "s3" {
    bucket         = "myco-tfstate-prod"
    key            = "myapp/production/terraform.tfstate"
    region         = "eu-west-1"
    encrypt        = true
    use_lockfile   = true   # native S3 locking (Terraform 1.10+)
  }
}
```

> `dynamodb_table` has been deprecated since Terraform 1.11: locking now goes through a
> lock file in the bucket itself. One less DynamoDB table to provision and pay for.

### State management commands
```bash
terraform state list                              # all resources
terraform state show azurerm_linux_web_app.this   # details of one resource
terraform state mv  module.old.res module.new.res # rename without recreating
terraform state rm  azurerm_resource_group.legacy # remove from state without destroying
terraform import    azurerm_resource_group.legacy /subscriptions/.../rg-name
```

---

## 5. Provider versions and constraints

```hcl
# shared/versions.tf, to copy into each environment
terraform {
  required_version = ">= 1.7, < 2.0"
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 5.1"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }
}
```

Lock the `.terraform.lock.hcl` in Git, it guarantees reproducible builds.

> **Migration 3.x → 5.x**: azurerm has gone through two major versions since 3. Version 4.0 makes `subscription_id`
> mandatory in the provider block and replaces `skip_provider_registration` with
> `resource_provider_registrations`. Do not skip these two steps without reading the upgrade guides.

---

## 6. Guardrails and common pitfalls

| Pitfall | Symptom | Remedy |
|-------|----------|--------|
| Local state / committed to Git | Team conflicts, exposed secrets | Remote backend + `.gitignore` on `*.tfstate*` |
| `terraform apply` without a saved plan | Inconsistent apply if the state changed in the meantime | Always `-out=tfplan.bin` + `apply tfplan.bin` |
| Hard-coding secrets in HCL | Secrets in Git | `var` + Key Vault / Secrets Manager or `sensitive = true` |
| Modules too fine-grained (1 resource) | Composition overhead, nested calls | Group by functional domain |
| `terraform destroy` without `-target` | Destruction of the whole infra | Always target or use isolated workspaces |
| Ignored drift | Real state diverges from the plan | Weekly `plan -refresh-only` in CI |
| No `lifecycle.prevent_destroy` on critical resources | Accidental deletion of database/storage | Add `prevent_destroy = true` on stateful resources |

```hcl
# Protect a critical database
resource "azurerm_postgresql_flexible_server" "main" {
  # ...
  lifecycle {
    prevent_destroy = true
  }
}
```

---

## 7. 2026 best practices

- **Pin provider versions** via `.terraform.lock.hcl` (committed to Git).
- **Secrets**: never put them in `.tfvars`; use `sensitive = true` + CI injection (`TF_VAR_*` env vars).
- **Systematic tagging**: `locals` module with `common_tags` inherited by all resources.
- **Sensitive outputs**: mark them `sensitive = true` to avoid plaintext logs.
- **CI/CD**: `terraform plan` on PR (automatic comment), `terraform apply` only on merge to main.
- **Workspaces**: reserved for ephemeral environments (feature branches), do not use them for prod/staging (prefer separate folders with their own state).
- **Tflint + Checkov**: linting and security scanning before the plan.
  ```bash
  tflint --recursive
  checkov -d . --framework terraform
  ```

---

## 8. Quick reference commands

```bash
# Init & format
terraform init -upgrade && terraform fmt -recursive && terraform validate

# Safe plan
terraform plan -var-file=environments/prod.tfvars -out=tfplan.bin

# Plan inspection
terraform show tfplan.bin                   # human readable
terraform show -json tfplan.bin | jq '.'   # JSON for scripts

# State ops
terraform state list
terraform state show <resource_address>
terraform state mv   <src> <dst>
terraform state rm   <resource_address>

# Import an existing resource
terraform import <resource_address> <cloud_id>

# Drift
terraform plan -refresh-only
```
