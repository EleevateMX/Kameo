extends RefCounted
## Región abierta «Camino a Motul»: el primer tramo del mundo abierto (docs/OPEN_WORLD.md).
## Un camino blanco entre monte bajo y albarradas que sale de Mérida hacia el este-noreste —donde
## queda Motul respecto a Mérida— con una milpa, un cenote y un henequenal a los lados. Es una
## interpretación fantástica: no reproduce la carretera real ni ningún lugar concreto.
##
## Datos y movimiento compartidos por el servidor de zonas y el cliente, como zone_def.gd con la
## plaza. Ejes: x = este, z = sur (el norte es −z), igual que en la plaza.
##
## Lo transitable es la unión de un pasillo alrededor del eje del camino (ROAD, medio ancho
## ROAD_HALF) y unos claros redondos (CLEARINGS). Fuera de eso hay albarrada y monte.

const ID := "camino_motul"
const NAME := "Camino a Motul"
const ALIAS := "el camino blanco"

const PLAYER_R := 0.45

# ── Geometría (metros) ──
## Eje del camino, de la salida de Mérida (oeste) al cartel de Motul (este-noreste): 222 m.
const ROAD: Array = [
	Vector2(0.0, 0.0), Vector2(26.0, -4.0), Vector2(52.0, -16.0), Vector2(78.0, -20.0), Vector2(104.0, -34.0),
	Vector2(128.0, -52.0), Vector2(154.0, -58.0), Vector2(180.0, -72.0), Vector2(204.0, -80.0),
]
const ROAD_HALF := 9.0             # medio ancho transitable (entre albarradas)
const ROAD_WHITE := 2.3            # medio ancho del camino blanco
## Claros: [x, z, radio]. En este orden: salida de Mérida, milpa, cenote, henequenal, llegada a Motul.
const CLEARINGS: Array = [
	[4.0, 0.0, 12.0], [44.0, 6.0, 12.0], [92.0, -46.0, 14.0], [140.0, -38.0, 14.0], [206.0, -81.0, 13.0],
]
const MILPA := Vector2(44.0, 6.0)
const CENOTE := Vector2(92.0, -50.0)       # el ojo de agua (no se pisa)
const CENOTE_R := 5.0
const HENEQUENAL := Vector2(140.0, -38.0)
const SIGN := Vector2(199.0, -78.3)        # el cartel de bienvenida de Motul cruza el camino aquí

## Zonas seguras: [x, z, radio]. Dentro no entran criaturas ni se combate.
const SAFE: Array = [[4.0, 0.0, 26.0], [204.0, -80.0, 26.0]]
## Dónde se reaparece tras caer, una por zona segura (misma posición que SAFE)
const RESPAWNS: Array = [Vector2(6.0, -0.6), Vector2(197.0, -77.6)]

## Obstáculos redondos, por grupos: [x, z, radio]. El movimiento usa la suma (PILLARS).
const ARCH_JAMBS: Array = [[-5.2, -2.7, 0.7], [-5.2, 2.7, 0.7]]                  # arco de la salida de Mérida
const SIGN_POSTS: Array = [[200.3, -74.3, 0.4], [197.7, -82.3, 0.4]]             # postes del cartel de Motul
## Mojoneras de jade: marcan a los dos lados del camino dónde acaba cada zona segura
const MARKERS: Array = [[32.1, 0.4, 0.45], [26.6, -11.4, 0.45], [182.2, -65.8, 0.45], [176.0, -77.3, 0.45]]
const TREES: Array = [
	[15.0, 4.2, 0.7],                                                            # el flamboyán de la cordelera
	[37.1, -3.1, 0.55], [56.1, -22.7, 0.55], [72.8, -12.6, 0.55], [108.6, -29.9, 0.55], [116.6, -50.9, 0.55],
	[148.4, -62.4, 0.55], [166.4, -57.3, 0.55], [171.0, -74.0, 0.55],
	[101.5, -50.5, 0.9],                                                         # el árbol grande del cenote
]
const WATER: Array = [[92.0, -50.0, 5.0]]                                        # el cenote
## Matas de henequén dentro del claro (las demás son decorado, fuera de la albarrada)
const AGAVES: Array = [[131.5, -36.5, 0.8], [134.5, -30.0, 0.8], [146.5, -44.5, 0.8], [149.0, -37.5, 0.8]]
const PROPS: Array = [[10.2, 7.0, 0.6], [145.5, -28.5, 0.9], [40.0, 12.5, 0.3]]   # rueda de corchar · veleta · espantapájaros
## Quien da la misión (nombre provisional, pendiente de la biblia de historia)
const QUEST_NPC := Vector2(12.5, 5.5)
const NPC_PILLARS: Array = [[12.5, 5.5, 0.4]]
const PILLARS: Array = ARCH_JAMBS + SIGN_POSTS + MARKERS + TREES + WATER + AGAVES + PROPS + NPC_PILLARS

