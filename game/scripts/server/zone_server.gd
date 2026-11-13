extends Node
## Servidor de zonas sociales (prototipo): la plaza de Mérida.
##
## Es OTRO proceso, distinto del servidor de mazmorras (game_server.gd), que no se toca:
##   godot --headless --path game -- --zone [--port=9081]
##
## Qué hace:
##   · Sólo entra quien trae un ticket de zona firmado por la API (de un solo uso).
##   · El movimiento lo decide el servidor: aplica cada entrada del cliente una vez, con la misma
##     función que el cliente usa para predecir (zone_def.gd). Nadie puede moverse más rápido ni
##     atravesar muros diciendo dónde está.
##   · Interés por proximidad: cada jugador recibe sólo a los aluxes cercanos (con un tope), los
##     cercanos más a menudo que los lejanos. El aspecto de cada uno viaja una vez, al entrar a la vista.
##   · Capacidad configurable (ALUX_ZONE_CAPACITY).
## No hay combate, ni criaturas, ni nada que guardar: la posición vive en memoria.

const Zone := preload("res://scripts/shared/zone_def.gd")
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
	print("[zona] «%s» escuchando en ws://0.0.0.0:%d · capacidad %d" % [Zone.ID, port, _capacity])


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
	# Quien lo estaba viendo deja de verlo
	for other in _players.values():
		if (other as P).sees.has(p.num):
			(other as P).sees.erase(p.num)
			_send_to(other, {"t": "leave", "i": p.num})


func _send_to(p: P, msg: Dictionary) -> void:
	var c: Conn = _conns.get(p.conn_id)
	if c != null and not c.closing:
		_send(c, msg)


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
		"stats":
			if _dev:
				_send(c, {"t": "stats", "players": _players.size(), "cap": _capacity, "tick_avg_ms": _last.tick_avg_ms,
					"tick_max_ms": _last.tick_max_ms, "bytes_out_s": _last.bytes_out_s, "msgs_out_s": _last.msgs_out_s,
					"mem_mb": snappedf(float(OS.get_static_memory_usage()) / 1048576.0, 0.1)})


func _hello(c: Conn, msg: Dictionary) -> void:
	var claims := Ticket.verify(str(msg.get("ticket", "")), _secret, "alux-zone")
	if claims.is_empty() or str(claims.get("zone", "")) != Zone.ID:
		_kick(c, "bad_ticket", "Ticket inválido o caducado.")
		return
	var jti := str(claims.get("jti", ""))
	var pid := str(claims.get("sub", ""))
	if jti.is_empty() or pid.is_empty() or _used_jti.has(jti):
		_kick(c, "bad_ticket", "Ticket ya usado.")
		return
	_used_jti[jti] = _num(claims.get("exp"))
	var p: P = _players.get(pid)
	if p == null:
		if _players.size() >= _capacity:
			_kick(c, "zone_full", "La plaza está llena. Inténtalo en un momento.")
			return
		p = P.new()
		p.id = pid
		p.num = _next_num
		_next_num += 1
		var at := Zone.spawn(_players.size())
		p.s = [at.x, 0.0, at.y, 0.0]
		p.yaw = PI   # mirando al árbol
		_players[pid] = p
	elif p.conn_id != 0 and _conns.has(p.conn_id):
		_kick(_conns[p.conn_id], "replaced", "Abriste la plaza en otra ventana.")
	# El perfil sale siempre del ticket (firmado por la API), nunca del cliente
	p.name = str(claims.get("name", "Alux")).substr(0, 24)
	var col: Variant = claims.get("color")
	if typeof(col) == TYPE_STRING and col.length() == 7 and col.begins_with("#") and col.substr(1).is_valid_hex_number():
		p.color = col
	p.hat = clampi(int(_num(claims.get("hat"))), 0, Look.HATS.size() - 1)
	p.look = Look.clean(claims.get("look"))
	p.conn_id = c.id
	p.queue.clear()
	p.ack = 0
	p.sees.clear()
	c.pid = pid
	_send(c, {"t": "welcome", "v": PROTOCOL, "id": pid, "i": p.num, "zone": Zone.ID, "cap": _capacity, "tick": Zone.TICK,
		"me": _profile(p), "pos": [p.s[0], p.s[1], p.s[2]], "yaw": p.yaw})
	# Quien ya lo veía recibe su perfil otra vez (pudo cambiar de aspecto antes de volver)
	for other in _players.values():
		if (other as P).sees.has(p.num):
			_send_to(other, _enter_msg(p))


