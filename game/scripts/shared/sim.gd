extends RefCounted
## Simulación de movimiento determinista, compartida por cliente y servidor.
## Cada "input" avanza exactamente un tick (DT). El servidor es la autoridad;
## el cliente ejecuta el mismo código para predecir su propio alux.

const World := preload("res://scripts/shared/world_def.gd")

const TICK_RATE := 30
const DT := 1.0 / 30.0
const GRAVITY := 18.0
const STEP := 0.45          # altura que se sube sin saltar
const BODY_R := 0.4
const BODY_H := 1.3
const FORM_COOLDOWN := 1.0

## Formas disponibles. Todas las reglas de juego viven aquí.
const FORMS := {
	"alux": {"speed": 5.2, "jump": 6.2, "name": "Alux"},
	"balam": {"speed": 8.4, "jump": 8.6, "name": "Balam"},
}
const FORM_IDS: Array[String] = ["alux", "balam"]


class PlayerState:
	extends RefCounted
	var pos := Vector3.ZERO
	var vy := 0.0
	var yaw := 0.0
	var grounded := true
	var swim := false
	var form := "alux"
	var form_cd := 0.0

	func copy_from(o: PlayerState) -> void:
		pos = o.pos
		vy = o.vy
		yaw = o.yaw
		grounded = o.grounded
		swim = o.swim
		form = o.form
		form_cd = o.form_cd

	## [x, y, z, vy, yaw, forma, cd, banderas]
	func to_array() -> Array:
		return [
			snappedf(pos.x, 0.001), snappedf(pos.y, 0.001), snappedf(pos.z, 0.001),
			snappedf(vy, 0.001), snappedf(yaw, 0.01), FORM_IDS.find(form),
			snappedf(form_cd, 0.001), (1 if grounded else 0) | (2 if swim else 0),
		]

	func from_array(a: Array) -> void:
		pos = Vector3(a[0], a[1], a[2])
		vy = a[3]
		yaw = a[4]
		form = FORM_IDS[clampi(int(a[5]), 0, FORM_IDS.size() - 1)]
		form_cd = a[6]
		var flags := int(a[7])
		grounded = (flags & 1) != 0
		swim = (flags & 2) != 0


## Avanza un tick. `inp` = {mx, mz, j, f}. `unlocked` = formas permitidas.
static func step(s: PlayerState, inp: Dictionary, unlocked: Array, gate_open: bool) -> void:
	# Transformación
	s.form_cd = maxf(0.0, s.form_cd - DT)
	var want: String = inp.get("f", "")
	if want != "" and want != s.form and s.form_cd <= 0.0 and FORMS.has(want) and unlocked.has(want):
		s.form = want
		s.form_cd = FORM_COOLDOWN
	var form: Dictionary = FORMS[s.form]

	var dir := Vector2(float(inp.get("mx", 0.0)), float(inp.get("mz", 0.0)))
	var len := dir.length()
	if len > 1.0:
		dir /= len
		len = 1.0
	var speed: float = form.speed * (0.55 if s.swim else 1.0)
	if len > 0.05:
		s.yaw = atan2(dir.x, dir.y)

	if int(inp.get("j", 0)) != 0 and (s.grounded or s.swim):
		s.vy = form.jump * (0.75 if s.swim else 1.0)
		s.grounded = false
		s.swim = false
	s.vy = maxf(s.vy - GRAVITY * DT, -30.0)

	var was_grounded := s.grounded
	var x := s.pos.x + dir.x * speed * DT
	var z := s.pos.z + dir.y * speed * DT
	var y := s.pos.y + s.vy * DT

	# Obstáculos cilíndricos (árboles, columnas)
	for c in World.cylinders():
		var dx: float = x - c.x
		var dz: float = z - c.z
		var min_d: float = c.r + BODY_R
		var d2 := dx * dx + dz * dz
		if d2 < min_d * min_d:
			if d2 < 0.000001:
				dx = 1.0
				dz = 0.0
				d2 = 1.0
			var d := sqrt(d2)
			x = c.x + dx / d * min_d
			z = c.z + dz / d * min_d

	# Cajas (ruinas, muros, pirámide, puerta)
	for b in World.boxes():
		if gate_open and b.id == World.GATE_ID:
			continue
		if y >= b.top - STEP or y + BODY_H <= b.y0:
			continue
		var cx := clampf(x, b.x0, b.x1)
		var cz := clampf(z, b.z0, b.z1)
		var bx := x - cx
		var bz := z - cz
		var bd2 := bx * bx + bz * bz
		if bd2 >= BODY_R * BODY_R:
			continue
		if bd2 > 0.000001:
			var bd := sqrt(bd2)
			x = cx + bx / bd * BODY_R
			z = cz + bz / bd * BODY_R
		else:
			# El centro quedó dentro: salir por el lado más cercano
			var l: float = x - b.x0
			var r: float = b.x1 - x
			var t: float = z - b.z0
			var u: float = b.z1 - z
			var m := minf(minf(l, r), minf(t, u))
			if m == l:
				x = b.x0 - BODY_R
			elif m == r:
				x = b.x1 + BODY_R
			elif m == t:
				z = b.z0 - BODY_R
			else:
				z = b.z1 + BODY_R

	# Límite del claro
	var rr := sqrt(x * x + z * z)
	if rr > World.RADIUS:
		x = x / rr * World.RADIUS
		z = z / rr * World.RADIUS

	# Suelo
	var floor_y := floor_at(x, z, maxf(y, s.pos.y), gate_open)
	if y <= floor_y:
		y = floor_y
		s.vy = 0.0
		s.grounded = true
	elif was_grounded and s.vy <= 0.0 and y - floor_y < 0.35:
		y = floor_y  # pegarse al suelo al bajar pendientes
		s.vy = 0.0
		s.grounded = true
	else:
		s.grounded = false

	# Agua del cenote: flotar y nadar
	var float_y := World.WATER_LEVEL - 0.55
	if World.terrain_h(x, z) < World.WATER_LEVEL - 0.7 and y <= float_y:
		y = float_y
		s.vy = 0.0
		s.swim = true
		s.grounded = false
	else:
		s.swim = false

	s.pos = Vector3(x, y, z)


static func floor_at(x: float, z: float, feet: float, gate_open: bool) -> float:
	var f := World.terrain_h(x, z)
	for b in World.boxes():
		if gate_open and b.id == World.GATE_ID:
			continue
		if x > b.x0 - 0.15 and x < b.x1 + 0.15 and z > b.z0 - 0.15 and z < b.z1 + 0.15:
			if b.top <= feet + STEP and b.top > f:
				f = b.top
	return f