## Obstáculos rectangulares: [x, z, medio ancho, medio fondo]
const WALLS: Array = [[-7.0, 0.0, 1.2, 16.0]]                                    # la muralla blanca de Mérida
const HUTS: Array = [[49.5, 11.5, 1.7, 1.4], [141.5, -27.2, 1.6, 1.0], [212.5, -86.5, 1.5, 1.0]]   # troje · pila · carreta
const BOXES: Array = WALLS + HUTS

# ── Pasos, llegadas y puntos de interés ──
const GATE_MERIDA := Vector2(-3.6, 0.0)    # bajo el arco: de vuelta a la plaza
const GATE_MERIDA_R := 3.4
const GATE_CART := Vector2(210.6, -84.6)   # la carreta de regreso, junto al cartel de Motul
const GATE_CART_R := 2.8
const ARRIVE := Vector2(3.0, 0.0)          # adonde se llega desde Mérida (y donde se entra con ticket)
const ARRIVE_YAW := PI * 0.5               # mirando al este, camino adelante
const NPC_R := 3.0                         # alcance para hablar con quien da la misión

## Puntos de descubrimiento: al acercarse por primera vez, el servidor lo valida por posición y
## pide a la API la recompensa `discovery` con `id` como clave (una vez por jugador y lugar).
const DISCOVERIES: Array = [
	{"id": "camino_motul:milpa", "name": "La milpa del camino", "at": Vector2(44.0, 8.0), "r": 5.0},
	{"id": "camino_motul:cenote", "name": "El cenote escondido", "at": Vector2(92.0, -43.5), "r": 5.0},
	{"id": "camino_motul:henequenal", "name": "El henequenal", "at": Vector2(140.0, -38.0), "r": 5.0},
	{"id": "camino_motul:cartel_motul", "name": "La entrada de Motul", "at": Vector2(199.0, -78.3), "r": 6.0},
]

## Criaturas hostiles: [tipo (wild_def.gd), x, z]. Su identificador es su posición en esta lista.
## Todas quedan fuera de las zonas seguras.
const SPAWNS: Array = [
	["zarza", 44.1, -11.8], ["zarza", 59.4, -14.1], ["henequen", 72.4, -22.2], ["zarza", 88.4, -23.3],
	["zarza", 100.4, -34.9], ["henequen", 116.4, -39.5], ["zarza", 127.5, -55.0], ["zarza", 152.6, -57.7],
	["henequen", 141.0, -35.0], ["zarza", 47.5, 3.5],
]

# ── Movimiento (los mismos números que en la plaza) ──
const TICK := 20
const DT := 0.05
const SPEED := 5.2
const JUMP := 6.2
const GRAVITY := 18.0


## Punto de llegada del alux número `i` (repartidos en corro para que no aparezcan encimados).
static func spawn(i: int) -> Vector2:
	var a := TAU * float(i % 8) / 8.0
	return ARRIVE + Vector2(sin(a), cos(a)) * (1.2 + 0.9 * float((i / 8) % 3))


static func is_safe(x: float, z: float) -> bool:
	for s in SAFE:
		var dx := x - float(s[0])
		var dz := z - float(s[1])
		if dx * dx + dz * dz <= float(s[2]) * float(s[2]):
			return true
	return false


## Devuelve (x, z) metido dentro de lo transitable, dejando `margin` hasta el borde.
static func confine(x: float, z: float, margin: float) -> Vector2:
	var p := Vector2(x, z)
	var best := INF
	var best_c := Vector2.ZERO
	var best_r := 0.0
	var half := ROAD_HALF - margin
	for i in range(ROAD.size() - 1):
		var a: Vector2 = ROAD[i]
		var ab: Vector2 = (ROAD[i + 1] as Vector2) - a
		var c := a + ab * clampf((p - a).dot(ab) / ab.length_squared(), 0.0, 1.0)
		var d := p.distance_to(c) - half
		if d <= 0.0:
			return p
		if d < best:
			best = d
			best_c = c
			best_r = half
	for cl in CLEARINGS:
		var c := Vector2(float(cl[0]), float(cl[1]))
		var d := p.distance_to(c) - (float(cl[2]) - margin)
		if d <= 0.0:
			return p
		if d < best:
			best = d
			best_c = c
			best_r = float(cl[2]) - margin
	# Fuera de todo: al borde de la forma más cercana
	return best_c + (p - best_c).normalized() * best_r


