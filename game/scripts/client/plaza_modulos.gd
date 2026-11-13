extends RefCounted
## Vocabulario modular de la arquitectura de la plaza de Mérida: unas pocas piezas a la misma
## escala (paño de muro, zócalo, cornisa, pretil con remates, columna, arco, puerta, ventana con
## reja, balcón, farol de pared, toldo, tejado, torre) y los edificios que se componen con ellas
## (casona, portales, templo). Es una interpretación fantástica: no copia ningún edificio real.
##
## Cada fachada tiene su marco `f` (Transform3D): x a lo largo de la fachada, y hacia arriba y z
## hacia la plaza (z = 0 es el paño del muro). Las piezas se piden en ese marco y van a los lotes
## del constructor (plaza_builder.gd), así que no añaden llamadas de dibujo:
##   «obra»    volúmenes y vanos que deben verse desde toda la plaza y arrojar sombra
##   «suelo»   lo mismo, para lo que no arroja sombra sobre la plaza (lo del norte y el este)
##   «det»     lo fino (rejas, marcos, barandales, remates): por cuadrantes, de lejos se oculta
##   «brillo»  lo encendido · «luz» la luz pintada sobre muros y suelo
##
## Medidas (m) comunes a todos los edificios, para que casen entre sí:
const BAY := 3.0          # vano; los arcos de los soportales miden dos
const FLOOR_0 := 4.4      # alto de la planta baja
const FLOOR_1 := 3.6      # alto de la planta alta
const DOOR_W := 1.5
const DOOR_H := 2.9
const WIN_W := 1.15
const WIN_H := 1.9
const SILL := 1.05        # alto del alféizar de las ventanas de planta baja

const WHITE := Color(0.9, 0.87, 0.8)          # cal
const WHITE_SHADE := Color(0.66, 0.62, 0.62)
const STONE := Color(0.8, 0.74, 0.6)          # piedra caliza
const STONE_SHADE := Color(0.52, 0.47, 0.42)
const TERRACOTTA := Color(0.72, 0.36, 0.24)
const AZOTEA := Color(0.6, 0.52, 0.47)
const WOOD := Color(0.44, 0.28, 0.17)
const WOOD_DARK := Color(0.26, 0.17, 0.12)
const IRON := Color(0.1, 0.11, 0.13)
const GLASS := Color(0.12, 0.16, 0.25)        # ventana apagada
const LIT := Color(1.0, 0.76, 0.42)           # ventana encendida
const WARM := Color(1.0, 0.78, 0.42)
const JADE := Color(0.18, 0.95, 0.72)
const GOLD := Color(1.0, 0.8, 0.35)
const NONE := Color(0, 0, 0, 0)

var b                      # plaza_builder.gd: lotes y formas básicas
var _n := 0                # reparte, siempre igual, qué ventanas están encendidas


func _init(builder) -> void:
	b = builder


static func frame(origin: Vector3, yaw: float) -> Transform3D:
	return Transform3D(Basis(Vector3.UP, yaw), origin)


# ───────────────────────── Formas en el marco de la fachada ─────────────────────────

func _lot(f: Transform3D, lot: String, at: Vector3) -> String:
	return b._det(f * at) if lot == "det" else lot


func box(f: Transform3D, lot: String, size: Vector3, color: Color, at: Vector3, bottom := NONE) -> void:
	b._emit(_lot(f, lot, at), "box", f.basis, size, f * at, color, bottom)


func cyl(f: Transform3D, lot: String, radius: float, height: float, color: Color, at: Vector3, sides := 8, top := -1.0, bottom := NONE, tilt := Basis.IDENTITY) -> void:
	b._cyl(_lot(f, lot, at), radius, height, color, f * at, sides, top, bottom, f.basis * tilt)


func gem(f: Transform3D, lot: String, size: Vector3, color: Color, at: Vector3, bottom := NONE) -> void:
	b._emit(_lot(f, lot, at), "oct", f.basis, size, f * at, color, bottom)


func quad(f: Transform3D, lot: String, p0: Vector3, p1: Vector3, p2: Vector3, p3: Vector3, color: Color, low := NONE, both := false) -> void:
	b._quad(_lot(f, lot, p0), f * p0, f * p1, f * p2, f * p3, color, low, both)


## Rectángulo pegado a la fachada (mira hacia la plaza), a `z` del paño.
func panel(f: Transform3D, lot: String, x0: float, x1: float, y0: float, y1: float, z: float, color: Color, low := NONE) -> void:
	quad(f, lot, Vector3(x0, y1, z), Vector3(x1, y1, z), Vector3(x1, y0, z), Vector3(x0, y0, z), color, low)


## Disco o sector pegado a la fachada (ángulos desde el eje x, hacia arriba).
func disc(f: Transform3D, lot: String, at: Vector3, radius: float, color: Color, edge: Color, sides := 10, a0 := 0.0, a1 := TAU) -> void:
	b._disc(_lot(f, lot, at), f * at, f.basis.x, f.basis.y, radius, color, edge, sides, a0, a1)


