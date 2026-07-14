#!/bin/bash
# ============================================================
# Cloud-init script: setup de la VM Azure
# Instala Podman, Cockpit y levanta el stack de contenedores
# ============================================================
set -euo pipefail

LOG_FILE="/var/log/setup-vm.log"
exec > >(tee -a "$LOG_FILE") 2>&1

echo "=== Inicio del setup: $(date) ==="

# -----------------------------------------------------------
# 1. Actualizar sistema e instalar dependencias
# -----------------------------------------------------------
apt-get update -y
apt-get upgrade -y
apt-get install -y curl git ufw

# -----------------------------------------------------------
# 2. Instalar Podman + Compose
# -----------------------------------------------------------
echo "--- Instalando Podman ---"
apt-get install -y podman podman-compose
podman --version
podman-compose --version

# -----------------------------------------------------------
# 3. Configurar Podman para resolver images de Docker Hub
# -----------------------------------------------------------
echo "--- Configurando registries de Podman ---"
mkdir -p /etc/containers/registries.conf.d
echo 'unqualified-search-registries = ["docker.io"]' > /etc/containers/registries.conf.d/docker-io.conf

# -----------------------------------------------------------
# 4. Instalar Cockpit + complemento Podman
# -----------------------------------------------------------
echo "--- Instalando Cockpit ---"
apt-get install -y cockpit cockpit-podman
systemctl enable --now cockpit.socket

# -----------------------------------------------------------
# 5. Configurar firewall
# -----------------------------------------------------------
echo "--- Configurando firewall ---"
ufw --force enable
ufw allow 22/tcp    # SSH
ufw allow 80/tcp    # HTTP
ufw allow 443/tcp   # HTTPS
ufw allow 9090/tcp  # Cockpit

# -----------------------------------------------------------
# 6. Clonar repositorio
# -----------------------------------------------------------
echo "--- Clonando repositorio ---"
REPO_DIR="/opt/podman-cockpit-deployment"
git config --global --add safe.directory "$REPO_DIR"
if [ ! -d "$REPO_DIR" ]; then
  git clone "${repo_url}" "$REPO_DIR"
fi
cd "$REPO_DIR"

# -----------------------------------------------------------
# 7. Generar certificados SSL self-signed
# -----------------------------------------------------------
echo "--- Generando certificados SSL ---"
VM_IP=$(curl -s ifconfig.me)
bash nginx/generate-certs.sh "$VM_IP"

# -----------------------------------------------------------
# 8. Levantar stack con Podman Compose
# -----------------------------------------------------------
echo "--- Levantando contenedores ---"
podman compose up -d --build

echo "=== Setup completado: $(date) ==="
echo "Cockpit: https://$VM_IP:9090"
echo "Sitio:   https://$VM_IP"
