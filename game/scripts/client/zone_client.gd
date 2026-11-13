extends Node3D
## Cliente de la plaza social (prototipo): «Mérida, la Ciudad Blanca».
##
## Otro cliente, más pequeño que el de las misiones (game_client.gd), contra el servidor de zonas.
## El jugador pasea con su alux, ve a los demás que tiene cerca, puede cambiarse de aspecto y
## entra al Claro de los Aluxes por el portal. No hay combate.
##
## El movimiento se predice con la misma función que usa el servidor (zone_def.gd): cada entrada
## se aplica aquí al instante y, cuando el servidor contesta, se rehace desde su posición con las
## entradas que aún no ha visto. Los demás aluxes se dibujan un poco en el pasado, entre estados.

const Zone := preload("res://scripts/shared/zone_def.gd")
const Look := preload("res://scripts/shared/look_def.gd")
const Avatar := preload("res://scripts/client/avatar.gd")
const Audio := preload("res://scripts/client/audio.gd")
const Customizer := preload("res://scripts/client/customizer.gd")
const Plaza := preload("res://scripts/client/plaza_builder.gd")
const Kit := preload("res://scripts/client/ui/ui_kit.gd")
const Hud := preload("res://scripts/client/hud.gd")

enum Net { TICKET, CONNECTING, HELLO, PLAYING, WAIT, FATAL }

var _net := Net.TICKET
var _ws: WebSocketPeer
var _is_web := false
var _debug_on := false
var _time := 0.0
var _wait := 0.0
var _tries := 0
var _ticket_poll := 0.0
var _hello_sent := false

var _plaza := Plaza.new()
var _cam: Camera3D
var _cam_yaw := PI
var _cam_pitch := 0.3
var _cam_dist := 7.5
var _audio: Audio
var _custom: Customizer

# Mi alux
var _my_num := 0
var _profile := {"n": "Alux", "c": "#2ec4a6", "h": 0, "l": Look.DEFAULT}
var _me: Avatar
var _pred: Array = [0.0, 0.0, 0.0, 0.0]     # posición predicha: x, y, z, vy
var _prev: Array = [0.0, 0.0, 0.0, 0.0]     # la del paso anterior (para dibujar entre pasos)
var _pending: Array = []                    # entradas que el servidor aún no ha confirmado: [seq, mx, mz, salto]
var _seq := 0
var _acc := 0.0
var _fix := Vector3.ZERO                    # corrección que se va absorbiendo si el servidor discrepa
var _face := PI
var _goto: Variant = null                   # (pruebas) punto al que andar solo

# Los demás
var _others := {}                           # num -> {av, buf: [[t, x, y, z, yaw]], n}
var _total := 0
var _cap := 0

# Interfaz
var _ui: CanvasLayer
var _info: Label
var _hint: Label
var _prompt: Label
var _overlay: Label
var _menu: Control
var _menu_fs: Button
var _captured_t := 0.0
var _was_captured := false
var _room_poll := 0.0
var _debug_in := 0.0
var _amb_in := 0.0


func _ready() -> void:
	_is_web = OS.has_feature("web")
	Audio.ground_override = "piedra"
	_plaza.build(self)
	_cam = Camera3D.new()
	_cam.fov = 62.0
	_cam.far = 300.0
	add_child(_cam)
	_cam.make_current()
	_audio = Audio.new()
	add_child(_audio)
	_custom = Customizer.new()
	add_child(_custom)
	_custom.saved.connect(_on_look_saved)
	_custom.closed.connect(_on_custom_closed)
	_build_ui()
	if _is_web:
		_debug_on = int(_js("window.ALUX_DEBUG === true ? 1 : 0")) == 1
		_load_volumes()
		_request_ticket()
	_set_overlay("Abriendo la plaza…")
	_update_camera(Vector3(Zone.SPAWN_CENTER.x, 0.0, Zone.SPAWN_CENTER.y))


func _js(code: String) -> Variant:
	return JavaScriptBridge.eval(code) if _is_web else null


