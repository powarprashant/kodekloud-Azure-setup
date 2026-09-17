output "id" {
  value = azurerm_container_registry.this.id
}

output "name" {
  value = azurerm_container_registry.this.name
}

output "login_server" {
  value = azurerm_container_registry.this.login_server
}

output "admin_username" {
  value     = var.admin_enabled ? azurerm_container_registry.this.admin_username : null
  sensitive = true
}

output "admin_password" {
  value     = var.admin_enabled ? azurerm_container_registry.this.admin_password : null
  sensitive = true
}
