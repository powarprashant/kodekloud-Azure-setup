output "vm_id" {
  value = azurerm_linux_virtual_machine.this.id
}

output "vm_name" {
  value = azurerm_linux_virtual_machine.this.name
}

output "public_ip_address" {
  description = "Public IP address of the VM, or null if enable_public_ip=false."
  value       = var.enable_public_ip ? azurerm_public_ip.this[0].ip_address : null
}

output "private_ip_address" {
  value = azurerm_network_interface.this.private_ip_address
}

output "principal_id" {
  description = "Object/principal ID of the VM's SystemAssigned identity - grant it access to other Azure resources manually if enable_acr_role_assignment=false."
  value       = azurerm_linux_virtual_machine.this.identity[0].principal_id
}

output "acr_role_assignment_created" {
  value = length(azurerm_role_assignment.vm_acr_pull) > 0
}