## Los volúmenes son los mismos ajustes que guarda el juego de las misiones.
func _load_volumes() -> void:
	var raw: Variant = _js("(function(){try{return localStorage.getItem('alux_settings')||''}catch(e){return ''}})()")
	var saved: Variant = JSON.parse_string(str(raw)) if typeof(raw) == TYPE_STRING and not str(raw).is_empty() else null
	var s: Dictionary = saved if saved is Dictionary else {}
	for pair in [["Master", "vol_master", 0.9], ["Music", "vol_music", 0.7], ["Ambience", "vol_amb", 0.8], ["SFX", "vol_sfx", 0.9], ["UI", "vol_ui", 0.8]]:
		var v: Variant = s.get(pair[1])
		_audio.set_volume(str(pair[0]), clampf(float(v), 0.0, 1.0) if (typeof(v) == TYPE_FLOAT or typeof(v) == TYPE_INT) else float(pair[2]))


# ───────────────────────── Red ─────────────────────────

func _request_ticket() -> void:
	_net = Net.TICKET
	_ticket_poll = 0.2
	_js("(function(){window.ALUX_ZONE='';fetch('/api/v1/zones/%s/ticket',{method:'POST',credentials:'same-origin',headers:{'x-alux-csrf':'1'}})" % Zone.ID +
		".then(function(r){if(r.status===401){var w=window;try{if(window.top&&window.top.document)w=window.top}catch(e){}w.location.href='/?next=%2Fplaza';return ''}" +
		"return r.ok?r.text():Promise.reject(r.status)}).then(function(t){if(t)window.ALUX_ZONE=t}).catch(function(e){window.ALUX_ZONE='error:'+e})})()")


func _poll_net(delta: float) -> void:
	match _net:
		Net.TICKET:
			_ticket_poll -= delta
			if _ticket_poll > 0.0:
				return
			_ticket_poll = 0.2
			var raw := str(_js("window.ALUX_ZONE || ''"))
			if raw.is_empty():
				return
			var parsed: Variant = JSON.parse_string(raw)
			if raw.begins_with("error:") or not (parsed is Dictionary):
				_retry("La plaza no está disponible ahora mismo.")
				return
			_ws = WebSocketPeer.new()
			_ws.inbound_buffer_size = 262144
			if _ws.connect_to_url(str(parsed.wsUrl)) != OK:
				_retry("No se pudo conectar con la plaza.")
				return
			_ws.set_meta("ticket", str(parsed.ticket))
			_hello_sent = false
			_net = Net.CONNECTING
		Net.CONNECTING, Net.HELLO, Net.PLAYING:
			_ws.poll()
			var st := _ws.get_ready_state()
			if st == WebSocketPeer.STATE_OPEN:
				if not _hello_sent:
					_hello_sent = true
					_ws.send_text(JSON.stringify({"t": "hello", "ticket": _ws.get_meta("ticket")}))
					_net = Net.HELLO
				while _ws.get_available_packet_count() > 0:
					var m: Variant = JSON.parse_string(_ws.get_packet().get_string_from_utf8())
					if m is Dictionary:
						_on_message(m)
			elif st == WebSocketPeer.STATE_CLOSED and _net != Net.FATAL:
				_retry("Se perdió la conexión con la plaza.")
		Net.WAIT:
			_wait -= delta
			if _wait <= 0.0:
				_request_ticket()


func _retry(text: String) -> void:
	_clear_others()
	_tries += 1
	_wait = minf(2.0 + float(_tries), 8.0)
	_net = Net.WAIT
	_set_overlay("%s\nReintentando…" % text)


