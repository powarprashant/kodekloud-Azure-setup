variable "subscription_id" {
  type        = string
  description = "Azure subscription ID. Leave blank to use active Azure CLI subscription."
  default     = ""
}

variable "resource_group_name" {
  type        = string
  description = "Pre-provisioned KodeKloud Sandbox Resource Group name."
  default     = ""
}

variable "location" {
  type        = string
  description = "Azure region."
  default     = "eastus"
}

variable "environment" {
  type        = string
  description = "Environment name."
  default     = "kodekloud"
}

variable "project_name" {
  type        = string
  description = "Project name prefix."
  default     = "kodekloud"
}

variable "acr_name" {
  type        = string
  description = "ACR registry name (alphanumeric only). If blank, auto-generated."
  default     = ""
}

variable "acr_sku" {
  type        = string
  description = "ACR SKU tier (Basic is lowest cost and sandbox safe)."
  default     = "Basic"
}

variable "aks_cluster_name" {
  type        = string
  description = "Name of the AKS cluster."
  default     = "aks-kodekloud"
}

variable "aks_dns_prefix" {
  type        = string
  description = "DNS prefix for the AKS API server. If blank, auto-generated."
  default     = ""
}

variable "kubernetes_version" {
  type        = string
  description = "Kubernetes version for AKS (empty string uses latest stable default)."
  default     = ""
}

variable "aks_vm_size" {
  type        = string
  description = "VM SKU for the AKS node pool. Standard_D2s_v3 is required by KodeKloud sandbox policy."
  default     = "Standard_D2s_v3"
}

variable "aks_system_node_count" {
  type        = number
  description = "Number of worker nodes for the AKS system node pool."
  default     = 1
}

variable "vnet_cidr" {
  type        = string
  description = "CIDR block for the AKS Virtual Network."
  default     = "10.10.0.0/16"
}

variable "aks_subnet_cidr" {
  type        = string
  description = "CIDR block for the AKS Subnet."
  default     = "10.10.1.0/24"
}

variable "tags" {
  type        = map(string)
  description = "Resource tags."
  default     = {}
}
