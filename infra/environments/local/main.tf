# ---------------------------------------------------------------------------
# Local development stack.
#
# Mirrors the Azure environment on a developer's machine: the same app
# specifications, a Cosmos DB emulator standing in for the Cosmos account, and
# a Grafana/Prometheus/Loki/Tempo stack standing in for Azure Managed Grafana
# and Azure Monitor. Apps see identical environment variable names in both.
# ---------------------------------------------------------------------------

locals {
  name_prefix = "${var.stack_name}-"

  # Apps that expose a /metrics endpoint are scraped directly by Prometheus;
  # everything else arrives through the collector over OTLP.
  scrape_targets = [
    for name, spec in var.apps : {
      name         = name
      target       = "${name}:${spec.port}"
      metrics_path = spec.metrics_path
    }
    if spec.scrape_metrics
  ]

  # Populated only when a real Snowflake account is configured; there is no
  # Snowflake emulator, so local apps either talk to a dev account or run
  # without it.
  snowflake_env = var.snowflake_connection == null ? {} : {
    SNOWFLAKE_ACCOUNT          = var.snowflake_connection.account
    SNOWFLAKE_USER             = var.snowflake_connection.user
    SNOWFLAKE_ROLE             = var.snowflake_connection.role
    SNOWFLAKE_WAREHOUSE        = var.snowflake_connection.warehouse
    SNOWFLAKE_DATABASE         = var.snowflake_connection.database
    SNOWFLAKE_SCHEMA           = var.snowflake_connection.schema
    SNOWFLAKE_PRIVATE_KEY_PATH = var.snowflake_connection.private_key_path
  }
}

module "network" {
  source = "../../modules/local/network"

  name   = "${var.stack_name}-net"
  subnet = var.network_subnet
}

module "cosmos" {
  source = "../../modules/local/cosmos-emulator"

  container_name       = "${local.name_prefix}cosmos"
  network_name         = module.network.name
  image                = var.cosmos_emulator_image
  host_port            = var.ports.cosmos
  publish_direct_ports = var.cosmos_publish_direct_ports
  partition_count      = var.cosmos_partition_count
  persist_data         = var.cosmos_persist_data
  database_name        = var.cosmos_database_name
  containers           = keys(var.cosmos_containers)
}

module "observability" {
  source = "../../modules/local/observability"

  stack_name               = var.stack_name
  name_prefix              = local.name_prefix
  network_name             = module.network.name
  scrape_targets           = local.scrape_targets
  dashboards_dir           = "${path.module}/../../shared/dashboards"
  grafana_admin_user       = var.grafana_admin_user
  grafana_admin_password   = var.grafana_admin_password
  grafana_anonymous_access = var.grafana_anonymous_access
  grafana_plugins          = var.grafana_plugins
  retention_hours          = var.telemetry_retention_hours
  images                   = var.observability_images

  ports = {
    grafana    = var.ports.grafana
    prometheus = var.ports.prometheus
    loki       = var.ports.loki
    tempo      = var.ports.tempo
    otlp_grpc  = var.ports.otlp_grpc
    otlp_http  = var.ports.otlp_http
  }
}

module "apps" {
  source   = "../../modules/local/app"
  for_each = var.apps

  name          = each.key
  name_prefix   = local.name_prefix
  spec          = each.value
  network_name  = module.network.name
  otlp_endpoint = module.observability.otlp_grpc_endpoint
  cosmos_env    = module.cosmos.app_env
  snowflake_env = local.snowflake_env
}
