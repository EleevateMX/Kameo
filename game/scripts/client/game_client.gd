extends Node3D
## Cliente de ALUX: conexión, entrada, predicción local y presentación.
## El cliente nunca decide resultados: manda intenciones y dibuja lo que
## el servidor confirma, prediciendo sólo el movimiento de su propio personaje.

const Sim := preload("res://scripts/shared/sim.gd")
const World := preload("res://scripts/shared/world_def.gd")
const Defs := preload("res://scripts/shared/combat_def.gd")
const Avatar := preload("res://scripts/client/avatar.gd")
const EnemyView := preload("res://scripts/client/enemy_view.gd")
const WorldBuilder := preload("res://scripts/client/world_builder.gd")
const Hud := preload("res://scripts/client/hud.gd")
const Fx := preload("res://scripts/client/fx.gd")

const PROTOCOL := 2
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
const JADE := Color(0.35, 1.0, 0.85)
const GOLD := Color(1.0, 0.82, 0.3)

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
var _encounter := 0
var _wave_left := 0

var _pred := Sim.PlayerState.new()
var _prev_pos := Vector3.ZERO
var _visual_offset := Vector3.ZERO
var _pending: Array = []
var _latest_me: Array = []
var _latest_ack := 0
var _seq := 0
var _want_form := ""
var _hp := Defs.MAX_HP
var _team_hp := {}
var _mouse_l := false
var _mouse_r := false

var _avatars := {}      # slot -> Avatar
var _remote := {}       # slot -> {buf: Array}
var _enemies := {}      # id -> EnemyView
var _bolts := {}        # id del servidor -> {node, pos, dir, speed, life}
var _local_bolts: Array = []   # chispas propias aún sin id del servidor
var _builder: WorldBuilder
var _hud: Hud
var _cam: Camera3D
var _cam_yaw := PI
var _cam_pitch := 0.42
var _cam_dist := 7.0
var _cam_target := Vector3.ZERO
var _shake := 0.0
var _gate_anim := 0.0
var _debug_in := 0.0
var _debug_on := false
var _rejoins := 0
var _silence := 0.0
var _time := 0.0
var _ping_in := 1.0
var _ping_ms := -1.0
var _snaps := 0
var _snap_rate := 0.0
var _perf_in := 0.0
var _perf_on := false
var _quality_low := false
var _seen_enemy_dmg := {}   # id de enemigo -> daño total visto (para pruebas)
var _seen_player_dmg := {}  # lugar -> daño total visto
var _quality_locked := false
var _slow_windows := 0
var _fps_frames := 0
var _fps_time := 0.0


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
	_update_camera()
	_prewarm()

	for a in OS.get_cmdline_user_args():
		if a.begins_with("--ws="):
			_ws_url = a.trim_prefix("--ws=")
		elif a.begins_with("--ticket="):
			_cli_ticket = a.trim_prefix("--ticket=")
	if _is_web:
		# (los booleanos de JavaScript llegan como número, por eso se piden como 1/0)
		_debug_on = int(_js("window.ALUX_DEBUG === true ? 1 : 0")) == 1
		var q := str(_js("(window.ALUX && window.ALUX.quality) || 'auto'"))
		if q == "low":
			_low_quality()
		elif q == "high":
			_quality_locked = true


## Dibuja una vez cada efecto y cada enemigo mientras aún está la pantalla de carga.
## Así sus shaders se compilan ahora y no en mitad del primer combate (evita tirones).
func _prewarm() -> void:
	var at := Vector3(0, 1.6, -2.0)
	Fx.slash(self, at, 0.0, 1.0, 2.0, Color(1, 1, 1, 0.02), 0.6)
	Fx.ring(self, at, 0.5, Color(1, 1, 1, 0.02), 0.6)
	Fx.burst(self, at, Color(1, 1, 1), 2, 0.5, 0.01, 0.5)
	Fx.number(self, at, " ", Color(1, 1, 1, 0.02))
	Fx.telegraph(self, at, 0.2, 0.5)
	var temp: Array[Node3D] = [Fx.make_bolt(self, JADE)]
	for kind in Defs.ENEMY_IDS:
		var v := EnemyView.new()
		add_child(v)
		v.setup(-1, kind)
		v.show_bar_for_prewarm()
		temp.append(v)
	for form in ["alux", "balam"]:
		var av := Avatar.new()
		add_child(av)
		av.setup(" ", "#2ec4a6", 0)
		av.form = form
		av._apply()
		temp.append(av)
	for n in temp:
		n.scale = Vector3.ONE * 0.02
		n.global_position = at
	get_tree().create_timer(0.8).timeout.connect(func() -> void:
		for n in temp:
			n.queue_free())


