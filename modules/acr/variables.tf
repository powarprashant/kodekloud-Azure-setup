variable "resource_group_name" {
  type        = string
  description = "Resource group to create the registry in."
}

variable "location" {
  type        = string
  description = "Azure region."
}

variable "acr_name" {
  type        = string
  description = "Globally-unique ACR name (alphanumeric only)."
}

variable "sku" {
  type        = string
  description = "ACR SKU."
}

variable "admin_enabled" {
  type        = bool
  description = "Enable ACR admin credentials (used as the sandbox-safe AKS image-pull fallback)."
}

variable "tags" {
  type    = map(string)
  default = {}
}
