extends RefCounted
## Simulación determinista del jugador, compartida por cliente y servidor.
## Cada "input" avanza exactamente un tick (DT). El servidor es la autoridad;
## el cliente ejecuta el mismo código para predecir su propio personaje.
##
## Aquí se decide el MOVIMIENTO y la ACTIVACIÓN de habilidades (enfriamientos,
## energía, esquiva, salto ofensivo). El DAÑO nunca se decide aquí: la función
## sólo emite "acciones" y es el servidor quien comprueba a quién alcanzan.

const World := preload("res://scripts/shared/world_def.gd")
const Defs := preload("res://scripts/shared/combat_def.gd")

const TICK_RATE := 30
const DT := 1.0 / 30.0
const GRAVITY := 18.0
const STEP := 0.45          # altura que se sube sin saltar
const BODY_R := 0.4
const BODY_H := 1.3
const FORM_COOLDOWN := 1.0  # segundos
const MAX_SUBSTEP := 0.25   # ningún desplazamiento se resuelve en pasos mayores (evita atravesar muros)
const MAX_HSPEED := 22.0    # tope absoluto de velocidad horizontal

## Bits del campo "a" de cada input
const A_PRIMARY := 1
const A_SECONDARY := 2
const A_SPECIAL := 4

const FORMS := Defs.FORMS
const FORM_IDS: Array[String] = ["alux", "balam"]


## Los temporizadores se llevan en ticks enteros (no en segundos) para que el
## estado viaje por la red sin redondeos: cliente y servidor coinciden exactamente.
static func ticks(seconds: float) -> int:
	return int(round(seconds * TICK_RATE))


class PlayerState:
	extends RefCounted
	var pos := Vector3.ZERO
	var vy := 0.0
	var yaw := 0.0
	var grounded := true
	var swim := false
	var form := "alux"
	var form_cd := 0        # ticks
	var energy := 100.0     # siempre múltiplo de 0.5
	var cd1 := 0            # primaria (ticks)
	var cd2 := 0            # secundaria (ticks)
	var cd3 := 0            # especial (ticks)
	var dash_t := 0         # ticks restantes de esquiva (invulnerable mientras > 0)
	var dash_x := 0.0
	var dash_z := 1.0
	var charge_t := 0       # ticks cargando el golpe
	var pounce := false     # en el aire por el salto ofensivo
	var kx := 0.0           # empujón recibido (lo fija el servidor)
	var kz := 0.0
	var dead := false       # lo fija el servidor
	var prev_a := 0

	func copy_from(o: PlayerState) -> void:
		from_array(o.to_array_exact())

	func to_array_exact() -> Array:
		return [pos.x, pos.y, pos.z, vy, yaw, FORM_IDS.find(form), form_cd,
			(1 if grounded else 0) | (2 if swim else 0) | (4 if pounce else 0) | (8 if dead else 0),
			energy, cd1, cd2, cd3, dash_t, dash_x, dash_z, charge_t, kx, kz, prev_a]

	## Estado para la red:
	## [x, y, z, vy, giro, forma, cdForma, banderas(1 suelo, 2 nada, 4 salto ofensivo, 8 caído),
	##  energía, cd1, cd2, cd3, esquiva, esquivaX, esquivaZ, carga, empujeX, empujeZ, botonesPrevios]
	## Los temporizadores (ticks), la energía y las banderas viajan exactos; sólo se
	## redondean posición, velocidades y ángulos.
	func to_array() -> Array:
		var a := to_array_exact()
		for i in [0, 1, 2, 3, 16, 17]:
			a[i] = snappedf(a[i], 0.001)
		for i in [4, 13, 14]:
			a[i] = snappedf(a[i], 0.0001)
		return a

	func from_array(a: Array) -> void:
		pos = Vector3(a[0], a[1], a[2])
		vy = a[3]
		yaw = a[4]
		form = FORM_IDS[clampi(int(a[5]), 0, FORM_IDS.size() - 1)]
		form_cd = int(a[6])
		var flags := int(a[7])
		grounded = (flags & 1) != 0
		swim = (flags & 2) != 0
		pounce = (flags & 4) != 0
		dead = (flags & 8) != 0
		energy = a[8]
		cd1 = int(a[9])
		cd2 = int(a[10])
		cd3 = int(a[11])
		dash_t = int(a[12])
		dash_x = a[13]
		dash_z = a[14]
		charge_t = int(a[15])
		kx = a[16]
		kz = a[17]
		prev_a = int(a[18])


