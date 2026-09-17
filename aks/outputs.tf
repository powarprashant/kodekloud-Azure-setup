output "resource_group_name" {
  description = "Sandbox resource group name"
  value       = data.azurerm_resource_group.sandbox.name
}

output "location" {
  description = "Resource group location"
  value       = data.azurerm_resource_group.sandbox.location
}

output "acr_name" {
  description = "Azure Container Registry name"
  value       = azurerm_container_registry.acr.name
}

output "acr_login_server" {
  description = "ACR login server URL"
  value       = azurerm_container_registry.acr.login_server
}

output "acr_admin_username" {
  description = "ACR admin username"
  value       = azurerm_container_registry.acr.admin_username
  sensitive   = true
}

output "acr_admin_password" {
  description = "ACR admin password"
  value       = azurerm_container_registry.acr.admin_password
  sensitive   = true
}

output "aks_cluster_name" {
  description = "AKS Cluster name"
  value       = azurerm_kubernetes_cluster.aks.name
}

output "aks_kubeconfig_command" {
  description = "Azure CLI command to obtain cluster kubeconfig"
  value       = "az aks get-credentials --resource-group ${data.azurerm_resource_group.sandbox.name} --name ${azurerm_kubernetes_cluster.aks.name} --overwrite-existing"
}
