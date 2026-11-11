extends Node
## Servidor dedicado de ALUX (Godot headless).
##
## Reglas de oro:
##  - El cliente sólo envía intenciones (dirección, salto, forma deseada).
##  - La identidad viene de un ticket firmado por la API, nunca del cliente.
##  - Posiciones, acertijos y recompensas se deciden aquí.
##
## Configuración por variables de entorno:
##   ALUX_PORT            puerto WebSocket (9080)
##   ALUX_TICKET_SECRET   secreto compartido con la API (obligatorio)
##   ALUX_API_URL         URL interna de la API (opcional; sin ella no se guarda progreso)
##   ALUX_SERVICE_KEY     clave de servicio para llamar a la API
##   ALUX_SERVER_ID       identificador de esta instancia
##   ALUX_DEV=1           permite arrancar con un secreto de desarrollo

const Sim := preload("res://scripts/shared/sim.gd")
const World := preload("res://scripts/shared/world_def.gd")
const Ticket := preload("res://scripts/shared/ticket.gd")
const Defs := preload("res://scripts/shared/combat_def.gd")
const Combat := preload("res://scripts/server/combat.gd")

const PROTOCOL := 2
const MAX_PLAYERS := 4
const MAX_ROOMS := 64
const MAX_CONNS := 300
const SNAP_EVERY := 2            # 30 Hz / 2 = 15 estados por segundo
const HELLO_TIMEOUT := 20.0         # margen para clientes lentos (el juego aún está cargando)
const RECONNECT_GRACE := 120.0   # segundos que se guarda el lugar de un jugador caído
const EMPTY_ROOM_TTL := 30.0
const IDLE_TIMEOUT := 15.0          # sin mensajes del cliente: conexión muerta
const MAX_MSG_BYTES := 4096
const MAX_MSGS_PER_SEC := 90
const INPUT_QUEUE_MAX := 12
const INPUT_BUDGET_MAX := 8
const REWARD_SEAL := "sello_del_claro"
const FAIL_HOLD := 6.0              # tras una derrota, los altares tardan esto en volver a responder
const RESTART_HOLD := 3.0           # lo mismo al empezar otra ronda


class Conn:
	var id := 0
	var ws: WebSocketPeer
	var since := 0.0
	var last_rx := 0.0
	var room := ""
	var pid := ""
	var msgs := 0
	var msgs_window := 0.0
	var closing := false


class Player:
	var id := ""
	var slot := 0
	var name := ""
	var color := "#2ec4a6"
	var hat := 0
	var unlocked: Array = ["alux"]
	var state := Sim.PlayerState.new()
	var conn_id := 0
	var last_seq := 0
	var queued_seq := 0
	var budget := 0
	var queue: Array = []
	var gone_at := -1.0
	# Combate (sólo el servidor conoce y modifica estos valores)
	var hp := Defs.MAX_HP
	var respawn_t := 0.0
	var invuln_t := 0.0
	var hurt_at := -99.0


class Room:
	var code := ""
	var created := 0
	var players := {}            # pid -> Player
	var gate_open := false
	var plates: Array = [false, false, false, false]
	var need := 1
	var tick := 0
	var empty_since := -1.0
	var combat := Combat.new()
	var lock_t := 0.0            # mientras sea > 0 los altares no responden (derrota o nueva ronda)
	var again := {}              # pid -> true: quiere jugar otra ronda tras la victoria


var _tcp := TCPServer.new()
var _conns := {}                 # id -> Conn
var _rooms := {}                 # code -> Room
var _used_jti := {}              # jti -> exp
var _next_conn := 1
var _time := 0.0
var _secret := ""
var _api_url := ""
var _service_key := ""
var _server_id := "local-1"
var _heartbeat_in := 1.0
var _jti_gc_in := 30.0


