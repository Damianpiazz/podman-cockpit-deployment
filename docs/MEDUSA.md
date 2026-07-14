# Medusa

## Que es

[Medusa](https://medusajs.com/) es un backend de e-commerce open-source, modular y extensible. Funciona como la **API principal** del stack, manejando:

- **Catalogo** — productos, categorias, colecciones, variantes, precios
- **Carrito** — crear, agregar/quitar items, aplicar descuentos
- **Checkout** — direcciones, envios, pagos, ordenes
- **Clientes** — autenticacion, perfiles, direcciones, historial de ordenes
- **Admin** — dashboard para gestionar todo el catalogo y ordenes

En este proyecto, Medusa corre como contenedor Docker (`medusajs/medusa:latest`) y se comunica con PostgreSQL para persistencia.

---

## Arquitectura en este repo

```mermaid
graph TB
    Browser["Browser"] -->|"HTTPS :443"| Nginx["Nginx\n:443"]

    Nginx -->|"/store/*"| Medusa["Medusa API\n:9000"]
    Nginx -->|"/admin/*"| Medusa
    Nginx -->|"/*"| Nextjs["Next.js\n:3000"]

    Nextjs -->|"SSR fetch"| Medusa
    Medusa --> Postgres["PostgreSQL\n:5432"]

    style Nginx fill:#009639,stroke:#006b2b,color:#fff
    style Medusa fill:#56b4d3,stroke:#2c7a9e,color:#fff
    style Nextjs fill:#000,stroke:#333,color:#fff
    style Postgres fill:#336791,stroke:#1a3d5c,color:#fff
```

---

## Servicio en compose.yml

```yaml
medusa:
  image: medusajs/medusa:latest
  container_name: medusa-ecommerce
  environment:
    - NODE_ENV=production
    - DATABASE_URL=postgresql://medusa:medusa@postgres:5432/medusa
    - JWT_SECRET=${JWT_SECRET:-supersecretjwt}
    - COOKIE_SECRET=${COOKIE_SECRET:-supersecretcookie}
    - STORE_CORS=http://localhost,https://localhost
    - ADMIN_CORS=http://localhost,https://localhost
    - AUTH_CORS=http://localhost,https://localhost
  depends_on:
    postgres:
      condition: service_healthy
  networks:
    - frontend
    - backend
```

**Puntos clave:**
- Sin `ports` expuestos al host — solo accesible via nginx proxy
- Conectado a ambas redes: `frontend` (para Next.js) y `backend` (para PostgreSQL)
- Espera a que PostgreSQL este saludable antes de iniciar

---

## Variables de entorno

### Base de datos

| Variable | Descripcion | Ejemplo |
|:---------|:------------|:--------|
| `DATABASE_URL` | Connection string de PostgreSQL | `postgresql://user:pass@postgres:5432/medusa` |

### Seguridad

| Variable | Descripcion | Generar con |
|:---------|:------------|:------------|
| `JWT_SECRET` | Secreto para tokens JWT | `openssl rand -hex 32` |
| `COOKIE_SECRET` | Secreto para firmar cookies | `openssl rand -hex 32` |

### CORS

| Variable | Descripcion | Ejemplo |
|:---------|:------------|:--------|
| `STORE_CORS` | Dominios permitidos para la API publica | `http://localhost,https://localhost` |
| `ADMIN_CORS` | Dominios permitidos para el admin | `http://localhost,https://localhost` |
| `AUTH_CORS` | Dominios permitidos para autenticacion | `http://localhost,https://localhost` |

> **Nota:** En produccion, reemplazar `localhost` con el dominio real de la VM.

---

## API Endpoints principales

### Store API (`/store/*`)

| Endpoint | Metodo | Descripcion |
|:---------|:-------|:------------|
| `/store/products` | GET | Listar productos |
| `/store/products/{handle}` | GET | Obtener producto por handle |
| `/store/categories` | GET | Listar categorias |
| `/store/collections` | GET | Listar colecciones |
| `/store/regions` | GET | Listar regiones (determina moneda/paises) |
| `/store/carts` | POST | Crear carrito |
| `/store/carts/{id}` | POST | Actualizar carrito |
| `/store/carts/{id}/items` | POST | Agregar item al carrito |
| `/store/carts/{id}/items/{itemId}` | DELETE | Quitar item del carrito |

### Admin API (`/admin/*`)

Requiere autenticacion. Accesible desde `https://<IP>/admin/`.

---

## Frontend Next.js — Conexion con Medusa

El frontend usa estas variables para conectarse al backend:

| Variable | Valor (en compose) | Descripcion |
|:---------|:-------------------|:------------|
| `NEXT_PUBLIC_MEDUSA_BACKEND_URL` | `http://medusa:9000` | URL interna del backend (DNS del contenedor) |
| `NEXT_PUBLIC_MEDUSA_PUBLISHABLE_KEY` | `pk_test` | Clave publica del store (obtenible del admin) |
| `MEDUSA_BACKEND_URL` | `http://medusa:9000` | URL para middleware.ts (server-side, sin prefijo NEXT_PUBLIC_) |

### Flujo de requests

```mermaid
sequenceDiagram
    participant B as Browser
    participant N as Nginx
    participant J as Next.js
    participant M as Medusa
    participant P as PostgreSQL

    B->>N: GET /us/products
    N->>J: proxy_pass :3000
    J->>M: fetch /store/products (SSR)
    M->>P: SELECT * FROM products
    P-->>M: rows
    M-->>J: JSON products
    J-->>B: HTML rendered
```

El Next.js server ejecuta los requests a Medusa internamente (server-side), no desde el browser.

---

## Revalidacion (Webhooks)

Medusa puede notificar a Next.js cuando cambian productos o categorias, forzando regeneracion de paginas estaticas.

| Variable | Descripcion |
|:---------|:------------|
| `MEDUSA_REVALIDATION_SECRET` | Secreto compartido para validar webhooks |

---

## Red

- **`frontend`** — se comunica con Next.js (para requests SSR) y Nginx (proxy)
- **`backend`** — se comunica con PostgreSQL

---

## Troubleshooting

```bash
# Ver logs
podman compose logs medusa

# Verificar conexion a PostgreSQL
podman exec medusa-ecommerce node -e "const pg = require('pg'); const c = new pg.Client({connectionString: process.env.DATABASE_URL}); c.connect().then(() => console.log('OK')).catch(e => console.error(e))"

# Test de la API desde la VM
curl -k https://localhost/store/regions

# Test del admin
curl -k https://localhost/admin/app
```

---

## Referencias

- [Medusa Documentation](https://docs.medusajs.com/)
- [Medusa GitHub](https://github.com/medusajs/medusa)
- [Store API Reference](https://docs.medusajs.com/api/store)
- [Admin API Reference](https://docs.medusajs.com/api/admin)
