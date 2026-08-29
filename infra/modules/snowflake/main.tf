terraform {
  required_version = ">= 1.6"
  required_providers {
    snowflake = {
      source  = "snowflakedb/snowflake"
      version = ">= 2.0"
    }
  }
}

locals {
  # One grant resource per (role, schema) and (role, warehouse) pair.
  role_schemas = merge([
    for role_name, role in var.roles : {
      for schema_name in(length(role.schemas) > 0 ? role.schemas : keys(var.schemas)) :
      "${role_name}.${schema_name}" => {
        role        = role_name
        schema      = schema_name
        role_config = role
      }
    }
  ]...)

  role_warehouses = merge([
    for role_name, role in var.roles : {
      for wh in role.warehouses :
      "${role_name}.${wh}" => {
        role      = role_name
        warehouse = wh
      }
    }
  ]...)
}

# ---------------------------------------------------------------------------
# Database and schemas
# ---------------------------------------------------------------------------

resource "snowflake_database" "this" {
  name                        = var.database_name
  comment                     = var.database_comment
  is_transient                = var.database_is_transient
  data_retention_time_in_days = var.database_retention_days
}

resource "snowflake_schema" "this" {
  for_each = var.schemas

  database            = snowflake_database.this.name
  name                = each.key
  comment             = each.value.comment
  with_managed_access = each.value.with_managed_access
  is_transient        = each.value.is_transient
}

# ---------------------------------------------------------------------------
# Warehouses. Separate warehouses per workload keep an analyst's query from
# competing with the API for compute, and make cost attributable per app.
# ---------------------------------------------------------------------------

resource "snowflake_warehouse" "this" {
  for_each = var.warehouses

  name                = each.key
  comment             = each.value.comment
  warehouse_size      = each.value.size
  auto_suspend        = each.value.auto_suspend
  auto_resume         = tostring(each.value.auto_resume)
  initially_suspended = each.value.initially_suspended
  min_cluster_count   = each.value.min_cluster_count
  max_cluster_count   = each.value.max_cluster_count
  scaling_policy      = each.value.scaling_policy
  warehouse_type      = each.value.warehouse_type
}

# ---------------------------------------------------------------------------
# Roles and grants
# ---------------------------------------------------------------------------

resource "snowflake_account_role" "this" {
  for_each = var.roles

  name    = each.key
  comment = each.value.comment
}

resource "snowflake_grant_privileges_to_account_role" "database_usage" {
  for_each = var.roles

  account_role_name = snowflake_account_role.this[each.key].name
  privileges        = each.value.database_privileges

  on_account_object {
    object_type = "DATABASE"
    object_name = snowflake_database.this.name
  }
}

resource "snowflake_grant_privileges_to_account_role" "schema_usage" {
  for_each = local.role_schemas

  account_role_name = snowflake_account_role.this[each.value.role].name
  privileges        = each.value.role_config.schema_privileges

  on_schema {
    schema_name = "\"${snowflake_database.this.name}\".\"${snowflake_schema.this[each.value.schema].name}\""
  }
}

# Privileges on tables that exist today.
resource "snowflake_grant_privileges_to_account_role" "existing_tables" {
  for_each = {
    for k, v in local.role_schemas : k => v
    if length(v.role_config.table_privileges) > 0
  }

  account_role_name = snowflake_account_role.this[each.value.role].name
  privileges        = each.value.role_config.table_privileges

  on_schema_object {
    all {
      object_type_plural = "TABLES"
      in_schema          = "\"${snowflake_database.this.name}\".\"${snowflake_schema.this[each.value.schema].name}\""
    }
  }
}

# ... and on tables created later, so a new table does not silently break the
# app or lock analysts out.
resource "snowflake_grant_privileges_to_account_role" "future_tables" {
  for_each = {
    for k, v in local.role_schemas : k => v
    if length(v.role_config.table_privileges) > 0
  }

  account_role_name = snowflake_account_role.this[each.value.role].name
  privileges        = each.value.role_config.table_privileges

  on_schema_object {
    future {
      object_type_plural = "TABLES"
      in_schema          = "\"${snowflake_database.this.name}\".\"${snowflake_schema.this[each.value.schema].name}\""
    }
  }
}

resource "snowflake_grant_privileges_to_account_role" "existing_views" {
  for_each = {
    for k, v in local.role_schemas : k => v
    if length(v.role_config.view_privileges) > 0
  }

  account_role_name = snowflake_account_role.this[each.value.role].name
  privileges        = each.value.role_config.view_privileges

  on_schema_object {
    all {
      object_type_plural = "VIEWS"
      in_schema          = "\"${snowflake_database.this.name}\".\"${snowflake_schema.this[each.value.schema].name}\""
    }
  }
}

resource "snowflake_grant_privileges_to_account_role" "future_views" {
  for_each = {
    for k, v in local.role_schemas : k => v
    if length(v.role_config.view_privileges) > 0
  }

  account_role_name = snowflake_account_role.this[each.value.role].name
  privileges        = each.value.role_config.view_privileges

  on_schema_object {
    future {
      object_type_plural = "VIEWS"
      in_schema          = "\"${snowflake_database.this.name}\".\"${snowflake_schema.this[each.value.schema].name}\""
    }
  }
}

resource "snowflake_grant_privileges_to_account_role" "warehouse" {
  for_each = local.role_warehouses

  account_role_name = snowflake_account_role.this[each.value.role].name
  privileges        = ["USAGE", "OPERATE"]

  on_account_object {
    object_type = "WAREHOUSE"
    object_name = snowflake_warehouse.this[each.value.warehouse].name
  }
}

# ---------------------------------------------------------------------------
# Service users. Key-pair only: Snowflake blocks single-factor password
# authentication for programmatic users.
# ---------------------------------------------------------------------------

resource "snowflake_service_user" "this" {
  for_each = var.service_users

  name              = each.key
  comment           = each.value.comment
  rsa_public_key    = each.value.rsa_public_key
  default_role      = snowflake_account_role.this[each.value.role].name
  default_warehouse = snowflake_warehouse.this[each.value.default_warehouse].name
  default_namespace = "${snowflake_database.this.name}.${each.value.default_schema}"
}

resource "snowflake_grant_account_role" "service_users" {
  for_each = var.service_users

  role_name = snowflake_account_role.this[each.value.role].name
  user_name = snowflake_service_user.this[each.key].name
}