func _ready() -> void:
	var port := int(_env("ALUX_PORT", "9080"))
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--port="):
			port = int(a.trim_prefix("--port="))
	_secret = _env("ALUX_TICKET_SECRET", "")
	if _secret.is_empty():
		if _env("ALUX_DEV", "") == "1":
			_secret = "dev-ticket-secret-no-usar-en-produccion"
			print("[aviso] Usando secreto de desarrollo para los tickets.")
		else:
			push_error("Falta ALUX_TICKET_SECRET. Define el secreto o usa ALUX_DEV=1 en desarrollo.")
			get_tree().quit(1)
			return
	_api_url = _env("ALUX_API_URL", "").trim_suffix("/")
	_service_key = _env("ALUX_SERVICE_KEY", "")
	if _service_key.is_empty() and _env("ALUX_DEV", "") == "1":
		_service_key = "dev-service-key-no-usar-en-produccion"
	_server_id = _env("ALUX_SERVER_ID", "local-1")

	var err := _tcp.listen(port, _env("ALUX_BIND", "*"))
	if err != OK:
		push_error("No se pudo abrir el puerto %d (error %d)" % [port, err])
		get_tree().quit(1)
		return
	print("[alux] Servidor de juego escuchando en ws://0.0.0.0:%d · API: %s" % [
		port, _api_url if not _api_url.is_empty() else "(sin API: el progreso no se guarda)"])


func _env(key: String, fallback: String) -> String:
	var v := OS.get_environment(key)
	return v if not v.is_empty() else fallback


func _physics_process(delta: float) -> void:
	_time += delta
	_accept()
	_poll_conns(delta)
	for code in _rooms.keys():
		_tick_room(_rooms[code])
	_cleanup()
	_heartbeat_in -= delta
	if _heartbeat_in <= 0.0:
		_heartbeat_in = 3.0
		_send_heartbeat()
	_jti_gc_in -= delta
	if _jti_gc_in <= 0.0:
		_jti_gc_in = 30.0
		var now := Time.get_unix_time_from_system()
		for j in _used_jti.keys():
			if _used_jti[j] < now:
				_used_jti.erase(j)


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
		c.ws.inbound_buffer_size = 65536
		c.ws.outbound_buffer_size = 262144
		c.ws.max_queued_packets = 256
		c.since = _time
		if c.ws.accept_stream(stream) != OK:
			continue
		_conns[c.id] = c


func _poll_conns(delta: float) -> void:
	for id in _conns.keys():
		var c: Conn = _conns[id]
		c.ws.poll()
		var st := c.ws.get_ready_state()
		if st == WebSocketPeer.STATE_CLOSED:
			_drop_conn(c)
			continue
		if st != WebSocketPeer.STATE_OPEN:
			if _time - c.since > HELLO_TIMEOUT * 2.0:
				_drop_conn(c)
			continue
		if c.pid.is_empty() and _time - c.since > HELLO_TIMEOUT:
			_kick(c, "hello_timeout", "No se recibió el ticket a tiempo.")
			continue
		if not c.pid.is_empty() and _time - c.last_rx > IDLE_TIMEOUT:
			# La red del jugador se cortó sin cerrar la conexión: se libera y podrá reconectarse
			print("[alux] Conexión %d sin actividad" % c.id)
			c.ws.close(4001, "idle")
			_drop_conn(c)
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
		c.ws.send_text(JSON.stringify(msg))


func _kick(c: Conn, code: String, text: String) -> void:
	if c.closing:
		return
	print("[alux] Conexión %d rechazada: %s" % [c.id, code])
	_send(c, {"t": "error", "code": code, "msg": text})
	c.closing = true
	c.ws.close(4000, code)


func _drop_conn(c: Conn) -> void:
	_conns.erase(c.id)
	if c.pid.is_empty() or not _rooms.has(c.room):
		return
	var room: Room = _rooms[c.room]
	var p: Player = room.players.get(c.pid)
	if p != null and p.conn_id == c.id:
		p.conn_id = 0
		p.gone_at = _time
		p.queue.clear()
		print("[alux] %s se desconectó de %s (se guarda su lugar %ds)" % [p.name, room.code, int(RECONNECT_GRACE)])
		_broadcast_roster(room)


