extends RefCounted
## Nojoch Tuunich en el servidor: fases, ataques con aviso, glifos, anclas, corazón y ritual.
## Sólo el servidor decide nada de esto; ningún mensaje del cliente lo toca. Diseño: docs/BOSS.md.
##
##   Fase 1 «Olvido»    en el patio: purificar criaturas junto a él enciende los glifos del pecho.
##   Fase 2 «Furia»     sale andando a la explanada. Un alux despierta columnas (F); si embiste
##                      contra una queda aturdido; con las anclas pisadas las cadenas lo sujetan y
##                      Balam golpea el corazón expuesto. Tres veces.
##   Fase 3 «Recuerdo»  de rodillas. Se encienden los glifos del suelo purificando criaturas y
##                      después todos los que siguen en pie lo tocan a la vez (alux, mantener F).
##
## Nadie se teletransporta al cambiar de fase: es el guardián quien camina. Si cae todo el grupo,
## se duerme y el combate se retoma desde la última fase alcanzada.

const Sim := preload("res://scripts/shared/sim.gd")
const World := preload("res://scripts/shared/world_def.gd")
const Defs := preload("res://scripts/shared/combat_def.gd")
const Boss := preload("res://scripts/shared/boss_def.gd")

const DT := Sim.DT

var combat: RefCounted          # server/combat.gd (enemigos, daño a jugadores, eventos)
var phase := Boss.ASLEEP
var checkpoint_phase := Boss.OLVIDO   # desde dónde se reintenta tras una derrota
var state := "sleep"
var t := 0.0                    # segundos que le quedan al estado en curso
var x := Boss.HOME.x
var z := Boss.HOME.y
var yaw := Boss.HOME_YAW
var silence := Boss.SILENCE_MAX
var glyphs := 0
var needed := 2
var target_slot := -1
var aim := Vector2.ZERO         # punto del golpe de losa en curso
var aim_yaw := 0.0              # dirección del barrido o de la embestida en curso
var rubble: Array = []          # escombros: [x, z, radio, segundos que quedan, segundos hasta el próximo daño]
# Fase 2
var pillars: Array = []         # columnas en pie: [índice de zócalo, segundos que le quedan]
var anchors := 0                # máscara de anclas activas
var anchors_need := 1
var heart := 0.0                # aguante que le queda al corazón en esta exposición
var heart_max := 1.0
var releases := 0               # veces que se ha liberado el corazón
# Fase 3
var lit := 0                    # glifos de memoria encendidos en el suelo
var lit_need := 1
var ritual := 0.0               # segundos de contacto acumulados
var ritual_need := 3.0
var channel := 0                # máscara de slots que lo están tocando
var touch_need := 1             # cuántos tienen que tocarlo a la vez
## Avisos para la sala (los recoge game_server): "awake" al despertar por primera vez, "freed".
var notices: Array = []
var awakenings := 0

var _summon_cd := 0.0
var _rearm := 0.0
var _swing := 0                 # alterna barrido y losa cuando tiene a alguien cerca
var _walked := 0.0
var _dmg_scale := 1.0
var _anchor_t: Array = [0.0, 0.0, 0.0, 0.0]
var _charge_cd := 0.0
var _rain_cd := 0.0
var _rain_next := 0.0
var _dir := Vector2.ZERO        # dirección fijada de la embestida
var _run_left := 0.0
var _struck := {}
var _path: Array = []           # puntos por los que camina al cambiar de sitio
var _leap_from := Vector2.ZERO  # de dónde despegó el salto a la explanada
var _leg_t := 0.0
var _wave_t := 0.0
var _pulse_t := 0.0
var _pulse_w := -1.0            # > 0 mientras avisa el pulso
var _clang_cd := 0.0
## Los jugadores de la sala tal y como los vio el último tick (para lo que nace de una acción de
## jugador, fuera del tick del jefe).
var _players: Array = []


func _init(p_combat: RefCounted) -> void:
	combat = p_combat


## Vuelve a dormirse. `full`: olvida también hasta dónde había llegado el grupo.
func reset(full: bool) -> void:
	if full:
		checkpoint_phase = Boss.OLVIDO
		_rearm = 0.0
		awakenings = 0
		notices.clear()
	phase = Boss.ASLEEP
	state = "sleep"
	t = 0.0
	# A partir de la fase 2 duerme donde se libra el combate: en la explanada
	var at: Vector2 = Boss.HOME if checkpoint_phase == Boss.OLVIDO else Boss.P2_HOME
	x = at.x
	z = at.y
	yaw = Boss.HOME_YAW
	silence = float(Boss.SILENCE_AT[checkpoint_phase])
	glyphs = 0 if checkpoint_phase == Boss.OLVIDO else needed
	target_slot = -1
	rubble.clear()
	pillars.clear()
	anchors = 0
	_anchor_t = [0.0, 0.0, 0.0, 0.0]
	heart = 0.0
	releases = 0
	lit = 0
	ritual = 0.0
	channel = 0
	_summon_cd = 0.0
	_swing = 0
	_path.clear()
	_pulse_w = -1.0
	_clear_summoned()


