terraform {
  required_version = ">= 1.6"
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = ">= 4.81"
    }
    random = {
      source  = "hashicorp/random"
      version = ">= 3.5"
    }
  }
}

resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
  numeric = true
}

locals {
  account_name = substr("cosmos-${var.base_name}-${random_string.suffix.result}", 0, 44)

  # Serverless accounts reject any throughput setting; provisioned accounts need
  # exactly one of manual throughput or autoscale.
  serverless = var.capacity_mode == "serverless"
}

resource "azurerm_cosmosdb_account" "this" {
  name                = local.account_name
  resource_group_name = var.resource_group_name
  location            = var.location
  offer_type          = "Standard"
  kind                = "GlobalDocumentDB"

  free_tier_enabled                = var.free_tier_enabled
  automatic_failover_enabled       = length(var.geo_locations) > 1
  multiple_write_locations_enabled = var.multi_region_writes
  local_authentication_disabled    = var.disable_key_auth
  public_network_access_enabled    = var.public_network_access_enabled
  analytical_storage_enabled       = var.analytical_storage_enabled

  consistency_policy {
    consistency_level       = var.consistency_level
    max_interval_in_seconds = var.consistency_level == "BoundedStaleness" ? var.max_interval_in_seconds : null
    max_staleness_prefix    = var.consistency_level == "BoundedStaleness" ? var.max_staleness_prefix : null
  }

  dynamic "geo_location" {
    for_each = var.geo_locations
    content {
      location          = geo_location.value.location
      failover_priority = geo_location.value.failover_priority
      zone_redundant    = geo_location.value.zone_redundant
    }
  }

  dynamic "capabilities" {
    for_each = local.serverless ? ["EnableServerless"] : []
    content {
      name = capabilities.value
    }
  }

  backup {
    type                = var.backup.type
    interval_in_minutes = var.backup.type == "Periodic" ? var.backup.interval_in_minutes : null
    retention_in_hours  = var.backup.type == "Periodic" ? var.backup.retention_in_hours : null
    storage_redundancy  = var.backup.type == "Periodic" ? var.backup.storage_redundancy : null
    tier                = var.backup.type == "Continuous" ? var.backup.tier : null
  }

  tags = var.tags
}

resource "azurerm_cosmosdb_sql_database" "this" {
  name                = var.database_name
  resource_group_name = var.resource_group_name
  account_name        = azurerm_cosmosdb_account.this.name

  # Database-level throughput is shared by every container that does not set
  # its own. Serverless accounts must leave both unset.
  throughput = local.serverless || var.database_autoscale_max_throughput != null ? null : var.database_throughput

  dynamic "autoscale_settings" {
    for_each = !local.serverless && var.database_autoscale_max_throughput != null ? [1] : []
    content {
      max_throughput = var.database_autoscale_max_throughput
    }
  }
}

resource "azurerm_cosmosdb_sql_container" "this" {
  for_each = var.containers

  name                   = each.key
  resource_group_name    = var.resource_group_name
  account_name           = azurerm_cosmosdb_account.this.name
  database_name          = azurerm_cosmosdb_sql_database.this.name
  partition_key_paths    = each.value.partition_key_paths
  partition_key_version  = 2
  default_ttl            = each.value.default_ttl
  analytical_storage_ttl = var.analytical_storage_enabled ? each.value.analytical_storage_ttl : null

  throughput = local.serverless || each.value.autoscale_max_throughput != null ? null : each.value.throughput

  dynamic "autoscale_settings" {
    for_each = !local.serverless && each.value.autoscale_max_throughput != null ? [1] : []
    content {
      max_throughput = each.value.autoscale_max_throughput
    }
  }

  dynamic "unique_key" {
    for_each = each.value.unique_key_paths
    content {
      paths = unique_key.value
    }
  }
}

# ---------------------------------------------------------------------------
# Data-plane access for the app identity. This is what lets the apps read and
# write documents with a managed identity instead of an account key.
# ---------------------------------------------------------------------------

data "azurerm_cosmosdb_sql_role_definition" "data_contributor" {
  resource_group_name = var.resource_group_name
  account_name        = azurerm_cosmosdb_account.this.name
  # Built-in "Cosmos DB Built-in Data Contributor".
  role_definition_id = "00000000-0000-0000-0000-000000000002"
}

resource "azurerm_cosmosdb_sql_role_assignment" "apps" {
  for_each = toset(var.data_plane_principal_ids)

  resource_group_name = var.resource_group_name
  account_name        = azurerm_cosmosdb_account.this.name
  role_definition_id  = data.azurerm_cosmosdb_sql_role_definition.data_contributor.id
  principal_id        = each.value
  scope               = azurerm_cosmosdb_account.this.id
}

# ---------------------------------------------------------------------------
# Diagnostics -> Log Analytics, so Grafana can chart request charges, latency,
# and throttled (429) requests next to the app metrics.
# ---------------------------------------------------------------------------

resource "azurerm_monitor_diagnostic_setting" "this" {
  count = var.log_analytics_workspace_id == null ? 0 : 1

  name                       = "diag-to-law"
  target_resource_id         = azurerm_cosmosdb_account.this.id
  log_analytics_workspace_id = var.log_analytics_workspace_id

  dynamic "enabled_log" {
    for_each = var.diagnostic_log_categories
    content {
      category = enabled_log.value
    }
  }

  enabled_metric {
    category = "Requests"
  }
}
