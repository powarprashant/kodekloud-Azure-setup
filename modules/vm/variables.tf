variable "resource_group_name" {
  type        = string
  description = "Resource group to create the VM in."
}

variable "location" {
  type        = string
  description = "Azure region."
}

variable "vm_name" {
  type        = string
  description = "Name of the Linux VM."
}

variable "vm_size" {
  type        = string
  description = "VM SKU."
}

variable "admin_username" {
  type        = string
  description = "Admin username for the VM."
}

variable "ssh_public_key" {
  type        = string
  description = "SSH public key to install for admin_username."
}

variable "os_disk_type" {
  type        = string
  description = "OS disk storage account type."
}

variable "subnet_id" {
  type        = string
  description = "Subnet ID to attach the VM's NIC to."
}

variable "enable_public_ip" {
  type        = bool
  description = "Whether to attach a public IP to the VM."
}

variable "acr_id" {
  type        = string
  description = "ACR resource ID to grant the VM's identity AcrPull on. Empty string skips the role assignment entirely."
  default     = ""
}

variable "enable_acr_role_assignment" {
  type        = bool
  description = "Whether to create an AcrPull role assignment for the VM's SystemAssigned identity (requires Microsoft.Authorization/roleAssignments/write, usually blocked in the KodeKloud Sandbox)."
  default     = false
}

variable "tags" {
  type    = map(string)
  default = {}
}
