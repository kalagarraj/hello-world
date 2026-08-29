# ---------------------------------------------------------------------------
# Provider credentials. Prefer the matching SNOWFLAKE_* environment variables
# over passing these on the command line.
# ---------------------------------------------------------------------------

variable "organization_name" {
  description = "Snowflake organization name."
  type        = string
  default     = null
}

variable "account_name" {
  description = "Snowflake account name within the organization."
  type        = string
  default     = null
}

variable "user" {
  description = "Snowflake user Terraform authenticates as."
  type        = string
  default     = null
}

variable "role" {
  description = "Role Terraform runs under. Needs privileges to create databases, warehouses, roles, and users."
  type        = string
  default     = "SYSADMIN"
}

variable "authenticator" {
  description = "Authentication method. SNOWFLAKE_JWT is key-pair authentication."
  type        = string
  default     = "SNOWFLAKE_JWT"
}

variable "private_key" {
  description = "PEM-encoded private key for the Terraform user. Supply via TF_VAR_private_key."
  type        = string
  default     = null
  sensitive   = true
}

# ---------------------------------------------------------------------------
# Objects
# ---------------------------------------------------------------------------

variable "database_name" {
  description = "Database name."
  type        = string
}

variable "database_is_transient" {
  description = "Create the database as transient. Reasonable for dev, not for production."
  type        = bool
  default     = false
}

variable "database_retention_days" {
  description = "Time Travel retention in days."
  type        = number
  default     = 1
}

variable "schemas" {
  description = "Schemas to create, keyed by name."
  type = map(object({
    comment             = optional(string, "Managed by Terraform")
    with_managed_access = optional(bool, false)
    is_transient        = optional(bool, false)
  }))
}

variable "warehouses" {
  description = "Warehouses to create, keyed by name."
  type = map(object({
    size                = optional(string, "XSMALL")
    comment             = optional(string, "Managed by Terraform")
    auto_suspend        = optional(number, 60)
    auto_resume         = optional(bool, true)
    initially_suspended = optional(bool, true)
    min_cluster_count   = optional(number, 1)
    max_cluster_count   = optional(number, 1)
    scaling_policy      = optional(string, "STANDARD")
    warehouse_type      = optional(string, "STANDARD")
  }))
}

variable "roles" {
  description = "Account roles and their grants, keyed by role name."
  type = map(object({
    comment             = optional(string, "Managed by Terraform")
    schemas             = optional(list(string), [])
    warehouses          = optional(list(string), [])
    database_privileges = optional(list(string), ["USAGE"])
    schema_privileges   = optional(list(string), ["USAGE"])
    table_privileges    = optional(list(string), [])
    view_privileges     = optional(list(string), [])
  }))
}

variable "service_users" {
  description = "Programmatic users, keyed by user name."
  type = map(object({
    role              = string
    default_warehouse = string
    default_schema    = string
    rsa_public_key    = string
    comment           = optional(string, "Managed by Terraform")
  }))
  default = {}
}
