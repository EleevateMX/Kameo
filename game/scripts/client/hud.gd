extends CanvasLayer
## Interfaz dentro del juego: sala, jugadores, objetivo, vida, energía,
## habilidades, formas y avisos. Sólo muestra datos; no decide nada.

signal form_requested(form: String)

const Defs := preload("res://scripts/shared/combat_def.gd")

const BG := Color(0.07, 0.1, 0.09, 0.78)
const JADE := Color(0.18, 0.9, 0.7)
const GOLD := Color(1.0, 0.82, 0.3)
const RED := Color(0.93, 0.27, 0.3)

var _room_label: Label
var _players_box: VBoxContainer
var _player_bars := {}        # slot -> ProgressBar
var _objective: Label
var _banner: Label
var _banner_time := 0.0
var _overlay: ColorRect
var _overlay_label: Label
var _slots := {}
var _hp_bar: ProgressBar
var _hp_text: Label
var _en_bar: ProgressBar
var _abilities: Array = []    # [{panel, name, key, cover}]
var _death: Label
var _hurt: ColorRect
var _perf: Label
var _last_form := ""


static func _box(color: Color, radius := 14, margin := 12) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = color
	sb.set_corner_radius_all(radius)
	sb.set_content_margin_all(margin)
	return sb


static func _panel(margin := 12) -> PanelContainer:
	var p := PanelContainer.new()
	var sb := _box(BG, 14, margin)
	sb.border_color = Color(1, 1, 1, 0.1)
	sb.set_border_width_all(1)
	p.add_theme_stylebox_override("panel", sb)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return p


static func _label(text: String, size: int, color := Color.WHITE) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.6))
	l.add_theme_constant_override("outline_size", 4)
	return l


static func _bar(color: Color, height: int, width := 0) -> ProgressBar:
	var b := ProgressBar.new()
	b.show_percentage = false
	b.min_value = 0.0
	b.max_value = 100.0
	b.value = 100.0
	b.custom_minimum_size = Vector2(width, height)
	b.add_theme_stylebox_override("background", _box(Color(0, 0, 0, 0.55), height / 2, 0))
	b.add_theme_stylebox_override("fill", _box(color, height / 2, 0))
	b.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return b


func _ready() -> void:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	# Destello rojo al recibir daño
	_hurt = ColorRect.new()
	_hurt.color = Color(0.9, 0.1, 0.15, 0.0)
	_hurt.set_anchors_preset(Control.PRESET_FULL_RECT)
	_hurt.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_hurt)

	# Sala y jugadores (arriba a la izquierda)
	var left := _panel()
	left.position = Vector2(14, 14)
	left.custom_minimum_size = Vector2(236, 0)
	root.add_child(left)
	var lv := VBoxContainer.new()
	lv.add_theme_constant_override("separation", 6)
	left.add_child(lv)
	_room_label = _label("SALA", 15, GOLD)
	lv.add_child(_room_label)
	_players_box = VBoxContainer.new()
	_players_box.add_theme_constant_override("separation", 5)
	lv.add_child(_players_box)

	# Objetivo (arriba al centro)
	var top := _panel(10)
	top.set_anchors_preset(Control.PRESET_CENTER_TOP)
	top.grow_horizontal = Control.GROW_DIRECTION_BOTH
	top.position.y = 14
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

	# Aviso de caída
	_death = _label("", 30, Color(1.0, 0.7, 0.7))
	_death.set_anchors_preset(Control.PRESET_CENTER)
	_death.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_death.grow_vertical = Control.GROW_DIRECTION_BOTH
	_death.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_death.add_theme_constant_override("outline_size", 10)
	_death.visible = false
	root.add_child(_death)

	# Abajo al centro: vida, energía, habilidades y formas
	var bottom := VBoxContainer.new()
	bottom.add_theme_constant_override("separation", 8)
	bottom.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(bottom)
	bottom.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM, Control.PRESET_MODE_MINSIZE, 14)
	bottom.grow_horizontal = Control.GROW_DIRECTION_BOTH
	bottom.grow_vertical = Control.GROW_DIRECTION_BEGIN

	var vit := VBoxContainer.new()
	vit.add_theme_constant_override("separation", 4)
	vit.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bottom.add_child(vit)
	_hp_bar = _bar(RED, 18, 420)
	vit.add_child(_hp_bar)
	_hp_text = _label("100 / 100", 13)
	_hp_text.set_anchors_preset(Control.PRESET_FULL_RECT)
	_hp_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hp_text.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_hp_bar.add_child(_hp_text)
	_en_bar = _bar(Color(0.25, 0.75, 1.0), 9, 420)
	vit.add_child(_en_bar)

	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 8)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bottom.add_child(row)
	for key in ["Clic / J", "Clic der. / K", "F"]:
		var p := _panel(8)
		p.custom_minimum_size = Vector2(118, 54)
		p.clip_contents = true
		var v := VBoxContainer.new()
		v.add_theme_constant_override("separation", 0)
		v.mouse_filter = Control.MOUSE_FILTER_IGNORE
		p.add_child(v)
		var name_l := _label("", 15)
		name_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		v.add_child(name_l)
		var key_l := _label(key, 11, Color(1, 1, 1, 0.6))
		key_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		v.add_child(key_l)
		var cover := ColorRect.new()
		cover.color = Color(0, 0, 0, 0.62)
		cover.mouse_filter = Control.MOUSE_FILTER_IGNORE
		cover.set_anchors_preset(Control.PRESET_FULL_RECT)
		cover.anchor_top = 1.0
		p.add_child(cover)
		row.add_child(p)
		_abilities.append({"panel": p, "name": name_l, "cover": cover})
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(10, 0)
	row.add_child(gap)
	for def in [["alux", "1", "Alux"], ["balam", "2", "Balam"]]:
		var b := Button.new()
		b.text = "%s  %s" % [def[1], def[2]]
		b.custom_minimum_size = Vector2(96, 54)
		b.focus_mode = Control.FOCUS_NONE
		b.add_theme_font_size_override("font_size", 17)
		for st in ["normal", "hover", "pressed", "disabled", "focus"]:
			var sb := _box(BG if st != "hover" else Color(0.12, 0.2, 0.17, 0.9), 14, 6)
			sb.set_border_width_all(2)
			sb.border_color = Color(1, 1, 1, 0.18)
			b.add_theme_stylebox_override(st, sb)
		var id: String = def[0]
		b.pressed.connect(func() -> void: form_requested.emit(id))
		row.add_child(b)
		_slots[id] = b

	# Controles (abajo a la izquierda)
	var hint := _label("WASD moverse · Espacio saltar · 1/2 transformarse\nClic para capturar el ratón · Q/E girar cámara · F3 rendimiento", 12, Color(1, 1, 1, 0.75))
	root.add_child(hint)
	hint.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT, Control.PRESET_MODE_MINSIZE, 12)

	# Rendimiento (F3)
	_perf = _label("", 13, Color(0.8, 1.0, 0.9))
	root.add_child(_perf)
	_perf.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT, Control.PRESET_MODE_MINSIZE, 14)
	_perf.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_perf.position.y = 58
	_perf.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_perf.visible = false

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
	if _hurt.color.a > 0.0:
		_hurt.color.a = maxf(0.0, _hurt.color.a - delta * 1.4)


