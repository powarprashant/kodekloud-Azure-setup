variable "resource_group_name" {
  type        = string
  description = "Resource group to create networking resources in."
}

variable "location" {
  type        = string
  description = "Azure region."
}

variable "vnet_name" {
  type        = string
  description = "Name of the virtual network."
}

variable "vnet_address_space" {
  type        = list(string)
  description = "Address space for the virtual network."
}

variable "aks_subnet_name" {
  type        = string
  description = "Name of the AKS subnet."
}

variable "aks_subnet_address_prefix" {
  type        = list(string)
  description = "Address prefix for the AKS subnet."
}

variable "vm_subnet_name" {
  type        = string
  description = "Name of the VM subnet."
}

variable "vm_subnet_address_prefix" {
  type        = list(string)
  description = "Address prefix for the VM subnet."
}

variable "ssh_allowed_cidr" {
  type        = string
  description = "CIDR allowed to reach the VM subnet over SSH (port 22)."
}

variable "tags" {
  type    = map(string)
  default = {}
}
