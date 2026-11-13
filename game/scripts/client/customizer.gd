extends CanvasLayer
## Personalizador 3D: el jugador ve su alux real (el mismo modelo del juego) y elige colores,
## vestimenta, tocado, accesorio y amuleto.
##
## Muestra una copia de vista previa del alux en el mundo, gira la cámara a su alrededor
## (arrastrar = girar, rueda = acercar) y guarda en el perfil a través de la API. Lo que se elige
## no se le cree al cliente: la API lo valida contra el catálogo y el servidor de juego lo relee de
## ella antes de repartirlo a la sala.
##
## Quien lo usa (game_client.gd) llama a `open()`, a `process()` en cada cuadro mientras está
## activo y escucha `saved` y `closed`.

signal saved(character: Dictionary)   ## {name, color, hat, look} tal como quedó guardado
signal closed(did_save: bool)

const Avatar := preload("res://scripts/client/avatar.gd")
const Look := preload("res://scripts/shared/look_def.gd")
const Kit := preload("res://scripts/client/ui/ui_kit.gd")
const Audio := preload("res://scripts/client/audio.gd")
const Hud := preload("res://scripts/client/hud.gd")

const FOCUS_H := 0.72          # altura a la que mira la cámara (el alux mide algo más de un metro)
const DIST_MIN := 1.5
const DIST_MAX := 5.0
const ANIMS := [["Reposo", "Idle"], ["Correr", "Run"], ["Saltar", "Jump"]]

var active := false
var standalone := false

var _cam: Camera3D
var _preview: Node3D           # Avatar de vista previa
var _center := Vector3.ZERO
var _face := 0.0               # hacia dónde mira el alux
var _yaw := 0.35               # órbita de la cámara, relativa al frente del alux
var _pitch := 0.16
var _dist := 3.2
var _yaw_to := 0.35
var _pitch_to := 0.16
var _dist_to := 3.2
var _dragging := false
var _spin := 0.0               # giro con las flechas

var _name := "Alux"
var _color := "#2ec4a6"
var _hat := 0
var _look: Array = Look.DEFAULT.duplicate()
var _initial := {}
var _anim := 0

var _root: Control
var _status: Label
var _save_button: Button
var _close_button: Button
var _groups := {}              # familia -> Array de [valor, botón]
var _saving := false
var _save_poll := 0.0
var _is_web := false


func _ready() -> void:
	layer = 20
	visible = false
	_is_web = OS.has_feature("web")
	set_process_unhandled_input(false)


## Abre el personalizador con el alux en `at`, mirando hacia `face_yaw`. `character` es el perfil
## actual: {name, color, hat, look}.
func open(host: Node3D, cam: Camera3D, at: Vector3, face_yaw: float, character: Dictionary, p_standalone := false) -> void:
	if active:
		return
	active = true
	standalone = p_standalone
	_cam = cam
	_center = at
	_face = face_yaw
	_name = str(character.get("name", "Alux"))
	_color = str(character.get("color", "#2ec4a6")).to_lower()
	_hat = clampi(int(character.get("hat", 0)), 0, Look.HATS.size() - 1)
	_look = Look.clean(character.get("look"))
	_initial = _snapshot()
	_yaw = 0.35
	_yaw_to = 0.35
	_pitch = 0.16
	_pitch_to = 0.16
	_dist = 3.2
	_dist_to = 3.2
	_anim = 0
	_saving = false
	_preview = Avatar.new()
	host.add_child(_preview)
	_preview.global_position = at
	_preview.rotation.y = face_yaw
	_rebuild_preview()
	_build_panel()
	visible = true
	set_process_unhandled_input(true)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_frame_camera(1.0)


func close(did_save := false) -> void:
	if not active:
		return
	active = false
	visible = false
	set_process_unhandled_input(false)
	if _preview != null and is_instance_valid(_preview):
		_preview.queue_free()
	_preview = null
	if _root != null:
		_root.queue_free()
		_root = null
	_groups.clear()
	closed.emit(did_save)


## Estado para las pruebas automáticas.
func info() -> Dictionary:
	return {"active": active, "name": _name, "color": _color, "hat": _hat, "look": _look, "dirty": _dirty(),
		"status": _status.text if _status != null else "", "saving": _saving, "parts": parts(),
		"yaw": snappedf(_yaw, 0.01), "dist": snappedf(_dist, 0.01), "anim": str(ANIMS[_anim][1]), "options": _offered()}


