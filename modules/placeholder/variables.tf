variable "location" {
  type        = string
  description = "Azure region where resources will be deployed."
}

variable "resource_group_name" {
  type        = string
  description = "Name of the resource group in which to deploy resources."
}

variable "tags" {
  type        = map(string)
  description = "Map of tags to apply to all resources managed by this module."
  default     = {}
}
