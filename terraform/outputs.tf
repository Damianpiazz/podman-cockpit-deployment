output "public_ip_address" {
  description = "IP pública de la VM"
  value       = azurerm_public_ip.main.ip_address
}

output "vm_id" {
  description = "ID de la VM"
  value       = azurerm_linux_virtual_machine.main.id
}

output "ssh_private_key" {
  description = "Clave SSH privada (solo para dev — en prod usar Key Vault)"
  value       = tls_private_key.ssh.private_key_pem
  sensitive   = true
}

output "cockpit_url" {
  description = "URL de Cockpit"
  value       = "https://${azurerm_public_ip.main.ip_address}:9090"
}

output "site_url" {
  description = "URL del sitio web"
  value       = "https://${azurerm_public_ip.main.ip_address}"
}
