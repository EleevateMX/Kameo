extends RefCounted
## Combate de una sala. Sólo existe en el servidor: aquí se decide a quién
## alcanza cada golpe, la vida de jugadores y enemigos, la IA y el encuentro.
## Los clientes reciben el resultado en forma de estados y eventos.

const Sim := preload("res://scripts/shared/sim.gd")
const World := preload("res://scripts/shared/world_def.gd")
const Defs := preload("res://scripts/shared/combat_def.gd")
const BossAI := preload("res://scripts/server/boss.gd")

const DT := Sim.DT


class Enemy:
	var id := 0
	var kind := ""
	var x := 0.0
	var y := 0.0
	var z := 0.0
	var yaw := 0.0
	var hp := 1.0
	var max_hp := 1.0
	var state := "idle"
	var t := 0.0                 # temporizador del estado actual
	var home := Vector2.ZERO
	var wave := false            # pertenece a la emboscada
	var target := ""             # id del jugador objetivo
	var target_slot := -1
	var threat := {}             # id de jugador -> amenaza acumulada
	var wp := Vector2.ZERO       # punto de patrulla
	var dir := Vector2.ZERO      # dirección de la embestida
	var struck := {}             # jugadores ya golpeados en esta embestida
	var stuck_t := 0.0
	var side := 0.0
	var side_t := 0.0
	var wake := 0.0              # segundos que le quedan "despertando" (no persigue ni ataca)
	var dmg_scale := 1.0         # los de la emboscada pegan menos a grupos pequeños
	var summoned := false        # la llamó el guardián: no reaparece sola y cuenta para sus glifos


var enemies: Array = []
var bolts: Array = []
var events: Array = []
var encounter := 0               # 0 pendiente · 1 en curso · 2 superada · 3 fallida (se reinicia sola)
var checkpoint := 0
var brazier_cd := 0.0
var _next_id := 1
var _time := 0.0
var _gate_open := false
var _respawns: Array = []        # [tiempo, tipo, x, z] de enemigos ambientales por reaparecer
var _rng := RandomNumberGenerator.new()
## Nojoch Tuunich, el jefe del capítulo (server/boss.gd). Duerme hasta que se supera la emboscada.
var boss: BossAI


func _init() -> void:
	boss = BossAI.new(self)
	_rng.randomize()
	for a in Defs.AMBIENT:
		_spawn(a[0], a[1], a[2], 1.0, false)


func _spawn(kind: String, x: float, z: float, hp_scale: float, wave: bool) -> Enemy:
	var def: Dictionary = Defs.ENEMIES[kind]
	var e := Enemy.new()
	e.id = _next_id
	_next_id += 1
	e.kind = kind
	var p := Sim.resolve_xz(Vector2(x, z), World.terrain_h(x, z), def.radius, _gate_open)
	e.x = p.x
	e.z = p.y
	e.y = World.terrain_h(p.x, p.y)
	e.home = p
	e.wp = p
	e.max_hp = def.hp * hp_scale
	e.hp = e.max_hp
	e.wave = wave
	e.yaw = _rng.randf() * TAU
	e.t = _rng.randf_range(0.5, 2.5)
	enemies.append(e)
	return e


## Emboscada del santuario: aparece cuando se abre la puerta.
func start_encounter(player_count: int) -> void:
	if encounter != 0:
		return
	encounter = 1
	var kinds := Defs.encounter_wave(player_count)
	var scale := Defs.hp_scale(player_count)
	var c := Defs.ENCOUNTER_CENTER
	for i in kinds.size():
		var ang := float(i) / float(kinds.size()) * TAU + 0.4
		var rad := 4.0 + float(i % 3) * 1.3
		var e := _spawn(kinds[i], c.x + cos(ang) * rad, c.y + sin(ang) * rad, scale, true)
		e.home = c
		e.wake = Defs.ENCOUNTER_WAKE + 0.25 * float(i)   # despiertan escalonados
		e.dmg_scale = Defs.dmg_scale(player_count)
	events.append(["enc", "start", kinds.size()])


static func _targetable(p: Variant) -> bool:
	return p.conn_id != 0 and not p.state.dead


# ───────────────────────── Acciones de los jugadores ─────────────────────────

