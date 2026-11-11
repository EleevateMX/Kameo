# ALUX: El Despertar de Kukulkán

Aventura cooperativa 3D para **4 jugadores**, en el navegador, inspirada en las leyendas mayas de Yucatán.
Entras con tu cuenta de **Discord**, creas tu alux, formas un grupo y juegan juntos: transformaciones,
acertijos que sólo se resuelven en equipo y, más adelante, el camino hasta Kukulkán.

![Portada](docs/img/portada.jpg)
![Combate cooperativo en la emboscada del santuario](docs/img/juego-combate.jpg)

| El alux | Balam, el jaguar |
| --- | --- |
| ![Alux](docs/img/juego-alux-de-cerca.jpg) | ![Balam](docs/img/juego-balam-de-cerca.jpg) |

## Qué funciona hoy (Fases 1–3 y parte de la 4)

- **Portal** (Next.js): portada, inicio de sesión con Discord (OAuth2 con `state` y cookies seguras),
  creación del alux (nombre, color, accesorio), salas privadas por código, partida pública e invitaciones.
- **Juego 3D** (Godot 4, exportado a WebAssembly/WebGL 2): el Claro de los Aluxes, con plaza, pirámide,
  cenote para nadar, mirador y santuario sellado.
- **Multijugador con servidor autoritativo** (Godot sin ventana, WebSocket): hasta 4 jugadores por sala,
  predicción local e interpolación, reconexión automática conservando lugar y posición.
- **Combate cooperativo** decidido por el servidor ([docs/combate.md](docs/combate.md)):
  - **Alux**: chispa de jade (proyectil), esquiva con invulnerabilidad y "tocar" (purifica criaturas
    debilitadas y activa el brasero que cura).
  - **Balam**, el jaguar: garras, zarpazo cargado y salto ofensivo; corre y salta más.
  - **Enemigos** con IA y amenaza por jugador: guardián de piedra y criatura corrompida.
  - Vida, energía, enfriamientos, caída y reaparición en punto de control.
- **Encuentro cooperativo**: pisar a la vez tantos altares como jugadores haya (1–4) abre el santuario
  y desata una emboscada que escala con el grupo. Al vencerla todos reciben el *Sello del Claro*.
- **Personajes modelados en Blender** con animaciones (alux y Balam), generados por scripts
  reproducibles ([art/README.md](art/README.md)). Enemigos y escenario siguen siendo provisionales.
- **Progreso persistente**: PostgreSQL/Supabase, o un archivo local si no configuras base de datos.

Lo que falta y lo que aún no se ha podido validar está en [docs/pendientes.md](docs/pendientes.md).

### Controles

| | Ratón | Teclado |
| --- | --- | --- |
| Moverse / saltar | | W A S D · Espacio |
| Cámara | Mover el ratón (clic para capturarlo) | Q / E |
| Habilidad primaria | Clic izquierdo | J |
| Habilidad secundaria | Clic derecho | K |
| Habilidad especial | | F |
| Transformarse | | 1 Alux · 2 Balam |
| Rendimiento | | F3 |

## Probarlo en tu computadora

Necesitas **Node.js 20.11+** y Linux, macOS o WSL (el script descarga Godot para Linux x86_64; en otros
sistemas instala Godot 4.5 y define `GODOT_BIN` con su ruta).

```bash
npm install
```

```bash
npm run setup:godot
```

```bash
npm run dev
```

Abre <http://localhost:3000>. Sin configurar nada, la portada ofrece una **entrada de prueba** (sin Discord)
y los datos se guardan en `apps/api/data/dev-store.json`. Para probar con cuatro jugadores, abre cuatro
ventanas de incógnito o cuatro navegadores distintos y comparte el código de sala.

Si tu computadora no tiene tarjeta gráfica, añade `&q=low` a la dirección del juego (calidad baja).

### Activar el inicio de sesión con Discord