## Avanza un tick.
##   inp      = {mx, mz, j, f, a, r}  (dirección, salto, forma deseada, botones, giro de puntería)
##   unlocked = formas permitidas
##   open     = máscara de sólidos abiertos (World.OPEN_GATE, World.OPEN_COURT): la dicta el servidor
##   events   = si no es null, recibe las acciones emitidas en este tick:
##              {"k": tipo, "r": giro, "p": potencia}
static func step(s: PlayerState, inp: Dictionary, unlocked: Array, open: int, events: Variant = null) -> void:
	s.form_cd = maxi(0, s.form_cd - 1)
	s.cd1 = maxi(0, s.cd1 - 1)
	s.cd2 = maxi(0, s.cd2 - 1)
	s.cd3 = maxi(0, s.cd3 - 1)
	s.energy = minf(Defs.MAX_ENERGY, s.energy + Defs.ENERGY_PER_TICK)

	var a := int(inp.get("a", 0))
	var aim := float(inp.get("r", s.yaw))
	var dir := Vector2(float(inp.get("mx", 0.0)), float(inp.get("mz", 0.0)))
	var jump := int(inp.get("j", 0)) != 0
	if s.dead:
		a = 0
		dir = Vector2.ZERO
		jump = false
		s.charge_t = 0
		s.dash_t = 0
	var len := dir.length()
	if len > 1.0:
		dir /= len
		len = 1.0

	# Transformación (no en mitad de una esquiva, una carga o un salto ofensivo)
	var want: String = inp.get("f", "")
	if not s.dead and want != "" and want != s.form and s.form_cd <= 0 and FORMS.has(want) and unlocked.has(want) \
			and s.dash_t <= 0 and s.charge_t <= 0 and not s.pounce:
		s.form = want
		s.form_cd = ticks(FORM_COOLDOWN)
		_emit(events, "form", s.yaw, 0.0)
	var form: Dictionary = FORMS[s.form]
	var pressed := a & ~s.prev_a
	s.prev_a = a
	var speed_mul := 1.0
	var acted := false

	if not s.dead:
		# ── Primaria: se repite mientras se mantenga pulsada ──
		var pri: Dictionary = form.primary
		if (a & A_PRIMARY) != 0 and s.cd1 <= 0 and s.dash_t <= 0 and s.charge_t <= 0 and not s.pounce:
			s.cd1 = ticks(pri.cd)
			s.yaw = aim
			acted = true
			_emit(events, pri.kind, aim, 0.0)

		# ── Secundaria ──
		var sec: Dictionary = form.secondary
		if sec.kind == "dodge":
			if (pressed & A_SECONDARY) != 0 and s.cd2 <= 0 and s.energy >= sec.cost and s.dash_t <= 0:
				s.energy -= sec.cost
				s.cd2 = ticks(sec.cd)
				s.dash_t = ticks(sec.dur)
				var d := dir if len > 0.05 else Vector2(sin(s.yaw), cos(s.yaw))
				d = d.normalized()
				s.dash_x = d.x
				s.dash_z = d.y
				_emit(events, "dodge", atan2(d.x, d.y), 0.0)
		elif sec.kind == "charge":
			var min_t := ticks(sec.min_t)
			var max_t := ticks(sec.max_t)
			if (a & A_SECONDARY) != 0:
				if s.charge_t > 0:
					s.charge_t = mini(max_t, s.charge_t + 1)
				elif s.cd2 <= 0 and s.energy >= sec.cost and not s.pounce and not s.swim:
					s.charge_t = 1
					_emit(events, "charge_start", aim, 0.0)
			elif s.charge_t > 0:
				if s.charge_t >= min_t:
					s.energy -= sec.cost
					s.cd2 = ticks(sec.cd)
					s.yaw = aim
					acted = true
					_emit(events, "charged", aim, clampf(float(s.charge_t - min_t) / float(max_t - min_t), 0.0, 1.0))
				else:
					_emit(events, "charge_cancel", aim, 0.0)
				s.charge_t = 0
			if s.charge_t > 0:
				speed_mul = 0.45
				s.yaw = aim
				acted = true
		if sec.kind != "charge":
			s.charge_t = 0

		# ── Especial ──
		var spe: Dictionary = form.special
		if (pressed & A_SPECIAL) != 0 and s.cd3 <= 0:
			if spe.kind == "pounce":
				if s.energy >= spe.cost and s.grounded and s.charge_t <= 0 and s.dash_t <= 0:
					s.energy -= spe.cost
					s.cd3 = ticks(spe.cd)
					s.vy = spe.vy
					s.grounded = false
					s.pounce = true
					s.dash_x = sin(aim)
					s.dash_z = cos(aim)
					s.yaw = aim
					jump = false
					_emit(events, "pounce", aim, 0.0)
			elif spe.kind == "interact":
				s.cd3 = ticks(spe.cd)
				_emit(events, "interact", s.yaw, 0.0)

	# ── Velocidad horizontal ──
	var vel := Vector2.ZERO
	if s.dash_t > 0:
		s.dash_t -= 1
		vel = Vector2(s.dash_x, s.dash_z) * float(FORMS[s.form].secondary.get("speed", 18.0))
		s.yaw = atan2(s.dash_x, s.dash_z)
	elif s.pounce:
		vel = Vector2(s.dash_x, s.dash_z) * float(FORMS[s.form].special.get("speed", 12.0))
	else:
		vel = dir * float(form.speed) * speed_mul * (0.55 if s.swim else 1.0)
		if len > 0.05 and not acted:
			s.yaw = atan2(dir.x, dir.y)
	# empujón recibido (decae solo)
	if s.kx != 0.0 or s.kz != 0.0:
		vel += Vector2(s.kx, s.kz)
		s.kx *= 0.8
		s.kz *= 0.8
		if absf(s.kx) < 0.05:
			s.kx = 0.0
		if absf(s.kz) < 0.05:
			s.kz = 0.0
	var hs := vel.length()
	if hs > MAX_HSPEED:
		vel = vel / hs * MAX_HSPEED

	if jump and (s.grounded or s.swim) and s.dash_t <= 0 and s.charge_t <= 0:
		s.vy = float(form.jump) * (0.75 if s.swim else 1.0)
		s.grounded = false
		s.swim = false
	s.vy = maxf(s.vy - GRAVITY * DT, -30.0)

	var was_grounded := s.grounded
	var y := s.pos.y + s.vy * DT

	# ── Desplazamiento horizontal en pasos cortos, resolviendo colisiones en cada uno ──
	var p := move_xz(Vector2(s.pos.x, s.pos.z), vel * DT, y, BODY_R, open)

	# ── Suelo ──
	var floor_y := floor_at(p.x, p.y, maxf(y, s.pos.y), open)
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

	# ── Agua del cenote: flotar y nadar ──
	var float_y := World.WATER_LEVEL - 0.55
	if World.terrain_h(p.x, p.y) < World.WATER_LEVEL - 0.7 and y <= float_y:
		y = float_y
		s.vy = 0.0
		s.swim = true
		s.grounded = false
	else:
		s.swim = false

	# Al caer puede haber quedado junto a algo que a esta altura sí estorba
	if not is_free(p, y, BODY_R, open):
		p = resolve_xz(p, y, BODY_R, open)

	if s.pounce and (s.grounded or s.swim):
		s.pounce = false
		_emit(events, "pounce_land", s.yaw, 0.0)

	s.pos = Vector3(p.x, y, p.y)