func set_room(code: String) -> void:
	_room_label.text = "SALA  %s" % code


func set_roster(players: Array, my_id: String) -> void:
	for c in _players_box.get_children():
		c.queue_free()
	_player_bars.clear()
	var sorted := players.duplicate()
	sorted.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a.slot) < int(b.slot))
	for p in sorted:
		var col := VBoxContainer.new()
		col.add_theme_constant_override("separation", 2)
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
		col.add_child(row)
		var bar := _bar(RED, 6)
		bar.modulate.a = 1.0 if p.on else 0.35
		col.add_child(bar)
		_player_bars[int(p.slot)] = bar
		_players_box.add_child(col)
	for i in range(sorted.size(), 4):
		_players_box.add_child(_label("— lugar libre —", 14, Color(1, 1, 1, 0.35)))


## Vida de cada jugador de la sala (slot -> vida 0..100).
func set_team_hp(hp_by_slot: Dictionary) -> void:
	for slot in hp_by_slot:
		var bar: ProgressBar = _player_bars.get(slot)
		if bar != null:
			bar.value = hp_by_slot[slot]


func set_objective(text: String) -> void:
	_objective.text = text


func set_vitals(hp: float, energy: float) -> void:
	_hp_bar.value = hp / Defs.MAX_HP * 100.0
	_hp_text.text = "%d / %d" % [int(ceil(hp)), int(Defs.MAX_HP)]
	_en_bar.value = energy / Defs.MAX_ENERGY * 100.0


## cds = fracción restante de enfriamiento (0 lista, 1 recién usada) de cada habilidad.
func set_abilities(form: String, cds: Array, energy: float, charge: float) -> void:
	var def: Dictionary = Defs.FORMS[form]
	var keys := ["primary", "secondary", "special"]
	for i in 3:
		var ab: Dictionary = def[keys[i]]
		var slot: Dictionary = _abilities[i]
		if form != _last_form:
			(slot.name as Label).text = ab.name
		var frac: float = clampf(cds[i], 0.0, 1.0)
		(slot.cover as ColorRect).anchor_top = 1.0 - frac
		var lacks: bool = energy < float(ab.get("cost", 0.0))
		(slot.panel as Control).modulate = Color(1, 1, 1, 0.45) if lacks else Color.WHITE
		if i == 1 and charge > 0.0:
			(slot.panel as Control).modulate = Color(1.0, 0.85, 0.4).lerp(Color(1.0, 0.4, 0.2), charge)
	_last_form = form


func set_forms(unlocked: Array, current: String, cooldown: float) -> void:
	for id in _slots:
		var b: Button = _slots[id]
		b.disabled = not unlocked.has(id)
		var active: bool = id == current
		b.add_theme_color_override("font_color", JADE.lightened(0.3) if active else Color.WHITE)
		(b.get_theme_stylebox("normal") as StyleBoxFlat).border_color = JADE if active else Color(1, 1, 1, 0.18)
		b.modulate.a = 0.5 if (not active and cooldown > 0.0) or not unlocked.has(id) else 1.0


func set_death(active: bool) -> void:
	_death.visible = active
	if active:
		_death.text = "Has caído\nReapareces en el punto de control…"


func hurt() -> void:
	_hurt.color.a = 0.32


func banner(text: String, color := GOLD, seconds := 4.0) -> void:
	_banner.text = text
	_banner.add_theme_color_override("font_color", color)
	_banner_time = seconds
	_banner.modulate.a = 1.0


func set_overlay(text: String) -> void:
	_overlay.visible = not text.is_empty()
	_overlay_label.text = text


func toggle_perf() -> bool:
	_perf.visible = not _perf.visible
	return _perf.visible


func set_perf(text: String) -> void:
	_perf.text = text
