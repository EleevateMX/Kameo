extends RefCounted
## Nojoch Tuunich, el Guardián Dormido: datos compartidos por cliente y servidor.
## Diseño: docs/BOSS.md. La lógica vive en server/boss.gd; el cliente sólo dibuja.
##
## No se le derrota destruyéndolo: su barra es de Silencio y baja cuando el grupo le devuelve
## la memoria. Por eso los golpes de los jugadores no le hacen nada.

const ID := "nojoch"
const NAME := "Nojoch Tuunich"
const TITLE := "El Guardián Dormido"

## Fases (viajan en el estado del jefe).
const ASLEEP := 0      # sentado al fondo del patio; despierta cuando el grupo entra con la emboscada superada
const OLVIDO := 1      # fase 1: purificar criaturas cerca de él enciende los glifos del pecho
const FURIA := 2       # fase 2: anclas, embestida y corazón expuesto
const RECUERDO := 3    # fase 3: todos lo tocan a la vez
const FREED := 4       # recordó: se queda como guardián del claro
const PHASE_NAMES: Array[String] = ["Dormido", "Olvido", "Furia", "Recuerdo", "Liberado"]

## Estados (su índice viaja en el estado del jefe).
const STATES: Array[String] = ["sleep", "rise", "idle", "walk", "slam_w", "sweep_w", "summon_w", "recover", "kneel", "freed",
	"transit", "pillars_w", "rain_w", "rain", "charge_w", "charge", "stunned", "bound", "ritual"]

## Dónde duerme (al fondo del patio, tras el pedestal del cristal) y hacia dónde mira (al portal).
const HOME := Vector2(32.0, 0.0)
const HOME_YAW := -PI * 0.5
const RADIUS := 1.4
const HEIGHT := 5.0
const SIT_HEIGHT := 3.4
const SPEED := 1.7
## Patio del santuario por dentro (x0, x1, z0, z1): ahí transcurre la fase 1.
const ARENA := [22.9, 33.1, -5.1, 5.1]
const RISE_TIME := 4.0          # tarda en ponerse en pie (lo que dura su animación): nadie recibe daño mientras tanto
const REARM_TIME := 6.0         # tras una derrota, lo que tarda en poder despertar otra vez

const SILENCE_MAX := 100.0
const SILENCE_PER_PHASE := 34.0  # lo que pierde al completarse la fase 1
## Silencio con el que empieza cada fase (también al reintentarla tras una derrota).
const SILENCE_AT := {OLVIDO: 100.0, FURIA: 66.0, RECUERDO: 33.0}

## Golpe de losa: aviso en el suelo, daño alto y escombros que siguen haciendo daño un rato.
const SLAM := {"windup": 1.2, "reach": 6.5, "radius": 3.5, "dmg": 26.0, "knock": 7.0, "recover": 1.1,
	"rubble_r": 2.4, "rubble_t": 12.0, "rubble_dmg": 3.0, "rubble_every": 0.5}
## Barrido: abanico por delante; se esquiva o se salta.
const SWEEP := {"windup": 0.9, "range": 4.6, "arc": 2.44, "dmg": 18.0, "knock": 9.0, "recover": 0.9}
## Llamada del Silencio: saca criaturas corrompidas de las esquinas del patio.
const SUMMON := {"windup": 1.4, "cd": 16.0, "recover": 0.8, "wake": 1.2}
const SUMMON_SPOTS: Array[Vector2] = [Vector2(24.6, -3.9), Vector2(24.6, 3.9), Vector2(27.4, -4.3), Vector2(27.4, 4.3)]
## Purificar una criatura a esta distancia de él (o menos) enciende un glifo.
const GLYPH_RANGE := 6.0
const GLYPHS := 4               # glifos tallados en el pecho

## Glifos que hacen falta para completar la fase 1, según los conectados.
static func glyphs_needed(players: int) -> int:
	return [2, 3, 4, 4][clampi(players, 1, 4) - 1]

## Criaturas que saca cada llamada.
static func summon_count(players: int) -> int:
	return [2, 2, 3, 4][clampi(players, 1, 4) - 1]

static func in_arena(x: float, z: float, margin := 0.0) -> bool:
	return x > float(ARENA[0]) - margin and x < float(ARENA[1]) + margin and z > float(ARENA[2]) - margin and z < float(ARENA[3]) + margin


# ───────────────────────── Fase 2: el corazón de piedra ─────────────────────────
## El combate sale del patio a la explanada: el guardián cruza el portal andando (nadie se
## teletransporta) y pelea alrededor de este punto.
const P2_HOME := Vector2(15.5, 0.0)
const P2_RADIUS := 12.0
const TRANSIT_SPEED := 3.2

