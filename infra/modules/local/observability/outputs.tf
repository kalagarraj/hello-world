output "grafana_url" {
  description = "Grafana URL on the developer's machine."
  value       = "http://localhost:${var.ports.grafana}"
}

output "prometheus_url" {
  description = "Prometheus URL on the developer's machine."
  value       = "http://localhost:${var.ports.prometheus}"
}

output "loki_url" {
  description = "Loki URL on the developer's machine."
  value       = "http://localhost:${var.ports.loki}"
}

output "tempo_url" {
  description = "Tempo URL on the developer's machine."
  value       = "http://localhost:${var.ports.tempo}"
}

output "otlp_grpc_endpoint" {
  description = "OTLP gRPC endpoint apps inside the network export to."
  value       = "http://otel-collector:4317"
}

output "otlp_http_endpoint" {
  description = "OTLP HTTP endpoint apps inside the network export to."
  value       = "http://otel-collector:4318"
}
