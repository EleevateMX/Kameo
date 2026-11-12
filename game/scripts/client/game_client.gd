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
const Audio := preload("res://scripts/client/audio.gd")
const Story := preload("res://scripts/shared/story_def.gd")
const Cutscene := preload("res://scripts/client/cinematics/cutscene.gd")
const NpcView := preload("res://scripts/client/npc_view.gd")

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
const QUALITY_NAMES := ["alta", "baja", "mínima"]
## Errores con los que tiene sentido reintentar recargando (los demás sólo ofrecen volver al portal)
const RELOADABLE := ["version", "server_full", "rate_limited"]

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
var _team := {}             # slot -> {hp, dead, form} para el panel de grupo
var _brazier_ready := true
var _hint_in := 0.0
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
var _quality := 0
var _seen_enemy_dmg := {}   # id de enemigo -> daño total visto (para pruebas)
var _seen_player_dmg := {}  # lugar -> daño total visto
var _quality_locked := false
var _slow_windows := 0
var _fps_frames := 0
var _fps_time := 0.0

# Partida: estado, resultado y ayudas
var _audio: Audio
var _settings := {"sens": 0.5, "vol_master": 0.8, "vol_music": 0.55, "vol_sfx": 0.9, "vol_amb": 0.7}
var _welcomed := false        # ya se entró alguna vez a la sala (distingue cargar de reconectar)
var _votes := 0               # votos para otra ronda
var _connected := 1
var _lock := 0                # segundos que faltan para que los altares respondan
var _voted := false
var _result_kind := ""        # "victory" o "defeat" pendiente de mostrar
var _result_in := 0.0
var _reward_text := ""
var _stats := {"t0": 0.0, "secs": 0.0, "purified": 0, "kills": 0, "falls": 0, "left": 0}
var _respawn_at := 0.0
var _tips := {}               # ayudas de una sola vez ya mostradas
var _tip_clock := 0.0
var _free_mouse_t := 0.0
var _was_captured := false
var _captured_t := 0.0
var _prev_buttons := 0
var _net_note_t := 0.0
var _travelled := 0.0

# Historia: progreso de la sala, personaje con quien hablar y cinemáticas
var _story := 0               # banderas Story.F_* que dicta el servidor
var _npc: NpcView
var _npc_near := false
var _talking := ""            # id del personaje con el que se está hablando
var _cine := Cutscene.new()
var _cine_on := true          # ?cine=0 las desactiva (pruebas automáticas)
var _intro_after_cine := false

# Métricas de la sesión (beta): se envían a la API cada minuto y al terminar una ronda
var _m := {"sid": "", "fps": [], "ping_sum": 0.0, "ping_n": 0, "ping_max": 0.0, "load_ms": -1.0, "seconds": 0.0,
	"q_changes": 0, "wins": 0, "losses": 0, "falls": 0, "renderer": "", "report_in": 30.0}


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
	_hud.action.connect(_on_action)
	_hud.setting_changed.connect(_on_setting)
	_hud.dialogue_done.connect(_on_dialogue_done)
	_cine.finished.connect(_on_cine_finished)
	_npc = NpcView.new()
	add_child(_npc)
	_npc.setup("yaxche")
	_hud.set_overlay("Preparando el Claro de los Aluxes…")
	_audio = Audio.new()
	add_child(_audio)
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
		if q == "low" or q == "min":
			_set_quality(1 if q == "low" else 2)
			_quality_locked = q == "min"
		elif q == "high":
			_quality_locked = true
		_cine_on = int(_js("(window.ALUX && window.ALUX.cine === false) ? 0 : 1")) == 1
		_load_settings()
	_apply_settings()


## Dibuja una vez cada efecto y cada enemigo mientras aún está la pantalla de carga.
## Así sus shaders se compilan ahora y no en mitad del primer combate (evita tirones).
func _prewarm() -> void:
	var at := Vector3(0, 1.6, -2.0)
	Fx.slash(self, at, 0.0, 1.0, 2.0, Color(1, 1, 1, 0.02), 0.6)
	Fx.ring(self, at, 0.5, Color(1, 1, 1, 0.02), 0.6)
	Fx.burst(self, at, Color(1, 1, 1), 2, 0.5, 0.01, 0.5)
	Fx.number(self, at, " ", Color(1, 1, 1, 0.02))
	Fx.telegraph(self, at, 0.2, 0.5)
	Fx.pillar(self, at, Color(1, 1, 1, 0.02), 0.3, 0.1, 0.5)
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


## Calidad gráfica: 0 alta · 1 baja · 2 mínima. Se elige con ?q=high|low|min en la dirección
## o baja sola si el equipo no llega a 20 FPS (ver _auto_quality).
func _set_quality(level: int) -> void:
	if clampi(level, 0, 2) != _quality:
		_m.q_changes = int(_m.q_changes) + 1
	_quality = clampi(level, 0, 2)
	var vp := get_viewport()
	vp.msaa_3d = Viewport.MSAA_2X if _quality == 0 else Viewport.MSAA_DISABLED
	vp.scaling_3d_scale = [1.0, 0.6, 0.5][_quality]
	_builder.set_quality(_quality)


func _setup_input() -> void:
	var keys := {
		"fwd": [KEY_W, KEY_UP], "back": [KEY_S, KEY_DOWN], "left": [KEY_A, KEY_LEFT], "right": [KEY_D, KEY_RIGHT],
		"jump": [KEY_SPACE], "form1": [KEY_1], "form2": [KEY_2], "cam_l": [KEY_Q], "cam_r": [KEY_E],
		"atk1": [KEY_J], "atk2": [KEY_K], "atk3": [KEY_F, KEY_L], "perf": [KEY_F3], "help": [KEY_H], "quality": [KEY_F4],
		"recenter": [KEY_R], "menu": [KEY_ESCAPE, KEY_P], "accept": [KEY_ENTER, KEY_KP_ENTER],
	}
	for action in keys:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
		for k in keys[action]:
			var ev := InputEventKey.new()
			ev.physical_keycode = k
			InputMap.action_add_event(action, ev)


