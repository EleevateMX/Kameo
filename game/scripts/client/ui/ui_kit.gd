extends RefCounted
## Sistema visual del HUD de ALUX: paleta, tipografías y piezas dibujadas por código
## (placas talladas, medallones e iconos). No usa imágenes: todo es vectorial y escala
## con la ventana.

const OBSIDIAN := Color(0.035, 0.075, 0.07, 0.86)
const OBSIDIAN_SOLID := Color(0.05, 0.1, 0.095)
const STONE := Color(0.16, 0.24, 0.22)
const JADE := Color(0.18, 0.9, 0.69)
const JADE_DEEP := Color(0.07, 0.45, 0.38)
const TURQUOISE := Color(0.25, 0.78, 0.98)
const GOLD := Color(1.0, 0.82, 0.3)
const AMBER := Color(1.0, 0.6, 0.2)
const MAGENTA := Color(0.96, 0.22, 0.52)
const BLOOD := Color(0.92, 0.25, 0.3)
const LIME := Color(0.92, 0.88, 0.78)
const INK := Color(0.02, 0.04, 0.04)

static var _title: Font
static var _body: Font
static var _bold: Font


static func title_font() -> Font:
	if _title == null:
		_title = _load_font("res://assets/fonts/Bungee-Regular.ttf", 0)
	return _title


static func body_font() -> Font:
	if _body == null:
		_body = _load_font("res://assets/fonts/Rubik.ttf", 500)
	return _body


static func bold_font() -> Font:
	if _bold == null:
		_bold = _load_font("res://assets/fonts/Rubik.ttf", 700)
	return _bold


static func _load_font(path: String, weight: int) -> Font:
	if not ResourceLoader.exists(path):
		return ThemeDB.fallback_font
	var base := load(path) as Font
	if base == null:
		return ThemeDB.fallback_font
	if weight <= 0:
		return base
	var fv := FontVariation.new()
	fv.base_font = base
	fv.variation_opentype = {TextServerManager.get_primary_interface().name_to_tag("wght"): weight}
	return fv


static func label(text: String, size: int, color := Color.WHITE, font: Font = null) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", font if font != null else body_font())
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.55))
	l.add_theme_constant_override("outline_size", 4)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


static func flat(color: Color, radius: float, border := 0, border_color := Color.TRANSPARENT) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = color
	sb.set_corner_radius_all(int(radius))
	sb.corner_detail = 8
	sb.anti_aliasing = true
	if border > 0:
		sb.set_border_width_all(border)
		sb.border_color = border_color
	return sb


## Placa tallada: fondo de obsidiana, doble filo (oscuro por fuera, color por dentro),
## brillo superior y remaches de jade en las esquinas.
static func draw_plaque(ci: CanvasItem, rect: Rect2, accent: Color, radius := 16.0, studs := true) -> void:
	var shadow := flat(Color(0, 0, 0, 0.35), radius + 2.0)
	ci.draw_style_box(shadow, Rect2(rect.position + Vector2(0, 3), rect.size))
	ci.draw_style_box(flat(OBSIDIAN, radius, 2, Color(INK.r, INK.g, INK.b, 0.9)), rect)
	# degradado interior muy sutil (más claro arriba)
	var sheen := flat(Color(1, 1, 1, 0.045), radius - 3.0)
	sheen.corner_radius_bottom_left = 2
	sheen.corner_radius_bottom_right = 2
	ci.draw_style_box(sheen, Rect2(rect.position + Vector2(3, 3), Vector2(rect.size.x - 6.0, minf(rect.size.y * 0.45, 26.0))))
	var inner := flat(Color.TRANSPARENT, radius - 3.0, 1, Color(accent.r, accent.g, accent.b, 0.55))
	inner.draw_center = false
	ci.draw_style_box(inner, rect.grow(-3.0))
	if studs and rect.size.x > 70.0 and rect.size.y > 44.0:
		for corner in [Vector2(0, 0), Vector2(1, 0), Vector2(0, 1), Vector2(1, 1)]:
			var p: Vector2 = rect.position + Vector2(11.0, 11.0) + corner * (rect.size - Vector2(22.0, 22.0))
			diamond(ci, p, 3.2, accent)


static func diamond(ci: CanvasItem, c: Vector2, r: float, color: Color) -> void:
	ci.draw_colored_polygon(PackedVector2Array([c + Vector2(0, -r), c + Vector2(r, 0), c + Vector2(0, r), c + Vector2(-r, 0)]), color)


## Medallón redondo con aro de color.
static func draw_medallion(ci: CanvasItem, c: Vector2, r: float, ring: Color, glow := 0.0) -> void:
	if glow > 0.0:
		ci.draw_circle(c, r + 5.0, Color(ring.r, ring.g, ring.b, 0.22 * glow))
	ci.draw_circle(c + Vector2(0, 2), r + 1.0, Color(0, 0, 0, 0.4))
	ci.draw_circle(c, r, INK)
	ci.draw_circle(c, r - 2.0, OBSIDIAN_SOLID.lerp(ring, 0.16))
	ci.draw_arc(c, r - 1.5, 0.0, TAU, 48, ring, 2.6, true)
	ci.draw_arc(c, r - 5.0, 0.0, TAU, 40, Color(1, 1, 1, 0.12), 1.0, true)