# ───────────────────────── Mensajes ─────────────────────────

static func _num(v: Variant) -> float:
	if typeof(v) == TYPE_FLOAT or typeof(v) == TYPE_INT:
		var f := float(v)
		if is_finite(f):
			return f
	return 0.0


func _handle(c: Conn, msg: Dictionary) -> void:
	var t: Variant = msg.get("t")
	if typeof(t) != TYPE_STRING:
		return
	if c.pid.is_empty():
		if t == "hello":
			_handle_hello(c, msg)
		return  # nada más está permitido antes de autenticarse
	var room: Room = _rooms.get(c.room)
	if room == null:
		return
	var p: Player = room.players.get(c.pid)
	if p == null or p.conn_id != c.id:
		return
	match t:
		"in":
			var seq := int(_num(msg.get("s")))
			if seq <= p.queued_seq or seq > p.queued_seq + 600:
				return
			var f: Variant = msg.get("f")
			var form := ""
			if typeof(f) == TYPE_STRING and Sim.FORMS.has(f):
				form = f
			var inp := {
				"s": seq,
				"mx": clampf(_num(msg.get("mx")), -1.0, 1.0),
				"mz": clampf(_num(msg.get("mz")), -1.0, 1.0),
				"j": 1 if _num(msg.get("j")) != 0.0 else 0,
				"f": form,
				"a": clampi(int(_num(msg.get("a"))), 0, 7),
				"r": wrapf(_num(msg.get("r")), -PI, PI),
			}
			p.queued_seq = seq
			if p.queue.size() >= INPUT_QUEUE_MAX:
				p.queue.pop_front()  # el cliente va más rápido que el tiempo real: se descarta
			p.queue.append(inp)
		"ping":
			_send(c, {"t": "pong", "c": _num(msg.get("c"))})
		"again":
			# Voto para jugar otra ronda. Sólo cuenta con la emboscada superada; la sala
			# se reinicia cuando votan todos los conectados (ver _tick_room).
			if room.combat.encounter == 2:
				if _num(msg.get("v", 1.0)) != 0.0:
					room.again[p.id] = true
				else:
					room.again.erase(p.id)
		_:
			pass  # cualquier otra cosa (p. ej. "dame la recompensa") se ignora