## Lo que el panel ofrece de cada familia (sólo lo que el modelo trae).
func _offered() -> Dictionary:
	var out := {}
	for family in _groups:
		var values := []
		for pair in _groups[family]:
			values.append(pair[0])
		out[family] = values
	return out


## Piezas del modelo que están a la vista ahora mismo (para comprobar que la elección se ve).
func parts() -> Array:
	var out := []
	if _preview == null or not is_instance_valid(_preview):
		return out
	for node in _preview.find_children("*", "Node3D", true, false):
		var n := str(node.name)
		if (n.begins_with("Hat_") or n.begins_with("Outfit_") or n.begins_with("Acc_") or n.begins_with("Amu_")) and (node as Node3D).is_visible_in_tree():
			var base := n.get_slice("_", 0) + "_" + n.get_slice("_", 1)
			if not out.has(base):
				out.append(base)
	out.sort()
	return out


## (pruebas) «color:#e4007c», «hat:4», «outfit:1», «accessory:2», «amulet:3», «accent:5», «skin:2»,
## «yaw:1.2», «zoom:2», «random», «reset», «save», «close».
func command(cmd: String) -> void:
	var key := cmd.get_slice(":", 0)
	var value := cmd.get_slice(":", 1) if ":" in cmd else ""
	match key:
		"color":
			_choose("color", value)
		"hat", "outfit", "accessory", "amulet", "accent", "skin":
			_choose(key, int(value))
		"yaw":
			_yaw_to = value.to_float()
		"zoom":
			_dist_to = clampf(value.to_float(), DIST_MIN, DIST_MAX)
		"random":
			_randomize()
		"reset":
			_reset()
		"save":
			_save()
		"close":
			close(false)


func _snapshot() -> Dictionary:
	return {"name": _name, "color": _color, "hat": _hat, "look": _look.duplicate()}


func _dirty() -> bool:
	return _snapshot().hash() != _initial.hash()


## Apariencia como la guarda la API: {outfit, accessory, amulet, accent, skin}.
func _look_dict() -> Dictionary:
	return {"outfit": _look[Look.OUTFIT], "accessory": _look[Look.ACCESSORY], "amulet": _look[Look.AMULET],
		"accent": _look[Look.ACCENT], "skin": _look[Look.SKIN]}


func _rebuild_preview() -> void:
	if _preview == null:
		return
	_preview.is_local = true
	_preview.setup(" ", _color, _hat, _look)
	_preview.preview_anim(str(ANIMS[_anim][1]))


# ───────────────────────── Cámara ─────────────────────────

func _unhandled_input(event: InputEvent) -> void:
	if not active:
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT or mb.button_index == MOUSE_BUTTON_RIGHT:
			_dragging = mb.pressed
		elif mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			_dist_to = clampf(_dist_to - 0.3, DIST_MIN, DIST_MAX)
		elif mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_dist_to = clampf(_dist_to + 0.3, DIST_MIN, DIST_MAX)
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion and _dragging:
		var mm := event as InputEventMouseMotion
		_yaw_to -= mm.relative.x * 0.008
		_pitch_to = clampf(_pitch_to + mm.relative.y * 0.005, -0.12, 0.95)
		get_viewport().set_input_as_handled()
	elif event is InputEventScreenDrag:
		var sd := event as InputEventScreenDrag
		_yaw_to -= sd.relative.x * 0.008
		_pitch_to = clampf(_pitch_to + sd.relative.y * 0.005, -0.12, 0.95)
		get_viewport().set_input_as_handled()
	elif event is InputEventMagnifyGesture:
		_dist_to = clampf(_dist_to / (event as InputEventMagnifyGesture).factor, DIST_MIN, DIST_MAX)
	elif event is InputEventKey:
		var k := event as InputEventKey
		if k.keycode == KEY_LEFT or k.keycode == KEY_A:
			_spin = -1.0 if k.pressed else 0.0
		elif k.keycode == KEY_RIGHT or k.keycode == KEY_D:
			_spin = 1.0 if k.pressed else 0.0
		elif k.pressed and (k.keycode == KEY_UP or k.keycode == KEY_W or k.keycode == KEY_EQUAL or k.keycode == KEY_PLUS):
			_dist_to = clampf(_dist_to - 0.3, DIST_MIN, DIST_MAX)
		elif k.pressed and (k.keycode == KEY_DOWN or k.keycode == KEY_S or k.keycode == KEY_MINUS):
			_dist_to = clampf(_dist_to + 0.3, DIST_MIN, DIST_MAX)
		elif k.pressed and k.keycode == KEY_ESCAPE and not _saving:
			close(false)
		get_viewport().set_input_as_handled()


