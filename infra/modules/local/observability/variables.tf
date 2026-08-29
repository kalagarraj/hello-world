variable "stack_name" {
  description = "Stack label attached to every metric and span as an external label."
  type        = string
  default     = "hello-world"
}

variable "name_prefix" {
  description = "Prefix applied to container and volume names."
  type        = string
  default     = "helloworld-"
}

variable "network_name" {
  description = "Docker network the observability containers join."
  type        = string
}

variable "scrape_targets" {
  description = "Apps Prometheus scrapes directly, in addition to the collector."
  type = list(object({
    name         = string
    target       = string
    metrics_path = string
  }))
  default = []
}

variable "dashboards_dir" {
  description = "Directory of Grafana dashboard JSON files to provision. Null disables dashboard provisioning."
  type        = string
  default     = null
}

variable "grafana_dashboard_folder" {
  description = "Grafana folder the provisioned dashboards land in."
  type        = string
  default     = "Hello World"
}

variable "grafana_admin_user" {
  description = "Grafana admin username for the local stack."
  type        = string
  default     = "admin"
}

variable "grafana_admin_password" {
  description = "Grafana admin password for the local stack. Local-only credential."
  type        = string
  default     = "admin"
  sensitive   = true
}

variable "grafana_anonymous_access" {
  description = "Allow unauthenticated read-only access to local Grafana."
  type        = bool
  default     = true
}

variable "grafana_plugins" {
  description = "Grafana plugins installed at container start."
  type        = list(string)
  default     = []
}

variable "retention_hours" {
  description = "Retention window applied to metrics, logs, and traces."
  type        = number
  default     = 168
}

variable "images" {
  description = "Container images for the observability stack."
  type = object({
    prometheus     = optional(string, "prom/prometheus:v3.1.0")
    loki           = optional(string, "grafana/loki:3.3.2")
    tempo          = optional(string, "grafana/tempo:2.7.0")
    otel_collector = optional(string, "otel/opentelemetry-collector-contrib:0.117.0")
    grafana        = optional(string, "grafana/grafana:11.5.1")
  })
  default = {}
}

variable "ports" {
  description = "Host ports published by the observability stack."
  type = object({
    grafana    = optional(number, 3000)
    prometheus = optional(number, 9090)
    loki       = optional(number, 3100)
    tempo      = optional(number, 3200)
    otlp_grpc  = optional(number, 4317)
    otlp_http  = optional(number, 4318)
  })
  default = {}
}