func active() -> bool:
	return phase != Boss.ASLEEP and phase != Boss.FREED


static func _connected(players: Array) -> int:
	var n := 0
	for p in players:
		if p.conn_id != 0:
			n += 1
	return n


func _summoned_alive() -> int:
	var n := 0
	for e in combat.enemies:
		if e.summoned and e.state != "dead":
			n += 1
	return n


func _clear_summoned() -> void:
	combat.enemies = combat.enemies.filter(func(e: Variant) -> bool: return not e.summoned)


## El Silencio suelta a sus criaturas: las que llamó el guardián y cualquier otra corrompida que
## ronde a menos de `radius` metros de él (las del claro reaparecen en su sitio más tarde).
func _purify_summoned(radius := 0.0) -> void:
	for e in combat.enemies:
		if e.state == "dead":
			continue
		var near: bool = radius > 0.0 and float(Defs.ENEMIES[e.kind].purify_at) > 0.0 and Vector2(e.x - x, e.z - z).length() < radius
		if e.summoned or near:
			combat._kill(e, null, true)


func _dist(p: Variant) -> float:
	return Vector2(p.state.pos.x - x, p.state.pos.z - z).length()


# ───────────────────────── Tick ─────────────────────────

func tick(players: Array) -> void:
	_players = players
	_rearm = maxf(0.0, _rearm - DT)
	if phase == Boss.ASLEEP:
		# Despierta cuando, con la emboscada superada, alguien se le acerca
		if combat.encounter == 2 and _rearm <= 0.0:
			for p in players:
				if combat._targetable(p) and _wakes(p):
					_awaken(players)
					break
		return
	if phase == Boss.FREED:
		return

	_tick_rubble(players)
	_tick_pillars()

	# Derrota: no queda en pie ningún conectado. El guardián vuelve a dormirse y se reintenta
	# desde la fase alcanzada.
	var connected := 0
	var standing := 0
	for p in players:
		if p.conn_id != 0:
			connected += 1
			if not p.state.dead:
				standing += 1
	if connected > 0 and standing == 0:
		_fail(players)
		return
	# Si el grupo se queda con menos gente, hace falta menos (nunca más de lo previsto al empezar)
	if connected > 0:
		match phase:
			Boss.OLVIDO:
				needed = mini(needed, Boss.glyphs_needed(connected))
				if glyphs >= needed and state != "rise":
					_begin_furia(players)
					return
			Boss.FURIA:
				anchors_need = Boss.anchors_needed(connected)
				_tick_anchors(players, connected)
			Boss.RECUERDO:
				lit_need = mini(lit_need, Boss.ritual_glyphs(connected))

	_summon_cd = maxf(0.0, _summon_cd - DT)
	_charge_cd = maxf(0.0, _charge_cd - DT)
	_rain_cd = maxf(0.0, _rain_cd - DT)
	_clang_cd = maxf(0.0, _clang_cd - DT)
	t -= DT
	match state:
		"rise":
			if t <= 0.0:
				_after_rise(players)
		"idle":
			if t <= 0.0:
				if phase == Boss.FURIA:
					_decide_furia(players)
				else:
					_decide(players)
		"walk":
			_walk(players)
		"slam_w":
			if t <= 0.0:
				_strike_slam(players)
		"sweep_w":
			if t <= 0.0:
				_strike_sweep(players)
		"summon_w":
			if t <= 0.0:
				_strike_summon(players)
		"recover":
			if t <= 0.0:
				_idle(0.5)
		"kneel":
			# Un instante de memoria al cambiar de fase; después camina a donde sigue el combate
			if t <= 0.0:
				_begin_transit()
		"transit":
			_tick_transit(players)
		"leap_w":
			if t <= 0.0:
				state = "leap"
				t = float(Boss.LEAP.time)
				combat.events.append(["boss", "leap", snappedf(aim.x, 0.01), snappedf(aim.y, 0.01)])
		"leap":
			_tick_leap(players)
		"rain_w":
			if t <= 0.0:
				state = "rain"
				t = Boss.RAIN.dur
				_rain_next = 0.0
				combat.events.append(["boss", "rain", snappedf(t, 0.01)])
		"rain":
			_tick_rain(players)
		"charge_w":
			_tick_charge_windup(players)
		"charge":
			_tick_charge(players)
		"stunned":
			if anchors_count() >= anchors_need:
				_bind()
			elif t <= 0.0:
				combat.events.append(["boss", "shake", 0])
				state = "recover"
				t = Boss.CHARGE.recover
		"bound":
			if anchors_count() < anchors_need or t <= 0.0:
				_unbind(players, false)
		"ritual":
			_tick_ritual(players, connected)
		_:
			pass


