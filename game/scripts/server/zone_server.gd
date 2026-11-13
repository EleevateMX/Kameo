extends Node
## Servidor de zonas: la plaza de Mérida y el primer tramo del mundo abierto, el Camino a Motul.
##
## Es OTRO proceso, distinto del servidor de mazmorras (game_server.gd), que no se toca:
##   godot --headless --path game -- --zone [--port=9081]
##
## Qué hace:
##   · Sólo entra quien trae un ticket de zona firmado por la API (de un solo uso).
##   · Varias zonas en este mismo proceso (zones.gd). El ticket dice por cuál se entra; después se
##     pasa de una a otra por sus pasos (`travel`) sin cambiar de conexión: el servidor comprueba
##     que el jugador está junto al paso y decide dónde llega. Cada zona tiene sus propios vecinos.
##   · El movimiento lo decide el servidor: aplica cada entrada del cliente una vez, con la misma
##     función que el cliente usa para predecir (zone_def.gd, camino_def.gd). Nadie puede moverse
##     más rápido ni atravesar muros diciendo dónde está.
##   · Interés por proximidad: cada jugador recibe sólo a los aluxes cercanos de su zona (con un
##     tope), los cercanos más a menudo que los lejanos. El aspecto viaja una vez, al entrar a la vista.
##   · Capacidad configurable (ALUX_ZONE_CAPACITY), para el proceso entero.
##   · En las zonas abiertas (zone_wild.gd): criaturas, combate mínimo, descubrimientos y una
##     misión. Las recompensas se piden a la API (`/internal/rpg/grant`); aquí no se guarda nada:
##     la posición, la vida y el avance de la misión viven en memoria.

const Zone := preload("res://scripts/shared/zone_def.gd")
const Zones := preload("res://scripts/shared/zones.gd")
const WildDef := preload("res://scripts/shared/wild_def.gd")
const ZoneWild := preload("res://scripts/server/zone_wild.gd")
const Ticket := preload("res://scripts/shared/ticket.gd")
const Look := preload("res://scripts/shared/look_def.gd")

const PROTOCOL := 1
const HELLO_TIMEOUT := 8.0
const IDLE_TIMEOUT := 20.0
const MAX_MSGS_PER_SEC := 70
const MAX_MSG_BYTES := 4096
const INPUT_QUEUE_MAX := 8
const MAX_CONNS := 400
const VIS_EVERY := 4             # cada cuántos pasos se recalcula quién ve a quién (5 veces por segundo)
const MEMO_KEEP := 1800.0        # segundos que se recuerda la sesión de quien se desconectó (misión, lugares)
const GRANT_TRIES := 3           # intentos de pedir una recompensa a la API antes de darla por perdida
const GRANT_RETRY := 4.0         # segundos entre intentos


class Conn:
	var id := 0
	var ws: WebSocketPeer
	var since := 0.0
	var last_rx := 0.0
	var msgs := 0
	var msgs_window := 0.0
	var closing := false
	var pid := ""


class P:
	var id := ""
	var num := 0                 # número corto con el que viaja en los estados
	var name := "Alux"
	var color := "#2ec4a6"
	var hat := 0
	var look: Array = []
	var s: Array = [0.0, 0.0, 0.0, 0.0]   # x, y, z, vy
	var yaw := 0.0
	var queue: Array = []        # entradas pendientes: [seq, mx, mz, salto, yaw]
	var ack := 0
	var credit := 1.0            # entradas que puede aplicar: una por paso, con un pequeño margen
	var conn_id := 0
	var sees := {}               # num -> P que este jugador está recibiendo
	var look_asked := -100.0
	var zone := "merida"
	var epoch := 0               # sube con cada viaje o reaparición: las entradas de antes se descartan
	# Mundo abierto (zone_wild.gd). Las estadísticas salen del ticket (`rpg`), nunca del cliente
	var max_hp := 100.0
	var dmg := 1.0               # multiplicador del ataque básico
	var hp := 100.0
	var down := false
	var down_until := 0.0
	var invuln_until := 0.0
	var hurt_at := -100.0
	var atk_ready := 0
	var memo := {}               # lo que se recuerda entre conexiones: lugares descubiertos y misión


