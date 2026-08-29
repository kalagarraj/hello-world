# ---------------------------------------------------------------------------
# Development environment.
#
# Cost-shaped: serverless Cosmos, scale-to-zero apps, no VNet, no zone
# redundancy. `image` names are repository paths inside the ACR this stack
# creates; CI pushes the tags and owns them from the first deploy onwards.
# ---------------------------------------------------------------------------

environment = "dev"
location    = "westeurope"

tags = {
  cost_center = "engineering"
  owner       = "platform"
}

apps = {
  web = {
    image            = "helloworld/web"
    tag              = "latest"
    port             = 8080
    cpu              = 0.25
    memory           = "0.5Gi"
    min_replicas     = 0
    max_replicas     = 2
    external_ingress = true
    health_path      = "/healthz"
    env = {
      API_BASE_URL = "https://api.internal"
    }
  }

  api = {
    image            = "helloworld/api"
    tag              = "latest"
    port             = 8080
    cpu              = 0.5
    memory           = "1Gi"
    min_replicas     = 0
    max_replicas     = 5
    external_ingress = false
    health_path      = "/healthz"
    uses_cosmos      = true
    uses_snowflake   = false
  }
}

cosmos = {
  database_name = "appdb"
  capacity_mode = "serverless"

  containers = {
    greetings = {
      partition_key_paths = ["/tenantId"]
    }
    events = {
      partition_key_paths = ["/tenantId"]
      default_ttl         = 2592000
    }
  }
}

observability = {
  enable_grafana            = true
  enable_managed_prometheus = true
  grafana_sku               = "Essential"
  retention_days            = 30
  # grafana_admin_principal_ids = ["<entra-object-id>"]
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
    severity         = 2
    dimensions = [
      {
        name     = "StatusCode"
        operator = "Include"
        values   = ["429"]
      }
    ]
  }
}