func _wakes(p: Variant) -> bool:
	if checkpoint_phase == Boss.OLVIDO:
		return Boss.in_arena(p.state.pos.x, p.state.pos.z)
	return _dist(p) < 9.0


func _awaken(players: Array) -> void:
	var n := maxi(1, _connected(players))
	awakenings += 1
	phase = checkpoint_phase
	_dmg_scale = Defs.dmg_scale(n)
	silence = float(Boss.SILENCE_AT[phase])
	match phase:
		Boss.OLVIDO:
			needed = Boss.glyphs_needed(n)
			glyphs = 0
			_summon_cd = 2.0
		Boss.FURIA:
			_setup_furia(n)
		Boss.RECUERDO:
			_setup_recuerdo(n)
	state = "rise"
	t = Boss.RISE_TIME
	combat.events.append(["boss", "awake", phase, needed])
	if awakenings == 1:
		notices.append("awake")


## La cinemática del despertar ya lo mostró poniéndose en pie: el combate empieza donde ella acaba.
func skip_rise() -> void:
	if state == "rise":
		t = minf(t, 0.4)


func _after_rise(players: Array) -> void:
	match phase:
		Boss.RECUERDO:
			_begin_ritual(players)
		_:
			_idle(0.6)


func _fail(players: Array) -> void:
	combat.events.append(["boss", "fail", phase])
	reset(false)
	_rearm = Boss.REARM_TIME
	for p in players:
		if p.conn_id == 0:
			combat._respawn(p, false)
		elif p.state.dead:
			p.respawn_t = minf(p.respawn_t, Defs.RESPAWN_TIME_DEFEAT)


func _idle(wait: float) -> void:
	state = "idle"
	t = wait


func _in_zone(px: float, pz: float, margin: float) -> bool:
	if phase == Boss.OLVIDO:
		return Boss.in_arena(px, pz, margin)
	return Boss.in_esplanade(px, pz, margin + 2.0)


func _target(players: Array) -> Variant:
	var best: Variant = null
	var best_d := 1e9
	for p in players:
		if not combat._targetable(p):
			continue
		var d := _dist(p)
		# quien está en la zona del combate tiene prioridad sobre quien se asoma desde fuera
		if not _in_zone(p.state.pos.x, p.state.pos.z, 0.6):
			d += 40.0
		if d < best_d:
			best_d = d
			best = p
	return best


func _melee_choice(p: Variant, d: float) -> bool:
	if d <= float(Boss.SWEEP.range) - 0.5 and _swing % 2 == 0:
		_swing += 1
		aim_yaw = yaw
		state = "sweep_w"
		t = Boss.SWEEP.windup
		combat.events.append(["boss", "tele", "sweep", snappedf(t, 0.01), snappedf(aim_yaw, 0.01)])
		return true
	if d <= float(Boss.SLAM.reach):
		_swing += 1
		aim = Vector2(p.state.pos.x, p.state.pos.z)
		state = "slam_w"
		t = Boss.SLAM.windup
		combat.events.append(["boss", "tele", "slam", snappedf(t, 0.01), snappedf(aim.x, 0.01), snappedf(aim.y, 0.01)])
		return true
	return false


func _decide(players: Array) -> void:
	var p: Variant = _target(players)
	if p == null:
		target_slot = -1
		_idle(0.5)
		return
	target_slot = p.slot
	var to := Vector2(p.state.pos.x - x, p.state.pos.z - z)
	var d := to.length()
	# Sin criaturas no hay forma de encender glifos: las llama en cuanto puede
	if _summon_cd <= 0.0 and _summoned_alive() == 0:
		state = "summon_w"
		t = Boss.SUMMON.windup
		combat.events.append(["boss", "tele", "summon", snappedf(t, 0.01)])
		return
	if d > 0.05:
		yaw = atan2(to.x, to.y)
	if not _melee_choice(p, d):
		state = "walk"
		_walked = 0.0


func _walk(players: Array) -> void:
	var p: Variant = _target(players)
	_walked += DT
	if p == null or _walked > 2.6:
		_idle(0.2)
		return
	target_slot = p.slot
	var to := Vector2(p.state.pos.x - x, p.state.pos.z - z)
	var d := to.length()
	if d <= float(Boss.SLAM.reach) - 1.5:
		_idle(0.15)
		return
	yaw = atan2(to.x, to.y)
	var speed := Boss.SPEED * (1.35 if phase == Boss.FURIA else 1.0)
	var next := Sim.move_xz(Vector2(x, z), to / d * speed * DT, World.terrain_h(x, z), Boss.RADIUS, true)
	# No sale de la zona donde se libra la fase
	var ok := Boss.in_arena(next.x, next.y, -Boss.RADIUS * 0.4) if phase == Boss.OLVIDO else Boss.in_esplanade(next.x, next.y)
	if ok:
		x = next.x
		z = next.y
	elif phase == Boss.FURIA:
		_idle(0.3)


