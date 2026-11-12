extends CanvasLayer
## Interfaz de ALUX: grupo, objetivo, brújula, vida y energía, habilidades,
## formas, avisos y ayuda. Sólo muestra datos; no decide nada.
## El estilo (placas, medallones, iconos) vive en ui/ui_kit.gd.

signal form_requested(form: String)
## Botones de menús y paneles: start, resume, help, recenter, quality, again, retry, reload, exit, menu
signal action(id: String)
## Ajustes del menú: sens, vol_master, vol_music, vol_sfx, vol_amb (0–1)
signal setting_changed(key: String, value: float)
## El jugador terminó de leer un diálogo (completed = llegó hasta el final).
signal dialogue_done(completed: bool)

const Defs := preload("res://scripts/shared/combat_def.gd")
const World := preload("res://scripts/shared/world_def.gd")
const Kit := preload("res://scripts/client/ui/ui_kit.gd")

## Nombre de la build, visible en el menú para que quien pruebe pueda citarla al reportar.
const BUILD := "ALUX Closed Alpha 0.2.1"
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
	var denied := 0.0       # > 0 mientras dura el aviso de "no se puede usar"

	func deny() -> void:
		denied = 1.0
		queue_redraw()

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
		if denied > 0.0:
			denied = maxf(0.0, denied - delta * 2.6)
			queue_redraw()

	func _draw() -> void:
		var rect := Rect2(Vector2.ZERO, size)
		if denied > 0.0:
			# sacudida lateral y borde rojo: la habilidad no está disponible
			draw_set_transform(Vector2(sin(denied * 26.0) * 5.0 * denied, 0.0))
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
		if denied > 0.0:
			var no := Kit.flat(Color(0.9, 0.15, 0.2, 0.22 * denied), 15.0, 3, Color(1.0, 0.3, 0.35, denied))
			draw_style_box(no, rect)
		if lacks and cooldown <= 0.001:
			# sin energía: gota vacía en la esquina
			draw_circle(Vector2(size.x - 11.0, size.y - 11.0), 7.0, Kit.INK)
			draw_arc(Vector2(size.x - 11.0, size.y - 11.0), 5.0, 0.0, TAU, 16, Kit.TURQUOISE.darkened(0.2), 1.6, true)
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
var _objective_detail: Label
var _free_row: Label
var _net_chip: Plaque
var _net_dot: ColorRect
var _net_label: Label
var _menu_button: Button
var _intro: Plaque
var _result: Plaque
var _result_title: Label
var _result_sub: Label
var _result_stats: GridContainer
var _result_note: Label
var _result_buttons: HBoxContainer
var _menu: Plaque
var _menu_again: Button
var _menu_quality: Button
var _sliders := {}            # clave -> HSlider
var _overlay_buttons: HBoxContainer
var _shade: ColorRect
var _low_hp := false
var _play: Control            # todo lo que se oculta durante una cinemática
var _bars: Array[ColorRect] = []
var _cine := false
var _cine_k := 0.0
var _fade: ColorRect
var _fade_tween: Tween
var _cine_sub: Label
var _cine_who: Label
var _cine_title: Label
var _cine_skip: Label
var _dialog: Plaque
var _dialog_medal: Medallion
var _dialog_name: Label
var _dialog_role: Label
var _dialog_text: Label
var _dialog_foot: Label
var _dialog_lines: Array = []
var _dialog_i := 0
var _dialog_chars := 0.0
var _base_marks: Array = []
var _altars_key := -2
var _npc_mark := ""
var _npc_pos := Vector2.ZERO
var _npc_on := false
var _pulse := 0.0
var _hurt := 0.0
var _hurt_color := Color(0.9, 0.1, 0.15)


