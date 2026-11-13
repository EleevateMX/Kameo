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
const Boss := preload("res://scripts/shared/boss_def.gd")
const Combat := preload("res://scripts/server/combat.gd")

## Máscaras de sólidos abiertos (ver World.OPEN_*)
const SEALED := 0                                        # santuario sellado
const GATE := World.OPEN_GATE                            # portal abierto, muros del patio cerrados
const COURT := World.OPEN_GATE | World.OPEN_COURT        # portal y muros del patio abiertos
const WALL_TOP := 3.2   # altura de los muros del santuario sobre su suelo (que está a cota 0)

const EPS := 0.002
const UNLOCKED := ["alux", "balam"]

var _seed := 1
var _fails: Array[String] = []
var _checks := 0
var _plain_ticks := 0
var _plain_over := 0
var _court_entries := 0


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


## ¿Dentro del patio, lejos de la portada? (ahí sólo se llega por el portal… o por un muro abierto)
func _in_court(pos: Vector3) -> bool:
	return Boss.in_arena(pos.x, pos.z, -0.3) and pos.x > 24.0


func _check(s: Sim.PlayerState, prev: Vector3, open: int, tag: String, boosted: bool) -> void:
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
		if (open & int(b.opens)) != 0:
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


## `open`: máscara de sólidos abiertos. `court_guard`: con los muros del patio cerrados, comprueba
## que al patio sólo se entra por el portal (o por encima de un muro), nunca atravesándolo.
func _run_walker(seed_v: int, ticks: int, start: Vector2, hostile_to: Vector2, open: int, with_knock: bool, court_guard := false) -> Sim.PlayerState:
	_seed = seed_v
	var s := Sim.PlayerState.new()
	var at := Sim.resolve_xz(start, World.terrain_h(start.x, start.y), Sim.BODY_R, open)
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
		Sim.step(s, inp, UNLOCKED, open, evs)
		for e in evs:
			if counts.has(e.k):
				counts[e.k] += 1
		_check(s, prev, open, "semilla %d tick %d" % [seed_v, t], boosted)
		if (open & World.OPEN_GATE) == 0 and not started_inside and _inside_sanctuary(s.pos):
			_fail("semilla %d tick %d: entró al santuario con la puerta cerrada en %s" % [seed_v, t, s.pos])
			break
		if court_guard and _in_court(s.pos) and not _in_court(prev):
			# Acaba de entrar al fondo del patio: tiene que venir de la franja del portal (x < 24)
			# o de lo alto de un muro; desde fuera, a ras de suelo, sería haberlo atravesado
			var from_door := Boss.in_arena(prev.x, prev.z, 0.2)
			var from_above := prev.y >= WALL_TOP - Sim.STEP - EPS
			if not from_door and not from_above:
				_fail("semilla %d tick %d: atravesó un muro cerrado del patio: de %s a %s" % [seed_v, t, prev, s.pos])
				break
			_court_entries += 1
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


