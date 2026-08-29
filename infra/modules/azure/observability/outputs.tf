output "application_insights_id" {
  description = "Application Insights resource id."
  value       = azurerm_application_insights.this.id
}

output "application_insights_connection_string" {
  description = "Connection string apps use with the Azure Monitor OpenTelemetry exporter."
  value       = azurerm_application_insights.this.connection_string
  sensitive   = true
}

output "application_insights_instrumentation_key" {
  description = "Instrumentation key, for SDKs that predate connection strings."
  value       = azurerm_application_insights.this.instrumentation_key
  sensitive   = true
}

output "monitor_workspace_id" {
  description = "Azure Monitor (managed Prometheus) workspace id, or null when disabled."
  value       = try(azurerm_monitor_workspace.this[0].id, null)
}

output "prometheus_query_endpoint" {
  description = "Managed Prometheus query endpoint, or null when disabled."
  value       = try(azurerm_monitor_workspace.this[0].query_endpoint, null)
}

output "grafana_url" {
  description = "Azure Managed Grafana endpoint, or null when disabled."
  value       = try(azurerm_dashboard_grafana.this[0].endpoint, null)
}

output "grafana_id" {
  description = "Azure Managed Grafana resource id, or null when disabled."
  value       = try(azurerm_dashboard_grafana.this[0].id, null)
}

output "grafana_principal_id" {
  description = "Managed identity principal id of the Grafana instance, or null when disabled."
  value       = try(azurerm_dashboard_grafana.this[0].identity[0].principal_id, null)
}

output "action_group_id" {
  description = "Action group id used by the alerts, or null when no receivers are configured."
  value       = try(azurerm_monitor_action_group.this[0].id, null)
}