## Saca (x, z) de los obstáculos, para un cuerpo de radio `r`.
static func push_out(x: float, z: float, r: float) -> Vector2:
	for _pass in 2:
		for p in PILLARS:
			var dx := x - float(p[0])
			var dz := z - float(p[1])
			var need := float(p[2]) + r
			var d2 := dx * dx + dz * dz
			if d2 < need * need:
				var d := sqrt(d2)
				if d < 0.0001:
					dx = 1.0
					dz = 0.0
					d = 1.0
				x = float(p[0]) + dx / d * need
				z = float(p[1]) + dz / d * need
		for b in BOXES:
			var cx := clampf(x, float(b[0]) - float(b[2]), float(b[0]) + float(b[2]))
			var cz := clampf(z, float(b[1]) - float(b[3]), float(b[1]) + float(b[3]))
			var ox := x - cx
			var oz := z - cz
			var o2 := ox * ox + oz * oz
			if o2 < r * r:
				if o2 > 0.000001:
					var o := sqrt(o2)
					x = cx + ox / o * r
					z = cz + oz / o * r
				else:
					# el centro quedó dentro de la caja: sale por la cara más cercana
					var left := x - (float(b[0]) - float(b[2]))
					var right := (float(b[0]) + float(b[2])) - x
					var back := z - (float(b[1]) - float(b[3]))
					var front := (float(b[1]) + float(b[3])) - z
					var m := minf(minf(left, right), minf(back, front))
					if m == left:
						x = float(b[0]) - float(b[2]) - r
					elif m == right:
						x = float(b[0]) + float(b[2]) + r
					elif m == back:
						z = float(b[1]) - float(b[3]) - r
					else:
						z = float(b[1]) + float(b[3]) + r
	return Vector2(x, z)


## Avanza un paso. `s` = [x, y, z, vy]; devuelve el estado nuevo. Mismo contrato que
## zone_def.step: el servidor lo aplica una vez por entrada y el cliente predice con él.
static func step(s: Array, mx: float, mz: float, jump: bool) -> Array:
	var move := Vector2(mx, mz)
	if not (is_finite(move.x) and is_finite(move.y)):
		move = Vector2.ZERO
	if move.length() > 1.0:
		move = move.normalized()
	var x := float(s[0]) + move.x * SPEED * DT
	var z := float(s[2]) + move.y * SPEED * DT
	var y := float(s[1])
	var vy := float(s[3])
	if y <= 0.0 and jump:
		vy = JUMP
	vy -= GRAVITY * DT
	y += vy * DT
	if y <= 0.0:
		y = 0.0
		vy = 0.0
	var at := confine(x, z, PLAYER_R)
	at = push_out(at.x, at.y, PLAYER_R)
	return [at.x, y, at.y, vy]


## Punto del eje del camino a `dist` metros de la salida de Mérida, y hacia dónde sigue.
static func road_at(dist: float) -> Array:
	var left := maxf(dist, 0.0)
	for i in range(ROAD.size() - 1):
		var a: Vector2 = ROAD[i]
		var ab: Vector2 = (ROAD[i + 1] as Vector2) - a
		var len := ab.length()
		if left <= len or i == ROAD.size() - 2:
			return [a + ab * minf(left / len, 1.0), ab / len]
		left -= len
	return [ROAD[0], Vector2.RIGHT]


static func road_length() -> float:
	var total := 0.0
	for i in range(ROAD.size() - 1):
		total += (ROAD[i] as Vector2).distance_to(ROAD[i + 1])
	return total


## Distancia de (x, z) al eje del camino.
static func road_dist(x: float, z: float) -> float:
	var p := Vector2(x, z)
	var best := INF
	for i in range(ROAD.size() - 1):
		var a: Vector2 = ROAD[i]
		var ab: Vector2 = (ROAD[i + 1] as Vector2) - a
		best = minf(best, p.distance_to(a + ab * clampf((p - a).dot(ab) / ab.length_squared(), 0.0, 1.0)))
	return best


static func discovery_at(x: float, z: float) -> String:
	for d in DISCOVERIES:
		if Vector2(x, z).distance_to(d.at) <= float(d.r):
			return str(d.id)
	return ""
