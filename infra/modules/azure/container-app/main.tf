terraform {
  required_version = ">= 1.6"
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = ">= 4.81"
    }
  }
}

locals {
  # Same variable names the local Docker stack injects, so application code is
  # identical in both environments.
  injected_env = merge(
    {
      APP_NAME                 = var.name
      APP_ENV                  = var.environment
      PORT                     = tostring(var.spec.port)
      OTEL_SERVICE_NAME        = var.name
      OTEL_RESOURCE_ATTRIBUTES = "service.name=${var.name},deployment.environment=${var.environment}"
      AZURE_CLIENT_ID          = var.identity_client_id
    },
    var.spec.uses_cosmos ? var.cosmos_env : {},
    var.spec.uses_snowflake ? var.snowflake_env : {},
    var.extra_env,
    var.spec.env,
  )

  image = "${var.registry_login_server}/${var.spec.image}:${var.spec.tag}"
}

resource "azurerm_container_app" "this" {
  name                         = "ca-${var.base_name}-${var.name}"
  resource_group_name          = var.resource_group_name
  container_app_environment_id = var.container_app_environment_id
  revision_mode                = var.spec.revision_mode
  workload_profile_name        = var.spec.workload_profile_name
  tags                         = var.tags

  identity {
    type         = "UserAssigned"
    identity_ids = [var.identity_id]
  }

  registry {
    server   = var.registry_login_server
    identity = var.identity_id
  }

  # Secrets are pulled from Key Vault at revision start using the same identity,
  # so no secret value passes through Terraform state.
  dynamic "secret" {
    for_each = var.spec.key_vault_secrets
    content {
      name                = secret.key
      key_vault_secret_id = secret.value
      identity            = var.identity_id
    }
  }

  template {
    min_replicas = var.spec.min_replicas
    max_replicas = var.spec.max_replicas

    container {
      name    = var.name
      image   = local.image
      cpu     = var.spec.cpu
      memory  = var.spec.memory
      command = var.spec.entrypoint
      args    = var.spec.command

      dynamic "env" {
        for_each = local.injected_env
        content {
          name  = env.key
          value = env.value
        }
      }

      # Key Vault-backed secrets surface as environment variables by reference.
      dynamic "env" {
        for_each = var.spec.key_vault_secrets
        content {
          name        = upper(replace(env.key, "-", "_"))
          secret_name = env.key
        }
      }

      dynamic "liveness_probe" {
        for_each = var.spec.health_path == null ? [] : [var.spec.health_path]
        content {
          transport               = "HTTP"
          port                    = var.spec.port
          path                    = liveness_probe.value
          initial_delay           = 10
          interval_seconds        = 30
          failure_count_threshold = 3
        }
      }

      dynamic "readiness_probe" {
        for_each = var.spec.health_path == null ? [] : [var.spec.health_path]
        content {
          transport               = "HTTP"
          port                    = var.spec.port
          path                    = readiness_probe.value
          interval_seconds        = 10
          failure_count_threshold = 3
        }
      }
    }

    # Scale on concurrent requests for anything with ingress; scale-to-zero
    # applies when min_replicas is 0.
    dynamic "http_scale_rule" {
      for_each = var.spec.ingress_enabled && var.spec.concurrent_requests != null ? [1] : []
      content {
        name                = "http-concurrency"
        concurrent_requests = var.spec.concurrent_requests
      }
    }
  }

  dynamic "ingress" {
    for_each = var.spec.ingress_enabled ? [1] : []
    content {
      external_enabled           = var.spec.external_ingress
      target_port                = var.spec.port
      transport                  = "auto"
      allow_insecure_connections = false

      traffic_weight {
        percentage      = 100
        latest_revision = true
      }
    }
  }

  lifecycle {
    # The image tag is owned by the CI/CD pipeline after the first deploy;
    # Terraform manages the surrounding infrastructure, not the release.
    ignore_changes = [
      template[0].container[0].image,
    ]
  }
}
