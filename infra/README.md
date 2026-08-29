# Infrastructure

Terraform for the same application stack in two places: a developer's machine
and Azure. The apps, the document database, and the observability backend all
have a local stand-in, so the wiring can be exercised before anything reaches a
subscription.

| Concern       | Local                                              | Azure                                                    |
| ------------- | -------------------------------------------------- | -------------------------------------------------------- |
| Apps          | Docker containers on a bridge network               | Azure Container Apps                                      |
| Images        | Pulled, or built from a Dockerfile in this repo     | Azure Container Registry                                  |
| Documents     | Cosmos DB emulator                                  | Cosmos DB (SQL API)                                       |
| Warehouse     | Shared Snowflake dev account (no emulator exists)   | Snowflake, wired in through Key Vault                     |
| Dashboards    | Grafana container                                   | Azure Managed Grafana                                     |
| Metrics       | Prometheus                                          | Azure Monitor workspace (managed Prometheus)              |
| Logs          | Loki                                                | Log Analytics                                             |
| Traces        | Tempo                                               | Application Insights                                      |
| Telemetry in  | OpenTelemetry Collector                             | Azure Monitor OpenTelemetry exporter                      |
| Identity      | None                                                | One user-assigned identity for registry, Key Vault, Cosmos |

## Layout

```
infra/
├── environments/
│   ├── local/        docker stack: apps, Cosmos emulator, Grafana/Prometheus/Loki/Tempo
│   ├── azure/        Container Apps, Cosmos, Managed Grafana, Key Vault  (dev.tfvars, prod.tfvars)
│   └── snowflake/    database, schemas, warehouses, roles, service users (dev.tfvars)
├── modules/
│   ├── local/        network, app, cosmos-emulator, observability
│   ├── azure/        foundation, container-app, cosmos, observability
│   └── snowflake/    database and grant model
└── shared/
    └── dashboards/   Grafana JSON used by both local Grafana and Azure Managed Grafana
```

Snowflake is a separate root module because it authenticates against Snowflake
rather than Azure, and its objects outlive any single Azure environment. Its
outputs feed the `snowflake_connection` variable of the other two roots.

## Adding an app

Apps are configuration, not code. `environments/local/terraform.tfvars` and
`environments/azure/*.tfvars` each carry an `apps` map with the same key names
and a deliberately overlapping schema:

```hcl
apps = {
  api = {
    image          = "helloworld/api"   # local: a pullable image; azure: a repo in the ACR
    tag            = "latest"
    port           = 8080
    uses_cosmos    = true
    uses_snowflake = false
    health_path    = "/healthz"
  }
}
```

Add a key in both files and both environments pick it up. No new Terraform.

Fields only meaningful in one place stay in that file: `host_port`, `build`, and
`scrape_metrics` are local; `cpu`, `memory`, `min_replicas`, `max_replicas`,
`external_ingress`, `concurrent_requests`, and `key_vault_secrets` are Azure.

### What an app receives

Both environments inject the same variable names, so application code does not
branch on where it is running:

| Variable                                       | Set when                     |
| ---------------------------------------------- | ---------------------------- |
| `APP_NAME`, `APP_ENV`, `PORT`                  | always                       |
| `OTEL_SERVICE_NAME`, `OTEL_RESOURCE_ATTRIBUTES`| always                       |
| `OTEL_EXPORTER_OTLP_ENDPOINT`                  | local (points at the collector) |
| `APPLICATIONINSIGHTS_CONNECTION_STRING`        | Azure                        |
| `AZURE_CLIENT_ID`                              | Azure (for `DefaultAzureCredential`) |
| `COSMOS_ENDPOINT`, `COSMOS_DATABASE`, `COSMOS_CONTAINERS` | `uses_cosmos = true` |
| `COSMOS_KEY`, `COSMOS_CONNECTION_STRING`       | `uses_cosmos = true`, local only |
| `COSMOS_AUTH_MODE = managed-identity`          | `uses_cosmos = true`, Azure only |
| `SNOWFLAKE_ACCOUNT`, `_USER`, `_ROLE`, `_WAREHOUSE`, `_DATABASE`, `_SCHEMA` | `uses_snowflake = true` |
| `SNOWFLAKE_PRIVATE_KEY`                        | `uses_snowflake = true`, Azure (from Key Vault) |

The Cosmos difference is the point: locally the app authenticates with the
emulator's well-known key, in Azure with a managed identity holding the built-in
Cosmos data contributor role. Read `COSMOS_AUTH_MODE` and pick the credential.

## Running the local stack

Needs Docker and roughly 4 GB of free memory for the emulator.

```bash
cd infra/environments/local
terraform init
terraform apply
```

Then:

| Service    | URL                     |
| ---------- | ----------------------- |
| web        | http://localhost:8080   |
| api        | http://localhost:8088   |
| Grafana    | http://localhost:3000   |
| Prometheus | http://localhost:9090   |
| Loki       | http://localhost:3100   |
| Tempo      | http://localhost:3200   |
| Cosmos     | https://localhost:8081  |
| OTLP       | grpc 4317 / http 4318   |