var _tcp := TCPServer.new()
var _conns := {}                 # id -> Conn
var _players := {}               # pid -> P
var _used_jti := {}              # jti -> exp
var _next_conn := 1
var _next_num := 1
var _time := 0.0
var _tick := 0
var _acc := 0.0
var _secret := ""
var _api_url := ""
var _service_key := ""
var _capacity := Zone.DEFAULT_CAPACITY
var _dev := false
# Medidas (ventana de 5 s): lo que cuesta cada paso y lo que se envía
var _stat_t := 0.0
var _stat_ticks := 0
var _stat_usec := 0
var _stat_usec_max := 0
var _stat_bytes := 0
var _stat_msgs := 0
var _last := {"players": 0, "tick_avg_ms": 0.0, "tick_max_ms": 0.0, "bytes_out_s": 0.0, "msgs_out_s": 0.0}
var _wild := {}                  # zona -> ZoneWild (sólo las zonas abiertas)
var _memo := {}                  # pid -> {found, quest, seen}: sobrevive a la desconexión, no al reinicio
var _grants: Array = []          # recompensas por pedir a la API: {grants, tries, at, cb}
var _grants_flying := 0


func _ready() -> void:
	var port := int(_env("ALUX_ZONE_PORT", "9081"))
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--port="):
			port = int(a.trim_prefix("--port="))
	_dev = _env("ALUX_DEV", "") == "1"
	_secret = _env("ALUX_TICKET_SECRET", "")
	if _secret.is_empty():
		if _dev:
			_secret = "dev-ticket-secret-no-usar-en-produccion"
		else:
			push_error("Falta ALUX_TICKET_SECRET. Define el secreto o usa ALUX_DEV=1 en desarrollo.")
			get_tree().quit(1)
			return
	_api_url = _env("ALUX_API_URL", "").trim_suffix("/")
	_service_key = _env("ALUX_SERVICE_KEY", "")
	if _service_key.is_empty() and _dev:
		_service_key = "dev-service-key-no-usar-en-produccion"
	_capacity = maxi(1, int(_env("ALUX_ZONE_CAPACITY", str(Zone.DEFAULT_CAPACITY))))
	var err := _tcp.listen(port, _env("ALUX_BIND", "*"))
	if err != OK:
		push_error("No se pudo abrir el puerto %d (error %d)" % [port, err])
		get_tree().quit(1)
		return
	# Cada arranque firma sus claves de recompensa con su propia marca: tras un reinicio, las
	# criaturas vuelven a numerarse desde cero y sin ella chocarían con claves ya pagadas.
	var boot := "%x" % int(Time.get_unix_time_from_system())
	var respawn := maxf(1.0, float(_env("ALUX_WILD_RESPAWN", str(WildDef.RESPAWN))))
	var harm := clampf(float(_env("ALUX_WILD_DAMAGE", "1")), 0.0, 10.0)
	for z in Zones.WILD:
		_wild[z] = ZoneWild.new(self, boot, respawn, harm)
	print("[zona] escuchando en ws://0.0.0.0:%d · capacidad %d · zonas: %s" % [port, _capacity, ", ".join(Zones.IDS)])


func _env(key: String, fallback: String) -> String:
	var v := OS.get_environment(key)
	return v if not v.is_empty() else fallback


