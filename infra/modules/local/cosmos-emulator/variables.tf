variable "container_name" {
  description = "Container name for the emulator."
  type        = string
  default     = "helloworld-cosmos"
}

variable "image" {
  description = <<-EOT
    Cosmos DB emulator image. The vnext-preview image is the lighter, faster
    default and works on arm64. Switch to
    mcr.microsoft.com/cosmosdb/linux/azure-cosmos-emulator:latest for the
    classic x86-64 emulator, and set publish_direct_ports = true with it.
  EOT
  type        = string
  default     = "mcr.microsoft.com/cosmosdb/linux/azure-cosmos-emulator:vnext-preview"
}

variable "network_name" {
  description = "Docker network to attach the emulator to."
  type        = string
}

variable "host_port" {
  description = "Host port mapped to the emulator gateway port (8081)."
  type        = number
  default     = 8081
}

variable "publish_direct_ports" {
  description = "Publish 10250-10255 as well. Required by the classic emulator image only."
  type        = bool
  default     = false
}

variable "partition_count" {
  description = "Number of physical partitions the emulator starts with. Higher values slow startup."
  type        = number
  default     = 3
}

variable "persist_data" {
  description = "Keep emulator data in a named volume across restarts."
  type        = bool
  default     = true
}

variable "database_name" {
  description = "Logical database name apps should use. Created by the application at startup."
  type        = string
}

variable "containers" {
  description = "Container names apps expect in the database, surfaced to apps as configuration."
  type        = list(string)
  default     = []
}
