extends Node3D
## Cliente de ALUX: conexión, entrada, predicción local y presentación.
## El cliente nunca decide resultados: manda intenciones y dibuja lo que
## el servidor confirma, prediciendo sólo el movimiento de su propio personaje.

const Customizer := preload("res://scripts/client/customizer.gd")
const Look := preload("res://scripts/shared/look_def.gd")
const Sim := preload("res://scripts/shared/sim.gd")
const World := preload("res://scripts/shared/world_def.gd")
const Defs := preload("res://scripts/shared/combat_def.gd")
const Avatar := preload("res://scripts/client/avatar.gd")
const EnemyView := preload("res://scripts/client/enemy_view.gd")
const BossDef := preload("res://scripts/shared/boss_def.gd")
const WorldBuilder := preload("res://scripts/client/world_builder.gd")
const Hud := preload("res://scripts/client/hud.gd")
const Fx := preload("res://scripts/client/fx.gd")
const Audio := preload("res://scripts/client/audio.gd")
const Story := preload("res://scripts/shared/story_def.gd")
const Cutscene := preload("res://scripts/client/cinematics/cutscene.gd")
const VideoBridge := preload("res://scripts/client/cinematics/video_bridge.gd")
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
const MAGENTA := Color(1.0, 0.2, 0.61)
const QUALITY_NAMES := ["alta", "baja", "mínima"]
## Errores con los que tiene sentido reintentar recargando (los demás sólo ofrecen volver al portal)
const RELOADABLE := ["version", "server_full", "rate_limited"]

enum Net { TICKET, CONNECTING, HELLO, PLAYING, WAIT, FATAL, CUSTOM }   # CUSTOM: sólo el personalizador, sin sala

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
var _boss: BossView     # Nojoch Tuunich (lo crea la primera instantánea que trae su estado)
var _boss_state: Array = []
var _arena: BossArena  # anclas, columnas, cadenas y glifos del combate con el guardián
var _talk_npc := ""    # personaje con el que se puede hablar ahora mismo ("" si ninguno)
var _touch_sfx := 0.0
var _fs_poll := 0.0
var _custom: Customizer        # personalizador 3D del alux
var _custom_only := false     # el juego se abrió sólo para personalizar (desde el portal)
var _me_poll := 0.0           # espera del perfil para el personalizador sin sala
var _cine_staged := false
var _motes_in := 0.0
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
var _settings := {"sens": 0.5, "vol_master": 0.9, "vol_music": 0.7, "vol_sfx": 0.9, "vol_amb": 0.8,
	"vol_ui": 0.8, "vol_cine": 0.9, "shake": 0.6}
var _spawn_sound_t := -10.0
var _breath_at := 0.0
var _online := {}           # id de jugador -> conectado (para avisar de quién entra y quién se va)
var _amb_in := 0.0          # cuenta atrás hasta la siguiente revisión de ambientes y música
var _danger_until := 0.0    # hasta cuándo se considera que hay peligro cerca (música de tensión)
var _far_from_claro := false
var _sound_test_in := 0.0   # cuenta atrás hasta medir el resultado de «Probar sonido»
var _welcomed := false        # ya se entró alguna vez a la sala (distingue cargar de reconectar)
var _votes := 0               # votos para otra ronda
var _connected := 1
var _lock := 0                # segundos que faltan para que los altares respondan
var _voted := false
var _result_kind := ""        # "victory", "defeat" o "freed" pendiente de mostrar
var _feather_text := ""       # qué pasó con la Pluma de Jade ("" si aún no se sabe)
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
var _frozen := false          # hay una cinemática compartida: la sala está en pausa
var _skip_votes := 0
var _skip_voted := false
var _video := VideoBridge.new()   # vídeos de las cinemáticas (los reproduce el navegador)
var _cine_phase := 0          # Story.CINE_*: fase de la cinemática compartida, según el servidor
var _prep := {}               # preparación en curso: {id, t, wait, sent}
var _cine_out := 0.0          # segundos hasta volver a descubrir el juego tras una cinemática
var _video_release_in := 0.0  # segundos hasta soltar los decodificadores de vídeo
var _cine_stats := {"video": 0, "engine": 0, "fallbacks": 0, "skipped": 0}
## Playtest del jefe: lo que se mide de cada jugador durante el combate (docs/PLAYTEST.md)
var _pt := {"secs": [0, 0, 0], "fails": [0, 0, 0], "dmg": 0, "falls": 0, "balam": 0, "freed": false, "denied": 0}

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
	_cine.video = _video
	# Mientras un vídeo tapa el juego no hace falta dibujar el mundo
	_cine.covered.connect(func(on: bool) -> void: get_viewport().disable_3d = on)
	_npc = NpcView.new()
	add_child(_npc)
	_npc.setup("yaxche")
	_hud.set_overlay("Preparando el Claro de los Aluxes…")
	_audio = Audio.new()
	add_child(_audio)
	_custom = Customizer.new()
	add_child(_custom)
	_custom.saved.connect(_on_look_saved)
	_custom.closed.connect(_on_custom_closed)
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
		if str(_js("(window.ALUX && window.ALUX.mode) || ''")) == "alux":
			_begin_custom_only()
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
	if _custom.active or _net == Net.CUSTOM:
		return   # el personalizador lleva su propia entrada
	# Cinemática: sólo se puede omitir (Enter o Esc); nada más llega al juego
	if _cine.active:
		if event.is_action_pressed("accept") or event.is_action_pressed("menu"):
			if _cine.shared:
				# Compartida: omitirla es un voto; decide el servidor cuando vota la mayoría
				if not _skip_voted and _ws != null and _net == Net.PLAYING and _cine_phase == Story.CINE_PLAYING:
					_skip_voted = true
					_ws.send_text(JSON.stringify({"t": "skip"}))
					Audio.play("ui_click")
			else:
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
		_open_dialogue(_talk_npc)
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
			# Enter sigue la aventura (el santuario, el guardián); otra ronda se pide con su botón
			_on_action("close" if _encounter == 2 else "retry")
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
	var stored := {}
	var raw: Variant = _js("(function(){try{return localStorage.getItem('alux_settings')||''}catch(e){return ''}})()")
	if typeof(raw) == TYPE_STRING and not raw.is_empty():
		var json := JSON.new()
		if json.parse(raw) == OK and typeof(json.data) == TYPE_DICTIONARY:
			stored = json.data
	for key in _settings.keys():
		var v: Variant = stored.get(key)
		if typeof(v) == TYPE_FLOAT or typeof(v) == TYPE_INT:
			_settings[key] = clampf(float(v), 0.0, 1.0)
	# Quien pide menos movimiento en su sistema empieza sin sacudidas de cámara (puede subirlas)
	if not stored.has("shake") and bool(_js("(function(){try{return !!(window.matchMedia&&matchMedia('(prefers-reduced-motion: reduce)').matches)}catch(e){return false}})()")):
		_settings.shake = 0.0


func _save_settings() -> void:
	if _is_web:
		_js("(function(){try{localStorage.setItem('alux_settings', %s)}catch(e){}})()" % JSON.stringify(JSON.stringify(_settings)))


func _apply_settings() -> void:
	_audio.set_volume("Master", float(_settings.vol_master))
	_audio.set_volume("Music", float(_settings.vol_music))
	_audio.set_volume("SFX", float(_settings.vol_sfx))
	_audio.set_volume("Ambience", float(_settings.vol_amb))
	_audio.set_volume("UI", float(_settings.vol_ui))
	_audio.set_volume("Cinematics", float(_settings.vol_cine))


func _on_setting(key: String, value: float) -> void:
	_settings[key] = clampf(value, 0.0, 1.0)
	_apply_settings()
	_save_settings()
	if key == "vol_sfx" or key == "vol_master" or key == "vol_ui":
		Audio.play("ui_click")
	if key.begins_with("vol_"):
		_hud.set_menu_audio(_audio_status())


func _again_text() -> String:
	if _encounter != 2:
		return ""
	if _voted:
		return "Quitar mi voto de otra ronda  (%d/%d)" % [_votes, _connected]
	return "Jugar otra ronda" if _connected <= 1 else "Jugar otra ronda  (%d/%d listos)" % [_votes, _connected]


## Texto del botón de pantalla completa según lo que diga el navegador ("" si no la ofrece).
func _fs_text() -> String:
	if not _is_web or not bool(_js("!!(window.ALUX_FS && ALUX_FS.supported)")):
		return ""
	return "Pantalla completa: %s" % ("sí" if bool(_js("ALUX_FS.active()")) else "no")


func _open_menu() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_was_captured = false
	_mouse_l = false
	_mouse_r = false
	_hud.hide_result()
	_hud.show_menu(_settings, QUALITY_NAMES[_quality], _again_text())
	_hud.set_menu_audio(_audio_status())
	_hud.set_menu_fullscreen(_fs_text())
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


# ───────────────────────── Personalizador 3D ─────────────────────────