## Anclas mágicas de la explanada. Con el guardián aturdido, pisarlas lo sujeta con cadenas de jade.
const ANCHORS: Array[Vector2] = [Vector2(10.8, -5.0), Vector2(10.8, 5.0), Vector2(19.4, 6.2), Vector2(8.4, 0.0)]
const ANCHOR_R := 1.4
## Un ancla sigue activa un rato después de soltarla: jugando solo, lo que dura la ventana del
## corazón (hay que pisarla y correr a golpear); en grupo, lo justo para recolocarse.
const ANCHOR_LATCH_SOLO := 10.0
const ANCHOR_LATCH := 2.0

## Anclas que hay que tener activas a la vez. Siempre queda al menos alguien libre para ser Balam.
static func anchors_needed(players: int) -> int:
	return [1, 1, 2, 2][clampi(players, 1, 4) - 1]

## Columnas: duermen bajo la explanada. Un alux las despierta tocando su glifo (F). Dan refugio
## de la lluvia de piedra y, si el guardián embiste contra una, la rompe y queda aturdido.
const PILLARS := {"count": 3, "life": 50.0, "radius": 0.9, "shelter": 2.6, "touch": 2.6, "crash": 2.0}
const PILLAR_SPOTS: Array[Vector2] = [Vector2(12.6, -2.6), Vector2(12.6, 2.6), Vector2(18.2, 2.8), Vector2(15.5, -6.0), Vector2(14.6, 5.4), Vector2(18.4, -2.2)]
## Lluvia de piedra: daña a quien no esté junto a una columna.
const RAIN := {"windup": 2.0, "dur": 4.0, "every": 0.5, "dmg": 6.0, "recover": 1.0, "cd": 20.0}
## Embestida: se orienta durante el aviso y fija la dirección al final; corre en línea recta.
const CHARGE := {"windup": 1.6, "lock": 0.5, "speed": 12.0, "dist": 16.0, "hit_r": 1.9, "dmg": 24.0, "knock": 10.0,
	"recover": 1.4, "stun": 7.0, "cd": 10.0}
## Sujeto por las cadenas: el corazón de la espalda queda expuesto un tiempo. Sólo Balam lo alcanza.
const BOUND := {"window": 9.0, "heart": 90.0, "recover": 1.8, "shove": 9.0, "shove_r": 5.0}

## Aguante del corazón en cada exposición (con cuatro jugadores hay dos Balam golpeando).
static func heart_pool(players: int) -> float:
	return float(BOUND.heart) * [1.0, 1.0, 1.0, 1.5][clampi(players, 1, 4) - 1]

## En la explanada no vuelve a entrar al patio ni se aleja de ella.
static func in_esplanade(x: float, z: float, margin := 0.0) -> bool:
	return x < 20.6 + margin and Vector2(x - P2_HOME.x, z - P2_HOME.y).length() < P2_RADIUS + margin
const EXPOSURES := 3                 # veces que hay que liberar el corazón
const SILENCE_PER_EXPOSURE := 11.0

# ───────────────────────── Fase 3: la memoria restaurada ─────────────────────────
## De rodillas en la explanada. Todos los que sigan en pie lo tocan a la vez (alux, mantener F).
## Primero hay que encender los glifos de memoria del suelo (purificando criaturas junto a él);
## después, todos los que sigan en pie lo tocan a la vez (alux, mantener F).
const RITUAL := {"time": 3.0, "time_solo": 4.0, "range": 4.6, "decay": 1.2, "block": 1.0, "wave_every": 9.0, "first_wave": 2.5,
	"far": 30.0}
## Última resistencia: un pulso de Silencio que empuja a quien esté pegado a él. No llega al borde
## del círculo de contacto: quien lo toca desde ahí (donde están los glifos) no tiene que soltarlo.
const PULSE := {"every": 11.0, "windup": 1.5, "radius": 3.6, "dmg": 10.0, "knock": 9.0}
## Glifos del suelo alrededor de él (posición relativa): se encienden al purificar.
const RITUAL_SPOTS: Array[Vector2] = [Vector2(0.0, -4.1), Vector2(4.1, 0.0), Vector2(0.0, 4.1), Vector2(-4.1, 0.0)]
## Por dónde llegan las criaturas del Silencio en la fase 3.
const RITUAL_GATES: Array[Vector2] = [Vector2(9.2, -6.6), Vector2(9.2, 6.6), Vector2(19.8, 5.6), Vector2(19.6, -3.2), Vector2(12.4, 8.2)]

## Glifos de memoria que hay que encender antes del contacto.
static func ritual_glyphs(players: int) -> int:
	return [1, 2, 2, 3][clampi(players, 1, 4) - 1]

## Última resistencia del Silencio: criaturas por oleada y máximo a la vez.
static func ritual_wave(players: int) -> int:
	return [1, 2, 2, 3][clampi(players, 1, 4) - 1]

static func ritual_max(players: int) -> int:
	return [2, 3, 4, 5][clampi(players, 1, 4) - 1]

## Recompensa por liberarlo (la da el servidor, una vez por jugador).
const REWARD := "pluma_de_jade"