func _ready() -> void:
	for f in ["alux", "balam", "yaxche"]:
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

	# Capa de juego: grupo, objetivo, barra y avisos. Se oculta entera durante una cinemática.
	_play = Control.new()
	_play.set_anchors_preset(Control.PRESET_FULL_RECT)
	_play.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_play)
	_build_party(_play)
	_build_top(_play)
	_build_bottom(_play)
	_build_hints(_play)

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
	_toast.position.y = 100
	_toast.modulate.a = 0.0

	# Rendimiento (F3)
	_perf = Kit.label("", 12, Color(0.8, 1.0, 0.9))
	root.add_child(_perf)
	_perf.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT, Control.PRESET_MODE_MINSIZE, 14)
	_perf.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_perf.position.y = 170
	_perf.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_perf.visible = false

	_build_status(_play)
	_build_story(root)
	_build_panels(root)

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
	_overlay_buttons = HBoxContainer.new()
	_overlay_buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	_overlay_buttons.add_theme_constant_override("separation", 12)
	col.add_child(_overlay_buttons)


## Cinemáticas (fundido, franjas, subtítulos, rótulo) y caja de diálogo.
func _build_story(root: Control) -> void:
	# Fundido a negro para entrar y salir de las cinemáticas (por debajo de sus textos)
	_fade = ColorRect.new()
	_fade.color = Color(0, 0, 0, 0)
	_fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fade.visible = false
	root.add_child(_fade)
	for top in [true, false]:
		var bar := ColorRect.new()
		bar.color = Color(0.01, 0.02, 0.02)
		bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		bar.set_anchors_preset(Control.PRESET_TOP_WIDE if top else Control.PRESET_BOTTOM_WIDE)
		bar.grow_vertical = Control.GROW_DIRECTION_END if top else Control.GROW_DIRECTION_BEGIN
		bar.custom_minimum_size = Vector2(0, 0)
		bar.visible = false
		root.add_child(bar)
		_bars.append(bar)
	_cine_title = Kit.label("", 30, Kit.GOLD, Kit.title_font())
	_cine_title.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP, Control.PRESET_MODE_MINSIZE)
	_cine_title.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_cine_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_cine_title.position.y = 104
	_cine_title.add_theme_constant_override("outline_size", 10)
	_cine_title.add_theme_color_override("font_outline_color", Color(0.03, 0.06, 0.05, 0.9))
	_cine_title.visible = false
	root.add_child(_cine_title)
	var sub := VBoxContainer.new()
	sub.add_theme_constant_override("separation", 2)
	sub.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(sub)
	sub.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM, Control.PRESET_MODE_MINSIZE)
	sub.grow_horizontal = Control.GROW_DIRECTION_BOTH
	sub.grow_vertical = Control.GROW_DIRECTION_BEGIN
	sub.position.y -= 100
	_cine_who = Kit.label("", 15, Kit.GOLD, Kit.bold_font())
	_cine_who.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.add_child(_cine_who)
	_cine_sub = Kit.label("", 21, Color(1, 0.98, 0.92), Kit.bold_font())
	_cine_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_cine_sub.custom_minimum_size = Vector2(860, 0)
	_cine_sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_cine_sub.add_theme_constant_override("outline_size", 8)
	_cine_sub.add_theme_color_override("font_outline_color", Color(0.02, 0.04, 0.04, 0.95))
	sub.add_child(_cine_sub)
	_cine_who.get_parent().visible = false
	_cine_skip = Kit.label("Enter  ·  omitir", 12, Color(1, 1, 1, 0.6), Kit.bold_font())
	_cine_skip.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT, Control.PRESET_MODE_MINSIZE, 18)
	_cine_skip.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_cine_skip.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_cine_skip.visible = false
	root.add_child(_cine_skip)

	# Caja de diálogo
	_dialog = Plaque.new(16, Kit.GOLD, 18.0)
	_dialog.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_dialog)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	_dialog.add_child(row)
	_dialog_medal = Medallion.new(84)
	_dialog_medal.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	row.add_child(_dialog_medal)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 4)
	row.add_child(col)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 10)
	col.add_child(head)
	_dialog_name = Kit.label("", 19, Kit.GOLD, Kit.title_font())
	head.add_child(_dialog_name)
	_dialog_role = Kit.label("", 12, Color(1, 1, 1, 0.55))
	_dialog_role.size_flags_vertical = Control.SIZE_SHRINK_END
	head.add_child(_dialog_role)
	_dialog_text = Kit.label("", 17, Kit.LIME)
	_dialog_text.custom_minimum_size = Vector2(640, 78)
	_dialog_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_dialog_text.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	col.add_child(_dialog_text)
	_dialog_foot = Kit.label("", 12, Color(1, 1, 1, 0.55), Kit.bold_font())
	_dialog_foot.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	col.add_child(_dialog_foot)
	_dialog.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM, Control.PRESET_MODE_MINSIZE)
	_dialog.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_dialog.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_dialog.position.y -= 132
	_dialog.visible = false


