# Progresión RPG de ALUX (primera versión, Alpha 0.5)

Nivel, experiencia, Semillas de Jade, inventario, equipamiento, mejoras de habilidad y gachapón.
Todo lo decide y lo guarda **la API**; el navegador y el cliente del juego sólo lo muestran. Sin
dinero real: las semillas sólo se ganan jugando.

> **Regla de diseño.** El nivel cuenta la trayectoria del alux y abre contenido; el poder de verdad
> sale de combinar formas, habilidades, prendas y amuletos. Un alux de nivel 5 tiene que ser útil al
> lado de uno de nivel 40: las bonificaciones son pequeñas a propósito.

## Números (fijados por el dueño)

| Qué | Valor |
| --- | --- |
| Nivel | Empieza en 1; máximo provisional 10 |
| Vida y energía base | 100 |
| Experiencia para pasar del nivel *n* al *n*+1 | `100 + 20·(n−1)²` |
| Vida por nivel | +1 % de la base por cada nivel por encima del 1 (nivel 10: 109) |
| Amuletos | Un espacio equipado. Común +2 %, raro +4 % |
| Gachapón | 100 semillas. 70 % común, 25 % raro, 4 % épico, 1 % legendario. Épico o mejor garantizado cada 20 tiradas |
| Tienda | Chispa I 100 · Garras I 150 · amuleto común 80 · amuleto raro 250 |

| Recompensa | XP | Semillas | Repetible |
| --- | --- | --- | --- |
| Purificar una criatura | 20 | 8 | Sí, con tope diario |
| Vencer a una criatura (sin purificarla) | 15 | 5 | Sí, con tope diario |
| Descubrir un lugar | 40 | 15 | No: una vez por lugar |
| Completar una misión | 100 | 40 | No: una vez por misión |
| Superar el Claro | 150 | 75 | Una vez al día |
| Primera liberación de Nojoch Tuunich | 300 | 150 | No: una sola vez |

**Decididos aquí, provisionales y pendientes de su visto bueno** (el dueño no dio cifra):

- Tope diario (día UTC) de las repetibles: 40 purificaciones y 40 criaturas vencidas con recompensa.
  Por encima se sigue jugando igual, sin XP ni semillas.
- Las criaturas las cobra **todo el grupo conectado**, no quien da el último golpe.
- Chispa I y Garras I: +10 % de daño de esa habilidad.
- Amuletos épico y legendario: +6 % y +8 %.
- Qué mejora cada amuleto: vida máxima o daño (ver catálogo en `packages/shared-contracts/src/rpg.ts`).

## Equilibrio en los niveles 1, 5 y 10

Lo calcula `npm run test:rpg -w @alux/tests` con las fórmulas de la API y el combate del Claro
(chispa 12 y garras 16 de daño base, ×1,5 contra corrompidas; criatura de 40 de vida que pega 15):

| Perfil | Vida | Chispa | Garras | Chispas para vencerla | Golpes que aguanta |
| --- | --- | --- | --- | --- | --- |
| Nivel 1, sin nada | 100 | 18 | 24 | 3 | 7 |
| Nivel 5, sin nada | 104 | 18 | 24 | 3 | 7 |
| Nivel 5, amuleto común de vida + Chispa I | 106 | 19,8 | 24 | 2 | 8 |
| Nivel 10, sin nada | 109 | 18 | 24 | 3 | 8 |
| Nivel 10, raro de daño + Chispa I + Garras I | 109 | 20,6 | 27,5 | 2 | 8 |
| Nivel 10, legendario de vida + mejoras | 118 | 19,8 | 26,4 | 2 | 8 |
| Nivel 10, legendario de daño + mejoras | 109 | 21,4 | 28,5 | 2 | 8 |

Lo máximo que permite esta versión frente a un recién llegado es +18 % de vida o +19 % de daño:
una chispa menos por criatura y un golpe más de aguante. El nivel solo no da daño. Por eso todavía
no hace falta escalar enemigos ni normalizar estadísticas en cooperativo.

Economía: la primera partida completa (12 criaturas, el Claro y Nojoch) da 285 semillas y deja en
el nivel 4: alcanza para la primera mejora y un amuleto común, no para todo. Repetir tiene tope:
como mucho 595 semillas al día (menos de seis tiradas).

## Dónde vive cada cosa

| Pieza | Sitio |
| --- | --- |
| Números, catálogo y fórmulas (compartidos) | `packages/shared-contracts/src/rpg.ts` |
| Tablas | `rpg_state` (xp, semillas, mejoras, amuleto equipado, contador de garantía), `rpg_items` (inventario), `rpg_ledger` (un apunte por movimiento, con clave única) |
| Reglas y transacciones | `apps/api/src/app.ts` + `store/*` |