## El juego se abrió sólo para personalizar (portal → «Personalizar en 3D»): no hay sala ni
## servidor de juego. Se pide el perfil y se muestra el alux en la plaza del claro.
func _begin_custom_only() -> void:
	_custom_only = true
	_net = Net.CUSTOM
	_hud.visible = false
	_js("(function(){window.ALUX_ME='';fetch('/api/v1/me',{credentials:'same-origin'}).then(function(r){return r.ok?r.text():Promise.reject(r.status)})" +
		".then(function(t){window.ALUX_ME=t}).catch(function(e){window.ALUX_ME='error:'+e})})()")
	_me_poll = 0.2


func _poll_custom_only(delta: float) -> void:
	if _custom.active or _me_poll <= 0.0:
		return
	_me_poll -= delta
	if _me_poll > 0.0:
		return
	_me_poll = 0.2
	var raw := str(_js("window.ALUX_ME || ''"))
	if raw.is_empty():
		return
	_me_poll = 0.0
	var parsed: Variant = JSON.parse_string(raw)
	if raw.begins_with("error:") or not (parsed is Dictionary) or not ((parsed as Dictionary).get("character") is Dictionary):
		if raw == "error:401":
			_js("(function(){var w=window;try{if(window.top&&window.top.document)w=window.top}catch(e){}w.location.href='/?next=%2Falux'})()")
		else:
			_fatal("No se pudo leer tu perfil para el personalizador.", true)
		return
	var c: Dictionary = parsed.character
	var look: Dictionary = c.get("look", {}) if c.get("look") is Dictionary else {}
	var at := Vector3(1.6, World.terrain_h(1.6, 5.2), 5.2)
	_custom.open(self, _cam, at, 0.0, {"name": c.get("name", "Alux"), "color": c.get("color", "#2ec4a6"), "hat": int(c.get("hat", 0)),
		"look": [int(look.get("outfit", 0)), int(look.get("accessory", 0)), int(look.get("amulet", 0)), int(look.get("accent", 0)), int(look.get("skin", 0))]}, true)
	_audio.ambience({"amb_selva": 0.7, "amb_aves": 0.45, "amb_insectos": 0.25, "amb_brasero": 0.3})
	_audio.set_music("mus_claro")
	_hud.set_overlay("")


## Desde el menú, con la partida en marcha: el personalizador se abre donde está el jugador.
func _open_customizer() -> void:
	var me: Avatar = _avatars.get(_my_slot)
	if _net != Net.PLAYING or me == null or _custom.active:
		return
	if _encounter == 1 or _frozen or _cine.active or _pred.dead or (_encounter == 2 and _boss_phase() in [BossDef.OLVIDO, BossDef.FURIA, BossDef.RECUERDO]):
		_hud.hint("Ahora no: cambia tu aspecto cuando no haya combate", 4.0)
		return
	_close_menu(false)
	_hud.hide_result()
	_hud.visible = false
	me.visible = false
	_custom.open(self, _cam, me.global_position, me.rotation.y, {"name": me.player_name, "color": "#" + me.color.to_html(false), "hat": me.hat, "look": me.look})


func _on_look_saved(character: Dictionary) -> void:
	if _custom_only:
		return
	# Lo guardó la API. El servidor de juego lo relee de ella y lo reparte a la sala; mientras
	# llega, el jugador ya se ve con su aspecto nuevo.
	var me: Avatar = _avatars.get(_my_slot)
	if me != null:
		var form := me.form
		me.setup(me.player_name, str(character.color), int(character.hat), character.look)
		me.is_local = true
		me.set_form(form, false)
	if _ws != null and _net == Net.PLAYING:
		_ws.send_text(JSON.stringify({"t": "look"}))


func _on_custom_closed(_did_save: bool) -> void:
	if _custom_only:
		_exit_to_portal()
		return
	_hud.visible = true
	var me: Avatar = _avatars.get(_my_slot)
	if me != null:
		me.visible = true
	if _net == Net.PLAYING:
		_hud.hint("Pulsa el juego para seguir", 3.0)


func _exit_to_portal() -> void:
	_metrics_send(true)
	if _ws:
		_ws.close()
	if _is_web:
		_js("(function(){var w=window;try{if(window.top&&window.top.document)w=window.top}catch(e){}w.location.href='/hub'})()")
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

## Cinemática compartida, fase de preparación: la sala ya está en pausa. Este cliente funde a
## negro, comprueba si tiene los vídeos y avisa al servidor, que da la orden de inicio a todos.
func _begin_shared_prep(id: String, wait: float) -> void:
	_skip_voted = false
	_prep = {"id": id, "t": 0.0, "wait": wait, "sent": false}
	if not _cine_on or not Story.CUTSCENES.has(id):
		# Sin escenas (pruebas automáticas) o escena desconocida: no se hace esperar a nadie
		_send_cine_ready(id, false)
		_prep.sent = true
		return
	if _cine.active:
		_intro_after_cine = false
		_cine.stop()
	_hud.hide_intro()
	_hud.hide_result()
	_hud.hide_dialogue()
	_hud.hide_menu()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_mouse_l = false
	_mouse_r = false
	_video.preload_clips(Story.cutscene_videos(id))
	_video.prepare(Story.cutscene_videos(id))
	_video_release_in = 0.0
	_hud.set_cine(true, false)
	_hud.fade_to(1.0, 0.45)
	_cine_out = 0.0


func _send_cine_ready(id: String, with_video: bool) -> void:
	if _ws != null and _net == Net.PLAYING:
		_ws.send_text(JSON.stringify({"t": "cine_ready", "id": id, "v": 1 if with_video else 0}))


## Orden de inicio del servidor (o enganche a mitad, con `at` segundos ya transcurridos).
func _start_shared(id: String, at: float) -> void:
	_skip_voted = false
	_prep = {}
	if not _cine_on or not Story.CUTSCENES.has(id):
		_hud.hint("El grupo está viendo una escena: la partida sigue en unos segundos", 5.0)
		return
	if _cine.active:
		_intro_after_cine = false
		_cine.stop()
	_hud.hide_intro()
	_hud.hide_result()
	_hud.hide_dialogue()
	_hud.hide_menu()
	_cine_out = 0.0
	_video_release_in = 0.0
	_play_cutscene(id, at)
	_hud.fade_to(0.0, 0.4)


## Avanza la preparación y la vuelta al juego de las cinemáticas.
func _update_cine_flow(delta: float) -> void:
	if not _prep.is_empty() and not bool(_prep.sent):
		_prep.t = float(_prep.t) + delta
		var clips: Array = Story.cutscene_videos(str(_prep.id))
		var settled := true
		var have := not clips.is_empty()
		for clip in clips:
			var st: String = _video.status(clip)
			if st == "fetched":
				_video.prepare([clip])   # terminó de descargarse durante la espera
			if st != "ready":
				have = false
			if not (st in ["ready", "absent", "error"]):
				settled = false
		# Listo cuando acabó el fundido y ya se sabe qué pasa con el vídeo; si la descarga
		# tarda, se avisa antes de que se agote la espera y se verá la escena del motor.
		if float(_prep.t) >= 0.5 and (settled or float(_prep.t) >= float(_prep.wait) - 1.2):
			_send_cine_ready(str(_prep.id), have)
			_prep.sent = true
	if _video_release_in > 0.0:
		_video_release_in -= delta
		if _video_release_in <= 0.0 and not _cine.active:
			_video.release()
	if _cine_out > 0.0:
		_cine_out -= delta
		if _cine_out <= 0.0:
			_hud.fade_to(0.0, 0.55)
	# Red de seguridad: sin cinemática en curso, la pantalla no se queda en negro
	elif _cine_phase == Story.CINE_NONE and _prep.is_empty() and not _cine.active and _hud.fade_alpha() >= 0.99:
		_hud.fade_to(0.0, 0.4)


func _seen(key: String) -> bool:
	return _is_web and str(_js("(function(){try{return localStorage.getItem('alux_seen_%s')||''}catch(e){return ''}})()" % key)) == "1"


func _mark_seen(key: String) -> void:
	if _is_web:
		_js("(function(){try{localStorage.setItem('alux_seen_%s','1')}catch(e){}})()" % key)


## Reproduce una cinemática hecha en el motor. Las locales no detienen la partida de nadie:
## sólo dejan quieto a este jugador mientras la ve.
func _play_cutscene(id: String, start_at := 0.0) -> void:
	if _cine.active or not Story.CUTSCENES.has(id):
		return
	_cine.volume = clampf(float(_settings.vol_master) * float(_settings.vol_sfx), 0.0, 1.0)
	_video.prepare(Story.cutscene_videos(id))   # por si no hubo fase de preparación (locales, enganche a mitad)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_mouse_l = false
	_mouse_r = false
	_hud.hide_menu()
	var names := {}
	for npc in Story.NPCS:
		names[npc] = Story.NPCS[npc].name
	# Banda sonora de la escena: una sola, se vea como vídeo o con el motor. Si no la hay (o no
	# hay mezclador), cada plano dispara su efecto como antes; nunca las dos cosas.
	_cine.soundtrack = _audio.cine_start(id, start_at)
	_cine.play(id, Story.CUTSCENES[id], _cam, _hud, names, start_at)