## Botón con el estilo de las placas. `primary` lo destaca en oro.
func _button(text: String, id: String, primary := false) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(0, 40)
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var accent := Kit.GOLD if primary else Kit.JADE
	var normal := Kit.flat(Kit.OBSIDIAN_SOLID.lerp(accent, 0.16 if primary else 0.06), 12.0, 2, accent.darkened(0.25))
	var hover := Kit.flat(Kit.OBSIDIAN_SOLID.lerp(accent, 0.3), 12.0, 2, accent)
	var down := Kit.flat(Kit.OBSIDIAN_SOLID.lerp(accent, 0.45), 12.0, 2, accent.lightened(0.3))
	for sb in [normal, hover, down]:
		sb.content_margin_left = 18
		sb.content_margin_right = 18
		sb.content_margin_top = 8
		sb.content_margin_bottom = 8
	b.add_theme_stylebox_override("normal", normal)
	b.add_theme_stylebox_override("hover", hover)
	b.add_theme_stylebox_override("pressed", down)
	b.add_theme_stylebox_override("disabled", normal)
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	b.add_theme_font_override("font", Kit.bold_font())
	b.add_theme_font_size_override("font_size", 15)
	b.add_theme_color_override("font_color", accent.lightened(0.5))
	b.add_theme_color_override("font_hover_color", Color.WHITE)
	b.add_theme_color_override("font_pressed_color", Color.WHITE)
	b.pressed.connect(func() -> void: action.emit(id))
	return b


## Indicador de conexión y botón de menú (arriba a la derecha).
func _build_status(root: Control) -> void:
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	col.alignment = BoxContainer.ALIGNMENT_BEGIN
	root.add_child(col)
	col.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT, Control.PRESET_MODE_MINSIZE, 14)
	col.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_menu_button = _button("Menú  ·  Esc", "menu")
	_menu_button.custom_minimum_size = Vector2(0, 32)
	_menu_button.add_theme_font_size_override("font_size", 12)
	_menu_button.size_flags_horizontal = Control.SIZE_SHRINK_END
	_menu_button.modulate.a = 0.85
	col.add_child(_menu_button)
	_net_chip = Plaque.new(7, Kit.AMBER, 12.0)
	_net_chip.studs = false
	_net_chip.size_flags_horizontal = Control.SIZE_SHRINK_END
	col.add_child(_net_chip)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 7)
	_net_chip.add_child(row)
	_net_dot = ColorRect.new()
	_net_dot.custom_minimum_size = Vector2(9, 9)
	_net_dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(_net_dot)
	_net_label = Kit.label("", 12, Kit.LIME, Kit.bold_font())
	row.add_child(_net_label)
	_net_chip.visible = false


func _center(panel: Control) -> void:
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER, Control.PRESET_MODE_MINSIZE)
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH


