extends CanvasLayer
## Interfaz de ALUX: grupo, objetivo, brújula, vida y energía, habilidades,
## formas, avisos y ayuda. Sólo muestra datos; no decide nada.
## El estilo (placas, medallones, iconos) vive en ui/ui_kit.gd.

signal form_requested(form: String)

const Defs := preload("res://scripts/shared/combat_def.gd")
const World := preload("res://scripts/shared/world_def.gd")
const Kit := preload("res://scripts/client/ui/ui_kit.gd")

const FORM_ACCENT := {"alux": Kit.JADE, "balam": Kit.AMBER}
const KEY_HINTS := ["Clic · J", "Clic der. · K", "F"]


# ───────────────────────── Piezas ─────────────────────────

## Contenedor con aspecto de placa tallada.
class Plaque:
	extends PanelContainer
	var accent := Kit.JADE
	var radius := 16.0
	var studs := true

	func _init(margin := 12, p_accent := Kit.JADE, p_radius := 16.0) -> void:
		accent = p_accent
		radius = p_radius
		var sb := StyleBoxEmpty.new()
		sb.set_content_margin_all(margin)
		add_theme_stylebox_override("panel", sb)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func set_accent(c: Color) -> void:
		if c != accent:
			accent = c
			queue_redraw()

	func _draw() -> void:
		Kit.draw_plaque(self, Rect2(Vector2.ZERO, size), accent, radius, studs)


## Medallón con icono (retrato de forma, estado…).
class Medallion:
	extends Control
	var icon := "alux"
	var ring := Kit.JADE
	var icon_color := Kit.JADE
	var glow := 0.0
	var dim := false
	var portrait: Texture2D

	func _init(diameter: float) -> void:
		custom_minimum_size = Vector2(diameter, diameter)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func configure(p_icon: String, p_ring: Color, p_icon_color: Color, p_glow := 0.0, p_dim := false) -> void:
		if p_icon == icon and p_ring == ring and p_icon_color == icon_color and is_equal_approx(p_glow, glow) and p_dim == dim:
			return
		icon = p_icon
		ring = p_ring
		icon_color = p_icon_color
		glow = p_glow
		dim = p_dim
		queue_redraw()

	func _draw() -> void:
		var c := size * 0.5
		var r := minf(size.x, size.y) * 0.5 - 2.0
		Kit.draw_medallion(self, c, r, ring if not dim else ring.darkened(0.5), glow)
		if portrait != null:
			var d := r * 1.34
			draw_texture_rect(portrait, Rect2(c - Vector2(d, d) * 0.5, Vector2(d, d)), false, Color(1, 1, 1, 0.5 if dim else 1.0))
		else:
			Kit.draw_icon(self, icon, c, r * 0.62, icon_color if not dim else icon_color.darkened(0.45))


