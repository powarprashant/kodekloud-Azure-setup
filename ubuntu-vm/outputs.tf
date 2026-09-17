output "resource_group_name" {
  value = data.azurerm_resource_group.sandbox.name
}

output "vm_name" {
  value = azurerm_linux_virtual_machine.vm.name
}

output "public_ip" {
  value = azurerm_public_ip.vm_pip.ip_address
}

output "private_ip" {
  value = azurerm_network_interface.vm_nic.private_ip_address
}

output "ssh_command" {
  value = "ssh -i ${var.vm_name}_key.pem ${var.admin_username}@${azurerm_public_ip.vm_pip.ip_address}"
}

output "ssh_private_key_path" {
  value = var.ssh_public_key == "" ? "${var.vm_name}_key.pem" : "Pre-existing public key used"
}
