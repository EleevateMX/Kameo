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
const STATES: Array[String] = ["sleep", "rise", "idle", "walk", "slam_w", "sweep_w", "summon_w", "recover", "kneel", "freed"]

## Dónde duerme (al fondo del patio, tras el pedestal del cristal) y hacia dónde mira (al portal).
const HOME := Vector2(32.0, 0.0)
const HOME_YAW := -PI * 0.5
const RADIUS := 1.4
const HEIGHT := 5.0
const SIT_HEIGHT := 3.4
const SPEED := 1.7
## Patio del santuario por dentro (x0, x1, z0, z1): ahí transcurre la fase 1.
const ARENA := [22.9, 33.1, -5.1, 5.1]
const RISE_TIME := 3.0          # tarda en ponerse en pie: nadie recibe daño mientras tanto
const REARM_TIME := 6.0         # tras una derrota, lo que tarda en poder despertar otra vez

const SILENCE_MAX := 100.0
const SILENCE_PER_PHASE := 34.0  # lo que pierde al completarse cada fase

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
