# Arquitectura

```
Navegador ──HTTPS──► Portal (Next.js) ──► API ──► PostgreSQL / Supabase
    │                   │ Discord OAuth2    ▲
    │                   └ sirve el juego    │ latidos y recompensas (clave de servicio)
    └──────WSS────────────────────────► Servidor de juego (Godot sin ventana)
```

| Pieza | Tecnología | Responsabilidad |
| --- | --- | --- |
| Portal | Next.js 16 + TypeScript | Portada, inicio de sesión con Discord, creación del alux, salas e invitaciones. Sirve el juego exportado. |
| API | Node + Express + TypeScript | Perfiles, salas, emparejamiento público, tickets de acceso, recompensas idempotentes. |
| Juego (cliente) | Godot 4.5, GDScript, renderizador Compatibility (WebGL 2) | Entrada, predicción local, interpolación, escenario y personajes 3D. |
| Servidor de juego | El mismo proyecto Godot en modo `--headless -- --server` | Simulación autoritativa de cada sala a 30 Hz, estados a 15 Hz. |
| Datos | PostgreSQL (Supabase) o archivo local en desarrollo | Jugadores, personajes, formas, salas, misiones, libro de recompensas. |

## Cómo entra un jugador a una sala

1. El portal autentica con Discord y deja una cookie de sesión firmada (`alux_session`, HttpOnly).
2. El jugador crea o elige una sala. La API la asigna al servidor de juego con menos salas.
3. La página del juego pide a la API un **ticket**: un JWT de 90 segundos y un solo uso con el id del
   jugador, la sala, su aspecto y sus formas desbloqueadas.
4. El cliente Godot abre el WebSocket y manda el ticket. El servidor lo verifica con el secreto
   compartido; nada de lo que diga el cliente sobre su identidad se toma en cuenta.
5. Si la conexión se cae, el cliente pide otro ticket y vuelve a su lugar (el servidor lo guarda 120 s).

## Reglas del multijugador

- El cliente envía **intenciones** (dirección, salto, forma deseada); el servidor decide el resultado.
- La simulación de movimiento (`game/scripts/shared/sim.gd`) es el mismo código en cliente y servidor.
  El cliente la usa para predecir su propio alux y se corrige con cada estado del servidor.
- Cada jugador avanza como mucho al ritmo del tiempo real: mandar más entradas no lo hace más rápido.
- Altares, puerta del santuario y recompensas se calculan en el servidor.
- Las recompensas persistentes las pide el servidor de juego a la API con una clave de servicio.
  La API sólo las da a miembros reales de la sala y una sola vez (clave de idempotencia en `rewards_ledger`).

Detalle de mensajes y defensas: [protocolo.md](protocolo.md).

## Decisiones tomadas respecto al plan original

- **Emparejador dentro de la API.** El plan tenía `services/matchmaker` aparte. Con un solo tipo de
  sala no aporta nada separarlo; vive en `apps/api/src/app.ts` (`/v1/rooms/quick` y `pickServer`).
  Se puede extraer cuando haya varias regiones o colas.
- **Un proceso de juego aloja muchas salas** (hasta 64). Para crecer se levantan más procesos y se
  listan en `GAME_SERVERS`; la API reparte las salas.
- **Simulación propia en lugar de la física de Godot en el servidor.** Colisiones con terreno, cajas y
  cilindros definidas en `world_def.gd`. Es determinista, barata y permite predicción exacta.
- **JSON sobre WebSocket.** Suficiente para 4 jugadores por sala; el formato está aislado para poder
  pasar a binario si hiciera falta.
- **Escenario y personajes procedimentales.** Todo se construye por código para tener el hito jugable
  sin depender de arte. Sustituirlos por modelos de Blender no cambia la lógica: `avatar.gd` y
  `world_builder.gd` sólo dibujan.

## Plan por fases

| Fase | Contenido | Estado |
| --- | --- | --- |
| 1. Infraestructura y acceso | Monorepo, portal, Discord, esquema de datos, Docker, sesiones | Hecho. Pendiente de credenciales reales: Discord y Supabase alojado (ver [pendientes.md](pendientes.md)) |
| 2. Primera sala multijugador | Escenario 3D, 4 aluxes, movimiento sincronizado, nombres, reconexión | Hecho y verificado con 4 navegadores |
| 3. Transformaciones y combate | Habilidades de alux y Balam, energía, enfriamientos, enemigos con IA, vida, caída y reaparición | Hecho y verificado con bots y navegadores ([combate.md](combate.md)) |
| 4. Primer capítulo | Selva, cenote, acertijos, misiones, jefe, guardado de grupo | Empezada: acertijo de los altares + emboscada cooperativa con recompensa. Falta jefe, misiones y más zonas |
| 5. Calidad | Modelos, animaciones, sonido, accesibilidad, rendimiento | Empezada: alux y Balam modelados en Blender en dos pasadas, escenario e interfaz rediseñados y tres niveles de calidad ([direccion-artistica.md](direccion-artistica.md)). Enemigos provisionales. Audio provisional generado por código. Sin medición con GPU |
| 6. Beta privada | Despliegue, telemetría, respaldos | Despliegue con Docker probado en local; falta un servidor real con dominio |

El detalle de lo que queda por validar está en [pendientes.md](pendientes.md).