func _unhandled_input(event: InputEvent) -> void:
	# Cinemática: sólo se puede omitir (Enter o Esc); nada más llega al juego
	if _cine.active:
		if event.is_action_pressed("accept") or event.is_action_pressed("menu"):
			_cine.skip()
		return
	# Diálogo: cualquier tecla de acción o clic pasa a la línea siguiente; Esc lo cierra
	if _hud.dialogue_open():
		if event.is_action_pressed("menu"):
			_hud.hide_dialogue()
		elif event.is_action_pressed("accept") or event.is_action_pressed("atk3") or event.is_action_pressed("atk1") \
				or event.is_action_pressed("jump") or (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT):
			_hud.advance_dialogue()
			Audio.play("ui_click", null, -6.0)
		return
	# Con la bienvenida abierta, cualquier tecla de juego o clic empieza la partida
	if _hud.intro_open():
		if event is InputEventMouseButton:
			if event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
				_start_playing(true)
			return
		if not (event is InputEventKey and event.pressed and not event.echo):
			return
		_start_playing(false)
		if event.is_action("menu") or event.is_action("accept"):
			return
		# cualquier otra tecla empieza la partida y además hace lo suyo (moverse, transformarse…)
	# Junto a un personaje, F es "hablar" (en cualquier forma)
	if event.is_action_pressed("atk3") and _npc_near and _net == Net.PLAYING and not _hud.panel_open():
		_open_dialogue(_npc.npc_id)
		return
	if event is InputEventMouseButton:
		var captured := Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed and not captured and _net == Net.PLAYING:
				# clic fuera de un panel: lo cierra y vuelve al juego capturando el ratón
				if _hud.menu_open():
					_close_menu(false)
				if _hud.result_open():
					_hud.hide_result()
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
			var sens := _sensitivity()
			_cam_yaw -= event.relative.x * 0.0042 * sens
			_cam_pitch = clampf(_cam_pitch + event.relative.y * 0.0035 * sens, -0.15, 1.25)
	elif event.is_action_pressed("menu"):
		if _hud.help_open():
			_hud.toggle_help()
		elif _hud.menu_open():
			_close_menu(false)
		elif _net == Net.PLAYING:
			_open_menu()
	elif event.is_action_pressed("accept"):
		if _hud.result_open():
			_on_action("again" if _encounter == 2 else "retry")
		elif _hud.menu_open():
			_close_menu(false)
	elif event.is_action_pressed("recenter"):
		_recenter()
	elif event.is_action_pressed("form1"):
		_want_form = "alux"
	elif event.is_action_pressed("form2"):
		_want_form = "balam"
	elif event.is_action_pressed("perf"):
		_perf_on = _hud.toggle_perf()
	elif event.is_action_pressed("help"):
		_hud.toggle_help()
	elif event.is_action_pressed("quality"):
		_cycle_quality()


func _cycle_quality() -> void:
	# El jugador elige: se respeta su nivel y se apaga la bajada automática
	_quality_locked = true
	_set_quality((_quality + 1) % 3)
	_hud.hint("Calidad gráfica: " + QUALITY_NAMES[_quality], 3.0)
	_hud.update_menu(QUALITY_NAMES[_quality], _again_text())


# ───────────────────────── Menú, ajustes y paneles ─────────────────────────

## Multiplicador de la sensibilidad del ratón: 0.4× … 2.3×, con 1× en el centro del control.
func _sensitivity() -> float:
	return 0.42 * pow(5.6, float(_settings.sens))


func _load_settings() -> void:
	if not _is_web:
		return
	var raw: Variant = _js("(function(){try{return localStorage.getItem('alux_settings')||''}catch(e){return ''}})()")
	if typeof(raw) != TYPE_STRING or raw.is_empty():
		return
	var json := JSON.new()
	if json.parse(raw) == OK and typeof(json.data) == TYPE_DICTIONARY:
		for key in _settings.keys():
			var v: Variant = json.data.get(key)
			if typeof(v) == TYPE_FLOAT or typeof(v) == TYPE_INT:
				_settings[key] = clampf(float(v), 0.0, 1.0)


func _save_settings() -> void:
	if _is_web:
		_js("(function(){try{localStorage.setItem('alux_settings', %s)}catch(e){}})()" % JSON.stringify(JSON.stringify(_settings)))


func _apply_settings() -> void:
	_audio.set_volume("Master", float(_settings.vol_master))
	_audio.set_volume("Music", float(_settings.vol_music))
	_audio.set_volume("SFX", float(_settings.vol_sfx))
	_audio.set_volume("Ambience", float(_settings.vol_amb))


func _on_setting(key: String, value: float) -> void:
	_settings[key] = clampf(value, 0.0, 1.0)
	_apply_settings()
	_save_settings()
	if key == "vol_sfx" or key == "vol_master":
		Audio.play("ui_click")


func _again_text() -> String:
	if _encounter != 2:
		return ""
	if _voted:
		return "Quitar mi voto de otra ronda  (%d/%d)" % [_votes, _connected]
	return "Jugar otra ronda" if _connected <= 1 else "Jugar otra ronda  (%d/%d listos)" % [_votes, _connected]


func _open_menu() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_was_captured = false
	_mouse_l = false
	_mouse_r = false
	_hud.hide_result()
	_hud.show_menu(_settings, QUALITY_NAMES[_quality], _again_text())
	Audio.play("ui_abrir")


## `capture`: volver a capturar el ratón (sólo funciona dentro de un clic o una tecla).
func _close_menu(capture: bool) -> void:
	_hud.hide_menu()
	if capture and _net == Net.PLAYING:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _recenter() -> void:
	_cam_yaw = _pred.yaw
	_cam_pitch = 0.42
	_cam_dist = 7.0


func _exit_to_portal() -> void:
	_metrics_send(true)
	if _ws:
		_ws.close()
	if _is_web:
		_js("location.href = '/hub'")
	else:
		get_tree().quit()


func _start_playing(capture: bool) -> void:
	_hud.hide_intro()
	if capture and _net == Net.PLAYING:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	Audio.play("ui_click")
	_hud.hint("Ratón para mirar  ·  H muestra los controles  ·  Esc abre el menú", 6.0)
	_tip_clock = 0.0