## Resplandor pintado en el muro (se suma: no es una luz de verdad).
func wash(f: Transform3D, x: float, y: float, radius: float, color: Color, strength := 0.3, z := 0.06) -> void:
	disc(f, "luz", Vector3(x, y, z), radius, Color(color.r * strength, color.g * strength, color.b * strength), Color(0, 0, 0), 10)


# ───────────────────────── Piezas ─────────────────────────

## Paño de muro: de x0 a x1 y de y0 a y1, con `depth` de fondo hacia dentro.
func wall(f: Transform3D, x0: float, x1: float, y0: float, y1: float, depth: float, color: Color, lot := "obra", shade := 0.2) -> void:
	box(f, lot, Vector3(x1 - x0, y1 - y0, depth), color, Vector3((x0 + x1) * 0.5, (y0 + y1) * 0.5, -depth * 0.5), color.darkened(shade))


## Zócalo: la franja pintada al pie del muro.
func plinth(f: Transform3D, x0: float, x1: float, color: Color, h := 0.85, lot := "obra") -> void:
	box(f, lot, Vector3(x1 - x0, h, 0.14), color, Vector3((x0 + x1) * 0.5, h * 0.5, 0.04), color.darkened(0.32))


## Cornisa: moldura corrida que vuela sobre el paño.
func cornice(f: Transform3D, x0: float, x1: float, y: float, color := WHITE, h := 0.28, out := 0.3, lot := "obra") -> void:
	var mid := (x0 + x1) * 0.5
	box(f, lot, Vector3(x1 - x0, h, out + 0.1), color, Vector3(mid, y + h * 0.5, out * 0.5 - 0.05), color.darkened(0.2))
	box(f, "det", Vector3(x1 - x0, h * 0.5, out * 0.5 + 0.06), color.darkened(0.14), Vector3(mid, y - h * 0.25, out * 0.25 - 0.03))


## Pretil de azotea con sus remates. kind: 0 liso · 1 pináculos · 2 almenas escalonadas ·
## 3 balaustrada con macetones.
func parapet(f: Transform3D, x0: float, x1: float, y: float, kind := 1, color := WHITE, step := BAY, lot := "obra") -> void:
	var w := x1 - x0
	var mid := (x0 + x1) * 0.5
	var shade := color.darkened(0.22)
	if kind == 3:
		box(f, lot, Vector3(w, 0.13, 0.32), color, Vector3(mid, y + 0.76, 0.0))
		box(f, lot, Vector3(w, 0.16, 0.36), color, Vector3(mid, y + 0.08, 0.0), shade)
		var bars := maxi(2, roundi(w / 0.55))
		for k in bars:
			var bx := x0 + (float(k) + 0.5) * w / float(bars)
			panel(f, "det", bx - 0.09, bx + 0.09, y + 0.16, y + 0.7, 0.1, color, shade)
	else:
		box(f, lot, Vector3(w, 0.66, 0.32), color, Vector3(mid, y + 0.33, 0.0), shade)
	if kind == 0:
		return
	var n := maxi(1, roundi(w / step))
	for k in n:
		var x := x0 + (float(k) + 0.5) * w / float(n)
		match kind:
			1:
				box(f, "det", Vector3(0.4, 0.5, 0.4), color, Vector3(x, y + 0.85, 0.0), shade)
				gem(f, "det", Vector3(0.36, 0.56, 0.36), color, Vector3(x, y + 1.36, 0.0), shade)
			2:
				box(f, "det", Vector3(1.1, 0.36, 0.32), color, Vector3(x, y + 0.84, 0.0), shade)
				box(f, "det", Vector3(0.5, 0.34, 0.32), color, Vector3(x, y + 1.19, 0.0))
			_:
				box(f, "det", Vector3(0.42, 0.95, 0.42), color, Vector3(x - w / float(n) * 0.5, y + 0.47, 0.0), shade)
				cyl(f, "det", 0.2, 0.34, TERRACOTTA, Vector3(x - w / float(n) * 0.5, y + 0.95, 0.0), 6, 0.3)
				gem(f, "det", Vector3(0.62, 0.6, 0.62), Color(0.3, 0.52, 0.26), Vector3(x - w / float(n) * 0.5, y + 1.5, 0.0), Color(0.14, 0.3, 0.16))


## Columna de soportal: basa, fuste con algo de éntasis y capitel.
func column(f: Transform3D, x: float, z: float, h: float, color := WHITE, r := 0.42, lot := "obra") -> void:
	box(f, lot, Vector3(r * 2.5, 0.3, r * 2.5), color.darkened(0.16), Vector3(x, 0.15, z))
	cyl(f, lot, r, h - 0.5, color, Vector3(x, 0.3, z), 8, r * 0.84, color.darkened(0.26))
	box(f, lot, Vector3(r * 2.4, 0.22, r * 2.4), color, Vector3(x, h - 0.09, z))