## Contrato

**Perfil.** `GET /api/v1/me` añade `rpg`:
`{ level, xp, xpInLevel, xpToNext, seeds, skills: {chispa, garras}, equipped: itemId|null, items: [{id, item, rarity}], pity, stats: {hp, dmg} }`.

**Catálogo.** `GET /api/v1/rpg/catalog`: mejoras, amuletos con su precio y efecto, coste y
probabilidades del gachapón, y la tabla de recompensas. El juego pinta el puesto con esto.

**Tienda (sesión del jugador; todo idempotente por `requestId`, un UUID que genera el cliente):**

- `POST /api/v1/rpg/buy` `{ what: "skill:chispa" | "skill:garras" | "amulet:<id>", requestId }`
- `POST /api/v1/rpg/gacha` `{ requestId }` → `{ item, rarity, pity }` (repetir la petición devuelve el mismo resultado, no otra tirada)
- `POST /api/v1/rpg/equip` `{ itemId | null }`
- Errores: `400 invalid`, `402 not_enough_seeds`, `409 already_owned`.

**Recompensas (sólo servidores del juego, con la clave de servicio):**

`POST /internal/rpg/grant` `{ grants: [{ playerId, kind, key }] }`, con
`kind ∈ purify | enemy | discovery | mission | claro | nojoch` y `key` única por hecho.
La API calcula las cantidades (el servidor del juego no las manda), aplica topes y unicidad y
responde `{ results: [{ playerId, kind, applied, reason?, xp, seeds, level, leveledUp, totalXp, totalSeeds }] }`.
Repetir una clave no vuelve a pagar (`applied: false, reason: "duplicate"`). Claves:

| kind | key | Unicidad |
| --- | --- | --- |
| `purify`, `enemy` | `<sala o zona>:<ronda>:<id de criatura>` | Por clave, y tope diario |
| `discovery` | id del lugar (`camino_motul:cenote`) | Una vez por jugador y lugar |
| `mission` | id de la misión | Una vez por jugador y misión |
| `claro` | `<sala>:<ronda>` | Una al día por jugador |
| `nojoch` | `<sala>:<ronda>` | Una vez por jugador |

**Tickets.** El ticket de sala y el de zona llevan `rpg: { lv, hp, dmg: {chispa, garras, all} }`
ya calculado por la API (nivel + amuleto + mejoras). El servidor de mazmorras y el de zonas lo
aplican; nunca aceptan estadísticas del cliente. Sin ese campo valen 1, 100 y multiplicadores 1.

## Contra trampas y duplicados

- Cada movimiento es un apunte en `rpg_ledger` con clave única; el saldo se actualiza en la misma
  transacción. Un reintento choca con la clave y no hace nada.
- Compras y tiradas: se bloquea la fila del jugador (`select … for update`) antes de comprobar el
  saldo, así dos peticiones a la vez no gastan las mismas semillas.
- El gachapón tira en la API con `crypto.randomInt`; el resultado queda en el apunte.
- El cliente no puede otorgarse nada: `/internal/*` no es accesible desde fuera.

## Compatibilidad

Los perfiles existentes empiezan en nivel 1 sin perder nada: sellos, Pluma de Jade, formas y
progreso de capítulos siguen igual. La migración sólo añade tablas.

## Qué está hecho y probado

| Pieza | Estado |
| --- | --- |
| API: perfil, catálogo, compras, gachapón, equipar, recompensas internas | 8 pruebas, en memoria y contra PostgreSQL real (duplicados, topes, compras simultáneas, garantía) |
| Mazmorra: vida y daño del ticket, acotados; recompensas por purificar, vencer, el Claro y Nojoch | Prueba de protocolo (ticket absurdo acotado, un aviso por criatura, el cliente no puede concederse nada) |
| HUD de la mazmorra: nivel, experiencia, semillas, aviso de lo ganado y subida de nivel | En la prueba de flujo en navegador |
| Puesto de Saberes en la plaza: comprar, tirar, equipar | En la prueba de flujo en navegador |

## Lo que esta versión no hace todavía

Prendas y accesorios con estadísticas, rarezas con efectos especiales y sinergias, mejoras de
objetos, niveles 11–60, escalado de enemigos por nivel (con +9 % de vida como diferencia máxima no
hace falta aún), formas nuevas, y objetos poderosos por exploración (hoy épico y legendario sólo
salen del gachapón).
