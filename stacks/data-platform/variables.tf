variable "subscription_id" {
  description = "Azure subscription that receives the resources."
  type        = string
}

variable "tenant_id" {
  description = "Microsoft Entra tenant."
  type        = string
}

variable "environment" {
  description = "Environment name."
  type        = string

  validation {
    condition     = contains(["dev", "uat", "prod"], var.environment)
    error_message = "The environment must be dev, uat or prod."
  }
}

variable "location" {
  description = "Azure region."
  type        = string
  default     = "westeurope"
}

variable "vnet_address_space" {
  description = "Address range of the virtual network."
  type        = list(string)
}

variable "data_lakes" {
  description = "Data lake storage accounts by short key, with their containers."
  type = map(object({
    containers = set(string)
  }))
}

variable "public_access_enabled" {
  description = "Allow public network access to the platform services. Allowed only in dev."
  type        = bool
  default     = false

  validation {
    condition     = !var.public_access_enabled || var.environment == "dev"
    error_message = "Public access can be turned on only in the dev environment."
  }
}
