#!/bin/bash
# ============================================================
# Generar certificado SSL self-signed para Nginx
# Uso: ./generate-certs.sh [IP_O_DOMINIO]
# ============================================================
set -euo pipefail

SSL_DIR="$(cd "$(dirname "$0")" && pwd)/ssl"
mkdir -p "$SSL_DIR"

# IP o dominio como argumento, o default
HOST="${1:-localhost}"

echo "Generando certificado para: $HOST"

openssl req -x509 -newkey rsa:2048 -nodes \
  -keyout "${SSL_DIR}/key.pem" \
  -out    "${SSL_DIR}/cert.pem" \
  -days   365 \
  -subj   "/CN=${HOST}" \
  -addext "subjectAltName=IP:${HOST},DNS:${HOST}" \
  2>/dev/null

chmod 600 "${SSL_DIR}/key.pem"
chmod 644 "${SSL_DIR}/cert.pem"

echo "Certificados generados en: ${SSL_DIR}/"
echo "  cert.pem"
echo "  key.pem"
