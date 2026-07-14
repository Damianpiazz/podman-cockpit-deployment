# Puertos del Servidor — VM Azure

**IP pública:** `20.164.202.187`

| Puerto | URL | Servicio | Qué ves en el navegador |
|--------|-----|----------|------------------------|
| 80 | `http://20.164.202.187` | Nginx (HTTP) | Redirige automáticamente a HTTPS (301) |
| 443 | `https://20.164.202.187` | Nginx (HTTPS) | **Next.js Commerce** — tienda frontend con SSL (certificado autofirmado) |
| 3000 | `http://20.164.202.187:3000` | Next.js (directo) | Next.js Commerce sin proxy (mismo contenido que 443, sin HTTPS) |
| 9090 | `https://20.164.202.187:9090` | Cockpit | Panel de administración de la VM (login con `azureuser`) |

## Notas

- **Puerto 443 (recomendado):** Es la forma correcta de acceder. Nginx maneja SSL + proxy a Next.js. El navegador va a advertir que el certificado es autofirmado — aceptalo.
- **Puerto 80:** Solo redirige a HTTPS, no sirve contenido directamente.
- **Puerto 3000:** Acceso directo a Next.js sin pasar por Nginx. Funcional pero sin SSL.
- **Puerto 9090:** Cockpit para gestionar la VM (terminal, servicios, logs, etc.)