## Calidad baja (?q=low, o automática si el equipo no da para más):
## sin sombras ni resplandor y a menor resolución interna.
func _low_quality() -> void:
	_set_quality(true)


func _set_quality(low: bool) -> void:
	_quality_low = low
	var vp := get_viewport()
	vp.msaa_3d = Viewport.MSAA_DISABLED if low else Viewport.MSAA_2X
	vp.scaling_3d_scale = 0.6 if low else 1.0
	_builder.sun.shadow_enabled = not low
	_builder.env.glow_enabled = not low
	_builder.fireflies.emitting = not low
	_builder.fireflies.visible = not low


func _setup_input() -> void:
	var keys := {
		"fwd": [KEY_W, KEY_UP], "back": [KEY_S, KEY_DOWN], "left": [KEY_A, KEY_LEFT], "right": [KEY_D, KEY_RIGHT],
		"jump": [KEY_SPACE], "form1": [KEY_1], "form2": [KEY_2], "cam_l": [KEY_Q], "cam_r": [KEY_E],
		"atk1": [KEY_J], "atk2": [KEY_K], "atk3": [KEY_F, KEY_L], "perf": [KEY_F3],
	}
	for action in keys:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
		for k in keys[action]:
			var ev := InputEventKey.new()
			ev.physical_keycode = k
			InputMap.action_add_event(action, ev)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var captured := Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed and not captured and _net == Net.PLAYING:
				Input.mouse_mode = Input.MOUSE_MODE_CAPTURED  # el primer clic sólo captura el ratón
			else:
				_mouse_l = event.pressed and captured
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			_mouse_r = event.pressed and captured
		elif event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_cam_dist = maxf(3.5, _cam_dist - 0.6)
		elif event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_cam_dist = minf(13.0, _cam_dist + 0.6)
	elif event is InputEventMouseMotion:
		if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			_cam_yaw -= event.relative.x * 0.0042
			_cam_pitch = clampf(_cam_pitch + event.relative.y * 0.0035, -0.15, 1.25)
	elif event.is_action_pressed("ui_cancel"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		_mouse_l = false
		_mouse_r = false
	elif event.is_action_pressed("form1"):
		_want_form = "alux"
	elif event.is_action_pressed("form2"):
		_want_form = "balam"
	elif event.is_action_pressed("perf"):
		_perf_on = _hud.toggle_perf()


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
				if not _latest_me.is_empty():
					_reconcile(_latest_me, _latest_ack)
					_latest_me = []
				if _net == Net.PLAYING and _ws != null:
					_ping_in -= delta
					if _ping_in <= 0.0:
						_ping_in = 2.0
						_ws.send_text(JSON.stringify({"t": "ping", "c": Time.get_ticks_msec()}))
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
			_hp = float(m.get("hp", Defs.MAX_HP))
			_prev_pos = _pred.pos
			_visual_offset = Vector3.ZERO
			_pending.clear()
			_latest_me = []
			_seq = 0
			_retries = 0
			_clear_combat()
			_apply_world(m.w, true)
			_set_roster(m.players)
			_apply_enemies(m.get("e", []))
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
		"pong":
			var rtt := float(Time.get_ticks_msec()) - float(m.get("c", 0.0))
			if rtt >= 0.0 and rtt < 10000.0:
				_ping_ms = rtt if _ping_ms < 0.0 else lerpf(_ping_ms, rtt, 0.3)
		"error":
			var code := str(m.get("code", ""))
			if FATAL_CODES.has(code):
				_fatal(FATAL_CODES[code])
			# bad_ticket / ticket_used: se pide un ticket nuevo al reconectar


func _clear_combat() -> void:
	for id in _enemies:
		_enemies[id].queue_free()
	_enemies.clear()
	for id in _bolts:
		_bolts[id].node.queue_free()
	_bolts.clear()
	for b in _local_bolts:
		b.node.queue_free()
	_local_bolts.clear()


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
				_remote[slot] = {"buf": []}
		elif av.player_name != str(p.name) or av.hat != int(p.hat) or av.color.to_html(false) != str(p.color).trim_prefix("#").to_lower():
			av.setup(str(p.name), str(p.color), int(p.hat))
		av.set_online(bool(p.on))
	for slot in _avatars.keys():
		if not seen.has(slot):
			_avatars[slot].queue_free()
			_avatars.erase(slot)
			_remote.erase(slot)
	_hud.set_roster(players, _my_id)
	_hud.set_team_hp(_team_hp)


func _apply_world(w: Array, instant := false) -> void:
	var open := int(w[0]) != 0
	_plates_mask = int(w[1])
	_need = int(w[2])
	_encounter = int(w[3]) if w.size() > 3 else 0
	_wave_left = int(w[4]) if w.size() > 4 else 0
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
	if _encounter == 1:
		_hud.set_objective("¡Emboscada! Quedan %d guardianes corrompidos" % _wave_left)
	elif _encounter == 2:
		_hud.set_objective("Santuario liberado · Explora el claro")
	else:
		_hud.set_objective("Pisen %d altar%s al mismo tiempo para abrir el santuario  (%d/%d)" % [
			_need, "" if _need == 1 else "es", pressed, _need])


func _apply_enemies(list: Array) -> void:
	var seen := {}
	for e in list:
		var id := int(e[0])
		seen[id] = true
		var view: EnemyView = _enemies.get(id)
		if view == null:
			view = EnemyView.new()
			add_child(view)
			view.setup(id, Defs.ENEMY_IDS[clampi(int(e[1]), 0, Defs.ENEMY_IDS.size() - 1)])
			_enemies[id] = view
		view.push_state(_time, Vector3(e[2], e[3], e[4]), float(e[5]), float(e[6]), float(e[7]),
			Defs.ENEMY_STATES[clampi(int(e[8]), 0, Defs.ENEMY_STATES.size() - 1)])
	for id in _enemies.keys():
		if not seen.has(id):
			_enemies[id].queue_free()
			_enemies.erase(id)


func _on_snapshot(m: Dictionary) -> void:
	_snaps += 1
	_apply_world(m.w)
	for p in m.p:
		var slot := int(p[0])
		var state: Array = p.slice(4)
		_team_hp[slot] = float(p[3])
		var av: Avatar = _avatars.get(slot)
		if av != null:
			av.set_dead((int(state[7]) & 8) != 0)
		if slot == _my_slot:
			_hp = float(p[3])
			# Se reconcilia una sola vez por cuadro, con el estado más reciente (ver _poll_net)
			_latest_me = state
			_latest_ack = int(p[1])
		elif _remote.has(slot):
			var buf: Array = _remote[slot].buf
			buf.append({"t": _time, "pos": Vector3(state[0], state[1], state[2]), "yaw": float(state[4]),
				"form": Sim.FORM_IDS[clampi(int(state[5]), 0, Sim.FORM_IDS.size() - 1)], "flags": int(state[7])})
			while buf.size() > 12:
				buf.pop_front()
	_hud.set_team_hp(_team_hp)
	_apply_enemies(m.get("e", []))
	for ev in m.get("ev", []):
		_on_combat_event(ev)


func _reconcile(state: Array, ack: int) -> void:
	var old := _pred.pos
	_pred.from_array(state)
	while not _pending.is_empty() and int(_pending[0].s) <= ack:
		_pending.pop_front()
	for inp in _pending:
		Sim.step(_pred, inp, _unlocked, _gate_open)  # sin eventos: los efectos ya se mostraron
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
			_hud.banner("¡El santuario se abre!", Color(0.5, 1.0, 0.85), 3.0)
		"reward":
			if not bool(m.get("saved", false)):
				_hud.banner("Sello del Claro (no se pudo guardar el progreso)", Color(1, 0.6, 0.5), 5.0)
			elif bool(m.get("new", false)):
				_hud.banner("Obtuviste el Sello del Claro", GOLD, 6.0)
			else:
				_hud.banner("Ya tenías el Sello del Claro", Color(1, 1, 1, 0.9), 4.0)


# ───────────────────────── Combate (presentación) ─────────────────────────

func _avatar_pos(slot: int) -> Vector3:
	var av: Avatar = _avatars.get(slot)
	return av.global_position if av != null else Vector3.ZERO


## Efectos de una acción de jugador. Para el propio personaje se llaman al predecir.
func _show_action(slot: int, kind: String, yaw: float, power: float) -> void:
	var av: Avatar = _avatars.get(slot)
	if av == null:
		return
	av.play_action(kind)
	var pos := av.global_position
	match kind:
		"claw":
			var ab: Dictionary = Defs.FORMS.balam.primary
			Fx.slash(self, pos + Vector3(0, 0.8, 0), yaw, ab.range, ab.arc, Color(1.0, 0.75, 0.3))
		"charged":
			var ab: Dictionary = Defs.FORMS.balam.secondary
			Fx.slash(self, pos + Vector3(0, 0.8, 0), yaw, ab.range * (1.0 + 0.2 * power), ab.arc, Color(1.0, 0.45, 0.15), 0.32)
			Fx.burst(self, pos + Vector3(sin(yaw), 0.8, cos(yaw)) * 1.2, GOLD, 10 + int(power * 14.0), 5.0)
		"pounce":
			Fx.burst(self, pos + Vector3(0, 0.3, 0), Color(0.9, 0.8, 0.6), 10, 3.0)
		"pounce_land":
			Fx.ring(self, pos, Defs.FORMS.balam.special.radius, Color(1.0, 0.7, 0.25), 0.4)
			Fx.burst(self, pos + Vector3(0, 0.2, 0), Color(0.85, 0.75, 0.55), 16, 4.5, 0.09)
			if slot == _my_slot:
				_shake = 0.2
		"dodge":
			Fx.burst(self, pos + Vector3(0, 0.6, 0), av.color.lightened(0.4), 10, 2.5, 0.06, 0.35)
		"interact":
			Fx.ring(self, pos, 1.6, JADE, 0.35)


func _spawn_bolt(origin: Vector3, yaw: float) -> Dictionary:
	var ab: Dictionary = Defs.FORMS.alux.primary
	var b := {"node": Fx.make_bolt(self, JADE), "pos": origin, "dir": Vector3(sin(yaw), 0, cos(yaw)),
		"speed": float(ab.speed), "life": float(ab.life) + 0.25}
	(b.node as Node3D).global_position = origin
	return b


func _on_local_action(ev: Dictionary) -> void:
	if ev.k == "form":
		return
	_show_action(_my_slot, ev.k, ev.r, ev.p)
	if ev.k == "bolt":
		_local_bolts.append(_spawn_bolt(_pred.pos + Vector3(sin(ev.r) * 0.5, 0.9, cos(ev.r) * 0.5), ev.r))


func _on_combat_event(ev: Array) -> void:
	match str(ev[0]):
		"act":
			if int(ev[1]) != _my_slot:  # las propias ya se mostraron al predecirlas
				_show_action(int(ev[1]), str(ev[2]), float(ev[3]), float(ev[4]))
		"bolt":
			var id := int(ev[1])
			if int(ev[2]) == _my_slot and not _local_bolts.is_empty():
				_bolts[id] = _local_bolts.pop_front()  # la chispa que ya se veía pasa a ser la oficial
			else:
				_bolts[id] = _spawn_bolt(Vector3(ev[3], ev[4], ev[5]), float(ev[6]))
		"bolt_end":
			var id := int(ev[1])
			if _bolts.has(id):
				_bolts[id].node.queue_free()
				_bolts.erase(id)
			Fx.burst(self, Vector3(ev[2], ev[3], ev[4]), JADE, 12 if int(ev[5]) != 0 else 5, 3.5, 0.06, 0.35)
		"hit":
			var tally: Dictionary = _seen_enemy_dmg if str(ev[1]) == "e" else _seen_player_dmg
			var key := str(int(ev[2]))
			tally[key] = int(tally.get(key, 0)) + int(ev[3])
			if str(ev[1]) == "e":
				var view: EnemyView = _enemies.get(int(ev[2]))
				if view != null:
					view.hit_flash()
					var mine := int(ev[5]) == _my_slot
					Fx.number(self, view.global_position + Vector3(0, 1.6, 0), str(int(ev[3])), GOLD if mine else Color(1, 1, 1, 0.9), mine)
					Fx.burst(self, view.global_position + Vector3(0, 0.8, 0), Color(1.0, 0.9, 0.6), 6, 3.0, 0.05, 0.3)
			else:
				var slot := int(ev[2])
				var av: Avatar = _avatars.get(slot)
				if av != null:
					av.play_action("hit")
					Fx.number(self, av.global_position + Vector3(0, 1.8, 0), "-%d" % int(ev[3]), Color(1.0, 0.35, 0.35), slot == _my_slot)
				if slot == _my_slot:
					_hud.hurt()
					_shake = 0.3
		"die":
			if str(ev[1]) == "e":
				var view: EnemyView = _enemies.get(int(ev[2]))
				if view != null:
					view.die(int(ev[3]) != 0)
					if int(ev[3]) != 0:
						Fx.number(self, view.global_position + Vector3(0, 1.8, 0), "¡Purificada!", Color(0.6, 1.0, 0.8), true)
			else:
				var av: Avatar = _avatars.get(int(ev[2]))
				if av != null:
					av.set_dead(true)
					Fx.burst(self, av.global_position + Vector3(0, 0.6, 0), av.color, 18, 4.0)
		"respawn":
			var av: Avatar = _avatars.get(int(ev[1]))
			if av != null:
				av.set_dead(false)
			var c: Vector2 = Defs.CHECKPOINTS[clampi(1 if _encounter == 2 else 0, 0, 1)]
			Fx.ring(self, Vector3(c.x, World.terrain_h(c.x, c.y), c.y), 2.4, JADE, 0.6)
			if int(ev[1]) == _my_slot:
				_hud.banner("De vuelta en el punto de control", Color(0.6, 1.0, 0.85), 2.5)
		"heal":
			Fx.number(self, _avatar_pos(int(ev[1])) + Vector3(0, 1.9, 0), "+%d" % int(ev[2]), Color(0.5, 1.0, 0.6))
		"evade":
			Fx.number(self, _avatar_pos(int(ev[1])) + Vector3(0, 1.9, 0), "¡Esquiva!", Color(0.6, 0.95, 1.0))
		"eatk":
			var view: EnemyView = _enemies.get(int(ev[1]))
			if view != null:
				view.slam()
		"brazier":
			Fx.ring(self, Vector3(0, 0.1, 0), Defs.BRAZIER_RANGE + 2.0, Color(1.0, 0.75, 0.3), 0.7)
			Fx.burst(self, Vector3(0, 1.4, 0), Color(1.0, 0.8, 0.35), 26, 5.0, 0.08, 0.9)
		"enc":
			if str(ev[1]) == "start":
				_hud.banner("¡Emboscada! Los guardianes corrompidos despiertan", Color(1.0, 0.45, 0.6), 4.5)
			else:
				_hud.banner("¡Emboscada superada!", GOLD, 4.0)


## Ayuda de puntería: si hay un enemigo cerca de donde mira la cámara, se apunta a él.
func _aim_yaw() -> float:
	var base := wrapf(_cam_yaw, -PI, PI)
	var reach := 15.0 if _pred.form == "alux" else 4.5
	var best := base
	var best_score := 0.9  # como mucho ~50° de desviación
	for id in _enemies:
		var view: EnemyView = _enemies[id]
		if view.dying:
			continue
		var d := view.global_position - _pred.pos
		var dist := Vector2(d.x, d.z).length()
		if dist > reach or dist < 0.05:
			continue
		var yaw := atan2(d.x, d.z)
		var off := absf(angle_difference(base, yaw))
		var score := off + dist * 0.02
		if score < best_score:
			best_score = score
			best = yaw
	return best


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
	var buttons := 0
	if Input.is_action_pressed("atk1") or _mouse_l:
		buttons |= Sim.A_PRIMARY
	if Input.is_action_pressed("atk2") or _mouse_r:
		buttons |= Sim.A_SECONDARY
	if Input.is_action_pressed("atk3"):
		buttons |= Sim.A_SPECIAL
	_seq += 1
	var inp := {
		"t": "in", "s": _seq,
		"mx": snappedf(move.x, 0.001), "mz": snappedf(move.y, 0.001),
		"j": 1 if Input.is_action_pressed("jump") else 0,
		"f": _want_form,
		"a": buttons,
		"r": snappedf(_aim_yaw(), 0.001),
	}
	_want_form = ""
	_prev_pos = _pred.pos
	var actions: Array = []
	Sim.step(_pred, inp, _unlocked, _gate_open, actions)
	for ev in actions:
		_on_local_action(ev)
	_pending.append(inp)
	if _pending.size() > MAX_PENDING:
		_pending.pop_front()
	_ws.send_text(JSON.stringify(inp))


# ───────────────────────── Presentación ─────────────────────────

func _process(delta: float) -> void:
	_time += delta
	_poll_net(delta)

	if _debug_on:
		# Sólo en pruebas automáticas: permite orientar la cámara desde la página
		var forced := str(_js("window.ALUX_CAM_YAW === undefined ? '' : String(window.ALUX_CAM_YAW)"))
		if forced.is_valid_float():
			_cam_yaw = forced.to_float()
		var q := str(_js("window.ALUX_SET_QUALITY || ''"))
		if q == "low" or q == "high":
			_js("window.ALUX_SET_QUALITY = ''")
			_quality_locked = true
			_set_quality(q == "low")
	if Input.is_action_pressed("cam_l"):
		_cam_yaw += 1.9 * delta
	if Input.is_action_pressed("cam_r"):
		_cam_yaw -= 1.9 * delta

	# Mi personaje: interpolado entre ticks de simulación
	var me: Avatar = _avatars.get(_my_slot)
	if me != null and _net == Net.PLAYING:
		var f := Engine.get_physics_interpolation_fraction()
		_visual_offset = _visual_offset.lerp(Vector3.ZERO, minf(1.0, delta * 12.0))
		me.global_position = _prev_pos.lerp(_pred.pos, f) + _visual_offset
		me.rotation.y = lerp_angle(me.rotation.y, _pred.yaw, minf(1.0, delta * 16.0))
		me.set_form(_pred.form)
		me.animate(delta, _pred.grounded, _pred.swim)
		_cam_target = _cam_target.lerp(me.global_position + Vector3(0, 1.25, 0), minf(1.0, delta * 14.0))
		var form: Dictionary = Defs.FORMS[_pred.form]
		_hud.set_forms(_unlocked, _pred.form, float(_pred.form_cd))
		_hud.set_vitals(_hp, _pred.energy)
		_hud.set_abilities(_pred.form, [
			float(_pred.cd1) / float(Sim.ticks(form.primary.cd)),
			float(_pred.cd2) / float(Sim.ticks(form.secondary.cd)),
			float(_pred.cd3) / float(Sim.ticks(form.special.cd)),
		], _pred.energy, float(_pred.charge_t) / float(Sim.ticks(Defs.FORMS.balam.secondary.max_t)))
		_hud.set_death(_pred.dead)

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

	for id in _enemies:
		(_enemies[id] as EnemyView).update_view(_time, delta)

	# Chispas en vuelo (las retira el servidor al impactar; aquí sólo avanzan)
	for id in _bolts.keys():
		if not _advance_bolt(_bolts[id], delta):
			_bolts.erase(id)
	_local_bolts = _local_bolts.filter(func(b: Dictionary) -> bool: return _advance_bolt(b, delta))

	# Puerta y sello del santuario, glifo
	if _gate_open and _gate_anim < 1.0:
		_gate_anim = minf(1.0, _gate_anim + delta * 0.8)
	if _builder.gate_bars:
		var base_y := World.terrain_h(World.SANCTUARY.x - 6.0, World.SANCTUARY.y)
		_builder.gate_bars.position.y = base_y - _gate_anim * 3.6
		_builder.gate_bars.visible = _gate_anim < 1.0
		_builder.gate_light.light_energy = 1.8 * (1.0 - _gate_anim)
	if _builder.seal_veil:
		_builder.seal_veil.visible = _gate_anim < 1.0
		_builder.seal_mat.albedo_color.a = 0.16 * (1.0 - _gate_anim) * (0.8 + 0.2 * sin(_time * 2.0))
	if _builder.glyph:
		_builder.glyph.rotation.y += delta * 1.2
		_builder.glyph.position.y += sin(_time * 2.0) * delta * 0.25

	_update_camera()
	_update_perf(delta)
	_debug_export(delta)


func _advance_bolt(b: Dictionary, delta: float) -> bool:
	b.life -= delta
	b.pos += b.dir * b.speed * delta
	if b.life <= 0.0:
		b.node.queue_free()
		return false
	(b.node as Node3D).global_position = b.pos
	return true


func _update_camera() -> void:
	var fwd := Vector3(sin(_cam_yaw) * cos(_cam_pitch), -sin(_cam_pitch), cos(_cam_yaw) * cos(_cam_pitch))
	var pos := _cam_target - fwd * _cam_dist
	var ground := World.terrain_h(pos.x, pos.z) + 0.5
	if pos.y < ground:
		pos.y = ground
	if _shake > 0.0:
		_shake = maxf(0.0, _shake - get_process_delta_time())
		pos += Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * _shake * 0.35
	_cam.global_position = pos
	_cam.look_at(_cam_target, Vector3.UP)


## Datos de rendimiento (F3): cuadros, latencia, estados por segundo y memoria.
func _perf_stats() -> Dictionary:
	var mem := float(OS.get_static_memory_usage()) / 1048576.0
	var heap := -1.0
	if _is_web:
		heap = float(_js("(performance && performance.memory) ? performance.memory.usedJSHeapSize / 1048576 : -1"))
	return {
		"fps": Engine.get_frames_per_second(), "ping": snappedf(_ping_ms, 0.1), "snaps": snappedf(_snap_rate, 0.1),
		"mem": snappedf(mem, 0.1), "heap": snappedf(heap, 0.1),
		"draws": RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME),
		"enemies": _enemies.size(), "pending": _pending.size(),
	}