## Recibe una acción emitida por la simulación del jugador y resuelve su efecto.
func player_action(p: Variant, ev: Dictionary, players: Array) -> void:
	var kind: String = ev.k
	var yaw: float = ev.r
	var s: Sim.PlayerState = p.state
	var form: Dictionary = Defs.FORMS[s.form]
	# Todos ven la animación; el daño se decide aquí abajo
	events.append(["act", p.slot, kind, snappedf(yaw, 0.01), snappedf(ev.p, 0.01)])
	match kind:
		"bolt":
			var ab: Dictionary = form.primary
			var b := {
				"id": _next_id, "owner": p, "x": s.pos.x + sin(yaw) * 0.5, "y": s.pos.y + 0.9, "z": s.pos.z + cos(yaw) * 0.5,
				"dx": sin(yaw), "dz": cos(yaw), "speed": float(ab.speed), "life": float(ab.life),
				"dmg": float(ab.dmg), "radius": float(ab.radius),
			}
			_next_id += 1
			bolts.append(b)
			events.append(["bolt", b.id, p.slot, snappedf(b.x, 0.01), snappedf(b.y, 0.01), snappedf(b.z, 0.01), snappedf(yaw, 0.01)])
		"claw":
			var ab: Dictionary = form.primary
			_melee(p, yaw, ab.range, ab.arc, ab.dmg, "claw", 1.5, 0.0)
		"charged":
			var ab: Dictionary = form.secondary
			var power: float = clampf(ev.p, 0.0, 1.0)
			_melee(p, yaw, ab.range, ab.arc, lerpf(ab.dmg_min, ab.dmg_max, power), "charged", ab.knock, ab.stun * (0.5 + 0.5 * power))
		"pounce_land":
			var ab: Dictionary = form.special
			if ab.kind == "pounce":
				_melee(p, yaw, ab.radius, TAU, ab.dmg, "pounce", ab.knock, ab.stun)
		"interact":
			_interact(p, players)


func _melee(p: Variant, yaw: float, reach: float, arc: float, dmg: float, kind: String, knock: float, stun: float) -> void:
	var s: Sim.PlayerState = p.state
	var origin := Vector2(s.pos.x, s.pos.z)
	for e in enemies:
		if e.state == "dead":
			continue
		var def: Dictionary = Defs.ENEMIES[e.kind]
		var d := Vector2(e.x, e.z) - origin
		var dist := d.length()
		if dist > reach + def.radius or absf(e.y - s.pos.y) > 2.4:
			continue
		if dist > 0.7 and arc < TAU and absf(angle_difference(yaw, atan2(d.x, d.y))) > arc * 0.5:
			continue
		var away := d / dist if dist > 0.01 else Vector2(sin(yaw), cos(yaw))
		_damage_enemy(e, dmg, p, kind, away, knock, stun)
	# Al guardián no se le hace daño: sólo su corazón expuesto acusa las garras de Balam
	boss.on_melee(p, dmg, reach)


func _interact(p: Variant, players: Array) -> void:
	var s: Sim.PlayerState = p.state
	var here := Vector2(s.pos.x, s.pos.z)
	var reach: float = Defs.FORMS[s.form].special.get("range", 2.8)
	# 1) Purificar a una criatura corrompida debilitada
	var best: Enemy = null
	var best_d := reach
	for e in enemies:
		var def: Dictionary = Defs.ENEMIES[e.kind]
		if e.state == "dead" or def.purify_at <= 0.0 or e.hp > e.max_hp * def.purify_at:
			continue
		var d := (Vector2(e.x, e.z) - here).length() - float(def.radius)
		if d < best_d:
			best_d = d
			best = e
	if best != null:
		_kill(best, p, true)
		for o in players:
			if _targetable(o) and Vector2(o.state.pos.x - best.x, o.state.pos.z - best.z).length() < 9.0:
				_heal(o, Defs.PURIFY_HEAL)
		return
	# 2) Despertar una columna de la explanada (fase 2 del guardián)
	if boss.raise_pillar(p):
		return
	# 3) Brasero de la plaza: cura a quienes estén cerca
	if brazier_cd <= 0.0 and (here - Defs.BRAZIER).length() < Defs.BRAZIER_RANGE:
		brazier_cd = Defs.BRAZIER_CD
		events.append(["brazier", p.slot])
		for o in players:
			if _targetable(o) and (Vector2(o.state.pos.x, o.state.pos.z) - Defs.BRAZIER).length() < Defs.BRAZIER_RANGE + 2.0:
				_heal(o, Defs.BRAZIER_HEAL)