static func _emit(events: Variant, kind: String, yaw: float, power: float) -> void:
	if events != null:
		events.append({"k": kind, "r": yaw, "p": power})


## Desplaza un círculo de radio `r` resolviendo colisiones en pasos cortos.
## Si tras resolver un paso el círculo sigue solapando algo (p. ej. una esquina
## entre dos obstáculos), ese paso se descarta: nunca se acepta una posición inválida.
## La usan los jugadores y también los enemigos del servidor.
static func move_xz(from: Vector2, delta: Vector2, y: float, r: float, open: int) -> Vector2:
	var p := from
	var steps := maxi(1, int(ceil(delta.length() / MAX_SUBSTEP)))
	var start_ok := is_free(p, y, r, open)
	for i in steps:
		var cand := resolve_xz(p + delta / float(steps), y, r, open)
		if start_ok and not is_free(cand, y, r, open):
			break  # bloqueado: se queda en la última posición válida
		p = cand
	return p


## Saca un círculo de radio `r` (a la altura `y`) de árboles, columnas, cajas y del borde del claro.
static func resolve_xz(p: Vector2, y: float, r: float, open: int) -> Vector2:
	var q := p
	for pass_i in 4:
		var next := _resolve_once(q, y, r, open)
		if next.is_equal_approx(q):
			return next
		q = next
	return q


