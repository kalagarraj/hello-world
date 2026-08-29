variable "base_name" {
  description = "prefix-environment string used to build the account name."
  type        = string
}

variable "resource_group_name" {
  description = "Resource group the account is created in."
  type        = string
}

variable "location" {
  description = "Primary Azure region."
  type        = string
}

variable "tags" {
  description = "Tags applied to the account."
  type        = map(string)
  default     = {}
}

variable "capacity_mode" {
  description = "provisioned or serverless. Serverless suits dev and spiky workloads; it disallows throughput settings."
  type        = string
  default     = "serverless"

  validation {
    condition     = contains(["provisioned", "serverless"], var.capacity_mode)
    error_message = "capacity_mode must be provisioned or serverless."
  }
}

variable "consistency_level" {
  description = "Cosmos consistency level."
  type        = string
  default     = "Session"

  validation {
    condition = contains(
      ["Eventual", "ConsistentPrefix", "Session", "BoundedStaleness", "Strong"],
      var.consistency_level
    )
    error_message = "Invalid Cosmos consistency level."
  }
}

variable "max_interval_in_seconds" {
  description = "Bounded staleness lag in seconds. Used only with BoundedStaleness."
  type        = number
  default     = 300
}

variable "max_staleness_prefix" {
  description = "Bounded staleness lag in operations. Used only with BoundedStaleness."
  type        = number
  default     = 100000
}

variable "geo_locations" {
  description = "Regions the account is replicated to. failover_priority 0 is the write region."
  type = list(object({
    location          = string
    failover_priority = number
    zone_redundant    = optional(bool, false)
  }))
}

variable "multi_region_writes" {
  description = "Enable multi-region writes. Doubles write cost; only useful with more than one region."
  type        = bool
  default     = false
}

variable "free_tier_enabled" {
  description = "Use the free tier. One account per subscription, and it cannot be toggled after creation."
  type        = bool
  default     = false
}

variable "disable_key_auth" {
  description = "Reject account-key authentication so only Entra ID identities can reach the data plane."
  type        = bool
  default     = false
}

variable "public_network_access_enabled" {
  description = "Allow public network access to the account."
  type        = bool
  default     = true
}

variable "analytical_storage_enabled" {
  description = "Enable the analytical store (the column store behind Synapse Link mirroring)."
  type        = bool
  default     = false
}

variable "backup" {
  description = "Backup policy for the account."
  type = object({
    type                = optional(string, "Continuous")
    tier                = optional(string, "Continuous7Days")
    interval_in_minutes = optional(number, 240)
    retention_in_hours  = optional(number, 8)
    storage_redundancy  = optional(string, "Local")
  })
  default = {}
}

variable "database_name" {
  description = "SQL database name."
  type        = string
}

variable "database_throughput" {
  description = "Manual shared RU/s for the database. Ignored when serverless or when autoscale is set."
  type        = number
  default     = null
}

variable "database_autoscale_max_throughput" {
  description = "Autoscale maximum shared RU/s for the database. Ignored when serverless."
  type        = number
  default     = null
}

variable "containers" {
  description = "SQL containers to create, keyed by container name."
  type = map(object({
    partition_key_paths      = list(string)
    default_ttl              = optional(number)
    throughput               = optional(number)
    autoscale_max_throughput = optional(number)
    analytical_storage_ttl   = optional(number)
    unique_key_paths         = optional(list(list(string)), [])
  }))
  default = {}
}

variable "data_plane_principal_ids" {
  description = "Principal ids granted the built-in Cosmos data contributor role."
  type        = list(string)
  default     = []
}

variable "log_analytics_workspace_id" {
  description = "Workspace diagnostics are sent to. Null disables diagnostic settings."
  type        = string
  default     = null
}

variable "diagnostic_log_categories" {
  description = "Cosmos diagnostic log categories to forward."
  type        = list(string)
  default = [
    "DataPlaneRequests",
    "QueryRuntimeStatistics",
    "PartitionKeyStatistics",
    "ControlPlaneRequests",
  ]
}