func _physics_process(delta: float) -> void:
	_time += delta
	_accept()
	_poll_conns(delta)
	_acc += delta
	var steps := 0
	while _acc >= Zone.DT and steps < 4:
		_acc -= Zone.DT
		steps += 1
		var t0 := Time.get_ticks_usec()
		_step()
		var used := Time.get_ticks_usec() - t0
		_stat_ticks += 1
		_stat_usec += used
		_stat_usec_max = maxi(_stat_usec_max, used)
	if steps == 4:
		_acc = 0.0   # el proceso se quedó atrás: no intenta recuperar el tiempo perdido
	_stat_t += delta
	if _stat_t >= 5.0:
		_last = {
			"players": _players.size(),
			"tick_avg_ms": snappedf(float(_stat_usec) / 1000.0 / float(maxi(_stat_ticks, 1)), 0.001),
			"tick_max_ms": snappedf(float(_stat_usec_max) / 1000.0, 0.001),
			"bytes_out_s": snappedf(float(_stat_bytes) / _stat_t, 1.0),
			"msgs_out_s": snappedf(float(_stat_msgs) / _stat_t, 0.1),
		}
		if _players.size() > 0:
			print("[zona] %d aluxes · paso %.3f ms de media (máx. %.3f) · %.1f KB/s de salida" % [
				_players.size(), _last.tick_avg_ms, _last.tick_max_ms, float(_last.bytes_out_s) / 1024.0])
		_stat_t = 0.0
		_stat_ticks = 0
		_stat_usec = 0
		_stat_usec_max = 0
		_stat_bytes = 0
		_stat_msgs = 0
		var now := Time.get_unix_time_from_system()
		for jti in _used_jti.keys():
			if float(_used_jti[jti]) < now:
				_used_jti.erase(jti)
		for pid in _memo.keys():
			if not _players.has(pid) and _time - float(_memo[pid].seen) > MEMO_KEEP:
				_memo.erase(pid)
	_pump_grants()


# ───────────────────────── Conexiones ─────────────────────────

func _accept() -> void:
	while _tcp.is_connection_available():
		var stream := _tcp.take_connection()
		if _conns.size() >= MAX_CONNS:
			stream.disconnect_from_host()
			continue
		var c := Conn.new()
		c.id = _next_conn
		_next_conn += 1
		c.ws = WebSocketPeer.new()
		c.ws.inbound_buffer_size = 32768
		c.ws.outbound_buffer_size = 262144
		c.ws.max_queued_packets = 256
		c.since = _time
		c.last_rx = _time
		if c.ws.accept_stream(stream) != OK:
			continue
		_conns[c.id] = c


func _poll_conns(delta: float) -> void:
	for id in _conns.keys():
		var c: Conn = _conns[id]
		c.ws.poll()
		var st := c.ws.get_ready_state()
		if st == WebSocketPeer.STATE_CLOSED:
			_drop(c)
			continue
		if st != WebSocketPeer.STATE_OPEN:
			if _time - c.since > HELLO_TIMEOUT * 2.0:
				_drop(c)
			continue
		if c.pid.is_empty() and _time - c.since > HELLO_TIMEOUT:
			_kick(c, "hello_timeout", "No se recibió el ticket a tiempo.")
			continue
		if not c.pid.is_empty() and _time - c.last_rx > IDLE_TIMEOUT:
			c.ws.close(4001, "idle")
			_drop(c)
			continue
		c.msgs_window += delta
		if c.msgs_window >= 1.0:
			c.msgs_window = 0.0
			c.msgs = 0
		while c.ws.get_available_packet_count() > 0 and not c.closing:
			var pkt := c.ws.get_packet()
			c.last_rx = _time
			c.msgs += 1
			if c.msgs > MAX_MSGS_PER_SEC:
				_kick(c, "rate_limit", "Demasiados mensajes.")
				break
			if pkt.size() > MAX_MSG_BYTES:
				_kick(c, "too_big", "Mensaje demasiado grande.")
				break
			var json := JSON.new()
			if json.parse(pkt.get_string_from_utf8()) != OK or typeof(json.data) != TYPE_DICTIONARY:
				_kick(c, "bad_message", "Mensaje inválido.")
				break
			_handle(c, json.data)


func _send(c: Conn, msg: Dictionary) -> void:
	if c.ws.get_ready_state() == WebSocketPeer.STATE_OPEN:
		var text := JSON.stringify(msg)
		_stat_bytes += text.length()
		_stat_msgs += 1
		c.ws.send_text(text)


func _kick(c: Conn, code: String, text: String) -> void:
	if c.closing:
		return
	_send(c, {"t": "error", "code": code, "msg": text})
	c.closing = true
	c.ws.close(4000, code)


func _drop(c: Conn) -> void:
	_conns.erase(c.id)
	if c.pid.is_empty():
		return
	var p: P = _players.get(c.pid)
	if p == null or p.conn_id != c.id:
		return   # ya entró por otra conexión
	_players.erase(p.id)
	p.memo.seen = _time
	_unsee(p)
	if _wild.has(p.zone):
		(_wild[p.zone] as ZoneWild).leave(p)


