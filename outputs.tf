output "resource_group_name" {
  value = module.resource_group.name
}

output "location" {
  value = module.resource_group.location
}

output "vnet_name" {
  value = module.network.vnet_name
}

output "vm_name" {
  value = module.vm.vm_name
}

output "vm_public_ip" {
  value = module.vm.public_ip_address
}

output "vm_ssh_command" {
  value = module.vm.public_ip_address != null ? "ssh -i ${var.vm_name}_ssh_key.pem ${var.vm_admin_username}@${module.vm.public_ip_address}" : "No public IP assigned (vm_enable_public_ip=false)."
}

output "ssh_private_key_path" {
  description = "Path to the generated private key, if one was generated (empty when you supplied your own ssh_public_key)."
  value       = var.ssh_public_key == "" ? "${var.vm_name}_ssh_key.pem" : ""
}

output "acr_name" {
  value = module.acr.name
}

output "acr_login_server" {
  value = module.acr.login_server
}

output "aks_cluster_name" {
  value = module.aks.name
}

output "aks_kubeconfig_command" {
  value = "az aks get-credentials --resource-group ${module.resource_group.name} --name ${module.aks.name}"
}

output "aks_acr_pull_role_assignment_created" {
  description = "Whether Terraform created the AcrPull role assignment. If false, use the ACR admin-credentials fallback documented in docs/sandbox-notes.md."
  value       = module.aks.acr_role_assignment_created
}

output "vm_principal_id" {
  description = "Object/principal ID of the VM's SystemAssigned identity - use this to grant it access to other Azure resources manually."
  value       = module.vm.principal_id
}