## Bienvenida, resultado de la partida y menú.
func _build_panels(root: Control) -> void:
	# Velo que oscurece el juego mientras hay un panel abierto
	_shade = ColorRect.new()
	_shade.color = Color(0.01, 0.03, 0.03, 0.55)
	_shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	_shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_shade.visible = false
	root.add_child(_shade)

	# ── Bienvenida ──
	_intro = Plaque.new(22, Kit.GOLD)
	_intro.mouse_filter = Control.MOUSE_FILTER_IGNORE   # un clic en cualquier parte empieza
	root.add_child(_intro)
	var iv := VBoxContainer.new()
	iv.add_theme_constant_override("separation", 10)
	_intro.add_child(iv)
	var it := Kit.label("EL CLARO DE LOS ALUXES", 26, Kit.GOLD, Kit.title_font())
	it.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	iv.add_child(it)
	var goal := Kit.label("Abran el santuario pisando los altares a la vez\ny venzan juntos a los guardianes corrompidos.", 16, Kit.LIME)
	goal.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	iv.add_child(goal)
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 14)
	grid.add_theme_constant_override("v_separation", 7)
	iv.add_child(grid)
	for line in [
		["W A S D", "Moverte"], ["Ratón", "Mirar"],
		["Espacio", "Saltar"], ["Clic", "Atacar"],
		["Clic derecho", "Esquivar"], ["F", "Tocar / purificar"],
		["1  ·  2", "Alux  ·  Balam (jaguar)"], ["Esc", "Menú y ajustes"],
	]:
		var key := Kit.label(line[0], 14, Kit.JADE, Kit.bold_font())
		key.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		key.custom_minimum_size = Vector2(110, 0)
		grid.add_child(key)
		var what := Kit.label(line[1], 14, Color(1, 1, 1, 0.9))
		what.custom_minimum_size = Vector2(170, 0)
		grid.add_child(what)
	var tip := Kit.label("Las criaturas debilitadas se pueden purificar con F siendo alux.", 13, Color(1, 1, 1, 0.65))
	tip.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	iv.add_child(tip)
	var go := _button("¡A jugar!   (clic o Enter)", "start", true)
	go.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	iv.add_child(go)
	_center(_intro)
	_intro.visible = false

	# ── Resultado ──
	_result = Plaque.new(22, Kit.GOLD)
	_result.mouse_filter = Control.MOUSE_FILTER_STOP
	root.add_child(_result)
	var rv := VBoxContainer.new()
	rv.add_theme_constant_override("separation", 10)
	_result.add_child(rv)
	_result_title = Kit.label("", 40, Kit.GOLD, Kit.title_font())
	_result_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	rv.add_child(_result_title)
	_result_sub = Kit.label("", 16, Kit.LIME)
	_result_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_result_sub.custom_minimum_size = Vector2(460, 0)
	_result_sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	rv.add_child(_result_sub)
	_result_stats = GridContainer.new()
	_result_stats.columns = 2
	_result_stats.add_theme_constant_override("h_separation", 26)
	_result_stats.add_theme_constant_override("v_separation", 4)
	_result_stats.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	rv.add_child(_result_stats)
	_result_note = Kit.label("", 13, Kit.GOLD)
	_result_note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	rv.add_child(_result_note)
	_result_buttons = HBoxContainer.new()
	_result_buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	_result_buttons.add_theme_constant_override("separation", 12)
	rv.add_child(_result_buttons)
	_center(_result)
	_result.visible = false

	# ── Menú ──
	_menu = Plaque.new(20, Kit.JADE)
	_menu.mouse_filter = Control.MOUSE_FILTER_STOP
	root.add_child(_menu)
	var mv := VBoxContainer.new()
	mv.add_theme_constant_override("separation", 8)
	_menu.add_child(mv)
	var mt := Kit.label("MENÚ", 24, Kit.GOLD, Kit.title_font())
	mt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	mv.add_child(mt)
	var note := Kit.label("La partida sigue en marcha mientras el menú está abierto.", 12, Color(1, 1, 1, 0.55))
	note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	mv.add_child(note)
	mv.add_child(_button("Continuar", "resume", true))
	_menu_again = _button("Jugar otra ronda", "again")
	mv.add_child(_menu_again)
	var two := HBoxContainer.new()
	two.add_theme_constant_override("separation", 8)
	mv.add_child(two)
	var help_b := _button("Controles  (H)", "help")
	help_b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	two.add_child(help_b)
	var rec := _button("Recentrar cámara  (R)", "recenter")
	rec.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	two.add_child(rec)
	_menu_quality = _button("Calidad gráfica: alta  (F4)", "quality")
	mv.add_child(_menu_quality)
	mv.add_child(_button("Ver la introducción del capítulo", "replay_intro"))
	var sg := GridContainer.new()
	sg.columns = 2
	sg.add_theme_constant_override("h_separation", 14)
	sg.add_theme_constant_override("v_separation", 6)
	mv.add_child(sg)
	for def in [["sens", "Sensibilidad del ratón"], ["vol_master", "Volumen general"], ["vol_music", "Música"],
			["vol_sfx", "Efectos"], ["vol_amb", "Ambiente"]]:
		sg.add_child(Kit.label(def[1], 14, Kit.LIME))
		var sl := HSlider.new()
		sl.min_value = 0.0
		sl.max_value = 1.0
		sl.step = 0.05
		sl.custom_minimum_size = Vector2(220, 22)
		sl.focus_mode = Control.FOCUS_NONE
		sl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		var key: String = def[0]
		sl.value_changed.connect(func(v: float) -> void: setting_changed.emit(key, v))
		sg.add_child(sl)
		_sliders[key] = sl
	mv.add_child(_button("Salir al portal", "exit"))
	var build := Kit.label(BUILD, 11, Color(1, 1, 1, 0.4))
	build.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	mv.add_child(build)
	_center(_menu)
	_menu.visible = false