## Muros del patio (los que hunde el guardián al despertar).
func _court_walls() -> void:
	const STILL := {"mx": 0.0, "mz": 0.0, "j": 0, "f": "", "a": 0, "r": 0.0}
	# a) Cerrados, con el portal abierto: al patio sólo se entra por el portal. Nadie atraviesa un
	#    muro, ni empujando, ni esquivando, ni saltando, ni con empujones hacia dentro.
	var before := _checks
	var court := Vector2(Boss.HOME.x - 3.0, 0.0)
	for i in 180:
		# desde fuera, pegados a los muros norte, sur y fondo, empujando hacia el centro del patio
		var k := float(i % 60) / 59.0
		var from: Vector2 = [Vector2(lerpf(24.5, 33.5, k), -8.0 - float(i % 3)), Vector2(lerpf(24.5, 33.5, k), 8.0 + float(i % 3)),
			Vector2(36.0 + float(i % 3), lerpf(-5.0, 5.0, k))][i / 60]
		_run_walker(15000 + i, 600, from, court, GATE, true, true)
	var held := 0
	for i in 60:
		# desde dentro, empujando hacia fuera por los tres lados: tampoco se sale atravesándolos
		var a := float(i) / 60.0 * TAU
		var out := court + Vector2(cos(a) * 0.6 + 0.8, sin(a)).normalized() * 30.0
		var s := _run_walker(16000 + i, 240, court + Vector2(cos(a), sin(a)) * 2.0, out, GATE, true)
		var outside := s.pos.x > World.SANCTUARY.x - 5.0 and not Boss.in_arena(s.pos.x, s.pos.z, 0.2)
		if outside and s.pos.y < WALL_TOP - Sim.STEP:
			_fail("semilla %d: salió del patio a través de un muro cerrado, acabó en %s" % [16000 + i, s.pos])
		else:
			held += 1
	print("  muros del patio cerrados: %d comprobaciones; %d entradas al patio, todas por el portal o por encima; %d de 60 retenidos dentro" % [
		_checks - before, _court_entries, held])

	# b) En línea recta contra cada muro: cerrado lo para; abierto se pasa
	before = _checks
	var crossed := 0
	var starts := [Vector2(28.0, -10.0), Vector2(31.0, 10.0), Vector2(38.0, 2.0), Vector2(25.0, -9.0)]
	for i in starts.size():
		for open in [GATE, COURT]:
			var s := Sim.PlayerState.new()
			var from: Vector2 = starts[i]
			s.pos = Vector3(from.x, World.terrain_h(from.x, from.y), from.y)
			var dir := (court - from).normalized()
			for t in 120:
				var prev := s.pos
				Sim.step(s, {"mx": dir.x, "mz": dir.y, "j": 0, "f": "", "a": 0, "r": 0.0}, UNLOCKED, open)
				_check(s, prev, open, "muro %d abierto=%d tick %d" % [i, open, t], false)
				if _in_court(s.pos):
					break
			var inside := _in_court(s.pos)
			if open == COURT:
				crossed += 1 if inside else 0
				if not inside:
					_fail("con los muros abiertos no pudo entrar al patio desde %s: se quedó en %s" % [from, s.pos])
			elif inside:
				_fail("cruzó un muro cerrado desde %s hasta %s" % [from, s.pos])
	# c) Los muros se cierran con alguien justo en su línea (en el juego sólo se cierran con todo
	#    el grupo caído; aun así nadie puede quedarse dentro de la piedra): sale al lado más cercano
	var freed := 0
	for i in 45:
		var s := Sim.PlayerState.new()
		var j := float(i / 3)
		var off := (float(i % 5) - 2.0) * 0.2
		var at: Vector2 = [Vector2(24.0 + j * 0.6, -6.0 + off), Vector2(24.0 + j * 0.6, 6.0 + off), Vector2(34.0 + off, -4.5 + j * 0.6)][i % 3]
		s.pos = Vector3(at.x, 0.0, at.y)
		Sim.step(s, STILL, UNLOCKED, COURT)
		if (Vector2(s.pos.x, s.pos.z) - at).length() > 0.001:
			_fail("con los muros abiertos, estar en su línea no debería mover a nadie (%s → %s)" % [at, s.pos])
		var prev := s.pos
		Sim.step(s, STILL, UNLOCKED, GATE)
		_check(s, prev, GATE, "cierre con alguien en la línea %d" % i, true)
		if Sim.is_free(Vector2(s.pos.x, s.pos.z), s.pos.y, Sim.BODY_R, GATE) and Vector2(s.pos.x - at.x, s.pos.z - at.y).length() < 1.0:
			freed += 1
		else:
			_fail("al cerrarse el muro, quien estaba en %s quedó en %s (¿atrapado o lanzado lejos?)" % [at, s.pos])
	print("  muros del patio abiertos: %d comprobaciones; %d de %d cruces; %d de 45 apartados al cerrarse sin quedar dentro" % [
		_checks - before, crossed, starts.size(), freed])

	# d) Quién decide que están abiertos: el guardián del servidor. Cerrados mientras duerme,
	#    sólidos mientras se hunden, abiertos al terminar y cerrados otra vez cuando se duerme.
	var combat := Combat.new()
	var boss: RefCounted = combat.boss
	var seen := [boss.open_bits(), boss.snapshot()[24]]
	boss._awaken([])
	seen.append_array([boss.walls, boss.open_bits(), boss.snapshot()[25]])
	var opening_ticks := 0
	while boss.walls == Boss.WALLS_OPENING and opening_ticks < 1000:
		if boss.open_bits() != 0:
			_fail("los muros dejaron de ser sólidos antes de terminar de abrirse")
		boss.tick([])
		opening_ticks += 1
	seen.append_array([boss.walls, boss.open_bits(), boss.snapshot()[24]])
	boss._fail([])
	seen.append_array([boss.walls, boss.open_bits()])
	boss._awaken([])
	boss.skip_rise()   # como al terminar «El despertar»: sólo queda el último tramo
	var tail_ticks := 0
	while boss.walls == Boss.WALLS_OPENING and tail_ticks < 1000:
		boss.tick([])
		tail_ticks += 1
	boss._free()
	seen.append_array([boss.walls, boss.open_bits()])
	combat.restart([])
	seen.append_array([boss.walls, boss.open_bits()])
	var want := [0, Boss.WALLS_SHUT, Boss.WALLS_OPENING, 0, World.COURT_OPEN_TIME, Boss.WALLS_OPEN, World.OPEN_COURT, Boss.WALLS_OPEN,
		Boss.WALLS_SHUT, 0, Boss.WALLS_OPEN, World.OPEN_COURT, Boss.WALLS_SHUT, 0]
	if seen != want:
		_fail("muros del patio en el servidor: %s (se esperaba %s)" % [seen, want])
	var full := Sim.ticks(World.COURT_OPEN_TIME)
	var tail := Sim.ticks(World.COURT_OPEN_TAIL)
	if absi(opening_ticks - full) > 1 or absi(tail_ticks - tail) > 1:
		_fail("los muros tardaron %d ticks en abrirse y %d tras la escena (se esperaban %d y %d)" % [opening_ticks, tail_ticks, full, tail])
	boss.combat = null   # (se sueltan el uno al otro para que no queden objetos vivos al salir)
	combat.boss = null
	print("  muros en el servidor: se abren en %d ticks (%d tras «El despertar»), sólidos hasta el final, cerrados al dormirse y en ronda nueva" % [
		opening_ticks, tail_ticks])