func _on_cine_finished(id: String, skipped: bool) -> void:
	# Omitida: la banda sonora se funde enseguida. Terminada: se deja respirar la cola.
	_audio.cine_stop(0.25 if skipped and not _cine.near_end() else 1.6)
	if skipped and not _cine.near_end():
		_cine_stats.skipped += 1
	_mark_seen(id)
	_cine_stats["video" if _cine.video_shots > 0 else "engine"] += 1
	_cine_stats.fallbacks += _cine.fallbacks
	_video.note("")
	_video_release_in = 1.2   # cuando el vídeo ya se fundió, se sueltan sus decodificadores
	# Vuelta al juego: corte a negro (la cámara regresa detrás del personaje sin que se vea el
	# salto) y fundido de entrada. En las compartidas la sala sigue en pausa mientras tanto.
	if _cine.shared or _cine.ended_on_video:
		_hud.fade_to(1.0, 0.0)
		_cine_out = 0.35
		if _gate_open:
			_gate_anim = 1.0   # lo que la escena mostró abrirse ya está abierto al volver
	if _intro_after_cine:
		_intro_after_cine = false
		_hud.show_intro()


func _open_dialogue(npc: String) -> void:
	var lines: Array = Story.dialogue(npc, _story, _encounter, _boss_phase())
	if lines.is_empty():
		return
	var texts := []
	for line in lines:
		texts.append(str(line[1]))
	_talking = npc
	_mouse_l = false
	_mouse_r = false
	_hud.context_hint("")
	_hud.show_dialogue(str(Story.NPCS[npc].name), str(Story.NPCS[npc].title), texts, GOLD, npc)
	Audio.play("ui_abrir")


## Al terminar de leer se avisa al servidor: es él quien anota el avance de la historia.
func _on_dialogue_done(completed: bool) -> void:
	var npc := _talking
	_talking = ""
	if completed and not npc.is_empty() and _ws != null and _net == Net.PLAYING:
		_ws.send_text(JSON.stringify({"t": "talk", "n": npc}))
		if npc == _npc.npc_id:
			_npc.gesture("Bless")   # despedida: levanta el bastón


