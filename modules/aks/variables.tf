variable "resource_group_name" {
  type        = string
  description = "Resource group to create the cluster in."
}

variable "location" {
  type        = string
  description = "Azure region."
}

variable "cluster_name" {
  type        = string
  description = "Name of the AKS cluster."
}

variable "dns_prefix" {
  type        = string
  description = "DNS prefix for the AKS API server."
}

variable "kubernetes_version" {
  type        = string
  description = "Kubernetes version. Empty string uses the AKS default."
  default     = ""
}

variable "subnet_id" {
  type        = string
  description = "Subnet ID for the system (and optional user) node pool."
}

variable "network_plugin" {
  type        = string
  description = "kubenet or azure."
}

variable "system_vm_size" {
  type        = string
  description = "VM SKU for the system node pool."
}

variable "system_node_count" {
  type        = number
  description = "Number of nodes in the system node pool."
}

variable "enable_user_node_pool" {
  type        = bool
  description = "Whether to create an additional user node pool."
  default     = false
}

variable "user_vm_size" {
  type        = string
  description = "VM SKU for the user node pool."
  default     = ""
}

variable "user_node_count" {
  type        = number
  description = "Number of nodes in the user node pool."
  default     = 1
}

variable "acr_id" {
  type        = string
  description = "ACR resource ID to grant AcrPull to. Empty string skips the role assignment entirely."
  default     = ""
}

variable "enable_acr_role_assignment" {
  type        = bool
  description = "Whether to create the AcrPull role assignment (requires Microsoft.Authorization/roleAssignments/write, usually blocked in the KodeKloud Sandbox)."
  default     = false
}

variable "tags" {
  type    = map(string)
  default = {}
}
