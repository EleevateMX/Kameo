extends RefCounted
## Mundo abierto en el servidor de zonas: lo que tiene el «Camino a Motul» y no tiene la plaza.
##
##   · Criaturas hostiles simuladas aquí: aparecen en puntos fijos (camino_def.SPAWNS), persiguen a
##     quien se acerca, avisan antes de golpear, no entran a las zonas seguras y reaparecen al rato.
##   · Combate mínimo: un ataque básico del alux validado por el servidor (alcance, arco,
##     enfriamiento; nunca desde una zona segura) y purificar con F a las criaturas débiles.
##     NO es el combate de la mazmorra (combat.gd): no hay formas, energía ni proyectiles.
##   · Vida del jugador en la zona, caída y reaparición en la zona segura más cercana, sin perder nada.
##   · Puntos de descubrimiento y una misión, comprobados por posición.
##   · Recompensas: se piden a la API (`/internal/rpg/grant`, docs/RPG.md); aquí no se calcula
##     ninguna cantidad. Cobran todos los que participaron y siguen cerca.
##
## Sólo se simula si hay alguien en la zona. El servidor de zonas (zone_server.gd) llama a
## `join`, `leave`, `handle` y `step`, y presta `send_to`, `grant` y `warp`.
##
## Del jugador (clase P de zone_server.gd) usa: id, num, s, yaw, hp, max_hp, dmg, atk_ready,
## down, down_until, invuln_until, hurt_at y memo (lo que se recuerda entre conexiones:
## `found` = lugares descubiertos, `quest` = estado de la misión).

const Camino := preload("res://scripts/shared/camino_def.gd")
const Wild := preload("res://scripts/shared/wild_def.gd")

const VIEW_R := 44.0               # hasta dónde se mandan criaturas y sucesos
const NEAR_R := 26.0               # más cerca van en todos los estados; más lejos, en los turnos lejanos


class Creature:
	var id := 0
	var kind := ""
	var def: Dictionary
	var home := Vector2.ZERO
	var pos := Vector2.ZERO
	var yaw := 0.0
	var hp := 0.0
	var state := "idle"
	var t := 0.0                 # segundos en el estado actual
	var target := ""             # id del jugador al que persigue
	var alive := true
	var round := 0               # cuántas veces ha reaparecido (entra en la clave de la recompensa)
	var respawn_at := 0.0
	var hitters := {}            # id de jugador -> instante del último golpe
	var roam := Vector2.ZERO
	var roam_in := 0.0


var zone := Camino.ID
var _srv: Node
var _boot := ""                  # distingue las claves de recompensa de cada arranque del servidor
var _creatures: Array = []
var _players: Array = []         # los de esta zona en el paso en curso
var _time := 0.0
var _tick := 0
var _respawn := Wild.RESPAWN
var _harm := 1.0                 # multiplicador del daño de las criaturas (ALUX_WILD_DAMAGE; pruebas y ajuste)
var _rng := RandomNumberGenerator.new()


func _init(server: Node, boot: String, respawn: float, harm := 1.0) -> void:
	_srv = server
	_boot = boot
	_respawn = respawn
	_harm = harm
	_rng.seed = 20261113
	for i in Camino.SPAWNS.size():
		var sp: Array = Camino.SPAWNS[i]
		var c := Creature.new()
		c.id = i
		c.kind = str(sp[0])
		c.def = Wild.CREATURES[c.kind]
		c.home = Vector2(float(sp[1]), float(sp[2]))
		c.pos = c.home
		c.hp = float(c.def.hp)
		c.yaw = _rng.randf() * TAU
		_creatures.append(c)


# ───────────────────────── Entrar y salir ─────────────────────────

func join(p: Object) -> void:
	p.hp = p.max_hp
	p.down = false
	p.atk_ready = 0
	p.invuln_until = _time + Wild.RESPAWN_INVULN
	p.hurt_at = -100.0