## Botones de la interfaz (menú, resultado, bienvenida y pantallas de error).
func _on_action(id: String) -> void:
	if id in ["start", "again", "retry", "replay_intro"]:
		Audio.play("ui_confirmar|ui_click")
	elif id in ["resume", "close"] or (id == "menu" and _hud.menu_open()):
		Audio.play("ui_cerrar|ui_click")
	elif id != "sound_test":
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
		"sound_test":
			# Suena la prueba y, cuando ha tenido tiempo de salir, se mide lo que llegó a la salida
			_audio.test()
			_sound_test_in = 0.9
			_hud.set_menu_audio("Probando…")
		"fullscreen":
			# El navegador decide: si la niega, la partida sigue en ventana
			if _is_web:
				_js("window.ALUX_FS && ALUX_FS.toggle()")
				_fs_poll = 0.0
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
		"customize":
			_open_customizer()
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
	_hud.visible = true
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
			_apply_boss(m.get("b", []))
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
				_video.preload_clips(Story.video_ids())
				# La primera vez, la introducción del capítulo; después, directo a los controles
				if _cine_on and not _seen("llamado"):
					_intro_after_cine = true
					_play_cutscene("llamado")
				else:
					_hud.show_intro()
				_amb_in = 0.0   # el ambiente de la zona entra en el siguiente cuadro
			_refresh_music()
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
			av.setup(str(p.name), str(p.color), int(p.hat), p.get("look"))
			if slot != _my_slot:
				_remote[slot] = {"buf": []}
		elif av.player_name != str(p.name) or av.hat != int(p.hat) or av.color.to_html(false) != str(p.color).trim_prefix("#").to_lower() \
				or av.look != Look.clean(p.get("look")):
			# cambió su aspecto (personalizador): se rehace el modelo conservando forma y estado
			var was_form := av.form
			av.setup(str(p.name), str(p.color), int(p.hat), p.get("look"))
			av.set_form(was_form, false)
		av.set_online(bool(p.on))
	for slot in _avatars.keys():
		if not seen.has(slot):
			_avatars[slot].queue_free()
			_avatars.erase(slot)
			_remote.erase(slot)
	# Aviso sonoro de quién entra y quién se va (no al recibir la lista por primera vez)
	var online := {}
	for p in players:
		online[str(p.id)] = bool(p.on)
	if not _online.is_empty():
		for id in online:
			if id != _my_id and bool(online[id]) != bool(_online.get(id, false)):
				Audio.play("ui_jugador_entra" if bool(online[id]) else "ui_jugador_sale", null, -4.0, 0.0)
	_online = online
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
	_frozen = w.size() > 11 and int(w[11]) > 0
	_skip_votes = int(w[12]) if w.size() > 12 else 0
	_cine_phase = int(w[13]) if w.size() > 13 else (Story.CINE_PLAYING if _frozen else Story.CINE_NONE)
	if _cine_phase == Story.CINE_NONE and not _prep.is_empty():
		# La preparación se quedó sin escena (p. ej. reconexión): se vuelve al juego sin más
		_prep = {}
		if not _cine.active:
			_hud.set_cine(false)
			_hud.fade_to(0.0, 0.4)
	if _cine.active and _cine.shared:
		if _cine_phase != Story.CINE_PLAYING and not instant:
			_cine.stop()   # el servidor ya la dio por terminada
		else:
			var need := Story.skip_votes_needed(_connected)
			var note := "Votaste omitir  (%d/%d)" % [_skip_votes, need] if _skip_voted else ("Enter  ·  omitir" if _connected <= 1 else "Enter  ·  votar para omitir  (%d/%d)" % [_skip_votes, need])
			_hud.cine_skip_text(note)
			_video.note(note)
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
			_builder.settle_aftermath()   # ya estaba abierto al llegar: sin destello
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
	elif _encounter == 2 and _boss_phase() in [BossDef.OLVIDO, BossDef.FURIA, BossDef.RECUERDO]:
		_boss_objective()
	elif _encounter == 2:
		var detail := "Esc: jugar otra ronda o salir al portal"
		if _votes > 0 and _connected > 1:
			detail = "Otra ronda: %d de %d listos  ·  Esc para %s" % [_votes, _connected, "quitar tu voto" if _voted else "unirte"]
		if (_story & Story.F_CLUE) != 0:
			_hud.set_objective("Capítulo I completado", "success", "La Pluma de Jade señala el cenote  ·  " + detail)
		elif _boss_phase() == BossDef.FREED:
			_hud.set_objective("Habla con Nojoch Tuunich", "goal", "Recordó quién es  ·  acércate y pulsa F")
		elif _votes > 0 and _connected > 1:
			_hud.set_objective("Santuario abierto", "success", detail)
		elif _boss_state.size() > 1 and float(_boss_state[1]) < 22.0:
			_hud.set_objective("El guardián volvió a dormirse", "goal", "Acérquense a él cuando el grupo esté listo  ·  se retoma desde la fase alcanzada")
		else:
			_hud.set_objective("Entra al santuario", "goal", "Algo enorme duerme al fondo del patio")
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
	_refresh_music()
	_voted = false
	if to == 1:
		_stats = {"t0": _time, "secs": 0.0, "purified": 0, "kills": 0, "falls": 0, "left": 0}
		_reward_text = ""
		_feather_text = ""
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
	if kind == "freed":
		if _boss_phase() != BossDef.FREED:
			return
		if _cine.active or _frozen:
			# la escena de la liberación va primero: el panel espera a que termine
			_result_kind = "freed"
			_result_in = 0.5
			return
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_was_captured = false
	_mouse_l = false
	_mouse_r = false
	_hud.hide_menu()
	var secs := int(float(_stats.secs))
	var time_text := "%d:%02d" % [secs / 60, secs % 60]
	if kind == "freed":
		var stats := [["Tiempo", time_text], ["Criaturas purificadas", str(_stats.purified)], ["Caídas del grupo", str(_stats.falls)]]
		stats.append(["Pluma de Jade", _feather_text if not _feather_text.is_empty() else "guardando…"])
		_hud.show_result("victory", "CAPÍTULO I COMPLETADO", "Nojoch Tuunich recordó quién es y les confió la Pluma de Jade. Háblenle: sabe hacia dónde tira.", stats, [
			["close", "Hablar con el guardián", true], ["again", "Jugar otra ronda", false], ["exit", "Salir al portal", false]])
	elif kind == "victory":
		var stats := [["Tiempo", time_text], ["Criaturas purificadas", str(_stats.purified)],
			["Enemigos vencidos", str(_stats.kills)], ["Caídas del grupo", str(_stats.falls)]]
		if not _reward_text.is_empty():
			stats.append(["Sello del Claro", _reward_text])
		_hud.show_result("victory", "¡VICTORIA!", "El santuario está abierto y el claro vuelve a respirar. Pero al fondo del patio algo enorme sigue dormido…", stats, [
			["close", "Entrar al santuario", true], ["again", "Jugar otra ronda", false], ["exit", "Salir al portal", false]])
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
			if _net == Net.PLAYING and _time - _spawn_sound_t > 0.25:
				_spawn_sound_t = _time   # (una oleada entera no dispara ocho sonidos a la vez)
				Audio.play("enemigo_aparece", Vector3(e[2], e[3], e[4]), -3.0)
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
	_apply_boss(m.get("b", []))
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
		"cine_prep":
			# Cinemática compartida: el servidor pausó la sala y espera a que los clientes se preparen
			_begin_shared_prep(str(m.get("id", "")), float(m.get("wait", Story.CINE_PREP_MAX)))
		"cine":
			# Orden de inicio: todos la empiezan al recibirla
			_start_shared(str(m.get("id", "")), float(m.get("at", 0.0)))
		"cine_end":
			_prep = {}
			if _cine.active and _cine.shared:
				_cine.stop()
		"story":
			match str(m.get("k", "")):
				"talked":
					Audio.play("objetivo")
					_hud.hint("%s habló con Chiich Yaxché  ·  nueva misión: los altares" % str(m.get("by", "Un alux")), 5.0)
				"freed":
					_story |= Story.F_FREED
				"clue":
					_story |= Story.F_CLUE
					Audio.play("pluma_jade", null, 0.0, 0.0)
					_hud.banner("La Pluma de Jade señala el cenote", JADE, 5.0)
					_hud.hint("%s escuchó al guardián  ·  el camino del capítulo II queda marcado en la brújula" % str(m.get("by", "Un alux")), 7.0)
					_refresh_music()
		"gate_open":
			_hud.banner("¡El santuario se abre!", Color(0.5, 1.0, 0.85), 3.0)
			Audio.play("santuario_abre", Vector3(World.SANCTUARY.x - 7.0, 1.0, World.SANCTUARY.y), 3.0)
		"reward":
			if str(m.get("reward", "")) == BossDef.REWARD:
				# La Pluma de Jade: objeto ancestral, queda en el perfil de cada jugador
				if not bool(m.get("saved", false)):
					_feather_text = "no se pudo guardar"
					_hud.toast("Pluma de Jade\nno se pudo guardar")
				elif bool(m.get("new", false)):
					_feather_text = "guardada en tu perfil"
					_hud.toast("Pluma de Jade\nguardada en tu perfil")
					Audio.play("pluma_jade", null, -2.0, 0.0)
					Audio.play("ui_recompensa", null, -2.0, 0.0)
				else:
					_feather_text = "ya la tenías"
				if _hud.result_open() and _boss_phase() == BossDef.FREED:
					_result_kind = "freed"
					_result_in = 0.01
				return
			if str(m.get("reward", "")) != "sello_del_claro":
				# Progreso del capítulo guardado en el perfil (sin panel: ya se avisó en la partida)
				if bool(m.get("saved", false)) and bool(m.get("new", false)):
					_hud.toast("Capítulo I\nprogreso guardado en tu perfil")
				return
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
		# las habilidades propias van un poco por encima: tienen que oírse claras sobre la música
		Audio.play(snd, pos, 3.0 if slot == _my_slot else -5.0)
	match kind:
		"interact":
			Audio.play("interactuar", pos, -6.0 if slot == _my_slot else -12.0)
			Fx.ring(self, pos, 1.6, JADE, 0.35)
		"claw":
			var ab: Dictionary = Defs.FORMS.balam.primary
			Fx.claws(self, pos + Vector3(0, 0.8, 0), yaw, ab.range, ab.arc, Color(1.0, 0.75, 0.3))
		"charged":
			var ab: Dictionary = Defs.FORMS.balam.secondary
			Fx.slash(self, pos + Vector3(0, 0.8, 0), yaw, ab.range * (1.0 + 0.2 * power), ab.arc, Color(1.0, 0.45, 0.15), 0.32)
			Fx.burst(self, pos + Vector3(sin(yaw), 0.8, cos(yaw)) * 1.2, GOLD, 10 + int(power * 14.0), 5.0)
			if power > 0.7:
				Audio.play("balam_especial", pos, -2.0 if slot == _my_slot else -8.0)   # zarpazo a plena carga
		"pounce":
			Fx.burst(self, pos + Vector3(0, 0.3, 0), Color(0.9, 0.8, 0.6), 10, 3.0)
		"pounce_land":
			Fx.ring(self, pos, Defs.FORMS.balam.special.radius, Color(1.0, 0.7, 0.25), 0.4)
			Fx.burst(self, pos + Vector3(0, 0.2, 0), Color(0.85, 0.75, 0.55), 16, 4.5, 0.09)
			if slot == _my_slot:
				_shake = 0.2
		"dodge":
			Fx.burst(self, pos + Vector3(0, 0.6, 0), av.color.lightened(0.4), 10, 2.5, 0.06, 0.35)


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
					var by: Avatar = _avatars.get(int(ev[5]))
					Audio.play("balam_golpe|golpe" if by != null and by.form == "balam" else "golpe", view.global_position, 0.0 if mine else -6.0, 0.12)
					Audio.play("enemigo_dano", view.global_position, -6.0 if mine else -12.0, 0.1)
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
					Audio.play("dano_fuerte|dano" if int(ev[3]) >= 20 else "dano", av.global_position, 0.0 if slot == _my_slot else -8.0)
				if slot == _my_slot:
					_hud.hurt()
					_shake = 0.3
					if _encounter == 2:
						_pt.dmg = int(_pt.dmg) + int(ev[3])
					if int(ev[4]) <= 40 and int(ev[4]) > 0:
						_tip("brazier", "Con poca vida: toca el brasero de la plaza (F como alux) para curar al grupo", 7.0)
		"die":
			if str(ev[1]) == "e":
				var view: EnemyView = _enemies.get(int(ev[2]))
				if view != null:
					view.die(int(ev[3]) != 0)
					Audio.play("purificar" if int(ev[3]) != 0 else "enemigo_muere", view.global_position)
					if int(ev[3]) != 0:
						Audio.play("enemigo_purificado", view.global_position, -3.0)
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
					if int(ev[2]) != _my_slot:
						Audio.play("aliado_caido", null, -4.0, 0.0)   # aviso de interfaz: se oye aunque esté lejos
				if int(ev[2]) == _my_slot:
					_m.falls = int(_m.falls) + 1
					if _encounter == 2:
						_pt.falls = int(_pt.falls) + 1
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
			if int(ev[1]) != _my_slot:
				Audio.play("aliado_revive", null, -6.0, 0.0)
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
				Audio.play(("guardian_ataque" if view.kind == "piedra" else "criatura_ataque") + "|enemigo_golpe", view.global_position)
		"brazier":
			Fx.ring(self, Vector3(0, 0.1, 0), Defs.BRAZIER_RANGE + 2.0, Color(1.0, 0.75, 0.3), 0.7)
			Fx.burst(self, Vector3(0, 1.4, 0), Color(1.0, 0.8, 0.35), 26, 5.0, 0.08, 0.9)
			if int(ev[1]) == _my_slot:
				_hud.hint("El brasero cura al grupo  ·  tarda %d s en volver a encenderse" % int(Defs.BRAZIER_CD), 4.0)
		"boss":
			_on_boss_event(ev)
		"enc":
			match str(ev[1]):
				"start":
					_hud.banner("¡Emboscada!", Color(1.0, 0.45, 0.6), 3.5)
					Audio.play("emboscada", null, -3.0, 0.0)
					_tip("balam", "Pulsa 2 para ser Balam y pelear cuerpo a cuerpo  ·  1 vuelve a alux", 7.0)
				"clear":
					_hud.banner("¡Emboscada superada!", GOLD, 3.0)
					if _audio.has("mus_victoria") and _audio.has_mixer():
						_audio.sting("mus_victoria")
					else:
						Audio.play("victoria", null, 0.0, 0.0)
				"fail":
					_respawn_at = minf(_respawn_at, _time + Defs.RESPAWN_TIME_DEFEAT)
					_hud.banner("El grupo ha caído", Color(1.0, 0.5, 0.5), 3.0)
					Audio.play("derrota", null, 0.0, 0.0)


# ───────────────────────── Jefe: Nojoch Tuunich (presentación) ─────────────────────────

func _boss_phase() -> int:
	return int(_boss_state[0]) if _boss_state.size() > 0 else BossDef.ASLEEP


func _boss_action() -> String:
	if _boss_state.size() < 5:
		return "sleep"
	return BossDef.STATES[clampi(int(_boss_state[4]), 0, BossDef.STATES.size() - 1)]


static func _bits(mask: int) -> int:
	var n := 0
	for i in 8:
		if (mask & (1 << i)) != 0:
			n += 1
	return n


