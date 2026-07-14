# Informe de Despliegue — Next.js Commerce en Azure

| Campo        | Valor |
|--------------|-------|
| **Nombre**   | Damian Piazza |
| **Legajo**   | 33400 |
| **Repositorio** | https://github.com/Damianpiazz/podman-cockpit-deployment.git |
| **IP de la VM** | 20.164.202.187 |

---

## 1. Objetivo

Desplegar un frontend Next.js Commerce (Vercel Commerce, respaldado por Shopify) en una máquina virtual de Azure utilizando Terraform para la infraestructura, Podman para la contenedorización y Cockpit para la gestión del servidor.

**Arquitectura final:** Nginx como reverse proxy con terminación SSL → frontend Next.js, todo containerizado con Podman y administrado mediante Cockpit en el puerto 9090.

---

## 2. Arquitectura final

### 2.1 Infraestructura

| Componente | Detalle |
|------------|---------|
| **VM** | Azure VM Ubuntu 24.04, Standard_D2s_v3 |
| **Región** | South Africa North |
| **Red** | VNet con subnet, NSG con reglas HTTP/HTTPS/SSH |

### 2.2 Contenedores

| Contenedor | Imagen base | Puertos | Función |
|------------|-------------|---------|---------|
| `nginx-ecommerce` | nginx:1.27-alpine | 80, 443 | Terminación SSL, proxy reverso a `127.0.0.1:3000` |
| `nextjs-ecommerce` | Node 20 Alpine (multi-stage) | 3000 | Vercel Commerce, frontend Next.js |

Ambos contenedores utilizan `network_mode: host`, compartiendo el namespace de red de la VM. Esta fue la solución definitiva tras problemas de resolución DNS entre contenedores.

### 2.3 Servicios

- **Cockpit** (puerto 9090): Panel de administración web para gestionar la VM y los contenedores (con plugin `cockpit-podman`).
- **Terraform**: Gestiona toda la infraestructura de Azure (VM, VNet, NSG, NIC, IP pública).

---

## 3. Estructura del repositorio

