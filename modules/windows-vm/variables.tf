variable "resource_group_name" {
  type        = string
  description = "Resource group where the Windows VM will be created."
}

variable "location" {
  type        = string
  description = "Azure region."
}

variable "vm_name" {
  type        = string
  description = "Name of the Windows virtual machine."
  default     = "win-vm-01"
}

variable "computer_name" {
  type        = string
  description = "NetBIOS computer name (max 15 characters)."
  default     = "win-server"
}

variable "vm_size" {
  type        = string
  description = "VM SKU. Standard_B2s (2 vCPU, 4GB RAM) or Standard_D2s_v3 (2 vCPU, 8GB RAM)."
  default     = "Standard_B2s"
}

variable "admin_username" {
  type        = string
  description = "Admin username for the VM."
  default     = "azureuser"
}

variable "admin_password" {
  type        = string
  description = "Admin password. Leave empty to auto-generate a secure random password."
  default     = ""
  sensitive   = true
}

variable "subnet_id" {
  type        = string
  description = "Subnet ID where the VM NIC will be attached."
}

variable "enable_public_ip" {
  type        = bool
  description = "Whether to associate a public IP address with the VM."
  default     = true
}

variable "os_disk_type" {
  type        = string
  description = "Storage account type for the OS disk (StandardSSD_LRS recommended for sandboxes)."
  default     = "StandardSSD_LRS"
}

variable "os_disk_size_gb" {
  type        = number
  description = "Size of the OS disk in GB."
  default     = 127
}

variable "windows_os_publisher" {
  type        = string
  description = "Publisher of the Windows OS image."
  default     = "MicrosoftWindowsServer"
}

variable "windows_os_offer" {
  type        = string
  description = "Offer of the Windows OS image."
  default     = "WindowsServer"
}

variable "windows_os_sku" {
  type        = string
  description = "SKU of the Windows OS image (e.g. 2022-datacenter-azure-edition, 2022-Datacenter, 2019-Datacenter)."
  default     = "2022-datacenter-azure-edition"
}

variable "windows_os_version" {
  type        = string
  description = "Version of the Windows OS image."
  default     = "latest"
}

variable "enable_openssh" {
  type        = bool
  description = "Whether to auto-install and enable OpenSSH Server via custom_data."
  default     = true
}

variable "generate_rdp_file" {
  type        = bool
  description = "Whether to generate a local .rdp shortcut file."
  default     = true
}

variable "tags" {
  type        = map(string)
  description = "Resource tags."
  default     = {}
}