func _strike_slam(players: Array) -> void:
	var def: Dictionary = Boss.SLAM
	for p in players:
		if combat._targetable(p) and Vector2(p.state.pos.x - aim.x, p.state.pos.z - aim.y).length() <= float(def.radius):
			combat.damage_player(p, float(def.dmg) * _dmg_scale, aim, float(def.knock))
	rubble.append([aim.x, aim.y, float(def.rubble_r), float(def.rubble_t), float(def.rubble_every)])
	combat.events.append(["boss", "slam", snappedf(aim.x, 0.01), snappedf(aim.y, 0.01), float(def.radius)])
	state = "recover"
	t = def.recover


func _strike_sweep(players: Array) -> void:
	var def: Dictionary = Boss.SWEEP
	var here := Vector2(x, z)
	for p in players:
		if not combat._targetable(p):
			continue
		var to := Vector2(p.state.pos.x - x, p.state.pos.z - z)
		if to.length() > float(def.range):
			continue
		if absf(angle_difference(aim_yaw, atan2(to.x, to.y))) <= float(def.arc) * 0.5:
			combat.damage_player(p, float(def.dmg) * _dmg_scale, here, float(def.knock))
	combat.events.append(["boss", "sweep", snappedf(aim_yaw, 0.01)])
	state = "recover"
	t = def.recover


func _strike_summon(players: Array) -> void:
	var n := Boss.summon_count(maxi(1, _connected(players)))
	_spawn_summoned(n, Boss.SUMMON_SPOTS, players)
	_summon_cd = Boss.SUMMON.cd
	state = "recover"
	t = Boss.SUMMON.recover


func _spawn_summoned(n: int, spots: Array, players: Array) -> void:
	var scale := Defs.hp_scale(maxi(1, _connected(players)))
	var first: int = int(combat._rng.randi() % spots.size()) if phase == Boss.RECUERDO else 0
	for i in n:
		var spot: Vector2 = spots[(first + i) % spots.size()]
		var e: Variant = combat._spawn("corrupta", spot.x, spot.y, scale, false)
		e.summoned = true
		e.wake = float(Boss.SUMMON.wake) + 0.2 * float(i)
		e.dmg_scale = _dmg_scale
		if phase == Boss.RECUERDO:
			e.home = Vector2(x, z)   # vienen a por quienes rodean al guardián
	combat.events.append(["boss", "summon", n])


func _tick_rubble(players: Array) -> void:
	for r in rubble:
		r[3] = float(r[3]) - DT
		r[4] = float(r[4]) - DT
		if float(r[4]) <= 0.0:
			r[4] = float(Boss.SLAM.rubble_every)
			var c := Vector2(r[0], r[1])
			for p in players:
				if combat._targetable(p) and p.state.grounded and Vector2(p.state.pos.x - c.x, p.state.pos.z - c.y).length() <= float(r[2]):
					combat.damage_player(p, float(Boss.SLAM.rubble_dmg) * _dmg_scale, c, 0.0)
	rubble = rubble.filter(func(r: Array) -> bool: return float(r[3]) > 0.0)


# ───────────────────────── Fase 1: memoria ─────────────────────────

## Una criatura corrompida acaba de ser purificada: si fue cerca del guardián, enciende un glifo
## (los del pecho en la fase 1, los del suelo en la fase 3).
func on_purified(e: Variant, by: Variant) -> void:
	var slot: int = by.slot if by != null else -1
	if phase == Boss.OLVIDO and state != "rise":
		if Vector2(e.x - x, e.z - z).length() > Boss.GLYPH_RANGE:
			combat.events.append(["boss", "far", slot])
			return
		glyphs = mini(Boss.GLYPHS, glyphs + 1)
		combat.events.append(["boss", "glyph", glyphs, needed, slot])
	elif phase == Boss.RECUERDO and state == "ritual" and lit < lit_need:
		if Vector2(e.x - x, e.z - z).length() > Boss.GLYPH_RANGE + 1.5:
			combat.events.append(["boss", "far", slot])
			return
		lit += 1
		combat.events.append(["boss", "lit", lit, lit_need, slot])
		if lit >= lit_need:
			_pulse_t = float(Boss.PULSE.every) * 0.6
			combat.events.append(["boss", "contact", touch_need])


# ───────────────────────── Fase 2: el corazón de piedra ─────────────────────────

func _setup_furia(n: int) -> void:
	anchors_need = Boss.anchors_needed(n)
	anchors = 0
	_anchor_t = [0.0, 0.0, 0.0, 0.0]
	releases = 0
	heart_max = Boss.heart_pool(n)
	heart = heart_max
	pillars.clear()
	_charge_cd = 5.0
	_rain_cd = 14.0
	_swing = 0
	glyphs = needed