## Puerta, con sus jambas, su dintel y su escalón. kind: 0 de casa (dos hojas con tableros) ·
## 1 con medio punto de abanico · 2 zaguán (portón con clavos) · 3 de tienda (abierta: se ve el
## interior encendido).
func door(f: Transform3D, x: float, color: Color, kind := 0, lit := false, trim := WHITE) -> void:
	var w: float = [DOOR_W, DOOR_W, 2.5, 2.3][kind]
	var h: float = [DOOR_H, 2.65, 3.5, 2.85][kind]
	var shade := trim.darkened(0.22)
	for s: float in [-1.0, 1.0]:
		box(f, "det", Vector3(0.24, h + 0.06, 0.18), trim, Vector3(x + s * (w * 0.5 + 0.12), (h + 0.06) * 0.5, 0.07), shade)
	box(f, "det", Vector3(w + 0.5, 0.14, 0.42), STONE_SHADE, Vector3(x, 0.07, 0.2))
	if kind == 1:
		# medio punto con abanico de hierro; la arquivolta es un sector de disco
		disc(f, "det", Vector3(x, h, 0.1), w * 0.5 + 0.26, trim, shade, 8, 0.0, PI)
		disc(f, "brillo" if lit else "obra", Vector3(x, h, 0.12), w * 0.5, LIT if lit else GLASS, LIT.darkened(0.3) if lit else GLASS.darkened(0.3), 8, 0.0, PI)
		for k in 5:
			var a := PI * float(k + 1) / 6.0
			quad(f, "det", Vector3(x + cos(a + 0.04) * w * 0.5, h + sin(a + 0.04) * w * 0.5, 0.14), Vector3(x + cos(a - 0.04) * w * 0.5, h + sin(a - 0.04) * w * 0.5, 0.14),
				Vector3(x, h, 0.14), Vector3(x, h + 0.04, 0.14), IRON, NONE, true)
	else:
		box(f, "det", Vector3(w + 0.8, 0.28, 0.24), trim, Vector3(x, h + 0.2, 0.09), shade)
	if kind == 3:
		panel(f, "brillo", x - w * 0.5, x + w * 0.5, 0.14, h, 0.03, LIT, Color(0.75, 0.42, 0.2))
		# lo que se adivina dentro: estantes a contraluz
		for k in 3:
			panel(f, "det", x - w * 0.5 + 0.12, x + w * 0.5 - 0.12, 0.85 + 0.62 * float(k), 0.93 + 0.62 * float(k), 0.05, WOOD_DARK)
		wash(f, x, h * 0.6, 2.6, WARM, 0.22)
		b._pool(f * Vector3(x, 0.0, 1.5), 2.8, WARM, 0.3)
		return
	box(f, "obra", Vector3(w, h, 0.1), color, Vector3(x, h * 0.5, 0.03), color.darkened(0.45))
	panel(f, "det", x - 0.025, x + 0.025, 0.12, h - 0.04, 0.085, color.darkened(0.6))
	for s: float in [-1.0, 1.0]:
		var cx := x + s * w * 0.25
		if kind == 2:
			# clavos del portón
			for k in 3:
				gem(f, "det", Vector3(0.12, 0.12, 0.08), IRON.lightened(0.25), Vector3(cx, 0.7 + 0.95 * float(k), 0.09))
		else:
			panel(f, "det", cx - w * 0.16, cx + w * 0.16, h * 0.5, h - 0.28, 0.085, color.lightened(0.12), color.darkened(0.1))
			panel(f, "det", cx - w * 0.16, cx + w * 0.16, 0.3, h * 0.5 - 0.16, 0.085, color.lightened(0.08), color.darkened(0.15))


## Ventana con marco. kind: 0 de planta baja, con reja de cajón · 1 puerta-ventana de balcón ·
## 2 pequeña, de torre o de entresuelo. `lit`: encendida. `shutters`: color de las contraventanas.
func window(f: Transform3D, x: float, y: float, lit: bool, kind := 0, trim := WHITE, shutters := NONE) -> void:
	var w: float = [WIN_W, 1.2, 0.8][kind]
	var h: float = [WIN_H, 2.45, 1.0][kind]
	var y1 := y + h
	var shade := trim.darkened(0.22)
	if lit:
		panel(f, "brillo", x - w * 0.5, x + w * 0.5, y, y1, 0.035, LIT, Color(0.85, 0.5, 0.24))
		panel(f, "det", x - 0.03, x + 0.03, y, y1, 0.05, WOOD_DARK)
		panel(f, "det", x - w * 0.5, x + w * 0.5, y + h * 0.62 - 0.03, y + h * 0.62 + 0.03, 0.05, WOOD_DARK)
	else:
		panel(f, "obra", x - w * 0.5, x + w * 0.5, y, y1, 0.035, GLASS.lightened(0.1), GLASS.darkened(0.25))
	box(f, "det", Vector3(w + 0.46, 0.2, 0.2), trim, Vector3(x, y1 + 0.13, 0.08), shade)
	if kind != 1:
		box(f, "det", Vector3(w + 0.36, 0.13, 0.34), trim, Vector3(x, y - 0.065, 0.15), shade)
	if kind == 0:
		var zr := 0.3
		for k in 5:
			var bx := x - w * 0.5 + w * float(k) / 4.0
			panel(f, "det", bx - 0.028, bx + 0.028, y, y1, zr, IRON)
		box(f, "det", Vector3(w + 0.1, 0.06, zr), IRON, Vector3(x, y1 - 0.16, zr * 0.5))
		box(f, "det", Vector3(w + 0.1, 0.06, zr), IRON, Vector3(x, y + 0.16, zr * 0.5))
	if shutters.a > 0.0:
		for s: float in [-1.0, 1.0]:
			box(f, "det", Vector3(0.46, h, 0.07), shutters, Vector3(x + s * (w * 0.5 + 0.25), y + h * 0.5, 0.045), shutters.darkened(0.3))
	if lit and kind == 0:
		b._pool(f * Vector3(x, 0.0, 1.1), 2.0, WARM, 0.14)


