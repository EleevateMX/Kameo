extends RefCounted
## Lugar social: la plaza de «Mérida, la Ciudad Blanca» (interpretación fantástica; no reproduce
## la plaza real). Datos y movimiento compartidos por el servidor de zonas y el cliente.
##
## Es una pieza aparte del Claro de los Aluxes a propósito: no usa world_def.gd ni sim.gd, así que
## nada de lo que cambie aquí puede alterar las misiones (docs/OPEN_WORLD.md).
##
## El movimiento es deliberadamente sencillo —suelo llano, andar y saltar, choques con columnas y
## muros— y determinista: el servidor aplica cada entrada una vez y el cliente la predice con esta
## misma función.

const ID := "merida"
const NAME := "Mérida"
const ALIAS := "la Ciudad Blanca"

# ── Geometría (metros). La plaza es un cuadrado centrado en el origen. ──
const HALF := 34.0                 # medio lado transitable
const PLAYER_R := 0.45
## Columnas, troncos, fuente, farolas: [x, z, radio]
const PILLARS: Array = [
	[0.0, 0.0, 2.6],               # el gran árbol del centro, con su arriate
	[-15.0, 12.0, 2.5],            # fuente
	[15.0, -13.0, 2.9],            # quiosco
	# arcos del lado norte (una columna cada 6 m)
	[-27.0, -27.5, 0.55], [-21.0, -27.5, 0.55], [-15.0, -27.5, 0.55], [-9.0, -27.5, 0.55], [-3.0, -27.5, 0.55],
	[3.0, -27.5, 0.55], [9.0, -27.5, 0.55], [15.0, -27.5, 0.55], [21.0, -27.5, 0.55], [27.0, -27.5, 0.55],
	# jambas del portal del Claro (lado este)
	[30.5, -2.4, 0.7], [30.5, 2.4, 0.7],
	# farolas
	[-9.0, -9.0, 0.25], [9.0, -9.0, 0.25], [-9.0, 9.0, 0.25], [9.0, 9.0, 0.25],
	[-22.0, 0.0, 0.25], [22.0, 13.0, 0.25], [-7.0, 23.0, 0.25], [7.0, -20.0, 0.25],
]
## Muros y bancos: [x, z, medio ancho, medio fondo]
const BOXES: Array = [
	[0.0, -31.5, 34.0, 2.5],       # edificio de los arcos (norte)
	[-7.0, 4.6, 1.3, 0.35], [7.0, 4.6, 1.3, 0.35], [-7.0, -4.6, 1.3, 0.35], [7.0, -4.6, 1.3, 0.35],   # bancos del árbol
	[-15.0, 17.2, 1.3, 0.35], [-20.4, 12.0, 0.35, 1.3],                                             # bancos de la fuente
]
## Portal al Claro de los Aluxes (lado este) y su zona de uso
const PORTAL := Vector2(30.5, 0.0)
const PORTAL_R := 3.2
## Dónde aparecen los aluxes: en corro, al sur del árbol
const SPAWN_CENTER := Vector2(0.0, 13.0)
const SPAWN_RADIUS := 5.5
const SPAWN_SLOTS := 16

# ── Movimiento ──
const TICK := 20                   # entradas y pasos de simulación por segundo
const DT := 0.05
const SPEED := 5.2                 # como el alux en el Claro
const JUMP := 6.2
const GRAVITY := 18.0

# ── Interés por proximidad ──
const ENTER_R := 36.0              # a esta distancia un alux empieza a verse
const LEAVE_R := 44.0              # y a esta deja de verse (margen para que no parpadee)
const MAX_NEIGHBORS := 24          # como mucho, los más cercanos
const NEAR_R := 18.0               # más cerca: 10 estados por segundo; más lejos: 4
const NEAR_EVERY := 2              # cada cuántos pasos se manda un vecino cercano (20 / 2 = 10 Hz)
const FAR_EVERY := 5               # y uno lejano (20 / 5 = 4 Hz)
const DEFAULT_CAPACITY := 32       # se cambia con ALUX_ZONE_CAPACITY; ver las medidas en docs/OPEN_WORLD.md


static func spawn(i: int) -> Vector2:
	var a := TAU * float(i % SPAWN_SLOTS) / float(SPAWN_SLOTS) + (0.2 if (i / SPAWN_SLOTS) % 2 == 1 else 0.0)
	var r := SPAWN_RADIUS + 1.6 * float((i / SPAWN_SLOTS) % 3)
	return SPAWN_CENTER + Vector2(sin(a), cos(a)) * r


## Avanza un paso. `s` = [x, y, z, vy]; devuelve el estado nuevo. `mx`, `mz`: dirección en el
## mundo (se recorta a longitud 1); `jump`: quiere saltar.
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
	# Bordes de la plaza
	var lim := HALF - PLAYER_R
	x = clampf(x, -lim, lim)
	z = clampf(z, -lim, lim)
	# Dos pasadas: salir de un obstáculo no debe meter en el de al lado
	for _pass in 2:
		for p in PILLARS:
			var dx := x - float(p[0])
			var dz := z - float(p[1])
			var need := float(p[2]) + PLAYER_R
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
			if o2 < PLAYER_R * PLAYER_R:
				if o2 > 0.000001:
					var o := sqrt(o2)
					x = cx + ox / o * PLAYER_R
					z = cz + oz / o * PLAYER_R
				else:
					# el centro quedó dentro de la caja: sale por la cara más cercana
					var left := x - (float(b[0]) - float(b[2]))
					var right := (float(b[0]) + float(b[2])) - x
					var back := z - (float(b[1]) - float(b[3]))
					var front := (float(b[1]) + float(b[3])) - z
					var m := minf(minf(left, right), minf(back, front))
					if m == left:
						x = float(b[0]) - float(b[2]) - PLAYER_R
					elif m == right:
						x = float(b[0]) + float(b[2]) + PLAYER_R
					elif m == back:
						z = float(b[1]) - float(b[3]) - PLAYER_R
					else:
						z = float(b[1]) + float(b[3]) + PLAYER_R
	return [x, y, z, vy]


static func at_portal(x: float, z: float) -> bool:
	return Vector2(x, z).distance_to(PORTAL) <= PORTAL_R