## Quien lo estaba viendo deja de verlo.
func _unsee(p: P) -> void:
	for other in _players.values():
		if (other as P).sees.has(p.num):
			(other as P).sees.erase(p.num)
			_send_to(other, {"t": "leave", "i": p.num})


func _send_to(p: P, msg: Dictionary) -> void:
	var c: Conn = _conns.get(p.conn_id)
	if c != null and not c.closing:
		_send(c, msg)


## (para zone_wild.gd)
func send_to(p: Object, msg: Dictionary) -> void:
	_send_to(p as P, msg)


func player(pid: String) -> Object:
	return _players.get(pid)


static func _num(v: Variant) -> float:
	return float(v) if (typeof(v) == TYPE_FLOAT or typeof(v) == TYPE_INT) and is_finite(float(v)) else 0.0


# ───────────────────────── Mensajes ─────────────────────────

func _handle(c: Conn, msg: Dictionary) -> void:
	var t := str(msg.get("t", ""))
	if c.pid.is_empty():
		if t == "hello":
			_hello(c, msg)
		else:
			_kick(c, "hello_first", "Primero el ticket.")
		return
	var p: P = _players.get(c.pid)
	if p == null:
		return
	match t:
		"in":
			# Una entrada por paso de simulación. El servidor no acepta posiciones: sólo hacia
			# dónde quiere ir el jugador, y lo mueve él.
			var seq := int(_num(msg.get("s")))
			if seq <= p.ack or (not p.queue.is_empty() and seq <= int(p.queue[-1][0])):
				return
			# Una entrada mandada antes de un viaje o de reaparecer no vale en el sitio nuevo
			if msg.has("e") and int(_num(msg.get("e"))) != p.epoch:
				return
			if p.queue.size() >= INPUT_QUEUE_MAX:
				p.queue.pop_front()   # el cliente va más rápido que el tiempo real: se descarta
			p.queue.append([seq, clampf(_num(msg.get("x")), -1.0, 1.0), clampf(_num(msg.get("z")), -1.0, 1.0),
				_num(msg.get("j")) != 0.0, wrapf(_num(msg.get("r")), -PI, PI)])
		"ping":
			_send(c, {"t": "pong", "c": _num(msg.get("c"))})
		"look":
			# Cambió su aspecto en el personalizador: se relee de la API, no se le cree al cliente
			if _time - p.look_asked >= 2.0:
				p.look_asked = _time
				_refresh_look(p.id)
		"travel":
			_travel(p, str(msg.get("to", "")))
		"stats":
			if _dev:
				_send(c, {"t": "stats", "players": _players.size(), "cap": _capacity, "tick_avg_ms": _last.tick_avg_ms,
					"tick_max_ms": _last.tick_max_ms, "bytes_out_s": _last.bytes_out_s, "msgs_out_s": _last.msgs_out_s,
					"mem_mb": snappedf(float(OS.get_static_memory_usage()) / 1048576.0, 0.1)})
		_:
			if _wild.has(p.zone):
				(_wild[p.zone] as ZoneWild).handle(p, t, msg)