func _heal(p: Variant, amount: float) -> void:
	var before: float = p.hp
	p.hp = minf(Defs.MAX_HP, p.hp + amount)
	if p.hp > before:
		events.append(["heal", p.slot, int(round(p.hp - before)), int(round(p.hp))])


# ───────────────────────── Daño ─────────────────────────

func _damage_enemy(e: Enemy, amount: float, by: Variant, kind: String, away: Vector2, knock: float, stun: float) -> void:
	if e.state == "dead":
		return
	var def: Dictionary = Defs.ENEMIES[e.kind]
	var dealt := amount * float(def.mult.get(kind, 1.0))
	e.hp -= dealt
	if by != null:
		e.threat[by.id] = float(e.threat.get(by.id, 0.0)) + dealt * (1.5 if kind == "charged" else 1.0)
	events.append(["hit", "e", e.id, int(round(dealt)), int(ceil(maxf(e.hp, 0.0))), by.slot if by != null else -1])
	if e.hp <= 0.0:
		_kill(e, by, false)
		return
	if knock > 0.0:
		var push := away * knock * 0.18 * float(def.knock_resist)
		var p := Sim.move_xz(Vector2(e.x, e.z), push, e.y, def.radius, _gate_open)
		if World.terrain_h(p.x, p.y) >= World.WATER_LEVEL - 0.45:
			e.x = p.x
			e.z = p.y
	if stun > 0.0 and e.state != "strike":
		e.state = "stun"
		e.t = stun * float(def.knock_resist)
	elif e.state == "idle" or e.state == "return":
		e.state = "chase"


func _kill(e: Enemy, by: Variant, purified: bool) -> void:
	e.hp = 0.0
	e.state = "dead"
	e.t = 1.6
	events.append(["die", "e", e.id, 1 if purified else 0, by.slot if by != null else -1])
	if not e.wave and not e.summoned:
		_respawns.append([_time + Defs.AMBIENT_RESPAWN, e.kind, e.home.x, e.home.y])
	if purified and by != null:
		boss.on_purified(e, by)


func damage_player(p: Variant, amount: float, from: Vector2, knock: float) -> void:
	var s: Sim.PlayerState = p.state
	if s.dead or p.invuln_t > 0.0:
		return
	if s.dash_t > 0:
		events.append(["evade", p.slot])
		return
	p.hp -= amount
	p.hurt_at = _time
	var d := Vector2(s.pos.x, s.pos.z) - from
	if d.length() > 0.01 and knock > 0.0:
		d = d.normalized() * knock
		s.kx = d.x
		s.kz = d.y
	events.append(["hit", "p", p.slot, int(round(amount)), int(ceil(maxf(p.hp, 0.0))), -1])
	if p.hp <= 0.0:
		p.hp = 0.0
		s.dead = true
		s.charge_t = 0
		s.dash_t = 0
		s.pounce = false
		p.respawn_t = Defs.RESPAWN_TIME_ENCOUNTER if encounter == 1 or boss.active() else Defs.RESPAWN_TIME
		events.append(["die", "p", p.slot, 0, -1])


# ───────────────────────── Tick ─────────────────────────

## Avanza el combate un tick. Devuelve CLEARED si la emboscada se superó en este tick,
## FAILED si todo el grupo conectado cayó a la vez, y NOTHING en cualquier otro caso.
enum { NOTHING, CLEARED, FAILED }

