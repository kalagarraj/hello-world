variable "name" {
  description = "Logical app name, used as the container name suffix and DNS alias."
  type        = string
}

variable "name_prefix" {
  description = "Prefix applied to container names to keep stacks isolated."
  type        = string
  default     = "helloworld-"
}

variable "spec" {
  description = "App specification. Mirrors the schema consumed by the Azure root module."
  type = object({
    image          = string
    tag            = string
    port           = number
    host_port      = optional(number)
    entrypoint     = optional(list(string))
    command        = optional(list(string))
    env            = optional(map(string), {})
    uses_cosmos    = optional(bool, false)
    uses_snowflake = optional(bool, false)
    health_path    = optional(string)
    metrics_path   = optional(string, "/metrics")
    scrape_metrics = optional(bool, true)
    build = optional(object({
      context    = string
      dockerfile = optional(string, "Dockerfile")
      build_args = optional(map(string), {})
    }))
  })
}

variable "network_name" {
  description = "Docker network to attach the container to."
  type        = string
}

variable "otlp_endpoint" {
  description = "OTLP endpoint the app exports traces and metrics to."
  type        = string
}

variable "cosmos_env" {
  description = "Cosmos connection environment variables, injected when spec.uses_cosmos is true."
  type        = map(string)
  default     = {}
}

variable "snowflake_env" {
  description = "Snowflake connection environment variables, injected when spec.uses_snowflake is true."
  type        = map(string)
  default     = {}
}
