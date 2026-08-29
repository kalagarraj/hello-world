variable "stack_name" {
  description = "Prefix for the docker network, containers, and volumes."
  type        = string
  default     = "helloworld"
}

variable "docker_host" {
  description = "Docker daemon endpoint. Override on Windows or with a non-default socket path."
  type        = string
  default     = "unix:///var/run/docker.sock"
}

variable "network_subnet" {
  description = "CIDR for the stack's bridge network."
  type        = string
  default     = "172.28.0.0/16"
}

# ---------------------------------------------------------------------------
# Apps
#
# This schema is intentionally the same as the Azure root module's `apps`
# variable, minus the fields that only make sense in one place. Adding an app
# means adding an entry here and in azure/*.tfvars, not writing new Terraform.
# ---------------------------------------------------------------------------

variable "apps" {
  description = "Apps to run locally, keyed by app name."
  type = map(object({
    image          = string
    tag            = optional(string, "latest")
    port           = optional(number, 8080)
    host_port      = optional(number)
    entrypoint     = optional(list(string))
    command        = optional(list(string))
    env            = optional(map(string), {})
    uses_cosmos    = optional(bool, false)
    uses_snowflake = optional(bool, false)
    health_path    = optional(string)
    metrics_path   = optional(string, "/metrics")
    scrape_metrics = optional(bool, true)
    build = optional(object({
      context    = string
      dockerfile = optional(string, "Dockerfile")
      build_args = optional(map(string), {})
    }))
  }))
}

variable "ports" {
  description = "Host ports published by the stack."
  type = object({
    grafana    = optional(number, 3000)
    prometheus = optional(number, 9090)
    loki       = optional(number, 3100)
    tempo      = optional(number, 3200)
    otlp_grpc  = optional(number, 4317)
    otlp_http  = optional(number, 4318)
    cosmos     = optional(number, 8081)
  })
  default = {}
}

# ---------------------------------------------------------------------------
# Cosmos emulator
# ---------------------------------------------------------------------------

variable "cosmos_emulator_image" {
  description = "Cosmos DB emulator image."
  type        = string
  default     = "mcr.microsoft.com/cosmosdb/linux/azure-cosmos-emulator:vnext-preview"
}

variable "cosmos_publish_direct_ports" {
  description = "Publish ports 10250-10255. Required by the classic emulator image only."
  type        = bool
  default     = false
}

variable "cosmos_partition_count" {
  description = "Emulator physical partition count. Lower values start faster."
  type        = number
  default     = 3
}

variable "cosmos_persist_data" {
  description = "Keep emulator data across container restarts."
  type        = bool
  default     = true
}

variable "cosmos_database_name" {
  description = "Cosmos database name. Matches the Azure environment."
  type        = string
  default     = "appdb"
}

variable "cosmos_containers" {
  description = "Cosmos containers the apps expect. Keys are surfaced to apps as COSMOS_CONTAINERS."
  type = map(object({
    partition_key_paths = list(string)
  }))
  default = {}
}

# ---------------------------------------------------------------------------
# Observability
# ---------------------------------------------------------------------------

variable "grafana_admin_user" {
  description = "Local Grafana admin username."
  type        = string
  default     = "admin"
}

variable "grafana_admin_password" {
  description = "Local Grafana admin password. Local-only, never reused in Azure."
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
  description = "Grafana plugins to install, e.g. snowflake-datasource for querying Snowflake."
  type        = list(string)
  default     = []
}

variable "telemetry_retention_hours" {
  description = "Retention window for local metrics, logs, and traces."
  type        = number
  default     = 168
}

variable "observability_images" {
  description = "Pin the observability container images."
  type = object({
    prometheus     = optional(string, "prom/prometheus:v3.1.0")
    loki           = optional(string, "grafana/loki:3.3.2")
    tempo          = optional(string, "grafana/tempo:2.7.0")
    otel_collector = optional(string, "otel/opentelemetry-collector-contrib:0.117.0")
    grafana        = optional(string, "grafana/grafana:11.5.1")
  })
  default = {}
}

# ---------------------------------------------------------------------------
# Snowflake
# ---------------------------------------------------------------------------

variable "snowflake_connection" {
  description = <<-EOT
    Connection settings local apps use to reach a shared Snowflake development
    account. There is no Snowflake emulator, so leave this null to run the
    stack without Snowflake.
  EOT
  type = object({
    account          = string
    user             = string
    role             = string
    warehouse        = string
    database         = string
    schema           = string
    private_key_path = optional(string, "/run/secrets/snowflake_key.p8")
  })
  default = null
}