func _build_party(root: Control) -> void:
	var panel := Plaque.new(14)
	panel.position = Vector2(16, 16)
	panel.custom_minimum_size = Vector2(226, 0)
	panel.modulate.a = 0.92
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
	var texts := VBoxContainer.new()
	texts.add_theme_constant_override("separation", 0)
	texts.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_child(texts)
	_objective = Kit.label("", 17, Kit.LIME, Kit.bold_font())
	texts.add_child(_objective)
	_objective_detail = Kit.label("", 12, Color(1, 1, 1, 0.7))
	_objective_detail.visible = false
	texts.add_child(_objective_detail)
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
	_base_marks = _compass.marks.duplicate()
	_compass.modulate.a = 0.8
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
		["F", "Habilidad especial / tocar"], ["1  ·  2", "Alux / Balam"], ["R", "Recentrar la cámara"],
		["Esc", "Menú: volumen, sensibilidad, salir"],
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
	# Franjas de cine: entran y salen deslizándose
	_cine_k = move_toward(_cine_k, 1.0 if _cine else 0.0, delta * 2.6)
	var h := 76.0 * (1.0 - pow(1.0 - _cine_k, 3.0))
	for bar in _bars:
		bar.visible = _cine_k > 0.001
		bar.custom_minimum_size.y = h
		bar.size.y = h
		if bar.anchor_top == 1.0:
			bar.position.y = get_viewport().get_visible_rect().size.y - h
	# Diálogo: el texto aparece letra a letra
	if _dialog.visible and _dialog_i < _dialog_lines.size():
		var full := str(_dialog_lines[_dialog_i])
		if int(_dialog_chars) < full.length():
			_dialog_chars = minf(float(full.length()), _dialog_chars + delta * 48.0)
			_dialog_text.visible_characters = int(_dialog_chars)
			if int(_dialog_chars) >= full.length():
				_dialog_text.visible_characters = -1
	_pulse += delta
	_hurt = maxf(0.0, _hurt - delta * 1.3)
	# con poca vida queda un latido rojo en los bordes hasta que el jugador se cura
	var low := (0.1 + 0.07 * sin(_pulse * 5.0)) if _low_hp else 0.0
	var col := _hurt_color if _hurt > low else Color(0.9, 0.1, 0.15)
	col.a = maxf(_hurt, low)
	_vignette.color = col
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
	# Los lugares libres ocupan una sola línea discreta (menos panel permanente)
	var free := 4 - sorted.size()
	if free > 0:
		var fl := Kit.label("%d lugar%s libre%s  ·  invita con el código" % [free, "" if free == 1 else "es", "" if free == 1 else "s"], 11, Color(1, 1, 1, 0.45))
		_players_box.add_child(fl)
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
			st.text = "ausente"
			st.add_theme_color_override("font_color", Color(1, 1, 1, 0.6))
		elif dead:
			st.text = "caído"
			st.add_theme_color_override("font_color", Kit.BLOOD.lightened(0.3))
		else:
			st.text = "tú" if row.me else ""
			st.add_theme_color_override("font_color", Kit.GOLD)


