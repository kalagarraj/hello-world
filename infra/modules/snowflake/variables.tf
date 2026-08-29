variable "database_name" {
  description = "Snowflake database name."
  type        = string
}

variable "database_comment" {
  description = "Comment attached to the database."
  type        = string
  default     = "Managed by Terraform"
}

variable "database_is_transient" {
  description = "Create the database as transient (no fail-safe, cheaper storage)."
  type        = bool
  default     = false
}

variable "database_retention_days" {
  description = "Time Travel retention in days."
  type        = number
  default     = 1
}

variable "schemas" {
  description = "Schemas to create, keyed by schema name."
  type = map(object({
    comment             = optional(string, "Managed by Terraform")
    with_managed_access = optional(bool, false)
    is_transient        = optional(bool, false)
  }))
}

variable "warehouses" {
  description = "Virtual warehouses to create, keyed by warehouse name."
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
  description = <<-EOT
    Account roles to create, keyed by role name. `schemas` limits the role to a
    subset of the schemas above; leave it empty to grant across all of them.
  EOT
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
  description = <<-EOT
    Programmatic users, keyed by user name. rsa_public_key is the PEM body
    without the header and footer lines; generate a key pair per user and keep
    the private half in Key Vault.
  EOT
  type = map(object({
    role              = string
    default_warehouse = string
    default_schema    = string
    rsa_public_key    = string
    comment           = optional(string, "Managed by Terraform")
  }))
  default = {}
}
