---
name: azure-cloud-advisor
description: Advice for architecture and deployment on Azure, App Service, Azure Functions, Container Apps, SQL Azure and cloud best practices. Use when the user deploys on Azure, chooses cloud services or optimizes Azure costs. Also triggers on "Azure", "App Service", "Azure Functions", "Container Apps", "Azure SQL", "Azure deployment", "Azure costs".
---

# Azure Cloud Advisor

## Workflow

1. **Qualify the need**: workload type (web, event-driven, batch, real time), constraints (SLA, latency, data residency), target monthly budget.
2. **Choose the compute service**: use the matrix below; if ambiguous, ask whether the team already knows K8s.
3. **Architect**: network topology (VNet, Private Endpoints), security (Managed Identity, Key Vault), resilience (zones, geo-replication).
4. **Provision**: copy-ready `az` commands or Bicep/Terraform.
5. **Optimize**: costs (Reserved, Spot, scale-to-zero), performance (profiling through App Insights), scalability.

---

## Choosing the compute service

| Service | Ideal use | Scale | Cost profile |
|---|---|---|---|
| **App Service** | .NET, Node, Python web API/app | Auto-scale per plan | Fixed floor per plan, paid even when idle |
| **Container Apps** | Containerized microservices, Dapr | KEDA, scale-to-zero | Zero when stopped, rises with traffic |
| **Azure Functions** | Event-driven, triggers (HTTP, Queue, Timer) | Consumption auto | Cheapest below the free tier |
| **AKS** | Complex K8s orchestration, multi-tenant | Node autoscaler + KEDA | Most expensive: nodes paid continuously |
| **VM / VMSS** | Legacy, full network control | Manual or VMSS | Variable, depends on sizing |

> Absolute amounts vary by region, tier and commitment, and change too often
> to be reliable in a reference sheet. What matters is the relative order:
> check today's figure with `az pricing` or the Azure calculator.

### Decision tree

```
New project?
├── Short event-driven processing (< 10 min) → Azure Functions (Consumption)
├── Containerized microservices, variable traffic → Container Apps
├── Web app / REST API, team without K8s ops    → App Service
├── Advanced Kubernetes needs (CRD, helm, custom network) → AKS
└── Lift-and-shift migration or GPU workload   → VM / VMSS

Migrating an existing system?
├── Monolithic .NET IIS app → App Service (Windows plan)
├── Existing Docker Compose  → Container Apps
└── Very fine network control (BGP, ASN)        → AKS or VMs
```

---

## Provisioning, copy-ready commands

### Create a Container Apps Environment + app

```bash
# Variables
RG=rg-myapp-prod
LOCATION=westeurope
ENV=cae-myapp-prod
APP=api-backend

az group create -n $RG -l $LOCATION

az containerapp env create \
  --name $ENV --resource-group $RG --location $LOCATION

az containerapp create \
  --name $APP --resource-group $RG \
  --environment $ENV \
  --image myregistry.azurecr.io/api:latest \
  --target-port 8080 --ingress external \
  --min-replicas 0 --max-replicas 10 \
  --cpu 0.5 --memory 1Gi \
  --registry-server myregistry.azurecr.io \
  --system-assigned                         # Managed Identity
```

### Create an Azure Function (Consumption)

```bash
az storage account create -n stfnmyapp -g $RG -l $LOCATION --sku Standard_LRS
az functionapp create \
  --name fn-myapp-prod --resource-group $RG \
  --storage-account stfnmyapp \
  --consumption-plan-location $LOCATION \
  --runtime dotnet-isolated --runtime-version 10 \
  --functions-version 4 \
  --assign-identity '[system]'
```

### App Service + staging slot

```bash
az appservice plan create -n plan-myapp -g $RG --sku P2V3 --is-linux
az webapp create -n web-myapp -g $RG --plan plan-myapp --runtime "DOTNETCORE:10.0"
az webapp deployment slot create --name web-myapp -g $RG --slot staging
# Zero-downtime swap:
az webapp deployment slot swap --name web-myapp -g $RG --slot staging
```

---

## Reference architecture, Container Apps (microservices)

