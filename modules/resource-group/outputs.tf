output "name" {
  description = "Resolved resource group name (created or existing)."
  value       = var.create_resource_group ? azurerm_resource_group.this[0].name : data.azurerm_resource_group.existing[0].name
}

output "location" {
  description = "Resolved resource group location (created or existing)."
  value       = var.create_resource_group ? azurerm_resource_group.this[0].location : data.azurerm_resource_group.existing[0].location
}

output "id" {
  description = "Resolved resource group ID (created or existing)."
  value       = var.create_resource_group ? azurerm_resource_group.this[0].id : data.azurerm_resource_group.existing[0].id
}
