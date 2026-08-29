output "database_name" {
  description = "Database name."
  value       = module.snowflake.database_name
}

output "schema_names" {
  description = "Created schemas."
  value       = module.snowflake.schema_names
}

output "warehouse_names" {
  description = "Created warehouses."
  value       = module.snowflake.warehouse_names
}

output "role_names" {
  description = "Created roles."
  value       = module.snowflake.role_names
}

output "service_user_names" {
  description = "Created service users."
  value       = module.snowflake.service_user_names
}

output "connections" {
  description = <<-EOT
    Connection settings per service user. Feed the relevant entry into the
    `snowflake_connection` variable of environments/azure and environments/local.
  EOT
  value = {
    for user_name, env in module.snowflake.app_env : user_name => merge(env, {
      SNOWFLAKE_ACCOUNT = "${var.organization_name}-${var.account_name}"
    })
  }
}
