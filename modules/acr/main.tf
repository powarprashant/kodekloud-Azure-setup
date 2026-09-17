####################################################################
#
# Azure Container Registry
#
# Basic SKU only - Premium features (geo-replication, private
# endpoints, customer-managed keys) are unnecessary for a sandbox
# lab and some are outright blocked by sandbox policy.
#
####################################################################

resource "azurerm_container_registry" "this" {
  name                = var.acr_name
  resource_group_name = var.resource_group_name
  location            = var.location
  sku                 = var.sku

  # KodeKloud Sandbox note: admin credentials are the fallback path for
  # AKS -> ACR image pulls when Microsoft.Authorization/roleAssignments/write
  # (needed for a proper AcrPull role assignment) is blocked. See
  # docs/sandbox-notes.md.
  admin_enabled = var.admin_enabled

  tags = var.tags
}