func _hello(c: Conn, msg: Dictionary) -> void:
	var claims := Ticket.verify(str(msg.get("ticket", "")), _secret, "alux-zone")
	var zone := str(claims.get("zone", ""))
	if claims.is_empty() or not Zones.has(zone):
		_kick(c, "bad_ticket", "Ticket inválido o caducado.")
		return
	var jti := str(claims.get("jti", ""))
	var pid := str(claims.get("sub", ""))
	if jti.is_empty() or pid.is_empty() or _used_jti.has(jti):
		_kick(c, "bad_ticket", "Ticket ya usado.")
		return
	_used_jti[jti] = _num(claims.get("exp"))
	var p: P = _players.get(pid)
	var fresh := false
	if p == null:
		if _players.size() >= _capacity:
			_kick(c, "zone_full", "La plaza está llena. Inténtalo en un momento.")
			return
		p = P.new()
		p.id = pid
		p.num = _next_num
		_next_num += 1
		# El ticket dice por qué zona se entra; el sitio lo decide el servidor
		p.zone = zone
		var entry := Zones.entry(zone, _count(zone))
		p.s = [(entry[0] as Vector2).x, 0.0, (entry[0] as Vector2).y, 0.0]
		p.yaw = float(entry[1])
		if not _memo.has(pid):
			_memo[pid] = {"found": {}, "quest": {"st": "none", "n": 0}, "seen": _time}
		p.memo = _memo[pid]
		_players[pid] = p
		fresh = true
	elif p.conn_id != 0 and _conns.has(p.conn_id):
		# Sigue donde estaba (zona y sitio), entre por donde entre el ticket nuevo
		_kick(_conns[p.conn_id], "replaced", "Abriste la plaza en otra ventana.")
	# El perfil sale siempre del ticket (firmado por la API), nunca del cliente
	p.name = str(claims.get("name", "Alux")).substr(0, 24)
	var col: Variant = claims.get("color")
	if typeof(col) == TYPE_STRING and col.length() == 7 and col.begins_with("#") and col.substr(1).is_valid_hex_number():
		p.color = col
	p.hat = clampi(int(_num(claims.get("hat"))), 0, Look.HATS.size() - 1)
	p.look = Look.clean(claims.get("look"))
	_apply_rpg(p, claims.get("rpg"))
	p.conn_id = c.id
	p.queue.clear()
	p.ack = 0
	p.sees.clear()
	c.pid = pid
	if fresh and _wild.has(p.zone):
		(_wild[p.zone] as ZoneWild).join(p)
	var welcome := {"t": "welcome", "v": PROTOCOL, "id": pid, "i": p.num, "zone": p.zone, "e": p.epoch, "cap": _capacity, "tick": Zone.TICK,
		"me": _profile(p), "pos": [p.s[0], p.s[1], p.s[2]], "yaw": p.yaw}
	if _wild.has(p.zone):
		welcome.merge((_wild[p.zone] as ZoneWild).info(p))
	_send(c, welcome)
	# Quien ya lo veía recibe su perfil otra vez (pudo cambiar de aspecto antes de volver)
	for other in _players.values():
		if (other as P).sees.has(p.num):
			_send_to(other, _enter_msg(p))


func _profile(p: P) -> Dictionary:
	return {"n": p.name, "c": p.color, "h": p.hat, "l": p.look}


## Estadísticas del jugador para el mundo abierto, tal como las calculó la API (docs/RPG.md):
## `rpg: { lv, hp, dmg: { chispa, garras, all }, done? }`. Sin ese campo valen 100 de vida y ×1.
## `done` (opcional, fuera del contrato actual): claves de descubrimientos y misiones que la API
## ya pagó, para no celebrarlos ni ofrecerlos otra vez.
func _apply_rpg(p: P, rpg: Variant) -> void:
	if not (rpg is Dictionary):
		return
	var r: Dictionary = rpg
	if r.has("hp"):
		var full := p.hp >= p.max_hp
		p.max_hp = clampf(_num(r.get("hp")), 1.0, 10000.0)
		p.hp = p.max_hp if full else minf(p.hp, p.max_hp)
	var d: Variant = r.get("dmg")
	if d is Dictionary:
		var all := _num((d as Dictionary).get("all", 1.0))
		var chispa := _num((d as Dictionary).get("chispa", 1.0))
		p.dmg = clampf((all if all > 0.0 else 1.0) * (chispa if chispa > 0.0 else 1.0), 0.1, 20.0)
	var done: Variant = r.get("done")
	if done is Array:
		for key in (done as Array).slice(0, 128):
			if typeof(key) != TYPE_STRING:
				continue
			if key == WildDef.MISSION:
				p.memo.quest.st = "done"
			else:
				p.memo.found[key] = true


func _count(zone: String) -> int:
	var n := 0
	for p in _players.values():
		if (p as P).zone == zone:
			n += 1
	return n


# ───────────────────────── Viajes entre zonas ─────────────────────────

