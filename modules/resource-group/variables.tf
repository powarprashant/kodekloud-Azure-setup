variable "create_resource_group" {
  type        = bool
  description = "Whether to create a new resource group or use an existing one."
}

variable "resource_group_name" {
  type        = string
  description = "Name of the resource group to use or create. Empty string triggers auto-detection (existing) or the default name (create)."
}

variable "location" {
  type        = string
  description = "Azure region (only used when create_resource_group=true)."
}

variable "tags" {
  type        = map(string)
  description = "Tags to apply (only used when create_resource_group=true)."
  default     = {}
}
