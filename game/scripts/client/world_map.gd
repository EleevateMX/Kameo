extends Control
## Mapa del viajero (tecla M): Mérida, el Camino a Motul, Motul y —sólo como destinos futuros,
## marcados «próximamente»— Izamal y Valladolid, cada uno en su posición geográfica aproximada.
## Es un esquema, no cartografía: las posiciones salen de las coordenadas de
## docs/mundo/FUENTES_YUCATAN.md (sin cotejar aún con INEGI) y conservan la posición relativa
## real: Motul al este-noreste de Mérida, Izamal al este y Valladolid más al este-sureste.
##
## Todos los iconos son originales y están dibujados por código: no hay escudos oficiales ni
## marcas. Cada lugar tiene el suyo (ICONS); también los puntos del camino, las criaturas y la misión.

const Kit := preload("res://scripts/client/ui/ui_kit.gd")
const Camino := preload("res://scripts/shared/camino_def.gd")
const Wild := preload("res://scripts/shared/wild_def.gd")

## Lugares: latitud, longitud, sobrenombre del juego (docs/OPEN_WORLD.md) y estado.
const PLACES := [
	{"id": "merida", "name": "Mérida", "alias": "la Ciudad Blanca", "lat": 20.968, "lon": -89.622, "open": true, "note": "lugar social"},
	{"id": "motul", "name": "Motul", "alias": "campos de henequén", "lat": 21.095, "lon": -89.283, "open": false, "note": "se llega hasta su entrada"},
	{"id": "izamal", "name": "Izamal", "alias": "la ciudad dorada", "lat": 20.931, "lon": -89.018, "open": false, "note": "próximamente"},
	{"id": "valladolid", "name": "Valladolid", "alias": "la ciudad del cenote", "lat": 20.689, "lon": -88.202, "open": false, "note": "próximamente"},
]
## Caminos: [de, a, abierto]
const ROADS := [["merida", "motul", true], ["merida", "izamal", false], ["izamal", "valladolid", false]]
## Icono de cada punto de descubrimiento del camino (en el orden de camino_def.DISCOVERIES)
const SPOT_ICONS := ["milpa", "cenote", "henequen", "cartel"]
const KX := 0.934                 # un grado de longitud mide a esta latitud 0.934 de uno de latitud

var zone := "merida"
var progress := 0.0               # por dónde va el jugador en el camino (0 = Mérida, 1 = cartel de Motul)
var known: Array = []
var quest := {"st": "none", "n": 0, "need": 3}
var _t := 0.0


func _init() -> void:
	custom_minimum_size = Vector2(860, 500)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func refresh(p_zone: String, p_progress: float, p_known: Array, p_quest: Dictionary) -> void:
	zone = p_zone
	progress = clampf(p_progress, 0.0, 1.0)
	known = p_known
	quest = p_quest
	queue_redraw()


func _process(delta: float) -> void:
	if is_visible_in_tree():
		_t += delta
		queue_redraw()   # el marcador del jugador late


func _place(id: String) -> Dictionary:
	for p in PLACES:
		if p.id == id:
			return p
	return {}


## Dónde cae un lugar dentro del recuadro del mapa.
func _xy(p: Dictionary, area: Rect2) -> Vector2:
	var lon0 := -89.78
	var lon1 := -88.05
	var lat0 := 21.42
	var lat1 := 20.55
	var sx := area.size.x / ((lon1 - lon0) * KX)
	var sy := area.size.y / (lat0 - lat1)
	var s := minf(sx, sy)
	var ox := area.position.x + (area.size.x - (lon1 - lon0) * KX * s) * 0.5
	var oy := area.position.y + (area.size.y - (lat0 - lat1) * s) * 0.5
	return Vector2(ox + (float(p.lon) - lon0) * KX * s, oy + (lat0 - float(p.lat)) * s)


func _text(at: Vector2, text: String, size: int, color: Color, font: Font = null, align := HORIZONTAL_ALIGNMENT_LEFT, width := -1.0) -> void:
	var f := font if font != null else Kit.body_font()
	var pos := at
	if align == HORIZONTAL_ALIGNMENT_CENTER and width < 0.0:
		pos.x -= f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x * 0.5
	draw_string_outline(f, pos, text, align, width, size, 4, Color(0, 0, 0, 0.55))
	draw_string(f, pos, text, align, width, size, color)


