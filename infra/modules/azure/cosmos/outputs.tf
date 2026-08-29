output "account_name" {
  description = "Cosmos account name."
  value       = azurerm_cosmosdb_account.this.name
}

output "account_id" {
  description = "Cosmos account resource id."
  value       = azurerm_cosmosdb_account.this.id
}

output "endpoint" {
  description = "Cosmos account endpoint."
  value       = azurerm_cosmosdb_account.this.endpoint
}

output "database_name" {
  description = "SQL database name."
  value       = azurerm_cosmosdb_sql_database.this.name
}

output "container_names" {
  description = "Names of the created containers."
  value       = sort(keys(azurerm_cosmosdb_sql_container.this))
}

output "primary_key" {
  description = "Primary account key. Prefer managed identity; this is here for tools that cannot use Entra ID."
  value       = azurerm_cosmosdb_account.this.primary_key
  sensitive   = true
}

output "app_env" {
  description = "Environment variables apps use to reach Cosmos with a managed identity."
  value = {
    COSMOS_ENDPOINT   = azurerm_cosmosdb_account.this.endpoint
    COSMOS_DATABASE   = azurerm_cosmosdb_sql_database.this.name
    COSMOS_CONTAINERS = join(",", sort(keys(azurerm_cosmosdb_sql_container.this)))
    COSMOS_AUTH_MODE  = "managed-identity"
  }
}
