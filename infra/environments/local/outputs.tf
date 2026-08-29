output "app_urls" {
  description = "Host URLs for apps that publish a port."
  value       = { for name, app in module.apps : name => app.url if app.url != null }
}

output "app_internal_targets" {
  description = "host:port each app is reachable at from inside the stack network."
  value       = { for name, app in module.apps : name => app.internal_target }
}

output "grafana_url" {
  description = "Local Grafana."
  value       = module.observability.grafana_url
}

output "prometheus_url" {
  description = "Local Prometheus."
  value       = module.observability.prometheus_url
}

output "loki_url" {
  description = "Local Loki."
  value       = module.observability.loki_url
}

output "tempo_url" {
  description = "Local Tempo."
  value       = module.observability.tempo_url
}

output "otlp_endpoint" {
  description = "OTLP endpoint apps export telemetry to from inside the network."
  value       = module.observability.otlp_grpc_endpoint
}

output "cosmos_endpoint" {
  description = "Cosmos emulator endpoint from the host machine."
  value       = module.cosmos.host_endpoint
}

output "cosmos_database" {
  description = "Cosmos database name apps are configured with."
  value       = var.cosmos_database_name
}

output "network_name" {
  description = "Docker network the stack runs on."
  value       = module.network.name
}