Grafana comes up with the Prometheus, Loki, and Tempo datasources wired
together (exemplars to traces, traces to logs, service graphs) and the
dashboards in `shared/dashboards` already loaded. Anonymous viewing is on by
default; the admin login is `admin`/`admin`, local-only.

The default `apps` entries are placeholder images that run out of the box, so
the stack can be verified before the real apps exist. Replace `image`, or swap
it for a `build` block:

```hcl
web = {
  image = "helloworld/web"
  tag   = "dev"
  port  = 8080
  build = { context = "../../../apps/web" }
}
```

The Cosmos emulator defaults to the `vnext-preview` image, which is faster and
runs on arm64. For the classic emulator set:

```hcl
cosmos_emulator_image       = "mcr.microsoft.com/cosmosdb/linux/azure-cosmos-emulator:latest"
cosmos_publish_direct_ports = true
```

Tear down with `terraform destroy`. Named volumes go with it, so emulator data
and Grafana's saved state do not survive.

## Deploying to Azure

Terraform needs an identity that can create resources and assign roles —
Contributor is not enough on its own, because the stack grants AcrPull, Key
Vault, Cosmos data-plane, and Grafana roles. Owner, or Contributor plus User
Access Administrator, works.

```bash
cd infra/environments/azure
cp backend.dev.hcl.example backend.dev.hcl   # fill in your state storage account
terraform init -backend-config=backend.dev.hcl
terraform plan  -var-file=dev.tfvars -out=dev.tfplan
terraform apply dev.tfplan
```

`prod.tfvars` differs where it matters: apps hold a warm floor of replicas
instead of scaling to zero, Cosmos runs provisioned with autoscale across two
regions and rejects account-key auth, the environment sits in a VNet with zone
redundancy, and Key Vault purge protection is on.

Two things are deliberately not managed here:

- **Image tags.** The container app ignores changes to `template.container.image`
  after the first apply, so a deploy pipeline can move tags without Terraform
  reverting them on the next plan.
- **State.** The `azurerm` backend is declared but left empty; supply it with
  `-backend-config`, or delete the block to use local state.

### Observability in Azure

Managed Grafana is created with a system-assigned identity and granted
Monitoring Reader on the resource group, Log Analytics Reader on the workspace,
and Monitoring Data Reader on the Azure Monitor workspace — without those three
every datasource returns an authorization error. Grant humans access by adding
their Entra object ids to `observability.grafana_admin_principal_ids`.

The dashboards in `shared/dashboards` use datasource *variables* rather than
fixed UIDs, so the same JSON imports into Managed Grafana and binds to the Azure
Monitor datasources there. Import them from the Grafana UI, or push them from CI
with the Grafana API (`grafana_api_key_enabled` is on by default).

Alerts are config-driven. Add entries to `metric_alerts` and email addresses to
`observability.alert_email_receivers`; `target = "cosmos"` scopes an alert to the
Cosmos account, anything else to the resource group.

Set `observability.enable_grafana = false` in throwaway environments — Managed
Grafana is the most expensive item in the stack by a wide margin.

## Snowflake

```bash
cd infra/environments/snowflake
export SNOWFLAKE_ORGANIZATION_NAME=myorg
export SNOWFLAKE_ACCOUNT_NAME=myaccount
export SNOWFLAKE_USER=TERRAFORM_SVC
export TF_VAR_private_key="$(cat ~/.snowflake/terraform.p8)"
terraform init
terraform apply -var-file=dev.tfvars
```

The model is a database with an `APP` schema the API writes to and an
`ANALYTICS` schema for curated views, two warehouses so an analyst's query
cannot starve the API of compute, and two roles: `HELLOWORLD_APP` (read/write on
`APP`) and `HELLOWORLD_READER` (read-only, the role Grafana queries under).
Grants cover both existing and future tables and views, so a new table does not
silently lock anyone out.

Service users authenticate with key pairs; Snowflake blocks single-factor
passwords for programmatic users. Generate a pair per user:

```bash
openssl genrsa 2048 | openssl pkcs8 -topk8 -inform PEM -out svc_api.p8 -nocrypt
openssl rsa -in svc_api.p8 -pubout -out svc_api.pub
```

Put the public key body (no `BEGIN`/`END` lines) in `service_users`, and give the
private half to Azure as `TF_VAR_snowflake_private_key`. It lands in Key Vault
and reaches the app as `SNOWFLAKE_PRIVATE_KEY`; the value never appears in a
`.tfvars` file, and Container Apps resolves the Key Vault reference at revision
start rather than through Terraform state.

To let local Grafana query Snowflake, set
`grafana_plugins = ["snowflake-datasource"]` and fill in `snowflake_connection`
in `environments/local/terraform.tfvars`.

## Verification status

The Azure root module and all four Azure modules pass `terraform validate`
against `hashicorp/azurerm` 4.81, and `dev.tfvars` and `prod.tfvars` both
typecheck against the variable schemas. They have not been applied against a
live subscription.

The local and Snowflake roots are HCL-valid but have not been run through
`terraform validate`, because the `kreuzwerker/docker` and `snowflakedb/snowflake`
providers were not reachable from the environment they were written in. Run
`terraform init && terraform validate` in each before the first apply.
