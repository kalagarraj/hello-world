output "resource_group_name" {
  description = "Resource group holding the stack."
  value       = azurerm_resource_group.this.name
}

output "resource_group_id" {
  description = "Resource group id."
  value       = azurerm_resource_group.this.id
}

output "location" {
  description = "Azure region of the stack."
  value       = azurerm_resource_group.this.location
}

output "base_name" {
  description = "prefix-environment string other modules build names from."
  value       = local.base
}

output "log_analytics_workspace_id" {
  description = "Log Analytics workspace resource id."
  value       = azurerm_log_analytics_workspace.this.id
}

output "container_registry_id" {
  description = "Container registry resource id."
  value       = azurerm_container_registry.this.id
}

output "container_registry_login_server" {
  description = "Registry login server, e.g. myacr.azurecr.io."
  value       = azurerm_container_registry.this.login_server
}

output "container_app_environment_id" {
  description = "Container Apps environment resource id."
  value       = azurerm_container_app_environment.this.id
}

output "container_app_environment_default_domain" {
  description = "Default domain apps are published under."
  value       = azurerm_container_app_environment.this.default_domain
}

output "app_identity_id" {
  description = "Resource id of the shared app identity."
  value       = azurerm_user_assigned_identity.apps.id
}

output "app_identity_principal_id" {
  description = "Principal (object) id of the shared app identity, for role assignments."
  value       = azurerm_user_assigned_identity.apps.principal_id
}

output "app_identity_client_id" {
  description = "Client id of the shared app identity, for DefaultAzureCredential."
  value       = azurerm_user_assigned_identity.apps.client_id
}

output "key_vault_id" {
  description = "Key Vault resource id."
  value       = azurerm_key_vault.this.id
}

output "key_vault_uri" {
  description = "Key Vault URI."
  value       = azurerm_key_vault.this.vault_uri
}

output "tenant_id" {
  description = "Tenant the stack is deployed into."
  value       = data.azurerm_client_config.current.tenant_id
}
