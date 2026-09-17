####################################################################
#
# Variables used. All have KodeKloud Azure Sandbox-friendly defaults.
#
####################################################################

variable "subscription_id" {
  type        = string
  description = "Azure subscription ID. Leave empty to use the subscription currently selected via `az account set`."
  default     = ""
}

variable "location" {
  type        = string
  description = "Azure region to deploy into."
  default     = "eastus"
}

variable "environment" {
  type        = string
  description = "Environment tag applied to all resources."
  default     = "kodekloud"
}

variable "project_name" {
  type        = string
  description = "Short project name used to build resource names. Lowercase alphanumeric and hyphens only."
  default     = "kodekloud"

  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.project_name))
    error_message = "project_name must be lowercase alphanumeric characters and hyphens only."
  }
}

variable "tags" {
  type        = map(string)
  description = "Additional tags to merge with the default common tags."
  default     = {}
}

####################################################################
# Resource Group
#
# KodeKloud Azure Sandbox note: the sandbox does NOT allow creating
# additional resource groups (Microsoft.Resources/subscriptions/resourceGroups
# write is blocked). A single resource group (often named like
# "ODL-azure-XXXXXXXX") is pre-provisioned for you. By default this repo
# looks up and reuses that existing resource group instead of creating one.
#
# On a personal/full-permission subscription, set create_resource_group=true
# to have Terraform create it instead.
####################################################################

variable "create_resource_group" {
  type        = bool
  description = "Whether to create a new resource group (true) or use an existing one (false, KodeKloud Sandbox default)."
  default     = false
}

variable "resource_group_name" {
  type        = string
  description = "Name of the resource group to use or create. Leave empty to auto-detect the sole pre-existing resource group (sandbox) or to use the generated default name (when create_resource_group=true)."
  default     = ""
}

####################################################################
# Networking
####################################################################

variable "vnet_address_space" {
  type        = list(string)
  description = "Address space for the virtual network."
  default     = ["10.0.0.0/16"]
}

variable "aks_subnet_address_prefix" {
  type        = list(string)
  description = "Address prefix for the AKS subnet."
  default     = ["10.0.1.0/24"]
}

variable "vm_subnet_address_prefix" {
  type        = list(string)
  description = "Address prefix for the VM subnet."
  default     = ["10.0.2.0/24"]
}

variable "ssh_allowed_cidr" {
  type        = string
  description = "CIDR allowed to reach the VM over SSH (port 22). Restrict this to your own IP/32 where possible."
  default     = "*"
}

####################################################################
# Azure VM
####################################################################

variable "vm_name" {
  type        = string
  description = "Name of the Linux VM."
  default     = "vm-kodekloud"
}

variable "vm_size" {
  type        = string
  description = "VM SKU. Keep small/cheap for sandbox usage."
  default     = "Standard_B1s"
}

variable "vm_admin_username" {
  type        = string
  description = "Admin username for the VM."
  default     = "azureuser"

  validation {
    condition = !contains(
      ["administrator", "admin", "user", "user1", "test", "user2", "test1", "user3",
        "1", "123", "a", "actuser", "adm", "aspnet", "backup",
        "console", "david", "guest", "john", "owner", "root", "server", "sql",
      "support", "support_388945a0", "sys", "test2", "test3", "user4", "user5"],
      lower(var.vm_admin_username)
    )
    error_message = "vm_admin_username is on Azure's reserved/disallowed username list for VMs. Pick another value (e.g. azureuser)."
  }
}

variable "vm_os_disk_type" {
  type        = string
  description = "OS disk storage account type. KodeKloud Sandbox policy disallows Premium disks - keep Standard/StandardSSD."
  default     = "StandardSSD_LRS"
}

variable "vm_enable_public_ip" {
  type        = bool
  description = "Whether to attach a public IP to the VM."
  default     = true
}

variable "ssh_public_key" {
  type        = string
  description = "SSH public key to install on the VM. Leave empty to have Terraform generate a new keypair (saved locally, never committed)."
  default     = ""
}

