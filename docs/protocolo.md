# Protocolo de red

WebSocket con mensajes JSON de texto. Los tipos están en `packages/shared-contracts/src/protocol.ts`.
Versión actual: **1**.

## Cliente → servidor

| Mensaje | Campos | Cuándo |
| --- | --- | --- |
| `hello` | `v` versión, `ticket` JWT | Primer mensaje, antes de 20 s. |
| `in` | `s` secuencia, `mx`, `mz` dirección (−1…1), `j` salto 0/1, `f` forma deseada o `""` | Uno por tick (30 por segundo). |
| `ping` | `c` marca de tiempo del cliente | Opcional. |

No existe ningún mensaje para fijar posición, abrir puertas o pedir recompensas.

## Servidor → cliente

| Mensaje | Contenido |
| --- | --- |
| `welcome` | Tu id, lugar (0–3), sala, formas, tu estado, lista de jugadores, estado del mundo, `rejoin`. |
| `roster` | Lista de jugadores (nombre, color, accesorio, conectado). |
| `snap` | 15 por segundo. `p`: por jugador `[lugar, últimaEntradaProcesada, conectado, x, y, z, vy, giro, forma, enfriamiento, banderas]`. `w`: `[santuarioAbierto, máscaraDeAltares, altaresNecesarios]`. |
| `event` | `gate_open` (quiénes lo abrieron) o `reward` (recompensa, si se guardó y si era nueva). |
| `error` | `code` y mensaje. Tras un error el servidor cierra la conexión. |

Códigos de error: `bad_ticket`, `ticket_used`, `hello_timeout`, `version`, `room_full`, `server_full`,
`replaced` (abriste el juego en otra ventana), `rate_limit`, `too_big`, `bad_message`.

## Ticket

JWT HS256 firmado por la API con `GAME_TICKET_SECRET`: `aud: "alux-game"`, `sub` (jugador), `jti`
(un solo uso), `room`, `name`, `color`, `hat`, `forms`, `exp` (90 s). El servidor lo verifica en
`game/scripts/shared/ticket.gd`.

## Defensas del servidor

| Intento | Qué pasa |
| --- | --- |
| Ticket falso, vencido o repetido | Se rechaza la conexión. |
| Mandar cualquier cosa sin autenticarse | Se ignora; a los 20 s se cierra. |
| Vector de movimiento enorme | Se recorta a longitud 1. |
| Mandar entradas más rápido que el tiempo real | Presupuesto de 1 entrada por tick (ráfaga máx. 8, cola máx. 12); el resto se descarta. |
| Mensajes inventados (`pos`, `reward`…) o campos extra | Se ignoran. |
| Pedir una forma no desbloqueada | Se ignora: las formas salen del ticket, no del cliente. |
| Más de 90 mensajes por segundo o mensajes de más de 4 KB | Expulsión. |
| Quinto jugador | `room_full` (la API ya lo impide al pedir el ticket). |
| Conexión que deja de enviar 15 s | Se libera; el jugador puede reconectarse. |
| Recompensas duplicadas | La API usa una clave de idempotencia por jugador y recompensa. |

Todo esto está cubierto por `tests/protocol.test.ts`.
