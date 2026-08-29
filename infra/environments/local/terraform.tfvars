# ---------------------------------------------------------------------------
# Local stack defaults.
#
# The images below are stand-ins that run out of the box so the wiring can be
# verified before the real apps exist. Replace `image` with your own image, or
# swap it for a `build` block pointing at a Dockerfile in this repository.
# ---------------------------------------------------------------------------

stack_name = "helloworld"

apps = {
  web = {
    image     = "nginx"
    tag       = "1.27-alpine"
    port      = 80
    host_port = 8080
    # nginx serves no /metrics endpoint; its telemetry arrives via the collector.
    scrape_metrics = false
    env = {
      API_BASE_URL = "http://api:8080"
    }
  }

  api = {
    image       = "mendhak/http-https-echo"
    tag         = "35"
    port        = 8080
    host_port   = 8088
    uses_cosmos = true
    # Flip to true once a Snowflake dev account is configured below.
    uses_snowflake = false
    scrape_metrics = false
    env = {
      HTTP_PORT = "8080"
    }
  }
}

ports = {
  grafana    = 3000
  prometheus = 9090
  loki       = 3100
  tempo      = 3200
  otlp_grpc  = 4317
  otlp_http  = 4318
  cosmos     = 8081
}

cosmos_database_name = "appdb"

cosmos_containers = {
  greetings = {
    partition_key_paths = ["/tenantId"]
  }
  events = {
    partition_key_paths = ["/tenantId"]
  }
}

grafana_anonymous_access = true

# Uncomment to let local Grafana query a Snowflake development account.
# grafana_plugins = ["snowflake-datasource"]

# snowflake_connection = {
#   account   = "myorg-myaccount"
#   user      = "SVC_HELLOWORLD_API"
#   role      = "HELLOWORLD_APP"
#   warehouse = "HELLOWORLD_APP_WH"
#   database  = "HELLOWORLD_DEV"
#   schema    = "APP"
# }