## Balcón: losa volada sobre ménsula, barandal de hierro y su puerta-ventana.
func balcony(f: Transform3D, x: float, y: float, lit: bool, trim := WHITE, w := 2.1) -> void:
	window(f, x, y + 0.08, lit, 1, trim)
	box(f, "obra", Vector3(w, 0.14, 0.78), trim, Vector3(x, y, 0.37), trim.darkened(0.2))
	box(f, "det", Vector3(w - 0.5, 0.22, 0.34), trim.darkened(0.2), Vector3(x, y - 0.18, 0.2))
	var z := 0.72
	box(f, "det", Vector3(w, 0.05, 0.05), IRON, Vector3(x, y + 0.98, z))
	for k in 9:
		var bx := x - w * 0.5 + 0.04 + (w - 0.08) * float(k) / 8.0
		panel(f, "det", bx - 0.022, bx + 0.022, y + 0.07, y + 0.98, z, IRON)
	for s: float in [-1.0, 1.0]:
		box(f, "det", Vector3(0.05, 0.05, z), IRON, Vector3(x + s * (w * 0.5 - 0.025), y + 0.98, z * 0.5))
		quad(f, "det", Vector3(x + s * (w * 0.5 - 0.02), y + 0.98, 0.02), Vector3(x + s * (w * 0.5 - 0.02), y + 0.98, z), Vector3(x + s * (w * 0.5 - 0.02), y + 0.5, z),
			Vector3(x + s * (w * 0.5 - 0.02), y + 0.5, 0.02), IRON, NONE, true)


## Farol de pared: brazo de hierro, luz y su resplandor pintado en el muro y en el suelo.
func lantern(f: Transform3D, x: float, y: float, color := WARM, strength := 1.0) -> void:
	box(f, "det", Vector3(0.05, 0.05, 0.44), IRON, Vector3(x, y + 0.36, 0.22))
	cyl(f, "det", 0.17, 0.1, IRON, Vector3(x, y + 0.2, 0.42), 4, 0.03)
	gem(f, "brillo", Vector3(0.24, 0.38, 0.24), color, Vector3(x, y, 0.42))
	wash(f, x, y, 1.8, color, 0.3 * strength)
	b._pool(f * Vector3(x, 0.0, 1.2), 2.6, color, 0.2 * strength)


## Toldo de rayas: nace en el muro a la altura `y` y cae `drop` al salir `out`.
func awning(f: Transform3D, x: float, y: float, w: float, out: float, colors: Array, drop := 0.7, z0 := 0.06, lot := "det") -> void:
	var n := maxi(2, roundi(w / 0.55))
	for k in n:
		var xa := x - w * 0.5 + w * float(k) / float(n)
		var xb := xa + w / float(n)
		var c: Color = colors[k % colors.size()]
		quad(f, lot, Vector3(xa, y, z0), Vector3(xb, y, z0), Vector3(xb, y - drop, z0 + out), Vector3(xa, y - drop, z0 + out), c, c.darkened(0.22), true)
		quad(f, "det", Vector3(xa, y - drop, z0 + out), Vector3(xb, y - drop, z0 + out), Vector3(xb, y - drop - 0.24, z0 + out), Vector3(xa, y - drop - 0.24, z0 + out),
			c.darkened(0.08), c.darkened(0.3), true)


## Tablero de rótulo (el texto es una etiqueta aparte: ver plaza_builder._labels).
func signboard(f: Transform3D, x: float, y: float, w: float, color := WOOD_DARK, z := 0.1) -> void:
	box(f, "det", Vector3(w, 0.62, 0.1), color, Vector3(x, y, z))
	panel(f, "det", x - w * 0.5 + 0.06, x + w * 0.5 - 0.06, y - 0.25, y + 0.25, z + 0.06, Color(0.86, 0.78, 0.6), Color(0.72, 0.62, 0.46))