func _begin_furia(players: Array) -> void:
	var n := maxi(1, _connected(players))
	silence = float(Boss.SILENCE_AT[Boss.FURIA])
	# Las criaturas que quedaban se deshacen: ya no hay Silencio que las sostenga en esta fase
	_purify_summoned(16.0)
	rubble.clear()
	phase = Boss.FURIA
	checkpoint_phase = Boss.FURIA
	combat.checkpoint = 2
	_dmg_scale = Defs.dmg_scale(n)
	_setup_furia(n)
	state = "kneel"
	t = 2.4
	target_slot = -1
	combat.events.append(["boss", "phase", phase, int(round(silence))])


## Cambio de sitio al cambiar de fase. Si está dentro del santuario (o en su portal) sale de un
## salto: no depende de rodear el pedestal ni de caber por el portal. Ya en la explanada, camina.
func _begin_transit() -> void:
	_path.clear()
	if x > 20.6:
		_begin_leap()
		return
	_path.append(Boss.P2_HOME)
	_leg_t = 0.0
	state = "transit"
	t = 0.0
	target_slot = -1
	combat.events.append(["boss", "transit", phase])


func _tick_transit(players: Array) -> void:
	if _path.is_empty():
		_arrive(players)
		return
	var goal: Vector2 = _path[0]
	var to := goal - Vector2(x, z)
	var d := to.length()
	var step := Boss.TRANSIT_SPEED * DT
	if d <= step:
		x = goal.x
		z = goal.y
		_path.pop_front()
		_leg_t = 0.0
		return
	yaw = atan2(to.x, to.y)
	_leg_t += DT
	var next := Vector2(x, z) + to / d * step
	# Si algo le estorba más de la cuenta, pasa igualmente: no puede quedarse atascado a mitad
	if _leg_t < 1.5:
		next = Sim.move_xz(Vector2(x, z), to / d * step, World.terrain_h(x, z), Boss.RADIUS, true)
	x = next.x
	z = next.y


func _begin_leap() -> void:
	_leap_from = Vector2(x, z)
	aim = Boss.P2_HOME
	var to := aim - _leap_from
	yaw = atan2(to.x, to.y)
	aim_yaw = yaw
	state = "leap_w"
	t = float(Boss.LEAP.windup)
	target_slot = -1
	combat.events.append(["boss", "leap_w", snappedf(aim.x, 0.01), snappedf(aim.y, 0.01), snappedf(t, 0.01)])


## En el aire va en línea recta de donde despegó a donde cae; la altura la pone el cliente con
## Boss.leap_height (sólo es dibujo: en el aire no golpea ni se le puede tocar).
func _tick_leap(players: Array) -> void:
	var p := clampf(1.0 - t / float(Boss.LEAP.time), 0.0, 1.0)
	var at := _leap_from.lerp(aim, p)
	x = at.x
	z = at.y
	if t > 0.0:
		return
	x = aim.x
	z = aim.y
	# Al caer empuja a quien esté debajo o pegado (sin daño)
	var pushed := 0
	for pl in players:
		if pl.conn_id == 0 or pl.state.dead:
			continue
		var d := Vector2(pl.state.pos.x - x, pl.state.pos.z - z)
		if d.length() < float(Boss.LEAP.radius):
			var away := d.normalized() if d.length() > 0.05 else Vector2(-1.0, 0.0)
			pl.state.kx = away.x * float(Boss.LEAP.knock)
			pl.state.kz = away.y * float(Boss.LEAP.knock)
			pushed |= 1 << int(pl.slot)
	combat.events.append(["boss", "land", snappedf(x, 0.01), snappedf(z, 0.01), pushed])
	_arrive(players)


func _arrive(players: Array) -> void:
	combat.events.append(["boss", "arena", phase])
	if phase == Boss.RECUERDO:
		_begin_ritual(players)
	else:
		_idle(0.9)


func anchors_count() -> int:
	var n := 0
	for i in Boss.ANCHORS.size():
		if (anchors & (1 << i)) != 0:
			n += 1
	return n


func _tick_anchors(players: Array, connected: int) -> void:
	var latch := Boss.ANCHOR_LATCH_SOLO if connected <= 1 else Boss.ANCHOR_LATCH
	var mask := 0
	for i in Boss.ANCHORS.size():
		var a: Vector2 = Boss.ANCHORS[i]
		var on := false
		for p in players:
			if combat._targetable(p) and Vector2(p.state.pos.x - a.x, p.state.pos.z - a.y).length() < Boss.ANCHOR_R \
					and absf(p.state.pos.y - World.terrain_h(a.x, a.y)) < 0.8:
				on = true
				break
		# Sólo responden con el guardián aturdido o ya sujeto: antes no hay nada que amarrar
		if on and (state == "stunned" or state == "bound"):
			_anchor_t[i] = latch
		else:
			_anchor_t[i] = maxf(0.0, float(_anchor_t[i]) - DT)
		if float(_anchor_t[i]) > 0.0:
			mask |= 1 << i
	if mask != anchors:
		for i in Boss.ANCHORS.size():
			if (mask & (1 << i)) != 0 and (anchors & (1 << i)) == 0:
				combat.events.append(["boss", "anchor", i, 1])
			elif (mask & (1 << i)) == 0 and (anchors & (1 << i)) != 0:
				combat.events.append(["boss", "anchor", i, 0])
		anchors = mask