func leave(p: Object) -> void:
	_players.erase(p)
	for c in _creatures:
		if (c as Creature).target == p.id:
			(c as Creature).target = ""


## Lo que acompaña a la bienvenida de la zona: vida, lugares ya conocidos y estado de la misión.
func info(p: Object) -> Dictionary:
	return {"hp": int(ceil(p.hp)), "maxhp": int(p.max_hp), "known": (p.memo.found as Dictionary).keys(), "quest": _quest_msg(p)}


func _quest_msg(p: Object) -> Dictionary:
	var q: Dictionary = p.memo.quest
	return {"t": "quest", "id": Wild.MISSION, "st": q.st, "n": q.n, "need": int(Wild.MISSIONS[Wild.MISSION].purify)}


# ───────────────────────── Mensajes del jugador ─────────────────────────

func handle(p: Object, t: String, msg: Dictionary) -> bool:
	match t:
		"atk":
			_attack(p, wrapf(_num(msg.get("r")), -PI, PI))
		"purify":
			_purify(p)
		"quest":
			_quest_accept(p)
		_:
			return false
	return true


static func _num(v: Variant) -> float:
	return float(v) if (typeof(v) == TYPE_FLOAT or typeof(v) == TYPE_INT) and is_finite(float(v)) else 0.0


static func _at(p: Object) -> Vector2:
	return Vector2(float(p.s[0]), float(p.s[2]))


## Ataque básico. El cliente sólo dice hacia dónde apunta: alcance, arco, enfriamiento y daño
## los pone el servidor, con la posición que él mismo calculó.
func _attack(p: Object, yaw: float) -> void:
	var why := ""
	if p.down:
		why = "down"
	elif _tick < int(p.atk_ready):
		why = "cd"
	elif Camino.is_safe(float(p.s[0]), float(p.s[2])):
		why = "safe"
	if not why.is_empty():
		_srv.send_to(p, {"t": "atk_no", "why": why})
		return
	p.atk_ready = _tick + Wild.ATTACK_CD_TICKS
	var me := _at(p)
	var aim := Vector2(sin(yaw), cos(yaw))
	var best: Creature = null
	var best_d := INF
	for c in _creatures:
		var cr: Creature = c
		if not cr.alive:
			continue
		var to := cr.pos - me
		var d := to.length()
		if d > float(Wild.ATTACK.range) + float(cr.def.radius):
			continue
		# de muy cerca el arco no cuenta (la criatura está encima)
		if d > 1.2 and absf(aim.angle_to(to)) > float(Wild.ATTACK.arc) * 0.5:
			continue
		if d < best_d:
			best_d = d
			best = cr
	var dmg := 0.0
	if best != null:
		dmg = snappedf(float(Wild.ATTACK.dmg) * float(p.dmg), 0.1)
		_damage(best, p, dmg)
	_event(me, {"t": "ev", "e": "atk", "i": p.num, "c": best.id if best != null else -1, "d": dmg, "r": snappedf(yaw, 0.01)})


func _damage(c: Creature, p: Object, dmg: float) -> void:
	c.hp -= dmg
	c.hitters[p.id] = _time
	if c.hp <= 0.0:
		_kill(c, false)
		return
	if c.state != "weak" and c.hp <= float(c.def.hp) * float(c.def.purify_at):
		_set_state(c, "weak")
	elif c.state == "idle" or c.state == "return":
		if _valid_target(c, p):
			c.target = p.id
			_set_state(c, "chase")


## Purificar (F): la criatura débil más cercana al alcance.
func _purify(p: Object) -> void:
	if p.down:
		return
	var me := _at(p)
	var best: Creature = null
	var best_d := INF
	for c in _creatures:
		var cr: Creature = c
		if not cr.alive or cr.state != "weak":
			continue
		var d := cr.pos.distance_to(me)
		if d <= Wild.PURIFY_RANGE + float(cr.def.radius) and d < best_d:
			best_d = d
			best = cr
	if best == null:
		_srv.send_to(p, {"t": "atk_no", "why": "nothing"})
		return
	best.hitters[p.id] = _time
	p.hp = minf(p.max_hp, p.hp + Wild.PURIFY_HEAL)
	_kill(best, true)


