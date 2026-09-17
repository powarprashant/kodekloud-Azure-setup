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

  admin_password = var.admin_password != "" ? var.admin_password : random_password.win_password[0].result

  powershell_setup = <<-EOF
    <powershell>
    # Enable OpenSSH Server on Windows Server
    Add-WindowsCapability -Online -Name OpenSSH.Server~~~~0.0.1.0
    Start-Service sshd
    Set-Service -Name sshd -StartupType 'Automatic'
    New-NetFirewallRule -Name 'OpenSSH-Server-In-TCP' -DisplayName 'OpenSSH Server (sshd)' -Enabled True -Direction Inbound -Protocol TCP -Action Allow -LocalPort 22
    </powershell>
  EOF
}

data "azurerm_resource_group" "sandbox" {
  name = var.resource_group_name
}

resource "random_password" "win_password" {
  count            = var.admin_password == "" ? 1 : 0
  length           = 18
  special          = true
  override_special = "!@#$%&*-_=+:?"
  min_lower        = 2
  min_upper        = 2
  min_numeric      = 2
  min_special      = 2
}

resource "azurerm_virtual_network" "vm_vnet" {
  name                = "vnet-${var.vm_name}"
  resource_group_name = data.azurerm_resource_group.sandbox.name
  location            = data.azurerm_resource_group.sandbox.location
  address_space       = [var.vnet_cidr]
  tags                = local.common_tags
}

resource "azurerm_subnet" "vm_subnet" {
  name                 = "snet-${var.vm_name}"
  resource_group_name  = data.azurerm_resource_group.sandbox.name
  virtual_network_name = azurerm_virtual_network.vm_vnet.name
  address_prefixes     = [var.vm_subnet_cidr]
}

resource "azurerm_network_security_group" "vm_nsg" {
  name                = "nsg-${var.vm_name}"
  resource_group_name = data.azurerm_resource_group.sandbox.name
  location            = data.azurerm_resource_group.sandbox.location
  tags                = local.common_tags

  security_rule {
    name                       = "AllowRDP"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "3389"
    source_address_prefix      = var.rdp_allowed_cidr
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "AllowSSH"
    priority                   = 110
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefix      = var.rdp_allowed_cidr
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "AllowWinRM"
    priority                   = 120
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_ranges    = ["5985", "5986"]
    source_address_prefix      = var.rdp_allowed_cidr
    destination_address_prefix = "*"
  }
}

resource "azurerm_subnet_network_security_group_association" "vm_nsg_assoc" {
  subnet_id                 = azurerm_subnet.vm_subnet.id
  network_security_group_id = azurerm_network_security_group.vm_nsg.id
}

resource "azurerm_public_ip" "vm_pip" {
  name                = "pip-${var.vm_name}"
  resource_group_name = data.azurerm_resource_group.sandbox.name
  location            = data.azurerm_resource_group.sandbox.location
  allocation_method   = "Static"
  sku                 = "Standard"
  tags                = local.common_tags
}

resource "azurerm_network_interface" "vm_nic" {
  name                = "nic-${var.vm_name}"
  resource_group_name = data.azurerm_resource_group.sandbox.name
  location            = data.azurerm_resource_group.sandbox.location
  tags                = local.common_tags

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.vm_subnet.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.vm_pip.id
  }
}

resource "azurerm_windows_virtual_machine" "vm" {
  name                  = var.vm_name
  computer_name         = "win-server"
  resource_group_name   = data.azurerm_resource_group.sandbox.name
  location              = data.azurerm_resource_group.sandbox.location
  size                  = var.vm_size
  admin_username        = var.admin_username
  admin_password        = local.admin_password
  network_interface_ids = [azurerm_network_interface.vm_nic.id]
  tags                  = local.common_tags

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = var.os_disk_type
    disk_size_gb         = var.os_disk_size_gb
  }

  source_image_reference {
    publisher = "MicrosoftWindowsServer"
    offer     = "WindowsServer"
    sku       = "2022-datacenter-azure-edition"
    version   = "latest"
  }

  custom_data = base64encode(local.powershell_setup)

  identity {
    type = "SystemAssigned"
  }
}

resource "local_file" "credentials" {
  filename        = "${path.root}/${var.vm_name}_credentials.txt"
  file_permission = "0600"
  content         = <<-EOT
    === Windows VM Credentials ===
    VM Name: ${var.vm_name}
    Public IP: ${azurerm_public_ip.vm_pip.ip_address}
    Username: ${var.admin_username}
    Password: ${local.admin_password}
    RDP Command: mstsc /v:${azurerm_public_ip.vm_pip.ip_address}
  EOT
}

resource "local_file" "rdp_file" {
  filename        = "${path.root}/${var.vm_name}.rdp"
  file_permission = "0600"
  content         = <<-EOT
    full address:s:${azurerm_public_ip.vm_pip.ip_address}:3389
    username:s:${var.admin_username}
    prompt for credentials:i:1
    administrative session:i:1
  EOT
}
