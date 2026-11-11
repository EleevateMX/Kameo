extends SceneTree
## Prueba de la simulación de movimiento (se ejecuta sin ventana):
##   godot --headless --path game --script res://tests/sim_fuzz.gd
##
## Lanza cientos de personajes con entradas aleatorias y hostiles y comprueba,
## en cada tick, que la simulación respeta sus invariantes. Sale con código 1
## si alguna falla.

const Sim := preload("res://scripts/shared/sim.gd")
const World := preload("res://scripts/shared/world_def.gd")
const Defs := preload("res://scripts/shared/combat_def.gd")

const EPS := 0.002
const UNLOCKED := ["alux", "balam"]

var _seed := 1
var _fails: Array[String] = []
var _checks := 0
var _plain_ticks := 0
var _plain_over := 0


func _rand() -> float:
	_seed = (_seed * 1103515245 + 12345) % 2147483648
	return float(_seed) / 2147483648.0


func _fail(msg: String) -> void:
	if _fails.size() < 12:
		_fails.append(msg)


func _random_input(prev: Dictionary, hostile_dir: Vector2) -> Dictionary:
	# Cambia de intención de vez en cuando; a veces empuja con saña hacia un objetivo
	var inp := prev.duplicate()
	if _rand() < 0.08 or inp.is_empty():
		var a := _rand() * TAU
		var m := 1.0 if _rand() < 0.8 else _rand()
		inp = {"mx": cos(a) * m, "mz": sin(a) * m, "j": 0, "f": "", "a": 0, "r": _rand() * TAU - PI}
		if hostile_dir != Vector2.ZERO and _rand() < 0.6:
			inp.mx = hostile_dir.x
			inp.mz = hostile_dir.y
			inp.r = atan2(hostile_dir.x, hostile_dir.y)
	inp.j = 1 if _rand() < 0.15 else 0
	inp.a = int(_rand() * 8.0)
	inp.f = ""
	if _rand() < 0.02:
		inp.f = "balam" if _rand() < 0.5 else "alux"
	# Valores absurdos que un cliente modificado podría mandar (el servidor los recorta antes;
	# aquí se comprueba que la simulación tampoco se rompe con ellos)
	if _rand() < 0.01:
		inp.mx = 9999.0
	return inp


func _inside_sanctuary(pos: Vector3) -> bool:
	var s := World.SANCTUARY
	return pos.x > s.x - 5.4 and pos.x < s.x + 5.4 and absf(pos.z - s.y) < 5.4


func _check(s: Sim.PlayerState, prev: Vector3, gate_open: bool, tag: String, boosted: bool) -> void:
	_checks += 1
	var p := s.pos
	if not (is_finite(p.x) and is_finite(p.y) and is_finite(p.z)):
		_fail("%s: posición no finita %s" % [tag, p])
		return
	if Vector2(p.x, p.z).length() > World.RADIUS + EPS:
		_fail("%s: fuera del claro %s" % [tag, p])
	for c in World.cylinders():
		var d := Vector2(p.x - c.x, p.z - c.z).length()
		if d < c.r + Sim.BODY_R - EPS:
			_fail("%s: dentro de un cilindro (%s) a %.3f" % [tag, c.kind, d])
	for b in World.boxes():
		if gate_open and b.sealed:
			continue
		if p.y >= b.top - Sim.STEP - EPS or p.y + Sim.BODY_H <= b.y0:
			continue
		var cx := clampf(p.x, b.x0, b.x1)
		var cz := clampf(p.z, b.z0, b.z1)
		var d := Vector2(p.x - cx, p.z - cz).length()
		if d < Sim.BODY_R - EPS:
			_fail("%s: dentro de la caja %s (penetra %.3f) en %s" % [tag, b.id, Sim.BODY_R - d, p])
	var ground := World.terrain_h(p.x, p.z)
	var lowest := minf(ground, World.WATER_LEVEL - 0.55)
	if p.y < lowest - EPS:
		_fail("%s: por debajo del suelo (y=%.3f, suelo=%.3f)" % [tag, p.y, ground])
	var moved := Vector2(p.x - prev.x, p.z - prev.z).length()
	# Las colisiones pueden corregir la posición, pero nunca regalan velocidad extra
	var limit := Sim.MAX_HSPEED * Sim.DT + 0.45
	if moved > limit:
		_fail("%s: se movió %.3f m en un tick (límite %.3f)" % [tag, moved, limit])
	if not boosted:
		# Sin esquiva, salto ofensivo ni empujón, lo normal es no superar la carrera de Balam.
		# Una corrección de colisión puede añadir un poco en un tick suelto; se cuentan para
		# comprobar al final que son rarísimas (no un modo de ganar velocidad).
		_plain_ticks += 1
		if moved > 8.4 * Sim.DT + EPS:
			_plain_over += 1
	if s.energy < -EPS or s.energy > Defs.MAX_ENERGY + EPS:
		_fail("%s: energía fuera de rango %.2f" % [tag, s.energy])
	if s.cd1 < 0 or s.cd2 < 0 or s.cd3 < 0 or s.form_cd < 0:
		_fail("%s: enfriamiento negativo" % tag)


