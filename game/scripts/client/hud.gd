extends CanvasLayer
## Interfaz dentro del juego: sala, jugadores, objetivo, formas y avisos.

signal form_requested(form: String)

const BG := Color(0.07, 0.1, 0.09, 0.78)
const JADE := Color(0.18, 0.9, 0.7)
const GOLD := Color(1.0, 0.82, 0.3)

var _room_label: Label
var _players_box: VBoxContainer
var _objective: Label
var _banner: Label
var _banner_time := 0.0
var _overlay: ColorRect
var _overlay_label: Label
var _slots := {}
var _hint: Label


static func _panel(margin := 12) -> PanelContainer:
	var p := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = BG
	sb.set_corner_radius_all(14)
	sb.set_content_margin_all(margin)
	sb.border_color = Color(1, 1, 1, 0.1)
	sb.set_border_width_all(1)
	p.add_theme_stylebox_override("panel", sb)
	return p


static func _label(text: String, size: int, color := Color.WHITE) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.6))
	l.add_theme_constant_override("outline_size", 4)
	return l


func _ready() -> void:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	# Sala y jugadores (arriba a la izquierda)
	var left := _panel()
	left.position = Vector2(14, 14)
	left.custom_minimum_size = Vector2(230, 0)
	left.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(left)
	var lv := VBoxContainer.new()
	lv.add_theme_constant_override("separation", 6)
	left.add_child(lv)
	_room_label = _label("SALA", 15, GOLD)
	lv.add_child(_room_label)
	_players_box = VBoxContainer.new()
	_players_box.add_theme_constant_override("separation", 4)
	lv.add_child(_players_box)

	# Objetivo (arriba al centro)
	var top := _panel(10)
	top.set_anchors_preset(Control.PRESET_CENTER_TOP)
	top.grow_horizontal = Control.GROW_DIRECTION_BOTH
	top.position.y = 14
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(top)
	_objective = _label("", 17)
	_objective.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	top.add_child(_objective)

	# Aviso grande
	_banner = _label("", 34, GOLD)
	_banner.set_anchors_preset(Control.PRESET_CENTER)
	_banner.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_banner.grow_vertical = Control.GROW_DIRECTION_BOTH
	_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_banner.position.y -= 150
	_banner.add_theme_constant_override("outline_size", 10)
	_banner.modulate.a = 0.0
	root.add_child(_banner)

	# Formas (abajo al centro)
	var bar := HBoxContainer.new()
	bar.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	bar.grow_horizontal = Control.GROW_DIRECTION_BOTH
	bar.grow_vertical = Control.GROW_DIRECTION_BEGIN
	bar.position.y -= 16
	bar.add_theme_constant_override("separation", 10)
	root.add_child(bar)
	for def in [["alux", "1", "Alux"], ["balam", "2", "Balam"]]:
		var b := Button.new()
		b.text = "%s  %s" % [def[1], def[2]]
		b.custom_minimum_size = Vector2(120, 52)
		b.focus_mode = Control.FOCUS_NONE
		b.add_theme_font_size_override("font_size", 18)
		for st in ["normal", "hover", "pressed", "disabled", "focus"]:
			var sb := StyleBoxFlat.new()
			sb.bg_color = BG if st != "hover" else Color(0.12, 0.2, 0.17, 0.9)
			sb.set_corner_radius_all(14)
			sb.set_border_width_all(2)
			sb.border_color = Color(1, 1, 1, 0.18)
			b.add_theme_stylebox_override(st, sb)
		var id: String = def[0]
		b.pressed.connect(func() -> void: form_requested.emit(id))
		bar.add_child(b)
		_slots[id] = b

	# Controles (abajo a la izquierda)
	_hint = _label("WASD moverse · Espacio saltar · 1/2 transformarse\nClic para girar la cámara con el ratón · Q/E girar · Esc soltar", 13, Color(1, 1, 1, 0.8))
	root.add_child(_hint)
	_hint.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT, Control.PRESET_MODE_MINSIZE, 14)

	# Pantalla de conexión
	_overlay = ColorRect.new()
	_overlay.color = Color(0.03, 0.06, 0.05, 0.82)
	_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_overlay)
	_overlay_label = _label("Conectando…", 26)
	_overlay_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	_overlay_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_overlay_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_overlay_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_overlay.add_child(_overlay_label)


func _process(delta: float) -> void:
	if _banner_time > 0.0:
		_banner_time -= delta
		_banner.modulate.a = clampf(_banner_time, 0.0, 1.0)


func set_room(code: String) -> void:
	_room_label.text = "SALA  %s" % code


func set_roster(players: Array, my_id: String) -> void:
	for c in _players_box.get_children():
		c.queue_free()
	var sorted := players.duplicate()
	sorted.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a.slot) < int(b.slot))
	for p in sorted:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		var dot := ColorRect.new()
		dot.custom_minimum_size = Vector2(12, 12)
		dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		dot.color = Color.from_string(str(p.color), JADE)
		row.add_child(dot)
		var name := str(p.name) + ("  (tú)" if p.id == my_id else "")
		var l := _label(name if p.on else name + " · desconectado", 15)
		l.modulate.a = 1.0 if p.on else 0.5
		row.add_child(l)
		_players_box.add_child(row)
	for i in range(sorted.size(), 4):
		var l := _label("— lugar libre —", 14, Color(1, 1, 1, 0.35))
		_players_box.add_child(l)


func set_objective(text: String) -> void:
	_objective.text = text


func set_forms(unlocked: Array, current: String, cooldown: float) -> void:
	for id in _slots:
		var b: Button = _slots[id]
		b.disabled = not unlocked.has(id)
		var active: bool = id == current
		b.add_theme_color_override("font_color", JADE.lightened(0.3) if active else Color.WHITE)
		(b.get_theme_stylebox("normal") as StyleBoxFlat).border_color = JADE if active else Color(1, 1, 1, 0.18)
		b.modulate.a = 0.5 if (not active and cooldown > 0.0) or not unlocked.has(id) else 1.0


func banner(text: String, color := GOLD, seconds := 4.0) -> void:
	_banner.text = text
	_banner.add_theme_color_override("font_color", color)
	_banner_time = seconds
	_banner.modulate.a = 1.0


func set_overlay(text: String) -> void:
	_overlay.visible = not text.is_empty()
	_overlay_label.text = text
