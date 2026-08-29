terraform {
  required_version = ">= 1.6"
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = ">= 4.81"
    }
  }
}

locals {
  grafana_name = substr("graf-${var.base_name}", 0, 23)
}

# ---------------------------------------------------------------------------
# Application Insights: distributed traces, request rates, and dependency
# telemetry. Apps reach it with the OTLP-compatible Azure Monitor exporter.
# ---------------------------------------------------------------------------

resource "azurerm_application_insights" "this" {
  name                = "appi-${var.base_name}"
  resource_group_name = var.resource_group_name
  location            = var.location
  workspace_id        = var.log_analytics_workspace_id
  application_type    = "web"
  retention_in_days   = var.retention_days
  sampling_percentage = var.sampling_percentage
  tags                = var.tags
}

# ---------------------------------------------------------------------------
# Azure Monitor workspace: the managed Prometheus store. Apps and the
# collector remote-write here; Grafana queries it as a Prometheus data source.
# ---------------------------------------------------------------------------

resource "azurerm_monitor_workspace" "this" {
  count = var.enable_managed_prometheus ? 1 : 0

  name                = "amw-${var.base_name}"
  resource_group_name = var.resource_group_name
  location            = var.location
  tags                = var.tags
}

# ---------------------------------------------------------------------------
# Azure Managed Grafana: the same dashboards as the local stack, backed by
# Azure Monitor instead of the local Prometheus/Loki/Tempo containers.
# ---------------------------------------------------------------------------

resource "azurerm_dashboard_grafana" "this" {
  count = var.enable_grafana ? 1 : 0

  name                              = local.grafana_name
  resource_group_name               = var.resource_group_name
  location                          = var.location
  grafana_major_version             = var.grafana_major_version
  sku                               = var.grafana_sku
  api_key_enabled                   = var.grafana_api_key_enabled
  deterministic_outbound_ip_enabled = false
  public_network_access_enabled     = true
  zone_redundancy_enabled           = var.grafana_zone_redundant
  tags                              = var.tags

  identity {
    type = "SystemAssigned"
  }

  dynamic "azure_monitor_workspace_integrations" {
    for_each = azurerm_monitor_workspace.this
    content {
      resource_id = azure_monitor_workspace_integrations.value.id
    }
  }
}

# Grafana reads metrics and logs across the whole resource group: without this
# every data source in the workspace returns an authorization error.
resource "azurerm_role_assignment" "grafana_monitoring_reader" {
  count = var.enable_grafana ? 1 : 0

  scope                = var.resource_group_id
  role_definition_name = "Monitoring Reader"
  principal_id         = azurerm_dashboard_grafana.this[0].identity[0].principal_id
}

resource "azurerm_role_assignment" "grafana_log_analytics_reader" {
  count = var.enable_grafana ? 1 : 0

  scope                = var.log_analytics_workspace_id
  role_definition_name = "Log Analytics Reader"
  principal_id         = azurerm_dashboard_grafana.this[0].identity[0].principal_id
}

resource "azurerm_role_assignment" "grafana_prometheus_reader" {
  count = var.enable_grafana && var.enable_managed_prometheus ? 1 : 0

  scope                = azurerm_monitor_workspace.this[0].id
  role_definition_name = "Monitoring Data Reader"
  principal_id         = azurerm_dashboard_grafana.this[0].identity[0].principal_id
}

# Humans who need to build dashboards in the portal.
resource "azurerm_role_assignment" "grafana_admins" {
  for_each = var.enable_grafana ? toset(var.grafana_admin_principal_ids) : toset([])

  scope                = azurerm_dashboard_grafana.this[0].id
  role_definition_name = "Grafana Admin"
  principal_id         = each.value
}

resource "azurerm_role_assignment" "grafana_viewers" {
  for_each = var.enable_grafana ? toset(var.grafana_viewer_principal_ids) : toset([])

  scope                = azurerm_dashboard_grafana.this[0].id
  role_definition_name = "Grafana Viewer"
  principal_id         = each.value
}

# ---------------------------------------------------------------------------
# Alerting
# ---------------------------------------------------------------------------

resource "azurerm_monitor_action_group" "this" {
  count = length(var.alert_email_receivers) > 0 ? 1 : 0

  name                = "ag-${var.base_name}"
  resource_group_name = var.resource_group_name
  short_name          = substr(replace(var.base_name, "-", ""), 0, 12)
  tags                = var.tags

  dynamic "email_receiver" {
    for_each = var.alert_email_receivers
    content {
      name                    = email_receiver.key
      email_address           = email_receiver.value
      use_common_alert_schema = true
    }
  }
}

resource "azurerm_monitor_metric_alert" "this" {
  for_each = var.metric_alerts

  name                = "alert-${var.base_name}-${each.key}"
  resource_group_name = var.resource_group_name
  scopes              = each.value.scopes
  description         = each.value.description
  severity            = each.value.severity
  frequency           = each.value.frequency
  window_size         = each.value.window_size
  auto_mitigate       = true
  tags                = var.tags

  criteria {
    metric_namespace = each.value.metric_namespace
    metric_name      = each.value.metric_name
    aggregation      = each.value.aggregation
    operator         = each.value.operator
    threshold        = each.value.threshold

    dynamic "dimension" {
      for_each = each.value.dimensions
      content {
        name     = dimension.value.name
        operator = dimension.value.operator
        values   = dimension.value.values
      }
    }
  }

  dynamic "action" {
    for_each = azurerm_monitor_action_group.this
    content {
      action_group_id = action.value.id
    }
  }
}
