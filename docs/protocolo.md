# Protocolo de red

WebSocket con mensajes JSON de texto. Los tipos están en `packages/shared-contracts/src/protocol.ts`.
Versión actual: **2** (la 2 añade el combate).

## Cliente → servidor

| Mensaje | Campos | Cuándo |
| --- | --- | --- |
| `hello` | `v` versión, `ticket` JWT | Primer mensaje, antes de 20 s. |
| `in` | `s` secuencia · `mx`, `mz` dirección (−1…1) · `j` salto 0/1 · `f` forma deseada o `""` · `a` botones (1 primaria, 2 secundaria, 4 especial) · `r` giro de puntería en radianes | Uno por tick (30 por segundo). |
| `ping` | `c` marca de tiempo del cliente | Cada 2 s, para medir la latencia. |
| `talk` | `n` id del personaje | Al terminar de leer un diálogo. El servidor comprueba que el jugador está junto al personaje y anota el avance de la historia de la sala. |
| `cine_ready` | `id` de la cinemática · `v` 1 tiene el vídeo, 0 verá la escena del motor | Respuesta a `cine_prep`, cuando el cliente terminó su fundido de entrada. Sólo acorta la espera: quien no contesta retrasa el inicio como mucho 5 s. |
| `skip` | — | Voto para omitir la cinemática compartida. Sólo cuenta durante la reproducción; se omite cuando vota la mayoría de los conectados. |
| `again` | `v` 1 (por defecto) vota, 0 retira el voto | Sólo con la emboscada superada: pide otra ronda. La sala se reinicia cuando votan todos los conectados. |

No existe ningún mensaje para fijar posición, hacer daño, curarse, abrir puertas o pedir recompensas.
`again` es sólo un voto: quien decide reiniciar es el servidor, y fuera de la victoria se ignora.

## Servidor → cliente

| Mensaje | Contenido |
| --- | --- |
| `welcome` | Tu id, lugar (0–3), sala, formas, tu estado y vida, lista de jugadores, estado del mundo, enemigos, `rejoin`. |
| `roster` | Lista de jugadores (nombre, color, accesorio, conectado). |
| `snap` | 15 por segundo: `p` jugadores, `e` enemigos, `w` mundo, `ev` eventos de combate desde el estado anterior. |
| `event` | `gate_open` (quiénes lo abrieron), `reward` (recompensa, si se guardó y si era nueva), `defeat` (todo el grupo cayó), `restart` (empieza otra ronda), `story` (avanzó la historia: `talked` con un personaje, `freed` al liberar al guardián o `clue` al recibir la pista del Cenote, y quién), `cine_prep` (la sala se pausa para una cinemática compartida: id y espera máxima), `cine` (orden de inicio: id, duración y `at`, los segundos ya transcurridos para quien se engancha a mitad) o `cine_end` (terminó, y si fue por votos). |
| `pong` | Eco de `c`. |
| `error` | `code` y mensaje. Tras un error el servidor cierra la conexión. |

### Cinemáticas compartidas

`PREPARING → PLAYING → RESUMING`, siempre en ese orden y dictadas por el servidor (valor 14 del estado
del mundo: 1, 2, 3; 0 si no hay ninguna). La sala está en pausa en las tres: las entradas de
movimiento y ataque se ignoran y el combate no avanza.

| Fase | Empieza con | Termina cuando |
| --- | --- | --- |
| Preparación | `cine_prep` | Todos los conectados enviaron `cine_ready`, o pasan 5 s |
| Reproducción | `cine` | Se cumple la duración, o vota omitir la mayoría de los conectados |
| Reanudación | `cine_end` | Pasa 1 s; después el estado del mundo vuelve a fase 0 |

Quien entra o se reconecta recibe, tras el `welcome`, el `cine_prep` (con la espera que queda) o el
`cine` (con `at`) de la fase en curso. El vídeo nunca viaja por este canal: cada navegador lo
descarga por HTTP. Detalle y motivos: [CINEMATICS.md](CINEMATICS.md).

### `snap.b` — el jefe

Estado de Nojoch Tuunich ([BOSS.md](BOSS.md)); también viaja en `welcome`. Lo decide todo el servidor
y no existe ningún mensaje del cliente que lo toque:

`[fase, x, z, giro, estado, segundosDelEstado, silencio, glifos, glifosNecesarios, slotObjetivo, golpeX, golpeZ, giroDelBarridoOEmbestida, escombros, anclasActivas, anclasNecesarias, columnas, corazón, corazonesLiberados, glifosDelSuelo, glifosDelSueloNecesarios, contacto, quiénesLoTocan, cuántosDebenTocarlo, murosDelPatio, segundosParaAbrirse]`

- Fase: 0 dormido · 1 olvido · 2 furia · 3 recuerdo · 4 liberado. Silencio: de 100 a 0.
- Estado: `sleep`, `rise`, `idle`, `walk`, `slam_w`, `sweep_w`, `summon_w`, `recover`, `kneel`, `freed`,
  `transit` (camina a la explanada), `rain_w`, `rain`, `charge_w`, `charge`, `stunned`, `bound`
  (sujeto por las cadenas, corazón expuesto) y `ritual`.
- Escombros: lista de `[x, z, radio, segundosQueQuedan]`. Columnas: lista de `[zócalo, segundosQueQuedan]`.
- `anclasActivas` y `quiénesLoTocan` son máscaras de bits (de anclas y de slots de jugador).
  `corazón` y `contacto` van de 0 a 100.