func _draw() -> void:
	var rect := Rect2(Vector2.ZERO, size)
	Kit.draw_plaque(self, rect, Kit.GOLD, 18.0)
	_text(Vector2(size.x * 0.5, 44), "EL MAYAB DE LOS ALUXES", 24, Kit.GOLD, Kit.title_font(), HORIZONTAL_ALIGNMENT_CENTER)
	_text(Vector2(size.x * 0.5, 66), "Mapa del viajero  ·  esquema, no cartografía: las posiciones son aproximadas", 12, Color(1, 1, 1, 0.6), null, HORIZONTAL_ALIGNMENT_CENTER)
	var area := Rect2(34, 84, size.x - 68, size.y - 84 - 150)
	# Fondo del mapa: tierra, con el Golfo sugerido al norte
	draw_style_box(Kit.flat(Color(0.09, 0.16, 0.13), 12.0, 1, Color(Kit.GOLD.r, Kit.GOLD.g, Kit.GOLD.b, 0.3)), area)
	var coast := PackedVector2Array()
	for k in 25:
		var t := float(k) / 24.0
		coast.append(Vector2(area.position.x + 6.0 + (area.size.x - 12.0) * t, area.position.y + 22.0 + sin(t * 5.2 + 0.6) * 5.0 - t * 9.0))
	var sea := coast.duplicate()
	sea.append(Vector2(area.end.x - 6.0, area.position.y + 5.0))
	sea.append(Vector2(area.position.x + 6.0, area.position.y + 5.0))
	draw_colored_polygon(sea, Color(0.08, 0.3, 0.38, 0.75))
	draw_polyline(coast, Color(0.3, 0.75, 0.82, 0.8), 2.0, true)
	_text(Vector2(area.end.x - 150, area.position.y + 18), "Golfo de México", 11, Color(0.6, 0.9, 0.95, 0.75))
	# rosa de los vientos mínima
	var rose := Vector2(area.end.x - 34, area.end.y - 40)
	draw_line(rose + Vector2(0, 16), rose + Vector2(0, -16), Color(1, 1, 1, 0.5), 1.5, true)
	draw_line(rose + Vector2(-12, 0), rose + Vector2(12, 0), Color(1, 1, 1, 0.3), 1.5, true)
	draw_colored_polygon(PackedVector2Array([rose + Vector2(0, -22), rose + Vector2(5, -12), rose + Vector2(-5, -12)]), Kit.GOLD)
	_text(rose + Vector2(0, -26), "N", 12, Kit.GOLD, Kit.bold_font(), HORIZONTAL_ALIGNMENT_CENTER)
	# Caminos
	for r in ROADS:
		var a := _xy(_place(r[0]), area)
		var b := _xy(_place(r[1]), area)
		if bool(r[2]):
			draw_line(a, b, Color(0, 0, 0, 0.5), 9.0, true)
			draw_line(a, b, Color(0.87, 0.84, 0.74), 5.0, true)
		else:
			var n := int(a.distance_to(b) / 12.0)
			for k in n:
				if k % 2 == 0:
					draw_line(a.lerp(b, float(k) / float(n)), a.lerp(b, float(k + 1) / float(n)), Color(0.87, 0.84, 0.74, 0.32), 3.0, true)
	# El Camino a Motul: sus lugares por descubrir, repartidos según por dónde caen en el camino
	var m := _xy(_place("merida"), area)
	var mo := _xy(_place("motul"), area)
	var len := Camino.road_length()
	var side := (mo - m).orthogonal().normalized()
	for i in Camino.DISCOVERIES.size():
		var d: Dictionary = Camino.DISCOVERIES[i]
		var along := clampf(_along(d.at) / len, 0.06, 0.94)
		if i == Camino.DISCOVERIES.size() - 1:
			along = 0.9
		var found := known.has(str(d.id))
		var p := m.lerp(mo, along) + side * (-17.0 if i % 2 == 0 else 17.0)
		draw_line(m.lerp(mo, along), p, Color(1, 1, 1, 0.25), 1.0, true)
		Kit.draw_medallion(self, p, 11.0, Color(0.3, 0.9, 1.0) if found else Color(1, 1, 1, 0.3))
		if found:
			_icon(SPOT_ICONS[i], p, 6.5, Color(0.75, 0.97, 1.0))
		else:
			_text(p + Vector2(0, 5), "?", 13, Color(1, 1, 1, 0.5), Kit.bold_font(), HORIZONTAL_ALIGNMENT_CENTER)
	var below := side if side.y > 0.0 else -side
	_text(m.lerp(mo, 0.5) + below * 36.0 + Vector2(0, 8), "Camino a Motul", 12, Color(0.95, 0.92, 0.8), Kit.bold_font(), HORIZONTAL_ALIGNMENT_CENTER)
	# Lugares
	for p in PLACES:
		var at := _xy(p, area)
		var here: bool = str(p.id) == "merida" and zone == "merida"
		var ring: Color = Kit.GOLD if bool(p.open) else (Color(0.95, 0.92, 0.8) if p.id == "motul" else Color(1, 1, 1, 0.35))
		Kit.draw_medallion(self, at, 25.0, ring, 1.0 if here else 0.0)
		_icon(str(p.id), at, 15.0, Color.WHITE if (bool(p.open) or p.id == "motul") else Color(1, 1, 1, 0.5))
		# Mérida lleva el rótulo debajo; los demás, encima (por debajo pasan los caminos)
		var soon := str(p.note) == "próximamente"
		var ty := at.y + 44.0
		if str(p.id) != "merida":
			ty = at.y - (66.0 if soon else 48.0)
		_text(Vector2(at.x, ty), str(p.name).to_upper(), 15, Color.WHITE if bool(p.open) or p.id == "motul" else Color(1, 1, 1, 0.6), Kit.bold_font(), HORIZONTAL_ALIGNMENT_CENTER)
		_text(Vector2(at.x, ty + 15.0), str(p.alias), 11, Color(1, 1, 1, 0.62), null, HORIZONTAL_ALIGNMENT_CENTER)
		if soon:
			var w := 96.0
			draw_style_box(Kit.flat(Color(0.05, 0.1, 0.095, 0.9), 8.0, 1, Color(Kit.AMBER.r, Kit.AMBER.g, Kit.AMBER.b, 0.7)), Rect2(at.x - w * 0.5, ty + 21.0, w, 18.0))
			_text(Vector2(at.x, ty + 34.0), "PRÓXIMAMENTE", 10, Kit.AMBER, Kit.bold_font(), HORIZONTAL_ALIGNMENT_CENTER)
	# Dónde está el jugador
	var me := m if zone == "merida" else m.lerp(mo, 0.04 + 0.9 * progress)
	var pulse := 0.5 + 0.5 * sin(_t * 4.0)
	draw_circle(me, 9.0 + 5.0 * pulse, Color(Kit.JADE.r, Kit.JADE.g, Kit.JADE.b, 0.25 * (1.0 - pulse) + 0.1))
	draw_circle(me, 6.0, Kit.INK)
	draw_circle(me, 4.5, Kit.JADE)
	_text(me + (Vector2(10, 18) if zone != "merida" else Vector2(0, -36)), "TÚ", 12, Kit.JADE, Kit.bold_font(), HORIZONTAL_ALIGNMENT_CENTER)
	_legend(Rect2(34, size.y - 142, size.x - 68, 104))
	_text(Vector2(size.x * 0.5, size.y - 18), "M o Esc cierra el mapa", 12, Color(1, 1, 1, 0.55), null, HORIZONTAL_ALIGNMENT_CENTER)


