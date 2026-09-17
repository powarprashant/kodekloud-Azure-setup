####################################################################
#
# Virtual Network, Subnets & Network Security Group
#
# Kept intentionally minimal for KodeKloud Sandbox compatibility:
# no NAT Gateway, no Azure Firewall, no Bastion, no route tables.
# Every Azure NSG already denies inbound and allows outbound by
# default, so the VM's NSG only needs an explicit SSH allow rule.
#
####################################################################

resource "azurerm_virtual_network" "this" {
  name                = var.vnet_name
  resource_group_name = var.resource_group_name
  location            = var.location
  address_space       = var.vnet_address_space
  tags                = var.tags
}

resource "azurerm_subnet" "aks" {
  name                 = var.aks_subnet_name
  resource_group_name  = var.resource_group_name
  virtual_network_name = azurerm_virtual_network.this.name
  address_prefixes     = var.aks_subnet_address_prefix
}

resource "azurerm_subnet" "vm" {
  name                 = var.vm_subnet_name
  resource_group_name  = var.resource_group_name
  virtual_network_name = azurerm_virtual_network.this.name
  address_prefixes     = var.vm_subnet_address_prefix
}

resource "azurerm_network_security_group" "vm" {
  name                = "nsg-vm-${var.vm_subnet_name}"
  resource_group_name = var.resource_group_name
  location            = var.location
  tags                = var.tags

  security_rule {
    name                       = "AllowSSH"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefix      = var.ssh_allowed_cidr
    destination_address_prefix = "*"
  }
}

resource "azurerm_subnet_network_security_group_association" "vm" {
  subnet_id                 = azurerm_subnet.vm.id
  network_security_group_id = azurerm_network_security_group.vm.id
}