## Barra con transición suave y "estela" que muestra lo recién perdido.
class Gauge:
	extends Control
	var value := 1.0      # 0..1 real
	var shown := 1.0      # lo que se dibuja (suavizado)
	var ghost := 1.0      # estela de daño
	var color := Kit.BLOOD
	var flash := 0.0
	var flash_color := Color.WHITE
	var ticks := 0

	func _init(p_color: Color, height: float, width := 0.0, p_ticks := 0) -> void:
		color = p_color
		ticks = p_ticks
		custom_minimum_size = Vector2(width, height)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func set_value(v: float) -> void:
		v = clampf(v, 0.0, 1.0)
		if v > value + 0.02:
			flash = 1.0
			flash_color = Color(0.6, 1.0, 0.7)
		elif v < value - 0.005:
			flash = 1.0
			flash_color = Color(1.0, 1.0, 1.0)
		value = v

	func _process(delta: float) -> void:
		var before := shown + ghost + flash
		shown = lerpf(shown, value, minf(1.0, delta * 14.0))
		if absf(shown - value) < 0.002:
			shown = value
		ghost = maxf(shown, ghost - delta * 0.35) if ghost > shown else shown
		flash = maxf(0.0, flash - delta * 3.0)
		if not is_equal_approx(before, shown + ghost + flash):
			queue_redraw()

	func _draw() -> void:
		var r := size.y * 0.5
		draw_style_box(Kit.flat(Color(0, 0, 0, 0.62), r, 2, Kit.INK), Rect2(Vector2.ZERO, size))
		var inner := Rect2(Vector2(3, 3), size - Vector2(6, 6))
		if ghost > shown + 0.003:
			draw_style_box(Kit.flat(Color(1.0, 0.9, 0.6, 0.75), inner.size.y * 0.5), Rect2(inner.position, Vector2(maxf(inner.size.y, inner.size.x * ghost), inner.size.y)))
		if shown > 0.003:
			var w := maxf(inner.size.y, inner.size.x * shown)
			var fill := Rect2(inner.position, Vector2(w, inner.size.y))
			draw_style_box(Kit.flat(color.lerp(flash_color, flash * 0.6), inner.size.y * 0.5), fill)
			# brillo superior
			draw_style_box(Kit.flat(Color(1, 1, 1, 0.22), inner.size.y * 0.25), Rect2(fill.position + Vector2(3, 1.5), Vector2(maxf(0.0, w - 6.0), inner.size.y * 0.32)))
		for i in range(1, ticks):
			var x := inner.position.x + inner.size.x * float(i) / float(ticks)
			draw_line(Vector2(x, inner.position.y + 1.0), Vector2(x, inner.end.y - 1.0), Color(0, 0, 0, 0.45), 1.5)


## Ranura de habilidad: icono, tecla, enfriamiento y destello al usarla.
class AbilitySlot:
	extends Control
	var icon := "bolt"
	var accent := Kit.JADE
	var key := ""
	var cooldown := 0.0     # 0 lista · 1 recién usada
	var seconds := 0.0
	var lacks := false
	var charge := 0.0
	var flash := 0.0

	func _init(p_key: String) -> void:
		key = p_key
		custom_minimum_size = Vector2(66, 66)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func update(p_icon: String, p_accent: Color, p_cd: float, p_seconds: float, p_lacks: bool, p_charge: float) -> void:
		if p_cd > cooldown + 0.3:
			flash = 1.0   # acaba de activarse
		var changed := p_icon != icon or p_accent != accent or absf(p_cd - cooldown) > 0.004 or p_lacks != lacks or absf(p_charge - charge) > 0.01
		icon = p_icon
		accent = p_accent
		cooldown = p_cd
		seconds = p_seconds
		lacks = p_lacks
		charge = p_charge
		if changed:
			queue_redraw()

	func _process(delta: float) -> void:
		if flash > 0.0:
			flash = maxf(0.0, flash - delta * 3.5)
			queue_redraw()

	func _draw() -> void:
		var rect := Rect2(Vector2.ZERO, size)
		var usable := cooldown <= 0.001 and not lacks
		var edge := accent if usable else accent.darkened(0.55)
		if charge > 0.0:
			edge = Kit.GOLD.lerp(Kit.MAGENTA, charge)
		draw_style_box(Kit.flat(Color(0, 0, 0, 0.4), 16.0), Rect2(Vector2(0, 3), size))
		draw_style_box(Kit.flat(Kit.OBSIDIAN_SOLID.lerp(accent, 0.1 if usable else 0.02), 15.0, 2, Kit.INK), rect)
		var rim := Kit.flat(Color.TRANSPARENT, 12.0, 2, edge)
		rim.draw_center = false
		draw_style_box(rim, rect.grow(-3.0))
		var c := size * 0.5 + Vector2(0, 2)
		var tint := Color.WHITE.lerp(accent, 0.55) if usable else Color(0.55, 0.6, 0.6)
		if lacks:
			tint = Color(0.4, 0.5, 0.6)
		Kit.draw_icon(self, icon, c, size.x * (0.27 + 0.04 * flash + 0.05 * charge), tint)
		# enfriamiento: cortina que baja
		if cooldown > 0.001:
			var h := (size.y - 8.0) * clampf(cooldown, 0.0, 1.0)
			draw_style_box(Kit.flat(Color(0, 0, 0, 0.62), 10.0), Rect2(Vector2(4, size.y - 4.0 - h), Vector2(size.x - 8.0, h)))
			if seconds >= 0.6:
				var txt := "%.0f" % ceilf(seconds)
				var f := Kit.title_font()
				var w := f.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 22).x
				draw_string(f, Vector2((size.x - w) * 0.5, size.y * 0.5 + 9.0), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color(1, 1, 1, 0.95))
		if charge > 0.0:
			draw_arc(c, size.x * 0.44, -PI * 0.5, -PI * 0.5 + TAU * charge, 32, Kit.GOLD, 3.0, true)
		if flash > 0.0:
			var ring := Kit.flat(Color.TRANSPARENT, 15.0 + 6.0 * (1.0 - flash), 3, Color(1, 1, 1, flash))
			ring.draw_center = false
			draw_style_box(ring, rect.grow(6.0 * (1.0 - flash)))
		# tecla
		var kf := Kit.bold_font()
		var kw := kf.get_string_size(key, HORIZONTAL_ALIGNMENT_LEFT, -1, 10).x + 10.0
		draw_style_box(Kit.flat(Kit.INK, 6.0, 1, Color(1, 1, 1, 0.25)), Rect2(Vector2((size.x - kw) * 0.5, -7.0), Vector2(kw, 15.0)))
		draw_string(kf, Vector2((size.x - kw) * 0.5 + 5.0, 4.0), key, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(1, 1, 1, 0.85))