func _fatal(text: String) -> void:
	_net = Net.FATAL
	_clear_others()
	_set_overlay(text)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _on_message(m: Dictionary) -> void:
	match str(m.get("t", "")):
		"welcome":
			_my_num = int(m.get("i", 0))
			_cap = int(m.get("cap", 0))
			_profile = m.get("me", _profile)
			var pos: Array = m.get("pos", [0.0, 0.0, 0.0])
			_pred = [float(pos[0]), float(pos[1]), float(pos[2]), 0.0]
			_prev = _pred.duplicate()
			_pending.clear()
			_seq = 0
			_fix = Vector3.ZERO
			_face = float(m.get("yaw", PI))
			_cam_yaw = _face
			_spawn_me()
			_tries = 0
			_net = Net.PLAYING
			_set_overlay("")
			_hint.text = "Clic para mirar  ·  WASD para andar  ·  Espacio para saltar  ·  Esc: menú"
			_audio.set_music("mus_lobby")
		"s":
			_total = int(m.get("n", 0))
			_reconcile(m.get("m", []), int(m.get("a", 0)))
			for e in m.get("p", []):
				var o: Dictionary = _others.get(int(e[0]), {})
				if o.is_empty():
					continue
				var buf: Array = o.buf
				buf.append([_time, float(e[1]), float(e[2]), float(e[3]), float(e[4])])
				if buf.size() > 12:
					buf.pop_front()
		"enter":
			_enter(m)
		"leave":
			_leave(int(m.get("i", 0)))
		"me":
			_profile = m.get("me", _profile)
			_spawn_me()
		"error":
			var code := str(m.get("code", ""))
			if code == "zone_full":
				_retry("La plaza está llena.")
			elif code == "replaced":
				_fatal("Abriste la plaza en otra ventana.\nEsta se queda en pausa.")
			elif code == "bad_ticket":
				_retry("El pase a la plaza caducó.")
			else:
				_fatal("La plaza cerró la conexión (%s)." % code)


func _spawn_me() -> void:
	if _me == null:
		_me = Avatar.new()
		_me.forms = ["alux"]
		_me.is_local = true
		add_child(_me)
	_me.setup(str(_profile.get("n", "Alux")), str(_profile.get("c", "#2ec4a6")), int(_profile.get("h", 0)), _profile.get("l"))
	_me.visible = not _custom.active


func _enter(m: Dictionary) -> void:
	var num := int(m.get("i", 0))
	var o: Dictionary = _others.get(num, {})
	if o.is_empty():
		var av := Avatar.new()
		av.forms = ["alux"]   # en la plaza nadie se transforma: un solo modelo por alux
		add_child(av)
		o = {"av": av, "buf": [], "n": ""}
		_others[num] = o
		av.global_position = Vector3(float(m.get("x", 0.0)), float(m.get("y", 0.0)), float(m.get("z", 0.0)))
		av.rotation.y = float(m.get("r", 0.0))
	o.n = str(m.get("n", "Alux"))
	o.c = str(m.get("c", "#2ec4a6"))
	o.h = int(m.get("h", 0))
	o.l = Look.clean(m.get("l"))
	(o.av as Avatar).setup(o.n, o.c, o.h, o.l)
	(o.buf as Array).append([_time, float(m.get("x", 0.0)), float(m.get("y", 0.0)), float(m.get("z", 0.0)), float(m.get("r", 0.0))])


func _leave(num: int) -> void:
	var o: Dictionary = _others.get(num, {})
	if not o.is_empty():
		(o.av as Avatar).queue_free()
		_others.erase(num)


func _clear_others() -> void:
	for num in _others.keys():
		_leave(num)


## El servidor dice dónde estoy tras aplicar hasta la entrada `ack`: se rehace desde ahí con las
## que aún no ha visto. Si todo va bien el resultado es el mismo que ya se había predicho.
func _reconcile(state: Array, ack: int) -> void:
	if state.size() < 4:
		return
	while not _pending.is_empty() and int(_pending[0][0]) <= ack:
		_pending.pop_front()
	var s: Array = [float(state[0]), float(state[1]), float(state[2]), float(state[3])]
	for inp in _pending:
		s = Zone.step(s, float(inp[1]), float(inp[2]), bool(inp[3]))
	var gap := Vector3(float(_pred[0]) - float(s[0]), float(_pred[1]) - float(s[1]), float(_pred[2]) - float(s[2]))
	if gap.length() > 0.001:
		# La diferencia no se salta de golpe: se absorbe en unas décimas (o de una vez si es enorme)
		_fix = (_fix + gap) if gap.length() < 3.0 else Vector3.ZERO
		_pred = s
		_prev = s.duplicate()


# ───────────────────────── Bucle ─────────────────────────

