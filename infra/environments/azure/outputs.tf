output "resource_group_name" {
  description = "Resource group holding the environment."
  value       = module.foundation.resource_group_name
}

output "container_registry_login_server" {
  description = "Registry CI pushes app images to."
  value       = module.foundation.container_registry_login_server
}

output "app_urls" {
  description = "Ingress URLs per app."
  value       = { for name, app in module.apps : name => app.url if app.url != null }
}

output "app_identity_client_id" {
  description = "Client id apps use with DefaultAzureCredential."
  value       = module.foundation.app_identity_client_id
}

output "key_vault_uri" {
  description = "Key Vault URI."
  value       = module.foundation.key_vault_uri
}

output "cosmos_endpoint" {
  description = "Cosmos account endpoint."
  value       = module.cosmos.endpoint
}

output "cosmos_database" {
  description = "Cosmos database name."
  value       = module.cosmos.database_name
}

output "cosmos_containers" {
  description = "Cosmos containers created in the database."
  value       = module.cosmos.container_names
}

output "grafana_url" {
  description = "Azure Managed Grafana endpoint."
  value       = module.observability.grafana_url
}

output "prometheus_query_endpoint" {
  description = "Managed Prometheus query endpoint."
  value       = module.observability.prometheus_query_endpoint
}

output "log_analytics_workspace_id" {
  description = "Workspace backing Application Insights and the Grafana logs data source."
  value       = module.foundation.log_analytics_workspace_id
}

output "application_insights_connection_string" {
  description = "Application Insights connection string."
  value       = module.observability.application_insights_connection_string
  sensitive   = true
}
