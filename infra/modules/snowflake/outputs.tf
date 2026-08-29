output "database_name" {
  description = "Snowflake database name."
  value       = snowflake_database.this.name
}

output "schema_names" {
  description = "Created schema names."
  value       = sort(keys(snowflake_schema.this))
}

output "warehouse_names" {
  description = "Created warehouse names."
  value       = sort(keys(snowflake_warehouse.this))
}

output "role_names" {
  description = "Created account role names."
  value       = sort(keys(snowflake_account_role.this))
}

output "service_user_names" {
  description = "Created service user names."
  value       = sort(keys(snowflake_service_user.this))
}

output "app_env" {
  description = <<-EOT
    Non-secret Snowflake connection settings for the apps. The private key is
    delivered separately through Key Vault.
  EOT
  value = {
    for user_name, user in var.service_users : user_name => {
      SNOWFLAKE_USER      = user_name
      SNOWFLAKE_ROLE      = user.role
      SNOWFLAKE_WAREHOUSE = user.default_warehouse
      SNOWFLAKE_DATABASE  = snowflake_database.this.name
      SNOWFLAKE_SCHEMA    = user.default_schema
    }
  }
}