| Archivo | Descripción |
|---------|-------------|
| `terraform/main.tf` | Define los recursos de Azure: Resource Group, VNet, Subnet, NSG, reglas de seguridad, NIC e IP pública. |
| `terraform/providers.tf` | Configura el provider `azurerm` con `resource_provider_registrations = "none"` (requerido para suscripciones de estudiantes). |
| `terraform/variables.tf` | Variables de entrada: `vm_size`, `location`, `admin_username`. |
| `terraform/terraform.tfvars` | Valores concretos: `Standard_D2s_v3`, `South Africa North`. |
| `terraform/scripts/setup.sh` | Script cloud-init que ejecuta al crear la VM: instala Podman, podman-compose, Cockpit, configura el registro de docker.io y marca directorios como seguros para Git. |
| `compose.yml` | Define los servicios `nginx` y `nextjs` con `network_mode: host`. |
| `frontend/Dockerfile` | Build multi-stage: base con pnpm@9, instalación de dependencias, builder con `pnpm build`, runner con output standalone de Next.js. |
| `frontend/` | Código fuente de Vercel Commerce (clonado de https://github.com/vercel/commerce.git, directorio `.git` eliminado). |
| `nginx/Dockerfile` | Imagen `nginx:1.27-alpine` con configuración personalizada. |
| `nginx/conf.d/default.conf` | Configuración de server block: redirect HTTP→HTTPS, SSL con certificado autofirmado, `proxy_pass` a `127.0.0.1:3000`. |
| `nginx/nginx.conf` | Configuración principal de Nginx. |

---

## 4. Paso a paso de ejecución

A continuación se describe cada paso del despliegue, incluyendo los comandos utilizados, su propósito y los problemas encontrados durante el proceso.

### 4.1 Login en Azure

```bash
az login
```

**Qué hace:** Autentica al usuario con Azure CLI. Selecciona automáticamente la suscripción "Azure for Students" bajo el tenant de UTN FRLP. Abre el navegador para completar el flujo de autenticación.

### 4.2 Terraform Init

```bash
cd terraform
terraform init
```

**Qué hace:** Inicializa el directorio de trabajo de Terraform. Descarga los providers necesarios:
- `azurerm` v4.81.0 (proveedor de Azure)
- `random` v3.9.0 (generación de nombres aleatorios)
- `tls` v4.3.0 (generación de claves SSH)

Crea el archivo `.terraform.lock.hcl` que bloquea las versiones de los providers para reproducibilidad.

### 4.3 Terraform Plan — Error de registro de providers

```bash
terraform plan
```

**Qué hace:** Analiza los archivos de configuración y genera un plan de ejecución sin modificar recursos reales. Muestra qué recursos serán creados, modificados o eliminados.

> **PROBLEMA 1: Error de registro de Resource Providers**
>
> ```
> Error: ConflictingConcurrentWriteNotAllowed
> ```
>
> **Causa:** La suscripción "Azure for Students" tiene permisos limitados que impiden el registro automático de resource providers. Terraform intenta registrar providers como `Microsoft.Network` y `Microsoft.Compute`, pero la suscripción lo bloquea.
>
> **Solución:** Se agregó `resource_provider_registrations = "none"` al bloque `provider "azurerm"` en `terraform/providers.tf`. Esto le indica a Terraform que no intente registrar providers, asumiendo que ya están registrados en la suscripción.

### 4.4 Terraform Apply — Error de tamaño de VM

```bash
terraform apply
```

**Qué hace:** Ejecuta el plan de Terraform, creando todos los recursos definidos en los archivos `.tf`. Primero solicita confirmación del plan y luego procede a crear cada recurso secuencialmente.

Se crearon exitosamente: Resource Group, VNet, Subnet, NSG, reglas de seguridad, NIC e IP pública. Sin embargo, la creación de la VM falló.

> **PROBLEMA 2: VM Standard_B2s no disponible**
>
> ```
> Error: SkuNotAvailable: Standard_B2s is currently not available in location SouthAfricaNorth
> ```
>
> **Causa:** Las VMs de la serie B (con CPU bursting) no están disponibles para suscripciones de estudiantes en la región South Africa North por restricciones de capacidad.
>
> **Solución:** Se cambió el valor de `vm_size` en `terraform.tfvars` de `Standard_B2s` a `Standard_D2s_v3`. Se ejecutó nuevamente `terraform apply` para completar la creación de la VM.

### 4.5 Conexión SSH — Error de permisos

```bash
ssh azureuser@20.164.202.187 -i ~/.ssh/azure_vm.pem
```

**Qué hace:** Establece una conexión SSH segura a la VM utilizando la clave privada generada por Terraform. El parámetro `-i` especifica la ruta al archivo de clave privada.

> **PROBLEMA 3: SSH Permission Denied**
>
> ```
> Load key: error in libcrypto
> Permission denied (publickey)
> ```
>
> **Causa:** Terraform en Windows creó el archivo `.pem` con permisos demasiado abiertos. Los clientes SSH rechazan claves cuyo archivo de permisos no es estrictamente `600` (solo lectura/escritura para el propietario).
>
> **Solución:** Se ejecutó `chmod 600 ~/.ssh/azure_vm.pem` para restringir los permisos. Luego la conexión SSH funcionó correctamente.

### 4.6 Script de configuración — Múltiples errores

El script `setup.sh` se ejecuta automáticamente vía cloud-init al crear la VM. Se monitoreó con:

```bash
tail -f /var/log/setup-vm.log
```

**Qué hace:** Muestra en tiempo real las últimas líneas del log de configuración, permitiendo verificar si el script completó exitosamente o si hubo errores.

Se encontraron varios problemas durante la ejecución del setup:

> **PROBLEMA 4: podman-compose no encontrado**
>
> ```
> podman-compose: command not found
> ```
>
> **Causa:** El script `setup.sh` no incluía la instalación de `podman-compose`, solo instalaba `podman`.
>
> **Solución:** Se instaló manualmente con `sudo apt-get install -y podman-compose` y se actualizó `setup.sh` para incluirlo en futuras ejecuciones.

> **PROBLEMA 5: Podman no resuelve nombres cortos de imágenes**
>
> ```
> Error: short-name "nginx" did not resolve to an alias and no unqualified-search registries are defined
> ```
>
> **Causa:** Podman en Ubuntu 24.04 no viene configurado con registros de búsqueda implícitos. A diferencia de Docker, Podman requiere configuración explícita para resolver nombres cortos como `nginx` a `docker.io/library/nginx`.
>
> **Solución:** Se creó el archivo `/etc/containers/registries.conf.d/docker-io.conf` con el contenido:
>
> ```
> unqualified-search-registries = ["docker.io"]
> ```

> **PROBLEMA 6: Error de propiedad de Git ("dubious ownership")**
>
> ```
> fatal: detected dubious ownership in repository at '/opt/podman-cockpit-deployment'
> ```
>
> **Causa:** El repositorio fue clonado por el usuario `root` (durante cloud-init) pero se intenta acceder desde el usuario `azureuser`. Git verifica que el directorio del repositorio pertenezca al usuario actual.
>
> **Solución:** Se ejecutó `sudo git config --global --add safe.directory /opt/podman-cockpit-deployment` para marcar el directorio como seguro.

> **PROBLEMA 7: Imagen Docker de Medusa eliminada**
>
> ```
> Error: reading manifest latest in docker.io/medusajs/medusa: requested access to the resource is denied
> ```
>
> **Causa:** La etiqueta `latest` de la imagen `medusajs/medusa` fue eliminada de Docker Hub como parte de la migración a Medusa v2. La imagen ya no está disponible públicamente.
>
> **Solución:** Se simplificó toda la arquitectura eliminando el backend Medusa, PostgreSQL y Redis. Se actualizó `compose.yml`, los Dockerfiles y la configuración de Nginx para soportar únicamente el frontend.

### 4.7 Primer despliegue del frontend (Medusa Storefront)

Tras la simplificación, se desplegó el frontend basado en Medusa. El build completó exitosamente, pero:

> **PROBLEMA 8: El middleware de Next.js falla sin backend Medusa**
>
> ```
> Error: middleware.ts requires MEDUSA_BACKEND_URL
> ```
>
> **Causa:** El middleware del storefront de Medusa (`middleware.ts`) intenta hacer fetch de las regiones disponibles desde el backend de Medusa durante la generación estática. Sin un backend configurado, el middleware lanza errores 500.
>
> **Solución:** Se reemplazó todo el frontend con Vercel Commerce (https://github.com/vercel/commerce.git), que está diseñado para funcionar de forma independiente con Shopify como backend.

### 4.8 Despliegue de Vercel Commerce

Se clonó el repositorio de Vercel Commerce en el directorio `frontend/`, se eliminó el directorio `.git` y se creó un Dockerfile multi-stage con pnpm@9.

> **PROBLEMA 9: pnpm@latest requiere Node 22**
>
> ```
> Error: ERR_UNKNOWN_BUILTIN_MODULE: No such built-in module: node:sqlite
> ```
>
> **Causa:** pnpm en su versión más reciente (v11) requiere Node.js 22+, pero se utiliza Node.js 20 Alpine como base del Dockerfile.
>
> **Solución:** Se fijó la versión a `pnpm@9` en el Dockerfile con `npm install -g pnpm@9`.

> **PROBLEMA 10: Build falla por consulta a Shopify con dominio placeholder**
>
> Durante el build de Next.js, el framework intenta hacer fetch de datos desde el dominio configurado en `SHOPIFY_STORE_DOMAIN`. Con el valor por defecto `"placeholder.myshopify.com"`, la consulta retorna 404 y Next.js falla al generar la página `/_not-found`.
>
> **Solución:** Se configuró `SHOPIFY_STORE_DOMAIN=""` (cadena vacía). La base de código de Vercel Commerce incluye guards del tipo `if (!endpoint)` que retornan datos vacíos cuando no hay un dominio de Shopify configurado, permitiendo que el build complete sin errores.

> **PROBLEMA 11: Directorio `public/` falta en el build**
>
> ```
> COPY --from=builder /app/public ./public: no such file or directory
> ```
>
> **Causa:** Git no rastrea directorios vacíos. El directorio `frontend/public/` existía en el repositorio original pero al clonar y eliminar `.git`, el directorio vacío no se preservó.
>
> **Solución:** Se agregó un archivo `.gitkeep` dentro de `frontend/public/` para que Git preserve el directorio.

### 4.9 Problemas de resolución DNS — El mayor desafío

Después de que ambos contenedores estuvieran ejecutándose, Nginx retornaba errores 502 Bad Gateway.

> **PROBLEMA 12: Podman Aardvark-DNS no resuelve nombres de contenedores desde Alpine/musl**
>
> ```
> curl: (6) Could not resolve host: nextjs
> ```
>
> **Causa:** El contenedor de Nginx (basado en Alpine, que usa la libc musl) no puede resolver el hostname `nextjs` a través del DNS interno de Podman (Aardvark-DNS). Se verificó que:
> - `getent hosts nextjs` no retornaba nada
> - `ping nextjs` fallaba
> - `nslookup nextjs 10.89.0.1` excedía el tiempo de espera
> - Pero la dirección IP funcionaba: `wget http://10.89.0.17:3000` retornaba HTML válido
>
> Esta es una incompatibilidad conocida entre el resolver DNS de musl libc y Aardvark-DNS de Podman.
>
> **Intentos fallidos:**
> 1. Agregar `resolver 10.89.0.1` en la configuración de Nginx → sigue con 502, timeout de DNS
> 2. Usar `set $nextjs_upstream http://nextjs:3000` con resolver → mismo problema
>
> **Solución definitiva:** Se cambió a `network_mode: host` para ambos contenedores. En este modo, los contenedores comparten el namespace de red de la VM. Nginx hace proxy a `127.0.0.1:3000` en lugar de `http://nextjs:3000`, eliminando completamente la necesidad de resolución DNS entre contenedores.

> **PROBLEMA 13: Next.js se vincula a una IP específica en lugar de todas las interfaces**
>
> Después del cambio a `network_mode: host`, Next.js solo escuchaba en la IP interna de la VM (no en `0.0.0.0`), por lo que Nginx no podía conectar.
>
> **Causa:** Next.js por defecto usa el hostname del contenedor como dirección de enlace. En modo host, esto resulta en la IP de la VM en lugar de `0.0.0.0`.
>
> **Solución:** Se agregó la variable de entorno `HOSTNAME=0.0.0.0` al contenedor de Next.js en `compose.yml`.

### 4.10 Configuración de Cockpit

Cockpit fue instalado mediante el script `setup.sh`:

```bash
sudo apt-get install -y cockpit cockpit-podman
```

**Qué hace:** Instala el panel de administración web Cockpit y el plugin `cockpit-podman` para gestionar contenedores Podman desde la interfaz gráfica.

```bash
sudo systemctl enable --now cockpit.socket
```

**Qué hace:** Habilita e inicia el socket de Cockpit. El servicio escucha en el puerto 9090 y se activa bajo demanda cuando se accede por primera vez.

No se configuró contraseña durante la creación de la VM (solo se usó clave SSH).

> **PROBLEMA 14: Login de Cockpit falla**
>
> **Causa:** La VM fue creada únicamente con clave SSH, sin contraseña de administrador. Cockpit requiere una contraseña para autenticar usuarios.
>
> **Solución:** Se configuró una contraseña para el usuario `azureuser` con `sudo passwd azureuser`. Esta contraseña se utiliza para acceder a Cockpit.

---

## 5. Puertos expuestos

| Puerto | URL | Servicio | Qué se ve |
|--------|-----|----------|-----------|
| 80 | http://20.164.202.187 | Nginx HTTP | Redirect 301 a HTTPS |
| 443 | https://20.164.202.187 | Nginx HTTPS | Vercel Commerce (cert autofirmado) |
| 3000 | http://20.164.202.187:3000 | Next.js directo | Mismo contenido sin SSL |
| 9090 | https://20.164.202.187:9090 | Cockpit | Panel de administración (user: azureuser) |

> **Nota de seguridad:** El puerto 3000 está expuesto directamente debido al uso de `network_mode: host`. En un entorno de producción, se recomendaría restringir el acceso a este puerto mediante NSG rules o firewall interno.

---

## 6. Problemas encontrados y soluciones

| #  | Problema | Causa | Solución |
|----|----------|-------|----------|
| 1  | Terraform provider registration error | Student subscription limits | `resource_provider_registrations = "none"` |
| 2  | VM size Standard_B2s unavailable | Capacity restrictions in SA North | Changed to Standard_D2s_v3 |
| 3  | SSH Permission Denied | .pem file permissions on Windows | `chmod 600 ~/.ssh/azure_vm.pem` |
| 4  | podman-compose not found | setup.sh didn't install it | Added to setup.sh + manual install |
| 5  | Podman short-name resolution | No unqualified-search-registries configured | Created docker-io.conf |
| 6  | Git dubious ownership | Root cloned, azureuser accessing | `git config --global --add safe.directory` |
| 7  | Medusa Docker image removed | medusajs/medusa:latest deleted from Docker Hub | Removed Medusa, simplified to frontend-only |
| 8  | Next.js middleware 500 errors | Middleware requires Medusa backend | Replaced frontend with Vercel Commerce |
| 9  | pnpm@latest Node 22 required | pnpm v11 incompatible with Node 20 | Pinned to pnpm@9 |
| 10 | Build fails on Shopify query | Placeholder domain hits real Shopify API | Set SHOPIFY_STORE_DOMAIN="" (empty) |
| 11 | public/ dir missing in build | Git doesn't track empty dirs | Added .gitkeep |
| 12 | Podman DNS doesn't work from Alpine | musl libc + Aardvark-DNS incompatibility | Switched to network_mode: host |
| 13 | Next.js binds to specific IP | HOSTNAME defaults to container hostname | Added HOSTNAME=0.0.0.0 env var |
| 14 | Cockpit login fails | No password, SSH key only | `sudo passwd azureuser` |

---

## 7. Comandos de despliegue rápido

Para referencia, estos son los comandos necesarios para un despliegue completo desde cero o una actualización del frontend:

```bash
# === Desde la máquina local (Windows) ===

# Autenticar con Azure CLI
az login

# Inicializar y aplicar la infraestructura de Terraform
cd terraform
terraform init
terraform apply

# Conectarse a la VM por SSH
ssh azureuser@20.164.202.187 -i ~/.ssh/azure_vm.pem

# === Dentro de la VM ===

# Navegar al directorio del proyecto
cd /opt/podman-cockpit-deployment

# Actualizar el código desde el repositorio
sudo git pull

# Detener los contenedores actuales
sudo podman compose down

# Reconstruir e iniciar los contenedores
sudo podman compose up -d --build

# Verificar que los contenedores estén ejecutándose
sudo podman ps

# Verificar que el frontend responde correctamente
curl -sk https://localhost
```

---

## 8. URLs de acceso

| Servicio | URL |
|----------|-----|
| Frontend (Vercel Commerce) | https://20.164.202.187 |
| Cockpit (Panel de administración) | https://20.164.202.187:9090 |
| Repositorio | https://github.com/Damianpiazz/podman-cockpit-deployment.git |