## A qué distancia de Mérida, siguiendo el camino, cae un punto de la zona.
func _along(at: Vector2) -> float:
	var best := 0.0
	var best_d := INF
	var len := Camino.road_length()
	var d := 0.0
	while d <= len:
		var gap := (Camino.road_at(d)[0] as Vector2).distance_to(at)
		if gap < best_d:
			best_d = gap
			best = d
		d += 2.0
	return best


func _legend(area: Rect2) -> void:
	var col := area.size.x / 3.0
	var x := area.position.x
	var y := area.position.y + 12.0
	# Camino: descubrimientos
	_text(Vector2(x, y), "LUGARES DEL CAMINO  ·  %d de %d" % [_found_count(), Camino.DISCOVERIES.size()], 11, Kit.JADE, Kit.bold_font())
	for i in Camino.DISCOVERIES.size():
		var d: Dictionary = Camino.DISCOVERIES[i]
		var found := known.has(str(d.id))
		var p := Vector2(x + 9.0, y + 19.0 + 19.0 * float(i))
		_icon(SPOT_ICONS[i], p, 6.5, Color(0.75, 0.97, 1.0) if found else Color(1, 1, 1, 0.35))
		_text(p + Vector2(15, 4), str(d.name) if found else "Sin descubrir", 12, Color.WHITE if found else Color(1, 1, 1, 0.45))
	# Criaturas
	x += col
	_text(Vector2(x, y), "CRIATURAS DEL MONTE", 11, Kit.JADE, Kit.bold_font())
	var row := 0
	for kind in ["zarza", "henequen"]:
		var p := Vector2(x + 9.0, y + 21.0 + 22.0 * float(row))
		_icon("c_" + kind, p, 8.0, Color(1.0, 0.75, 0.85))
		_text(p + Vector2(16, 4), str(Wild.CREATURES[kind].name), 12, Color.WHITE)
		row += 1
	var sp := Vector2(x + 9.0, y + 21.0 + 22.0 * float(row))
	_icon("seguro", sp, 7.5, Kit.JADE)
	_text(sp + Vector2(16, 4), "Mojonera de jade: zona segura", 12, Color(1, 1, 1, 0.8))
	# Misión
	x += col
	_text(Vector2(x, y), "MISIÓN", 11, Kit.JADE, Kit.bold_font())
	var mdef: Dictionary = Wild.MISSIONS[Wild.MISSION]
	var st := str(quest.get("st", "none"))
	_icon("mision", Vector2(x + 9.0, y + 21.0), 8.0, Kit.GOLD if st != "none" else Color(1, 1, 1, 0.5))
	_text(Vector2(x + 25.0, y + 25.0), str(mdef.name), 12, Color.WHITE, Kit.bold_font())
	var lines := ["Habla con %s," % str(mdef.giver), "a la salida de Mérida"]
	if st == "active":
		lines = ["Purificadas: %d de %d" % [int(quest.get("n", 0)), int(quest.get("need", 3))], "Después, al cartel de Motul"]
	elif st == "done":
		lines = ["Cumplida", ""]
	for i in 2:
		_text(Vector2(x + 25.0, y + 43.0 + 16.0 * float(i)), lines[i], 11, Kit.GOLD if st == "done" else Color(1, 1, 1, 0.7))


