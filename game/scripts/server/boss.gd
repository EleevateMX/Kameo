extends RefCounted
## Nojoch Tuunich en el servidor: fases, ataques con aviso, glifos y escombros.
## Sólo el servidor decide nada de esto; ningún mensaje del cliente lo toca. Diseño: docs/BOSS.md.
##
## Hecho: fase 1 (Olvido). Las fases 2 y 3 están definidas en el diseño y sin programar: al
## completar la fase 1 el guardián queda de rodillas.

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
var aim_yaw := 0.0              # dirección del barrido en curso
var rubble: Array = []          # escombros: [x, z, radio, segundos que quedan, segundos hasta el próximo daño]
var _summon_cd := 0.0
var _rearm := 0.0
var _swing := 0                 # alterna barrido y losa cuando tiene a alguien cerca
var _walked := 0.0
var _dmg_scale := 1.0


func _init(p_combat: RefCounted) -> void:
	combat = p_combat


## Vuelve a dormirse en su sitio. `full`: olvida también hasta dónde había llegado el grupo.
func reset(full: bool) -> void:
	phase = Boss.ASLEEP
	state = "sleep"
	t = 0.0
	x = Boss.HOME.x
	z = Boss.HOME.y
	yaw = Boss.HOME_YAW
	glyphs = 0
	target_slot = -1
	rubble.clear()
	_summon_cd = 0.0
	_swing = 0
	_clear_summoned()
	if full:
		checkpoint_phase = Boss.OLVIDO
		silence = Boss.SILENCE_MAX
		_rearm = 0.0


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


# ───────────────────────── Tick ─────────────────────────

func tick(players: Array) -> void:
	_rearm = maxf(0.0, _rearm - DT)
	if phase == Boss.ASLEEP:
		# Despierta cuando, con la emboscada superada, alguien entra al patio
		if combat.encounter == 2 and _rearm <= 0.0:
			for p in players:
				if combat._targetable(p) and Boss.in_arena(p.state.pos.x, p.state.pos.z):
					_awaken(players)
					break
		return
	if phase == Boss.FREED:
		return

	_tick_rubble(players)

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
	# Si el grupo se queda con menos gente, hacen falta menos glifos (nunca más de los previstos)
	if connected > 0:
		needed = mini(needed, Boss.glyphs_needed(connected))
		if phase == Boss.OLVIDO and glyphs >= needed and state != "rise":
			_complete_phase()
			return

	_summon_cd = maxf(0.0, _summon_cd - DT)
	t -= DT
	match state:
		"rise":
			if t <= 0.0:
				_idle(0.6)
		"idle":
			if t <= 0.0:
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
		_:
			pass   # kneel: fase 2 sin programar


func _awaken(players: Array) -> void:
	var n := maxi(1, _connected(players))
	phase = checkpoint_phase if checkpoint_phase == Boss.OLVIDO else Boss.OLVIDO
	needed = Boss.glyphs_needed(n)
	glyphs = 0
	silence = Boss.SILENCE_MAX
	_dmg_scale = Defs.dmg_scale(n)
	_summon_cd = 2.0
	state = "rise"
	t = Boss.RISE_TIME
	combat.events.append(["boss", "awake", phase, needed])


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


func _target(players: Array) -> Variant:
	var best: Variant = null
	var best_d := 1e9
	for p in players:
		if not combat._targetable(p):
			continue
		var d := Vector2(p.state.pos.x - x, p.state.pos.z - z).length()
		# quien está dentro del patio tiene prioridad sobre quien se asoma desde fuera
		if not Boss.in_arena(p.state.pos.x, p.state.pos.z, 0.6):
			d += 40.0
		if d < best_d:
			best_d = d
			best = p
	return best


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
	if d <= float(Boss.SWEEP.range) - 0.5 and _swing % 2 == 0:
		_swing += 1
		aim_yaw = yaw
		state = "sweep_w"
		t = Boss.SWEEP.windup
		combat.events.append(["boss", "tele", "sweep", snappedf(t, 0.01), snappedf(aim_yaw, 0.01)])
	elif d <= float(Boss.SLAM.reach):
		_swing += 1
		aim = Vector2(p.state.pos.x, p.state.pos.z)
		state = "slam_w"
		t = Boss.SLAM.windup
		combat.events.append(["boss", "tele", "slam", snappedf(t, 0.01), snappedf(aim.x, 0.01), snappedf(aim.y, 0.01)])
	else:
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
	var step := to / d * Boss.SPEED * DT
	var next := Sim.move_xz(Vector2(x, z), step, World.terrain_h(x, z), Boss.RADIUS, true)
	# En la fase 1 no sale del patio
	if Boss.in_arena(next.x, next.y, -Boss.RADIUS * 0.4):
		x = next.x
		z = next.y


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
	var scale := Defs.hp_scale(maxi(1, _connected(players)))
	for i in n:
		var spot: Vector2 = Boss.SUMMON_SPOTS[i % Boss.SUMMON_SPOTS.size()]
		var e: Variant = combat._spawn("corrupta", spot.x, spot.y, scale, false)
		e.summoned = true
		e.wake = float(Boss.SUMMON.wake) + 0.2 * float(i)
		e.dmg_scale = _dmg_scale
	_summon_cd = Boss.SUMMON.cd
	combat.events.append(["boss", "summon", n])
	state = "recover"
	t = Boss.SUMMON.recover


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


# ───────────────────────── Memoria ─────────────────────────

## Una criatura corrompida acaba de ser purificada: si fue cerca del guardián, enciende un glifo.
func on_purified(e: Variant, by: Variant) -> void:
	if phase != Boss.OLVIDO or state == "rise":
		return
	if Vector2(e.x - x, e.z - z).length() > Boss.GLYPH_RANGE:
		combat.events.append(["boss", "far", by.slot if by != null else -1])
		return
	glyphs = mini(Boss.GLYPHS, glyphs + 1)
	combat.events.append(["boss", "glyph", glyphs, needed, by.slot if by != null else -1])
	if glyphs >= needed:
		_complete_phase()


func _complete_phase() -> void:
	silence = maxf(0.0, silence - Boss.SILENCE_PER_PHASE)
	# Las criaturas que quedaban se deshacen: ya no hay Silencio que las sostenga en esta fase
	for e in combat.enemies:
		if e.summoned and e.state != "dead":
			combat._kill(e, null, true)
	rubble.clear()
	phase = Boss.FURIA
	checkpoint_phase = Boss.FURIA
	state = "kneel"
	t = 0.0
	target_slot = -1
	combat.events.append(["boss", "phase", phase, int(round(silence))])


## [fase, x, z, giro, estado, segundos del estado, silencio, glifos, glifosNecesarios, slotObjetivo,
##  puntoDelGolpeX, puntoDelGolpeZ, giroDelBarrido, escombros[[x, z, radio, segundos]]]
func snapshot() -> Array:
	var rub := []
	for r in rubble:
		rub.append([snappedf(r[0], 0.01), snappedf(r[1], 0.01), snappedf(r[2], 0.01), snappedf(r[3], 0.1)])
	return [phase, snappedf(x, 0.01), snappedf(z, 0.01), snappedf(yaw, 0.01), Boss.STATES.find(state), snappedf(maxf(t, 0.0), 0.01),
		int(round(silence)), glyphs, needed, target_slot, snappedf(aim.x, 0.01), snappedf(aim.y, 0.01), snappedf(aim_yaw, 0.01), rub]