## Tejado de teja a un agua hacia la plaza, sobre un cuerpo de x0 a x1 que acaba en `y`.
func tiled_roof(f: Transform3D, x0: float, x1: float, y: float, depth := 3.6, rise := 1.5, lot := "obra") -> void:
	var a := Vector3(x0 - 0.25, y + rise, -depth)
	var bb := Vector3(x1 + 0.25, y + rise, -depth)
	var c := Vector3(x1 + 0.25, y + 0.02, 0.5)
	var d := Vector3(x0 - 0.25, y + 0.02, 0.5)
	quad(f, lot, a, bb, c, d, TERRACOTTA.lightened(0.1), TERRACOTTA.darkened(0.12))
	box(f, lot, Vector3(x1 - x0 + 0.5, 0.16, 0.2), TERRACOTTA.darkened(0.25), Vector3((x0 + x1) * 0.5, y + 0.04, 0.5))
	# hastiales (los costados) y la hilera de la cumbrera
	for side in [[d, a, Vector3(x0 - 0.25, y, -depth)], [bb, c, Vector3(x1 + 0.25, y, -depth)]]:
		quad(f, lot, side[0], side[1], side[2], side[0], WHITE_SHADE, NONE, true)
	box(f, "det", Vector3(x1 - x0 + 0.5, 0.2, 0.3), TERRACOTTA.darkened(0.2), Vector3((x0 + x1) * 0.5, y + rise, -depth))
	var rows := maxi(2, roundi((x1 - x0) / 1.5))
	for k in rows + 1:
		var x := x0 + (x1 - x0) * float(k) / float(rows)
		b._beam(_lot(f, "det", Vector3(x, y, 0.0)), f * Vector3(x, y + rise + 0.03, -depth), f * Vector3(x, y + 0.06, 0.5), 0.07, TERRACOTTA.darkened(0.18), 0.16)


## Torre: fuste cuadrado con pilastras, campanario de vanos en arco y remate escalonado con su
## joya. Centrada en (x, z) del marco; `w` de lado; `h` hasta el campanario.
func tower(f: Transform3D, x: float, z: float, w: float, h: float, color: Color, lot := "obra", belfry := 3.0, glow := GOLD) -> void:
	var shade := color.darkened(0.24)
	box(f, lot, Vector3(w, h, w), color, Vector3(x, h * 0.5, z), shade)
	box(f, lot, Vector3(w + 0.5, 0.34, w + 0.5), WHITE, Vector3(x, h + 0.17, z), WHITE_SHADE)
	var bw := w - 0.7
	var y := h + 0.34
	box(f, lot, Vector3(bw, belfry, bw), color.lightened(0.06), Vector3(x, y + belfry * 0.5, z), shade)
	# vanos del campanario: a los cuatro lados, con la campana a contraluz
	for k in 4:
		var g := f * Transform3D(Basis(Vector3.UP, PI * 0.5 * float(k)), Vector3(x, 0.0, z))
		var ow := bw * 0.46
		panel(g, lot, -ow * 0.5, ow * 0.5, y + 0.35, y + belfry - 0.2 - ow * 0.5, bw * 0.5 + 0.03, Color(0.2, 0.13, 0.12), Color(0.08, 0.06, 0.08))
		disc(g, lot, Vector3(0.0, y + belfry - 0.2 - ow * 0.5, bw * 0.5 + 0.03), ow * 0.5, Color(0.2, 0.13, 0.12), Color(0.2, 0.13, 0.12), 6, 0.0, PI)
		gem(g, "brillo", Vector3(0.5, 0.62, 0.3), glow, Vector3(0.0, y + belfry * 0.52, bw * 0.5 + 0.04), glow.darkened(0.35))
		box(g, "det", Vector3(ow + 0.3, 0.14, 0.16), WHITE, Vector3(0.0, y + 0.28, bw * 0.5 + 0.06))
	y += belfry
	box(f, lot, Vector3(bw + 0.5, 0.3, bw + 0.5), WHITE, Vector3(x, y + 0.15, z), WHITE_SHADE)
	# remate: tres cuerpos que se van recogiendo y una joya encendida
	var side := bw
	for k in 3:
		side *= 0.72
		box(f, lot, Vector3(side, 0.62, side), color.lightened(0.05), Vector3(x, y + 0.61 + 0.62 * float(k), z), shade)
	cyl(f, lot, side * 0.5, 1.1, TERRACOTTA, Vector3(x, y + 2.16, z), 4, 0.04, TERRACOTTA.darkened(0.25), Basis(Vector3.UP, PI * 0.25))
	gem(f, "brillo", Vector3(0.42, 0.7, 0.42), JADE, Vector3(x, y + 3.6, z))


## Soportal: `n` arcos rebajados de `bay` de ancho sobre columnas, desde x0. Las columnas van en
## z = 0 y la galería tiene `deep` de fondo; el muro del fondo lo pone quien llama.
func arcade(f: Transform3D, x0: float, n: int, bay := BAY * 2.0, h := FLOOR_0, deep := 3.2, color := WHITE, lot := "obra") -> void:
	var col_h := 3.0
	for k in n + 1:
		column(f, x0 + bay * float(k), 0.0, col_h, color, 0.42, lot)
	for k in n:
		var xa := x0 + bay * float(k)
		b._arch(lot, f, xa, xa + bay, col_h, h + 0.5, 0.9, bay - 0.95, 0.0, 1.2, color, color.darkened(0.3))
	var w := bay * float(n)
	# techo de la galería y viga del fondo
	box(f, lot, Vector3(w + 0.9, 0.3, deep + 0.9), color.darkened(0.1), Vector3(x0 + w * 0.5, h + 0.65, -deep * 0.5))
	box(f, "suelo", Vector3(w, 0.1, deep), Color(0.5, 0.42, 0.36), Vector3(x0 + w * 0.5, 0.02, -deep * 0.5 - 0.2))