func _tick_pillars() -> void:
	for pl in pillars:
		pl[1] = float(pl[1]) - DT
		if float(pl[1]) <= 0.0:
			combat.events.append(["boss", "pillar_down", int(pl[0]), 0])
	pillars = pillars.filter(func(pl: Array) -> bool: return float(pl[1]) > 0.0)


## Un alux toca (F) el glifo de una columna dormida. Devuelve true si el toque era para eso.
func raise_pillar(p: Variant) -> bool:
	if phase != Boss.FURIA or state == "kneel" or state == "transit" or state == "rise" or state == "leap_w" or state == "leap":
		return false
	var here := Vector2(p.state.pos.x, p.state.pos.z)
	var best := -1
	var best_d := float(Boss.PILLARS.touch)
	for i in Boss.PILLAR_SPOTS.size():
		var up := false
		for pl in pillars:
			if int(pl[0]) == i:
				up = true
		if up:
			continue
		var d := (here - Boss.PILLAR_SPOTS[i]).length()
		if d < best_d:
			best_d = d
			best = i
	if best < 0:
		return false
	if pillars.size() >= int(Boss.PILLARS.count):
		combat.events.append(["boss", "pillar_max", p.slot])
		return true
	# No sube debajo del guardián
	if (Vector2(x, z) - Boss.PILLAR_SPOTS[best]).length() < Boss.RADIUS + float(Boss.PILLARS.radius) + 0.4:
		return true
	pillars.append([best, float(Boss.PILLARS.life)])
	combat.events.append(["boss", "pillar", best, p.slot])
	return true


func _sheltered(p: Variant) -> bool:
	for pl in pillars:
		var s: Vector2 = Boss.PILLAR_SPOTS[int(pl[0])]
		if Vector2(p.state.pos.x - s.x, p.state.pos.z - s.y).length() <= float(Boss.PILLARS.shelter):
			return true
	return false


func _decide_furia(players: Array) -> void:
	var p: Variant = _target(players)
	if p == null:
		target_slot = -1
		_idle(0.5)
		return
	target_slot = p.slot
	var to := Vector2(p.state.pos.x - x, p.state.pos.z - z)
	var d := to.length()
	if d > 0.05:
		yaw = atan2(to.x, to.y)
	if _rain_cd <= 0.0:
		_rain_cd = Boss.RAIN.cd
		state = "rain_w"
		t = Boss.RAIN.windup
		combat.events.append(["boss", "tele", "rain", snappedf(t, 0.01)])
		return
	if _charge_cd <= 0.0 and d > 2.6:
		_charge_cd = Boss.CHARGE.cd
		aim_yaw = yaw
		state = "charge_w"
		t = Boss.CHARGE.windup
		combat.events.append(["boss", "tele", "charge", snappedf(t, 0.01)])
		return
	if not _melee_choice(p, d):
		state = "walk"
		_walked = 0.0


func _tick_rain(players: Array) -> void:
	_rain_next -= DT
	if _rain_next <= 0.0:
		_rain_next = Boss.RAIN.every
		for p in players:
			if combat._targetable(p) and Boss.in_esplanade(p.state.pos.x, p.state.pos.z, 4.0) and not _sheltered(p):
				combat.damage_player(p, float(Boss.RAIN.dmg) * _dmg_scale, Vector2(p.state.pos.x, p.state.pos.z), 0.0)
	if t <= 0.0:
		state = "recover"
		t = Boss.RAIN.recover


func _tick_charge_windup(players: Array) -> void:
	# Sigue a su objetivo hasta el último momento: ahí fija la dirección y ya no la cambia
	if t > float(Boss.CHARGE.lock):
		var p: Variant = _target(players)
		if p != null:
			target_slot = p.slot
			var to := Vector2(p.state.pos.x - x, p.state.pos.z - z)
			if to.length() > 0.05:
				aim_yaw = atan2(to.x, to.y)
				yaw = aim_yaw
	if t <= 0.0:
		_dir = Vector2(sin(aim_yaw), cos(aim_yaw))
		_run_left = Boss.CHARGE.dist
		_struck = {}
		state = "charge"
		t = 0.0
		combat.events.append(["boss", "charge", snappedf(aim_yaw, 0.01)])