# ───────────────────────── Historia: cinemáticas y diálogos ─────────────────────────

func _seen(key: String) -> bool:
	return _is_web and str(_js("(function(){try{return localStorage.getItem('alux_seen_%s')||''}catch(e){return ''}})()" % key)) == "1"


func _mark_seen(key: String) -> void:
	if _is_web:
		_js("(function(){try{localStorage.setItem('alux_seen_%s','1')}catch(e){}})()" % key)


## Reproduce una cinemática hecha en el motor. Las locales no detienen la partida de nadie:
## sólo dejan quieto a este jugador mientras la ve.
func _play_cutscene(id: String) -> void:
	if _cine.active or not Story.CUTSCENES.has(id):
		return
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_mouse_l = false
	_mouse_r = false
	_hud.hide_menu()
	var names := {}
	for npc in Story.NPCS:
		names[npc] = Story.NPCS[npc].name
	_cine.play(id, Story.CUTSCENES[id], _cam, _hud, names)


func _on_cine_finished(id: String, _skipped: bool) -> void:
	_mark_seen(id)
	if _intro_after_cine:
		_intro_after_cine = false
		_hud.show_intro()


func _open_dialogue(npc: String) -> void:
	var lines: Array = Story.dialogue(npc, _story, _encounter)
	if lines.is_empty():
		return
	var texts := []
	for line in lines:
		texts.append(str(line[1]))
	_talking = npc
	_mouse_l = false
	_mouse_r = false
	_hud.context_hint("")
	_hud.show_dialogue(str(Story.NPCS[npc].name), str(Story.NPCS[npc].title), texts, GOLD)
	Audio.play("ui_abrir")


## Al terminar de leer se avisa al servidor: es él quien anota el avance de la historia.
func _on_dialogue_done(completed: bool) -> void:
	var npc := _talking
	_talking = ""
	if completed and not npc.is_empty() and _ws != null and _net == Net.PLAYING:
		_ws.send_text(JSON.stringify({"t": "talk", "n": npc}))


## Botones de la interfaz (menú, resultado, bienvenida y pantallas de error).
func _on_action(id: String) -> void:
	Audio.play("ui_click")
	match id:
		"replay_intro":
			_close_menu(false)
			_play_cutscene("llamado")
		"start":
			_start_playing(true)
		"menu":
			if _hud.menu_open():
				_close_menu(false)
			elif _net == Net.PLAYING:
				_open_menu()
		"resume":
			_close_menu(true)
		"help":
			_hud.toggle_help()
		"recenter":
			_recenter()
			_close_menu(true)
		"quality":
			_cycle_quality()
		"again":
			# Voto para otra ronda: el servidor reinicia cuando votan todos los conectados
			if _encounter == 2 and _ws != null and _net == Net.PLAYING:
				_voted = not _voted
				_ws.send_text(JSON.stringify({"t": "again", "v": 1 if _voted else 0}))
				_hud.update_menu(QUALITY_NAMES[_quality], _again_text())
				if _voted and _connected > 1:
					_hud.set_result_note("Voto enviado  ·  esperando al resto del grupo")
				elif not _voted:
					_hud.set_result_note("")
		"retry", "close":
			_hud.hide_result()
			if _net == Net.PLAYING:
				Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		"reload":
			if _is_web:
				_js("location.reload()")
		"exit":
			_exit_to_portal()


## Ayuda que se muestra una sola vez por sesión.
func _tip(key: String, text: String, seconds := 7.0) -> void:
	if _tips.has(key):
		return
	_tips[key] = true
	_hud.hint(text, seconds)


# ───────────────────────── Red ─────────────────────────

func _js(code: String) -> Variant:
	return JavaScriptBridge.eval(code, true)


func _fatal(text: String, can_reload := false) -> void:
	_net = Net.FATAL
	if _ws:
		_ws.close()
	_ws = null
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_hud.hide_intro()
	_hud.hide_menu()
	_hud.hide_result()
	_hud.set_net("")
	_audio.set_music("")
	var actions := [["exit", "Volver al portal", true]]
	if can_reload and _is_web:
		actions.append(["reload", "Reintentar", false])
	_hud.set_overlay(text, actions)


func _retry(reason: String) -> void:
	_ws = null
	_retries += 1
	if _retries > 40 or (not _is_web and _cli_ticket.is_empty()):
		_fatal("No se pudo conectar con el servidor de juego.", true)
		return
	_retry_in = minf(8.0, 0.8 * pow(1.6, _retries - 1))
	_net = Net.WAIT
	if _welcomed:
		# Ya estaba jugando: el claro sigue a la vista y sólo se avisa de la reconexión
		_hud.set_net("bad" if _retries > 3 else "warn", "Reconectando…  intento %d" % _retries)
		if _retries == 1:
			_hud.banner("Se perdió la conexión  ·  reconectando", Color(1.0, 0.75, 0.4), 3.5)
	else:
		_hud.set_overlay("%s\nReintentando…  (intento %d)" % [reason, _retries])