## kind: "goal" (objetivo), "alert" (combate), "success" (logro), "wait" (esperando)
## `detail` es una segunda línea pequeña con el paso siguiente o el estado de la espera.
func set_objective(text: String, kind := "goal", detail := "") -> void:
	if detail != _objective_detail.text:
		_objective_detail.text = detail
		_objective_detail.visible = not detail.is_empty()
	if text == _objective.text and kind == _objective_kind:
		return
	_objective.text = text
	_objective_kind = kind
	var accent: Color = {"goal": Kit.JADE, "alert": Kit.MAGENTA, "success": Kit.GOLD, "wait": Kit.TURQUOISE}.get(kind, Kit.JADE)
	_objective_plaque.set_accent(accent)
	_objective_icon.configure("goal" if kind == "wait" else kind, accent, accent, 1.0 if kind != "goal" else 0.0)
	_objective.add_theme_color_override("font_color", Kit.LIME if kind == "goal" else accent.lightened(0.45))
	# pequeño "latido" al cambiar
	_objective_plaque.pivot_offset = _objective_plaque.size * 0.5
	_objective_plaque.scale = Vector2(1.08, 1.08)
	var tw := _objective_plaque.create_tween()
	tw.tween_property(_objective_plaque, "scale", Vector2.ONE, 0.35).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)


func objective_text() -> String:
	return _objective.text


## Marca los altares en la brújula mientras haya que pisarlos (dorados los que ya están activos).
func set_altars(show: bool, mask: int) -> void:
	var key := (mask if show else -1)
	if key == _altars_key:
		return
	_altars_key = key
	var marks := _base_marks.duplicate()
	if _npc_on:
		marks.append(["alux", Kit.GOLD, _npc_pos])
	if show:
		for i in World.PLATES.size():
			var on := (mask & (1 << i)) != 0
			marks.append(["goal", Kit.GOLD if on else Kit.JADE, World.PLATES[i]])
	_compass.marks = marks
	_compass.queue_redraw()


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


## Aviso de caída con cuenta atrás. Con un panel de resultado abierto no se muestra.
func set_death(active: bool, seconds := -1.0) -> void:
	_death.visible = active and not _result.visible
	if active:
		if seconds > 0.0:
			_death.text = "HAS CAÍDO\nReapareces junto al brasero en %d…" % int(ceil(seconds))
		else:
			_death.text = "HAS CAÍDO\nReapareces en el punto de control…"


func hurt() -> void:
	_hurt = 0.38
	_hurt_color = Color(0.9, 0.1, 0.15)


func healed() -> void:
	_hurt = 0.24
	_hurt_color = Color(0.3, 1.0, 0.6)


func set_low_hp(on: bool) -> void:
	_low_hp = on


## La habilidad `index` (0–2) no se puede usar ahora: sacude su ranura y explica por qué.
func deny(index: int, why: String) -> void:
	if index >= 0 and index < _slots.size():
		_slots[index].deny()
	if not why.is_empty():
		hint(why, 1.6)


## Estado de la conexión: kind "" (oculto), "ok", "warn" o "bad".
func set_net(kind: String, text := "") -> void:
	_net_chip.visible = not kind.is_empty()
	if kind.is_empty():
		return
	var c: Color = {"ok": Kit.JADE, "warn": Kit.AMBER, "bad": Kit.BLOOD}.get(kind, Kit.AMBER)
	_net_chip.set_accent(c)
	_net_dot.color = c
	_net_label.text = text


# ───────────────────────── Paneles ─────────────────────────

func _sync_shade() -> void:
	_shade.visible = _intro.visible or _result.visible or _menu.visible


## ¿Hay algo abierto que deja quieto al personaje? (paneles, diálogo o cinemática)
func panel_open() -> bool:
	return _intro.visible or _result.visible or _menu.visible or _dialog.visible or _cine


