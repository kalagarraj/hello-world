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

# Globally unique names (registry, key vault) need a stable suffix that is not
# derived from anything a caller might change.
resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
  numeric = true
}

locals {
  base           = "${var.name_prefix}-${var.environment}"
  compact_base   = replace(local.base, "-", "")
  suffix         = random_string.suffix.result
  registry_name  = substr("${local.compact_base}acr${local.suffix}", 0, 50)
  key_vault_name = substr("${local.compact_base}kv${local.suffix}", 0, 24)
}

resource "azurerm_resource_group" "this" {
  name     = "rg-${local.base}"
  location = var.location
  tags     = var.tags
}

# ---------------------------------------------------------------------------
# Networking (optional: required for internal-only Container Apps ingress)
# ---------------------------------------------------------------------------

resource "azurerm_virtual_network" "this" {
  count = var.enable_vnet ? 1 : 0

  name                = "vnet-${local.base}"
  resource_group_name = azurerm_resource_group.this.name
  location            = azurerm_resource_group.this.location
  address_space       = [var.vnet_address_space]
  tags                = var.tags
}

# Container Apps requires a dedicated, delegated subnet of at least /23 for
# workload profile environments.
resource "azurerm_subnet" "container_apps" {
  count = var.enable_vnet ? 1 : 0

  name                 = "snet-container-apps"
  resource_group_name  = azurerm_resource_group.this.name
  virtual_network_name = azurerm_virtual_network.this[0].name
  address_prefixes     = [var.container_apps_subnet_prefix]

  delegation {
    name = "container-apps"
    service_delegation {
      name = "Microsoft.App/environments"
      actions = [
        "Microsoft.Network/virtualNetworks/subnets/join/action",
      ]
    }
  }
}

# ---------------------------------------------------------------------------
# Shared logging workspace: Container Apps console/system logs, Cosmos
# diagnostics, and the Grafana Azure Monitor data source all point here.
# ---------------------------------------------------------------------------

resource "azurerm_log_analytics_workspace" "this" {
  name                = "log-${local.base}"
  resource_group_name = azurerm_resource_group.this.name
  location            = azurerm_resource_group.this.location
  sku                 = "PerGB2018"
  retention_in_days   = var.log_retention_days
  tags                = var.tags
}

# ---------------------------------------------------------------------------
# Container registry
# ---------------------------------------------------------------------------

resource "azurerm_container_registry" "this" {
  name                = local.registry_name
  resource_group_name = azurerm_resource_group.this.name
  location            = azurerm_resource_group.this.location
  sku                 = var.registry_sku
  admin_enabled       = false
  tags                = var.tags
}

# ---------------------------------------------------------------------------
# Workload identity shared by every app: pulls images, reads secrets, and
# talks to Cosmos without a single password in the configuration.
# ---------------------------------------------------------------------------

resource "azurerm_user_assigned_identity" "apps" {
  name                = "id-${local.base}-apps"
  resource_group_name = azurerm_resource_group.this.name
  location            = azurerm_resource_group.this.location
  tags                = var.tags
}

resource "azurerm_role_assignment" "acr_pull" {
  scope                = azurerm_container_registry.this.id
  role_definition_name = "AcrPull"
  principal_id         = azurerm_user_assigned_identity.apps.principal_id
}

# ---------------------------------------------------------------------------
# Key Vault: holds the credentials that genuinely cannot be replaced by
# managed identity, notably the Snowflake service-user secret.
# ---------------------------------------------------------------------------

data "azurerm_client_config" "current" {}

resource "azurerm_key_vault" "this" {
  name                       = local.key_vault_name
  resource_group_name        = azurerm_resource_group.this.name
  location                   = azurerm_resource_group.this.location
  tenant_id                  = data.azurerm_client_config.current.tenant_id
  sku_name                   = "standard"
  rbac_authorization_enabled = true
  purge_protection_enabled   = var.key_vault_purge_protection
  soft_delete_retention_days = 7
  tags                       = var.tags
}

resource "azurerm_role_assignment" "kv_apps_reader" {
  scope                = azurerm_key_vault.this.id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = azurerm_user_assigned_identity.apps.principal_id
}

# Lets whoever runs `terraform apply` write the secrets below.
resource "azurerm_role_assignment" "kv_deployer" {
  count = var.grant_deployer_key_vault_access ? 1 : 0

  scope                = azurerm_key_vault.this.id
  role_definition_name = "Key Vault Secrets Officer"
  principal_id         = data.azurerm_client_config.current.object_id
}

# ---------------------------------------------------------------------------
# Container Apps environment
# ---------------------------------------------------------------------------

resource "azurerm_container_app_environment" "this" {
  name                       = "cae-${local.base}"
  resource_group_name        = azurerm_resource_group.this.name
  location                   = azurerm_resource_group.this.location
  log_analytics_workspace_id = azurerm_log_analytics_workspace.this.id
  infrastructure_subnet_id   = var.enable_vnet ? azurerm_subnet.container_apps[0].id : null
  zone_redundancy_enabled    = var.enable_vnet ? var.zone_redundant : false
  tags                       = var.tags
}