func _handle_hello(c: Conn, msg: Dictionary) -> void:
	if int(_num(msg.get("v"))) != PROTOCOL:
		_kick(c, "version", "Tu versión del juego no coincide con el servidor. Recarga la página.")
		return
	var token: Variant = msg.get("ticket")
	if typeof(token) != TYPE_STRING:
		_kick(c, "bad_ticket", "Ticket inválido.")
		return
	var claims := Ticket.verify(token, _secret)
	if claims.is_empty():
		_kick(c, "bad_ticket", "Ticket inválido o vencido.")
		return
	var pid: Variant = claims.get("sub")
	var code: Variant = claims.get("room")
	var jti: Variant = claims.get("jti")
	if typeof(pid) != TYPE_STRING or typeof(code) != TYPE_STRING or typeof(jti) != TYPE_STRING \
			or pid.is_empty() or code.is_empty() or code.length() > 12 or jti.is_empty():
		_kick(c, "bad_ticket", "Ticket incompleto.")
		return
	if _used_jti.has(jti):
		_kick(c, "ticket_used", "Este ticket ya fue usado.")
		return
	_used_jti[jti] = float(claims.get("exp"))

	var room: Room = _rooms.get(code)
	if room == null:
		if _rooms.size() >= MAX_ROOMS:
			_kick(c, "server_full", "El servidor está lleno. Intenta más tarde.")
			return
		room = Room.new()
		room.code = code
		room.created = int(Time.get_unix_time_from_system())
		_rooms[code] = room
		print("[alux] Sala %s creada" % code)

	var p: Player = room.players.get(pid)
	var rejoin := p != null
	if p == null:
		if room.players.size() >= MAX_PLAYERS:
			_kick(c, "room_full", "La sala ya tiene 4 aluxes.")
			return
		p = Player.new()
		p.id = pid
		var used := []
		for o in room.players.values():
			used.append(o.slot)
		for s in MAX_PLAYERS:
			if not used.has(s):
				p.slot = s
				break
		p.state.pos = World.spawn_pos(p.slot)
		room.players[pid] = p
	elif p.conn_id != 0 and _conns.has(p.conn_id):
		_kick(_conns[p.conn_id], "replaced", "Abriste el juego en otra ventana.")

	# El perfil siempre sale del ticket (firmado por la API), no del cliente
	p.name = str(claims.get("name", "Alux")).substr(0, 24)
	var col: Variant = claims.get("color")
	if typeof(col) == TYPE_STRING and col.length() == 7 and col.begins_with("#") and col.substr(1).is_valid_hex_number():
		p.color = col
	p.hat = clampi(int(_num(claims.get("hat"))), 0, 3)
	p.unlocked = ["alux"]
	var forms: Variant = claims.get("forms")
	if typeof(forms) == TYPE_ARRAY:
		for f in forms:
			if typeof(f) == TYPE_STRING and Sim.FORMS.has(f) and not p.unlocked.has(f):
				p.unlocked.append(f)
	if not p.unlocked.has(p.state.form):
		p.state.form = "alux"
	p.conn_id = c.id
	c.last_rx = _time
	p.gone_at = -1.0
	p.queue.clear()
	p.queued_seq = 0
	p.last_seq = 0
	p.budget = 0
	c.pid = pid
	c.room = code
	room.empty_since = -1.0

	_send(c, {
		"t": "welcome", "v": PROTOCOL, "id": pid, "slot": p.slot, "room": code,
		"rejoin": rejoin, "unlocked": p.unlocked, "me": p.state.to_array(), "hp": int(ceil(p.hp)),
		"players": _roster(room), "w": _world_state(room), "e": room.combat.snapshot(), "tick_rate": Sim.TICK_RATE,
	})
	_broadcast_roster(room)
	print("[alux] %s %s en %s (%d/%d)" % [p.name, "volvió" if rejoin else "entró", code, room.players.size(), MAX_PLAYERS])


func _roster(room: Room) -> Array:
	var out := []
	for p in room.players.values():
		out.append({"id": p.id, "slot": p.slot, "name": p.name, "color": p.color, "hat": p.hat, "on": p.conn_id != 0})
	return out


func _broadcast(room: Room, msg: Dictionary) -> void:
	var text := JSON.stringify(msg)
	for p in room.players.values():
		if p.conn_id != 0 and _conns.has(p.conn_id):
			var c: Conn = _conns[p.conn_id]
			if c.ws.get_ready_state() == WebSocketPeer.STATE_OPEN:
				c.ws.send_text(text)


func _broadcast_roster(room: Room) -> void:
	_broadcast(room, {"t": "roster", "players": _roster(room)})


func _world_state(room: Room) -> Array:
	var mask := 0
	for i in room.plates.size():
		if room.plates[i]:
			mask |= 1 << i
	var votes := 0
	var connected := 0
	for p in room.players.values():
		if p.conn_id != 0:
			connected += 1
			if room.again.has(p.id):
				votes += 1
	## [santuarioAbierto, altares, altaresNecesarios, emboscada(0/1/2/3), enemigosRestantes, puntoDeReaparición,
	##  braseroListo, votosOtraRonda, conectados, segundosDeEsperaDeLosAltares]
	return [1 if room.gate_open else 0, mask, room.need, room.combat.encounter, room.combat.wave_alive(),
		room.combat.checkpoint, 1 if room.combat.brazier_cd <= 0.0 else 0, votes, connected, int(ceil(room.lock_t))]


# ───────────────────────── Simulación de sala ─────────────────────────

