####################################################################
#
# Root module: wires resource-group -> network -> vm / acr -> aks
#
# One `terraform apply` provisions the entire lab environment.
#
####################################################################

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
}

# Short random suffix for globally-unique names (ACR, AKS DNS prefix)
# when the user leaves them blank.
resource "random_id" "suffix" {
  byte_length = 3
}

module "resource_group" {
  source = "./modules/resource-group"

  create_resource_group = var.create_resource_group
  resource_group_name   = var.resource_group_name
  location              = var.location
  tags                  = local.common_tags
}

module "network" {
  source = "./modules/network"

  resource_group_name       = module.resource_group.name
  location                  = module.resource_group.location
  vnet_name                 = "vnet-${var.project_name}"
  vnet_address_space        = var.vnet_address_space
  aks_subnet_name           = "snet-aks-${var.project_name}"
  aks_subnet_address_prefix = var.aks_subnet_address_prefix
  vm_subnet_name            = "snet-vm-${var.project_name}"
  vm_subnet_address_prefix  = var.vm_subnet_address_prefix
  ssh_allowed_cidr          = var.ssh_allowed_cidr
  tags                      = local.common_tags
}

####################################################################
# SSH key: use the supplied public key, or generate one and save the
# private key locally (git-ignored, never stored in Terraform state
# as anything other than this resource's own attribute).
####################################################################

resource "tls_private_key" "generated" {
  count = var.ssh_public_key == "" ? 1 : 0

  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "local_file" "generated_private_key" {
  count = var.ssh_public_key == "" ? 1 : 0

  filename        = "${path.module}/${var.vm_name}_ssh_key.pem"
  content         = tls_private_key.generated[0].private_key_pem
  file_permission = "0600"
}

locals {
  ssh_public_key = var.ssh_public_key != "" ? var.ssh_public_key : tls_private_key.generated[0].public_key_openssh

  # ACR names may only contain letters and digits (no hyphens/underscores),
  # unlike most other Azure resource names - and project_name is explicitly
  # allowed to contain hyphens - so the generated default must be sanitized
  # rather than interpolated directly, or a hyphenated project_name would
  # produce an invalid ACR name at apply time.
  acr_name_generated = substr(
    lower(replace("acr${var.project_name}${random_id.suffix.hex}", "/[^a-zA-Z0-9]/", "")),
    0, 50
  )
}

module "acr" {
  source = "./modules/acr"

  resource_group_name = module.resource_group.name
  location            = module.resource_group.location
  acr_name            = var.acr_name != "" ? var.acr_name : local.acr_name_generated
  sku                 = var.acr_sku
  admin_enabled       = var.acr_admin_enabled
  tags                = local.common_tags
}

module "vm" {
  source = "./modules/vm"

  resource_group_name        = module.resource_group.name
  location                   = module.resource_group.location
  vm_name                    = var.vm_name
  vm_size                    = var.vm_size
  admin_username             = var.vm_admin_username
  ssh_public_key             = local.ssh_public_key
  os_disk_type               = var.vm_os_disk_type
  subnet_id                  = module.network.vm_subnet_id
  enable_public_ip           = var.vm_enable_public_ip
  acr_id                     = module.acr.id
  enable_acr_role_assignment = var.vm_enable_acr_role_assignment
  tags                       = local.common_tags
}

module "aks" {
  source = "./modules/aks"

  resource_group_name        = module.resource_group.name
  location                   = module.resource_group.location
  cluster_name               = var.aks_cluster_name
  dns_prefix                 = var.aks_dns_prefix != "" ? var.aks_dns_prefix : "${var.aks_cluster_name}-${random_id.suffix.hex}"
  kubernetes_version         = var.kubernetes_version
  subnet_id                  = module.network.aks_subnet_id
  network_plugin             = var.aks_network_plugin
  system_vm_size             = var.aks_vm_size
  system_node_count          = var.aks_system_node_count
  enable_user_node_pool      = var.aks_enable_user_node_pool
  user_vm_size               = var.aks_user_vm_size
  user_node_count            = var.aks_user_node_count
  acr_id                     = module.acr.id
  enable_acr_role_assignment = var.enable_acr_role_assignment
  tags                       = local.common_tags
}