func _run_walker(seed_v: int, ticks: int, start: Vector2, hostile_to: Vector2, gate_open: bool, with_knock: bool) -> Sim.PlayerState:
	_seed = seed_v
	var s := Sim.PlayerState.new()
	var at := Sim.resolve_xz(start, World.terrain_h(start.x, start.y), Sim.BODY_R, gate_open)
	s.pos = Vector3(at.x, World.terrain_h(at.x, at.y), at.y)
	var started_inside := _inside_sanctuary(s.pos)
	var inp := {}
	var counts := {"bolt": 0, "claw": 0, "dodge": 0, "pounce": 0, "charged": 0}
	for t in ticks:
		var hostile := Vector2.ZERO
		if hostile_to != Vector2.INF:
			hostile = (hostile_to - Vector2(s.pos.x, s.pos.z)).normalized()
		inp = _random_input(inp, hostile)
		if with_knock and _rand() < 0.01:
			# empujón como los que aplica el servidor al recibir un golpe
			var ka := _rand() * TAU
			s.kx = cos(ka) * 7.0
			s.kz = sin(ka) * 7.0
			if hostile != Vector2.ZERO and _rand() < 0.5:
				s.kx = hostile.x * 7.0
				s.kz = hostile.y * 7.0
		var prev := s.pos
		var boosted := s.dash_t > 0 or s.pounce or absf(s.kx) > 0.0 or absf(s.kz) > 0.0 or (int(inp.a) & 6) != 0
		var evs: Array = []
		Sim.step(s, inp, UNLOCKED, gate_open, evs)
		for e in evs:
			if counts.has(e.k):
				counts[e.k] += 1
		_check(s, prev, gate_open, "semilla %d tick %d" % [seed_v, t], boosted)
		if not gate_open and not started_inside and _inside_sanctuary(s.pos):
			_fail("semilla %d tick %d: entró al santuario con la puerta cerrada en %s" % [seed_v, t, s.pos])
			break
		if _fails.size() >= 12:
			break
	# Las habilidades no pueden activarse más rápido que su enfriamiento
	var secs := ticks * Sim.DT
	var caps := {"bolt": 0.42, "claw": 0.38, "dodge": 0.9, "pounce": 3.0, "charged": 1.0}
	for k in counts:
		var cap := int(ceil(secs / float(caps[k]))) + 1
		if counts[k] > cap:
			_fail("semilla %d: %s se activó %d veces en %.0f s (máximo %d)" % [seed_v, k, counts[k], secs, cap])
	return s