func _poll_net(delta: float) -> void:
	match _net:
		Net.TICKET:
			var ticket := ""
			if _is_web:
				var err: Variant = _js("window.ALUX ? (window.ALUX.error || '') : 'no_config'")
				if typeof(err) == TYPE_STRING and not err.is_empty():
					if FATAL_CODES.has(err):
						_fatal(FATAL_CODES[err], RELOADABLE.has(err))
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
			if not _welcomed:
				_hud.set_overlay(("Conectando con la sala %s…" % _room) if not _room.is_empty() else "Conectando…")
			_ticket_wait = 0.0
			_silence = 0.0
		Net.CONNECTING, Net.HELLO, Net.PLAYING:
			_ws.poll()
			var st := _ws.get_ready_state()
			if st == WebSocketPeer.STATE_OPEN:
				if _net == Net.CONNECTING:
					_ws.send_text(JSON.stringify({"t": "hello", "v": PROTOCOL, "ticket": _ws.get_meta("ticket")}))
					_net = Net.HELLO
					if not _welcomed:
						_hud.set_overlay("Entrando al Claro de los Aluxes…")
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
			_prev_buttons = 0
			_voted = false
			if m.rejoin:
				_rejoins += 1
			if _welcomed:
				_hud.banner("Conexión recuperada", Color(0.6, 1.0, 0.85), 2.5)
				_hud.set_net("ok", "Conexión recuperada")
				_net_note_t = 3.0
			else:
				# Primera entrada de esta sesión: bienvenida con el objetivo y los controles
				_welcomed = true
				_metrics_begin()
				# La primera vez, la introducción del capítulo; después, directo a los controles
				if _cine_on and not _seen("llamado"):
					_intro_after_cine = true
					_play_cutscene("llamado")
				else:
					_hud.show_intro()
				_audio.loop("amb_selva", "Ambience", -4.0)
				_audio.loop("amb_brasero", "Ambience", -60.0)
			_audio.set_music("mus_emboscada" if _encounter == 1 else "mus_claro")
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
				_fatal(FATAL_CODES[code], RELOADABLE.has(code))
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
			av.is_local = slot == _my_slot
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
	_hud.set_team(_team)


func _apply_world(w: Array, instant := false) -> void:
	var open := int(w[0]) != 0
	var old_mask := _plates_mask
	var old_phase := _encounter
	if _encounter == 1 and _wave_left > 0:
		_stats.left = _wave_left   # último recuento antes de que el servidor retire la emboscada
	_plates_mask = int(w[1])
	_need = int(w[2])
	_encounter = int(w[3]) if w.size() > 3 else 0
	_wave_left = int(w[4]) if w.size() > 4 else 0
	_votes = int(w[7]) if w.size() > 7 else 0
	_connected = int(w[8]) if w.size() > 8 else 1
	_lock = int(w[9]) if w.size() > 9 else 0
	_story = int(w[10]) if w.size() > 10 else 0
	var talked := (_story & Story.F_TALKED) != 0
	_hud.set_npc_mark("" if talked else "yaxche", Story.npc_pos("yaxche"))
	for i in World.PLATES.size():
		var on := (_plates_mask & (1 << i)) != 0
		_builder.set_plate(i, on)
		if not instant and on != ((old_mask & (1 << i)) != 0):
			var pp := World.plate_pos(i)
			Audio.play("altar_on" if on else "altar_off", pp)
			if on:
				Fx.ring(self, pp + Vector3(0, 0.05, 0), World.PLATE_R + 0.4, JADE, 0.5)
	if _encounter != old_phase:
		_on_phase(old_phase, _encounter, instant)
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
	_brazier_ready = w.size() <= 6 or int(w[6]) != 0
	_hud.set_altars(_encounter == 0, _plates_mask)
	if _encounter == 1:
		_hud.set_objective("¡Emboscada!  Quedan %d enemigo%s" % [_wave_left, "" if _wave_left == 1 else "s"], "alert",
			"Véncelos o purifícalos  ·  si cae todo el grupo, se pierde" if _connected > 1 else "Véncelos o purifícalos  ·  si caes, se pierde")
	elif _encounter == 2:
		var detail := "Esc: jugar otra ronda o salir al portal"
		if _votes > 0 and _connected > 1:
			detail = "Otra ronda: %d de %d listos  ·  Esc para %s" % [_votes, _connected, "quitar tu voto" if _voted else "unirte"]
		_hud.set_objective("Santuario liberado", "success", detail)
		_hud.update_menu(QUALITY_NAMES[_quality], _again_text())
		if _hud.result_open() and _votes > 0 and _connected > 1:
			_hud.set_result_note("Otra ronda: %d de %d listos" % [_votes, _connected])
	elif _encounter == 3:
		_hud.set_objective("Derrota  ·  el santuario se selló de nuevo", "alert",
			("Los altares despiertan en %d s" % _lock) if _lock > 0 else "Reúnanse en el brasero")
	elif _lock > 0:
		_hud.set_objective("Nueva ronda", "wait", "Los altares despiertan en %d s" % _lock)
	elif not talked:
		# Primer objetivo del capítulo: escuchar a la abuela del claro
		_hud.set_objective("Habla con Chiich Yaxché", "goal", "Te espera junto al brasero  ·  acércate y pulsa F")
	else:
		var here := Vector2(_pred.pos.x, _pred.pos.z)
		var on_plate := false
		for i in World.PLATES.size():
			var pp := World.plate_pos(i)
			if Vector2(pp.x, pp.z).distance_to(here) < World.PLATE_R:
				on_plate = true
		if _need <= 1:
			_hud.set_objective("Pisa un altar para abrir el santuario", "goal",
				"Los altares están marcados en la brújula  ·  puedes invitar con el código de sala")
		elif on_plate and pressed < _need:
			_hud.set_objective("Quédate en el altar  (%d/%d)" % [pressed, _need], "wait", "Esperando a que el grupo pise los demás altares")
		else:
			_hud.set_objective("Pisen %d altares al mismo tiempo  (%d/%d)" % [_need, pressed, _need], "goal",
				"Un alux en cada altar  ·  están marcados en la brújula")


## Cambio de fase de la partida: 0 explorar · 1 emboscada · 2 victoria · 3 derrota.
## `instant` = se entra a una sala que ya estaba así (no se repiten avisos ni paneles).
func _on_phase(from: int, to: int, instant: bool) -> void:
	_audio.set_music("mus_emboscada" if to == 1 else "mus_claro")
	_voted = false
	if to == 1:
		_stats = {"t0": _time, "secs": 0.0, "purified": 0, "kills": 0, "falls": 0, "left": 0}
		_reward_text = ""
		_hud.hide_result()
		return
	if instant:
		return
	if to == 2 and from == 1:
		_stats.secs = _time - float(_stats.t0)
		_result_kind = "victory"
		_result_in = 1.6
		_m.wins = int(_m.wins) + 1
		_m.report_in = 3.0
	elif to == 3:
		_stats.secs = _time - float(_stats.t0)
		_m.losses = int(_m.losses) + 1
		_m.report_in = 3.0
		_result_kind = "defeat"
		_result_in = 1.0
	elif to == 0:
		_result_kind = ""
		if from == 2:
			_hud.hide_result()
			_hud.hide_menu()
			_hud.banner("¡Nueva ronda!", Color(0.6, 1.0, 0.85), 3.0)
			Audio.play("objetivo")
		elif from == 3:
			_hud.hint("Los altares vuelven a responder: a intentarlo de nuevo", 5.0)
			Audio.play("objetivo")