func _process(delta: float) -> void:
	_time += delta
	_poll_net(delta)
	_plaza.update(_time)
	if _net != Net.PLAYING or _me == null:
		_debug_export(delta)
		return
	_track_mouse(delta)
	# Entradas a 20 por segundo, una por paso de simulación
	_acc += delta
	var steps := 0
	while _acc >= Zone.DT and steps < 4:
		_acc -= Zone.DT
		steps += 1
		_tick()
	if steps == 4:
		_acc = 0.0
	# Mi alux, entre el paso anterior y el actual
	var k := clampf(_acc / Zone.DT, 0.0, 1.0)
	_fix = _fix.lerp(Vector3.ZERO, minf(1.0, delta * 10.0))
	var at := Vector3(lerpf(float(_prev[0]), float(_pred[0]), k), lerpf(float(_prev[1]), float(_pred[1]), k), lerpf(float(_prev[2]), float(_pred[2]), k)) + _fix
	_me.global_position = at
	_me.rotation.y = lerp_angle(_me.rotation.y, _face, minf(1.0, delta * 12.0))
	_me.animate(delta, at.y <= 0.02, false)
	_audio.listener = at
	_update_others(delta)
	if _custom.active:
		_custom.process(delta)
	else:
		_update_camera(at)
	_update_ui(at)
	_update_soundscape(delta, at)
	_poll_room(delta)
	_debug_export(delta)


func _tick() -> void:
	var mx := 0.0
	var mz := 0.0
	var jump := false
	if not _custom.active and not _menu.visible:
		var fwd := Vector2(sin(_cam_yaw), cos(_cam_yaw))
		var right := Vector2(-fwd.y, fwd.x)
		var f := float(Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP)) - float(Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_DOWN))
		var r := float(Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT)) - float(Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT))
		var move := fwd * f + right * r
		jump = Input.is_physical_key_pressed(KEY_SPACE)
		if _goto is Vector2:
			# (pruebas) anda solo hacia un punto
			var to: Vector2 = (_goto as Vector2) - Vector2(float(_pred[0]), float(_pred[2]))
			if to.length() < 0.6:
				_goto = null
			else:
				move = to.normalized()
		if move.length() > 1.0:
			move = move.normalized()
		mx = move.x
		mz = move.y
	if absf(mx) + absf(mz) > 0.01:
		_face = atan2(mx, mz)
	_prev = _pred.duplicate()
	_pred = Zone.step(_pred, mx, mz, jump)
	_seq += 1
	_pending.append([_seq, mx, mz, jump])
	if _pending.size() > 40:
		_pending.pop_front()
	if _ws != null and _ws.get_ready_state() == WebSocketPeer.STATE_OPEN:
		_ws.send_text(JSON.stringify({"t": "in", "s": _seq, "x": snappedf(mx, 0.001), "z": snappedf(mz, 0.001), "j": 1 if jump else 0, "r": snappedf(_face, 0.01)}))


## Los demás aluxes se dibujan un poco en el pasado, interpolando entre los estados recibidos.
## Los lejanos llegan menos a menudo: su retraso es mayor para que nunca falte el estado siguiente.
func _update_others(delta: float) -> void:
	for num in _others:
		var o: Dictionary = _others[num]
		var buf: Array = o.buf
		var av: Avatar = o.av
		if buf.is_empty():
			continue
		var spacing := 0.1
		if buf.size() >= 2:
			spacing = clampf(float(buf[-1][0]) - float(buf[-2][0]), 0.08, 0.3)
		var t := _time - spacing * 1.6
		var a: Array = buf[0]
		var b: Array = buf[-1]
		for i in range(buf.size() - 1):
			if float(buf[i + 1][0]) >= t:
				a = buf[i]
				b = buf[i + 1]
				break
			a = buf[i + 1]
		var span := float(b[0]) - float(a[0])
		var k := clampf((t - float(a[0])) / span, 0.0, 1.0) if span > 0.0001 else 1.0
		var pos := Vector3(lerpf(float(a[1]), float(b[1]), k), lerpf(float(a[2]), float(b[2]), k), lerpf(float(a[3]), float(b[3]), k))
		av.global_position = av.global_position.lerp(pos, minf(1.0, delta * 18.0))
		av.rotation.y = lerp_angle(av.rotation.y, lerp_angle(float(a[4]), float(b[4]), k), minf(1.0, delta * 10.0))
		av.animate(delta, pos.y <= 0.02, false)