func _found_count() -> int:
	var n := 0
	for d in Camino.DISCOVERIES:
		if known.has(str(d.id)):
			n += 1
	return n


func _pts(c: Vector2, s: float, raw: Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p in raw:
		out.append(c + Vector2(p[0], p[1]) * s)
	return out


## Iconos originales, dibujados en un cuadro de lado 2·s centrado en c.
func _icon(icon: String, c: Vector2, s: float, color: Color) -> void:
	var w := maxf(1.5, s * 0.16)
	match icon:
		"merida":  # la Ciudad Blanca: un arco blanco con su remate y el gran árbol asomando
			draw_circle(c + Vector2(0, -0.5) * s, s * 0.42, Color(0.3, 0.62, 0.36, color.a))
			draw_colored_polygon(_pts(c, s, [[-0.85, 0.8], [-0.85, -0.1], [0.85, -0.1], [0.85, 0.8], [0.45, 0.8], [0.45, 0.25], [-0.45, 0.25], [-0.45, 0.8]]), color)
			draw_arc(c + Vector2(0, 0.25) * s, s * 0.45, PI, TAU, 12, color, w * 1.6, true)
			draw_line(c + Vector2(-0.95, -0.14) * s, c + Vector2(0.95, -0.14) * s, Color(0.95, 0.7, 0.3, color.a), w * 1.3, true)
		"motul", "henequen":  # una mata de henequén: pencas en abanico
			var green := Color(0.5, 0.8, 0.68, color.a) if icon == "motul" else color
			for k in 7:
				var a := -PI * 0.5 + (float(k) - 3.0) * 0.36
				var tip := c + Vector2(cos(a), sin(a)) * s * (0.95 if k % 2 == 0 else 0.78) + Vector2(0, 0.55) * s
				var base := c + Vector2(0, 0.6) * s
				var nrm := Vector2(-sin(a), cos(a)) * s * 0.13
				draw_colored_polygon(PackedVector2Array([base - nrm, tip, base + nrm]), green)
			draw_circle(c + Vector2(0, 0.6) * s, s * 0.2, green.darkened(0.3))
		"izamal":  # la ciudad dorada: tres arcos amarillos sobre un cerro
			var gold := Color(1.0, 0.8, 0.3, color.a)
			draw_colored_polygon(_pts(c, s, [[-1.0, 0.85], [-0.55, 0.45], [0.55, 0.45], [1.0, 0.85]]), Color(0.45, 0.6, 0.36, color.a))
			draw_rect(Rect2(c + Vector2(-0.8, -0.35) * s, Vector2(1.6, 0.8) * s), gold)
			for k in 3:
				var ac := c + Vector2(-0.5 + 0.5 * float(k), 0.45) * s
				draw_circle(ac + Vector2(0, -0.3) * s, s * 0.17, Kit.INK)
				draw_rect(Rect2(ac + Vector2(-0.17, -0.3) * s, Vector2(0.34, 0.3) * s), Kit.INK)
			draw_line(c + Vector2(-0.9, -0.4) * s, c + Vector2(0.9, -0.4) * s, gold.lightened(0.3), w, true)
		"valladolid", "cenote":  # la ciudad del cenote: un ojo de agua con su escalinata
			var water := Color(0.3, 0.85, 0.95, color.a)
			draw_circle(c, s * 0.82, water.darkened(0.45))
			draw_circle(c + Vector2(0, 0.08) * s, s * 0.56, water)
			draw_arc(c, s * 0.82, 0.0, TAU, 20, color, w, true)
			if icon == "valladolid":
				for k in 3:
					draw_line(c + Vector2(-0.75 + 0.14 * float(k), -0.5 + 0.2 * float(k)) * s, c + Vector2(-0.3 + 0.14 * float(k), -0.5 + 0.2 * float(k)) * s, Color.WHITE, w, true)
			else:
				draw_arc(c + Vector2(0, 0.08) * s, s * 0.3, 0.3, 2.4, 8, Color(1, 1, 1, 0.8), w * 0.7, true)
		"milpa":  # una caña de maíz con su mazorca
			draw_line(c + Vector2(0, 0.9) * s, c + Vector2(0, -0.9) * s, color, w, true)
			draw_colored_polygon(_pts(c, s, [[0.0, 0.3], [0.75, -0.25], [0.2, 0.05]]), color)
			draw_colored_polygon(_pts(c, s, [[0.0, 0.0], [-0.75, -0.55], [-0.2, -0.25]]), color)
			draw_circle(c + Vector2(0.28, -0.5) * s, s * 0.22, Color(1.0, 0.82, 0.3, color.a))
		"cartel":  # un cartel entre dos postes
			draw_line(c + Vector2(-0.7, 0.9) * s, c + Vector2(-0.7, -0.7) * s, color, w, true)
			draw_line(c + Vector2(0.7, 0.9) * s, c + Vector2(0.7, -0.7) * s, color, w, true)
			draw_rect(Rect2(c + Vector2(-0.9, -0.6) * s, Vector2(1.8, 0.75) * s), color)
		"c_zarza":  # zarza errante: una maraña redonda con espinas y una brasa
			draw_arc(c, s * 0.6, 0.0, TAU, 14, color, w, true)
			for k in 8:
				var a := TAU * float(k) / 8.0 + 0.3
				draw_line(c + Vector2(cos(a), sin(a)) * s * 0.55, c + Vector2(cos(a), sin(a)) * s, color, w * 0.8, true)
			draw_circle(c, s * 0.24, Kit.MAGENTA)
		"c_henequen":  # henequén bravo: la mata con dos ojos
			_icon("henequen", c + Vector2(0, -0.1) * s, s, color)
			draw_circle(c + Vector2(-0.2, 0.45) * s, s * 0.11, Kit.AMBER)
			draw_circle(c + Vector2(0.2, 0.45) * s, s * 0.11, Kit.AMBER)
		"seguro":  # mojonera de jade
			draw_colored_polygon(_pts(c, s, [[-0.45, 0.9], [-0.32, -0.5], [0.32, -0.5], [0.45, 0.9]]), Color(0.7, 0.7, 0.66, color.a))
			draw_circle(c + Vector2(0, -0.72) * s, s * 0.26, color)
			draw_line(c + Vector2(-0.38, 0.1) * s, c + Vector2(0.38, 0.1) * s, color, w, true)
		"mision":  # un rollo de soga con su recado
			draw_arc(c, s * 0.75, 0.0, TAU, 16, color, w * 1.4, true)
			draw_arc(c, s * 0.4, 0.0, TAU, 12, color, w * 1.2, true)
			draw_line(c + Vector2(0.5, 0.55) * s, c + Vector2(1.0, 0.95) * s, color, w * 1.2, true)
