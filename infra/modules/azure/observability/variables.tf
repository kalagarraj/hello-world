variable "base_name" {
  description = "prefix-environment string used to build resource names."
  type        = string
}

variable "resource_group_name" {
  description = "Resource group the observability resources are created in."
  type        = string
}

variable "resource_group_id" {
  description = "Resource group id, used as the scope of Grafana's Monitoring Reader role."
  type        = string
}

variable "location" {
  description = "Azure region."
  type        = string
}

variable "log_analytics_workspace_id" {
  description = "Workspace backing Application Insights and the Grafana logs data source."
  type        = string
}

variable "tags" {
  description = "Tags applied to every resource."
  type        = map(string)
  default     = {}
}

variable "retention_days" {
  description = "Application Insights retention in days."
  type        = number
  default     = 90
}

variable "sampling_percentage" {
  description = "Application Insights ingestion sampling percentage."
  type        = number
  default     = 100
}

variable "enable_managed_prometheus" {
  description = "Create an Azure Monitor workspace (managed Prometheus) and wire it into Grafana."
  type        = bool
  default     = true
}

variable "enable_grafana" {
  description = "Create an Azure Managed Grafana instance. Turn off to save cost in throwaway environments."
  type        = bool
  default     = true
}

variable "grafana_sku" {
  description = "Managed Grafana SKU."
  type        = string
  default     = "Standard"

  validation {
    condition     = contains(["Essential", "Standard"], var.grafana_sku)
    error_message = "grafana_sku must be Essential or Standard."
  }
}

variable "grafana_major_version" {
  description = "Managed Grafana major version."
  type        = string
  default     = "11"
}

variable "grafana_zone_redundant" {
  description = "Run Managed Grafana zone-redundantly. Standard SKU only, and it cannot be changed later."
  type        = bool
  default     = false
}

variable "grafana_api_key_enabled" {
  description = "Allow API keys, needed to push dashboards from CI."
  type        = bool
  default     = true
}

variable "grafana_admin_principal_ids" {
  description = "Entra ID principals granted the Grafana Admin role."
  type        = list(string)
  default     = []
}

variable "grafana_viewer_principal_ids" {
  description = "Entra ID principals granted the Grafana Viewer role."
  type        = list(string)
  default     = []
}

variable "alert_email_receivers" {
  description = "Email addresses notified by alerts, keyed by receiver name."
  type        = map(string)
  default     = {}
}

variable "metric_alerts" {
  description = "Metric alerts to create, keyed by alert name."
  type = map(object({
    description      = string
    scopes           = list(string)
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