func _update_camera(target: Vector3) -> void:
	var look := target + Vector3(0, 1.1, 0)
	var fwd := Vector3(sin(_cam_yaw) * cos(_cam_pitch), -sin(_cam_pitch), cos(_cam_yaw) * cos(_cam_pitch))
	var pos := look - fwd * _cam_dist
	pos.y = maxf(pos.y, 0.4)
	# La cámara no sale del recinto (ni atraviesa el edificio de los arcos)
	pos.x = clampf(pos.x, -Zone.HALF + 0.4, Zone.HALF - 0.4)
	pos.z = clampf(pos.z, -28.4, Zone.HALF - 0.4)
	_cam.global_position = pos
	_cam.look_at(look, Vector3.UP)


func _update_soundscape(delta: float, at: Vector3) -> void:
	_amb_in -= delta
	if _amb_in > 0.0:
		return
	_amb_in = 0.5
	var fountain := clampf(1.0 - (Vector2(at.x, at.z).distance_to(Vector2(-15.0, 12.0)) - 2.5) / 16.0, 0.0, 1.0)
	_audio.ambience({"amb_aves": 0.3, "amb_viento": 0.25, "amb_agua": snappedf(0.55 * fountain * fountain, 0.05)})


# ───────────────────────── Entrada ─────────────────────────

func _unhandled_input(event: InputEvent) -> void:
	if _custom.active or _net != Net.PLAYING:
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var mm := event as InputEventMouseMotion
		_cam_yaw = wrapf(_cam_yaw - mm.relative.x * 0.004, -PI, PI)
		_cam_pitch = clampf(_cam_pitch + mm.relative.y * 0.003, -0.25, 1.1)
	elif event is InputEventMouseButton and (event as InputEventMouseButton).pressed:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			_cam_dist = clampf(_cam_dist - 0.6, 3.0, 13.0)
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_cam_dist = clampf(_cam_dist + 0.6, 3.0, 13.0)
		elif not _menu.visible:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	elif event is InputEventKey and (event as InputEventKey).pressed and not (event as InputEventKey).echo:
		var key := (event as InputEventKey).physical_keycode
		if key == KEY_ESCAPE:
			_toggle_menu(not _menu.visible)
		elif key == KEY_F and not _menu.visible and Zone.at_portal(float(_pred[0]), float(_pred[2])):
			_enter_claro()


## Esc en el navegador suelta el ratón sin avisar: se toma como «abrir el menú».
func _track_mouse(delta: float) -> void:
	if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_captured_t += delta
		if _captured_t > 0.5:
			_was_captured = true
	else:
		_captured_t = 0.0
		if _was_captured:
			_was_captured = false
			if not _custom.active and not _menu.visible and _room_poll <= 0.0:
				_toggle_menu(true)


# ───────────────────────── Portal al Claro ─────────────────────────

## Cruzar el portal: se crea una sala del Claro de los Aluxes con la API de siempre y se entra.
## (Prototipo: cada alux abre su sala; llevar al grupo junto llega con los grupos de la plaza.)
func _enter_claro() -> void:
	if _room_poll > 0.0:
		return
	Audio.play("santuario_abre|ui_confirmar", null, -4.0, 0.0)
	_set_overlay("Cruzando al Claro de los Aluxes…")
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_room_poll = 0.2
	_js("(function(){window.ALUX_ROOM='';fetch('/api/v1/rooms',{method:'POST',credentials:'same-origin',headers:{'content-type':'application/json','x-alux-csrf':'1'}," +
		"body:JSON.stringify({visibility:'private'})}).then(function(r){return r.ok?r.json():Promise.reject(r.status)})" +
		".then(function(d){window.ALUX_ROOM=d.code||'error:sin código'}).catch(function(e){window.ALUX_ROOM='error:'+e})})()")


