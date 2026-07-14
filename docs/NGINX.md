# Nginx

## Que es

[Nginx](https://nginx.org/) es un servidor web de alto performance usado como reverse proxy, load balancer y servidor de contenido estatico. En este proyecto actua como **unico punto de entrada TLS** del stack, manejando:

1. **Terminacion TLS** — HTTPS en puerto 443 con certificados self-signed
2. **Reverse proxy** — routing a los servicios internos (Next.js, Medusa)
3. **Compresion Gzip** — reduccion de tamano de respuestas
4. **Security headers** — proteccion basica contra ataques comunes

---

## Archivos del servicio

| Archivo | Proposito |
|:--------|:----------|
| `nginx/Dockerfile` | Build de la imagen `nginx:1.27-alpine` con config custom |
| `nginx/nginx.conf` | Config principal (worker, gzip, logging, mime types) |
| `nginx/conf.d/default.conf` | Virtual hosts: routing, SSL, CORS, proxy |
| `nginx/generate-certs.sh` | Script para generar certificados self-signed |

---

## Dockerfile

```dockerfile
FROM nginx:1.27-alpine

# Eliminar config default
RUN rm /etc/nginx/conf.d/default.conf

# Copiar configs custom
COPY nginx.conf /etc/nginx/nginx.conf
COPY conf.d/ /etc/nginx/conf.d/

# Crear directorio SSL
RUN mkdir -p /etc/nginx/ssl

EXPOSE 80 443
CMD ["nginx", "-g", "daemon off;"]
```

**Puntos clave:**
- Imagen base: `nginx:1.27-alpine` (minimal, ~40MB)
- Los certificados SSL se montan via volumen en compose, no se copian al build
- `daemon off;` necesario para correr como proceso principal en un contenedor

---

## nginx.conf — Config principal

```nginx
user  nginx;
worker_processes  auto;        # Un worker por CPU
worker_connections  1024;

http {
    # Gzip: compresion para text/css/js/json/xml/svg
    gzip on;
    gzip_vary on;
    gzip_comp_level 6;
    gzip_min_length 1024;

    # Seguridad: ocultar version de nginx
    server_tokens off;

    # Virtual hosts
    include /etc/nginx/conf.d/*.conf;
}
```

---

## default.conf — Routing y Proxy

### Estructura de virtual hosts

```
Puerto 80  → Redirect 301 a HTTPS
Puerto 443 → Server principal con SSL
```

### Rutas configuradas

| Ruta | Destino | Descripcion |
|:-----|:--------|:------------|
| `GET /store/*` | `http://medusa:9000/store/*` | API de tienda (productos, carrito, checkout) |
| `GET /admin/*` | `http://medusa:9000/admin/*` | Dashboard de administracion de Medusa |
| `GET /*` | `http://nextjs:3000` | Frontend Next.js (storefront) |

### Headers de proxy

Cada bloque `location` inyecta headers estandar:

```nginx
proxy_set_header   Host              $http_host;
proxy_set_header   X-Real-IP         $remote_addr;
proxy_set_header   X-Forwarded-For   $proxy_add_x_forwarded_for;
proxy_set_header   X-Forwarded-Proto $scheme;
```

### CORS para Medusa API

Los bloques `/store/` y `/admin/` incluyen headers CORS para permitir requests desde el frontend:

```nginx
add_header Access-Control-Allow-Origin "$http_origin" always;
add_header Access-Control-Allow-Methods "GET, POST, PUT, PATCH, DELETE, OPTIONS" always;
add_header Access-Control-Allow-Headers "Authorization, Content-Type, X-Requested-With" always;
add_header Access-Control-Allow-Credentials "true" always;

# Preflight OPTIONS → 204 sin body
if ($request_method = OPTIONS) {
    return 204;
}
```

### WebSocket para Next.js

El bloque `/` incluye soporte para WebSocket (necesario para Hot Module Replacement en desarrollo):

```nginx
proxy_set_header   Upgrade    $http_upgrade;
proxy_set_header   Connection "Upgrade";
```

---

## Certificados SSL self-signed

### Generar certs

```bash
bash nginx/generate-certs.sh <IP_O_DOMINIO>
```

Esto crea:
- `nginx/ssl/cert.pem` — certificado (valido 365 dias)
- `nginx/ssl/key.pem` — clave privada

### Montaje en compose

```yaml
volumes:
  - ./nginx/ssl:/etc/nginx/ssl:ro    # Solo lectura
```

---

## Security headers

| Header | Valor | Proteccion |
|:-------|:------|:-----------|
| `X-Content-Type-Options` | `nosniff` | Previene MIME sniffing |
| `X-Frame-Options` | `SAMEORIGIN` | Previene clickjacking |
| `Referrer-Policy` | `strict-origin-when-cross-origin` | Control de informacion enviada en referrers |

---

## Timeouts

| Parametro | Valor | Descripcion |
|:----------|:------|:------------|
| `proxy_read_timeout` | 90s | Tiempo maximo para leer respuesta del backend |
| `proxy_send_timeout` | 90s | Tiempo maximo para enviar request al backend |
| `proxy_connect_timeout` | 60s | Tiempo maximo para establecer conexion |

---

## Red

Nginx solo participa en la red `frontend`:

```yaml
networks:
  - frontend
```

Los servicios internos (`medusa`, `nextjs`) son resueltos por DNS del contenedor via el nombre del servicio en compose.

---

## Troubleshooting

```bash
# Ver logs de nginx
podman compose logs nginx

# Test de config (dentro del contenedor)
podman exec nginx-ecommerce nginx -t

# Verificar conectividad a backends
podman exec nginx-ecommerce wget -qO- http://nextjs:3000
podman exec nginx-ecommerce wget -qO- http://medusa:9000/store/regions
```
