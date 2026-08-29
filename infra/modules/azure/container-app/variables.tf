variable "name" {
  description = "Logical app name."
  type        = string
}

variable "base_name" {
  description = "prefix-environment string used to build the resource name."
  type        = string
}

variable "environment" {
  description = "Environment name, surfaced to the app as APP_ENV."
  type        = string
}

variable "resource_group_name" {
  description = "Resource group the app is created in."
  type        = string
}

variable "container_app_environment_id" {
  description = "Container Apps environment resource id."
  type        = string
}

variable "registry_login_server" {
  description = "Container registry login server."
  type        = string
}

variable "identity_id" {
  description = "User-assigned identity resource id used for registry pulls, Key Vault, and Cosmos."
  type        = string
}

variable "identity_client_id" {
  description = "Client id of the identity, passed to the app as AZURE_CLIENT_ID for DefaultAzureCredential."
  type        = string
}

variable "spec" {
  description = "App specification. Mirrors the schema consumed by the local Docker root module."
  type = object({
    image                 = string
    tag                   = string
    port                  = number
    cpu                   = optional(number, 0.5)
    memory                = optional(string, "1Gi")
    min_replicas          = optional(number, 0)
    max_replicas          = optional(number, 3)
    ingress_enabled       = optional(bool, true)
    external_ingress      = optional(bool, false)
    concurrent_requests   = optional(number, 50)
    revision_mode         = optional(string, "Single")
    workload_profile_name = optional(string)
    entrypoint            = optional(list(string))
    command               = optional(list(string))
    env                   = optional(map(string), {})
    key_vault_secrets     = optional(map(string), {})
    uses_cosmos           = optional(bool, false)
    uses_snowflake        = optional(bool, false)
    health_path           = optional(string)
  })
}

variable "extra_env" {
  description = "Environment variables injected into every app by the root module, e.g. the App Insights connection string."
  type        = map(string)
  default     = {}
}

variable "cosmos_env" {
  description = "Cosmos connection variables, injected when spec.uses_cosmos is true."
  type        = map(string)
  default     = {}
}

variable "snowflake_env" {
  description = "Snowflake connection variables, injected when spec.uses_snowflake is true."
  type        = map(string)
  default     = {}
}

variable "tags" {
  description = "Tags applied to the app."
  type        = map(string)
  default     = {}
}