func _tick_charge(players: Array) -> void:
	var step := float(Boss.CHARGE.speed) * DT
	var from := Vector2(x, z)
	var next := Sim.move_xz(from, _dir * step, World.terrain_h(x, z), Boss.RADIUS, true)
	var moved := (next - from).length()
	var inside := Boss.in_esplanade(next.x, next.y)
	if inside:
		x = next.x
		z = next.y
	_run_left -= step
	var here := Vector2(x, z)
	for p in players:
		if combat._targetable(p) and not _struck.has(p.id) and _dist(p) <= float(Boss.CHARGE.hit_r) \
				and absf(p.state.pos.y - World.terrain_h(x, z)) < 2.5:
			_struck[p.id] = true
			combat.damage_player(p, float(Boss.CHARGE.dmg) * _dmg_scale, here - _dir * 1.5, float(Boss.CHARGE.knock))
	# Contra una columna: la rompe y queda aturdido
	for pl in pillars:
		var s: Vector2 = Boss.PILLAR_SPOTS[int(pl[0])]
		if (here - s).length() <= float(Boss.PILLARS.crash):
			pillars.erase(pl)
			combat.events.append(["boss", "crash", int(pl[0]), snappedf(float(Boss.CHARGE.stun), 0.01)])
			state = "stunned"
			t = Boss.CHARGE.stun
			target_slot = -1
			return
	if not inside or moved < step * 0.4 or _run_left <= 0.0:
		combat.events.append(["boss", "charge_end", 0])
		state = "recover"
		t = Boss.CHARGE.recover


func _bind() -> void:
	state = "bound"
	t = Boss.BOUND.window
	combat.events.append(["boss", "bound", snappedf(t, 0.01), int(round(heart / heart_max * 100.0))])


func _unbind(players: Array, released: bool) -> void:
	anchors = 0
	_anchor_t = [0.0, 0.0, 0.0, 0.0]
	# Se suelta de un tirón: aparta a quien tenga encima, sin daño
	for p in players:
		if combat._targetable(p) and _dist(p) <= float(Boss.BOUND.shove_r):
			var d := Vector2(p.state.pos.x - x, p.state.pos.z - z)
			d = d.normalized() if d.length() > 0.05 else Vector2(sin(yaw), cos(yaw))
			p.state.kx = d.x * float(Boss.BOUND.shove)
			p.state.kz = d.y * float(Boss.BOUND.shove)
	combat.events.append(["boss", "unbound", 1 if released else 0])
	state = "recover"
	t = Boss.BOUND.recover
	_charge_cd = maxf(_charge_cd, 4.0)


## Un golpe cuerpo a cuerpo de un jugador (lo llama el combate). A Nojoch no se le hace daño:
## sólo cuenta contra el corazón, sólo con las cadenas puestas y sólo si quien golpea es Balam.
func on_melee(p: Variant, dmg: float, reach: float) -> void:
	if not active() or _dist(p) > reach + Boss.RADIUS or absf(p.state.pos.y - World.terrain_h(x, z)) > 3.0:
		return
	if phase != Boss.FURIA or state != "bound":
		if _clang_cd <= 0.0:
			_clang_cd = 0.8
			combat.events.append(["boss", "clang", p.slot])
		return
	heart = maxf(0.0, heart - dmg)
	combat.events.append(["boss", "heart_hit", p.slot, int(round(dmg)), int(round(heart / heart_max * 100.0))])
	if heart <= 0.0:
		_release(p)


func _release(by: Variant) -> void:
	releases += 1
	silence = maxf(0.0, silence - Boss.SILENCE_PER_EXPOSURE)
	combat.events.append(["boss", "heart", releases, Boss.EXPOSURES, int(round(silence)), by.slot])
	if releases >= Boss.EXPOSURES:
		_begin_recuerdo()
		return
	heart = heart_max
	_unbind(_players, true)


# ───────────────────────── Fase 3: la memoria restaurada ─────────────────────────

func _setup_recuerdo(n: int) -> void:
	lit = 0
	lit_need = Boss.ritual_glyphs(n)
	ritual = 0.0
	ritual_need = float(Boss.RITUAL.time_solo) if n <= 1 else float(Boss.RITUAL.time)
	channel = 0
	touch_need = 1
	pillars.clear()
	anchors = 0
	_anchor_t = [0.0, 0.0, 0.0, 0.0]
	glyphs = needed
	_pulse_w = -1.0


func _begin_recuerdo() -> void:
	var n := maxi(1, _connected(_players))
	for pl in pillars:
		combat.events.append(["boss", "pillar_down", int(pl[0]), 0])
	rubble.clear()
	phase = Boss.RECUERDO
	checkpoint_phase = Boss.RECUERDO
	silence = float(Boss.SILENCE_AT[Boss.RECUERDO])
	_setup_recuerdo(n)
	state = "kneel"
	t = 2.0
	target_slot = -1
	combat.events.append(["boss", "phase", phase, int(round(silence))])