## Brújula: marca dónde quedan los lugares importantes respecto a la cámara.
class Compass:
	extends Control
	var yaw := 0.0
	var pos := Vector2.ZERO
	var marks: Array = []   # [icono, color, Vector2]

	func _init() -> void:
		custom_minimum_size = Vector2(420, 26)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func update(p_yaw: float, p_pos: Vector2) -> void:
		if absf(angle_difference(p_yaw, yaw)) > 0.004 or p_pos.distance_to(pos) > 0.2:
			yaw = p_yaw
			pos = p_pos
			queue_redraw()

	func _draw() -> void:
		var mid := size.x * 0.5
		var cy := size.y * 0.5
		draw_line(Vector2(8, cy), Vector2(size.x - 8.0, cy), Color(1, 1, 1, 0.16), 2.0, true)
		draw_colored_polygon(PackedVector2Array([Vector2(mid - 5.0, 0), Vector2(mid + 5.0, 0), Vector2(mid, 6.0)]), Kit.GOLD)
		var span := 1.25   # radianes visibles a cada lado
		var f := Kit.bold_font()
		for card in [["N", PI], ["E", PI * 0.5], ["S", 0.0], ["O", -PI * 0.5]]:
			var d := angle_difference(yaw, card[1])
			if absf(d) < span:
				var x := mid - d / span * (mid - 14.0)
				draw_string(f, Vector2(x - 4.0, cy + 4.5), card[0], HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(1, 1, 1, 0.45 * (1.0 - absf(d) / span) + 0.2))
		for m in marks:
			var to: Vector2 = m[2] - pos
			if to.length() < 3.0:
				continue
			var d := angle_difference(yaw, atan2(to.x, to.y))
			var x := mid - clampf(d / span, -1.0, 1.0) * (mid - 14.0)
			var edge := absf(d) >= span
			var col: Color = m[1]
			col.a = 0.45 if edge else 1.0
			draw_circle(Vector2(x, cy), 10.0, Color(0, 0, 0, 0.55))
			Kit.draw_icon(self, m[0], Vector2(x, cy), 6.0 if edge else 7.5, col)


# ───────────────────────── Estado ─────────────────────────