## Muere (o queda purificada): cobran todos los que la golpearon hace poco y siguen cerca.
func _kill(c: Creature, purified: bool) -> void:
	c.alive = false
	c.respawn_at = _time + _respawn
	c.target = ""
	var credit: Array = []
	for pl in _players:
		if c.hitters.has(pl.id) and _time - float(c.hitters[pl.id]) <= Wild.CREDIT_TIME and _at(pl).distance_to(c.pos) <= Wild.CREDIT_R:
			credit.append(pl)
	c.hitters.clear()
	_event(c.pos, {"t": "ev", "e": "die", "c": c.id, "p": 1 if purified else 0})
	if credit.is_empty():
		return
	var key := "%s:%s-%d:%d" % [zone, _boot, c.round, c.id]
	var grants: Array = []
	for pl in credit:
		grants.append({"playerId": pl.id, "kind": "purify" if purified else "enemy", "key": key})
		if purified:
			_quest_progress(pl)
	_srv.grant(grants)


# ───────────────────────── Paso de simulación ─────────────────────────

## Un paso (20 por segundo). `players`: los que están en esta zona.
func step(players: Array, dt: float) -> void:
	_players = players
	_time += dt
	_tick += 1
	for p in players:
		_step_player(p, dt)
	for c in _creatures:
		_step_creature(c, dt)
	if _tick % 4 == 0:
		for p in players:
			if not p.down:
				_check_places(p)


func _step_player(p: Object, dt: float) -> void:
	if p.down:
		if _time >= float(p.down_until):
			_respawn_player(p)
		return
	if p.hp < p.max_hp:
		if Camino.is_safe(float(p.s[0]), float(p.s[2])):
			p.hp = minf(p.max_hp, p.hp + Wild.HP_REGEN_SAFE * dt)
		elif _time - float(p.hurt_at) >= Wild.HP_REGEN_DELAY:
			p.hp = minf(p.max_hp, p.hp + Wild.HP_REGEN * dt)


func _hurt(p: Object, dmg: float, by: Creature) -> void:
	p.hp -= dmg
	p.hurt_at = _time
	_event(_at(p), {"t": "ev", "e": "hit", "i": p.num, "c": by.id, "d": dmg})
	if p.hp <= 0.0:
		p.hp = 0.0
		p.down = true
		p.down_until = _time + Wild.DOWN_TIME
		p.queue.clear()
		_event(_at(p), {"t": "ev", "e": "down", "i": p.num})


## Vuelve en la zona segura más cercana, con la vida entera. No pierde nada: ni la misión ni lo descubierto.
func _respawn_player(p: Object) -> void:
	var me := _at(p)
	var best: Vector2 = Camino.RESPAWNS[0]
	for r in Camino.RESPAWNS:
		if me.distance_to(r) < me.distance_to(best):
			best = r
	p.down = false
	p.hp = p.max_hp
	p.invuln_until = _time + Wild.RESPAWN_INVULN
	p.hurt_at = -100.0
	var a := float(p.num) * 2.4
	_srv.warp(p, best + Vector2(sin(a), cos(a)) * 1.2, p.yaw)
	_event(best, {"t": "ev", "e": "up", "i": p.num})


func _player(pid: String) -> Object:
	for p in _players:
		if p.id == pid:
			return p
	return null


func _valid_target(c: Creature, p: Object) -> bool:
	if p == null or p.down:
		return false
	var at := _at(p)
	return not Camino.is_safe(at.x, at.y) and at.distance_to(c.home) <= Wild.LEASH + float(c.def.aggro)