func _init() -> void:
	var t0 := Time.get_ticks_msec()
	print("Simulación: prueba de invariantes")

	# 1) Paseantes aleatorios por todo el claro (con y sin puerta abierta, con empujones)
	for i in 240:
		_seed = 1000 + i
		var a := _rand() * TAU
		var r := _rand() * 40.0
		_run_walker(1000 + i, 900, Vector2(cos(a) * r, sin(a) * r), Vector2.INF, [GATE, SEALED, COURT][i % 3], i % 2 == 0)
	print("  paseantes aleatorios: %d comprobaciones" % _checks)

	# 2) Ataque dirigido al santuario con la puerta cerrada: desde todos los lados,
	#    esquivando, saltando y recibiendo empujones hacia dentro
	var before := _checks
	var san := World.SANCTUARY
	for i in 160:
		var a := float(i) / 160.0 * TAU
		var start := san + Vector2(cos(a), sin(a)) * (8.5 + float(i % 4))
		_run_walker(5000 + i, 700, start, san, SEALED, true)
	# ...y desde la ladera de detrás, que queda más alta que los muros
	for i in 120:
		var a := -0.9 + 1.8 * float(i) / 120.0
		_run_walker(7000 + i, 700, Vector2(cos(a), sin(a)) * (41.0 + float(i % 5)), san, SEALED, true)
	print("  asalto al santuario cerrado: %d comprobaciones" % (_checks - before))
	_court_walls()

	# 3) Contra cada árbol y columna, y contra el borde del claro
	before = _checks
	var n := 0
	for c in World.cylinders():
		n += 1
		if n % 3 != 0:
			continue
		_run_walker(9000 + n, 240, Vector2(c.x + 2.0, c.z + 1.0), Vector2(c.x, c.z), GATE, true)
	for i in 24:
		var a := float(i) / 24.0 * TAU
		_run_walker(12000 + i, 300, Vector2(cos(a), sin(a)) * 40.0, Vector2(cos(a), sin(a)) * 80.0, GATE, true)
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
			Sim.step(s, {"mx": 1.0, "mz": 0.0, "j": t % 2, "f": "", "a": (t % 2) * 7, "r": PI * 0.5}, UNLOCKED, GATE)
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
	var a1 := _run_walker(777, 1200, Vector2(3, 3), Vector2.INF, SEALED, true).to_array_exact()
	var a2 := _run_walker(777, 1200, Vector2(3, 3), Vector2.INF, SEALED, true).to_array_exact()
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
		Sim.step(server, inp, UNLOCKED, SEALED)
		Sim.step(client, inp, UNLOCKED, SEALED)
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
