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
  description = "Name of the Windows virtual machine."
  default     = "vm-windows"
}

variable "vm_size" {
  type        = string
  description = "VM SKU for Windows Server. Standard_B2s (2 vCPU, 4GB RAM) is supported and sandbox-quota friendly."
  default     = "Standard_B2s"
}

variable "admin_username" {
  type        = string
  description = "Admin username for the VM."
  default     = "azureuser"
}

variable "admin_password" {
  type        = string
  description = "Administrator password. Leave empty to auto-generate a strong random password."
  default     = ""
  sensitive   = true
}

variable "os_disk_type" {
  type        = string
  description = "OS disk storage type (StandardSSD_LRS is sandbox friendly)."
  default     = "StandardSSD_LRS"
}

variable "os_disk_size_gb" {
  type        = number
  description = "Size of the OS disk in GB."
  default     = 127
}

variable "vnet_cidr" {
  type        = string
  description = "CIDR block for the Windows VM Virtual Network."
  default     = "10.30.0.0/16"
}

variable "vm_subnet_cidr" {
  type        = string
  description = "CIDR block for the VM Subnet."
  default     = "10.30.1.0/24"
}

variable "rdp_allowed_cidr" {
  type        = string
  description = "CIDR allowed to connect via RDP (port 3389) and OpenSSH (port 22)."
  default     = "*"
}

variable "tags" {
  type        = map(string)
  description = "Resource tags."
  default     = {}
}
