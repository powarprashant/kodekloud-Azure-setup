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

  features {
    resource_group {
      # KodeKloud Sandbox note: the sandbox resource group is pre-populated
      # and cannot be created/destroyed by Terraform, so we never manage its
      # lifecycle directly (see modules/resource-group).
      prevent_deletion_if_contains_resources = false
    }
  }
}