```
Internet
  → Azure Front Door (CDN + WAF)
      → Container Apps Environment (integrated VNet)
            API Gateway (YARP / NGINX)
            ├── Service A  (scale-to-zero, KEDA Queue)
            ├── Service B  (min 1 replica)
            └── Worker     (Azure Service Bus trigger)
      → Azure SQL (Private Endpoint)
      → Azure Cache for Redis (Premium, clustering)
      → Azure Service Bus (Topics + DLQ)
      → Azure Key Vault   (Managed Identity, no secrets in env vars)
      → Application Insights + Log Analytics Workspace
```

---

## Best practices per service

### Azure SQL
- **Elastic Pools** if > 3 databases with variable load: 30–50 % savings.
- **Active Geo-Replication** (read) or **Failover Groups** (automatic failover) for HA.
- Alerts on `DTU percentage > 80 %` or `CPU percent > 85 %`.
- Always connect through Managed Identity (no SQL password in config):
  ```csharp
  // EF Core + Azure Identity
  services.AddDbContext<AppDbContext>(o =>
      o.UseSqlServer(conn, sql => sql.UseAzureIdentityAuthentication()));
  ```

### Azure Key Vault
- **Never** put secrets in App Settings, reference Key Vault:
  ```
  @Microsoft.KeyVault(SecretUri=https://kv-myapp.vault.azure.net/secrets/DbPassword/)
  ```
- Access policy: RBAC (`Key Vault Secrets User`) rather than Access Policies (deprecated).
- Enable **Soft-Delete** (90 days) and **Purge Protection** on prod KVs.

### Managed Identities
- System-assigned for ephemeral resources (Functions, Container Apps).
- User-assigned for identities shared between several services.
- Role assignment:
  ```bash
  az role assignment create \
    --assignee <principal-id> \
    --role "Key Vault Secrets User" \
    --scope /subscriptions/<sub>/resourceGroups/$RG/providers/Microsoft.KeyVault/vaults/kv-myapp
  ```

### Application Insights
- **Always** enable the Connection String (not the InstrumentationKey, deprecated).
- Enable **adaptive Sampling** in prod to limit telemetry costs.
- Business custom metrics through `TelemetryClient.TrackMetric()` for functional SLAs.

---

## Cost optimization

| Lever | Estimated savings | Effort |
|---|---|---|
| 1-year Reserved Instances (App Service, AKS nodes) | 30–45 % | Low |
| 3-year Reserved Instances | 50–65 % | Low |
| Spot VMs (batch, CI workers) | 60–90 % | Medium |
| Scale-to-zero (Container Apps, Functions) | Very high (idle = 0) | None |
| Right-sizing (Azure Advisor) | 20–40 % | Medium |
| Azure Dev/Test subscription | 50–55 % on VMs | Low |

```bash
# Show Azure Advisor recommendations (cost)
az advisor recommendation list --category Cost -o table
```

---

## Guardrails / Anti-patterns / Pitfalls

- **Never store secrets in the environment variables** of App Service or Container Apps: use Key Vault Reference.
- **Do not use the Consumption tier for Functions with latency < 200 ms**: cold start of 1–3 s on Consumption; prefer Premium or Flex Consumption (2024+).
- **Avoid SQL connections with SQL auth** in production: password rotation is costly, Managed Identity is free and safer.
- **Do not expose Container Apps with `--ingress external` if the API is internal**: use `internal` + VNet communication.
- **No Shared/Free plan in prod**: no SLA, aggressive CPU throttling.
- **Do not neglect Private Endpoints**: without them, Azure SQL/Storage traffic goes over the public internet even inside a VNet.
- **Separate Log Analytics Workspace per environment** (not prod + dev in the same one): data isolation and control of ingestion costs.
- **AKS without Cluster Autoscaler = systematic overprovisioning**: always enable `--enable-cluster-autoscaler`.

---

## Production deployment checklist

- [ ] Managed Identity enabled, no plain-text secret
- [ ] Key Vault with Soft-Delete + Purge Protection
- [ ] Private Endpoints on SQL, Redis, Storage
- [ ] Application Insights connected (Connection String)
- [ ] Cost alerts + technical metrics configured
- [ ] Auto-scaling (min/max replicas or App Service scale rules)
- [ ] Staging slot for zero-downtime deployment (App Service)
- [ ] Azure Defender / Defender for Cloud enabled on critical resources
- [ ] Geo-Replication or Failover Group on Azure SQL if SLA > 99.9 %