func _set_state(c: Creature, state: String) -> void:
	c.state = state
	c.t = 0.0


## Mueve la criatura hacia `to` sin salir de lo transitable ni entrar a una zona segura.
func _move(c: Creature, to: Vector2, speed: float, dt: float) -> void:
	var d := to - c.pos
	var dist := d.length()
	if dist < 0.01:
		return
	var r := float(c.def.radius)
	var next := c.pos + d / dist * minf(dist, speed * dt)
	next = Camino.confine(next.x, next.y, r)
	next = Camino.push_out(next.x, next.y, r)
	for s in Camino.SAFE:
		if next.distance_to(Vector2(float(s[0]), float(s[1]))) < float(s[2]) + r:
			return   # la zona segura no se pisa
	c.pos = next
	c.yaw = atan2(d.x, d.y)


func _step_creature(c: Creature, dt: float) -> void:
	if not c.alive:
		if _time < c.respawn_at:
			return
		# No reaparece con un alux encima, salvo que lleve mucho esperando
		if _time < c.respawn_at + Wild.RESPAWN_WAIT_MAX:
			for p in _players:
				if _at(p).distance_to(c.home) < Wild.RESPAWN_CLEAR_R:
					return
		c.alive = true
		c.round += 1
		c.hp = float(c.def.hp)
		c.pos = c.home
		c.target = ""
		_set_state(c, "idle")
		return
	c.t += dt
	var def := c.def
	var target: Object = _player(c.target) if not c.target.is_empty() else null
	match c.state:
		"idle":
			# ¿Alguien a tiro? El más cercano que no esté a salvo
			var best: Object = null
			var best_d := float(def.aggro)
			for p in _players:
				var d := _at(p).distance_to(c.pos)
				if d <= best_d and _valid_target(c, p):
					best_d = d
					best = p
			if best != null:
				c.target = best.id
				_set_state(c, "chase")
				return
			# Ronda su sitio
			c.roam_in -= dt
			if c.roam_in <= 0.0:
				c.roam_in = 3.0 + _rng.randf() * 4.0
				var a := _rng.randf() * TAU
				c.roam = c.home + Vector2(sin(a), cos(a)) * (_rng.randf() * 2.5)
			_move(c, c.roam, float(def.speed) * 0.35, dt)
		"chase":
			if not _valid_target(c, target) or c.pos.distance_to(c.home) > Wild.LEASH:
				c.target = ""
				_set_state(c, "return")
				return
			var to := _at(target)
			var d := to.distance_to(c.pos)
			if d <= float(def.range):
				c.yaw = atan2(to.x - c.pos.x, to.y - c.pos.y)
				_set_state(c, "windup")   # el aviso: el cliente lo enseña antes de que caiga el golpe
			else:
				_move(c, to, float(def.speed), dt)
		"windup":
			if c.t >= float(def.windup):
				var center := c.pos + Vector2(sin(c.yaw), cos(c.yaw)) * float(def.reach)
				for p in _players:
					var at := _at(p)
					if p.down or _time < float(p.invuln_until) or Camino.is_safe(at.x, at.y):
						continue
					if at.distance_to(center) <= float(def.hit_radius) + Camino.PLAYER_R:
						_hurt(p, float(def.dmg) * _harm, c)
				_set_state(c, "recover")
		"recover":
			if c.t >= float(def.recover):
				_set_state(c, "chase" if _valid_target(c, target) else "return")
		"weak":
			if c.t >= Wild.WEAK_TIME:
				c.hp = float(def.hp) * Wild.WEAK_RECOVER
				_set_state(c, "chase" if _valid_target(c, target) else "return")
		"return":
			_move(c, c.home, float(def.speed) * 1.3, dt)
			if c.pos.distance_to(c.home) < 0.5:
				c.hp = float(def.hp)
				c.hitters.clear()
				_set_state(c, "idle")


# ───────────────────────── Lugares y misión ─────────────────────────

