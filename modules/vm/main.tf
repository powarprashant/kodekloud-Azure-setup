####################################################################
#
# Linux VM: public IP, NIC, and the VM itself.
#
# The subnet's NSG (SSH-only inbound) is attached at the subnet level
# by the network module, so nothing NSG-related lives here.
#
####################################################################

resource "azurerm_public_ip" "this" {
  count = var.enable_public_ip ? 1 : 0

  name                = "pip-${var.vm_name}"
  resource_group_name = var.resource_group_name
  location            = var.location
  allocation_method   = "Static"
  sku                 = "Standard"
  tags                = var.tags
}

resource "azurerm_network_interface" "this" {
  name                = "nic-${var.vm_name}"
  resource_group_name = var.resource_group_name
  location            = var.location
  tags                = var.tags

  ip_configuration {
    name                          = "internal"
    subnet_id                     = var.subnet_id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = var.enable_public_ip ? azurerm_public_ip.this[0].id : null
  }
}

resource "azurerm_linux_virtual_machine" "this" {
  name                = var.vm_name
  resource_group_name = var.resource_group_name
  location            = var.location
  size                = var.vm_size
  admin_username      = var.admin_username
  network_interface_ids = [
    azurerm_network_interface.this.id
  ]
  tags = var.tags

  # KodeKloud Sandbox note: password auth is disallowed by policy in most
  # sandboxes anyway - SSH key auth is both required and simplest here.
  disable_password_authentication = true

  admin_ssh_key {
    username   = var.admin_username
    public_key = var.ssh_public_key
  }

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = var.os_disk_type
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-jammy"
    sku       = "22_04-lts-gen2"
    version   = "latest"
  }

  # SystemAssigned identity so the VM can optionally be granted access to
  # other Azure resources (e.g. ACR) without embedding credentials on the
  # box. The identity itself costs nothing and needs no extra permissions
  # to create - only the optional role assignment below does.
  identity {
    type = "SystemAssigned"
  }
}

# KodeKloud Sandbox note: like the AKS AcrPull role assignment, this
# requires Microsoft.Authorization/roleAssignments/write, which sandboxes
# usually block. Off by default - see docs/sandbox-notes.md.
resource "azurerm_role_assignment" "vm_acr_pull" {
  count = var.enable_acr_role_assignment && var.acr_id != "" ? 1 : 0

  scope                = var.acr_id
  role_definition_name = "AcrPull"
  principal_id         = azurerm_linux_virtual_machine.this.identity[0].principal_id
}