# ───────────────────────── Edificios ─────────────────────────

## Casona: `w` de frente desde x0, de una planta (alta) o de dos. Cada letra es un vano:
##   planta baja (`low`)   P puerta · A puerta con abanico · Z zaguán · T tienda abierta ·
##                         V ventana con reja · _ paño liso
##   planta alta (`high`)  B balcón · V ventana · _ paño liso   ("" = casona de una planta)
## roof: 0–3 pretil (ver parapet) · 4 tejado de teja.
## opts: deep (fondo) · trim · plinth (color del zócalo) · lot · shutters · toldo (colores).
func casona(f: Transform3D, x0: float, w: float, paint: Color, low: String, high := "", roof := 1, door_color := WOOD, opts := {}) -> void:
	var n := low.length()
	var bay := w / float(n)
	var two := not high.is_empty()
	var top := FLOOR_0 + (FLOOR_1 if two else 0.7)
	var deep: float = opts.get("deep", 8.0)
	var trim: Color = opts.get("trim", WHITE)
	var lot: String = opts.get("lot", "obra")
	var x1 := x0 + w
	wall(f, x0, x1, 0.0, top, deep, paint, lot, 0.16)
	plinth(f, x0, x1, opts.get("plinth", paint.darkened(0.3)), 0.85, lot)
	for x in [x0 + 0.21, x1 - 0.21]:
		box(f, lot, Vector3(0.42, top, 0.16), trim, Vector3(x, top * 0.5, 0.05), trim.darkened(0.22))
	if two:
		box(f, "det", Vector3(w - 0.84, 0.18, 0.16), trim, Vector3(x0 + w * 0.5, FLOOR_0 - 0.02, 0.06), trim.darkened(0.2))
	cornice(f, x0, x1, top, trim, 0.28, 0.3, lot)
	if roof == 4:
		tiled_roof(f, x0, x1, top + 0.28, 3.6, 1.5, lot)
	else:
		parapet(f, x0, x1, top + 0.28, roof, trim, bay, lot)
		quad(f, "suelo", Vector3(x0, top + 0.3, -deep), Vector3(x1, top + 0.3, -deep), Vector3(x1, top + 0.3, -0.1), Vector3(x0, top + 0.3, -0.1), AZOTEA)
	for k in n:
		var x := x0 + bay * (float(k) + 0.5)
		_n += 1
		var lit := (_n * 7 + 3) % 5 < 2
		match low[k]:
			"P":
				door(f, x, door_color, 0, false, trim)
				lantern(f, x + DOOR_W * 0.5 + 0.62, 3.0)
			"A":
				door(f, x, door_color, 1, lit, trim)
				lantern(f, x - DOOR_W * 0.5 - 0.62, 3.0)
			"Z":
				door(f, x, door_color, 2, false, trim)
				lantern(f, x + 1.9, 3.3)
				lantern(f, x - 1.9, 3.3)
			"T":
				door(f, x, door_color, 3, true, trim)
				if opts.has("toldo"):
					awning(f, x, 3.75, 2.9, 1.25, opts.toldo, 0.6)
			"V":
				window(f, x, SILL, lit, 0, trim, opts.get("shutters", NONE))
		if two:
			var lit2 := (_n * 5 + 1) % 7 < 3
			match high[k]:
				"B":
					balcony(f, x, FLOOR_0 + 0.22, lit2, trim)
				"V":
					window(f, x, FLOOR_0 + 1.15, lit2, 0, trim, opts.get("shutters", NONE))


## Callejón entre dos casas: un arco bajo con su farol y, al fondo, una ventana encendida.
func alley(f: Transform3D, x0: float, w: float, color := WHITE, deep := 8.0) -> void:
	b._arch("obra", f, x0, x0 + w, 0.0, 3.9, 0.5, w - 0.5, 2.3, (w - 0.5) * 0.5, color, color.darkened(0.3))
	cornice(f, x0, x0 + w, 3.9, color, 0.2, 0.2)
	panel(f, "obra", x0, x0 + w, 0.0, 3.9, -deep, Color(0.1, 0.09, 0.14), Color(0.05, 0.05, 0.08))
	panel(f, "brillo", x0 + w * 0.5 - 0.3, x0 + w * 0.5 + 0.3, 1.5, 2.5, -deep + 0.05, LIT.darkened(0.2), LIT.darkened(0.45))
	quad(f, "suelo", Vector3(x0, 0.01, -deep), Vector3(x0 + w, 0.01, -deep), Vector3(x0 + w, 0.01, 0.0), Vector3(x0, 0.01, 0.0), Color(0.16, 0.14, 0.17), Color(0.36, 0.3, 0.3))
	gem(f, "brillo", Vector3(0.22, 0.34, 0.22), WARM, Vector3(x0 + w * 0.5, 2.75, -0.1))
	wash(f, x0 + w * 0.5, 2.9, 1.4, WARM, 0.3, 0.3)
	b._pool(f * Vector3(x0 + w * 0.5, 0.0, 0.6), 2.2, WARM, 0.26)


