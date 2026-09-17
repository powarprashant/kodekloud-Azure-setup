provider "azurerm" {
  subscription_id = var.subscription_id != "" ? var.subscription_id : null
  use_cli         = true

  # KodeKloud Sandbox note: prevent 403 Forbidden registration errors
  resource_provider_registrations = "none"

  features {
    resource_group {
      prevent_deletion_if_contains_resources = false
    }
  }
}
