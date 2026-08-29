# ---------------------------------------------------------------------------
# Production environment.
#
# Differences from dev: apps never scale to zero, Cosmos runs provisioned with
# autoscale and continuous backup, the environment sits in a VNet with zone
# redundancy, and Key Vault purge protection is on.
# ---------------------------------------------------------------------------

environment = "prod"
location    = "westeurope"

registry_sku               = "Standard"
log_retention_days         = 90
enable_vnet                = true
zone_redundant             = true
key_vault_purge_protection = true

tags = {
  cost_center = "engineering"
  owner       = "platform"
  criticality = "high"
}

apps = {
  web = {
    image               = "helloworld/web"
    tag                 = "latest"
    port                = 8080
    cpu                 = 0.5
    memory              = "1Gi"
    min_replicas        = 2
    max_replicas        = 10
    concurrent_requests = 80
    external_ingress    = true
    health_path         = "/healthz"
    env = {
      API_BASE_URL = "https://api.internal"
    }
  }

  api = {
    image               = "helloworld/api"
    tag                 = "latest"
    port                = 8080
    cpu                 = 1.0
    memory              = "2Gi"
    min_replicas        = 2
    max_replicas        = 20
    concurrent_requests = 60
    external_ingress    = false
    health_path         = "/healthz"
    uses_cosmos         = true
    uses_snowflake      = true
  }
}

cosmos = {
  database_name                     = "appdb"
  capacity_mode                     = "provisioned"
  consistency_level                 = "Session"
  database_autoscale_max_throughput = 4000
  disable_key_auth                  = true

  geo_locations = [
    {
      location          = "westeurope"
      failover_priority = 0
      zone_redundant    = true
    },
    {
      location          = "northeurope"
      failover_priority = 1
      zone_redundant    = false
    },
  ]

  backup = {
    type = "Continuous"
    tier = "Continuous30Days"
  }

  containers = {
    greetings = {
      partition_key_paths      = ["/tenantId"]
      autoscale_max_throughput = 4000
    }
    events = {
      partition_key_paths      = ["/tenantId"]
      autoscale_max_throughput = 10000
      default_ttl              = 7776000
    }
  }
}

observability = {
  enable_grafana            = true
  enable_managed_prometheus = true
  grafana_sku               = "Standard"
  grafana_zone_redundant    = true
  retention_days            = 90
  sampling_percentage       = 50
  # grafana_admin_principal_ids = ["<entra-group-object-id>"]
  # alert_email_receivers       = { oncall = "oncall@example.com" }
}

metric_alerts = {
  cosmos-throttled-requests = {
    description      = "Cosmos is returning 429s; requests are being throttled."
    target           = "cosmos"
    metric_namespace = "Microsoft.DocumentDB/databaseAccounts"
    metric_name      = "TotalRequests"
    aggregation      = "Count"
    operator         = "GreaterThan"
    threshold        = 10
    severity         = 1
    dimensions = [
      {
        name     = "StatusCode"
        operator = "Include"
        values   = ["429"]
      }
    ]
  }

  cosmos-server-latency = {
    description      = "Cosmos server-side latency is above the service objective."
    target           = "cosmos"
    metric_namespace = "Microsoft.DocumentDB/databaseAccounts"
    metric_name      = "ServerSideLatency"
    aggregation      = "Average"
    operator         = "GreaterThan"
    threshold        = 100
    severity         = 2
  }
}

# Supplied by environments/snowflake outputs.
# snowflake_connection = {
#   account   = "myorg-myaccount"
#   user      = "SVC_HELLOWORLD_API"
#   role      = "HELLOWORLD_APP"
#   warehouse = "HELLOWORLD_APP_WH"
#   database  = "HELLOWORLD_PROD"
#   schema    = "APP"
# }