func _poll_room(delta: float) -> void:
	if _room_poll <= 0.0:
		return
	_room_poll -= delta
	if _room_poll > 0.0:
		return
	_room_poll = 0.2
	var code := str(_js("window.ALUX_ROOM || ''"))
	if code.is_empty():
		return
	_room_poll = 0.0
	if code.begins_with("error:"):
		_set_overlay("")
		_hint.text = "El portal no respondió. Inténtalo otra vez."
		return
	if _ws != null:
		_ws.close()
	_net = Net.FATAL   # ya no se reconecta: se va a la sala
	var debug := "?debug=1&q=min" if _debug_on else ""
	_js("(function(){var w=window;try{if(window.top&&window.top.document)w=window.top}catch(e){}w.location.href='/play/%s%s'})()" % [code.to_upper().substr(0, 12), debug])


# ───────────────────────── Personalizador ─────────────────────────

func _open_customizer() -> void:
	if _net != Net.PLAYING or _me == null or _custom.active:
		return
	_toggle_menu(false)
	_ui.visible = false
	_me.visible = false
	_custom.open(self, _cam, _me.global_position, _me.rotation.y,
		{"name": _profile.get("n", "Alux"), "color": _profile.get("c", "#2ec4a6"), "hat": int(_profile.get("h", 0)), "look": _profile.get("l")})


func _on_look_saved(character: Dictionary) -> void:
	# Lo guardó la API. El servidor de zonas lo relee de ella y lo reparte a quien me ve.
	_profile = {"n": _profile.get("n", "Alux"), "c": str(character.color), "h": int(character.hat), "l": character.look}
	_spawn_me()
	if _ws != null and _net == Net.PLAYING:
		_ws.send_text(JSON.stringify({"t": "look"}))


func _on_custom_closed(_did_save: bool) -> void:
	_ui.visible = true
	if _me != null:
		_me.visible = true


# ───────────────────────── Interfaz ─────────────────────────

func _build_ui() -> void:
	_ui = CanvasLayer.new()
	_ui.layer = 10
	add_child(_ui)
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui.add_child(root)
	var panel := Hud.Plaque.new(12)
	panel.position = Vector2(16, 16)
	panel.modulate.a = 0.92
	root.add_child(panel)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 2)
	panel.add_child(col)
	col.add_child(Kit.label("%s  ·  %s" % [Zone.NAME.to_upper(), Zone.ALIAS], 15, Kit.GOLD, Kit.bold_font()))
	_info = Kit.label("", 13, Kit.LIME)
	col.add_child(_info)
	_hint = Kit.label("", 13, Color(1, 1, 1, 0.75))
	_hint.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_hint.position = Vector2(60, -34)
	root.add_child(_hint)
	_prompt = Kit.label("", 20, Kit.JADE, Kit.bold_font())
	_prompt.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_prompt.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_prompt.position.y = -120
	root.add_child(_prompt)
	_overlay = Kit.label("", 22, Color.WHITE, Kit.bold_font())
	_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_overlay.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_overlay.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	root.add_child(_overlay)

	_menu = CenterContainer.new()
	_menu.set_anchors_preset(Control.PRESET_FULL_RECT)
	_menu.visible = false
	root.add_child(_menu)
	var plaque := Hud.Plaque.new(18)
	_menu.add_child(plaque)
	var mv := VBoxContainer.new()
	mv.add_theme_constant_override("separation", 8)
	mv.custom_minimum_size = Vector2(320, 0)
	plaque.add_child(mv)
	var title := Kit.label("LA PLAZA", 26, Kit.GOLD, Kit.title_font())
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	mv.add_child(title)
	mv.add_child(_button("Seguir paseando", func() -> void: _toggle_menu(false), true))
	mv.add_child(_button("Personalizar mi alux", _open_customizer))
	_menu_fs = _button("Pantalla completa", func() -> void: _js("window.ALUX_FS && ALUX_FS.toggle()"))
	_menu_fs.visible = _is_web and bool(_js("!!(window.ALUX_FS && ALUX_FS.supported)"))
	mv.add_child(_menu_fs)
	mv.add_child(_button("Volver al portal", _exit_to_portal))


