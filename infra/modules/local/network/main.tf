terraform {
  required_version = ">= 1.6"
  required_providers {
    docker = {
      source  = "kreuzwerker/docker"
      version = ">= 3.0"
    }
  }
}

# A single user-defined bridge network so every container in the stack can
# resolve the others by container name (app -> cosmos, otel -> loki, ...).
resource "docker_network" "this" {
  name   = var.name
  driver = "bridge"

  ipam_config {
    subnet = var.subnet
  }
}
