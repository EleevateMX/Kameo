extends Node3D
## Cliente de ALUX: conexión, entrada, predicción local y presentación.
## El cliente nunca decide resultados: manda intenciones y dibuja lo que
## el servidor confirma, prediciendo sólo el movimiento de su propio alux.

const Sim := preload("res://scripts/shared/sim.gd")
const World := preload("res://scripts/shared/world_def.gd")
const Avatar := preload("res://scripts/client/avatar.gd")
const WorldBuilder := preload("res://scripts/client/world_builder.gd")
const Hud := preload("res://scripts/client/hud.gd")

const PROTOCOL := 1
const INTERP_DELAY := 0.13
const MAX_PENDING := 90
const SERVER_SILENCE := 6.0   # segundos sin noticias del servidor antes de reconectar
const FATAL_CODES := {
	"room_full": "La sala ya tiene 4 aluxes.",
	"room_not_found": "Esa sala no existe o ya cerró.",
	"replaced": "Abriste el juego en otra ventana.",
	"version": "Hay una versión nueva del juego. Recarga la página.",
	"server_full": "El servidor está lleno. Intenta más tarde.",
	"rate_limited": "Demasiados intentos. Espera un momento y recarga.",
}

enum Net { TICKET, CONNECTING, HELLO, PLAYING, WAIT, FATAL }

var _net := Net.TICKET
var _ws: WebSocketPeer
var _ws_url := ""
var _retry_in := 0.0
var _retries := 0
var _ticket_wait := 0.0
var _is_web := false
var _cli_ticket := ""

var _my_id := ""
var _my_slot := -1
var _room := ""
var _unlocked: Array = ["alux"]
var _roster: Array = []
var _gate_open := false
var _plates_mask := 0
var _need := 1

var _pred := Sim.PlayerState.new()
var _prev_pos := Vector3.ZERO
var _prev_yaw := 0.0
var _visual_offset := Vector3.ZERO
var _pending: Array = []
var _seq := 0
var _want_form := ""

var _avatars := {}      # slot -> Avatar
var _remote := {}       # slot -> {buf: Array, form, on}
var _builder: WorldBuilder
var _hud: Hud
var _cam: Camera3D
var _cam_yaw := PI
var _cam_pitch := 0.42
var _cam_dist := 7.0
var _cam_target := Vector3.ZERO
var _gate_anim := 0.0
var _debug_in := 0.0
var _debug_on := false
var _rejoins := 0
var _silence := 0.0
var _time := 0.0


func _ready() -> void:
	_is_web = OS.has_feature("web")
	_setup_input()
	_builder = WorldBuilder.new()
	_builder.build(self)
	_cam = Camera3D.new()
	_cam.fov = 62.0
	_cam.far = 400.0
	add_child(_cam)
	_cam.make_current()
	_hud = Hud.new()
	add_child(_hud)
	_hud.form_requested.connect(func(f: String) -> void: _want_form = f)
	_hud.set_overlay("Preparando el Claro de los Aluxes…")
	_cam_target = Vector3(0, 1.2, 0)
	_update_camera(0.0, true)

	for a in OS.get_cmdline_user_args():
		if a.begins_with("--ws="):
			_ws_url = a.trim_prefix("--ws=")
		elif a.begins_with("--ticket="):
			_cli_ticket = a.trim_prefix("--ticket=")
	if _is_web:
		# (los booleanos de JavaScript llegan como número, por eso se piden como 1/0)
		_debug_on = int(_js("window.ALUX_DEBUG === true ? 1 : 0")) == 1
		if str(_js("(window.ALUX && window.ALUX.quality) || 'high'")) == "low":
			_low_quality()


## Calidad baja (?q=low): sin sombras ni resplandor y a menor resolución interna.
func _low_quality() -> void:
	var vp := get_viewport()
	vp.msaa_3d = Viewport.MSAA_DISABLED
	vp.scaling_3d_scale = 0.6
	_builder.sun.shadow_enabled = false
	_builder.env.glow_enabled = false
	_builder.fireflies.emitting = false
	_builder.fireflies.visible = false


