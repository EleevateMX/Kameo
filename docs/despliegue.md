# Despliegue de una beta

> Los Dockerfile y el Compose están escritos pero **no se han probado en un servidor real**.
> Trátalos como punto de partida y verifica cada paso.

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
