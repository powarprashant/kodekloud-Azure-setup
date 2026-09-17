####################################################################
#
# Resource Group - create or reuse
#
# KodeKloud Azure Sandbox does not allow creating additional resource
# groups. It pre-provisions exactly one (commonly named "ODL-azure-*").
# When create_resource_group=false (the default), this module reuses
# that existing resource group instead of trying to create a new one.
#
# The azurerm provider has no "list all resource groups" data source,
# so auto-detection of the sandbox's pre-provisioned resource group
# happens in scripts/setup.sh (which exports TF_VAR_resource_group_name
# before terraform runs) rather than inside Terraform itself. Running
# `terraform plan`/`apply` directly without that script requires
# resource_group_name to be set explicitly.
#
####################################################################

resource "azurerm_resource_group" "this" {
  count = var.create_resource_group ? 1 : 0

  name     = var.resource_group_name != "" ? var.resource_group_name : "rg-kodekloud-devops"
  location = var.location
  tags     = var.tags
}

data "azurerm_resource_group" "existing" {
  count = var.create_resource_group ? 0 : 1

  name = var.resource_group_name

  lifecycle {
    precondition {
      condition     = var.resource_group_name != ""
      error_message = "resource_group_name is empty. Run ./scripts/setup.sh to auto-detect your KodeKloud Sandbox resource group, or set resource_group_name explicitly in terraform.tfvars (find it with `az group list -o table`). See docs/sandbox-notes.md."
    }
  }
}