## Sacudida de cámara, moderada y a gusto del jugador (ajuste «Sacudida de cámara»).
func _bump(amount: float) -> void:
	_shake = maxf(_shake, amount)


## Música según lo que está pasando: emboscada, cada fase del guardián, tensión si hay
## criaturas encima, exploración lejos del centro o la calma del claro.
const MUSIC_FALLBACK := {"mus_exploracion": "mus_claro", "mus_peligro": "mus_claro", "mus_liberacion": "mus_recuerdo",
	"mus_jefe": "mus_emboscada", "mus_jefe_furia": "mus_emboscada", "mus_recuerdo": "mus_claro"}

func _refresh_music() -> void:
	var want := "mus_claro"
	if _encounter == 1:
		want = "mus_emboscada"
	elif _encounter == 2:
		match _boss_phase():
			BossDef.OLVIDO:
				want = "mus_jefe"
			BossDef.FURIA:
				want = "mus_jefe_furia"
			BossDef.RECUERDO:
				want = "mus_recuerdo"
			BossDef.FREED:
				want = "mus_liberacion" if (_story & Story.F_CLUE) == 0 else "mus_claro"
			_:
				want = "mus_peligro" if _time < _danger_until else "mus_claro"
	elif _time < _danger_until:
		want = "mus_peligro"
	elif _far_from_claro:
		want = "mus_exploracion"
	for _i in 3:
		if _audio.has(want) or not MUSIC_FALLBACK.has(want):
			break
		want = MUSIC_FALLBACK[want]
	_audio.set_music(want)


## Paisaje sonoro de donde está el jugador: capas de ambiente por zona (selva, cenote, ruinas,
## santuario) y música de tensión o de exploración. Se revisa unas pocas veces por segundo.
func _update_soundscape(delta: float, at: Vector3) -> void:
	_amb_in -= delta
	if _amb_in > 0.0:
		return
	_amb_in = 0.4
	var here := Vector2(at.x, at.z)
	var cenote := clampf(1.0 - (here.distance_to(World.CENOTE) - World.CENOTE_R) / 14.0, 0.0, 1.0)
	var ruins := clampf(1.0 - (here.distance_to(World.SANCTUARY) - 8.0) / 8.0, 0.0, 1.0)
	var pyramid := clampf(1.0 - (here.distance_to(World.PYRAMID) - 6.0) / 12.0, 0.0, 1.0)
	var fight := _encounter == 1 or (_encounter == 2 and _boss_phase() in [BossDef.OLVIDO, BossDef.FURIA, BossDef.RECUERDO])
	var ritual := _encounter == 2 and _boss_phase() == BossDef.RECUERDO
	var mix := {
		"amb_selva": 0.75 * (1.0 - 0.6 * ruins),
		"amb_aves": (0.2 if fight else 0.5) * (1.0 - 0.8 * ruins),
		"amb_insectos": 0.3 * (1.0 - 0.5 * ruins),
		"amb_viento": 0.2 + 0.3 * pyramid + (0.2 if fight else 0.0),
		"amb_agua": 0.6 * cenote,
		"amb_cenote": 0.45 * cenote,
		"amb_ruinas": maxf(0.7 * ruins, 0.4 * pyramid),
		"amb_energia": 0.3 * ruins + (0.35 if ritual else 0.0),
		"amb_brasero": 0.0,
	}
	for key in mix.keys():
		mix[key] = snappedf(float(mix[key]), 0.05)
		if float(mix[key]) <= 0.0 and key != "amb_brasero":
			mix.erase(key)
	# el brasero lo lleva set_layer_distance cuadro a cuadro: aquí sólo se conserva su valor
	mix["amb_brasero"] = _audio.layer("amb_brasero")
	_audio.ambience(mix)
	# Tensión: alguna criatura persiguiendo o atacando cerca (se mantiene unos segundos al perderla)
	for id in _enemies:
		var view: EnemyView = _enemies[id]
		if view.state in ["chase", "windup", "strike"] and view.global_position.distance_to(at) < 14.0:
			_danger_until = _time + 5.0
			break
	# El guardián dormido respira: se le oye al acercarse al patio
	if _boss != null and _boss.visible and not _boss_state.is_empty() and _boss_phase() == BossDef.ASLEEP and _time >= _breath_at \
			and (_boss.position - at).length() < 24.0:
		_breath_at = _time + 6.5
		Audio.play("jefe_respira", _boss.position, 2.0, 0.03)
	# Exploración: lejos del centro del claro (con margen para no ir cambiando en la frontera)
	var out := here.length()
	if out > 27.0 and ruins <= 0.0:
		_far_from_claro = true
	elif out < 21.0 or ruins > 0.0:
		_far_from_claro = false
	_refresh_music()


## Estado del audio para el menú, con lo que de verdad está saliendo por el navegador.
func _audio_status(tested := false) -> String:
	var info := _audio.info()
	var ctx := str(info.get("ctx", ""))
	if not bool(info.get("ok", false)):
		return "Audio: sin mezclador del navegador"
	if ctx != "running":
		return "Audio bloqueado por el navegador: haz clic en el juego o pulsa una tecla"
	if float(_settings.vol_master) <= 0.001:
		return "Volumen general a cero: no se oirá nada"
	var peak := float(info.get("peak", 0.0))
	if tested:
		if peak > 0.01:
			return "Prueba correcta: sale sonido (pico %d dB)" % int(round(linear_to_db(peak)))
		return "No llegó señal a la salida. Revisa el volumen del sistema y de la pestaña"
	if not (info.get("errors", []) as Array).is_empty():
		return "Audio en marcha, con %d aviso(s) de carga" % (info.get("errors", []) as Array).size()
	return "Audio en marcha a %d Hz" % int(info.get("rate", 0))


## Estado del jefe que manda el servidor: lo dibuja y actualiza su barra. El cliente no decide nada.
func _apply_boss(b: Array) -> void:
	if b.size() < 10:
		return
	var before := _boss_phase()
	_boss_state = b
	if _boss == null:
		_boss = BossView.new()
		add_child(_boss)
		_boss.setup()
		_boss.stepped.connect(_on_boss_step)
		_arena = BossArena.new()
		add_child(_arena)
		_arena.setup(_quality >= 1)
	_boss.apply(b)
	_arena.apply(b)
	var phase := int(b[0])
	var awake := phase in [BossDef.OLVIDO, BossDef.FURIA, BossDef.RECUERDO]
	var note := ""
	var sub_label := ""
	var sub := -1.0
	var sub_color := JADE
	var full := b.size() >= 24
	match phase:
		BossDef.OLVIDO:
			note = "No tiene vida: devuélvele la memoria"
		BossDef.FURIA:
			if full:
				note = "corazones liberados %d/%d" % [int(b[18]), BossDef.EXPOSURES]
				sub = float(b[17]) / 100.0
				sub_label = "CORAZÓN EXPUESTO  ·  ¡garras de Balam!" if _boss_action() == "bound" else "CORAZÓN DE PIEDRA"
				sub_color = Color(1.0, 0.55, 0.3)
		BossDef.RECUERDO:
			if full:
				note = "glifos de memoria %d/%d" % [int(b[19]), int(b[20])]
				if int(b[19]) >= int(b[20]):
					sub = float(b[21]) / 100.0
					sub_label = "CONTACTO  ·  %d de %d lo tocan" % [_bits(int(b[22])), int(b[23])]
	_hud.set_boss(awake, BossDef.PHASE_NAMES[clampi(phase, 0, 4)], float(b[6]) / BossDef.SILENCE_MAX,
		int(b[7]), int(b[8]) if phase == BossDef.OLVIDO else 0, note, sub_label, sub, sub_color)
	if phase != before:
		_refresh_music()
	# Brújula: las anclas mientras hacen falta; el cenote cuando la pluma ya lo señala
	var marks := []
	var key := ""
	if phase == BossDef.FURIA and (_boss_action() == "stunned" or _boss_action() == "bound") and full:
		key = "anclas%d" % int(b[14])
		for i in BossDef.ANCHORS.size():
			marks.append(["goal", GOLD if (int(b[14]) & (1 << i)) != 0 else JADE, BossDef.ANCHORS[i]])
	elif (_story & Story.F_CLUE) != 0:
		key = "cenote"
		marks.append(["goal", JADE, World.CENOTE])
	elif phase == BossDef.FREED:
		key = "nojoch"
		marks.append(["alux", JADE, Vector2(float(b[1]), float(b[2]))])
	_hud.set_extra_marks(key, marks)