func tick(players: Array, gate_open: bool) -> int:
	_time += DT
	_gate_open = gate_open
	brazier_cd = maxf(0.0, brazier_cd - DT)

	# Jugadores: reaparición, invulnerabilidad y regeneración
	for p in players:
		p.invuln_t = maxf(0.0, p.invuln_t - DT)
		var s: Sim.PlayerState = p.state
		if s.dead:
			p.respawn_t -= DT
			if p.respawn_t <= 0.0:
				_respawn(p)
		elif p.hp < Defs.MAX_HP and _time - p.hurt_at > Defs.HP_REGEN_DELAY:
			p.hp = minf(Defs.MAX_HP, p.hp + Defs.HP_REGEN * DT)

	_tick_bolts()
	for e in enemies:
		_tick_enemy(e, players)
	_separate()
	boss.tick(players)

	# Retirar cadáveres y reaparecer enemigos ambientales
	enemies = enemies.filter(func(e: Enemy) -> bool: return e.state != "dead" or e.t > 0.0)
	for r in _respawns.duplicate():
		if _time >= r[0]:
			var near := false
			for p in players:
				if _targetable(p) and Vector2(p.state.pos.x - r[2], p.state.pos.z - r[3]).length() < 14.0:
					near = true
			if not near:
				_respawns.erase(r)
				_spawn(r[1], r[2], r[3], 1.0, false)

	if encounter == 1:
		var alive := 0
		for e in enemies:
			if e.wave and e.state != "dead":
				alive += 1
		if alive == 0:
			encounter = 2
			checkpoint = 1
			events.append(["enc", "clear", 0])
			return CLEARED
		# Derrota: no queda en pie ninguno de los jugadores conectados
		var connected := 0
		var standing := 0
		for p in players:
			if p.conn_id != 0:
				connected += 1
				if not p.state.dead:
					standing += 1
		if connected > 0 and standing == 0:
			_fail(players)
			return FAILED
	return NOTHING


## El grupo entero cayó: la emboscada se retira y habrá que volver a abrir el santuario.
func _fail(players: Array) -> void:
	encounter = 3
	checkpoint = 0
	enemies = enemies.filter(func(e: Enemy) -> bool: return not e.wave)
	for b in bolts:
		events.append(["bolt_end", b.id, snappedf(b.x, 0.01), snappedf(b.y, 0.01), snappedf(b.z, 0.01), 0])
	bolts.clear()
	events.append(["enc", "fail", 0])
	# Quien no esté conectado no reaparece por su cuenta: se le lleva ya al punto de control.
	# Los demás vuelven pronto y a la vez, para reagruparse.
	for p in players:
		if p.conn_id == 0:
			_respawn(p, false)
		elif p.state.dead:
			p.respawn_t = minf(p.respawn_t, Defs.RESPAWN_TIME_DEFEAT)


## Nueva ronda (tras una victoria, a petición del grupo): todo vuelve al estado inicial.
func restart(players: Array) -> void:
	encounter = 0
	checkpoint = 0
	_gate_open = false
	enemies = enemies.filter(func(e: Enemy) -> bool: return not e.wave)
	bolts.clear()
	brazier_cd = 0.0
	boss.reset(true)
	for p in players:
		_respawn(p, p.conn_id != 0)


func wave_alive() -> int:
	var n := 0
	for e in enemies:
		if e.wave and e.state != "dead":
			n += 1
	return n


func _respawn(p: Variant, announce := true) -> void:
	var s: Sim.PlayerState = p.state
	var c: Vector2 = Defs.CHECKPOINTS[checkpoint]
	var off := Vector2(cos(p.slot * 1.57), sin(p.slot * 1.57)) * 1.4
	var at := Sim.resolve_xz(c + off, World.terrain_h(c.x, c.y), Sim.BODY_R, _gate_open)
	s.pos = Vector3(at.x, World.terrain_h(at.x, at.y), at.y)
	s.vy = 0.0
	s.kx = 0.0
	s.kz = 0.0
	s.dead = false
	s.grounded = true
	s.swim = false
	s.energy = Defs.MAX_ENERGY
	p.hp = Defs.MAX_HP
	p.invuln_t = Defs.RESPAWN_INVULN
	p.hurt_at = _time
	p.respawn_t = 0.0
	if announce:
		events.append(["respawn", p.slot])


