# ---------------------------------------------------------------------------
# Snowflake development objects.
#
# Provider credentials are NOT set here. Export them instead:
#   export SNOWFLAKE_ORGANIZATION_NAME=myorg
#   export SNOWFLAKE_ACCOUNT_NAME=myaccount
#   export SNOWFLAKE_USER=TERRAFORM_SVC
#   export TF_VAR_private_key="$(cat ~/.snowflake/terraform.p8)"
# ---------------------------------------------------------------------------

database_name           = "HELLOWORLD_DEV"
database_is_transient   = true
database_retention_days = 1

schemas = {
  APP = {
    comment = "Tables written by the API app"
  }
  ANALYTICS = {
    comment             = "Curated views for reporting and Grafana"
    with_managed_access = true
  }
}

warehouses = {
  HELLOWORLD_APP_WH = {
    size         = "XSMALL"
    auto_suspend = 60
    comment      = "Serves application queries"
  }
  HELLOWORLD_BI_WH = {
    size         = "XSMALL"
    auto_suspend = 120
    comment      = "Serves Grafana and ad-hoc analysis"
  }
}

roles = {
  # Read/write on the app schema only.
  HELLOWORLD_APP = {
    comment             = "Application read/write role"
    schemas             = ["APP"]
    warehouses          = ["HELLOWORLD_APP_WH"]
    database_privileges = ["USAGE"]
    schema_privileges   = ["USAGE", "CREATE TABLE", "CREATE VIEW"]
    table_privileges    = ["SELECT", "INSERT", "UPDATE", "DELETE"]
    view_privileges     = ["SELECT"]
  }

  # Read-only across both schemas: this is the role Grafana queries under.
  HELLOWORLD_READER = {
    comment             = "Read-only role for dashboards and analysis"
    schemas             = ["APP", "ANALYTICS"]
    warehouses          = ["HELLOWORLD_BI_WH"]
    database_privileges = ["USAGE"]
    schema_privileges   = ["USAGE"]
    table_privileges    = ["SELECT"]
    view_privileges     = ["SELECT"]
  }
}

# Generate a key pair per user, then paste the public key body here:
#   openssl genrsa 2048 | openssl pkcs8 -topk8 -inform PEM -out svc_api.p8 -nocrypt
#   openssl rsa -in svc_api.p8 -pubout -out svc_api.pub
# Store the private half in Key Vault (TF_VAR_snowflake_private_key for the
# Azure root) and never commit it.
service_users = {}

# service_users = {
#   SVC_HELLOWORLD_API = {
#     role              = "HELLOWORLD_APP"
#     default_warehouse = "HELLOWORLD_APP_WH"
#     default_schema    = "APP"
#     rsa_public_key    = "MIIBIjANBgkq...   # body only, no BEGIN/END lines"
#     comment           = "API service account"
#   }
#   SVC_HELLOWORLD_GRAFANA = {
#     role              = "HELLOWORLD_READER"
#     default_warehouse = "HELLOWORLD_BI_WH"
#     default_schema    = "ANALYTICS"
#     rsa_public_key    = "MIIBIjANBgkq..."
#     comment           = "Grafana Snowflake data source"
#   }
# }
