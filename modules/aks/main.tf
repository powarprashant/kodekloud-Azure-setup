####################################################################
#
# AKS cluster
#
# KodeKloud Sandbox compatibility choices:
#   - kubenet (default) instead of Azure CNI: kubenet needs no extra
#     subnet-level permissions and consumes far fewer IPs per node,
#     which matters on a sandbox's typically small subnet quota.
#   - SystemAssigned identity: no user-assigned identity to create or
#     manage separately.
#   - AcrPull role assignment is opt-in (enable_acr_role_assignment)
#     because it requires Microsoft.Authorization/roleAssignments/write,
#     which the sandbox usually blocks. See docs/sandbox-notes.md for
#     the ACR-admin-credentials fallback.
#
####################################################################

resource "azurerm_kubernetes_cluster" "this" {
  name                = var.cluster_name
  resource_group_name = var.resource_group_name
  location            = var.location
  dns_prefix          = var.dns_prefix
  kubernetes_version  = var.kubernetes_version != "" ? var.kubernetes_version : null
  tags                = var.tags

  default_node_pool {
    name           = "system"
    vm_size        = var.system_vm_size
    node_count     = var.system_node_count
    vnet_subnet_id = var.subnet_id
  }

  identity {
    type = "SystemAssigned"
  }

  network_profile {
    network_plugin = var.network_plugin
  }

  role_based_access_control_enabled = true
}

resource "azurerm_kubernetes_cluster_node_pool" "user" {
  count = var.enable_user_node_pool ? 1 : 0

  name                  = "user"
  kubernetes_cluster_id = azurerm_kubernetes_cluster.this.id
  vm_size               = var.user_vm_size
  node_count            = var.user_node_count
  vnet_subnet_id        = var.subnet_id
  mode                  = "User"
  tags                  = var.tags
}

resource "azurerm_role_assignment" "acr_pull" {
  count = var.enable_acr_role_assignment && var.acr_id != "" ? 1 : 0

  scope                = var.acr_id
  role_definition_name = "AcrPull"
  principal_id         = azurerm_kubernetes_cluster.this.kubelet_identity[0].object_id
}