1. Entra a <https://discord.com/developers/applications> y crea una aplicación.
2. En **OAuth2 → Redirects** agrega `http://localhost:3000/auth/discord/callback`
   (en producción, `https://tu-dominio/auth/discord/callback`).
3. Copia `.env.example` como `.env` y pon ahí el **Client ID** y el **Client Secret**.
4. Reinicia `npm run dev`. La entrada de prueba se desactiva sola cuando Discord está configurado.

Sólo se pide el permiso `identify` (nombre y avatar). No hace falta un bot.

### Guardar el progreso en Supabase

1. Crea un proyecto en Supabase y ejecuta `supabase/migrations/20261111000000_init.sql` en el editor SQL
   (o `supabase db push`).
2. Pon la cadena de conexión en `DATABASE_URL` dentro de `.env`.

Las tablas tienen RLS activado sin políticas: sólo la API puede leerlas y escribirlas.

## Pruebas

```bash
npm test
```

Ejecuta tres baterías:

- **API**: sesiones, salas, tickets y recompensas sin duplicados.
- **Simulación** (`scripts/test-sim.sh`): más de 400 000 comprobaciones de que nadie atraviesa muros,
  supera la velocidad permitida ni se salta un enfriamiento ([docs/simulacion.md](docs/simulacion.md)).
- **Red** contra el servidor real de Godot con bots: 4 jugadores, tickets falsos, trampas, reconexión,
  daño y enfriamientos, caída y reaparición, y la emboscada cooperativa completa.

```bash
npm run test:e2e
```

Con ALUX corriendo (`npm run dev`), abre **cuatro navegadores con cuatro cuentas**, los mete en la misma
sala desde el portal y comprueba movimiento, transformación, que todos ven la misma vida de enemigos y
compañeros en combate, un corte de red con reconexión automática y el rechazo del quinto jugador.

```bash
scripts/test-deploy.sh
```

Construye las imágenes Docker y levanta el despliegue completo en tu máquina (proxy HTTPS/WSS, portal,
API, servidor de juego y PostgreSQL) para comprobar sesión, guardado y entrada al juego por `wss://`.

Para repetir las pruebas de la API contra PostgreSQL real: `TEST_DATABASE_URL=postgres://… npm test`.

## Estructura

```
apps/portal/              Portal Next.js: portada, Discord OAuth2, centro de jugadores
apps/api/                 API: perfiles, salas, emparejamiento, tickets, recompensas
game/                     Proyecto Godot 4 (cliente Web y servidor dedicado en el mismo proyecto)
  scripts/shared/         Mundo, simulación y verificación de tickets (cliente y servidor)
  scripts/server/         Servidor autoritativo
  scripts/client/         Red, predicción, escenario 3D, personajes, HUD
services/game-server/     Imagen Docker del servidor de juego
packages/shared-contracts Protocolo, JWT y tipos compartidos
supabase/migrations/      Esquema de base de datos
infra/                    Docker Compose y proxy HTTPS/WSS (Caddy)
tests/                    Prueba de protocolo con bots y prueba de 4 navegadores
art/                      Scripts de Blender que generan los personajes (.glb) y sus vistas previas
docs/                     Arquitectura, protocolo, combate, simulación, rendimiento, despliegue
```

## Documentación

- [Arquitectura y plan por fases](docs/arquitectura.md)
- [Combate: formas, habilidades, enemigos y emboscada](docs/combate.md)
- [Protocolo de red y reglas anti-trampas](docs/protocolo.md)
- [Simulación de movimiento: garantías y pruebas](docs/simulacion.md)
- [Rendimiento: cómo medirlo](docs/rendimiento.md)
- [Despliegue de una beta](docs/despliegue.md)
- [Pendientes y validaciones que faltan](docs/pendientes.md)
- [Historia y origen de la idea](docs/historia.md)

ALUX es un proyecto original. Su punto de partida fue el recuerdo de los juegos de transformaciones
elementales de los 2000, pero el mundo, los personajes y la historia son propios.