var _room_code: Label
var _players_box: VBoxContainer
var _rows := {}               # slot -> {medal, bar, name, state}
var _team := {}               # slot -> {form, dead, on, hp}
var _objective_plaque: Plaque
var _objective_icon: Medallion
var _objective: Label
var _objective_kind := ""
var _compass: Compass
var _banner: Label
var _banner_time := 0.0
var _overlay: ColorRect
var _overlay_label: Label
var _hp: Gauge
var _hp_text: Label
var _energy: Gauge
var _me_medal: Medallion
var _slots: Array[AbilitySlot] = []
var _slot_names: Array[Label] = []
var _forms := {}              # forma -> {button, medal}
var _death: Label
var _vignette: ColorRect
var _perf: Label
var _hint_plaque: Plaque
var _hint: Label
var _hint_time := 0.0
var _hint_sticky := ""
var _help: Plaque
var _toast: Plaque
var _toast_label: Label
var _toast_time := 0.0
var _last_form := ""
var _portraits := {}


func _ready() -> void:
	for f in ["alux", "balam"]:
		var path := "res://assets/ui/portrait_%s.png" % f
		if ResourceLoader.exists(path):
			_portraits[f] = load(path)
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	# Destello de daño / curación
	_vignette = ColorRect.new()
	_vignette.color = Color(0.9, 0.1, 0.15, 0.0)
	_vignette.set_anchors_preset(Control.PRESET_FULL_RECT)
	_vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_vignette)

	_build_party(root)
	_build_top(root)
	_build_bottom(root)
	_build_hints(root)

	# Aviso grande
	_banner = Kit.label("", 38, Kit.GOLD, Kit.title_font())
	_banner.set_anchors_preset(Control.PRESET_CENTER)
	_banner.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_banner.grow_vertical = Control.GROW_DIRECTION_BOTH
	_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_banner.position.y -= 130
	_banner.add_theme_constant_override("outline_size", 12)
	_banner.add_theme_color_override("font_outline_color", Color(0.04, 0.07, 0.06, 0.92))
	_banner.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.5))
	_banner.add_theme_constant_override("shadow_offset_y", 4)
	_banner.modulate.a = 0.0
	root.add_child(_banner)

	_death = Kit.label("", 30, Color(1.0, 0.72, 0.72), Kit.title_font())
	_death.set_anchors_preset(Control.PRESET_CENTER)
	_death.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_death.grow_vertical = Control.GROW_DIRECTION_BOTH
	_death.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_death.add_theme_constant_override("outline_size", 10)
	_death.visible = false
	root.add_child(_death)

	# Recompensa (arriba a la derecha)
	_toast = Plaque.new(12, Kit.GOLD)
	root.add_child(_toast)
	var trow := HBoxContainer.new()
	trow.add_theme_constant_override("separation", 10)
	_toast.add_child(trow)
	var seal := Medallion.new(40)
	seal.configure("success", Kit.GOLD, Kit.GOLD, 1.0)
	trow.add_child(seal)
	_toast_label = Kit.label("", 15, Kit.LIME, Kit.bold_font())
	trow.add_child(_toast_label)
	_toast.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT, Control.PRESET_MODE_MINSIZE, 16)
	_toast.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_toast.position.y = 64
	_toast.modulate.a = 0.0

	# Rendimiento (F3)
	_perf = Kit.label("", 12, Color(0.8, 1.0, 0.9))
	root.add_child(_perf)
	_perf.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT, Control.PRESET_MODE_MINSIZE, 14)
	_perf.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_perf.position.y = 130
	_perf.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_perf.visible = false

	# Pantalla de conexión
	_overlay = ColorRect.new()
	_overlay.color = Color(0.02, 0.05, 0.045, 0.86)
	_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_overlay)
	var col := VBoxContainer.new()
	col.set_anchors_preset(Control.PRESET_CENTER)
	col.grow_horizontal = Control.GROW_DIRECTION_BOTH
	col.grow_vertical = Control.GROW_DIRECTION_BOTH
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override("separation", 6)
	_overlay.add_child(col)
	var logo := Kit.label("ALUX", 76, Kit.GOLD, Kit.title_font())
	logo.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	logo.add_theme_constant_override("outline_size", 14)
	col.add_child(logo)
	_overlay_label = Kit.label("Conectando…", 20, Kit.LIME)
	_overlay_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_overlay_label.custom_minimum_size = Vector2(620, 0)
	_overlay_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(_overlay_label)


