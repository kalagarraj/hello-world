output "endpoint" {
  description = "Emulator endpoint as seen from other containers on the network."
  value       = local.endpoint
}

output "host_endpoint" {
  description = "Emulator endpoint as seen from the developer's machine."
  value       = "https://localhost:${var.host_port}"
}

output "key" {
  description = "Well-known emulator key. Publicly documented, not a real credential."
  value       = local.well_known_key
}

output "app_env" {
  description = "Environment variables apps use to reach the emulator."
  value = {
    COSMOS_ENDPOINT          = local.endpoint
    COSMOS_KEY               = local.well_known_key
    COSMOS_CONNECTION_STRING = local.connection_string
    COSMOS_DATABASE          = var.database_name
    COSMOS_CONTAINERS        = join(",", var.containers)
    # The emulator serves a self-signed certificate; SDKs need this to connect.
    COSMOS_DISABLE_SSL_VERIFICATION = "true"
    NODE_TLS_REJECT_UNAUTHORIZED    = "0"
  }
}