## Tomar un paso hacia otra zona. El cliente sólo dice adónde quiere ir: el servidor comprueba que
## está junto a un paso que lleva allí y decide dónde llega. La conexión es la misma.
func _travel(p: P, to: String) -> void:
	var gate := {}
	for g in Zones.GATES.get(p.zone, []):
		if str(g.to) == to and Vector2(float(p.s[0]), float(p.s[2])).distance_to(g.at) <= float(g.r) + 0.5:
			gate = g
			break
	if gate.is_empty() or p.down:
		_send_to(p, {"t": "travel_no", "to": to, "why": "down" if p.down else "far"})
		return
	_unsee(p)
	if _wild.has(p.zone):
		(_wild[p.zone] as ZoneWild).leave(p)
	p.zone = to
	if _wild.has(to):
		(_wild[to] as ZoneWild).join(p)
		_refresh_look(p.id)   # y de paso sus estadísticas, por si compró algo en la plaza
	# Repartidos alrededor del punto de llegada, para no aparecer unos encima de otros
	var a := float(p.num) * 2.4
	warp(p, (gate.pos as Vector2) + Vector2(sin(a), cos(a)) * 1.1, float(gate.yaw))


## Coloca a un jugador en otro sitio (viaje o reaparición) y se lo dice. Sube `epoch`: las
## entradas que el cliente mandó antes de enterarse ya no se aplican.
func warp(p: Object, at: Vector2, yaw: float) -> void:
	var pl := p as P
	pl.s = [at.x, 0.0, at.y, 0.0]
	pl.yaw = yaw
	pl.queue.clear()
	pl.sees.clear()   # el cliente olvida a sus vecinos al recibir «zone»: se le vuelven a anunciar
	pl.epoch += 1
	var msg := {"t": "zone", "zone": pl.zone, "e": pl.epoch, "pos": [at.x, 0.0, at.y], "yaw": yaw}
	if _wild.has(pl.zone):
		msg.merge((_wild[pl.zone] as ZoneWild).info(pl))
	_send_to(pl, msg)


func _enter_msg(p: P) -> Dictionary:
	return {"t": "enter", "i": p.num, "n": p.name, "c": p.color, "h": p.hat, "l": p.look,
		"x": snappedf(float(p.s[0]), 0.01), "y": snappedf(float(p.s[1]), 0.01), "z": snappedf(float(p.s[2]), 0.01), "r": snappedf(p.yaw, 0.01)}


# ───────────────────────── Simulación y reparto ─────────────────────────

func _step() -> void:
	_tick += 1
	# 1) Movimiento: una entrada por jugador y paso. Cada paso da derecho a una entrada, con un
	#    margen de tres para absorber ráfagas de red: mandar entradas más deprisa no hace correr
	#    más, porque a la larga no se aplican más entradas que pasos han transcurrido.
	var by_zone := {}   # zona -> [P]
	for p in _players.values():
		var pl: P = p
		if not by_zone.has(pl.zone):
			by_zone[pl.zone] = []
		(by_zone[pl.zone] as Array).append(pl)
		pl.credit = minf(pl.credit + 1.0, 3.0)
		var applied := 0
		while applied < 2 and pl.credit >= 1.0 and not pl.queue.is_empty():
			applied += 1
			pl.credit -= 1.0
			var inp: Array = pl.queue.pop_front()
			if pl.down:
				pl.s = Zones.step(pl.zone, pl.s, 0.0, 0.0, false)   # caído no se mueve
			else:
				pl.s = Zones.step(pl.zone, pl.s, float(inp[1]), float(inp[2]), bool(inp[3]))
				pl.yaw = float(inp[4])
			pl.ack = int(inp[0])
		if applied == 0 and float(pl.s[1]) > 0.0:
			pl.s = Zones.step(pl.zone, pl.s, 0.0, 0.0, false)   # sin entradas, al menos termina de caer
	# 1b) Mundo abierto: criaturas y combate, sólo donde hay alguien
	for z in _wild:
		if by_zone.has(z):
			(_wild[z] as ZoneWild).step(by_zone[z], Zone.DT)
	# 2) Quién ve a quién
	if _tick % VIS_EVERY == 0:
		_update_visibility(by_zone)
	# 3) Estados: a cada jugador, el suyo y los de sus vecinos (los lejanos, menos a menudo)
	if _tick % Zone.NEAR_EVERY != 0:
		return
	var far_turn := _tick % Zone.FAR_EVERY == 0 or (_tick + 1) % Zone.FAR_EVERY == 0
	for p in _players.values():
		var me: P = p
		var c: Conn = _conns.get(me.conn_id)
		if c == null or c.closing:
			continue
		var wild: ZoneWild = _wild.get(me.zone)
		var list := []
		for other in me.sees.values():
			var o: P = other
			var dx := float(o.s[0]) - float(me.s[0])
			var dz := float(o.s[2]) - float(me.s[2])
			if not far_turn and dx * dx + dz * dz > Zone.NEAR_R * Zone.NEAR_R:
				continue
			var e := [o.num, snappedf(float(o.s[0]), 0.01), snappedf(float(o.s[1]), 0.01), snappedf(float(o.s[2]), 0.01), snappedf(o.yaw, 0.01)]
			if wild != null and o.down:
				e.append(1)   # caído
			list.append(e)
		var state := {"t": "s", "k": _tick, "a": me.ack,
			"m": [snappedf(float(me.s[0]), 0.001), snappedf(float(me.s[1]), 0.001), snappedf(float(me.s[2]), 0.001), snappedf(float(me.s[3]), 0.001)],
			"p": list, "n": (by_zone[me.zone] as Array).size()}
		if wild != null:
			state["h"] = int(ceil(me.hp))        # mi vida (0 = caído)
			state["c"] = wild.creatures_for(me, far_turn)
		_send(c, state)


