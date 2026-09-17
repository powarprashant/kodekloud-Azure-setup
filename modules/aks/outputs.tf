output "id" {
  value = azurerm_kubernetes_cluster.this.id
}

output "name" {
  value = azurerm_kubernetes_cluster.this.name
}

output "kubelet_identity_object_id" {
  description = "Object ID of the kubelet managed identity - grant this AcrPull manually if enable_acr_role_assignment=false."
  value       = azurerm_kubernetes_cluster.this.kubelet_identity[0].object_id
}

output "acr_role_assignment_created" {
  value = length(azurerm_role_assignment.acr_pull) > 0
}

output "kube_config_raw" {
  value     = azurerm_kubernetes_cluster.this.kube_config_raw
  sensitive = true
}