func _show_result() -> void:
	var kind := _result_kind
	_result_kind = ""
	if (kind == "victory" and _encounter != 2) or (kind == "defeat" and _encounter != 3 and _lock <= 0):
		return
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_was_captured = false
	_mouse_l = false
	_mouse_r = false
	_hud.hide_menu()
	var secs := int(float(_stats.secs))
	var time_text := "%d:%02d" % [secs / 60, secs % 60]
	if kind == "victory":
		var stats := [["Tiempo", time_text], ["Criaturas purificadas", str(_stats.purified)],
			["Enemigos vencidos", str(_stats.kills)], ["Caídas del grupo", str(_stats.falls)]]
		if not _reward_text.is_empty():
			stats.append(["Sello del Claro", _reward_text])
		_hud.show_result("victory", "¡VICTORIA!", "El santuario está libre y el claro vuelve a respirar.", stats, [
			["again", "Jugar otra ronda", true], ["close", "Seguir explorando", false], ["exit", "Salir al portal", false]])
	else:
		_hud.show_result("defeat", "DERROTA", "Todo el grupo cayó y el santuario se selló de nuevo. Reúnanse en el brasero, cúrense con F y vuelvan a pisar los altares.", [
			["Tiempo", time_text], ["Enemigos que quedaban", str(_stats.left)], ["Caídas del grupo", str(_stats.falls)]], [
			["retry", "Reintentar", true], ["exit", "Salir al portal", false]])


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
		var fallen := (int(state[7]) & 8) != 0
		_team[slot] = {"hp": float(p[3]), "dead": fallen, "form": Sim.FORM_IDS[clampi(int(state[5]), 0, Sim.FORM_IDS.size() - 1)]}
		var av: Avatar = _avatars.get(slot)
		if av != null:
			av.set_dead(fallen)
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
	_hud.set_team(_team)
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
		"story":
			if str(m.get("k", "")) == "talked":
				Audio.play("objetivo")
				_hud.hint("%s habló con Chiich Yaxché  ·  nueva misión: los altares" % str(m.get("by", "Un alux")), 5.0)
		"gate_open":
			_hud.banner("¡El santuario se abre!", Color(0.5, 1.0, 0.85), 3.0)
			Audio.play("santuario_abre", Vector3(World.SANCTUARY.x - 7.0, 1.0, World.SANCTUARY.y), 3.0)
		"reward":
			if not bool(m.get("saved", false)):
				_reward_text = "no se pudo guardar"
				_hud.toast("Sello del Claro\nno se pudo guardar el progreso")
			elif bool(m.get("new", false)):
				_reward_text = "guardado en tu perfil"
				_hud.toast("Sello del Claro\nguardado en tu perfil")
			else:
				_reward_text = "ya lo tenías"
			if _hud.result_open() and _encounter == 2:
				_result_kind = "victory"   # se vuelve a pintar el panel con el dato del sello
				_result_in = 0.01


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
	var snd: String = {"bolt": "chispa", "claw": "garras", "charge_start": "zarpazo_carga", "charged": "zarpazo",
		"pounce": "salto_jaguar", "pounce_land": "salto_impacto", "dodge": "esquiva"}.get(kind, "")
	if not snd.is_empty():
		Audio.play(snd, pos, 0.0 if slot == _my_slot else -5.0)
	match kind:
		"claw":
			var ab: Dictionary = Defs.FORMS.balam.primary
			Fx.claws(self, pos + Vector3(0, 0.8, 0), yaw, ab.range, ab.arc, Color(1.0, 0.75, 0.3))
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
			if int(ev[5]) != 0:
				Fx.ring(self, Vector3(ev[2], float(ev[3]) - 0.5, ev[4]), 1.1, JADE, 0.3)
				Audio.play("chispa_impacto", Vector3(ev[2], ev[3], ev[4]), -3.0)
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
					Fx.burst(self, view.global_position + Vector3(0, 0.8, 0), Color(1.0, 0.9, 0.6), 10 if mine else 6, 3.0, 0.05, 0.3)
					Audio.play("golpe", view.global_position, 0.0 if mine else -6.0, 0.12)
					if mine:
						# mi golpe entró: anillo de impacto y un pequeño temblor de cámara
						Fx.ring(self, view.global_position + Vector3(0, 0.1, 0), 1.0, GOLD, 0.22)
						_shake = maxf(_shake, 0.09 if int(ev[3]) < 25 else 0.18)
						_tip("purify", "Deja a las criaturas con poca vida y purifícalas con F siendo alux", 6.0)
			else:
				var slot := int(ev[2])
				var av: Avatar = _avatars.get(slot)
				if av != null:
					av.play_action("hit")
					Fx.number(self, av.global_position + Vector3(0, 1.8, 0), "-%d" % int(ev[3]), Color(1.0, 0.35, 0.35), slot == _my_slot)
					Fx.burst(self, av.global_position + Vector3(0, 0.9, 0), Color(1.0, 0.3, 0.3), 8, 3.0, 0.06, 0.35)
					Audio.play("dano", av.global_position, 0.0 if slot == _my_slot else -8.0)
				if slot == _my_slot:
					_hud.hurt()
					_shake = 0.3
					if int(ev[4]) <= 40 and int(ev[4]) > 0:
						_tip("brazier", "Con poca vida: toca el brasero de la plaza (F como alux) para curar al grupo", 7.0)
		"die":
			if str(ev[1]) == "e":
				var view: EnemyView = _enemies.get(int(ev[2]))
				if view != null:
					view.die(int(ev[3]) != 0)
					Audio.play("purificar" if int(ev[3]) != 0 else "enemigo_muere", view.global_position)
					if int(ev[3]) != 0:
						Fx.number(self, view.global_position + Vector3(0, 1.8, 0), "¡Purificada!", Color(0.6, 1.0, 0.8), true)
				# (la última baja llega en el mismo estado que ya marca la victoria)
				if _encounter == 1 or _result_kind == "victory":
					if int(ev[3]) != 0:
						_stats.purified = int(_stats.purified) + 1
					else:
						_stats.kills = int(_stats.kills) + 1
			else:
				var av: Avatar = _avatars.get(int(ev[2]))
				_stats.falls = int(_stats.falls) + 1
				if av != null:
					av.set_dead(true)
					Fx.burst(self, av.global_position + Vector3(0, 0.6, 0), av.color, 18, 4.0)
					Audio.play("caida", av.global_position, -4.0 if int(ev[2]) == _my_slot else -10.0)
				if int(ev[2]) == _my_slot:
					_m.falls = int(_m.falls) + 1
					_respawn_at = _time + (Defs.RESPAWN_TIME_ENCOUNTER if _encounter == 1 else Defs.RESPAWN_TIME)
				elif av != null and _encounter == 1:
					_hud.hint("%s ha caído  ·  volverá junto al brasero" % av.player_name, 3.5)
		"respawn":
			var av: Avatar = _avatars.get(int(ev[1]))
			if av != null:
				av.set_dead(false)
			var c: Vector2 = Defs.CHECKPOINTS[clampi(1 if _encounter == 2 else 0, 0, 1)]
			var at := Vector3(c.x, World.terrain_h(c.x, c.y), c.y)
			Fx.ring(self, at, 2.4, JADE, 0.6)
			Fx.pillar(self, at, JADE, 8.0, 1.4, 0.8)
			Audio.play("reaparecer", at, 0.0 if int(ev[1]) == _my_slot else -6.0)
			if int(ev[1]) == _my_slot and _encounter == 1:
				_hud.banner("¡De vuelta! Regresa con tu grupo", Color(0.6, 1.0, 0.85), 2.5)
		"heal":
			Fx.number(self, _avatar_pos(int(ev[1])) + Vector3(0, 1.9, 0), "+%d" % int(ev[2]), Color(0.5, 1.0, 0.6))
			Fx.heal(self, _avatar_pos(int(ev[1])))
			Audio.play("curar", _avatar_pos(int(ev[1])), 0.0 if int(ev[1]) == _my_slot else -8.0)
			if int(ev[1]) == _my_slot:
				_hud.healed()
		"evade":
			Fx.number(self, _avatar_pos(int(ev[1])) + Vector3(0, 1.9, 0), "¡Esquiva!", Color(0.6, 0.95, 1.0))
		"eatk":
			var view: EnemyView = _enemies.get(int(ev[1]))
			if view != null:
				view.slam()
				Audio.play("enemigo_golpe", view.global_position)
		"brazier":
			Fx.ring(self, Vector3(0, 0.1, 0), Defs.BRAZIER_RANGE + 2.0, Color(1.0, 0.75, 0.3), 0.7)
			Fx.burst(self, Vector3(0, 1.4, 0), Color(1.0, 0.8, 0.35), 26, 5.0, 0.08, 0.9)
			if int(ev[1]) == _my_slot:
				_hud.hint("El brasero cura al grupo  ·  tarda %d s en volver a encenderse" % int(Defs.BRAZIER_CD), 4.0)
		"enc":
			match str(ev[1]):
				"start":
					_hud.banner("¡Emboscada!", Color(1.0, 0.45, 0.6), 3.5)
					Audio.play("emboscada", null, -3.0, 0.0)
					_tip("balam", "Pulsa 2 para ser Balam y pelear cuerpo a cuerpo  ·  1 vuelve a alux", 7.0)
				"clear":
					_hud.banner("¡Emboscada superada!", GOLD, 3.0)
					Audio.play("victoria", null, 0.0, 0.0)
				"fail":
					_respawn_at = minf(_respawn_at, _time + Defs.RESPAWN_TIME_DEFEAT)
					_hud.banner("El grupo ha caído", Color(1.0, 0.5, 0.5), 3.0)
					Audio.play("derrota", null, 0.0, 0.0)


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
	var jump := Input.is_action_pressed("jump")
	# Con la bienvenida, el menú o un resultado abiertos el personaje se queda quieto
	# (se sigue enviando la entrada vacía: mantiene viva la conexión)
	if _hud.panel_open():
		move = Vector2.ZERO
		buttons = 0
		jump = false
		_want_form = ""
	if _npc_near:
		buttons &= ~Sim.A_SPECIAL   # junto a un personaje, F es "hablar", no una habilidad
	_explain_denied(buttons)
	_prev_buttons = buttons
	_seq += 1
	var inp := {
		"t": "in", "s": _seq,
		"mx": snappedf(move.x, 0.001), "mz": snappedf(move.y, 0.001),
		"j": 1 if jump else 0,
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


## Si el jugador pulsa una habilidad que ahora no puede usar, se le dice por qué.
func _explain_denied(buttons: int) -> void:
	var rising := buttons & ~_prev_buttons
	if _pred.dead:
		return
	var form: Dictionary = Defs.FORMS[_pred.form]
	if rising != 0:
		for def in [[1, Sim.A_SECONDARY, "secondary", _pred.cd2], [2, Sim.A_SPECIAL, "special", _pred.cd3]]:
			if (rising & int(def[1])) == 0:
				continue
			var ab: Dictionary = form[def[2]]
			if _pred.energy < float(ab.get("cost", 0.0)):
				_hud.deny(def[0], "Falta energía para %s" % ab.name)
				Audio.play("sin_energia")
			elif int(def[3]) > Sim.ticks(0.3):
				_hud.deny(def[0], "")
				Audio.play("sin_energia", null, -6.0)
			elif str(ab.kind) == "interact" and not _can_touch_something():
				_hud.hint("Aquí no hay nada que tocar  ·  F purifica criaturas débiles y enciende el brasero", 2.5)
	if not _want_form.is_empty() and _want_form != _pred.form:
		if not _unlocked.has(_want_form):
			_hud.hint("Aún no tienes esa transformación", 2.5)
			Audio.play("sin_energia")
		elif _pred.form_cd > 0:
			_hud.hint("La transformación se está recargando", 1.6)
			Audio.play("sin_energia", null, -6.0)


func _can_touch_something() -> bool:
	var here := Vector2(_pred.pos.x, _pred.pos.z)
	if (here - Defs.BRAZIER).length() < Defs.BRAZIER_RANGE + 0.5:
		return true
	var reach: float = float(Defs.FORMS.alux.special.range) + 1.0
	for id in _enemies:
		var v: EnemyView = _enemies[id]
		if not v.dying and Vector2(v.global_position.x - here.x, v.global_position.z - here.y).length() < reach:
			return true
	return false


# ───────────────────────── Presentación ─────────────────────────

func _process(delta: float) -> void:
	_time += delta
	_poll_net(delta)

	# Esc en el navegador suelta el ratón sin avisar al juego: se toma como "abrir el menú"
	# (sólo si la captura llegó a durar: si el navegador la rechaza, no se abre nada)
	var captured := Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
	if captured:
		_captured_t += delta
		if _captured_t > 0.5:
			_was_captured = true
	else:
		_captured_t = 0.0
		if _was_captured:
			_was_captured = false
			_mouse_l = false
			_mouse_r = false
			if _net == Net.PLAYING and not _hud.panel_open() and not _hud.help_open():
				_open_menu()

	if _result_in > 0.0:
		_result_in -= delta
		if _result_in <= 0.0 and not _result_kind.is_empty():
			_show_result()
	if _net_note_t > 0.0:
		_net_note_t -= delta
		if _net_note_t <= 0.0:
			_hud.set_net("")
	elif _net == Net.PLAYING:
		# Aviso de conexión sólo cuando hay algo que decir
		if _silence > 2.0:
			_hud.set_net("warn", "Sin respuesta del servidor…")
		elif _ping_ms > 350.0:
			_hud.set_net("warn", "Conexión lenta  ·  %d ms" % int(_ping_ms))
		else:
			_hud.set_net("")

	if _debug_on:
		# Sólo en pruebas automáticas: permite orientar la cámara desde la página
		var forced := str(_js("window.ALUX_CAM_YAW === undefined ? '' : String(window.ALUX_CAM_YAW)"))
		if forced.is_valid_float():
			_cam_yaw = forced.to_float()
		var act := str(_js("window.ALUX_ACTION || ''"))
		if not act.is_empty():
			_js("window.ALUX_ACTION = ''")
			_on_action(act)   # (pruebas) pulsa un botón de la interfaz por su id
		var q := str(_js("window.ALUX_SET_QUALITY || ''"))
		if q == "low" or q == "high" or q == "min":
			_js("window.ALUX_SET_QUALITY = ''")
			_quality_locked = true
			_set_quality({"high": 0, "low": 1, "min": 2}[q])
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
		_hud.set_death(_pred.dead, _respawn_at - _time)
		_hud.set_low_hp(_hp < 30.0 and not _pred.dead)
		_hud.set_compass(_cam_yaw, me.global_position)
		_update_hints(delta)
		_npc_near = not _pred.dead and _npc.distance_to(me.global_position) < _npc.talk_range
		_npc.update_view(delta, _npc_near, me.global_position, _hud.dialogue_open())
		_audio.listener = me.global_position
		_audio.set_loop_distance("amb_brasero", Vector3(0, 1.2, 0), -3.0)
		_update_onboarding(delta, captured)

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

	# Puerta y sello del santuario, glifo, fuego
	if _gate_open and _gate_anim < 1.0:
		_gate_anim = minf(1.0, _gate_anim + delta * 0.8)
	_builder.update(_time, delta, _gate_anim)

	if not _cine.process(delta):
		_update_camera()
	_update_perf(delta)
	_debug_export(delta)


## Ayudas del primer minuto y recordatorio del ratón. No insisten: cada una sale una vez.
func _update_onboarding(delta: float, captured: bool) -> void:
	if _hud.panel_open():
		return
	_tip_clock += delta
	var step := Vector2(_pred.pos.x - _prev_pos.x, _pred.pos.z - _prev_pos.z).length()
	_travelled += step
	if _tip_clock > 7.0 and _travelled < 2.0:
		_tip("move", "Muévete con W A S D  ·  Espacio salta", 6.0)
	if _encounter == 0 and (_story & Story.F_TALKED) == 0 and _tip_clock > 12.0:
		_tip("yaxche", "Chiich Yaxché te espera junto al brasero: acércate y pulsa F para hablar", 7.0)
	if _travelled > 12.0 and _encounter == 0 and _tip_clock > 9.0 and (_story & Story.F_TALKED) != 0:
		_tip("altars", "Los altares brillan en la brújula de arriba: camina hacia uno y quédate encima", 7.0)
	if _encounter == 0 and not _tips.has("fight"):
		for id in _enemies:
			var v: EnemyView = _enemies[id]
			if not v.dying and v.global_position.distance_to(_pred.pos) < 11.0:
				_tip("fight", "Clic lanza chispas de jade  ·  clic derecho esquiva  ·  2 te convierte en Balam", 7.0)
				break
	# Recordatorio del ratón: sólo si lleva un rato moviéndose sin capturarlo
	if captured:
		_free_mouse_t = 0.0
	elif step > 0.01:
		_free_mouse_t += delta
		if _free_mouse_t > 6.0:
			_free_mouse_t = -30.0
			_hud.hint("Haz clic en el juego para mirar con el ratón  ·  Q y E también giran la cámara", 5.0)


## Consejos contextuales: qué se puede tocar aquí y con qué forma.
func _update_hints(delta: float) -> void:
	_hint_in -= delta
	if _hint_in > 0.0:
		return
	_hint_in = 0.25
	var here := Vector2(_pred.pos.x, _pred.pos.z)
	var text := ""
	if _npc_near:
		text = "" if _hud.dialogue_open() else "F  ·  Hablar con %s" % Story.NPCS[_npc.npc_id].name
	elif not _pred.dead:
		var can_touch := _pred.form == "alux"
		for id in _enemies:
			var v: EnemyView = _enemies[id]
			if not v.purifiable():
				continue
			if Vector2(v.global_position.x - here.x, v.global_position.z - here.y).length() < 3.6:
				text = "F  ·  Purificar a la criatura" if can_touch else "1  ·  Vuelve a ser alux para purificarla"
		if text.is_empty() and _brazier_ready and _hp < Defs.MAX_HP - 1.0 and (here - Defs.BRAZIER).length() < Defs.BRAZIER_RANGE:
			text = "F  ·  Tocar el brasero para curar al grupo" if can_touch else "1  ·  Vuelve a ser alux para tocar el brasero"
	_hud.context_hint(text)


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
		"tris": RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME),
		"objects": RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_OBJECTS_IN_FRAME),
		"enemies": _enemies.size(), "pending": _pending.size(),
	}


