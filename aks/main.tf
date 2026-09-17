locals {
  common_tags = merge(
    {
      Environment = var.environment
      Project     = var.project_name
      ManagedBy   = "terraform"
      Owner       = "kodekloud"
    },
    var.tags
  )

  # ACR names require alphanumeric only (no hyphens/underscores), max 50 chars
  acr_name_generated = substr(
    lower(replace("acr${var.project_name}${random_id.suffix.hex}", "/[^a-zA-Z0-9]/", "")),
    0, 50
  )
}

resource "random_id" "suffix" {
  byte_length = 3
}

data "azurerm_resource_group" "sandbox" {
  name = var.resource_group_name
}

resource "azurerm_virtual_network" "aks_vnet" {
  name                = "vnet-aks-${var.project_name}"
  resource_group_name = data.azurerm_resource_group.sandbox.name
  location            = data.azurerm_resource_group.sandbox.location
  address_space       = [var.vnet_cidr]
  tags                = local.common_tags
}

resource "azurerm_subnet" "aks_subnet" {
  name                 = "snet-aks-${var.project_name}"
  resource_group_name  = data.azurerm_resource_group.sandbox.name
  virtual_network_name = azurerm_virtual_network.aks_vnet.name
  address_prefixes     = [var.aks_subnet_cidr]
}

resource "azurerm_container_registry" "acr" {
  name                = var.acr_name != "" ? var.acr_name : local.acr_name_generated
  resource_group_name = data.azurerm_resource_group.sandbox.name
  location            = data.azurerm_resource_group.sandbox.location
  sku                 = var.acr_sku
  admin_enabled       = true
  tags                = local.common_tags
}

resource "azurerm_kubernetes_cluster" "aks" {
  name                = var.aks_cluster_name
  resource_group_name = data.azurerm_resource_group.sandbox.name
  location            = data.azurerm_resource_group.sandbox.location
  dns_prefix          = var.aks_dns_prefix != "" ? var.aks_dns_prefix : "${var.aks_cluster_name}-${random_id.suffix.hex}"
  kubernetes_version  = var.kubernetes_version != "" ? var.kubernetes_version : null

  default_node_pool {
    name           = "system"
    vm_size        = var.aks_vm_size
    node_count     = var.aks_system_node_count
    vnet_subnet_id = azurerm_subnet.aks_subnet.id
  }

  identity {
    type = "SystemAssigned"
  }

  network_profile {
    network_plugin = "kubenet"
  }

  role_based_access_control_enabled = true
  tags                              = local.common_tags
}
