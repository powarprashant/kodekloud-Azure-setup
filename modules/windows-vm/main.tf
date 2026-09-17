resource "random_password" "admin_password" {
  count            = var.admin_password == "" ? 1 : 0
  length           = 18
  special          = true
  override_special = "!@#$%&*-_=+:?"
  min_lower        = 2
  min_upper        = 2
  min_numeric      = 2
  min_special      = 2
}

locals {
  admin_password = var.admin_password != "" ? var.admin_password : random_password.admin_password[0].result

  powershell_setup = <<-EOF
    <powershell>
    Add-WindowsCapability -Online -Name OpenSSH.Server~~~~0.0.1.0
    Start-Service sshd
    Set-Service -Name sshd -StartupType 'Automatic'
    New-NetFirewallRule -Name 'OpenSSH-Server-In-TCP' -DisplayName 'OpenSSH Server (sshd)' -Enabled True -Direction Inbound -Protocol TCP -Action Allow -LocalPort 22
    </powershell>
  EOF
}

resource "azurerm_public_ip" "pip" {
  count = var.enable_public_ip ? 1 : 0

  name                = "pip-${var.vm_name}"
  resource_group_name = var.resource_group_name
  location            = var.location
  allocation_method   = "Static"
  sku                 = "Standard"
  tags                = var.tags
}

resource "azurerm_network_interface" "nic" {
  name                = "nic-${var.vm_name}"
  resource_group_name = var.resource_group_name
  location            = var.location
  tags                = var.tags

  ip_configuration {
    name                          = "internal"
    subnet_id                     = var.subnet_id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = var.enable_public_ip ? azurerm_public_ip.pip[0].id : null
  }
}

resource "azurerm_windows_virtual_machine" "vm" {
  name                  = var.vm_name
  computer_name         = substr(var.computer_name, 0, 15)
  resource_group_name   = var.resource_group_name
  location              = var.location
  size                  = var.vm_size
  admin_username        = var.admin_username
  admin_password        = local.admin_password
  network_interface_ids = [azurerm_network_interface.nic.id]
  tags                  = var.tags

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = var.os_disk_type
    disk_size_gb         = var.os_disk_size_gb
  }

  source_image_reference {
    publisher = var.windows_os_publisher
    offer     = var.windows_os_offer
    sku       = var.windows_os_sku
    version   = var.windows_os_version
  }

  custom_data = var.enable_openssh ? base64encode(local.powershell_setup) : null

  identity {
    type = "SystemAssigned"
  }
}

resource "local_file" "rdp_file" {
  count = var.generate_rdp_file && var.enable_public_ip ? 1 : 0

  filename        = "${path.root}/${var.vm_name}.rdp"
  file_permission = "0600"
  content         = <<-EOT
    full address:s:${azurerm_public_ip.pip[0].ip_address}:3389
    username:s:${var.admin_username}
    prompt for credentials:i:1
    administrative session:i:1
    screen mode id:i:2
  EOT
}
