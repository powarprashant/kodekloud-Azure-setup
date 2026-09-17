####################################################################
#
# Provider configuration
#
# Authentication uses your existing `az login` session (Azure CLI).
# No credentials, client secrets, or service principals are stored
# in this repository or in Terraform state.
#
####################################################################

provider "azurerm" {
  # Falls back to the currently selected `az account set --subscription ...`
  # subscription when left unset.
  subscription_id = var.subscription_id != "" ? var.subscription_id : null

  # Explicit for clarity - this is also the default behaviour when no
  # other auth method (service principal env vars, OIDC, etc.) is configured.
  use_cli = true

  # KodeKloud Sandbox note: users do not have permissions to register Azure
  # resource providers at the subscription level (triggers 403 AuthorizationFailed).
  # All required resource providers (Compute, Network, ContainerRegistry, ContainerService, Resources)
  # are pre-registered by the sandbox.
  resource_provider_registrations = "none"

  features {
    resource_group {
      # KodeKloud Sandbox note: the sandbox resource group is pre-populated
      # and cannot be created/destroyed by Terraform, so we never manage its
      # lifecycle directly (see modules/resource-group).
      prevent_deletion_if_contains_resources = false
    }
  }
}