func _build_party(root: Control) -> void:
	var panel := Plaque.new(14)
	panel.position = Vector2(16, 16)
	panel.custom_minimum_size = Vector2(250, 0)
	root.add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	panel.add_child(v)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 8)
	v.add_child(head)
	var tag := Kit.label("SALA", 11, Color(1, 1, 1, 0.55), Kit.bold_font())
	tag.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(tag)
	_room_code = Kit.label("······", 20, Kit.GOLD, Kit.title_font())
	head.add_child(_room_code)
	_players_box = VBoxContainer.new()
	_players_box.add_theme_constant_override("separation", 7)
	v.add_child(_players_box)


func _build_top(root: Control) -> void:
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 5)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(col)
	col.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP, Control.PRESET_MODE_MINSIZE, 14)
	col.grow_horizontal = Control.GROW_DIRECTION_BOTH

	_objective_plaque = Plaque.new(8, Kit.JADE, 22.0)
	_objective_plaque.studs = false
	_objective_plaque.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	col.add_child(_objective_plaque)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	_objective_plaque.add_child(row)
	_objective_icon = Medallion.new(30)
	row.add_child(_objective_icon)
	_objective = Kit.label("", 16, Kit.LIME, Kit.bold_font())
	_objective.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(_objective)
	var pad := Control.new()
	pad.custom_minimum_size = Vector2(8, 0)
	row.add_child(pad)

	_compass = Compass.new()
	_compass.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_compass.marks = [
		["brazier", Kit.AMBER, Vector2(0, 0)],
		["pyramid", Kit.LIME, World.PYRAMID],
		["cenote", Kit.TURQUOISE, World.CENOTE],
		["sanctuary", Kit.MAGENTA, World.SANCTUARY - Vector2(7, 0)],
		["ledge", Kit.GOLD, World.LEDGE],
	]
	col.add_child(_compass)


func _build_bottom(root: Control) -> void:
	var bar := Plaque.new(12, Kit.JADE, 22.0)
	root.add_child(bar)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.add_child(row)

	# Retrato de la forma actual + vida y energía
	_me_medal = Medallion.new(78)
	_me_medal.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(_me_medal)
	var vit := VBoxContainer.new()
	vit.add_theme_constant_override("separation", 5)
	vit.alignment = BoxContainer.ALIGNMENT_CENTER
	vit.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(vit)
	_hp = Gauge.new(Kit.BLOOD, 24, 250)
	vit.add_child(_hp)
	_hp_text = Kit.label("100", 13, Color.WHITE, Kit.bold_font())
	_hp_text.set_anchors_preset(Control.PRESET_FULL_RECT)
	_hp_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hp_text.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_hp.add_child(_hp_text)
	_energy = Gauge.new(Kit.TURQUOISE, 13, 250, 4)
	vit.add_child(_energy)

	row.add_child(_divider())

	# Habilidades
	for i in 3:
		var col := VBoxContainer.new()
		col.add_theme_constant_override("separation", 3)
		col.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var slot := AbilitySlot.new(KEY_HINTS[i])
		slot.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		col.add_child(slot)
		var name_l := Kit.label("", 11, Color(1, 1, 1, 0.8))
		name_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		name_l.custom_minimum_size = Vector2(92, 0)
		col.add_child(name_l)
		row.add_child(col)
		_slots.append(slot)
		_slot_names.append(name_l)

	row.add_child(_divider())

	# Formas
	for def in [["alux", "1"], ["balam", "2"]]:
		var id: String = def[0]
		var b := Button.new()
		b.flat = true
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(58, 76)
		for st in ["normal", "hover", "pressed", "disabled", "focus"]:
			b.add_theme_stylebox_override(st, StyleBoxEmpty.new())
		b.pressed.connect(func() -> void: form_requested.emit(id))
		var medal := Medallion.new(52)
		medal.position = Vector2(3, 0)
		medal.portrait = _portraits.get(id)
		b.add_child(medal)
		var l := Kit.label("%s  %s" % [def[1], Defs.FORMS[id].name], 11, Color(1, 1, 1, 0.85), Kit.bold_font())
		l.position = Vector2(0, 56)
		l.custom_minimum_size = Vector2(58, 0)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		b.add_child(l)
		row.add_child(b)
		_forms[id] = {"button": b, "medal": medal}

	bar.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM, Control.PRESET_MODE_MINSIZE, 14)
	bar.grow_horizontal = Control.GROW_DIRECTION_BOTH
	bar.grow_vertical = Control.GROW_DIRECTION_BEGIN