## Lo que una cinemática pide al escenario en el plano en curso: la pose y el aspecto del
## guardián, las motas del Silencio y la Pluma de Jade. Al terminar, todo vuelve a seguir al estado
## del servidor.
func _update_cine_stage(delta: float) -> void:
	if _boss == null:
		return
	var shot: Dictionary = _cine.current_shot() if _cine.active else {}
	if not shot.has("boss"):
		if _cine_staged:
			_cine_staged = false
			_boss.cine_release()
			_arena.cine_feather = -1
		return
	_cine_staged = true
	var pose: Dictionary = shot.boss
	var glow: Array = pose.get("glow", [-1.0, -1.0])
	var look := int(pose.get("look", -1))
	if pose.has("look_to") and _cine.shot_k() >= float(pose.get("look_at", 0.5)):
		look = int(pose.look_to)
	_boss.cine_pose(str(pose.anim), float(pose.get("at", 0.0)) + _cine.shot_time() * float(pose.get("speed", 1.0)),
		look, lerpf(float(glow[0]), float(glow[1]), _cine.shot_k()))
	if shot.has("feather"):
		_arena.cine_feather = 1 if bool(shot.feather) else 0
	if shot.has("motes") and not _cine.using_video():
		_motes_in -= delta
		if _motes_in <= 0.0:
			_motes_in = 0.14 if _quality == 0 else 0.3
			var a := randf() * TAU
			var at := _boss.position + Vector3(cos(a) * randf_range(0.6, 1.9), randf_range(0.8, 3.6), sin(a) * randf_range(0.6, 1.9))
			Fx.burst(self, at, Color(str(shot.motes)), 3, 1.4, 0.06, 1.3)


func _on_boss_step() -> void:
	var d := (_boss.position - _pred.pos).length()
	if d < 26.0:
		Audio.play("jefe_paso", _boss.position, -2.0, 0.12)
	if d < 9.0:
		_bump(0.05 if _boss_action() != "charge" else 0.09)


func _boss_objective() -> void:
	var b := _boss_state
	var st := _boss_action()
	match _boss_phase():
		BossDef.OLVIDO:
			_hud.set_objective("Enciende los glifos del guardián  (%d/%d)" % [int(b[7]), int(b[8])], "alert",
				"Debilita a una criatura y tócala con F junto a él  ·  los golpes no le hacen nada")
		BossDef.FURIA:
			if b.size() < 24:
				return
			var hearts := "(%d/%d)" % [int(b[18]), BossDef.EXPOSURES]
			if st == "kneel" or st == "transit":
				_hud.set_objective("El Silencio lo arrastra a la explanada", "alert", "Síguelo fuera del santuario")
			elif st == "bound":
				_hud.set_objective("¡Corazón expuesto!  %s" % hearts, "success",
					"Golpéalo como Balam (2)  ·  quien pise un ancla, que no la suelte" if _connected > 1 else "Golpéalo como Balam (2) antes de que se suelte")
			elif st == "stunned":
				_hud.set_objective("¡Aturdido!  Pisen las anclas  (%d/%d)" % [_bits(int(b[14])), int(b[15])], "success",
					"Los discos de jade de la explanada: las cadenas lo sujetarán")
			elif (b[16] as Array).is_empty():
				_hud.set_objective("Despierta una columna  %s" % hearts, "alert",
					"Como alux, toca con F uno de los glifos dorados del suelo")
			elif st == "rain_w" or st == "rain":
				_hud.set_objective("¡Lluvia de piedra!", "alert", "Refúgiate junto a una columna (círculo de jade)")
			else:
				_hud.set_objective("Haz que embista contra una columna  %s" % hearts, "alert",
					"Ponte detrás de ella cuando te apunte  ·  quedará aturdido")
		BossDef.RECUERDO:
			if b.size() < 24:
				return
			if st != "ritual":
				_hud.set_objective("El guardián se arrodilla", "success", "El Silencio se resiste por última vez")
			elif int(b[19]) < int(b[20]):
				_hud.set_objective("Enciende los glifos de memoria  (%d/%d)" % [int(b[19]), int(b[20])], "alert",
					"Purifica criaturas junto a él (F)  ·  son lo último que le queda al Silencio")
			else:
				_hud.set_objective("Tóquenlo todos a la vez  (%d/%d)" % [_bits(int(b[22])), int(b[23])], "success",
					"Como alux, junto a él, mantén F  ·  un golpe corta el contacto")
		_:
			_hud.set_objective("Nojoch Tuunich", "alert", "")