func _button(text: String, on_press: Callable, primary := false) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(0, 40)
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var accent := Kit.GOLD if primary else Kit.JADE
	var normal := Kit.flat(Kit.OBSIDIAN_SOLID.lerp(accent, 0.16 if primary else 0.06), 12.0, 2, accent.darkened(0.25))
	var hover := Kit.flat(Kit.OBSIDIAN_SOLID.lerp(accent, 0.3), 12.0, 2, accent)
	b.add_theme_stylebox_override("normal", normal)
	b.add_theme_stylebox_override("hover", hover)
	b.add_theme_stylebox_override("pressed", hover)
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	b.add_theme_font_override("font", Kit.bold_font())
	b.add_theme_font_size_override("font_size", 15)
	b.add_theme_color_override("font_color", accent.lightened(0.5))
	b.add_theme_color_override("font_hover_color", Color.WHITE)
	b.pressed.connect(func() -> void:
		Audio.play("ui_click")
		on_press.call())
	return b


func _toggle_menu(open: bool) -> void:
	_menu.visible = open
	Audio.play("ui_abrir" if open else "ui_cerrar|ui_click")
	if open:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		_was_captured = false


func _set_overlay(text: String) -> void:
	_overlay.text = text


func _update_ui(at: Vector3) -> void:
	_info.text = "%d %s en la plaza  ·  ves a %d" % [_total, "alux" if _total == 1 else "aluxes", _others.size()]
	_prompt.text = "F  ·  Entrar al Claro de los Aluxes" if (Zone.at_portal(at.x, at.z) and not _menu.visible and _room_poll <= 0.0) else ""


func _exit_to_portal() -> void:
	if _ws != null:
		_ws.close()
	_net = Net.FATAL
	if _is_web:
		_js("(function(){var w=window;try{if(window.top&&window.top.document)w=window.top}catch(e){}w.location.href='/hub'})()")
	else:
		get_tree().quit()


# ───────────────────────── Pruebas ─────────────────────────

## Estado visible para las pruebas automáticas (sólo con ?debug=1 en la URL).
func _debug_export(delta: float) -> void:
	if not _is_web or not _debug_on:
		return
	var goto := str(_js("window.ALUX_ZONE_GOTO || ''"))
	if "," in goto:
		_js("window.ALUX_ZONE_GOTO = ''")
		_goto = Vector2(goto.get_slice(",", 0).to_float(), goto.get_slice(",", 1).to_float())
	var act := str(_js("window.ALUX_ACTION || ''"))
	if not act.is_empty():
		_js("window.ALUX_ACTION = ''")
		match act:
			"customize":
				_open_customizer()
			"portal":
				if Zone.at_portal(float(_pred[0]), float(_pred[2])):
					_enter_claro()
			"menu":
				_toggle_menu(not _menu.visible)
	var cmd := str(_js("window.ALUX_CUSTOM || ''"))
	if not cmd.is_empty():
		_js("window.ALUX_CUSTOM = ''")
		if _custom.active:
			_custom.command(cmd)
	_debug_in -= delta
	if _debug_in > 0.0:
		return
	_debug_in = 0.2
	var players := []
	for num in _others:
		var o: Dictionary = _others[num]
		var av: Avatar = o.av
		players.append({"name": o.n, "color": "#" + av.color.to_html(false), "hat": av.hat, "look": av.look,
			"x": snappedf(av.global_position.x, 0.01), "y": snappedf(av.global_position.y, 0.01), "z": snappedf(av.global_position.z, 0.01)})
	var state := {
		"net": Net.keys()[_net], "zone": Zone.ID, "total": _total, "cap": _cap, "players": players,
		"me": {"name": _profile.get("n", ""), "color": _profile.get("c", ""), "hat": _profile.get("h", 0), "look": _profile.get("l", []),
			"x": snappedf(float(_pred[0]), 0.01), "y": snappedf(float(_pred[1]), 0.01), "z": snappedf(float(_pred[2]), 0.01)},
		"portal": Zone.at_portal(float(_pred[0]), float(_pred[2])), "prompt": _prompt.text, "overlay": _overlay.text,
		"custom": _custom.info(), "snd": _audio.info(), "ui": {"menu": _menu.visible, "captured": Input.mouse_mode == Input.MOUSE_MODE_CAPTURED},
		"perf": {"fps": Engine.get_frames_per_second(), "draws": int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)),
			"pending": _pending.size()},
	}
	_js("window.__aluxState = %s" % JSON.stringify(state))
