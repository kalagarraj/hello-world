terraform {
  required_version = ">= 1.6"
  required_providers {
    docker = {
      source  = "kreuzwerker/docker"
      version = ">= 3.0"
    }
  }
}

# The emulator ships a well-known, publicly documented development key. It is
# not a secret: every Cosmos DB emulator instance in the world uses it, and it
# only ever unlocks a container on the developer's own machine.
locals {
  well_known_key = "C2y6yDjf5/R+ob0N8A7Cgv30VRDJIWEHLM+4QDU5DE2nQ9nDuVTqobD4b8mGGyPMbIZnqyMsEcaGQy67XIw/Jw=="
  endpoint       = "https://${var.container_name}:8081"
  connection_string = join(";", [
    "AccountEndpoint=${local.endpoint}/",
    "AccountKey=${local.well_known_key}",
  ])
}

resource "docker_image" "cosmos" {
  name         = var.image
  keep_locally = true
}

resource "docker_volume" "data" {
  count = var.persist_data ? 1 : 0
  name  = "${var.container_name}-data"
}

resource "docker_container" "cosmos" {
  name     = var.container_name
  image    = docker_image.cosmos.image_id
  restart  = "unless-stopped"
  must_run = true

  env = [
    "AZURE_COSMOS_EMULATOR_PARTITION_COUNT=${var.partition_count}",
    "AZURE_COSMOS_EMULATOR_ENABLE_DATA_PERSISTENCE=${var.persist_data}",
    "AZURE_COSMOS_EMULATOR_IP_ADDRESS_OVERRIDE=127.0.0.1",
    "PROTOCOL=https",
  ]

  networks_advanced {
    name    = var.network_name
    aliases = ["cosmos"]
  }

  ports {
    internal = 8081
    external = var.host_port
  }

  # The classic emulator image also needs the direct-mode port range published;
  # the vnext image serves everything over the gateway port alone.
  dynamic "ports" {
    for_each = var.publish_direct_ports ? range(10250, 10256) : []
    content {
      internal = ports.value
      external = ports.value
    }
  }

  dynamic "volumes" {
    for_each = docker_volume.data
    content {
      volume_name    = volumes.value.name
      container_path = "/tmp/cosmos/appdata"
    }
  }

  labels {
    label = "com.hello-world.role"
    value = "cosmos"
  }
}