func _on_boss_event(ev: Array) -> void:
	var at := _boss.position if _boss != null else Vector3(BossDef.HOME.x, 0.0, BossDef.HOME.y)
	var near := (at - _pred.pos).length()
	match str(ev[1]):
		"awake":
			_hud.banner("Nojoch Tuunich despierta", Color(1.0, 0.45, 0.7), 4.0)
			Audio.play("jefe_despierta", at, 2.0, 0.0)
			Audio.duck(-7.0, 1.0, 1.2)
			_bump(0.22)
			_refresh_music()
			# Qué significa su barra, una sola vez
			if int(ev[2]) == BossDef.OLVIDO:
				_tip("silencio", "Su barra no es vida: es Silencio. Purifica criaturas a su lado (F) y recordará", 9.0)
		"tele":
			match str(ev[2]):
				"slam":
					var p := Vector3(float(ev[4]), World.terrain_h(float(ev[4]), float(ev[5])) + 0.06, float(ev[5]))
					Fx.telegraph(self, p, float(BossDef.SLAM.radius), float(ev[3]))
					Audio.play("jefe_aviso", at, -1.0)
				"sweep":
					Fx.slash(self, at + Vector3(0, 0.4, 0), float(ev[4]), float(BossDef.SWEEP.range), float(BossDef.SWEEP.arc), Color(1.0, 0.3, 0.65), float(ev[3]))
					Audio.play("jefe_aviso", at, -3.0)
				"summon":
					Fx.pillar(self, at, Color(1.0, 0.25, 0.65), 7.0, 1.6, float(ev[3]))
					Audio.play("jefe_llamada", at, 0.0)
				"rain":
					_hud.banner("¡Lluvia de piedra!", Color(1.0, 0.6, 0.4), 2.2)
					Audio.play("jefe_llamada", at, 1.0)
					Fx.pillar(self, at, Color(1.0, 0.7, 0.4), 9.0, 2.0, float(ev[3]))
					_tip("lluvia", "Lluvia de piedra: sólo estás a salvo junto a una columna despierta", 7.0)
				"charge":
					Audio.play("jefe_aviso", at, 1.0)
					Audio.play("jefe_embestida", at, 0.0)
					_tip("embestida", "Va a embestir en línea recta: quítate… o deja una columna en medio", 7.0)
				"pulse":
					Fx.telegraph(self, at + Vector3(0, 0.06, 0), float(ev[4]), float(ev[3]))
					Audio.play("silencio_grieta", at, 2.0)
					if near < float(ev[4]) + 1.0:
						_hud.hint("¡Pulso de Silencio! Apártate o esquiva", 2.5)
		"slam":
			var p := Vector3(float(ev[2]), World.terrain_h(float(ev[2]), float(ev[3])) + 0.1, float(ev[3]))
			Fx.ring(self, p, float(ev[4]), Color(1.0, 0.8, 0.5), 0.5)
			Fx.burst(self, p + Vector3(0, 0.3, 0), Color(0.8, 0.75, 0.62), 22, 6.0, 0.12, 0.7)
			Audio.play("jefe_losa", p, 0.0)
			Audio.duck(-5.0, 0.25, 0.6)
			_bump(clampf(0.34 - (p - _pred.pos).length() * 0.02, 0.06, 0.3))
		"sweep":
			Fx.slash(self, at + Vector3(0, 0.9, 0), float(ev[2]), float(BossDef.SWEEP.range), float(BossDef.SWEEP.arc), Color(1.0, 0.85, 0.6), 0.25)
			Audio.play("jefe_barrido", at, 0.0)
			_bump(0.08)
		"summon":
			if _boss_phase() == BossDef.OLVIDO:
				_hud.hint("El Silencio trae criaturas: son la llave de su memoria", 5.0)
		"glyph":
			_hud.banner("Glifo encendido  %d/%d" % [int(ev[2]), int(ev[3])], JADE, 2.5)
			_boss.flash_memory()
			Audio.play("glifo_restaurado", at, 2.0)
			Fx.pillar(self, at, JADE, 7.0, 1.2, 0.7)
			Fx.ring(self, at + Vector3(0, 0.1, 0), 4.0, JADE, 0.6)
		"far":
			if int(ev[2]) == _my_slot:
				_hud.hint("Demasiado lejos del guardián: purifícala a su lado para encender un glifo", 5.0)
		"phase":
			_refresh_music()
			_bump(0.2)
			Audio.play("jefe_fase", at, 2.0, 0.0)
			Audio.play("punto_control", null, -6.0, 0.0)   # la fase alcanzada queda como punto de control
			Audio.duck(-8.0, 1.2, 1.5)
			if int(ev[2]) == BossDef.FURIA:
				_hud.banner("FASE 2  ·  El corazón de piedra", Color(1.0, 0.55, 0.35), 4.5)
				Audio.play("silencio_grieta", at, 3.0)
				Fx.ring(self, at + Vector3(0, 0.1, 0), 7.0, MAGENTA, 0.8)
			else:
				_hud.banner("FASE 3  ·  La memoria restaurada", JADE, 4.5)
				Audio.play("corazon_libre", at, 2.0)
				Fx.ring(self, at + Vector3(0, 0.1, 0), 8.0, JADE, 0.9)
		"transit":
			Audio.play("jefe_paso", at, 2.0)
		"arena":
			if int(ev[2]) == BossDef.FURIA:
				_tip("furia", "Sus golpes siguen sin hacerle nada. Despierta una columna (F como alux) y haz que choque con ella", 10.0)
		"pillar":
			_arena.pillar_fx(int(ev[2]), false)
			var s: Vector2 = BossDef.PILLAR_SPOTS[clampi(int(ev[2]), 0, BossDef.PILLAR_SPOTS.size() - 1)]
			Audio.play("pilar_sube", Vector3(s.x, 1.0, s.y), 1.0)
		"pillar_max":
			if int(ev[2]) == _my_slot:
				_hud.hint("Ya hay tres columnas despiertas: no caben más", 3.5)
		"pillar_down":
			_arena.pillar_fx(int(ev[2]), true)
			var gone: Vector2 = BossDef.PILLAR_SPOTS[clampi(int(ev[2]), 0, BossDef.PILLAR_SPOTS.size() - 1)]
			Audio.play("pilar_rompe", Vector3(gone.x, 1.0, gone.y), -2.0)
		"rain":
			Audio.play("lluvia_piedra", at, 0.0, 0.0)
			_bump(0.1)
		"charge":
			Audio.play("jefe_paso", at, 3.0)
			_bump(0.14)
		"crash":
			_arena.pillar_fx(int(ev[2]), true)
			Audio.play("jefe_choque", at, 2.0)
			Audio.play("jefe_aturdido", at, 0.0)
			Audio.play("pilar_rompe", at, 0.0)
			Audio.duck(-8.0, 0.6, 1.0)
			_bump(0.34)
			_hud.banner("¡Aturdido!  Pisen las anclas", GOLD, 3.0)
			_tip("anclas", "Aturdido: pisen los discos de jade de la explanada para sujetarlo con cadenas", 8.0)
		"shake":
			_hud.hint("Se sacude el aturdimiento… habrá que hacerlo chocar otra vez", 4.0)
		"anchor":
			if int(ev[3]) != 0:
				var a: Vector2 = BossDef.ANCHORS[clampi(int(ev[2]), 0, BossDef.ANCHORS.size() - 1)]
				var ap := Vector3(a.x, World.terrain_h(a.x, a.y), a.y)
				Audio.play("ancla_activa", ap, 2.0)
				Fx.pillar(self, ap, JADE, 6.0, 1.2, 0.5)
		"bound":
			_hud.banner("¡Cadenas de jade!  Corazón expuesto", JADE, 3.2)
			Audio.play("cadenas_jade", at, 2.0)
			Audio.play("corazon_expuesto", at, 0.0)
			_tip("corazon", "El corazón de su espalda sólo lo alcanzan las garras de Balam (2). ¡Ahora!", 8.0)
		"unbound":
			Fx.ring(self, at + Vector3(0, 0.3, 0), float(BossDef.BOUND.shove_r), Color(1.0, 0.8, 0.5), 0.45)
			Audio.play("jefe_barrido", at, 0.0)
			if int(ev[2]) == 0:
				_hud.hint("Las cadenas se sueltan: vuelve a aturdirlo", 4.0)
		"clang":
			Audio.play("golpe", at, -4.0)
			if int(ev[2]) == _my_slot:
				_tip("clang", "Es de piedra: los golpes no le hacen nada. Hay que exponer su corazón", 6.0)
		"heart_hit":
			var hp := at + Vector3(0, 3.0, 0)
			Fx.burst(self, hp, Color(1.0, 0.6, 0.35), 10, 5.0, 0.09, 0.45)
			Fx.number(self, hp + Vector3(0, 0.6, 0), str(int(ev[3])), Color(1.0, 0.75, 0.4), int(ev[3]) >= 30)
			Audio.play("corazon_golpe", at, 2.0)
			_bump(0.06 if int(ev[2]) != _my_slot else 0.1)
		"heart":
			_hud.banner("Corazón liberado  %d/%d" % [int(ev[2]), int(ev[3])], JADE, 3.5)
			_boss.flash_memory()
			Audio.play("corazon_libre", at, 3.0)
			Fx.pillar(self, at, JADE, 9.0, 1.8, 0.9)
			Fx.ring(self, at + Vector3(0, 0.1, 0), 6.0, JADE, 0.7)
			_bump(0.25)
		"ritual":
			_tip("ritual", "Se arrodilla. Enciende los glifos del suelo purificando criaturas junto a él (F)", 9.0)
		"lit":
			_hud.banner("Glifo de memoria  %d/%d" % [int(ev[2]), int(ev[3])], JADE, 2.5)
			_boss.flash_memory()
			Audio.play("glifo_restaurado", at, 2.0)
			Fx.pillar(self, at, JADE, 7.0, 1.2, 0.7)
		"contact":
			_hud.banner("¡Tóquenlo todos a la vez!", GOLD, 4.0)
			Audio.play("objetivo")
			_tip("contacto", "Como alux, junto a él, mantén F. Tienen que tocarlo todos los que sigan en pie", 9.0)
		"pulse":
			Fx.ring(self, at + Vector3(0, 0.2, 0), float(ev[2]), MAGENTA, 0.45)
			Audio.play("ritual_pulso|jefe_losa", at, -1.0)
			_bump(0.16)
		"freed":
			_hud.banner("Nojoch Tuunich recuerda", JADE, 5.0)
			_pt.freed = true
			Audio.play("liberacion", null, 0.0, 0.0)
			Audio.play("jefe_cae", at, 0.0, 0.0)
			Audio.duck(-10.0, 1.5, 1.5)
			Fx.pillar(self, at, JADE, 14.0, 2.6, 1.6)
			Fx.ring(self, at + Vector3(0, 0.1, 0), 12.0, JADE, 1.2)
			_stats.secs = _time - float(_stats.t0)
			_result_kind = "freed"
			_result_in = 4.0
			_refresh_music()
		"fail":
			_hud.banner("Nojoch Tuunich vuelve a dormirse", Color(1.0, 0.5, 0.5), 3.5)
			var lost := clampi(int(ev[2]), BossDef.OLVIDO, BossDef.RECUERDO) - 1
			(_pt.fails as Array)[lost] = int((_pt.fails as Array)[lost]) + 1
			Audio.play("derrota", null, 0.0, 0.0)
			_refresh_music()
			if int(ev[2]) >= BossDef.FURIA:
				_hud.hint("Se retoma desde esta fase: acércate a él cuando el grupo esté listo", 6.0)


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
	if _hud.panel_open() or _frozen or _custom.active:
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
	if _encounter == 2:
		_pt.denied = int(_pt.denied) + 1   # intentó algo que no podía: pista de que no entendió el objetivo
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
	if _custom_only:
		_poll_custom_only(delta)
	if _sound_test_in > 0.0:
		_sound_test_in -= delta
		if _sound_test_in <= 0.0:
			_hud.set_menu_audio(_audio_status(true))

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
			# (el personalizador suelta el ratón a propósito: no es un Esc)
			if _net == Net.PLAYING and not _custom.active and not _hud.panel_open() and not _hud.help_open():
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
		var custom_cmd := str(_js("window.ALUX_CUSTOM || ''"))
		if not custom_cmd.is_empty():
			_js("window.ALUX_CUSTOM = ''")
			if _custom.active:
				_custom.command(custom_cmd)   # (pruebas) elige una opción del personalizador
		var setting := str(_js("window.ALUX_SETTING || ''"))
		if ":" in setting:
			_js("window.ALUX_SETTING = ''")
			var parts := setting.split(":")
			if _settings.has(parts[0]) and parts[1].is_valid_float():
				_on_setting(parts[0], parts[1].to_float())   # (pruebas) mueve un ajuste: "vol_master:0"
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
		var by_yaxche := not _pred.dead and _npc.distance_to(me.global_position) < _npc.talk_range
		# Al guardián sólo se le puede hablar una vez liberado (y nunca en plena escena)
		var by_nojoch := not _pred.dead and not by_yaxche and _boss != null and _boss_phase() == BossDef.FREED \
			and (_boss.position - me.global_position).length() < float(Story.NPCS.nojoch.range)
		_npc_near = by_yaxche or by_nojoch
		_talk_npc = _npc.npc_id if by_yaxche else ("nojoch" if by_nojoch else "")
		_npc.update_view(delta, by_yaxche, me.global_position, _hud.dialogue_open())
		_audio.listener = me.global_position
		_audio.set_layer_distance("amb_brasero", Vector3(0, 1.2, 0), 0.8)
		_update_soundscape(delta, me.global_position)
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
	if _boss != null:
		_boss.update_view(delta)
		var where := {}
		for slot in _avatars:
			where[slot] = (_avatars[slot] as Node3D).global_position
		_arena.update_view(delta, _boss.position, where)
		# El contacto del ritual suena mientras este jugador lo mantiene
		_touch_sfx -= delta
		if _boss_state.size() >= 24 and _boss_phase() == BossDef.RECUERDO and (int(_boss_state[22]) & (1 << _my_slot)) != 0 and _touch_sfx <= 0.0:
			_touch_sfx = 1.75
			Audio.play("ritual_toque", null, -2.0, 0.0)

	# Chispas en vuelo (las retira el servidor al impactar; aquí sólo avanzan)
	for id in _bolts.keys():
		if not _advance_bolt(_bolts[id], delta):
			_bolts.erase(id)
	_local_bolts = _local_bolts.filter(func(b: Dictionary) -> bool: return _advance_bolt(b, delta))

	# Puerta y sello del santuario, glifo, fuego
	# El portal se abre a la vista: espera mientras se prepara una escena y mientras dure un plano
	# que lo quiere sellado; al volver de una escena ya está abierto del todo.
	var gate_held := not _prep.is_empty() or bool(_cine.current_shot().get("hold_gate", false))
	if _gate_open and _gate_anim < 1.0 and not gate_held:
		_gate_anim = minf(1.0, _gate_anim + delta * 0.8)
	_builder.update(_time, delta, _gate_anim)

	# Con el menú abierto, su botón de pantalla completa refleja lo que hizo el navegador
	if _hud.menu_open():
		_fs_poll -= delta
		if _fs_poll <= 0.0:
			_fs_poll = 0.5
			_hud.set_menu_fullscreen(_fs_text())
	_update_cine_flow(delta)
	if _custom.active:
		# Una emboscada, una escena o un golpe cierran el personalizador sin guardar
		if not _custom_only and (_encounter == 1 or _frozen or _cine.active or _pred.dead or not _prep.is_empty()):
			_custom.close(false)
		else:
			_custom.process(delta)
	elif not _cine.process(delta):
		_update_camera()
	_update_cine_stage(delta)
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
		text = "" if _hud.dialogue_open() else "F  ·  Hablar con %s" % Story.NPCS[_talk_npc].name
	elif not _pred.dead:
		var can_touch := _pred.form == "alux"
		text = _boss_hint(here, can_touch)
		for id in _enemies:
			var v: EnemyView = _enemies[id]
			if not v.purifiable():
				continue
			if Vector2(v.global_position.x - here.x, v.global_position.z - here.y).length() < 3.6:
				text = "F  ·  Purificar a la criatura" if can_touch else "1  ·  Vuelve a ser alux para purificarla"
		if text.is_empty() and _brazier_ready and _hp < Defs.MAX_HP - 1.0 and (here - Defs.BRAZIER).length() < Defs.BRAZIER_RANGE:
			text = "F  ·  Tocar el brasero para curar al grupo" if can_touch else "1  ·  Vuelve a ser alux para tocar el brasero"
	_hud.context_hint(text)


