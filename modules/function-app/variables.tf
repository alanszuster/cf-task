variable "name" {
  description = "Function app name."
  type        = string
}

variable "resource_group_name" {
  description = "Resource group that holds the function app."
  type        = string
}

variable "location" {
  description = "Azure region."
  type        = string
}

variable "storage_account_name" {
  description = "Storage account the function app uses for its runtime."
  type        = string
}

variable "storage_account_id" {
  description = "ID of that storage account."
  type        = string
}

variable "python_version" {
  description = "Python version of the runtime."
  type        = string
  default     = "3.12"
}

variable "public_network_access_enabled" {
  description = "Allow access to the app from the public internet."
  type        = bool
  default     = true
}

variable "virtual_network_subnet_id" {
  description = "Subnet for outbound VNet integration, delegated to Microsoft.Web/serverFarms. Null for none."
  type        = string
  default     = null

  validation {
    condition     = var.virtual_network_subnet_id == null || var.virtual_network_subnet_id != ""
    error_message = "Use null, not an empty string, to turn VNet integration off."
  }
}

variable "app_settings" {
  description = "Application settings."
  type        = map(string)
  default     = {}
}

variable "tags" {
  description = "Tags for all resources."
  type        = map(string)
  default     = {}
}