func _tick_room(room: Room) -> void:
	room.tick += 1
	var connected := 0
	var everyone: Array = room.players.values()
	for p in everyone:
		if p.conn_id == 0:
			continue
		connected += 1
		# Cada jugador avanza como mucho al ritmo del tiempo real
		p.budget = mini(p.budget + 1, INPUT_BUDGET_MAX)
		while p.budget > 0 and not p.queue.is_empty():
			var inp: Dictionary = p.queue.pop_front()
			var actions: Array = []
			Sim.step(p.state, inp, p.unlocked, room.gate_open, actions)
			p.last_seq = inp.s
			p.budget -= 1
			# La simulación sólo dice "intentó atacar"; el combate decide a quién alcanza
			for ev in actions:
				room.combat.player_action(p, ev, everyone)

	# Altares de presión: escalan con el número de aluxes conectados (1–4)
	room.need = clampi(connected, 1, World.PLATES.size())
	if room.lock_t > 0.0:
		room.lock_t = maxf(0.0, room.lock_t - Sim.DT)
		if room.lock_t <= 0.0 and room.combat.encounter == 3:
			room.combat.encounter = 0   # la derrota ya se mostró: se puede volver a intentar
	var pressed := 0
	for i in World.PLATES.size():
		var pp := World.plate_pos(i)
		var on := false
		for p in room.players.values():
			if p.conn_id == 0 or room.lock_t > 0.0 or p.state.dead:
				continue
			var s: Sim.PlayerState = p.state
			if absf(s.pos.y - pp.y) < 0.6 and Vector2(s.pos.x - pp.x, s.pos.z - pp.z).length() < World.PLATE_R:
				on = true
				break
		room.plates[i] = on
		if on:
			pressed += 1
	if not room.gate_open and connected > 0 and pressed >= room.need:
		room.gate_open = true
		_on_gate_open(room)

	# Combate: enemigos, proyectiles, vida, reaparición y emboscada
	match room.combat.tick(everyone, room.gate_open):
		Combat.CLEARED:
			_on_encounter_clear(room)
		Combat.FAILED:
			_on_encounter_failed(room)

	# Otra ronda: cuando todos los conectados la piden tras la victoria
	if room.combat.encounter == 2 and connected > 0 and not room.again.is_empty():
		var votes := 0
		for p in everyone:
			if p.conn_id != 0 and room.again.has(p.id):
				votes += 1
		if votes >= connected:
			_restart(room)

	if connected == 0:
		room.combat.events.clear()
	elif room.tick % SNAP_EVERY == 0:
		var ps := []
		for p in everyone:
			var a: Array = p.state.to_array()
			ps.append([p.slot, p.last_seq, 1 if p.conn_id != 0 else 0, int(ceil(p.hp))] + a)
		_broadcast(room, {
			"t": "snap", "k": room.tick, "w": _world_state(room), "p": ps,
			"e": room.combat.snapshot(), "ev": room.combat.events,
		})
		room.combat.events = []


func _on_gate_open(room: Room) -> void:
	var ids := []
	var names := []
	for p in room.players.values():
		if p.conn_id != 0:
			ids.append(p.id)
			names.append(p.name)
	print("[alux] Sala %s: santuario abierto por %s" % [room.code, ", ".join(names)])
	_broadcast(room, {"t": "event", "e": "gate_open", "by": names})
	# Al abrirse despiertan los guardianes corrompidos: el sello se gana al vencerlos
	room.combat.start_encounter(ids.size())


func _on_encounter_clear(room: Room) -> void:
	var ids := []
	for p in room.players.values():
		if p.conn_id != 0:
			ids.append(p.id)
	print("[alux] Sala %s: emboscada superada" % room.code)
	_grant_reward(room, REWARD_SEAL, ids)


## Todo el grupo cayó: el santuario se vuelve a sellar y hay que abrirlo otra vez.
func _on_encounter_failed(room: Room) -> void:
	print("[alux] Sala %s: emboscada fallida" % room.code)
	room.gate_open = false
	room.lock_t = FAIL_HOLD
	room.again.clear()
	_broadcast(room, {"t": "event", "e": "defeat"})