func _begin_ritual(_players_now: Array) -> void:
	state = "ritual"
	t = 0.0
	yaw = Boss.HOME_YAW
	_wave_t = Boss.RITUAL.first_wave
	_pulse_t = Boss.PULSE.every
	_pulse_w = -1.0
	combat.events.append(["boss", "ritual", lit_need])


func _tick_ritual(players: Array, connected: int) -> void:
	var n := maxi(1, connected)
	# La última resistencia del Silencio: criaturas que llegan de los bordes de la explanada
	_wave_t -= DT
	if _wave_t <= 0.0:
		var room_left := Boss.ritual_max(n) - _summoned_alive()
		var k := mini(Boss.ritual_wave(n), room_left)
		if k > 0:
			_spawn_summoned(k, Boss.RITUAL_GATES, players)
		# con los glifos ya encendidos vienen más despacio: lo que toca es el contacto
		_wave_t = float(Boss.RITUAL.wave_every) * (1.6 if lit >= lit_need else 1.0)

	var open := lit >= lit_need
	# …y, abierto el contacto, pulsos que apartan a quien esté pegado a él
	if open:
		if _pulse_w > 0.0:
			_pulse_w -= DT
			if _pulse_w <= 0.0:
				_pulse_w = -1.0
				var here := Vector2(x, z)
				for p in players:
					if combat._targetable(p) and _dist(p) <= float(Boss.PULSE.radius):
						combat.damage_player(p, float(Boss.PULSE.dmg) * _dmg_scale, here, float(Boss.PULSE.knock))
				combat.events.append(["boss", "pulse", float(Boss.PULSE.radius)])
		else:
			_pulse_t -= DT
			if _pulse_t <= 0.0:
				_pulse_t = Boss.PULSE.every
				_pulse_w = Boss.PULSE.windup
				combat.events.append(["boss", "tele", "pulse", snappedf(_pulse_w, 0.01), float(Boss.PULSE.radius)])

	# Contacto: todos los conectados que sigan en pie (y no se hayan ido lejos), a la vez
	var standing := 0
	var touching := 0
	var mask := 0
	for p in players:
		if not combat._targetable(p) or _dist(p) > float(Boss.RITUAL.far):
			continue
		standing += 1
		if open and p.state.form == "alux" and p.hold_special and _dist(p) <= float(Boss.RITUAL.range) \
				and combat._time - p.hurt_at > float(Boss.RITUAL.block):
			touching += 1
			mask |= 1 << p.slot
	touch_need = maxi(1, standing)
	ritual_need = float(Boss.RITUAL.time_solo) if n <= 1 else float(Boss.RITUAL.time)
	if mask != channel:
		channel = mask
	if open and standing > 0 and touching >= touch_need:
		ritual += DT
		if ritual >= ritual_need:
			_free()
	else:
		ritual = maxf(0.0, ritual - float(Boss.RITUAL.decay) * DT)


func _free() -> void:
	phase = Boss.FREED
	state = "freed"
	t = 0.0
	silence = 0.0
	channel = 0
	ritual = ritual_need
	target_slot = -1
	rubble.clear()
	_pulse_w = -1.0
	# El Silencio se retira: las criaturas corrompidas que rondaban cerca también recuerdan
	_purify_summoned(24.0)
	combat.events.append(["boss", "freed", 0])
	notices.append("freed")


## [fase, x, z, giro, estado, segundos del estado, silencio, glifos, glifosNecesarios, slotObjetivo,
##  puntoDelGolpeX, puntoDelGolpeZ, giroDelBarridoOEmbestida, escombros[[x, z, radio, segundos]],
##  anclasActivas(máscara), anclasNecesarias, columnas[[zócalo, segundos]], corazón(0–100), corazonesLiberados,
##  glifosDelSuelo, glifosDelSueloNecesarios, contacto(0–100), quiénesLoTocan(máscara), cuántosDebenTocarlo]
func snapshot() -> Array:
	var rub := []
	for r in rubble:
		rub.append([snappedf(r[0], 0.01), snappedf(r[1], 0.01), snappedf(r[2], 0.01), snappedf(r[3], 0.1)])
	var pil := []
	for pl in pillars:
		pil.append([int(pl[0]), snappedf(pl[1], 0.1)])
	return [phase, snappedf(x, 0.01), snappedf(z, 0.01), snappedf(yaw, 0.01), Boss.STATES.find(state), snappedf(maxf(t, 0.0), 0.01),
		int(round(silence)), glyphs, needed, target_slot, snappedf(aim.x, 0.01), snappedf(aim.y, 0.01), snappedf(aim_yaw, 0.01), rub,
		anchors, anchors_need, pil, int(round(heart / maxf(heart_max, 1.0) * 100.0)), releases,
		lit, lit_need, int(round(clampf(ritual / maxf(ritual_need, 0.1), 0.0, 1.0) * 100.0)), channel, touch_need]