## Calidad automática: si durante dos ventanas seguidas de 4 s no se llega a 20 FPS,
## se pasa a calidad baja. (?q=high lo desactiva.)
func _auto_quality(delta: float) -> void:
	if _quality >= 2 or _quality_locked or _net != Net.PLAYING:
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
		_slow_windows = 0
		_set_quality(_quality + 1)
		_hud.hint("Calidad gráfica reducida para ir más fluido", 5.0)


# ───────────────────────── Métricas de sesión ─────────────────────────

func _metrics_begin() -> void:
	if not _is_web:
		return
	_m.sid = str(_js("(self.crypto && crypto.randomUUID) ? crypto.randomUUID() : ''"))
	_m.load_ms = float(_js("Math.round(performance.now())"))   # desde abrir la página hasta estar dentro de la sala
	_m.renderer = str(_js("(function(){try{var c=document.createElement('canvas');var g=c.getContext('webgl2')||c.getContext('webgl');" +
		"var e=g.getExtension('WEBGL_debug_renderer_info');return String(e?g.getParameter(e.UNMASKED_RENDERER_WEBGL):g.getParameter(g.RENDERER))}catch(e){return ''}})()"))


## Una muestra por segundo mientras se juega (la llama _update_perf).
func _metrics_sample() -> void:
	if _net != Net.PLAYING or str(_m.sid).is_empty():
		return
	_m.seconds = float(_m.seconds) + 1.0
	var fps: Array = _m.fps
	if fps.size() < 7200:
		fps.append(Engine.get_frames_per_second())
	if _ping_ms >= 0.0:
		_m.ping_sum = float(_m.ping_sum) + _ping_ms
		_m.ping_n = int(_m.ping_n) + 1
		_m.ping_max = maxf(float(_m.ping_max), _ping_ms)
	_m.report_in = float(_m.report_in) - 1.0
	if float(_m.report_in) <= 0.0:
		_m.report_in = 60.0
		_metrics_send(false)