func _divider() -> Control:
	var d := ColorRect.new()
	d.color = Color(1, 1, 1, 0.1)
	d.custom_minimum_size = Vector2(2, 60)
	d.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	d.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return d


func _build_hints(root: Control) -> void:
	# Consejo contextual discreto (abajo a la izquierda)
	_hint_plaque = Plaque.new(9, Kit.TURQUOISE, 14.0)
	_hint_plaque.studs = false
	root.add_child(_hint_plaque)
	_hint = Kit.label("", 13, Kit.LIME)
	_hint_plaque.add_child(_hint)
	# centrado, justo encima de la barra inferior
	_hint_plaque.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM, Control.PRESET_MODE_MINSIZE)
	_hint_plaque.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_hint_plaque.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_hint_plaque.position.y -= 136
	_hint_plaque.modulate.a = 0.0

	# Ayuda completa (H)
	_help = Plaque.new(18, Kit.GOLD)
	root.add_child(_help)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	_help.add_child(v)
	var title := Kit.label("CONTROLES", 20, Kit.GOLD, Kit.title_font())
	v.add_child(title)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 22)
	grid.add_theme_constant_override("v_separation", 5)
	v.add_child(grid)
	for line in [
		["W A S D", "Moverse"], ["Espacio", "Saltar"], ["Ratón  ·  Q / E", "Girar la cámara"],
		["Clic  ·  J", "Habilidad primaria (mantener)"], ["Clic derecho  ·  K", "Habilidad secundaria"],
		["F", "Habilidad especial / tocar"], ["1  ·  2", "Alux / Balam"], ["Esc", "Soltar el ratón"],
		["H", "Mostrar u ocultar esta ayuda"], ["F4", "Calidad gráfica: alta, baja o mínima"], ["F3", "Rendimiento"],
	]:
		grid.add_child(Kit.label(line[0], 14, Kit.JADE, Kit.bold_font()))
		grid.add_child(Kit.label(line[1], 14, Kit.LIME))
	_help.set_anchors_and_offsets_preset(Control.PRESET_CENTER, Control.PRESET_MODE_MINSIZE)
	_help.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_help.grow_vertical = Control.GROW_DIRECTION_BOTH
	_help.visible = false


func _process(delta: float) -> void:
	if _banner_time > 0.0:
		_banner_time -= delta
		_banner.modulate.a = clampf(_banner_time, 0.0, 1.0)
	if _vignette.color.a > 0.0:
		_vignette.color.a = maxf(0.0, _vignette.color.a - delta * 1.3)
	if _toast_time > 0.0:
		_toast_time -= delta
		_toast.modulate.a = clampf(_toast_time, 0.0, 1.0)
	if _hint_sticky.is_empty():
		if _hint_time > 0.0:
			_hint_time -= delta
		_hint_plaque.modulate.a = lerpf(_hint_plaque.modulate.a, 1.0 if _hint_time > 0.0 else 0.0, minf(1.0, delta * 5.0))
	else:
		_hint_plaque.modulate.a = lerpf(_hint_plaque.modulate.a, 1.0, minf(1.0, delta * 8.0))


# ───────────────────────── API ─────────────────────────

func set_room(code: String) -> void:
	_room_code.text = code


