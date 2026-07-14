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
# 2. Instalar Podman
# -----------------------------------------------------------
echo "--- Instalando Podman ---"
apt-get install -y podman
podman --version

# -----------------------------------------------------------
# 3. Instalar Cockpit + complemento Podman
# -----------------------------------------------------------
echo "--- Instalando Cockpit ---"
apt-get install -y cockpit cockpit-podman
systemctl enable --now cockpit.socket

# -----------------------------------------------------------
# 4. Configurar firewall
# -----------------------------------------------------------
echo "--- Configurando firewall ---"
ufw --force enable
ufw allow 22/tcp    # SSH
ufw allow 80/tcp    # HTTP
ufw allow 443/tcp   # HTTPS
ufw allow 9090/tcp  # Cockpit

# -----------------------------------------------------------
# 5. Clonar repositorio
# -----------------------------------------------------------
echo "--- Clonando repositorio ---"
REPO_DIR="/opt/podman-cockpit-deployment"
if [ ! -d "$REPO_DIR" ]; then
  git clone "${repo_url}" "$REPO_DIR"
fi
cd "$REPO_DIR"

# -----------------------------------------------------------
# 6. Crear archivo .env con passwords generados
# -----------------------------------------------------------
echo "--- Configurando .env ---"
if [ ! -f .env ]; then
  cp .env.example .env
  # Reemplazar placeholders con valores reales
  sed -i "s/CHANGE_ME_TO_A_SECURE_PASSWORD/${db_password}/" .env
  # Generar secrets aleatorios
  JWT_SECRET=$(openssl rand -hex 32)
  COOKIE_SECRET=$(openssl rand -hex 32)
  REVAL_SECRET=$(openssl rand -hex 16)
  sed -i "s/CHANGE_ME_JWT_SECRET/$JWT_SECRET/" .env
  sed -i "s/CHANGE_ME_COOKIE_SECRET/$COOKIE_SECRET/" .env
  sed -i "s/CHANGE_ME_REVALIDATION_SECRET/$REVAL_SECRET/" .env
fi

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
echo "Medusa:  https://$VM_IP/admin"