## Nueva ronda pedida por el grupo: sala como al principio y todos junto al brasero.
func _restart(room: Room) -> void:
	print("[alux] Sala %s: nueva ronda" % room.code)
	room.gate_open = false
	room.lock_t = RESTART_HOLD
	room.again.clear()
	room.combat.restart(room.players.values())
	_broadcast(room, {"t": "event", "e": "restart"})


func _cleanup() -> void:
	for code in _rooms.keys():
		var room: Room = _rooms[code]
		var any_on := false
		var changed := false
		for pid in room.players.keys():
			var p: Player = room.players[pid]
			if p.conn_id != 0:
				any_on = true
			elif _time - p.gone_at > RECONNECT_GRACE:
				room.players.erase(pid)
				changed = true
		if changed:
			_broadcast_roster(room)
		if any_on:
			room.empty_since = -1.0
		else:
			if room.empty_since < 0.0:
				room.empty_since = _time
			if room.players.is_empty() and _time - room.empty_since > EMPTY_ROOM_TTL:
				_rooms.erase(code)
				print("[alux] Sala %s cerrada" % code)


# ───────────────────────── Comunicación con la API ─────────────────────────

func _api_post(path: String, body: Dictionary, on_done: Callable = Callable(), attempt: int = 1) -> void:
	if _api_url.is_empty():
		if on_done.is_valid():
			on_done.call(false, {})
		return
	var req := HTTPRequest.new()
	req.timeout = 8.0
	add_child(req)
	req.request_completed.connect(func(result: int, code: int, _h: PackedStringArray, data: PackedByteArray) -> void:
		req.queue_free()
		var ok := result == HTTPRequest.RESULT_SUCCESS and code >= 200 and code < 300
		if not ok and on_done.is_valid() and attempt < 5 and (result != HTTPRequest.RESULT_SUCCESS or code >= 500):
			# Reintento seguro: la API aplica las recompensas de forma idempotente
			get_tree().create_timer(1.5 * attempt).timeout.connect(func() -> void:
				_api_post(path, body, on_done, attempt + 1))
			return
		if on_done.is_valid():
			var json := JSON.new()
			var parsed := {}
			if json.parse(data.get_string_from_utf8()) == OK and typeof(json.data) == TYPE_DICTIONARY:
				parsed = json.data
			on_done.call(ok, parsed)
	)
	var headers := ["content-type: application/json", "x-service-key: " + _service_key]
	if req.request(_api_url + path, headers, HTTPClient.METHOD_POST, JSON.stringify(body)) != OK:
		req.queue_free()
		if on_done.is_valid():
			on_done.call(false, {})


func _grant_reward(room: Room, reward: String, player_ids: Array) -> void:
	var code := room.code
	var body := {
		"server_id": _server_id, "room": code, "reward": reward, "players": player_ids,
		"idempotency_key": "%s:%d:%s" % [code, room.created, reward],
	}
	_api_post("/internal/game/rewards", body, func(ok: bool, res: Dictionary) -> void:
		if not _rooms.has(code):
			return
		var r: Room = _rooms[code]
		var granted: Array = res.get("granted", []) if ok else []
		for p in r.players.values():
			if p.conn_id != 0 and _conns.has(p.conn_id) and player_ids.has(p.id):
				_send(_conns[p.conn_id], {
					"t": "event", "e": "reward", "reward": reward,
					"saved": ok, "new": granted.has(p.id),
				})
	)


func _send_heartbeat() -> void:
	if _api_url.is_empty():
		return
	var rooms := []
	for room in _rooms.values():
		var players := []
		for p in room.players.values():
			players.append({"id": p.id, "on": p.conn_id != 0})
		rooms.append({"code": room.code, "players": players, "gate_open": room.gate_open})
	_api_post("/internal/game/heartbeat", {"server_id": _server_id, "rooms": rooms})
