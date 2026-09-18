variable "subscription_id" {
  type        = string
  description = "Azure subscription ID. Leave blank to use active Azure CLI subscription."
  default     = ""
}

variable "resource_group_name" {
  type        = string
  description = "Pre-provisioned KodeKloud Sandbox Resource Group name."
  default     = ""
}

variable "location" {
  type        = string
  description = "Azure region."
  default     = "eastus"
}

variable "environment" {
  type        = string
  description = "Environment name."
  default     = "kodekloud"
}

variable "project_name" {
  type        = string
  description = "Project name prefix."
  default     = "kodekloud"
}

variable "vm_name" {
  type        = string
  description = "Name of the Linux virtual machine."
  default     = "vm-ubuntu"
}

variable "vm_size" {
  type        = string
  description = "VM SKU. Standard_B2s (2 vCPU, 4GB RAM) provides ample memory for Docker & SonarQube."
  default     = "Standard_B2s"
}

variable "admin_username" {
  type        = string
  description = "Admin username for the VM."
  default     = "azureuser"
}

variable "ssh_public_key" {
  type        = string
  description = "SSH public key. Leave empty to auto-generate a private/public keypair."
  default     = ""
}

variable "os_disk_type" {
  type        = string
  description = "OS disk storage type (StandardSSD_LRS is sandbox friendly)."
  default     = "StandardSSD_LRS"
}

variable "os_disk_size_gb" {
  type        = number
  description = "Size of the OS disk in GB."
  default     = 30
}

variable "vnet_cidr" {
  type        = string
  description = "CIDR block for the Ubuntu VM Virtual Network."
  default     = "10.20.0.0/16"
}

variable "vm_subnet_cidr" {
  type        = string
  description = "CIDR block for the VM Subnet."
  default     = "10.20.1.0/24"
}

variable "ssh_allowed_cidr" {
  type        = string
  description = "CIDR allowed to connect to the VM inbound (defaults to '*' allowing all traffic)."
  default     = "*"
}

variable "tags" {
  type        = map(string)
  description = "Resource tags."
  default     = {}
}
