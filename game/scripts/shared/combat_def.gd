extends RefCounted
## Datos de combate compartidos por cliente y servidor.
## Añadir una transformación nueva = añadir una entrada en FORMS con sus tres
## habilidades (primaria, secundaria, especial). La simulación (sim.gd) y el
## servidor (combat.gd) trabajan por "tipo" de habilidad, no por forma.

const MAX_HP := 100.0
const MAX_ENERGY := 100.0
const ENERGY_REGEN := 15.0       # por segundo
const ENERGY_PER_TICK := 0.5     # = ENERGY_REGEN / 30; exacto en coma flotante y en JSON
const HP_REGEN := 3.0            # por segundo, fuera de combate
const HP_REGEN_DELAY := 6.0
const RESPAWN_TIME := 4.0
const RESPAWN_INVULN := 2.5

## Tipos de habilidad disponibles:
##   bolt     proyectil mágico                    claw    golpe cuerpo a cuerpo en arco
##   dodge    esquiva con invulnerabilidad        charge  golpe cargado (mantener y soltar)
##   interact usar objetos / purificar enemigos   pounce  salto ofensivo con daño al caer
const FORMS := {
	"alux": {
		"name": "Alux", "speed": 5.2, "jump": 6.2,
		"primary": {"kind": "bolt", "name": "Chispa de jade", "cd": 0.42, "dmg": 12.0, "speed": 17.0, "life": 0.9, "radius": 0.45},
		"secondary": {"kind": "dodge", "name": "Esquiva", "cd": 0.9, "cost": 20.0, "dur": 0.2, "speed": 18.0},
		"special": {"kind": "interact", "name": "Tocar", "cd": 0.6, "range": 2.8},
	},
	"balam": {
		"name": "Balam", "speed": 8.4, "jump": 8.6,
		"primary": {"kind": "claw", "name": "Garras", "cd": 0.38, "dmg": 16.0, "range": 2.3, "arc": 1.9},
		"secondary": {"kind": "charge", "name": "Zarpazo cargado", "cd": 1.0, "cost": 25.0, "min_t": 0.3, "max_t": 1.2,
			"dmg_min": 22.0, "dmg_max": 60.0, "range": 2.9, "arc": 2.5, "knock": 7.0, "stun": 0.8},
		"special": {"kind": "pounce", "name": "Salto del jaguar", "cd": 3.0, "cost": 30.0, "vy": 7.2, "speed": 12.5,
			"dmg": 30.0, "radius": 2.8, "knock": 5.0, "stun": 0.5},
	},
}

## Enemigos. "mult" = multiplicador de daño según el tipo de ataque recibido.
const ENEMY_IDS: Array[String] = ["piedra", "corrupta"]
const ENEMIES := {
	"piedra": {
		"name": "Guardián de piedra", "hp": 60.0, "speed": 2.7, "radius": 0.7, "height": 1.5,
		"aggro": 9.0, "range": 1.9, "windup": 0.7, "recover": 0.9, "dmg": 15.0, "hit_radius": 2.0,
		"mult": {"bolt": 0.5}, "knock_resist": 0.4, "purify_at": 0.0,
	},
	"corrupta": {
		"name": "Criatura corrompida", "hp": 40.0, "speed": 5.0, "radius": 0.55, "height": 1.0,
		"aggro": 10.0, "range": 4.2, "windup": 0.4, "recover": 0.8, "dmg": 10.0, "hit_radius": 1.1,
		"lunge_speed": 13.0, "lunge_t": 0.35,
		"mult": {"bolt": 1.5}, "knock_resist": 1.0, "purify_at": 0.4,
	},
}
const ENEMY_STATES: Array[String] = ["idle", "chase", "windup", "strike", "recover", "stun", "dead", "return"]
const LEASH := 24.0
const AMBIENT_RESPAWN := 30.0

## Enemigos que rondan el claro (lejos de los altares): [tipo, x, z]
const AMBIENT := [
	["piedra", -22.0, -14.0],
	["piedra", 20.0, -20.0],
	["corrupta", -3.0, 28.0],
	["corrupta", 24.0, 14.0],
]

## Emboscada del santuario: aparece al abrirse la puerta. Escala con los jugadores.
const ENCOUNTER_CENTER := Vector2(15.0, 0.0)

static func encounter_wave(players: int) -> Array:
	var n := clampi(players, 1, 4)
	var out := []
	for i in 1 + n:
		out.append("corrupta")
	for i in 1 + n / 2:
		out.append("piedra")
	return out

static func hp_scale(players: int) -> float:
	return 1.0 + 0.25 * float(clampi(players, 1, 4) - 1)

## Brasero de la plaza: cura al tocarlo y es el punto de reaparición inicial.
const BRAZIER := Vector2(0.0, 0.0)
const BRAZIER_RANGE := 3.4
const BRAZIER_HEAL := 60.0
const BRAZIER_CD := 12.0
const PURIFY_HEAL := 15.0

## Puntos de reaparición (x, z). El segundo se activa al superar la emboscada.
const CHECKPOINTS: Array[Vector2] = [Vector2(0.0, 3.2), Vector2(13.0, 0.0)]
