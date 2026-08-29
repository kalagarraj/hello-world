terraform {
  required_version = ">= 1.6"
  required_providers {
    docker = {
      source  = "kreuzwerker/docker"
      version = ">= 3.0"
    }
  }
}

locals {
  image_ref = "${var.spec.image}:${var.spec.tag}"

  # Platform-neutral wiring injected on both local and Azure so application
  # code reads the same variable names in either environment.
  injected_env = merge(
    {
      APP_NAME                    = var.name
      APP_ENV                     = "local"
      PORT                        = tostring(var.spec.port)
      OTEL_EXPORTER_OTLP_ENDPOINT = var.otlp_endpoint
      OTEL_SERVICE_NAME           = var.name
      OTEL_RESOURCE_ATTRIBUTES    = "service.name=${var.name},deployment.environment=local"
    },
    var.spec.uses_cosmos ? var.cosmos_env : {},
    var.spec.uses_snowflake ? var.snowflake_env : {},
    var.spec.env,
  )
}

# `build` is set when the app is compiled from a Dockerfile in this repo,
# otherwise the image is pulled from a registry.
resource "docker_image" "this" {
  name         = local.image_ref
  keep_locally = true

  dynamic "build" {
    for_each = var.spec.build == null ? [] : [var.spec.build]
    content {
      context    = build.value.context
      dockerfile = build.value.dockerfile
      build_args = build.value.build_args
    }
  }
}

resource "docker_container" "this" {
  name     = "${var.name_prefix}${var.name}"
  image    = docker_image.this.image_id
  restart  = "unless-stopped"
  must_run = true

  entrypoint = var.spec.entrypoint
  command    = var.spec.command

  env = [for k, v in local.injected_env : "${k}=${v}"]

  networks_advanced {
    name    = var.network_name
    aliases = [var.name]
  }

  # Only externally reachable apps publish a host port; the rest stay on the
  # bridge network and are reached by container name.
  dynamic "ports" {
    for_each = var.spec.host_port == null ? [] : [var.spec.host_port]
    content {
      internal = var.spec.port
      external = ports.value
    }
  }

  labels {
    label = "com.hello-world.stack"
    value = var.name_prefix
  }

  labels {
    label = "com.hello-world.role"
    value = "app"
  }

  # Set health_path only for images that carry wget or curl; the probe reports
  # unhealthy rather than failing the apply, so a missing tool is only noise.
  dynamic "healthcheck" {
    for_each = var.spec.health_path == null ? [] : [var.spec.health_path]
    content {
      test = [
        "CMD-SHELL",
        "wget -q -O /dev/null http://localhost:${var.spec.port}${healthcheck.value} || curl -fsS -o /dev/null http://localhost:${var.spec.port}${healthcheck.value} || exit 1",
      ]
      interval     = "15s"
      timeout      = "5s"
      retries      = 3
      start_period = "20s"
    }
  }
}
