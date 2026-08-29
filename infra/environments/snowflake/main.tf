# ---------------------------------------------------------------------------
# Snowflake environment.
#
# Kept separate from the Azure root because it authenticates against Snowflake,
# not Azure, and its objects outlive any single Azure environment. The outputs
# here feed the `snowflake_connection` variable of environments/azure and the
# `snowflake_connection` variable of environments/local.
# ---------------------------------------------------------------------------

module "snowflake" {
  source = "../../modules/snowflake"

  database_name           = var.database_name
  database_comment        = "Application data for ${var.database_name}"
  database_is_transient   = var.database_is_transient
  database_retention_days = var.database_retention_days

  schemas       = var.schemas
  warehouses    = var.warehouses
  roles         = var.roles
  service_users = var.service_users
}
