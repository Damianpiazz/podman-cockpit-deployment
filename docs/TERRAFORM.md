# Terraform

## Que es

[Terraform](https://www.terraform.io/) es una herramienta de **infraestructura como codigo (IaC)** de HashiCorp. Permite definir, provisionar y gestionar recursos de cloud de forma declarativa y reproducible.

En este proyecto, Terraform crea y gestiona toda la infraestructura de Azure necesaria para alojar el stack de e-commerce.

---

## Archivos

| Archivo | Proposito |
|:--------|:----------|
| `terraform/providers.tf` | Providers requeridos (azurerm, random) y versiones |
| `terraform/variables.tf` | Inputs configurables con defaults |
| `terraform/main.tf` | Recursos de Azure (RG, VNet, NSG, VM, etc.) |
| `terraform/outputs.tf` | Valores de salida (IP, URLs, SSH key) |
| `terraform/scripts/setup.sh` | Cloud-init script ejecutado en la VM |
| `terraform/terraform.tfvars.example` | Ejemplo de variables para copiar |
| `terraform/validate.ps1` | Script de validacion HCL |

---

## Providers

```hcl
terraform {
  required_version = ">= 1.5.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }
}

provider "azurerm" {
  features {}
}
```

- `azurerm ~> 4.0` — provider oficial de Azure
- `random ~> 3.6` — para generar valores aleatorios (aunque actualmente no se usa activamente)

---

## Variables

| Variable | Tipo | Default | Descripcion |
|:---------|:-----|:--------|:------------|
| `resource_group_name` | string | `rg-podman-ecommerce` | Nombre del Resource Group |
| `location` | string | `East US` | Region de Azure |
| `vm_size` | string | `Standard_B2s` | Tamano de la VM (2 vCPU, 4GB) |
| `admin_username` | string | `azureuser` | Usuario admin de la VM |
| `vm_name` | string | `vm-podman-ecommerce` | Nombre de la VM |
| `environment` | string | `dev` | Entorno (dev, staging, prod) |
| `db_password` | string | **(requerido)** | Password de PostgreSQL (sensitive) |
| `repo_url` | string | URL del repo | URL del repositorio Git a clonar |

### Configurar variables

```bash
cd terraform
cp terraform.tfvars.example terraform.tfvars
```

Editar `terraform.tfvars`:

```hcl
db_password = "mi_password_seguro"
repo_url    = "https://github.com/TU_USUARIO/podman-cockpit-deployment.git"
```

---

## Recursos de Azure

### Cadena de dependencias

```
Resource Group
    └── Virtual Network (10.0.0.0/16)
            └── Subnet (10.0.1.0/24)
                    ├── Public IP (estatica)
                    ├── NSG (firewall rules)
                    └── NIC
                            └── VM (Ubuntu 24.04)
                                    ├── SSH Key (RSA 4096)
                                    └── custom_data → setup.sh
```

### Resource Group

```hcl
resource "azurerm_resource_group" "main" {
  name     = var.resource_group_name
  location = var.location
}
```

Contenedor logico que agrupa todos los recursos. Facilita limpieza con `terraform destroy`.

### Virtual Network + Subnet

```hcl
resource "azurerm_virtual_network" "main" {
  name                = "vnet-${var.vm_name}"
  address_space       = ["10.0.0.0/16"]
}

resource "azurerm_subnet" "main" {
  name                 = "subnet-main"
  address_prefixes     = ["10.0.1.0/24"]
}
```

Red virtual aislada para la VM. La subnet es donde vive la interfaz de red.

### NSG (Network Security Group)

```hcl
resource "azurerm_network_security_group" "main" {
  name = "nsg-${var.vm_name}"
}
```

Reglas de firewall inbound:

| Puerto | Servicio | Prioridad |
|:-------|:---------|:----------|
| 22 | SSH | 100 |
| 80 | HTTP | 200 |
| 443 | HTTPS | 300 |
| 9090 | Cockpit | 400 |

### VM

```hcl
resource "azurerm_linux_virtual_machine" "main" {
  name                = var.vm_name
  size                = var.vm_size        # Standard_B2s
  admin_username      = var.admin_username

  source_image_reference {
    publisher = "Canonical"
    offer     = "ubuntu-24_04-lts"
    sku       = "server"
    version   = "latest"
  }

  custom_data = base64encode(templatefile("${path.module}/scripts/setup.sh", {
    repo_url       = var.repo_url
    db_password    = var.db_password
    admin_username = var.admin_username
  }))
}
```

**custom_data** ejecuta `setup.sh` en el primer boot de la VM (cloud-init).

### SSH Key

```hcl
resource "tls_private_key" "ssh" {
  algorithm = "RSA"
  rsa_bits  = 4096
}
```

Terraform genera la clave SSH y la exporta como output. **En produccion, usar Azure Key Vault en vez de almacenarla en el state.**

---

## Outputs

| Output | Contenido |
|:-------|:----------|
| `public_ip_address` | IP publica de la VM |
| `vm_id` | ID completo de la VM |
| `ssh_private_key` | Clave SSH privada (sensitive) |
| `cockpit_url` | `https://<IP>:9090` |
| `site_url` | `https://<IP>` |

---

## Comandos

```bash
cd terraform

# Inicializar providers
terraform init

# Previsualizar cambios
terraform plan

# Aplicar cambios (crear recursos)
terraform apply

# Ver outputs
terraform output

# Ver IP publica
terraform output -raw public_ip_address

# Ver SSH key
terraform output -raw ssh_private_key > vm_key.pem

# Destruir todos los recursos
terraform destroy
```

---

## State management

El state se almacena localmente en `terraform/terraform.tfstate`.

> **Recomendacion para produccion:** usar un backend remoto (Azure Storage, Terraform Cloud) para compartir el state entre miembros del equipo y habilitar locking.

---

## Validacion

```bash
# Validar sintaxis HCL
terraform validate

# Formatear archivos
terraform fmt

# PowerShell (validacion custom)
.\validate.ps1
```

---

## Troubleshooting

```bash
# Ver logs de cloud-init en la VM
ssh -i vm_key.pem azureuser@<IP> "cat /var/log/setup-vm.log"

# Ver estado de provisionamiento
az vm show -g rg-podman-ecommerce -n vm-podman-ecommerce --query "provisioningState"

# Si terraform falla, revisar el state
terraform state list
terraform state show azurerm_linux_virtual_machine.main
```