func _check_places(p: Object) -> void:
	var at := _at(p)
	var found: Dictionary = p.memo.found
	for d in Camino.DISCOVERIES:
		if at.distance_to(d.at) > float(d.r):
			continue
		var id := str(d.id)
		if not found.has(id):
			found[id] = true
			_discover(p.id, id)
		if id == str(Wild.MISSIONS[Wild.MISSION].goal):
			_quest_goal(p)


## Lugar nuevo para esta sesión: la API dice si lo era de verdad (una vez por jugador y lugar).
## El aviso al cliente espera a esa respuesta para no celebrar dos veces lo ya descubierto.
func _discover(pid: String, id: String) -> void:
	_srv.grant([{"playerId": pid, "kind": "discovery", "key": id}], func(results: Variant) -> void:
		var p: Object = _srv.player(pid)
		if p == null:
			return
		var fresh := true   # sin API no se sabe: se da por nuevo (la recompensa no llega)
		if results is Array and not (results as Array).is_empty() and (results as Array)[0] is Dictionary:
			var r: Dictionary = (results as Array)[0]
			fresh = bool(r.get("applied", false)) or str(r.get("reason", "")) != "duplicate"
		_srv.send_to(p, {"t": "disc", "id": id, "new": fresh}))


func _quest_accept(p: Object) -> void:
	var q: Dictionary = p.memo.quest
	if p.down or str(q.st) != "none" or _at(p).distance_to(Camino.QUEST_NPC) > Camino.NPC_R + 0.5:
		_srv.send_to(p, _quest_msg(p))
		return
	q.st = "active"
	q.n = 0
	_srv.send_to(p, _quest_msg(p))


func _quest_progress(p: Object) -> void:
	var q: Dictionary = p.memo.quest
	var need := int(Wild.MISSIONS[Wild.MISSION].purify)
	if str(q.st) != "active" or int(q.n) >= need:
		return
	q.n = int(q.n) + 1
	_srv.send_to(p, _quest_msg(p))


## En el cartel de Motul con las purificaciones hechas: misión cumplida (recompensa única).
func _quest_goal(p: Object) -> void:
	var q: Dictionary = p.memo.quest
	if str(q.st) != "active" or int(q.n) < int(Wild.MISSIONS[Wild.MISSION].purify):
		return
	q.st = "done"
	_srv.send_to(p, _quest_msg(p))
	_srv.grant([{"playerId": p.id, "kind": "mission", "key": Wild.MISSION}])


# ───────────────────────── Lo que se manda ─────────────────────────

## Criaturas a la vista de `p`, para su estado: [id, x, z, giro, vida, estado, objetivo].
## Las lejanas sólo van en los turnos lejanos.
func creatures_for(p: Object, far_turn: bool) -> Array:
	var me := _at(p)
	var out := []
	for c in _creatures:
		var cr: Creature = c
		if not cr.alive:
			continue
		var d := cr.pos.distance_to(me)
		if d > VIEW_R or (d > NEAR_R and not far_turn):
			continue
		var tgt := 0
		if not cr.target.is_empty():
			var t: Object = _player(cr.target)
			tgt = int(t.num) if t != null else 0
		out.append([cr.id, snappedf(cr.pos.x, 0.01), snappedf(cr.pos.y, 0.01), snappedf(cr.yaw, 0.01), int(ceil(cr.hp)), Wild.STATES.find(cr.state), tgt])
	return out


## Un suceso (golpe, muerte…) para quien esté lo bastante cerca de verlo.
func _event(at: Vector2, msg: Dictionary) -> void:
	for p in _players:
		if _at(p).distance_to(at) <= VIEW_R:
			_srv.send_to(p, msg)


func stats() -> Dictionary:
	var alive := 0
	for c in _creatures:
		if (c as Creature).alive:
			alive += 1
	return {"creatures": _creatures.size(), "alive": alive}