func _tick_bolts() -> void:
	for b in bolts:
		b.life -= DT
		var step: float = b.speed * DT
		b.x += b.dx * step
		b.z += b.dz * step
		var hit := false
		var blocked: bool = b.life <= 0.0
		for e in enemies:
			if e.state == "dead":
				continue
			var def: Dictionary = Defs.ENEMIES[e.kind]
			if b.y < e.y - 0.3 or b.y > e.y + float(def.height) + 0.6:
				continue
			var rr: float = float(def.radius) + float(b.radius)
			if (e.x - b.x) * (e.x - b.x) + (e.z - b.z) * (e.z - b.z) < rr * rr:
				_damage_enemy(e, b.dmg, b.owner, "bolt", Vector2(b.dx, b.dz), 0.8, 0.0)
				hit = true
				break
		if not hit and not blocked and Sim.point_blocked(b.x, b.y, b.z, _gate_open):
			blocked = true
		if hit or blocked:
			b.life = -1.0
			events.append(["bolt_end", b.id, snappedf(b.x, 0.01), snappedf(b.y, 0.01), snappedf(b.z, 0.01), 1 if hit else 0])
	bolts = bolts.filter(func(b: Dictionary) -> bool: return b.life > 0.0)


# ───────────────────────── IA ─────────────────────────

func _pick_target(e: Enemy, players: Array) -> Variant:
	var def: Dictionary = Defs.ENEMIES[e.kind]
	var here := Vector2(e.x, e.z)
	var best: Variant = null
	var best_score := -1.0
	for p in players:
		if not _targetable(p):
			continue
		var d := (Vector2(p.state.pos.x, p.state.pos.z) - here).length()
		var threat: float = e.threat.get(p.id, 0.0)
		if threat <= 0.5 and d > float(def.aggro) and not e.wave:
			continue  # ni cerca ni me ha atacado
		if d > 30.0:
			continue
		# Prefiere a quien más daño le ha hecho; a igualdad, al más cercano
		var score := threat + maxf(0.0, 30.0 - d) * 0.4
		if score > best_score:
			best_score = score
			best = p
	return best


func _move(e: Enemy, dir: Vector2, speed: float) -> bool:
	if dir.length() < 0.001:
		return false
	var def: Dictionary = Defs.ENEMIES[e.kind]
	var before := Vector2(e.x, e.z)
	var want := dir.normalized() * speed * DT
	var p := Sim.move_xz(before, want, e.y, def.radius, _gate_open)
	if World.terrain_h(p.x, p.y) < World.WATER_LEVEL - 0.45:
		return false  # no entran al agua
	e.x = p.x
	e.z = p.y
	e.y = Sim.floor_at(p.x, p.y, e.y, _gate_open)
	return (p - before).length() > want.length() * 0.35


func _walk_to(e: Enemy, goal: Vector2, speed: float) -> void:
	var d := goal - Vector2(e.x, e.z)
	if d.length() < 0.05:
		return
	var dir := d.normalized()
	# Si se atasca contra un obstáculo, lo rodea un momento
	if e.side_t > 0.0:
		e.side_t -= DT
		dir = dir.rotated(1.25 * e.side)
	e.yaw = atan2(dir.x, dir.y)
	if _move(e, dir, speed):
		e.stuck_t = 0.0
	else:
		e.stuck_t += DT
		if e.stuck_t > 0.35 and e.side_t <= 0.0:
			e.side = 1.0 if _rng.randf() < 0.5 else -1.0
			e.side_t = 0.9
			e.stuck_t = 0.0