## Qué se puede hacer aquí durante el combate con el guardián (según la forma del jugador).
func _boss_hint(here: Vector2, can_touch: bool) -> String:
	var b := _boss_state
	if b.size() < 24 or _boss == null:
		return ""
	var st := _boss_action()
	var to_boss := Vector2(_boss.position.x - here.x, _boss.position.z - here.y).length()
	match _boss_phase():
		BossDef.FURIA:
			if st == "bound" and to_boss < 6.0:
				return "Clic  ·  ¡Golpea el corazón!" if not can_touch else "2  ·  Llama a Balam para golpear el corazón"
			if st == "stunned" or st == "bound":
				for i in BossDef.ANCHORS.size():
					if (int(b[14]) & (1 << i)) == 0 and (here - BossDef.ANCHORS[i]).length() < 4.0:
						return "Pisa el ancla de jade"
			if (b[16] as Array).size() < int(BossDef.PILLARS.count) and st != "kneel" and st != "transit":
				for i in BossDef.PILLAR_SPOTS.size():
					if not _arena.pillar_up(i) and (here - BossDef.PILLAR_SPOTS[i]).length() < float(BossDef.PILLARS.touch):
						return "F  ·  Despertar la columna" if can_touch else "1  ·  Vuelve a ser alux para despertar la columna"
		BossDef.RECUERDO:
			if st == "ritual" and int(b[19]) >= int(b[20]) and to_boss < float(BossDef.RITUAL.range) + 1.5:
				if to_boss > float(BossDef.RITUAL.range):
					return "Acércate más al guardián"
				return "Mantén F  ·  Tocar al guardián" if can_touch else "1  ·  Vuelve a ser alux para tocarlo"
	return ""


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
		pos += Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * _shake * 0.35 * float(_settings.shake) / 0.6
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
	# Combate con el guardián: segundos en cada fase y cuántos de ellos como Balam
	var phase := _boss_phase()
	if _encounter == 2 and phase >= BossDef.OLVIDO and phase <= BossDef.RECUERDO and not _frozen:
		(_pt.secs as Array)[phase - 1] = int((_pt.secs as Array)[phase - 1]) + 1
		if _pred.form == "balam":
			_pt.balam = int(_pt.balam) + 1
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
		"audio": {"master": _settings.vol_master, "music": _settings.vol_music, "sfx": _settings.vol_sfx, "amb": _settings.vol_amb,
			"ui": _settings.vol_ui, "cine": _settings.vol_cine},
		"cine": _cine_metrics(),
		"boss": {"secs": _pt.secs, "fails": _pt.fails, "dmg": _pt.dmg, "falls": _pt.falls, "balam": _pt.balam,
			"freed": _pt.freed, "denied": _pt.denied},
	}
	# El navegador añade resolución y estado del audio; keepalive deja terminar el envío al salir de la página
	_js("(function(b){try{b.viewport=innerWidth+'x'+innerHeight;b.dpr=devicePixelRatio||1;" +
"b.audio.context=(window.ALUX_AUDIO&&ALUX_AUDIO.state)||'';" +
		# lo que de verdad salió por la salida de audio durante la sesión (pico máximo, 0–1)
		"if(window.ALUX_SND&&ALUX_SND.ok){b.audio.peak=+ALUX_SND.peakMax.toFixed(4);b.audio.unlockMs=ALUX_SND.unlockMs;" +
		"b.audio.errors=ALUX_SND.errors.slice(-4);b.audio.tracks=Object.keys(ALUX_SND.loaded).length}" +
		"fetch('/api/v1/telemetry',{method:'POST',keepalive:true,credentials:'same-origin'," +
		"headers:{'content-type':'application/json','x-alux-csrf':'1'},body:JSON.stringify(b)}).catch(function(){})}catch(e){}})(%s)" % JSON.stringify(body))


## Cinemáticas de la sesión: cuántas se vieron como vídeo, cuántas con el motor y qué falló.
func _cine_metrics() -> Dictionary:
	var info: Dictionary = _video.info()
	var stats: Dictionary = info.get("stats", {})
	var fails := []
	for entry in info.get("log", []):
		fails.append("%s:%s" % [str(entry.get("id", "")), str(entry.get("what", ""))])
	return {"video": _cine_stats.video, "engine": _cine_stats.engine, "fallbacks": _cine_stats.fallbacks, "skipped": _cine_stats.skipped,
		"bytes": int(stats.get("bytes", 0)), "preloadMs": int(stats.get("preloadMs", 0)), "fails": fails}


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
			"color": "#" + av.color.to_html(false), "hat": av.hat, "look": av.look,   # el aspecto que se está dibujando
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
		"boss": _boss_state, "boss_glb": _boss.uses_glb if _boss != null else false, "boss_bar": _hud.boss_open(),
		"frozen": _frozen, "skip_votes": _skip_votes, "skip_voted": _skip_voted,
		"cine_phase": _cine_phase, "cine_video": _cine.using_video(), "fade": snappedf(_hud.fade_alpha(), 0.01),
		"video": _video.info(), "cine_stats": _cine_stats, "prep": not _prep.is_empty(),
		"ui": {"intro": _hud.intro_open(), "menu": _hud.menu_open(), "result": _hud.result_open(), "help": _hud.help_open(),
			"dialog": _hud.dialogue_open(), "cine": _hud.cine_open(),
			"objective": _hud.objective_text(), "captured": Input.mouse_mode == Input.MOUSE_MODE_CAPTURED},
		"votes": _votes, "connected": _connected, "lock": _lock, "voted": _voted,
		"stats": _stats, "audio": _audio.loaded(), "music": _audio.music(), "snd": _audio.info(), "custom": _custom.info(), "audio_status": _hud.menu_audio_text(), "settings": _settings,
		"metrics": {"sid": _m.sid, "seconds": _m.seconds, "samples": (_m.fps as Array).size(), "loadMs": _m.load_ms},
	}
	_js("window.__aluxState = %s" % JSON.stringify(state))