static func _pts(c: Vector2, s: float, raw: Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p in raw:
		out.append(c + Vector2(p[0], p[1]) * s)
	return out


## Iconos del juego, dibujados en un cuadro de lado 2·s centrado en c.
static func draw_icon(ci: CanvasItem, icon: String, c: Vector2, s: float, color: Color) -> void:
	var dark := Color(INK.r, INK.g, INK.b, 0.85)
	match icon:
		"bolt":  # chispa de jade: estrella de cuatro puntas con estela
			var star := []
			for i in 8:
				var a := i * TAU / 8.0 - PI * 0.5
				var rr := 0.9 if i % 2 == 0 else 0.3
				star.append([cos(a) * rr * 0.8 + 0.12, sin(a) * rr * 0.8 - 0.08])
			ci.draw_colored_polygon(_pts(c, s, star), color)
			ci.draw_circle(c + Vector2(0.12, -0.08) * s, s * 0.2, Color(1, 1, 1, 0.9))
			for i in 3:
				var o := Vector2(-0.55 - i * 0.14, 0.45 + i * 0.16) * s
				ci.draw_line(c + o, c + o + Vector2(-0.28, 0.28) * s, Color(color.r, color.g, color.b, 0.8 - i * 0.2), maxf(1.5, s * 0.1), true)
		"dodge":  # esquiva: dos flechas en arco
			for i in 2:
				var off := Vector2(-0.35 + i * 0.5, 0.0) * s
				ci.draw_polyline(_pts(c + off, s, [[-0.3, -0.6], [0.3, 0.0], [-0.3, 0.6]]), Color(color.r, color.g, color.b, 0.6 + 0.4 * i), maxf(2.5, s * 0.2), true)
		"interact":  # tocar: espiral de jade
			var pts := PackedVector2Array()
			for i in 34:
				var t := float(i) / 33.0
				var a := t * TAU * 1.75 - 0.4
				pts.append(c + Vector2(cos(a), sin(a)) * s * (0.12 + 0.72 * t))
			ci.draw_polyline(pts, color, maxf(2.5, s * 0.17), true)
			ci.draw_circle(c, s * 0.14, Color(1, 1, 1, 0.9))
		"claw":  # garras: tres zarpazos
			for i in 3:
				var x := -0.5 + i * 0.5
				ci.draw_colored_polygon(_pts(c, s, [[x + 0.26, -0.82], [x + 0.4, -0.7], [x - 0.3, 0.86], [x - 0.36, 0.7]]), color)
		"charged":  # zarpazo cargado: huella con destello
			ci.draw_circle(c + Vector2(0, 0.28) * s, s * 0.42, color)
			for p in [[-0.52, -0.2], [-0.2, -0.56], [0.2, -0.56], [0.52, -0.2]]:
				ci.draw_circle(c + Vector2(p[0], p[1]) * s, s * 0.19, color)
			for i in 5:
				var a := -PI * 0.5 + (i - 2) * 0.5
				ci.draw_line(c + Vector2(cos(a), sin(a)) * s * 0.86, c + Vector2(cos(a), sin(a)) * s * 1.08, Color(1, 1, 1, 0.75), maxf(1.5, s * 0.09), true)
		"pounce":  # salto del jaguar: arco con impacto
			var arc := PackedVector2Array()
			for i in 16:
				var t := float(i) / 15.0
				arc.append(c + Vector2(-0.85 + 1.5 * t, 0.5 - sin(t * PI) * 1.25) * s)
			ci.draw_polyline(arc, color, maxf(2.5, s * 0.18), true)
			ci.draw_colored_polygon(_pts(c, s, [[0.9, 0.62], [0.36, 0.42], [0.74, 0.08]]), color)
			for i in 3:
				var x := 0.3 + i * 0.3
				ci.draw_line(c + Vector2(x, 0.86) * s, c + Vector2(x + 0.12 * (i - 1), 0.66) * s, Color(1, 1, 1, 0.7), maxf(1.5, s * 0.09), true)
		"alux":  # alux: sombrero de palma y ojos brillantes
			ci.draw_circle(c + Vector2(0, 0.28) * s, s * 0.52, Color(0.66, 0.44, 0.29))
			ci.draw_colored_polygon(_pts(c, s, [[-0.98, 0.06], [-0.72, 0.18], [-0.58, -0.02]]), Color(0.66, 0.44, 0.29))
			ci.draw_colored_polygon(_pts(c, s, [[0.98, 0.06], [0.72, 0.18], [0.58, -0.02]]), Color(0.66, 0.44, 0.29))
			ci.draw_colored_polygon(_pts(c, s, [[0, -0.95], [0.95, 0.02], [0.5, 0.12], [-0.5, 0.12], [-0.95, 0.02]]), Color(0.85, 0.66, 0.36))
			ci.draw_polyline(_pts(c, s, [[-0.62, -0.06], [0.62, -0.06]]), Color(0.86, 0.25, 0.3), maxf(1.5, s * 0.1), true)
			for x in [-0.2, 0.2]:
				ci.draw_circle(c + Vector2(x, 0.32) * s, s * 0.14, color)
				ci.draw_circle(c + Vector2(x + 0.03, 0.29) * s, s * 0.05, Color.WHITE)
		"balam":  # Balam: cabeza de jaguar
			var fur := Color(0.95, 0.62, 0.2)
			for x in [-1.0, 1.0]:
				ci.draw_colored_polygon(_pts(c, s, [[0.34 * x, -0.5], [0.78 * x, -0.86], [0.8 * x, -0.2]]), fur)
			ci.draw_circle(c + Vector2(0, 0.06) * s, s * 0.7, fur)
			ci.draw_circle(c + Vector2(0, 0.36) * s, s * 0.36, Color(0.99, 0.92, 0.76))
			ci.draw_colored_polygon(_pts(c, s, [[-0.13, 0.2], [0.13, 0.2], [0, 0.36]]), dark)
			for x in [-1.0, 1.0]:
				ci.draw_colored_polygon(_pts(c, s, [[0.14 * x, -0.06], [0.46 * x, -0.2], [0.42 * x, 0.04]]), color)
				ci.draw_circle(c + Vector2(0.52 * x, 0.42) * s, s * 0.05, dark)
			for p in [[-0.3, -0.42], [0.0, -0.5], [0.3, -0.42]]:
				ci.draw_circle(c + Vector2(p[0], p[1]) * s, s * 0.07, dark)
		"fallen":
			ci.draw_line(c + Vector2(-0.5, -0.5) * s, c + Vector2(0.5, 0.5) * s, color, maxf(2.5, s * 0.2), true)
			ci.draw_line(c + Vector2(0.5, -0.5) * s, c + Vector2(-0.5, 0.5) * s, color, maxf(2.5, s * 0.2), true)
		"goal":  # objetivo: glifo de cuatro pétalos
			for i in 4:
				var a := i * PI * 0.5
				ci.draw_circle(c + Vector2(cos(a), sin(a)) * s * 0.48, s * 0.3, color)
			ci.draw_circle(c, s * 0.22, Color.WHITE)
		"alert":  # combate: dos colmillos cruzados
			ci.draw_colored_polygon(_pts(c, s, [[-0.8, -0.8], [-0.5, -0.86], [0.7, 0.6], [0.56, 0.78]]), color)
			ci.draw_colored_polygon(_pts(c, s, [[0.8, -0.8], [0.5, -0.86], [-0.7, 0.6], [-0.56, 0.78]]), color)
		"success":  # sello: sol de ocho rayos
			for i in 8:
				var a := i * TAU / 8.0
				ci.draw_line(c + Vector2(cos(a), sin(a)) * s * 0.55, c + Vector2(cos(a), sin(a)) * s * 0.95, color, maxf(2.0, s * 0.16), true)
			ci.draw_circle(c, s * 0.42, color)
			ci.draw_circle(c, s * 0.2, Color.WHITE)
		"pyramid":
			ci.draw_colored_polygon(_pts(c, s, [[-0.9, 0.7], [-0.9, 0.3], [-0.55, 0.3], [-0.55, -0.1], [-0.22, -0.1], [-0.22, -0.55], [0.22, -0.55], [0.22, -0.1], [0.55, -0.1], [0.55, 0.3], [0.9, 0.3], [0.9, 0.7]]), color)
		"cenote":
			ci.draw_colored_polygon(_pts(c, s, [[0, -0.9], [0.55, 0.1], [0.4, 0.6], [0, 0.8], [-0.4, 0.6], [-0.55, 0.1]]), color)
		"sanctuary":
			ci.draw_colored_polygon(_pts(c, s, [[-0.8, 0.8], [-0.8, -0.3], [0, -0.9], [0.8, -0.3], [0.8, 0.8], [0.35, 0.8], [0.35, 0.05], [-0.35, 0.05], [-0.35, 0.8]]), color)
		"ledge":
			ci.draw_colored_polygon(_pts(c, s, [[-0.5, 0.8], [-0.5, -0.2], [-0.8, -0.2], [0, -0.9], [0.8, -0.2], [0.5, -0.2], [0.5, 0.8]]), color)
		"brazier":
			ci.draw_colored_polygon(_pts(c, s, [[0, -0.9], [0.5, -0.1], [0.3, 0.45], [-0.3, 0.45], [-0.5, -0.1]]), color)
			ci.draw_colored_polygon(_pts(c, s, [[-0.7, 0.5], [0.7, 0.5], [0.4, 0.9], [-0.4, 0.9]]), Color(color.r, color.g, color.b, 0.6))
		_:
			ci.draw_circle(c, s * 0.5, color)