func _profile(p: P) -> Dictionary:
	return {"n": p.name, "c": p.color, "h": p.hat, "l": p.look}


func _enter_msg(p: P) -> Dictionary:
	return {"t": "enter", "i": p.num, "n": p.name, "c": p.color, "h": p.hat, "l": p.look,
		"x": snappedf(float(p.s[0]), 0.01), "y": snappedf(float(p.s[1]), 0.01), "z": snappedf(float(p.s[2]), 0.01), "r": snappedf(p.yaw, 0.01)}


# ───────────────────────── Simulación y reparto ─────────────────────────

func _step() -> void:
	_tick += 1
	# 1) Movimiento: una entrada por jugador y paso. Cada paso da derecho a una entrada, con un
	#    margen de tres para absorber ráfagas de red: mandar entradas más deprisa no hace correr
	#    más, porque a la larga no se aplican más entradas que pasos han transcurrido.
	for p in _players.values():
		var pl: P = p
		pl.credit = minf(pl.credit + 1.0, 3.0)
		var applied := 0
		while applied < 2 and pl.credit >= 1.0 and not pl.queue.is_empty():
			applied += 1
			pl.credit -= 1.0
			var inp: Array = pl.queue.pop_front()
			pl.s = Zone.step(pl.s, float(inp[1]), float(inp[2]), bool(inp[3]))
			pl.yaw = float(inp[4])
			pl.ack = int(inp[0])
		if applied == 0 and float(pl.s[1]) > 0.0:
			pl.s = Zone.step(pl.s, 0.0, 0.0, false)   # sin entradas, al menos termina de caer
	# 2) Quién ve a quién
	if _tick % VIS_EVERY == 0:
		_update_visibility()
	# 3) Estados: a cada jugador, el suyo y los de sus vecinos (los lejanos, menos a menudo)
	if _tick % Zone.NEAR_EVERY != 0:
		return
	var far_turn := _tick % Zone.FAR_EVERY == 0 or (_tick + 1) % Zone.FAR_EVERY == 0
	for p in _players.values():
		var me: P = p
		var c: Conn = _conns.get(me.conn_id)
		if c == null or c.closing:
			continue
		var list := []
		for other in me.sees.values():
			var o: P = other
			var dx := float(o.s[0]) - float(me.s[0])
			var dz := float(o.s[2]) - float(me.s[2])
			if not far_turn and dx * dx + dz * dz > Zone.NEAR_R * Zone.NEAR_R:
				continue
			list.append([o.num, snappedf(float(o.s[0]), 0.01), snappedf(float(o.s[1]), 0.01), snappedf(float(o.s[2]), 0.01), snappedf(o.yaw, 0.01)])
		_send(c, {"t": "s", "k": _tick, "a": me.ack,
			"m": [snappedf(float(me.s[0]), 0.001), snappedf(float(me.s[1]), 0.001), snappedf(float(me.s[2]), 0.001), snappedf(float(me.s[3]), 0.001)],
			"p": list, "n": _players.size()})


## Cada jugador ve a los aluxes que tiene cerca: entran a ENTER_R, salen a LEAVE_R y, si hay más
## de MAX_NEIGHBORS, se queda con los más cercanos. Con decenas de jugadores basta comparar todos
## con todos unas veces por segundo; una rejilla hará falta cuando sean centenares.
func _update_visibility() -> void:
	var all: Array = _players.values()
	for p in all:
		var me: P = p
		if me.conn_id == 0 or not _conns.has(me.conn_id):
			continue
		var near := []   # [distancia², P]
		for other in all:
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
		_send_to(p, {"t": "me", "me": _profile(p)})
		for other in _players.values():
			if (other as P).sees.has(p.num):
				_send_to(other, _enter_msg(p))
	)
	var headers := ["content-type: application/json", "x-service-key: " + _service_key]
	if req.request(_api_url + "/internal/zone/character", headers, HTTPClient.METHOD_POST, JSON.stringify({"player": pid})) != OK:
		req.queue_free()