## Cada jugador ve a los aluxes que tiene cerca: entran a ENTER_R, salen a LEAVE_R y, si hay más
## de MAX_NEIGHBORS, se queda con los más cercanos. Con decenas de jugadores basta comparar todos
## con todos unas veces por segundo; una rejilla hará falta cuando sean centenares.
func _update_visibility(by_zone: Dictionary) -> void:
	for p in _players.values():
		var me: P = p
		if me.conn_id == 0 or not _conns.has(me.conn_id):
			continue
		var near := []   # [distancia², P]
		for other in by_zone[me.zone]:
			var o: P = other
			if o == me:
				continue
			var dx := float(o.s[0]) - float(me.s[0])
			var dz := float(o.s[2]) - float(me.s[2])
			var d2 := dx * dx + dz * dz
			var limit := Zone.LEAVE_R if me.sees.has(o.num) else Zone.ENTER_R
			if d2 <= limit * limit:
				near.append([d2, o])
		if near.size() > Zone.MAX_NEIGHBORS:
			near.sort_custom(func(a: Array, b: Array) -> bool: return float(a[0]) < float(b[0]))
			near.resize(Zone.MAX_NEIGHBORS)
		var now := {}
		for pair in near:
			var o: P = pair[1]
			now[o.num] = o
			if not me.sees.has(o.num):
				_send_to(me, _enter_msg(o))
		for num in me.sees.keys():
			if not now.has(num):
				_send_to(me, {"t": "leave", "i": num})
		me.sees = now


# ───────────────────────── API ─────────────────────────

## Relee de la API el aspecto de un jugador y lo reparte a quien lo esté viendo.
func _refresh_look(pid: String) -> void:
	if _api_url.is_empty():
		return
	var req := HTTPRequest.new()
	req.timeout = 8.0
	add_child(req)
	req.request_completed.connect(func(result: int, code: int, _h: PackedStringArray, data: PackedByteArray) -> void:
		req.queue_free()
		var p: P = _players.get(pid)
		var parsed: Variant = JSON.parse_string(data.get_string_from_utf8())
		if result != HTTPRequest.RESULT_SUCCESS or code != 200 or p == null or not (parsed is Dictionary):
			return
		var res: Dictionary = parsed
		p.name = str(res.get("name", p.name)).substr(0, 24)
		var col: Variant = res.get("color")
		if typeof(col) == TYPE_STRING and col.length() == 7 and col.begins_with("#") and col.substr(1).is_valid_hex_number():
			p.color = col
		p.hat = clampi(int(_num(res.get("hat"))), 0, Look.HATS.size() - 1)
		p.look = Look.clean(res.get("look"))
		_apply_rpg(p, res.get("rpg"))   # (opcional) si la API lo devuelve, una compra vale sin reconectar
		_send_to(p, {"t": "me", "me": _profile(p)})
		for other in _players.values():
			if (other as P).sees.has(p.num):
				_send_to(other, _enter_msg(p))
	)
	var headers := ["content-type: application/json", "x-service-key: " + _service_key]
	if req.request(_api_url + "/internal/zone/character", headers, HTTPClient.METHOD_POST, JSON.stringify({"player": pid})) != OK:
		req.queue_free()


