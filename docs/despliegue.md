# Despliegue de una beta

> **Probado en una sola máquina** con `scripts/test-deploy.sh` (ver más abajo): imágenes, proxy
> HTTPS/WSS, portal, API, servidor de juego y PostgreSQL en contenedor.
> **No probado todavía:** un VPS real, un dominio con certificado de Let's Encrypt, Supabase como
> base de datos y el inicio de sesión real con Discord.

## Qué necesitas

- Un VPS Linux con Docker (2 vCPU y 4 GB bastan para una beta pequeña).
- Un dominio apuntando al VPS (registro A).
- Un proyecto de Supabase con la migración de `supabase/migrations` aplicada.
- Una aplicación de Discord con el redirect `https://TU-DOMINIO/auth/discord/callback`.

## Pasos

1. Copia `.env.example` como `.env` y rellena:
   - `DOMAIN`, `DISCORD_CLIENT_ID`, `DISCORD_CLIENT_SECRET`, `DATABASE_URL`
   - `SESSION_SECRET`, `GAME_TICKET_SECRET`, `SERVICE_KEY` (cada uno con `openssl rand -hex 32`)
2. Levanta todo:

```bash
docker compose -f infra/docker/docker-compose.yml --env-file .env up -d --build
```

3. Abre `https://TU-DOMINIO`. Caddy obtiene el certificado HTTPS automáticamente.

## Probar el despliegue en tu máquina

```bash
scripts/test-deploy.sh
```

Construye las tres imágenes, levanta todo con `DOMAIN=localhost` (Caddy usa su certificado interno) y
un PostgreSQL en contenedor con la migración aplicada, y ejecuta `tests/deploy-check.ts`, que comprueba:

1. el portal responde por HTTPS;
2. las rutas `/internal/*` no son accesibles desde fuera;
3. sesión con cookie `Secure`, y el perfil se guarda y se lee de la base de datos;
4. se crea una sala y la API entrega un ticket con dirección `wss://`;
5. el juego acepta la conexión WebSocket segura a través del proxy;
6. el servidor de juego informa a la API (la sala muestra al jugador).

Con `KEEP=1` deja los contenedores arriba en `https://localhost`. La misma comprobación sirve contra un
servidor real: `npx tsx tests/deploy-check.ts https://tu-dominio` (necesita la entrada de prueba activada).

### Detrás de un proxy corporativo

Si la red inspecciona HTTPS, copia el certificado raíz en `infra/docker/certs/` (extensión `.crt`);
los Dockerfile lo instalan antes de descargar nada.

## Qué queda expuesto

| Ruta pública | Destino |
| --- | --- |
| `/` y `/game/*` | Portal |
| `/api/v1/*` | API (sólo rutas de jugador, con cookie de sesión) |
| `/ws` | Servidor de juego (WebSocket seguro) |

Las rutas `/internal/*` de la API sólo son alcanzables dentro de la red de Docker y además exigen
`SERVICE_KEY`.

## Antes de invitar gente

- Comprueba que la entrada de prueba está desactivada (`ALLOW_DEV_LOGIN=false`, ya fijado en el Compose).
- Activa copias de seguridad en Supabase.
- Corre `npm run test:e2e` apuntando al dominio (`E2E_BASE_URL`), en un entorno de pruebas con la
  entrada de prueba activada, antes de abrir la beta.
- Para más de ~60 salas simultáneas, añade otro servicio `game` y lístalo en `GAME_SERVERS`.
