output "name" {
  description = "Container app resource name."
  value       = azurerm_container_app.this.name
}

output "id" {
  description = "Container app resource id."
  value       = azurerm_container_app.this.id
}

output "fqdn" {
  description = "Ingress FQDN, or null when the app has no ingress."
  value       = try(azurerm_container_app.this.ingress[0].fqdn, null)
}

output "url" {
  description = "Ingress URL, or null when the app has no ingress."
  value       = try("https://${azurerm_container_app.this.ingress[0].fqdn}", null)
}

output "latest_revision_name" {
  description = "Name of the latest revision."
  value       = azurerm_container_app.this.latest_revision_name
}