# ───────────────────────── Recompensas (API) ─────────────────────────

## Pide recompensas a la API: `grants` = [{playerId, kind, key}] (docs/RPG.md). Las cantidades,
## los topes y la unicidad son cosa de la API; aquí sólo se reenvía a cada jugador lo que le
## tocó. Si la API no contesta se reintenta (las claves son únicas: repetir no paga dos veces) y,
## si sigue sin contestar, el juego continúa sin esa recompensa. `on_done` recibe la lista de
## resultados, o null si no hubo manera.
func grant(grants: Array, on_done: Callable = Callable()) -> void:
	if grants.is_empty():
		return
	_grants.append({"grants": grants, "tries": 0, "at": _time, "cb": on_done})


func _pump_grants() -> void:
	if _grants.is_empty() or _grants_flying >= 4:
		return
	for job in _grants:
		if float(job.at) <= _time:
			_grants.erase(job)
			_send_grant(job)
			return


func _send_grant(job: Dictionary) -> void:
	job.tries = int(job.tries) + 1
	if _api_url.is_empty():
		_grant_done(job, null)
		return
	var req := HTTPRequest.new()
	req.timeout = 6.0
	add_child(req)
	_grants_flying += 1
	req.request_completed.connect(func(result: int, code: int, _h: PackedStringArray, data: PackedByteArray) -> void:
		req.queue_free()
		_grants_flying -= 1
		var parsed: Variant = JSON.parse_string(data.get_string_from_utf8()) if result == HTTPRequest.RESULT_SUCCESS and code == 200 else null
		if parsed is Dictionary and (parsed as Dictionary).get("results") is Array:
			_grant_done(job, (parsed as Dictionary).results)
		elif int(job.tries) < GRANT_TRIES and (result != HTTPRequest.RESULT_SUCCESS or code >= 500 or code == 429):
			job.at = _time + GRANT_RETRY
			_grants.append(job)
		else:
			_grant_done(job, null)
	)
	var headers := ["content-type: application/json", "x-service-key: " + _service_key]
	if req.request(_api_url + "/internal/rpg/grant", headers, HTTPClient.METHOD_POST, JSON.stringify({"grants": job.grants})) != OK:
		req.queue_free()
		_grants_flying -= 1
		_grant_done(job, null)


func _grant_done(job: Dictionary, results: Variant) -> void:
	var cb: Callable = job.cb
	if cb.is_valid():
		cb.call(results)
	var grants: Array = job.grants
	for i in grants.size():
		var g: Dictionary = grants[i]
		var p: P = _players.get(str(g.playerId))
		if p == null:
			continue
		var msg := {"t": "reward", "kind": g.kind, "key": g.key, "applied": false, "reason": "offline"}
		if results is Array:
			# La API contesta en el mismo orden; si no, se busca por jugador y tipo
			var r: Variant = (results as Array)[i] if i < (results as Array).size() else null
			if not (r is Dictionary) or str((r as Dictionary).get("playerId", "")) != p.id:
				r = null
				for cand in results:
					if cand is Dictionary and str(cand.get("playerId", "")) == p.id and str(cand.get("kind", "")) == str(g.kind):
						r = cand
						break
			if r is Dictionary:
				var d: Dictionary = r
				msg = {"t": "reward", "kind": g.kind, "key": g.key, "applied": bool(d.get("applied", false)), "reason": str(d.get("reason", "")),
					"xp": int(_num(d.get("xp"))), "seeds": int(_num(d.get("seeds"))), "level": int(_num(d.get("level"))), "up": bool(d.get("leveledUp", false)),
					"txp": int(_num(d.get("totalXp"))), "tseeds": int(_num(d.get("totalSeeds")))}
		_send_to(p, msg)