## Portales comerciales: soportal de `n` arcos con una tienda por arco al fondo de la galería,
## azotea con balaustrada y macetones. `shops`: por arco, [color de la puerta, toldo (colores) o null].
func portales(f: Transform3D, x0: float, n: int, paint: Color, shops: Array, deep := 3.2) -> void:
	var bay := BAY * 2.0
	var w := bay * float(n)
	var top := FLOOR_0 + 0.8
	arcade(f, x0, n, bay, FLOOR_0, deep)
	cornice(f, x0 - 0.45, x0 + w + 0.45, top, WHITE)
	parapet(f, x0 - 0.45, x0 + w + 0.45, top + 0.28, 3, WHITE, bay)
	# el cuerpo de las tiendas, detrás de la galería
	var g := f * Transform3D(Basis.IDENTITY, Vector3(0.0, 0.0, -deep))
	wall(g, x0 - 0.45, x0 + w + 0.45, 0.0, top, 6.0, paint, "obra", 0.2)
	plinth(g, x0, x0 + w, paint.darkened(0.32), 0.8, "det")
	quad(f, "suelo", Vector3(x0 - 0.45, top + 0.3, -deep - 6.0), Vector3(x0 + w + 0.45, top + 0.3, -deep - 6.0), Vector3(x0 + w + 0.45, top + 0.3, -0.2), Vector3(x0 - 0.45, top + 0.3, -0.2), AZOTEA)
	for k in n:
		var x := x0 + bay * (float(k) + 0.5)
		var shop: Array = shops[k % shops.size()]
		door(g, x, shop[0], 3, true)
		window(g, x - 2.05, SILL, true, 2)
		window(g, x + 2.05, SILL, k % 2 == 0, 2)
		signboard(g, x, 3.6, 2.6, shop[0])
		# farol colgado de la clave del arco
		b._lantern(f * Vector3(x, 3.35, -0.1), 0.4, WARM, 0.2)
		b._pool(f * Vector3(x, 0.0, 0.9), 3.4, WARM, 0.26)
		if shop.size() > 1 and shop[1] != null:
			awning(f, x, 3.5, bay - 1.5, 1.15, shop[1], 0.55, 0.42)