func _tick_enemy(e: Enemy, players: Array) -> void:
	var def: Dictionary = Defs.ENEMIES[e.kind]
	e.t -= DT
	for k in e.threat.keys():
		e.threat[k] *= 0.994
	var here := Vector2(e.x, e.z)

	match e.state:
		"dead":
			return
		"stun":
			if e.t <= 0.0:
				e.state = "chase"
		"idle":
			if e.wake > 0.0:
				e.wake -= DT
				if e.threat.is_empty():
					return   # aún despertando; si alguien lo golpea, reacciona ya
				e.wake = 0.0
			var tgt: Variant = _pick_target(e, players)
			if tgt != null:
				e.state = "chase"
				return
			if e.t <= 0.0:
				var a := _rng.randf() * TAU
				e.wp = e.home + Vector2(cos(a), sin(a)) * _rng.randf_range(1.5, 4.5)
				e.t = _rng.randf_range(2.5, 5.5)
			if (e.wp - here).length() > 0.4:
				_walk_to(e, e.wp, float(def.speed) * 0.4)
		"chase":
			var tgt: Variant = _pick_target(e, players)
			if tgt == null or (not e.wave and (here - e.home).length() > Defs.LEASH):
				e.state = "return"
				e.target = ""
				e.target_slot = -1
				e.threat.clear()
				return
			e.target = tgt.id
			e.target_slot = tgt.slot
			var tp := Vector2(tgt.state.pos.x, tgt.state.pos.z)
			var d := (tp - here).length()
			if d <= float(def.range) and absf(tgt.state.pos.y - e.y) < 2.5:
				e.state = "windup"
				e.t = def.windup
				e.dir = (tp - here).normalized() if d > 0.01 else Vector2(sin(e.yaw), cos(e.yaw))
				e.yaw = atan2(e.dir.x, e.dir.y)
			else:
				_walk_to(e, tp, def.speed)
		"windup":
			if e.t <= 0.0:
				if def.has("lunge_speed"):
					e.state = "strike"
					e.t = def.lunge_t
					e.struck = {}
				else:
					# Golpe en área frente al enemigo
					var center := here + e.dir * 1.0
					for p in players:
						if _targetable(p) and (Vector2(p.state.pos.x, p.state.pos.z) - center).length() < float(def.hit_radius) \
								and absf(p.state.pos.y - e.y) < 2.0:
							damage_player(p, float(def.dmg) * e.dmg_scale, here, 6.0)
					events.append(["eatk", e.id])
					e.state = "recover"
					e.t = def.recover
		"strike":
			_move(e, e.dir, def.lunge_speed)
			here = Vector2(e.x, e.z)
			for p in players:
				if _targetable(p) and not e.struck.has(p.id) \
						and (Vector2(p.state.pos.x, p.state.pos.z) - here).length() < float(def.hit_radius) + Sim.BODY_R \
						and absf(p.state.pos.y - e.y) < 1.8:
					e.struck[p.id] = true
					damage_player(p, float(def.dmg) * e.dmg_scale, here, 4.0)
			if e.t <= 0.0:
				e.state = "recover"
				e.t = def.recover
		"recover":
			if e.t <= 0.0:
				e.state = "chase"
		"return":
			e.hp = minf(e.max_hp, e.hp + e.max_hp * 0.25 * DT)
			if (e.home - here).length() < 1.0:
				e.state = "idle"
				e.t = 1.0
			else:
				_walk_to(e, e.home, def.speed)
			# si alguien lo ataca mientras vuelve, responde (la amenaza se añade al recibir daño)


func _separate() -> void:
	for i in enemies.size():
		var a: Enemy = enemies[i]
		if a.state == "dead" or a.state == "strike":
			continue
		for j in range(i + 1, enemies.size()):
			var b: Enemy = enemies[j]
			if b.state == "dead" or b.state == "strike":
				continue
			var d := Vector2(b.x - a.x, b.z - a.z)
			var min_d: float = float(Defs.ENEMIES[a.kind].radius) + float(Defs.ENEMIES[b.kind].radius)
			var len := d.length()
			if len < min_d and len > 0.001:
				var push := d / len * (min_d - len) * 0.5
				var pa := Sim.move_xz(Vector2(a.x, a.z), -push, a.y, Defs.ENEMIES[a.kind].radius, _gate_open)
				var pb := Sim.move_xz(Vector2(b.x, b.z), push, b.y, Defs.ENEMIES[b.kind].radius, _gate_open)
				a.x = pa.x
				a.z = pa.y
				b.x = pb.x
				b.z = pb.y


func snapshot() -> Array:
	var out := []
	for e in enemies:
		out.append([e.id, Defs.ENEMY_IDS.find(e.kind), snappedf(e.x, 0.01), snappedf(e.y, 0.01), snappedf(e.z, 0.01),
			snappedf(e.yaw, 0.01), int(ceil(maxf(e.hp, 0.0))), int(round(e.max_hp)), Defs.ENEMY_STATES.find(e.state), e.target_slot])
	return out
