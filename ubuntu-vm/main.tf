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

  ssh_public_key = var.ssh_public_key != "" ? var.ssh_public_key : tls_private_key.vm_key[0].public_key_openssh

  cloud_init = <<-EOF
    #cloud-config
    package_update: true
    packages:
      - apt-transport-https
      - ca-certificates
      - curl
      - gnupg
      - lsb-release
      - git
      - jq
      - unzip
      - htop
      - build-essential
      - docker.io
      - docker-compose-v2

    runcmd:
      - systemctl enable docker
      - systemctl start docker
      - usermod -aG docker ${var.admin_username}
      - sysctl -w vm.max_map_count=524288
      - sysctl -w fs.file-max=131072
      - echo -e "vm.max_map_count=524288\nfs.file-max=131072" > /etc/sysctl.d/99-sonarqube.conf
      - sysctl --system
      - curl -fsSL -o /usr/local/bin/kubectl "https://dl.k8s.io/release/v1.31.0/bin/linux/amd64/kubectl"
      - chmod +x /usr/local/bin/kubectl
      - curl -sL https://aka.ms/InstallAzureCLIDeb | bash
  EOF
}

data "azurerm_resource_group" "sandbox" {
  name = var.resource_group_name
}

resource "tls_private_key" "vm_key" {
  count     = var.ssh_public_key == "" ? 1 : 0
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "local_file" "private_key" {
  count           = var.ssh_public_key == "" ? 1 : 0
  filename        = "${path.root}/${var.vm_name}_key.pem"
  content         = tls_private_key.vm_key[0].private_key_pem
  file_permission = "0600"
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
    name                       = "AllowAllInbound"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = var.ssh_allowed_cidr
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

resource "azurerm_linux_virtual_machine" "vm" {
  name                  = var.vm_name
  resource_group_name   = data.azurerm_resource_group.sandbox.name
  location              = data.azurerm_resource_group.sandbox.location
  size                  = var.vm_size
  admin_username        = var.admin_username
  network_interface_ids = [azurerm_network_interface.vm_nic.id]
  tags                  = local.common_tags

  disable_password_authentication = true

  admin_ssh_key {
    username   = var.admin_username
    public_key = local.ssh_public_key
  }

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = var.os_disk_type
    disk_size_gb         = var.os_disk_size_gb
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-jammy"
    sku       = "22_04-lts-gen2"
    version   = "latest"
  }

  custom_data = base64encode(local.cloud_init)

  identity {
    type = "SystemAssigned"
  }
}
