extends RefCounted
## Registro de zonas del servidor de zonas: qué lugares hay, cómo se mueve uno en cada uno y por
## dónde se pasa de uno a otro. Un solo proceso las sirve todas (docs/OPEN_WORLD.md).
##
## Añadir una zona = su archivo de datos (como camino_def.gd), una entrada aquí y su escenario en
## el cliente. El id de cada zona es el que firma la API en el ticket (ZONES en protocol.ts).

const Merida := preload("res://scripts/shared/zone_def.gd")
const Camino := preload("res://scripts/shared/camino_def.gd")

const IDS: Array[String] = ["merida", "camino_motul"]
const NAMES := {"merida": "Mérida", "camino_motul": "Camino a Motul"}
const ALIASES := {"merida": "la Ciudad Blanca", "camino_motul": "el camino blanco"}
## Zonas con criaturas, combate, descubrimientos y misiones (server/zone_wild.gd)
const WILD: Array[String] = ["camino_motul"]

## Pasos entre zonas. `at`, `r`: desde dónde se toma (lo comprueba el servidor) · `to`: adónde
## lleva · `pos`, `yaw`: dónde se llega (lo decide el servidor) · `verb`: el aviso de la tecla F.
const GATES := {
	"merida": [
		{"id": "a_motul", "to": "camino_motul", "at": Merida.GATE_MOTUL, "r": Merida.GATE_MOTUL_R, "pos": Camino.ARRIVE, "yaw": Camino.ARRIVE_YAW,
			"verb": "Tomar el camino a Motul", "travel": "Tomando el camino a Motul…"},
	],
	"camino_motul": [
		{"id": "a_merida", "to": "merida", "at": Camino.GATE_MERIDA, "r": Camino.GATE_MERIDA_R, "pos": Merida.ARRIVE_MOTUL, "yaw": -PI * 0.5,
			"verb": "Entrar a Mérida", "travel": "Entrando a Mérida…"},
		{"id": "carreta", "to": "merida", "at": Camino.GATE_CART, "r": Camino.GATE_CART_R, "pos": Merida.ARRIVE_MOTUL, "yaw": -PI * 0.5,
			"verb": "Volver a Mérida en la carreta", "travel": "La carreta te lleva de vuelta a Mérida…"},
	],
}


static func has(zone: String) -> bool:
	return IDS.has(zone)


static func is_wild(zone: String) -> bool:
	return WILD.has(zone)


static func step(zone: String, s: Array, mx: float, mz: float, jump: bool) -> Array:
	if zone == Camino.ID:
		return Camino.step(s, mx, mz, jump)
	return Merida.step(s, mx, mz, jump)


## Dónde aparece quien entra con ticket (no por un paso): [posición, giro].
static func entry(zone: String, i: int) -> Array:
	if zone == Camino.ID:
		return [Camino.spawn(i), Camino.ARRIVE_YAW]
	return [Merida.spawn(i), PI]


## El paso que se puede tomar desde (x, z) en esa zona, o {} si no hay ninguno al alcance.
static func gate_at(zone: String, x: float, z: float, slack := 0.0) -> Dictionary:
	for g in GATES.get(zone, []):
		if Vector2(x, z).distance_to(g.at) <= float(g.r) + slack:
			return g
	return {}
