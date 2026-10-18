variable "zone_names" {
  description = "Private DNS zones to create, for example privatelink.blob.core.windows.net."
  type        = list(string)

  validation {
    condition     = alltrue([for zone in var.zone_names : startswith(zone, "privatelink.")])
    error_message = "Every zone must be a privatelink zone."
  }
}

variable "resource_group_name" {
  description = "Resource group that holds the zones."
  type        = string
}

variable "virtual_network_id" {
  description = "Virtual network that resolves names through the zones."
  type        = string
}

variable "tags" {
  description = "Tags for all resources."
  type        = map(string)
  default     = {}
}