## Calidad automática: si durante dos ventanas seguidas de 4 s no se llega a 20 FPS,
## se pasa a calidad baja. (?q=high lo desactiva.)
func _auto_quality(delta: float) -> void:
	if _quality_low or _quality_locked or _net != Net.PLAYING:
		return
	_fps_frames += 1
	_fps_time += delta
	if _fps_time < 4.0:
		return
	var fps := float(_fps_frames) / _fps_time
	_fps_frames = 0
	_fps_time = 0.0
	_slow_windows = _slow_windows + 1 if fps < 20.0 else 0
	if _slow_windows >= 2:
		_low_quality()
		_hud.banner("Calidad reducida para ir más fluido", Color(0.8, 0.9, 1.0), 3.0)


func _update_perf(delta: float) -> void:
	_auto_quality(delta)
	_perf_in -= delta
	if _perf_in > 0.0:
		return
	_snap_rate = float(_snaps)
	_snaps = 0
	_perf_in = 1.0
	if _perf_on:
		var s := _perf_stats()
		_hud.set_perf("%d FPS · ping %s ms · %s estados/s\n%d dibujados · %d enemigos · memoria %s MB%s" % [
			s.fps, ("%.0f" % s.ping) if s.ping >= 0.0 else "—", "%.0f" % s.snaps, s.draws, s.enemies,
			"%.0f" % s.mem, (" · JS %.0f MB" % s.heap) if s.heap >= 0.0 else ""])


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
			"id": p.id, "slot": p.slot, "name": p.name, "on": p.on, "form": av.form, "dead": av.dead,
			"hp": _team_hp.get(int(p.slot), 100.0),
			"x": snappedf(av.global_position.x, 0.01), "y": snappedf(av.global_position.y, 0.01), "z": snappedf(av.global_position.z, 0.01),
		})
	var foes := []
	for id in _enemies:
		var v: EnemyView = _enemies[id]
		foes.append({"id": id, "kind": v.kind, "hp": v.hp, "state": v.state,
			"x": snappedf(v.global_position.x, 0.01), "z": snappedf(v.global_position.z, 0.01)})
	var state := {
		"net": Net.keys()[_net], "room": _room, "me": _my_id, "slot": _my_slot, "players": players,
		"gate": _gate_open, "plates": _plates_mask, "need": _need, "form": _pred.form,
		"hp": _hp, "energy": _pred.energy, "encounter": _encounter, "wave": _wave_left, "enemies": foes,
		"frames": Engine.get_process_frames(), "rejoins": _rejoins, "glb": (_avatars.get(_my_slot) as Avatar).uses_glb if _avatars.has(_my_slot) else false,
		"dmg_enemies": _seen_enemy_dmg, "dmg_players": _seen_player_dmg,
		"perf": _perf_stats(), "quality": "low" if _quality_low else "high",
	}
	_js("window.__aluxState = %s" % JSON.stringify(state))