## Avanza la cámara y el guardado. Hay que llamarlo en cada cuadro mientras está activo.
func process(delta: float) -> void:
	if not active:
		return
	_yaw_to += _spin * delta * 1.8
	_frame_camera(minf(1.0, delta * 9.0))
	if _saving:
		_save_poll -= delta
		if _save_poll <= 0.0:
			_save_poll = 0.15
			_check_saved()


func _frame_camera(k: float) -> void:
	_yaw = lerpf(_yaw, _yaw_to, k)
	_pitch = lerpf(_pitch, _pitch_to, k)
	_dist = lerpf(_dist, _dist_to, k)
	var a := _face + _yaw
	var target := _center + Vector3(0, FOCUS_H, 0)
	var offset := Vector3(sin(a) * cos(_pitch), sin(_pitch), cos(a) * cos(_pitch)) * _dist
	# El panel ocupa la derecha: el alux se encuadra un poco a la izquierda del centro
	var side := Vector3(cos(a), 0, -sin(a)) * (0.24 * _dist)
	_cam.global_position = target + offset + side
	_cam.look_at(target + side, Vector3.UP)


# ───────────────────────── Panel ─────────────────────────

func _build_panel() -> void:
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)
	var hint := Kit.label("Arrastra para girar  ·  rueda para acercar", 13, Color(1, 1, 1, 0.7))
	hint.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	hint.position = Vector2(60, -34)   # (a la derecha del botón de pantalla completa de la página)
	_root.add_child(hint)

	var panel := Hud.Plaque.new(16)
	panel.anchor_left = 1.0
	panel.anchor_right = 1.0
	panel.anchor_top = 0.0
	panel.anchor_bottom = 1.0
	panel.offset_left = -404.0
	panel.offset_right = -16.0
	panel.offset_top = 16.0
	panel.offset_bottom = -16.0
	_root.add_child(panel)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	panel.add_child(col)
	var title := Kit.label("TU ALUX", 26, Kit.GOLD, Kit.title_font())
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(title)
	var who := Kit.label(_name, 14, Kit.LIME)
	who.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(who)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	col.add_child(scroll)
	var body := VBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 6)
	scroll.add_child(body)

	_swatches(body, "color", "Color de la túnica", Look.COLORS)
	_swatches(body, "accent", "Color secundario", Look.ACCENTS)
	if _preview.has_material("Skin"):
		_swatches(body, "skin", "Piel", Look.SKINS)
	_options(body, "outfit", "Vestimenta", Look.OUTFITS)
	_options(body, "hat", "Tocado", Look.HATS)
	_options(body, "accessory", "Accesorio", Look.ACCESSORIES)
	_options(body, "amulet", "Amuleto", Look.AMULETS)

	body.add_child(_heading("Ver en movimiento"))
	var anims := HFlowContainer.new()
	anims.add_theme_constant_override("h_separation", 6)
	body.add_child(anims)
	_groups["anim"] = []
	for i in ANIMS.size():
		var b := _chip(str(ANIMS[i][0]))
		var index := i
		b.pressed.connect(func() -> void:
			_anim = index
			_preview.preview_anim(str(ANIMS[index][1]))
			_refresh())
		anims.add_child(b)
		(_groups["anim"] as Array).append([i, b])

	var tools := HBoxContainer.new()
	tools.add_theme_constant_override("separation", 8)
	col.add_child(tools)
	var rnd := _button("Al azar", false)
	rnd.pressed.connect(_randomize)
	rnd.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tools.add_child(rnd)
	var rst := _button("Deshacer cambios", false)
	rst.pressed.connect(_reset)
	rst.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tools.add_child(rst)
	_status = Kit.label("", 13, Color(1, 1, 1, 0.8))
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(_status)
	var bottom := HBoxContainer.new()
	bottom.add_theme_constant_override("separation", 8)
	col.add_child(bottom)
	_close_button = _button("Volver al portal" if standalone else "Cancelar", false)
	_close_button.pressed.connect(func() -> void:
		if not _saving:
			close(false))
	_close_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bottom.add_child(_close_button)
	_save_button = _button("Guardar", true)
	_save_button.pressed.connect(_save)
	_save_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bottom.add_child(_save_button)
	_refresh()


