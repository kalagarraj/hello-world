terraform {
  required_version = ">= 1.6"

  required_providers {
    snowflake = {
      source  = "snowflakedb/snowflake"
      version = "~> 2.0"
    }
  }
}

# Credentials come from the environment (SNOWFLAKE_ORGANIZATION_NAME,
# SNOWFLAKE_ACCOUNT_NAME, SNOWFLAKE_USER, SNOWFLAKE_PRIVATE_KEY, ...) or from
# ~/.snowflake/config. Nothing authentication-related belongs in a .tfvars file.
provider "snowflake" {
  organization_name = var.organization_name
  account_name      = var.account_name
  user              = var.user
  role              = var.role
  authenticator     = var.authenticator
  private_key       = var.private_key
}