func set_roster(players: Array, my_id: String) -> void:
	for c in _players_box.get_children():
		c.queue_free()
	_rows.clear()
	var sorted := players.duplicate()
	sorted.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a.slot) < int(b.slot))
	for p in sorted:
		var slot := int(p.slot)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		var medal := Medallion.new(40)
		row.add_child(medal)
		var col := VBoxContainer.new()
		col.add_theme_constant_override("separation", 3)
		col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		col.alignment = BoxContainer.ALIGNMENT_CENTER
		var line := HBoxContainer.new()
		line.add_theme_constant_override("separation", 6)
		var name_l := Kit.label(str(p.name), 14, Color.WHITE, Kit.bold_font())
		name_l.clip_text = true
		name_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		line.add_child(name_l)
		var state_l := Kit.label("tú" if p.id == my_id else "", 11, Kit.GOLD)
		line.add_child(state_l)
		col.add_child(line)
		var bar := Gauge.new(Kit.BLOOD, 11)
		col.add_child(bar)
		row.add_child(col)
		_players_box.add_child(row)
		_rows[slot] = {"medal": medal, "bar": bar, "name": name_l, "state": state_l, "color": Color.from_string(str(p.color), Kit.JADE), "me": p.id == my_id}
		var info: Dictionary = _team.get(slot, {})
		info["on"] = bool(p.on)
		_team[slot] = info
	for i in range(sorted.size(), 4):
		var free_row := HBoxContainer.new()
		free_row.add_theme_constant_override("separation", 10)
		var m := Medallion.new(40)
		m.configure("", Color(1, 1, 1, 0.2), Color(1, 1, 1, 0.12), 0.0, true)
		free_row.add_child(m)
		var l := Kit.label("Lugar libre", 13, Color(1, 1, 1, 0.35))
		l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		free_row.add_child(l)
		_players_box.add_child(free_row)
	_refresh_team()


## Estado de cada jugador: slot -> {form, dead, hp}. Lo que falte se conserva.
func set_team(state: Dictionary) -> void:
	for slot in state:
		var info: Dictionary = _team.get(slot, {})
		info.merge(state[slot], true)
		_team[slot] = info
	_refresh_team()


func set_team_hp(hp_by_slot: Dictionary) -> void:
	var st := {}
	for slot in hp_by_slot:
		st[slot] = {"hp": hp_by_slot[slot]}
	set_team(st)


func _refresh_team() -> void:
	for slot in _rows:
		var row: Dictionary = _rows[slot]
		var info: Dictionary = _team.get(slot, {})
		var on: bool = info.get("on", true)
		var dead: bool = info.get("dead", false)
		var form: String = info.get("form", "alux")
		var medal: Medallion = row.medal
		var face: Texture2D = _portraits.get(form) if not dead else null
		if medal.portrait != face:
			medal.portrait = face
			medal.queue_redraw()
		medal.configure("fallen" if dead else form, row.color, Kit.BLOOD if dead else Kit.JADE.lightened(0.3), 0.0, not on)
		(row.bar as Gauge).set_value(float(info.get("hp", Defs.MAX_HP)) / Defs.MAX_HP)
		(row.bar as Gauge).modulate.a = 1.0 if on else 0.35
		(row.name as Label).modulate.a = 1.0 if on else 0.5
		var st: Label = row.state
		if not on:
			st.text = "reconectando"
			st.add_theme_color_override("font_color", Color(1, 1, 1, 0.6))
		elif dead:
			st.text = "caído"
			st.add_theme_color_override("font_color", Kit.BLOOD.lightened(0.3))
		else:
			st.text = "tú" if row.me else ""
			st.add_theme_color_override("font_color", Kit.GOLD)


## kind: "goal" (objetivo), "alert" (combate), "success" (logro)
func set_objective(text: String, kind := "goal") -> void:
	if text == _objective.text and kind == _objective_kind:
		return
	_objective.text = text
	_objective_kind = kind
	var accent: Color = {"goal": Kit.JADE, "alert": Kit.MAGENTA, "success": Kit.GOLD}.get(kind, Kit.JADE)
	_objective_plaque.set_accent(accent)
	_objective_icon.configure(kind, accent, accent, 1.0 if kind != "goal" else 0.0)
	_objective.add_theme_color_override("font_color", Kit.LIME if kind == "goal" else accent.lightened(0.45))
	# pequeño "latido" al cambiar
	_objective_plaque.pivot_offset = _objective_plaque.size * 0.5
	_objective_plaque.scale = Vector2(1.08, 1.08)
	var tw := _objective_plaque.create_tween()
	tw.tween_property(_objective_plaque, "scale", Vector2.ONE, 0.35).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)


