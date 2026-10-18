output "zone_ids" {
  description = "Zone IDs by zone name."
  value       = { for name, zone in azurerm_private_dns_zone.this : name => zone.id }
}