# ───────────────────────── Cinemáticas y diálogos ─────────────────────────

## Entra o sale del modo cine: franjas negras y la interfaz de juego oculta.
func set_cine(on: bool, skippable := true) -> void:
	_cine = on
	_play.visible = not on
	_cine_skip.visible = on and skippable
	_cine_skip.text = "Enter  ·  omitir"
	if not on:
		_cine_who.get_parent().visible = false
		_cine_title.visible = false
	else:
		hide_dialogue()
		_banner_time = 0.0
		_banner.modulate.a = 0.0


func cine_open() -> bool:
	return _cine


## Funde la imagen del juego hacia negro (alpha 1) o de vuelta (alpha 0) en `secs` segundos.
func fade_to(alpha: float, secs: float) -> void:
	if _fade_tween != null and _fade_tween.is_valid():
		_fade_tween.kill()
	_fade.visible = true
	if secs <= 0.0:
		_fade.color.a = alpha
		_fade.visible = alpha > 0.0
		return
	_fade_tween = create_tween()
	_fade_tween.tween_property(_fade, "color:a", alpha, secs)
	if alpha <= 0.0:
		_fade_tween.tween_callback(func() -> void: _fade.visible = false)


func fade_alpha() -> float:
	return _fade.color.a if _fade.visible else 0.0


## Texto del aviso de omitir (en las compartidas muestra el recuento de votos).
func cine_skip_text(text: String) -> void:
	_cine_skip.text = text


## Subtítulo de una cinemática ("" lo quita). `who` es el nombre de quien habla, si habla alguien.
func cine_subtitle(who: String, text: String) -> void:
	(_cine_who.get_parent() as Control).visible = not text.is_empty()
	_cine_who.text = who
	_cine_who.visible = not who.is_empty()
	_cine_sub.text = text


func cine_title(text: String) -> void:
	_cine_title.text = text
	_cine_title.visible = not text.is_empty()
	if not text.is_empty():
		_cine_title.modulate.a = 0.0
		_cine_title.create_tween().tween_property(_cine_title, "modulate:a", 1.0, 0.8)


## Abre un diálogo. lines: textos de un mismo personaje, en orden.
func show_dialogue(speaker: String, role: String, lines: Array, accent := Kit.GOLD, portrait := "alux") -> void:
	_dialog_lines = lines
	_dialog_i = -1
	_dialog_name.text = speaker
	_dialog_role.text = role
	_dialog.set_accent(accent)
	_dialog_medal.portrait = _portraits.get(portrait)
	_dialog_medal.configure(portrait, accent, accent, 1.0)
	_dialog_medal.queue_redraw()
	_dialog.visible = true
	_hint_time = 0.0
	_next_line()


func _next_line() -> void:
	_dialog_i += 1
	if _dialog_i >= _dialog_lines.size():
		_dialog.visible = false
		dialogue_done.emit(true)
		return
	_dialog_text.text = str(_dialog_lines[_dialog_i])
	_dialog_chars = 0.0
	_dialog_text.visible_characters = 0
	var last := _dialog_i == _dialog_lines.size() - 1
	_dialog_foot.text = "%d / %d      Enter  ·  F  ·  clic:  %s" % [_dialog_i + 1, _dialog_lines.size(), "terminar" if last else "continuar"]


## Avanza el diálogo: primero completa la línea que se está escribiendo; después pasa a la siguiente.
func advance_dialogue() -> void:
	if not _dialog.visible:
		return
	if _dialog_text.visible_characters >= 0:
		_dialog_chars = 9999.0
		_dialog_text.visible_characters = -1
	else:
		_next_line()


func hide_dialogue() -> void:
	if _dialog.visible:
		_dialog.visible = false
		dialogue_done.emit(false)


func dialogue_open() -> bool:
	return _dialog.visible


## Marca de un personaje en la brújula ("" la quita).
func set_npc_mark(key: String, pos := Vector2.ZERO) -> void:
	var want := key + str(pos)
	if want == _npc_mark:
		return
	_npc_mark = want
	_npc_pos = pos
	_npc_on = not key.is_empty()
	_altars_key = -2   # obliga a recomponer las marcas