func _heading(text: String) -> Label:
	var l := Kit.label(text.to_upper(), 12, Kit.JADE, Kit.bold_font())
	return l


func _swatches(parent: Control, family: String, title: String, colors: Array) -> void:
	parent.add_child(_heading(title))
	var flow := HFlowContainer.new()
	flow.add_theme_constant_override("h_separation", 6)
	flow.add_theme_constant_override("v_separation", 6)
	parent.add_child(flow)
	_groups[family] = []
	for i in colors.size():
		var b := Button.new()
		b.custom_minimum_size = Vector2(34, 34)
		b.focus_mode = Control.FOCUS_NONE
		b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		b.tooltip_text = str(colors[i])
		var value: Variant = str(colors[i]) if family == "color" else i
		b.pressed.connect(func() -> void: _choose(family, value))
		b.set_meta("swatch", Color.from_string(str(colors[i]), Color.WHITE))
		flow.add_child(b)
		(_groups[family] as Array).append([value, b])


func _options(parent: Control, family: String, title: String, catalog: Array) -> void:
	parent.add_child(_heading(title))
	var flow := HFlowContainer.new()
	flow.add_theme_constant_override("h_separation", 6)
	flow.add_theme_constant_override("v_separation", 6)
	parent.add_child(flow)
	_groups[family] = []
	for i in catalog.size():
		# Sólo se ofrece lo que el modelo trae de verdad
		var needs: Variant = catalog[i][1]
		var prefix := ""
		if typeof(needs) == TYPE_ARRAY:
			prefix = str(needs[0]) if (needs as Array).size() > 1 else ""
		else:
			prefix = str(needs)
		if not prefix.is_empty() and not _preview.has_part(prefix):
			continue
		var b := _chip(str(catalog[i][0]))
		var index := i
		b.pressed.connect(func() -> void: _choose(family, index))
		flow.add_child(b)
		(_groups[family] as Array).append([i, b])


func _chip(text: String) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	b.add_theme_font_override("font", Kit.body_font())
	b.add_theme_font_size_override("font_size", 14)
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	return b


func _button(text: String, primary: bool) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(0, 40)
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var accent := Kit.GOLD if primary else Kit.JADE
	var normal := Kit.flat(Kit.OBSIDIAN_SOLID.lerp(accent, 0.16 if primary else 0.06), 12.0, 2, accent.darkened(0.25))
	var hover := Kit.flat(Kit.OBSIDIAN_SOLID.lerp(accent, 0.3), 12.0, 2, accent)
	for sb in [normal, hover]:
		sb.content_margin_left = 14
		sb.content_margin_right = 14
	b.add_theme_stylebox_override("normal", normal)
	b.add_theme_stylebox_override("hover", hover)
	b.add_theme_stylebox_override("pressed", hover)
	b.add_theme_stylebox_override("disabled", normal)
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	b.add_theme_font_override("font", Kit.bold_font())
	b.add_theme_font_size_override("font_size", 15)
	b.add_theme_color_override("font_color", accent.lightened(0.5))
	b.add_theme_color_override("font_hover_color", Color.WHITE)
	b.add_theme_color_override("font_disabled_color", Color(1, 1, 1, 0.35))
	return b


func _current(family: String) -> Variant:
	match family:
		"color":
			return _color
		"hat":
			return _hat
		"outfit":
			return _look[Look.OUTFIT]
		"accessory":
			return _look[Look.ACCESSORY]
		"amulet":
			return _look[Look.AMULET]
		"accent":
			return _look[Look.ACCENT]
		"skin":
			return _look[Look.SKIN]
		"anim":
			return _anim
	return null


## Pinta cada botón según esté elegido o no, y el estado de «Guardar».
func _refresh() -> void:
	for family in _groups:
		var now: Variant = _current(family)
		for pair in _groups[family]:
			var b: Button = pair[1]
			var on: bool = pair[0] == now
			if b.has_meta("swatch"):
				var c: Color = b.get_meta("swatch")
				for state in ["normal", "hover", "pressed"]:
					b.add_theme_stylebox_override(state, Kit.flat(c, 9.0, 3 if on else 1, Kit.GOLD if on else Color(0, 0, 0, 0.5)))
			else:
				var accent := Kit.GOLD if on else Kit.JADE
				var sb := Kit.flat(Kit.OBSIDIAN_SOLID.lerp(accent, 0.28 if on else 0.05), 10.0, 2 if on else 1, accent if on else accent.darkened(0.45))
				sb.content_margin_left = 10
				sb.content_margin_right = 10
				sb.content_margin_top = 5
				sb.content_margin_bottom = 5
				for state in ["normal", "hover", "pressed"]:
					b.add_theme_stylebox_override(state, sb)
				b.add_theme_color_override("font_color", Color.WHITE if on else Kit.LIME)
	if _save_button != null:
		_save_button.disabled = _saving or not _dirty()
		_save_button.text = "Guardando…" if _saving else ("Guardar" if _dirty() else "Guardado")


