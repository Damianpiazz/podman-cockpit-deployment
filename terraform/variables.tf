variable "resource_group_name" {
  description = "Nombre del Resource Group"
  type        = string
  default     = "rg-podman-ecommerce"
}

variable "location" {
  description = "Región de Azure"
  type        = string
  default     = "South Africa North"
}

variable "vm_size" {
  description = "Tamaño de la VM"
  type        = string
  default     = "Standard_B2s"
}

variable "admin_username" {
  description = "Usuario admin de la VM"
  type        = string
  default     = "azureuser"
}

variable "vm_name" {
  description = "Nombre de la VM"
  type        = string
  default     = "vm-podman-ecommerce"
}

variable "environment" {
  description = "Entorno (dev, staging, prod)"
  type        = string
  default     = "dev"
}

variable "repo_url" {
  description = "URL del repositorio Git a clonar en la VM"
  type        = string
  default     = "https://github.com/TU_USUARIO/podman-cockpit-deployment.git"
}