####################################################################
# Azure Container Registry (ACR)
####################################################################

variable "acr_name" {
  type        = string
  description = "Globally-unique ACR name (alphanumeric only, 5-50 chars). Leave empty to auto-generate one."
  default     = ""

  validation {
    condition     = var.acr_name == "" || can(regex("^[a-zA-Z0-9]{5,50}$", var.acr_name))
    error_message = "acr_name must be 5-50 characters, letters and digits only (no hyphens/underscores), or left empty to auto-generate."
  }
}

variable "acr_sku" {
  type        = string
  description = "ACR SKU. Basic is sufficient and cheapest for sandbox usage."
  default     = "Basic"
}

variable "acr_admin_enabled" {
  type        = bool
  description = "Enable ACR admin credentials. Used as the KodeKloud Sandbox-safe fallback for AKS image pulls when role assignments are blocked."
  default     = true
}

####################################################################
# AKS
####################################################################

variable "aks_cluster_name" {
  type        = string
  description = "Name of the AKS cluster."
  default     = "aks-kodekloud"
}

variable "aks_dns_prefix" {
  type        = string
  description = "DNS prefix for the AKS cluster's API server. Leave empty to auto-generate a unique one."
  default     = ""

  validation {
    condition     = var.aks_dns_prefix == "" || can(regex("^[a-zA-Z][a-zA-Z0-9-]{0,52}[a-zA-Z0-9]$", var.aks_dns_prefix))
    error_message = "aks_dns_prefix must be 2-54 characters, start with a letter, end with a letter or digit, and contain only letters, digits, and hyphens - or left empty to auto-generate."
  }
}

variable "kubernetes_version" {
  type        = string
  description = "Kubernetes version for the AKS control plane and node pools. Leave empty to use the AKS default supported version."
  default     = ""
}

variable "aks_vm_size" {
  type        = string
  description = "VM SKU for the AKS system node pool. Standard_B2s is confirmed to work in the KodeKloud Azure Sandbox."
  default     = "Standard_B2s"
}

variable "aks_system_node_count" {
  type        = number
  description = "Number of nodes in the system node pool."
  default     = 1
}

variable "aks_enable_user_node_pool" {
  type        = bool
  description = "Whether to create an additional user node pool alongside the system node pool."
  default     = false
}

variable "aks_user_vm_size" {
  type        = string
  description = "VM SKU for the AKS user node pool (only used when aks_enable_user_node_pool=true)."
  default     = "Standard_B2s"
}

variable "aks_user_node_count" {
  type        = number
  description = "Number of nodes in the user node pool (only used when aks_enable_user_node_pool=true)."
  default     = 1
}

variable "aks_network_plugin" {
  type        = string
  description = "AKS network plugin. kubenet has the smallest permission/subnet footprint and is the most sandbox-compatible; azure is also supported."
  default     = "kubenet"

  validation {
    condition     = contains(["kubenet", "azure"], var.aks_network_plugin)
    error_message = "aks_network_plugin must be either \"kubenet\" or \"azure\"."
  }
}

variable "enable_acr_role_assignment" {
  type        = bool
  description = "Whether Terraform should create the AcrPull role assignment granting AKS's kubelet identity pull access to ACR. KodeKloud Azure Sandbox blocks Microsoft.Authorization/roleAssignments/write, so this defaults to false there - use the ACR admin-credentials fallback instead (see docs/sandbox-notes.md). Set true on a subscription where you have Owner/User Access Administrator."
  default     = false
}

variable "vm_enable_acr_role_assignment" {
  type        = bool
  description = "Whether Terraform should grant the VM's SystemAssigned identity AcrPull access to ACR. Same Microsoft.Authorization/roleAssignments/write requirement and sandbox restriction as enable_acr_role_assignment - off by default since the lab VM has no current need to pull from ACR."
  default     = false
}
