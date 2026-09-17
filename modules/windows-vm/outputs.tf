output "vm_id" {
  description = "ID of the Windows VM"
  value       = azurerm_windows_virtual_machine.vm.id
}

output "vm_name" {
  description = "Name of the Windows VM"
  value       = azurerm_windows_virtual_machine.vm.name
}

output "public_ip_address" {
  description = "Public IP address of the Windows VM (or null if enable_public_ip=false)"
  value       = var.enable_public_ip ? azurerm_public_ip.pip[0].ip_address : null
}

output "private_ip_address" {
  description = "Private IP address of the Windows VM"
  value       = azurerm_network_interface.nic.private_ip_address
}

output "admin_username" {
  description = "Administrator username for RDP/SSH access"
  value       = var.admin_username
}

output "admin_password" {
  description = "Administrator password for RDP/SSH access"
  value       = local.admin_password
  sensitive   = true
}

output "rdp_command" {
  description = "Connection command for Windows Remote Desktop"
  value       = var.enable_public_ip ? "mstsc /v:${azurerm_public_ip.pip[0].ip_address}" : null
}

output "rdp_file_path" {
  description = "Path to the local .rdp shortcut file"
  value       = var.generate_rdp_file && var.enable_public_ip ? abspath(local_file.rdp_file[0].filename) : null
}
