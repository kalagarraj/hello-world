variable "subscription_id" {
  description = "Target Azure subscription id. Can also be supplied as ARM_SUBSCRIPTION_ID."
  type        = string
  default     = null
}

variable "name_prefix" {
  description = "Short prefix for every resource name."
  type        = string
  default     = "helloworld"
}

variable "environment" {
  description = "Environment name, e.g. dev, stg, prod."
  type        = string
}

variable "location" {
  description = "Primary Azure region."
  type        = string
  default     = "westeurope"
}

variable "tags" {
  description = "Extra tags merged into the defaults applied to every resource."
  type        = map(string)
  default     = {}
}

# ---------------------------------------------------------------------------
# Foundation
# ---------------------------------------------------------------------------

variable "registry_sku" {
  description = "Container registry SKU."
  type        = string
  default     = "Basic"
}

variable "log_retention_days" {
  description = "Log Analytics retention in days."
  type        = number
  default     = 30
}

variable "enable_vnet" {
  description = "Run Container Apps inside a customer-managed VNet."
  type        = bool
  default     = false
}

variable "vnet_address_space" {
  description = "VNet address space when enable_vnet is true."
  type        = string
  default     = "10.20.0.0/16"
}

variable "container_apps_subnet_prefix" {
  description = "Subnet delegated to Container Apps. Must be /23 or larger."
  type        = string
  default     = "10.20.0.0/23"
}

variable "zone_redundant" {
  description = "Enable zone redundancy where the resource supports it. Requires enable_vnet for Container Apps."
  type        = bool
  default     = false
}

variable "key_vault_purge_protection" {
  description = "Enable Key Vault purge protection. Irreversible once on."
  type        = bool
  default     = false
}

variable "grant_deployer_key_vault_access" {
  description = "Give the Terraform principal the Key Vault Secrets Officer role so it can write secrets."
  type        = bool
  default     = true
}

# ---------------------------------------------------------------------------
# Apps
#
# Shares the schema used by environments/local, plus the fields that only apply
# to Container Apps (scaling, ingress, Key Vault references).
# ---------------------------------------------------------------------------

variable "apps" {
  description = "Apps to deploy, keyed by app name."
  type = map(object({
    image                 = string
    tag                   = optional(string, "latest")
    port                  = optional(number, 8080)
    cpu                   = optional(number, 0.5)
    memory                = optional(string, "1Gi")
    min_replicas          = optional(number, 0)
    max_replicas          = optional(number, 3)
    ingress_enabled       = optional(bool, true)
    external_ingress      = optional(bool, false)
    concurrent_requests   = optional(number, 50)
    revision_mode         = optional(string, "Single")
    workload_profile_name = optional(string)
    entrypoint            = optional(list(string))
    command               = optional(list(string))
    env                   = optional(map(string), {})
    key_vault_secrets     = optional(map(string), {})
    uses_cosmos           = optional(bool, false)
    uses_snowflake        = optional(bool, false)
    health_path           = optional(string)
  }))
}

# ---------------------------------------------------------------------------
# Cosmos DB
# ---------------------------------------------------------------------------

variable "cosmos" {
  description = "Cosmos DB account, database, and container configuration."
  type = object({
    database_name                     = optional(string, "appdb")
    capacity_mode                     = optional(string, "serverless")
    consistency_level                 = optional(string, "Session")
    free_tier_enabled                 = optional(bool, false)
    multi_region_writes               = optional(bool, false)
    disable_key_auth                  = optional(bool, false)
    public_network_access_enabled     = optional(bool, true)
    analytical_storage_enabled        = optional(bool, false)
    database_throughput               = optional(number)
    database_autoscale_max_throughput = optional(number)

    geo_locations = optional(list(object({
      location          = string
      failover_priority = number
      zone_redundant    = optional(bool, false)
    })), [])

    backup = optional(object({
      type                = optional(string, "Continuous")
      tier                = optional(string, "Continuous7Days")
      interval_in_minutes = optional(number, 240)
      retention_in_hours  = optional(number, 8)
      storage_redundancy  = optional(string, "Local")
    }), {})

    containers = optional(map(object({
      partition_key_paths      = list(string)
      default_ttl              = optional(number)
      throughput               = optional(number)
      autoscale_max_throughput = optional(number)
      analytical_storage_ttl   = optional(number)
      unique_key_paths         = optional(list(list(string)), [])
    })), {})
  })
  default = {}
}

# ---------------------------------------------------------------------------
# Observability
# ---------------------------------------------------------------------------

variable "observability" {
  description = "Application Insights, Azure Monitor, and Managed Grafana configuration."
  type = object({
    retention_days               = optional(number, 90)
    sampling_percentage          = optional(number, 100)
    enable_grafana               = optional(bool, true)
    enable_managed_prometheus    = optional(bool, true)
    grafana_sku                  = optional(string, "Standard")
    grafana_major_version        = optional(string, "11")
    grafana_zone_redundant       = optional(bool, false)
    grafana_api_key_enabled      = optional(bool, true)
    grafana_admin_principal_ids  = optional(list(string), [])
    grafana_viewer_principal_ids = optional(list(string), [])
    alert_email_receivers        = optional(map(string), {})
  })
  default = {}
}

variable "metric_alerts" {
  description = <<-EOT
    Metric alerts, keyed by alert name. `target` selects the scope: "cosmos"
    for the Cosmos account, anything else for the resource group.
  EOT
  type = map(object({
    description      = string
    target           = optional(string, "resource_group")
    metric_namespace = string
    metric_name      = string
    aggregation      = string
    operator         = string
    threshold        = number
    severity         = optional(number, 2)
    frequency        = optional(string, "PT5M")
    window_size      = optional(string, "PT15M")
    dimensions = optional(list(object({
      name     = string
      operator = string
      values   = list(string)
    })), [])
  }))
  default = {}
}

# ---------------------------------------------------------------------------
# Snowflake
# ---------------------------------------------------------------------------

variable "snowflake_connection" {
  description = <<-EOT
    Non-secret Snowflake connection settings, taken from the outputs of
    environments/snowflake. Null leaves Snowflake unwired.
  EOT
  type = object({
    account   = string
    user      = string
    role      = string
    warehouse = string
    database  = string
    schema    = string
  })
  default = null
}

variable "snowflake_private_key" {
  description = <<-EOT
    PEM-encoded private key for the Snowflake service user, stored in Key Vault
    and read by apps at revision start. Supply through TF_VAR_snowflake_private_key
    from a secret store, never in a .tfvars file.
  EOT
  type        = string
  default     = null
  sensitive   = true
}