## ¿Cabe un círculo de radio `r` en `p` sin tocar nada?
static func is_free(p: Vector2, y: float, r: float, open: int) -> bool:
	const TOL := 0.0005
	if p.length() > World.RADIUS + TOL:
		return false
	var near: Array = World.near(p.x, p.y)
	for c in near[0]:
		var dx: float = p.x - c.x
		var dz: float = p.y - c.z
		var min_d: float = c.r + r - TOL
		if dx * dx + dz * dz < min_d * min_d:
			return false
	for b in near[1]:
		if (open & b.opens) != 0:
			continue
		if y >= b.top - STEP or y + BODY_H <= b.y0:
			continue
		var bx := p.x - clampf(p.x, b.x0, b.x1)
		var bz := p.y - clampf(p.y, b.z0, b.z1)
		if bx * bx + bz * bz < (r - TOL) * (r - TOL):
			return false
	return true


static func _resolve_once(p: Vector2, y: float, r: float, open: int) -> Vector2:
	var x := p.x
	var z := p.y
	var near: Array = World.near(x, z)
	for c in near[0]:
		var dx: float = x - c.x
		var dz: float = z - c.z
		var min_d: float = c.r + r
		var d2 := dx * dx + dz * dz
		if d2 < min_d * min_d:
			if d2 < 0.000001:
				dx = 1.0
				dz = 0.0
				d2 = 1.0
			var d := sqrt(d2)
			x = c.x + dx / d * min_d
			z = c.z + dz / d * min_d

	for b in near[1]:
		if (open & b.opens) != 0:
			continue
		if y >= b.top - STEP or y + BODY_H <= b.y0:
			continue
		var cx := clampf(x, b.x0, b.x1)
		var cz := clampf(z, b.z0, b.z1)
		var bx := x - cx
		var bz := z - cz
		var bd2 := bx * bx + bz * bz
		if bd2 >= r * r:
			continue
		if bd2 > 0.000001:
			var bd := sqrt(bd2)
			x = cx + bx / bd * r
			z = cz + bz / bd * r
		else:
			# El centro quedó dentro: salir por el lado más cercano
			var l: float = x - b.x0
			var rt: float = b.x1 - x
			var t: float = z - b.z0
			var u: float = b.z1 - z
			var m := minf(minf(l, rt), minf(t, u))
			if m == l:
				x = b.x0 - r
			elif m == rt:
				x = b.x1 + r
			elif m == t:
				z = b.z0 - r
			else:
				z = b.z1 + r

	var rr := sqrt(x * x + z * z)
	if rr > World.RADIUS:
		x = x / rr * World.RADIUS
		z = z / rr * World.RADIUS
	return Vector2(x, z)


static func floor_at(x: float, z: float, feet: float, open: int) -> float:
	var f := World.terrain_h(x, z)
	for b in World.near(x, z)[1]:
		if (open & b.opens) != 0:
			continue
		if x > b.x0 - 0.15 and x < b.x1 + 0.15 and z > b.z0 - 0.15 and z < b.z1 + 0.15:
			if b.top <= feet + STEP and b.top > f:
				f = b.top
	return f


## ¿El punto (x, y, z) está dentro de algo sólido? (para proyectiles)
static func point_blocked(x: float, y: float, z: float, open: int) -> bool:
	if y < World.terrain_h(x, z):
		return true
	if x * x + z * z > World.RADIUS * World.RADIUS:
		return true
	var near: Array = World.near(x, z)
	for c in near[0]:
		var dx: float = x - c.x
		var dz: float = z - c.z
		if dx * dx + dz * dz < c.r * c.r:
			return true
	for b in near[1]:
		if (open & b.opens) != 0:
			continue
		if x > b.x0 and x < b.x1 and z > b.z0 and z < b.z1 and y < b.top and y > b.y0:
			return true
	return false