- `murosDelPatio`: 0 cerrados · 1 abriéndose · 2 abiertos (los dos laterales y el del fondo; la portada
  no se mueve). Se abren cuando despierta y se cierran cuando vuelve a dormirse (derrota o ronda nueva);
  liberado, quedan abiertos. **Sólo dejan de ser sólidos en el estado 2**, en el servidor y en la
  predicción del cliente; `segundosParaAbrirse` es lo que falta (3,6 s en total; 1,8 s tras «El despertar»).

Sus eventos van con los de combate (`["boss", tipo, …]`):

| Fase | Eventos |
| --- | --- |
| 1 | `awake` (fase, glifos) · `tele` (ataque, segundos, dónde) · `slam` · `sweep` · `summon` · `glyph` · `far` · `phase` (fase nueva, silencio) · `fail` |
| 2 | `transit` · `arena` · `pillar` (zócalo, quién) · `pillar_max` · `pillar_down` · `rain` · `charge` · `charge_end` · `crash` (zócalo, segundos aturdido) · `shake` · `anchor` (cuál, activa) · `bound` · `unbound` · `clang` (golpe sin efecto) · `heart_hit` (quién, daño, corazón) · `heart` (liberados, total, silencio, quién) |
| 3 | `ritual` · `lit` (encendidos, necesarios, quién) · `contact` · `pulse` · `freed` |

`tele` avisa de un ataque antes de que caiga (cuál, cuánto falta y dónde): `slam`, `sweep`, `summon`,
`rain`, `charge` y `pulse`.

Lo que el cliente manda y cuenta para el jefe es sólo su entrada de siempre: moverse (pisar un
ancla), el botón especial del alux (tocar una criatura o el glifo de una columna; **mantenerlo**
junto al guardián es el contacto del ritual) y los ataques de Balam (contra el corazón expuesto).
`talk` con `n: "nojoch"` sólo cuenta con el guardián liberado y estando a su lado.

### `snap.p` — jugadores

`[lugar, últimaEntradaProcesada, conectado, vida, ...estado]`, donde el estado simulado son 19 valores:

`[x, y, z, vy, giro, forma, cdForma, banderas, energía, cd1, cd2, cd3, esquiva, esquivaX, esquivaZ, carga, empujeX, empujeZ, botonesPrevios]`

Banderas: 1 en el suelo · 2 nadando · 4 en salto ofensivo · 8 caído. Los temporizadores van en ticks.

### `snap.e` — enemigos

`[id, tipo, x, y, z, giro, vida, vidaMáx, estado, lugarDelObjetivo]`
Tipos: 0 guardián de piedra · 1 criatura corrompida. Estados: `idle, chase, windup, strike, recover, stun, dead, return`.

### `snap.w` — mundo

`[santuarioAbierto, máscaraDeAltares, altaresNecesarios, emboscada, enemigosRestantes, puntoDeReaparición, braseroListo, votosOtraRonda, conectados, esperaDeAltares, historia]`
`historia` son banderas del progreso narrativo de la sala (1 = alguien habló con Chiich Yaxché · 2 = Nojoch Tuunich liberado · 4 = el guardián dio la pista del Cenote).
Al final van dos valores más: los segundos que le quedan a la cinemática compartida en curso (0 si no
hay; mientras sea mayor que 0 la sala está en pausa) y los votos para omitirla.
Emboscada: 0 pendiente · 1 en curso · 2 superada · 3 fallida (vuelve sola a 0 tras la espera).
`esperaDeAltares` son los segundos que faltan para que los altares respondan de nuevo (tras una derrota o al empezar otra ronda).

### `snap.ev` — eventos de combate

| Evento | Significado |
| --- | --- |
| `["act", lugar, acción, giro, potencia]` | Un jugador hizo algo (para animarlo): `bolt, claw, charged, pounce, pounce_land, dodge, interact, charge_start, charge_cancel, form`. |
| `["bolt", id, lugar, x, y, z, giro]` / `["bolt_end", id, x, y, z, impactó]` | Vida de un proyectil. |
| `["hit", "e"｜"p", idOLugar, daño, vidaRestante, lugarAtacante]` | Daño a un enemigo o a un jugador. |
| `["die", "e"｜"p", idOLugar, purificado, lugarAutor]` | Muerte o caída. |
| `["respawn", lugar]` · `["heal", lugar, cantidad, vida]` · `["evade", lugar]` | Reaparición, curación, golpe esquivado. |
| `["eatk", idEnemigo]` · `["brazier", lugar]` · `["enc", "start"｜"clear"｜"fail", n]` | Golpe de guardián, brasero usado, emboscada (empieza, superada, perdida). |

Como WebSocket entrega en orden y sin pérdidas, cada evento llega exactamente una vez.

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
| Mensajes inventados (`pos`, `hit`, `reward`…) o campos extra (`hp`, `dmg`…) | Se ignoran. |
| Pedir una forma no desbloqueada | Se ignora: las formas salen del ticket, no del cliente. |
| Atacar sin enfriamiento o sin energía | El enfriamiento y la energía viven en el estado del servidor. |
| Golpear desde lejos | El servidor comprueba alcance, arco y altura con sus propias posiciones. |
| Más de 90 mensajes por segundo o mensajes de más de 4 KB | Expulsión. |
| Quinto jugador | `room_full` (la API ya lo impide al pedir el ticket). |
| Conexión que deja de enviar 15 s | Se libera; el jugador puede reconectarse. |
| Recompensas duplicadas | La API usa una clave de idempotencia por jugador y recompensa. |

Todo esto está cubierto por `tests/protocol.test.ts`. Las garantías de la simulación de movimiento
están en [simulacion.md](simulacion.md) y las reglas de combate en [combate.md](combate.md).
