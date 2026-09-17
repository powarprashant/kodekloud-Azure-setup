output "resource_group_name" {
  value = data.azurerm_resource_group.sandbox.name
}

output "vm_name" {
  value = azurerm_windows_virtual_machine.vm.name
}

output "public_ip" {
  value = azurerm_public_ip.vm_pip.ip_address
}

output "admin_username" {
  value = var.admin_username
}

output "admin_password" {
  value     = local.admin_password
  sensitive = true
}

output "rdp_command" {
  value = "mstsc /v:${azurerm_public_ip.vm_pip.ip_address}"
}

output "rdp_file_path" {
  value = "${var.vm_name}.rdp"
}

output "credentials_file_path" {
  value = "${var.vm_name}_credentials.txt"
}