func _choose(family: String, value: Variant) -> void:
	if _saving:
		return
	match family:
		"color":
			if Look.COLORS.has(str(value).to_lower()):
				_color = str(value).to_lower()
		"hat":
			_hat = clampi(int(value), 0, Look.HATS.size() - 1)
		"outfit":
			_look[Look.OUTFIT] = clampi(int(value), 0, Look.OUTFITS.size() - 1)
		"accessory":
			_look[Look.ACCESSORY] = clampi(int(value), 0, Look.ACCESSORIES.size() - 1)
		"amulet":
			_look[Look.AMULET] = clampi(int(value), 0, Look.AMULETS.size() - 1)
		"accent":
			_look[Look.ACCENT] = clampi(int(value), 0, Look.ACCENTS.size() - 1)
		"skin":
			_look[Look.SKIN] = clampi(int(value), 0, Look.SKINS.size() - 1)
	Audio.play("ui_click")
	if _status != null:
		_status.text = ""
	_rebuild_preview()
	_refresh()


## Una combinación al azar entre lo que el modelo trae.
func _randomize() -> void:
	if _saving:
		return
	for family in ["color", "accent", "skin", "outfit", "hat", "accessory", "amulet"]:
		var list: Array = _groups.get(family, [])
		if list.is_empty():
			continue
		var pick: Variant = list[randi() % list.size()][0]
		match family:
			"color":
				_color = str(pick)
			"hat":
				_hat = int(pick)
			"outfit":
				_look[Look.OUTFIT] = int(pick)
			"accessory":
				_look[Look.ACCESSORY] = int(pick)
			"amulet":
				_look[Look.AMULET] = int(pick)
			"accent":
				_look[Look.ACCENT] = int(pick)
			"skin":
				_look[Look.SKIN] = int(pick)
	Audio.play("ui_confirmar|ui_click")
	_rebuild_preview()
	_refresh()


func _reset() -> void:
	if _saving:
		return
	_color = str(_initial.color)
	_hat = int(_initial.hat)
	_look = (_initial.look as Array).duplicate()
	Audio.play("ui_cerrar|ui_click")
	_rebuild_preview()
	_refresh()


# ───────────────────────── Guardado ─────────────────────────

func _save() -> void:
	if _saving or not _dirty():
		return
	var body := {"name": _name, "color": _color, "hat": _hat, "look": _look_dict()}
	if not _is_web:
		_done(true, "")
		return
	_saving = true
	_save_poll = 0.15
	_status.text = "Guardando…"
	_refresh()
	JavaScriptBridge.eval("(function(b){window.ALUX_LOOK_SAVE='';fetch('/api/v1/me/character',{method:'PUT',credentials:'same-origin'," +
		"headers:{'content-type':'application/json','x-alux-csrf':'1'},body:JSON.stringify(b)})" +
		".then(function(r){window.ALUX_LOOK_SAVE=r.ok?'ok':'error:'+r.status}).catch(function(){window.ALUX_LOOK_SAVE='error:red'})})(%s)" % JSON.stringify(body))


func _check_saved() -> void:
	var result := str(JavaScriptBridge.eval("window.ALUX_LOOK_SAVE || ''"))
	if result.is_empty():
		return
	_saving = false
	_done(result == "ok", result)


func _done(ok: bool, detail: String) -> void:
	if ok:
		_initial = _snapshot()
		_status.text = "Guardado. Así te verán los demás aluxes."
		Audio.play("ui_recompensa|objetivo", null, -6.0, 0.0)
		saved.emit(_snapshot())
	else:
		_status.text = "No se pudo guardar (%s). Inténtalo otra vez." % ("sin conexión" if detail.ends_with("red") else detail.trim_prefix("error:"))
		Audio.play("ui_error|sin_energia")
	_refresh()