func _setup_input() -> void:
	var keys := {
		"fwd": [KEY_W, KEY_UP], "back": [KEY_S, KEY_DOWN], "left": [KEY_A, KEY_LEFT], "right": [KEY_D, KEY_RIGHT],
		"jump": [KEY_SPACE], "form1": [KEY_1], "form2": [KEY_2], "cam_l": [KEY_Q], "cam_r": [KEY_E],
	}
	for action in keys:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
		for k in keys[action]:
			var ev := InputEventKey.new()
			ev.physical_keycode = k
			InputMap.action_add_event(action, ev)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED and _net == Net.PLAYING:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	elif event is InputEventMouseMotion:
		if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED or (event.button_mask & MOUSE_BUTTON_MASK_RIGHT) != 0:
			_cam_yaw -= event.relative.x * 0.0042
			_cam_pitch = clampf(_cam_pitch + event.relative.y * 0.0035, -0.15, 1.25)
	elif event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_cam_dist = maxf(3.5, _cam_dist - 0.6)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_cam_dist = minf(13.0, _cam_dist + 0.6)
	elif event.is_action_pressed("ui_cancel"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif event.is_action_pressed("form1"):
		_want_form = "alux"
	elif event.is_action_pressed("form2"):
		_want_form = "balam"


# ───────────────────────── Red ─────────────────────────

func _js(code: String) -> Variant:
	return JavaScriptBridge.eval(code, true)


func _fatal(text: String) -> void:
	_net = Net.FATAL
	if _ws:
		_ws.close()
	_ws = null
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_hud.set_overlay(text + "\n\nVuelve al portal para intentarlo de nuevo.")


func _retry(reason: String) -> void:
	_ws = null
	_retries += 1
	if _retries > 40 or (not _is_web and _cli_ticket.is_empty()):
		_fatal("No se pudo conectar con el servidor de juego.")
		return
	_retry_in = minf(8.0, 0.8 * pow(1.6, _retries - 1))
	_net = Net.WAIT
	_hud.set_overlay("%s\nReconectando…" % reason)


func _poll_net(delta: float) -> void:
	match _net:
		Net.TICKET:
			var ticket := ""
			if _is_web:
				var err: Variant = _js("window.ALUX ? (window.ALUX.error || '') : 'no_config'")
				if typeof(err) == TYPE_STRING and not err.is_empty():
					if FATAL_CODES.has(err):
						_fatal(FATAL_CODES[err])
						return
					if err == "no_session":
						_fatal("Tu sesión terminó. Inicia sesión de nuevo en el portal.")
						return
					if err == "no_config":
						_fatal("Esta página no trae la configuración del juego.")
						return
					# error de red al pedir el ticket: se reintenta
					_ticket_wait += delta
					if _ticket_wait > 2.0:
						_ticket_wait = 0.0
						_js("window.aluxRefreshTicket && window.aluxRefreshTicket()")
					return
				var t: Variant = _js("window.ALUX && window.ALUX.ticket ? window.ALUX.ticket : ''")
				if typeof(t) != TYPE_STRING or t.is_empty():
					return
				ticket = t
				_ws_url = str(_js("window.ALUX.wsUrl"))
				_room = str(_js("window.ALUX.room"))
				_js("window.ALUX.ticket = ''")  # los tickets son de un solo uso
			else:
				if _cli_ticket.is_empty() or _ws_url.is_empty():
					_fatal("Abre el juego desde el portal (o usa --ws= y --ticket=).")
					return
				ticket = _cli_ticket
				_cli_ticket = ""
			_ws = WebSocketPeer.new()
			_ws.inbound_buffer_size = 262144
			_ws.max_queued_packets = 512
			if _ws.connect_to_url(_ws_url) != OK:
				_retry("No se pudo abrir la conexión.")
				return
			_ws.set_meta("ticket", ticket)
			_net = Net.CONNECTING
			_ticket_wait = 0.0
			_silence = 0.0
		Net.CONNECTING, Net.HELLO, Net.PLAYING:
			_ws.poll()
			var st := _ws.get_ready_state()
			if st == WebSocketPeer.STATE_OPEN:
				if _net == Net.CONNECTING:
					_ws.send_text(JSON.stringify({"t": "hello", "v": PROTOCOL, "ticket": _ws.get_meta("ticket")}))
					_net = Net.HELLO
				_silence += minf(delta, 0.5)
				if _ws.get_available_packet_count() > 0:
					_silence = 0.0
				elif _silence > SERVER_SILENCE and _net != Net.CONNECTING:
					# La conexión sigue "abierta" pero no llega nada: la red se cortó
					_silence = 0.0
					_ws.close()
					_retry("Se perdió la conexión.")
					return
				while _ws != null and _ws.get_available_packet_count() > 0:
					var json := JSON.new()
					if json.parse(_ws.get_packet().get_string_from_utf8()) == OK and typeof(json.data) == TYPE_DICTIONARY:
						_on_message(json.data)
			elif st == WebSocketPeer.STATE_CLOSED:
				if _net != Net.FATAL:
					_retry("Se perdió la conexión.")
			elif _net == Net.CONNECTING:
				_ticket_wait += minf(delta, 0.5)  # un cuadro lento no cuenta como espera larga
				if _ticket_wait > 10.0:
					_ws.close()
					_retry("El servidor no responde.")
		Net.WAIT:
			_retry_in -= delta
			if _retry_in <= 0.0:
				_net = Net.TICKET
				if _is_web:
					_js("window.aluxRefreshTicket && window.aluxRefreshTicket()")


func _on_message(m: Dictionary) -> void:
	match m.get("t"):
		"welcome":
			_my_id = m.id
			_my_slot = int(m.slot)
			_room = m.room
			_unlocked = m.unlocked
			_pred.from_array(m.me)
			_prev_pos = _pred.pos
			_prev_yaw = _pred.yaw
			_visual_offset = Vector3.ZERO
			_pending.clear()
			_seq = 0
			_retries = 0
			_apply_world(m.w, true)
			_set_roster(m.players)
			_hud.set_room(_room)
			_hud.set_overlay("")
			if m.rejoin:
				_rejoins += 1
				_hud.banner("Conexión recuperada", Color(0.6, 1.0, 0.85), 2.5)
			else:
				_hud.banner("Bienvenido al Claro de los Aluxes", Color(0.6, 1.0, 0.85))
			_net = Net.PLAYING
		"roster":
			_set_roster(m.players)
		"snap":
			_on_snapshot(m)
		"event":
			_on_event(m)
		"error":
			var code := str(m.get("code", ""))
			if FATAL_CODES.has(code):
				_fatal(FATAL_CODES[code])
			# bad_ticket / ticket_used: se pide un ticket nuevo al reconectar


func _set_roster(players: Array) -> void:
	_roster = players
	var seen := {}
	for p in players:
		var slot := int(p.slot)
		seen[slot] = true
		var av: Avatar = _avatars.get(slot)
		if av == null:
			av = Avatar.new()
			add_child(av)
			_avatars[slot] = av
			av.setup(str(p.name), str(p.color), int(p.hat))
			if slot != _my_slot:
				_remote[slot] = {"buf": [], "id": p.id}
		elif av.player_name != str(p.name) or av.hat != int(p.hat) or av.color.to_html(false) != str(p.color).trim_prefix("#").to_lower():
			av.setup(str(p.name), str(p.color), int(p.hat))
		av.set_online(bool(p.on))
	for slot in _avatars.keys():
		if not seen.has(slot):
			_avatars[slot].queue_free()
			_avatars.erase(slot)
			_remote.erase(slot)
	_hud.set_roster(players, _my_id)


func _apply_world(w: Array, instant := false) -> void:
	var open := int(w[0]) != 0
	_plates_mask = int(w[1])
	_need = int(w[2])
	for i in World.PLATES.size():
		_builder.set_plate(i, (_plates_mask & (1 << i)) != 0)
	if open and not _gate_open:
		_gate_open = true
		if instant:
			_gate_anim = 1.0
	elif not open:
		_gate_open = false
		_gate_anim = 0.0
	var pressed := 0
	for i in World.PLATES.size():
		if (_plates_mask & (1 << i)) != 0:
			pressed += 1
	if _gate_open:
		_hud.set_objective("El santuario está abierto · Explora el claro")
	else:
		_hud.set_objective("Pisen %d altar%s al mismo tiempo para abrir el santuario  (%d/%d)" % [
			_need, "" if _need == 1 else "es", pressed, _need])


func _on_snapshot(m: Dictionary) -> void:
	_apply_world(m.w)
	for p in m.p:
		var slot := int(p[0])
		var state: Array = p.slice(3)
		if slot == _my_slot:
			_reconcile(state, int(p[1]))
		elif _remote.has(slot):
			var r: Dictionary = _remote[slot]
			var buf: Array = r.buf
			buf.append({"t": _time, "pos": Vector3(state[0], state[1], state[2]), "yaw": float(state[4]),
				"form": Sim.FORM_IDS[clampi(int(state[5]), 0, Sim.FORM_IDS.size() - 1)], "flags": int(state[7])})
			while buf.size() > 12:
				buf.pop_front()


func _reconcile(state: Array, ack: int) -> void:
	var old := _pred.pos
	_pred.from_array(state)
	while not _pending.is_empty() and int(_pending[0].s) <= ack:
		_pending.pop_front()
	for inp in _pending:
		Sim.step(_pred, inp, _unlocked, _gate_open)
	var correction := _pred.pos - old
	_prev_pos += correction
	if correction.length() < 2.5:
		_visual_offset -= correction  # la corrección se absorbe suavemente
	else:
		_visual_offset = Vector3.ZERO
		_prev_pos = _pred.pos


func _on_event(m: Dictionary) -> void:
	match m.get("e"):
		"gate_open":
			_hud.banner("¡El santuario se abre!", Color(0.5, 1.0, 0.85), 5.0)
		"reward":
			if not bool(m.get("saved", false)):
				_hud.banner("Sello del Claro (no se pudo guardar el progreso)", Color(1, 0.6, 0.5), 5.0)
			elif bool(m.get("new", false)):
				_hud.banner("Obtuviste el Sello del Claro", Color(1.0, 0.82, 0.3), 6.0)
			else:
				_hud.banner("Ya tenías el Sello del Claro", Color(1, 1, 1, 0.9), 4.0)


# ───────────────────────── Simulación local ─────────────────────────

func _physics_process(_delta: float) -> void:
	if _net != Net.PLAYING or _ws == null:
		return
	var fwd := Vector2(sin(_cam_yaw), cos(_cam_yaw))
	var right := Vector2(-fwd.y, fwd.x)
	var move := fwd * (Input.get_action_strength("fwd") - Input.get_action_strength("back")) \
		+ right * (Input.get_action_strength("right") - Input.get_action_strength("left"))
	if move.length() > 1.0:
		move = move.normalized()
	_seq += 1
	var inp := {
		"t": "in", "s": _seq,
		"mx": snappedf(move.x, 0.001), "mz": snappedf(move.y, 0.001),
		"j": 1 if Input.is_action_pressed("jump") else 0,
		"f": _want_form,
	}
	_want_form = ""
	_prev_pos = _pred.pos
	_prev_yaw = _pred.yaw
	Sim.step(_pred, inp, _unlocked, _gate_open)
	_pending.append(inp)
	if _pending.size() > MAX_PENDING:
		_pending.pop_front()
	_ws.send_text(JSON.stringify(inp))


# ───────────────────────── Presentación ─────────────────────────

func _process(delta: float) -> void:
	_time += delta
	_poll_net(delta)

	if Input.is_action_pressed("cam_l"):
		_cam_yaw += 1.9 * delta
	if Input.is_action_pressed("cam_r"):
		_cam_yaw -= 1.9 * delta

	# Mi alux: interpolado entre ticks de simulación
	var me: Avatar = _avatars.get(_my_slot)
	if me != null and _net == Net.PLAYING:
		var f := Engine.get_physics_interpolation_fraction()
		_visual_offset = _visual_offset.lerp(Vector3.ZERO, minf(1.0, delta * 12.0))
		me.global_position = _prev_pos.lerp(_pred.pos, f) + _visual_offset
		me.rotation.y = lerp_angle(me.rotation.y, _pred.yaw, minf(1.0, delta * 14.0))
		me.set_form(_pred.form)
		me.animate(delta, _pred.grounded, _pred.swim)
		_cam_target = _cam_target.lerp(me.global_position + Vector3(0, 1.25, 0), minf(1.0, delta * 14.0))
		_hud.set_forms(_unlocked, _pred.form, _pred.form_cd)

	# Los demás: interpolados un poco en el pasado entre estados del servidor
	var render_t := _time - INTERP_DELAY
	for slot in _remote:
		var av: Avatar = _avatars.get(slot)
		var buf: Array = _remote[slot].buf
		if av == null or buf.is_empty():
			continue
		var a: Dictionary = buf[0]
		var b: Dictionary = buf[buf.size() - 1]
		for i in range(buf.size() - 1, 0, -1):
			if buf[i - 1].t <= render_t:
				a = buf[i - 1]
				b = buf[i]
				break
		var span: float = b.t - a.t
		var k := clampf((render_t - a.t) / span, 0.0, 1.0) if span > 0.0001 else 1.0
		av.global_position = (a.pos as Vector3).lerp(b.pos, k)
		av.rotation.y = lerp_angle(a.yaw, b.yaw, k)
		av.set_form(b.form)
		av.animate(delta, (int(b.flags) & 1) != 0, (int(b.flags) & 2) != 0)

	# Puerta del santuario y glifo
	if _gate_open and _gate_anim < 1.0:
		_gate_anim = minf(1.0, _gate_anim + delta * 0.8)
	if _builder.gate_bars:
		var base_y := World.terrain_h(World.SANCTUARY.x - 6.0, World.SANCTUARY.y)
		_builder.gate_bars.position.y = base_y - _gate_anim * 3.6
		_builder.gate_bars.visible = _gate_anim < 1.0
		_builder.gate_light.light_energy = 1.8 * (1.0 - _gate_anim)
	if _builder.glyph:
		_builder.glyph.rotation.y += delta * 1.2
		_builder.glyph.position.y += sin(_time * 2.0) * delta * 0.25

	_update_camera(delta, false)
	_debug_export(delta)


func _update_camera(_delta: float, _snap: bool) -> void:
	var fwd := Vector3(sin(_cam_yaw) * cos(_cam_pitch), -sin(_cam_pitch), cos(_cam_yaw) * cos(_cam_pitch))
	var pos := _cam_target - fwd * _cam_dist
	var ground := World.terrain_h(pos.x, pos.z) + 0.5
	if pos.y < ground:
		pos.y = ground
	_cam.global_position = pos
	_cam.look_at(_cam_target, Vector3.UP)


## Estado visible para las pruebas automáticas (sólo con ?debug=1 en la URL).
func _debug_export(delta: float) -> void:
	if not _is_web or not _debug_on:
		return
	_debug_in -= delta
	if _debug_in > 0.0:
		return
	_debug_in = 0.2
	var players := []
	for p in _roster:
		var av: Avatar = _avatars.get(int(p.slot))
		if av == null:
			continue
		players.append({
			"id": p.id, "slot": p.slot, "name": p.name, "on": p.on, "form": av.form,
			"x": snappedf(av.global_position.x, 0.01), "y": snappedf(av.global_position.y, 0.01), "z": snappedf(av.global_position.z, 0.01),
		})
	var state := {
		"net": Net.keys()[_net], "room": _room, "me": _my_id, "slot": _my_slot, "players": players,
		"gate": _gate_open, "plates": _plates_mask, "need": _need, "form": _pred.form,
		"fps": Engine.get_frames_per_second(), "frames": Engine.get_process_frames(), "pending": _pending.size(), "rejoins": _rejoins,
	}
	_js("window.__aluxState = %s" % JSON.stringify(state))