## Envía el resumen de la sesión a la API (una fila por sesión, que se va actualizando).
func _metrics_send(final: bool) -> void:
	if not _is_web or str(_m.sid).is_empty():
		return
	var fps: Array = (_m.fps as Array).duplicate()
	if fps.is_empty():
		return
	fps.sort()
	var sum := 0.0
	for f in fps:
		sum += float(f)
	var body := {
		"sid": _m.sid, "room": _room, "quality": ["high", "low", "min"][_quality], "qualityAuto": not _quality_locked,
		"qualityChanges": _m.q_changes,
		"fpsAvg": snappedf(sum / float(fps.size()), 0.1), "fpsMin": fps[int(float(fps.size()) * 0.05)],   # percentil 5
		"pingAvg": snappedf(float(_m.ping_sum) / float(_m.ping_n), 0.1) if int(_m.ping_n) > 0 else null,
		"pingMax": snappedf(float(_m.ping_max), 0.1) if int(_m.ping_n) > 0 else null,
		"loadMs": _m.load_ms, "seconds": _m.seconds,
		"heapMb": _perf_stats().heap, "memMb": _perf_stats().mem,
		"rejoins": _rejoins, "wins": _m.wins, "losses": _m.losses, "falls": _m.falls, "players": _connected,
		"renderer": _m.renderer, "build": Hud.BUILD, "final": final,
		"audio": {"master": _settings.vol_master, "music": _settings.vol_music, "sfx": _settings.vol_sfx, "amb": _settings.vol_amb},
	}
	# El navegador añade resolución y estado del audio; keepalive deja terminar el envío al salir de la página
	_js("(function(b){try{b.viewport=innerWidth+'x'+innerHeight;b.dpr=devicePixelRatio||1;" +
		"b.audio.context=(window.ALUX_AUDIO&&ALUX_AUDIO.state)||'';" +
		"fetch('/api/v1/telemetry',{method:'POST',keepalive:true,credentials:'same-origin'," +
		"headers:{'content-type':'application/json','x-alux-csrf':'1'},body:JSON.stringify(b)}).catch(function(){})}catch(e){}})(%s)" % JSON.stringify(body))


func _update_perf(delta: float) -> void:
	_auto_quality(delta)
	_perf_in -= delta
	if _perf_in > 0.0:
		return
	_snap_rate = float(_snaps)
	_snaps = 0
	_perf_in = 1.0
	_metrics_sample()
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
		"perf": _perf_stats(), "quality": ["high", "low", "min"][_quality],
		"story": _story, "npc_near": _npc_near, "cine": _cine.id if _cine.active else "",
		"ui": {"intro": _hud.intro_open(), "menu": _hud.menu_open(), "result": _hud.result_open(), "help": _hud.help_open(),
			"dialog": _hud.dialogue_open(), "cine": _hud.cine_open(),
			"objective": _hud.objective_text(), "captured": Input.mouse_mode == Input.MOUSE_MODE_CAPTURED},
		"votes": _votes, "connected": _connected, "lock": _lock, "voted": _voted,
		"stats": _stats, "audio": _audio.loaded(), "music": _audio.music(), "settings": _settings,
		"metrics": {"sid": _m.sid, "seconds": _m.seconds, "samples": (_m.fps as Array).size(), "loadMs": _m.load_ms},
	}
	_js("window.__aluxState = %s" % JSON.stringify(state))