func show_intro() -> void:
	_intro.visible = true
	_sync_shade()


func hide_intro() -> void:
	_intro.visible = false
	_sync_shade()


func intro_open() -> bool:
	return _intro.visible


## kind: "victory" o "defeat". stats: [[etiqueta, valor]…]. actions: [[id, texto, destacado]…]
func show_result(kind: String, title: String, subtitle: String, stats: Array, actions: Array) -> void:
	var accent := Kit.GOLD if kind == "victory" else Kit.BLOOD
	_result.set_accent(accent)
	_result_title.text = title
	_result_title.add_theme_color_override("font_color", accent.lightened(0.15))
	_result_sub.text = subtitle
	for c in _result_stats.get_children():
		_result_stats.remove_child(c)
		c.queue_free()
	for st in stats:
		_result_stats.add_child(Kit.label(str(st[0]), 14, Color(1, 1, 1, 0.65)))
		_result_stats.add_child(Kit.label(str(st[1]), 14, Kit.LIME, Kit.bold_font()))
	_result_stats.visible = not stats.is_empty()
	for c in _result_buttons.get_children():
		_result_buttons.remove_child(c)
		c.queue_free()
	for a in actions:
		_result_buttons.add_child(_button(str(a[1]), str(a[0]), bool(a[2])))
	_result_note.text = ""
	_result_note.visible = false
	_menu.visible = false
	_result.visible = true
	_death.visible = false
	_banner_time = 0.0
	_banner.modulate.a = 0.0
	_sync_shade()
	_result.size = Vector2.ZERO   # el contenido cambió: se ajusta al mínimo y se vuelve a centrar
	_center(_result)
	_result.pivot_offset = _result.size * 0.5
	_result.scale = Vector2(0.85, 0.85)
	var tw := _result.create_tween()
	tw.tween_property(_result, "scale", Vector2.ONE, 0.35).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)


func set_result_note(text: String) -> void:
	_result_note.text = text
	_result_note.visible = not text.is_empty()


func hide_result() -> void:
	_result.visible = false
	_sync_shade()


func result_open() -> bool:
	return _result.visible


## Abre el menú con los valores actuales. `again` es el texto del botón de otra ronda ("" lo oculta).
func show_menu(settings: Dictionary, quality_name: String, again := "") -> void:
	for key in _sliders:
		(_sliders[key] as HSlider).set_value_no_signal(float(settings.get(key, 0.5)))
	update_menu(quality_name, again)
	_help.visible = false
	_menu.visible = true
	_sync_shade()


func update_menu(quality_name: String, again := "") -> void:
	_menu_quality.text = "Calidad gráfica: %s  (F4)" % quality_name
	_menu_again.visible = not again.is_empty()
	_menu_again.text = again
	_menu.size = Vector2.ZERO
	_center(_menu)


func hide_menu() -> void:
	_menu.visible = false
	_sync_shade()


func menu_open() -> bool:
	return _menu.visible


func banner(text: String, color := Kit.GOLD, seconds := 4.0) -> void:
	if _cine:
		return   # durante una cinemática no se superponen avisos
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
	if _help.visible:
		_menu.visible = false
		_sync_shade()


func help_open() -> bool:
	return _help.visible


## Pantalla completa de carga, conexión o error. actions: [[id, texto, destacado]…]
func set_overlay(text: String, actions: Array = []) -> void:
	_overlay.visible = not text.is_empty()
	_overlay_label.text = text
	for c in _overlay_buttons.get_children():
		_overlay_buttons.remove_child(c)
		c.queue_free()
	for a in actions:
		_overlay_buttons.add_child(_button(str(a[1]), str(a[0]), bool(a[2])))
	_overlay.mouse_filter = Control.MOUSE_FILTER_STOP if not actions.is_empty() else Control.MOUSE_FILTER_IGNORE


func toggle_perf() -> bool:
	_perf.visible = not _perf.visible
	return _perf.visible


func set_perf(text: String) -> void:
	_perf.text = text
