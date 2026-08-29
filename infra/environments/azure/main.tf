# ---------------------------------------------------------------------------
# Azure environment.
#
# Container Apps for the workloads, Cosmos DB for operational data, Azure
# Managed Grafana over Azure Monitor for observability, and Key Vault holding
# the one credential managed identity cannot replace: the Snowflake key.
#
# Snowflake objects themselves live in environments/snowflake, which has a
# different provider and credential lifecycle. This root consumes the
# connection details it produces.
# ---------------------------------------------------------------------------

locals {
  tags = merge(
    {
      application = var.name_prefix
      environment = var.environment
      managed_by  = "terraform"
    },
    var.tags,
  )

  # Every app gets the App Insights connection string and the Azure Monitor
  # OpenTelemetry knobs, matching what the local collector provides.
  common_app_env = {
    APPLICATIONINSIGHTS_CONNECTION_STRING = module.observability.application_insights_connection_string
    OTEL_TRACES_EXPORTER                  = "azuremonitor"
    OTEL_METRICS_EXPORTER                 = "azuremonitor"
    OTEL_LOGS_EXPORTER                    = "azuremonitor"
  }

  snowflake_env = var.snowflake_connection == null ? {} : {
    SNOWFLAKE_ACCOUNT   = var.snowflake_connection.account
    SNOWFLAKE_USER      = var.snowflake_connection.user
    SNOWFLAKE_ROLE      = var.snowflake_connection.role
    SNOWFLAKE_WAREHOUSE = var.snowflake_connection.warehouse
    SNOWFLAKE_DATABASE  = var.snowflake_connection.database
    SNOWFLAKE_SCHEMA    = var.snowflake_connection.schema
  }

  # Apps that declare uses_snowflake also get the private key mounted from Key
  # Vault, under the secret name the module turns into SNOWFLAKE_PRIVATE_KEY.
  snowflake_secret_ref = var.snowflake_private_key == null ? {} : {
    "snowflake-private-key" = azurerm_key_vault_secret.snowflake_private_key[0].versionless_id
  }
}

module "foundation" {
  source = "../../modules/azure/foundation"

  name_prefix                     = var.name_prefix
  environment                     = var.environment
  location                        = var.location
  tags                            = local.tags
  registry_sku                    = var.registry_sku
  log_retention_days              = var.log_retention_days
  enable_vnet                     = var.enable_vnet
  vnet_address_space              = var.vnet_address_space
  container_apps_subnet_prefix    = var.container_apps_subnet_prefix
  zone_redundant                  = var.zone_redundant
  key_vault_purge_protection      = var.key_vault_purge_protection
  grant_deployer_key_vault_access = var.grant_deployer_key_vault_access
}

module "cosmos" {
  source = "../../modules/azure/cosmos"

  base_name           = module.foundation.base_name
  resource_group_name = module.foundation.resource_group_name
  location            = module.foundation.location
  tags                = local.tags

  capacity_mode                     = var.cosmos.capacity_mode
  consistency_level                 = var.cosmos.consistency_level
  free_tier_enabled                 = var.cosmos.free_tier_enabled
  multi_region_writes               = var.cosmos.multi_region_writes
  disable_key_auth                  = var.cosmos.disable_key_auth
  public_network_access_enabled     = var.cosmos.public_network_access_enabled
  analytical_storage_enabled        = var.cosmos.analytical_storage_enabled
  database_name                     = var.cosmos.database_name
  database_throughput               = var.cosmos.database_throughput
  database_autoscale_max_throughput = var.cosmos.database_autoscale_max_throughput
  containers                        = var.cosmos.containers
  backup                            = var.cosmos.backup

  geo_locations = length(var.cosmos.geo_locations) > 0 ? var.cosmos.geo_locations : [
    {
      location          = var.location
      failover_priority = 0
      zone_redundant    = var.zone_redundant
    }
  ]

  data_plane_principal_ids   = [module.foundation.app_identity_principal_id]
  log_analytics_workspace_id = module.foundation.log_analytics_workspace_id
}

module "observability" {
  source = "../../modules/azure/observability"

  base_name                  = module.foundation.base_name
  resource_group_name        = module.foundation.resource_group_name
  resource_group_id          = module.foundation.resource_group_id
  location                   = module.foundation.location
  log_analytics_workspace_id = module.foundation.log_analytics_workspace_id
  tags                       = local.tags

  retention_days               = var.observability.retention_days
  sampling_percentage          = var.observability.sampling_percentage
  enable_grafana               = var.observability.enable_grafana
  enable_managed_prometheus    = var.observability.enable_managed_prometheus
  grafana_sku                  = var.observability.grafana_sku
  grafana_major_version        = var.observability.grafana_major_version
  grafana_zone_redundant       = var.observability.grafana_zone_redundant
  grafana_api_key_enabled      = var.observability.grafana_api_key_enabled
  grafana_admin_principal_ids  = var.observability.grafana_admin_principal_ids
  grafana_viewer_principal_ids = var.observability.grafana_viewer_principal_ids
  alert_email_receivers        = var.observability.alert_email_receivers

  # Alert scopes are resolved here because only the root module knows the ids.
  metric_alerts = {
    for name, alert in var.metric_alerts : name => merge(alert, {
      scopes = alert.target == "cosmos" ? [module.cosmos.account_id] : [module.foundation.resource_group_id]
    })
  }
}

# ---------------------------------------------------------------------------
# Snowflake credential. The private key is the only long-lived secret in the
# stack; apps read it from Key Vault with their managed identity.
# ---------------------------------------------------------------------------

resource "azurerm_key_vault_secret" "snowflake_private_key" {
  count = var.snowflake_private_key == null ? 0 : 1

  name         = "snowflake-private-key"
  value        = var.snowflake_private_key
  key_vault_id = module.foundation.key_vault_id
  content_type = "application/x-pem-file"
  tags         = local.tags

  depends_on = [module.foundation]
}

# ---------------------------------------------------------------------------
# Apps
# ---------------------------------------------------------------------------

module "apps" {
  source   = "../../modules/azure/container-app"
  for_each = var.apps

  name        = each.key
  base_name   = module.foundation.base_name
  environment = var.environment
  tags        = local.tags

  resource_group_name          = module.foundation.resource_group_name
  container_app_environment_id = module.foundation.container_app_environment_id
  registry_login_server        = module.foundation.container_registry_login_server
  identity_id                  = module.foundation.app_identity_id
  identity_client_id           = module.foundation.app_identity_client_id

  spec = merge(each.value, {
    key_vault_secrets = merge(
      each.value.key_vault_secrets,
      each.value.uses_snowflake ? local.snowflake_secret_ref : {},
    )
  })

  extra_env     = local.common_app_env
  cosmos_env    = module.cosmos.app_env
  snowflake_env = local.snowflake_env

  # Apps resolve Key Vault references and pull images at revision start, so the
  # identity's role assignments have to exist before the first revision does.
  # Neither is an implicit dependency of the container app resource.
  depends_on = [module.foundation]
}
