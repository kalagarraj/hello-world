terraform {
  required_version = ">= 1.6"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.81"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.5"
    }
  }

  # Remote state. Fill in via -backend-config, e.g.
  #   terraform init -backend-config=backend.dev.hcl
  # and delete this block to fall back to local state.
  backend "azurerm" {}
}

provider "azurerm" {
  subscription_id = var.subscription_id

  features {
    key_vault {
      # Recover a soft-deleted vault instead of failing the apply.
      recover_soft_deleted_key_vaults = true
      purge_soft_delete_on_destroy    = false
    }
    resource_group {
      prevent_deletion_if_contains_resources = true
    }
  }
}