func set_compass(cam_yaw: float, pos: Vector3) -> void:
	_compass.update(cam_yaw, Vector2(pos.x, pos.z))


func set_vitals(hp: float, energy: float) -> void:
	_hp.set_value(hp / Defs.MAX_HP)
	_hp_text.text = "%d" % int(ceil(hp))
	_energy.set_value(energy / Defs.MAX_ENERGY)


## cds = fracción restante de enfriamiento (0 lista, 1 recién usada) de cada habilidad.
func set_abilities(form: String, cds: Array, energy: float, charge: float) -> void:
	var def: Dictionary = Defs.FORMS[form]
	var keys := ["primary", "secondary", "special"]
	var accent: Color = FORM_ACCENT.get(form, Kit.JADE)
	for i in 3:
		var ab: Dictionary = def[keys[i]]
		if form != _last_form:
			_slot_names[i].text = ab.name
		var frac: float = clampf(cds[i], 0.0, 1.0)
		_slots[i].update(str(ab.kind), accent, frac, frac * float(ab.cd), energy < float(ab.get("cost", 0.0)), charge if i == 1 else 0.0)
	if form != _last_form:
		_me_medal.portrait = _portraits.get(form)
		_me_medal.queue_redraw()
		_me_medal.configure(form, accent, Kit.JADE.lightened(0.3), 1.0)
	_last_form = form


func set_forms(unlocked: Array, current: String, cooldown: float) -> void:
	for id in _forms:
		var b: Button = _forms[id].button
		var medal: Medallion = _forms[id].medal
		var active: bool = id == current
		var locked: bool = not unlocked.has(id)
		b.disabled = locked
		var accent: Color = FORM_ACCENT.get(id, Kit.JADE)
		medal.configure(id, accent if active else Color(1, 1, 1, 0.35), Kit.JADE.lightened(0.3), 1.0 if active else 0.0, locked or (not active and cooldown > 0.0))
		b.modulate.a = 1.0 if active else 0.8


func set_death(active: bool) -> void:
	_death.visible = active
	if active:
		_death.text = "HAS CAÍDO\nReapareces en el punto de control…"


func hurt() -> void:
	_vignette.color = Color(0.9, 0.1, 0.15, 0.34)


func healed() -> void:
	_vignette.color = Color(0.3, 1.0, 0.6, 0.2)


func banner(text: String, color := Kit.GOLD, seconds := 4.0) -> void:
	_banner.text = text
	_banner.add_theme_color_override("font_color", color)
	_banner_time = seconds
	_banner.modulate.a = 1.0
	_banner.pivot_offset = _banner.size * 0.5
	_banner.scale = Vector2(0.7, 0.7)
	var tw := _banner.create_tween()
	tw.tween_property(_banner, "scale", Vector2.ONE, 0.4).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)


## Aviso de recompensa obtenida.
func toast(text: String) -> void:
	_toast_label.text = text
	_toast_time = 6.0


## Consejo discreto que se desvanece solo.
func hint(text: String, seconds := 7.0) -> void:
	if _hint_sticky.is_empty():
		_hint.text = text
	_hint_time = seconds


## Consejo contextual que permanece mientras aplique ("" para quitarlo).
func context_hint(text: String) -> void:
	if text == _hint_sticky:
		return
	_hint_sticky = text
	if not text.is_empty():
		_hint.text = text
	else:
		_hint_time = 0.0


func toggle_help() -> void:
	_help.visible = not _help.visible


func set_overlay(text: String) -> void:
	_overlay.visible = not text.is_empty()
	_overlay_label.text = text


func toggle_perf() -> bool:
	_perf.visible = not _perf.visible
	return _perf.visible


func set_perf(text: String) -> void:
	_perf.text = text