## El templo: un santuario fantástico de piedra caliza, con atrio escalonado, portada de falso
## arco, rosetón de jade y oro, vitrales, crestería y dos torres. `w` de frente (24 m).
func templo(f: Transform3D, lot := "suelo") -> void:
	var w := 24.0
	var tw := 5.2                     # lado de las torres
	var nave_h := 10.4
	var mid := w * 0.5
	var stone := STONE
	# nave y su talud
	wall(f, tw - 0.3, w - tw + 0.3, 0.0, nave_h, 12.0, stone, lot, 0.2)
	box(f, lot, Vector3(w - tw * 2.0 + 0.6, 1.5, 0.5), stone.darkened(0.12), Vector3(mid, 0.75, 0.2), STONE_SHADE)
	cornice(f, tw, w - tw, nave_h, WHITE, 0.34, 0.36, lot)
	# crestería escalonada, con sus huecos y la joya
	var cw := w - tw * 2.0 - 1.2
	for k in 3:
		box(f, lot, Vector3(cw - 3.4 * float(k), 0.95, 0.9), stone.lightened(0.04), Vector3(mid, nave_h + 0.8 + 0.95 * float(k), -0.5), stone.darkened(0.14))
	for k in 5:
		panel(f, "det", mid - 4.6 + 2.3 * float(k) - 0.34, mid - 4.6 + 2.3 * float(k) + 0.34, nave_h + 0.52, nave_h + 1.1, -0.04, STONE_SHADE.darkened(0.4))
	gem(f, "brillo", Vector3(0.6, 0.95, 0.4), JADE, Vector3(mid, nave_h + 3.75, -0.5))
	# atrio: tres escalones
	# (nada pasa de z = 1: hasta ahí llega un alux y esto no es un obstáculo)
	for k in 3:
		var sd := 0.98 - 0.11 * float(k)
		box(f, lot, Vector3(9.4 - 0.5 * float(k), 0.2, sd), stone.lightened(0.06), Vector3(mid, 0.1 + 0.2 * float(k), sd * 0.5), STONE_SHADE)
	# portada: falso arco entre columnas pareadas, con el interior encendido
	var py := 0.6
	b._arch(lot, f * Transform3D(Basis.IDENTITY, Vector3(0.0, 0.0, 0.42)), mid - 3.3, mid + 3.3, py, 7.4, 0.5, 3.3, 2.9, 2.5, WHITE, WHITE_SHADE, 1)
	panel(f, "brillo", mid - 1.75, mid + 1.75, py, 6.1, 0.5, Color(0.5, 0.24, 0.12), Color(1.0, 0.72, 0.36))
	for s: float in [-1.0, 1.0]:
		for q in 2:
			var cx := mid + s * (2.25 + 0.8 * float(q))
			cyl(f, lot, 0.24, 5.3, WHITE, Vector3(cx, py, 0.72), 6, 0.2, WHITE_SHADE)
			box(f, "det", Vector3(0.62, 0.24, 0.56), WHITE, Vector3(cx, py + 5.42, 0.72))
	box(f, lot, Vector3(7.2, 0.5, 0.7), WHITE, Vector3(mid, 7.65, 0.6), WHITE_SHADE)
	# greca escalonada sobre el dintel (geometría, no escritura)
	for k in 9:
		var gx := mid - 3.2 + 0.8 * float(k)
		box(f, "det", Vector3(0.46, 0.2, 0.1), stone.darkened(0.3), Vector3(gx, 7.56 + (0.14 if k % 2 == 0 else 0.0), 0.97))
	wash(f, mid, 3.2, 4.6, WARM, 0.2, 0.75)
	b._pool(f * Vector3(mid, 0.0, 2.2), 5.5, WARM, 0.32)
	# rosetón: un sol de ocho gajos de jade y oro
	var rc := Vector3(mid, 9.05, 0.0)
	cyl(f, lot, 1.36, 0.34, WHITE, rc, 12, -1.0, WHITE_SHADE, Basis(Vector3.RIGHT, PI * 0.5))
	for k in 8:
		var a0 := TAU * float(k) / 8.0
		disc(f, "brillo", rc + Vector3(0, 0, 0.36), 1.12, Color(1.0, 0.95, 0.7), JADE if k % 2 == 0 else GOLD, 1, a0 + 0.04, a0 + TAU / 8.0 - 0.04)
	gem(f, "det", Vector3(0.36, 0.36, 0.2), WHITE, rc + Vector3(0, 0, 0.4))
	wash(f, mid, 9.05, 2.6, JADE, 0.16, 0.4)
	# vitrales altos a los lados de la portada
	for s: float in [-1.0, 1.0]:
		var vx := mid + s * 5.2
		for k in 3:
			var c0: Color = [Color(0.2, 0.85, 0.75), Color(1.0, 0.75, 0.3), Color(0.95, 0.35, 0.5)][k]
			panel(f, "brillo", vx - 0.5, vx + 0.5, 2.4 + 1.5 * float(k), 3.85 + 1.5 * float(k), 0.04, c0, c0.darkened(0.35))
		disc(f, "brillo", Vector3(vx, 6.85, 0.04), 0.5, Color(1.0, 0.9, 0.6), Color(0.95, 0.35, 0.5), 6, 0.0, PI)
		box(f, "det", Vector3(1.4, 0.2, 0.3), WHITE, Vector3(vx, 2.25, 0.12), WHITE_SHADE)
		for q: float in [-1.0, 1.0]:
			box(f, "det", Vector3(0.16, 4.6, 0.16), WHITE, Vector3(vx + q * 0.6, 4.6, 0.06), WHITE_SHADE)
		b._pool(f * Vector3(vx, 0.0, 1.4), 2.6, Color(0.5, 0.95, 0.8), 0.16)
	# torres
	for s: float in [0.0, 1.0]:
		var tx := tw * 0.5 + s * (w - tw)
		var g := f * Transform3D(Basis.IDENTITY, Vector3(tx, 0.0, 0.0))
		tower(f, tx, -tw * 0.5 + 0.7, tw, 12.6, stone.lightened(0.03), lot, 3.2)
		box(f, lot, Vector3(tw + 0.3, 1.5, 0.3), stone.darkened(0.12), Vector3(tx, 0.75, 0.82), STONE_SHADE)
		var gz := Transform3D(Basis.IDENTITY, Vector3(0.0, 0.0, 0.7))
		for lvl in 3:
			var wy := 2.6 + 3.5 * float(lvl)
			window(g * gz, 0.0, wy, lvl != 1, 2, WHITE)
			if lvl > 0:
				box(f, "det", Vector3(tw + 0.24, 0.2, 0.2), WHITE, Vector3(tx, wy - 0.9, 0.74), WHITE_SHADE)
		for q: float in [-1.0, 1.0]:
			box(f, "det", Vector3(0.5, 12.6, 0.18), stone.lightened(0.1), Vector3(tx + q * (tw * 0.5 - 0.25), 6.3, 0.76), stone.darkened(0.2))
	# braseros de copal al pie de la escalinata
	for s: float in [-1.0, 1.0]:
		var p := Vector3(mid + s * 5.3, 0.0, 0.52)
		cyl(f, "det", 0.24, 0.8, STONE_SHADE, p, 6, 0.18)
		cyl(f, "det", 0.34, 0.24, stone, p + Vector3(0, 0.8, 0), 6, 0.42)
		cyl(f, "brillo", 0.24, 0.5, Color(1.0, 0.5, 0.16), p + Vector3(0, 1.0, 0), 5, 0.0, Color(1.0, 0.86, 0.5))
		b._pool(f * (p + Vector3(0, 0, 0.8)), 3.0, Color(1.0, 0.6, 0.25), 0.3)