func _init() -> void:
	var t0 := Time.get_ticks_msec()
	print("Simulación: prueba de invariantes")

	# 1) Paseantes aleatorios por todo el claro (con y sin puerta abierta, con empujones)
	for i in 240:
		_seed = 1000 + i
		var a := _rand() * TAU
		var r := _rand() * 40.0
		_run_walker(1000 + i, 900, Vector2(cos(a) * r, sin(a) * r), Vector2.INF, i % 3 == 0, i % 2 == 0)
	print("  paseantes aleatorios: %d comprobaciones" % _checks)

	# 2) Ataque dirigido al santuario con la puerta cerrada: desde todos los lados,
	#    esquivando, saltando y recibiendo empujones hacia dentro
	var before := _checks
	var san := World.SANCTUARY
	for i in 160:
		var a := float(i) / 160.0 * TAU
		var start := san + Vector2(cos(a), sin(a)) * (8.5 + float(i % 4))
		_run_walker(5000 + i, 700, start, san, false, true)
	# ...y desde la ladera de detrás, que queda más alta que los muros
	for i in 120:
		var a := -0.9 + 1.8 * float(i) / 120.0
		_run_walker(7000 + i, 700, Vector2(cos(a), sin(a)) * (41.0 + float(i % 5)), san, false, true)
	print("  asalto al santuario cerrado: %d comprobaciones" % (_checks - before))

	# 3) Contra cada árbol y columna, y contra el borde del claro
	before = _checks
	var n := 0
	for c in World.cylinders():
		n += 1
		if n % 3 != 0:
			continue
		_run_walker(9000 + n, 240, Vector2(c.x + 2.0, c.z + 1.0), Vector2(c.x, c.z), true, true)
	for i in 24:
		var a := float(i) / 24.0 * TAU
		_run_walker(12000 + i, 300, Vector2(cos(a), sin(a)) * 40.0, Vector2(cos(a), sin(a)) * 80.0, true, true)
	print("  obstáculos y borde: %d comprobaciones" % (_checks - before))

	# 3b) Velocidad sostenida: 20 s en línea recta por terreno abierto machacando todos los botones.
	#     Cota: carrera de Balam + lo que añaden esquivas y saltos ofensivos limitados por su enfriamiento.
	for form in ["alux", "balam"]:
		var s := Sim.PlayerState.new()
		s.form = form
		s.pos = Vector3(-30.0, World.terrain_h(-30.0, -8.0), -8.0)
		var start := s.pos
		var path := 0.0
		var secs := 6.0
		for t in int(secs * Sim.TICK_RATE):
			var prev := s.pos
			Sim.step(s, {"mx": 1.0, "mz": 0.0, "j": t % 2, "f": "", "a": (t % 2) * 7, "r": PI * 0.5}, UNLOCKED, true)
			path += Vector2(s.pos.x - prev.x, s.pos.z - prev.z).length()
		var base: float = Defs.FORMS[form].speed * secs
		var extra := 0.0
		if form == "alux":
			extra = (secs / 0.9 + 1.0) * (18.0 - 5.2) * 0.2      # esquivas
		else:
			extra = (secs / 3.0 + 1.0) * (12.5 - 8.4) * 0.9      # saltos ofensivos (≈0.8 s en el aire)
		if path > base + extra + 0.5:
			_fail("%s recorrió %.1f m en %.0f s (cota %.1f)" % [form, path, secs, base + extra])
		print("  velocidad sostenida %s: %.1f m en %.0f s (cota %.1f)" % [form, path, secs, base + extra])
	if _plain_over > _plain_ticks / 200:
		_fail("demasiados ticks por encima de la velocidad de carrera: %d de %d" % [_plain_over, _plain_ticks])
	print("  ticks sin impulso por encima de la carrera: %d de %d (correcciones de colisión)" % [_plain_over, _plain_ticks])

	# 4) Determinismo: mismas entradas → exactamente el mismo resultado
	var a1 := _run_walker(777, 1200, Vector2(3, 3), Vector2.INF, false, true).to_array_exact()
	var a2 := _run_walker(777, 1200, Vector2(3, 3), Vector2.INF, false, true).to_array_exact()
	if a1 != a2:
		_fail("la simulación no es determinista: %s vs %s" % [a1, a2])
	print("  determinismo: %s" % ("idéntico" if a1 == a2 else "DIFERENTE"))

	# 5) Predicción del cliente: partir del estado redondeado que manda el servidor y repetir
	#    las mismas entradas debe dar (casi) lo mismo que el servidor
	_seed = 4242
	var server := Sim.PlayerState.new()
	server.pos = Vector3(3, World.terrain_h(3, 3), 3)
	var client := Sim.PlayerState.new()
	client.copy_from(server)
	var inp := {}
	var worst := 0.0
	for t in 3000:
		inp = _random_input(inp, Vector2.ZERO)
		inp.mx = clampf(inp.mx, -1.0, 1.0)
		Sim.step(server, inp, UNLOCKED, false)
		Sim.step(client, inp, UNLOCKED, false)
		worst = maxf(worst, (server.pos - client.pos).length())
		if t % 2 == 1:
			client.from_array(server.to_array())  # como al recibir un estado por la red
	if worst > 0.02:
		_fail("la predicción se separa %.4f m del servidor" % worst)
	# y los valores discretos (temporizadores, energía, banderas) deben coincidir exactamente
	var se := server.to_array_exact()
	var ce := client.to_array_exact()
	for i in [5, 6, 7, 8, 9, 10, 11, 12, 15, 18]:
		if se[i] != ce[i]:
			_fail("el campo %d difiere entre cliente y servidor: %s vs %s" % [i, se[i], ce[i]])
	print("  predicción vs servidor: separación máxima %.5f m" % worst)

	var ms := Time.get_ticks_msec() - t0
	if _fails.is_empty():
		print("OK · %d comprobaciones en %d ms, sin violaciones" % [_checks, ms])
		quit(0)
	else:
		print("FALLOS (%d):" % _fails.size())
		for f in _fails:
			print("  - " + f)
		quit(1)
