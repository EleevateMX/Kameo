# Combate

Todo el combate se decide en el servidor (`game/scripts/server/combat.gd`). El cliente manda
botones y puntería, y representa los estados y eventos que recibe.

## Controles

| Acción | Ratón | Teclado |
| --- | --- | --- |
| Habilidad primaria (mantener = repetir) | Clic izquierdo | J |
| Habilidad secundaria | Clic derecho | K |
| Habilidad especial | — | F (o L) |
| Transformarse | — | 1 Alux · 2 Balam |

El primer clic sobre el juego sólo captura el ratón. Si hay un enemigo cerca de donde mira la
cámara, la puntería se ajusta sola hacia él.

## Formas y habilidades

Cada forma tiene tres habilidades. Vida (100) y energía (100, +15/s) son comunes a todas las
formas, y los enfriamientos se conservan al transformarse.

| Forma | Primaria | Secundaria | Especial |
| --- | --- | --- | --- |
| **Alux** | *Chispa de jade*: proyectil, 12 de daño, cada 0.42 s | *Esquiva*: 4 m con invulnerabilidad, 20 de energía, cada 0.9 s | *Tocar*: purifica criaturas debilitadas y activa el brasero |
| **Balam** | *Garras*: arco de 2.3 m, 16 de daño, cada 0.38 s | *Zarpazo cargado*: mantener y soltar, 22–60 de daño, empuja y aturde, 25 de energía | *Salto del jaguar*: salto ofensivo, 30 de daño en área al caer, 30 de energía, cada 3 s |

### Añadir una transformación

1. Añade una entrada a `FORMS` en `game/scripts/shared/combat_def.gd` con `speed`, `jump` y sus
   tres habilidades, eligiendo el `kind` de cada una entre los existentes (`bolt`, `claw`, `dodge`,
   `charge`, `pounce`, `interact`).
2. Añade su id a `FORM_IDS` en `sim.gd` y al catálogo del portal.
3. Dale un modelo en `avatar.gd`.

Si la forma necesita un tipo de habilidad nuevo: su activación (enfriamiento, energía, efecto sobre
el movimiento) va en `Sim.step`, y su efecto (a quién alcanza, cuánto daño) en
`Combat.player_action`.

## Enemigos

| Enemigo | Vida | Comportamiento | Debilidad |
| --- | --- | --- | --- |
| **Guardián de piedra** | 60 | Lento. Avisa 0.7 s (círculo rojo en el suelo) y golpea en área: 15 de daño. Resiste empujones. | La magia le hace la mitad de daño: conviene Balam. |
| **Criatura corrompida** | 40 | Rápida. Embiste 4–5 m tras un aviso corto: 10 de daño. | La magia le hace ×1.5. Con ≤40 % de vida, un alux puede **purificarla** tocándola: cae al instante y cura 15 a los jugadores cercanos. |

Estados de la IA: patrulla → persecución → aviso → ataque → recuperación (y aturdido, regreso,
muerto). Cada enemigo lleva una **tabla de amenaza** por jugador: persigue a quien más daño le ha
hecho (el zarpazo cargado genera amenaza extra), y a igualdad, al más cercano. La amenaza decae sola.
Los enemigos del claro vuelven a su sitio si se alejan 24 m y reaparecen a los 30 s de caer.

## Vida, caída y reaparición

- La vida se regenera (3/s) tras 6 s sin recibir daño.
- El **brasero de la plaza** cura 60 a quienes estén cerca cuando un alux lo toca (cada 12 s).
- Al llegar a 0 el jugador cae y reaparece a los 4 s en el **punto de control** con vida completa y
  2.5 s de invulnerabilidad. El punto inicial es la plaza; al superar la emboscada pasa a la entrada
  del santuario.

## La emboscada del santuario

Al abrirse la puerta (acertijo de los altares) despiertan los guardianes corrompidos frente al
santuario. La oleada escala con los jugadores conectados:

| Jugadores | Criaturas | Guardianes | Vida de cada enemigo |
| --- | --- | --- | --- |
| 1 | 2 | 1 | ×1.00 |
| 2 | 3 | 2 | ×1.25 |
| 3 | 4 | 2 | ×1.50 |
| 4 | 5 | 3 | ×1.75 |

El **Sello del Claro** ya no se entrega al abrir la puerta sino al vencer la emboscada, una sola
vez por jugador (libro de recompensas idempotente en la API).

## Qué valida el servidor

Impactos (alcance, arco y altura con sus propias posiciones), vida de jugadores y enemigos,
energía, enfriamientos, invulnerabilidad de la esquiva, muerte, reaparición y recompensas.
`tests/protocol.test.ts` comprueba que atacar fuera de alcance, repetir el botón más rápido que
el enfriamiento o mandar mensajes de daño inventados no tiene ningún efecto.
