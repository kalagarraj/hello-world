variable "name_prefix" {
  description = "Short prefix for every resource name, e.g. \"helloworld\"."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{1,16}$", var.name_prefix))
    error_message = "name_prefix must be 2-17 lowercase alphanumeric or hyphen characters and start with a letter."
  }
}

variable "environment" {
  description = "Environment name, e.g. dev, stg, prod."
  type        = string
}

variable "location" {
  description = "Azure region."
  type        = string
}

variable "tags" {
  description = "Tags applied to every resource."
  type        = map(string)
  default     = {}
}

variable "registry_sku" {
  description = "Container registry SKU."
  type        = string
  default     = "Basic"

  validation {
    condition     = contains(["Basic", "Standard", "Premium"], var.registry_sku)
    error_message = "registry_sku must be Basic, Standard, or Premium."
  }
}

variable "log_retention_days" {
  description = "Log Analytics retention in days."
  type        = number
  default     = 30
}

variable "enable_vnet" {
  description = "Place the Container Apps environment in a customer-managed VNet."
  type        = bool
  default     = false
}

variable "vnet_address_space" {
  description = "Address space of the VNet when enable_vnet is true."
  type        = string
  default     = "10.20.0.0/16"
}

variable "container_apps_subnet_prefix" {
  description = "Subnet delegated to Container Apps. Must be /23 or larger."
  type        = string
  default     = "10.20.0.0/23"
}

variable "zone_redundant" {
  description = "Run the Container Apps environment zone-redundantly. Requires enable_vnet."
  type        = bool
  default     = false
}

variable "key_vault_purge_protection" {
  description = "Enable Key Vault purge protection. Leave off in throwaway environments; it cannot be undone."
  type        = bool
  default     = false
}

variable "grant_deployer_key_vault_access" {
  description = "Grant the identity running Terraform the Key Vault Secrets Officer role so it can write secrets."
  type        = bool
  default     = true
}
