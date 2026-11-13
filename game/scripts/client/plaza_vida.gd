extends RefCounted
## Lo vivo y lo menudo de la plaza de Mérida: vegetación (ceiba, flamboyán, lluvia de oro, laurel,
## palmas, buganvilias, macetas con henequén), los puestos del mercado y el mobiliario
## (confidentes, farolas). Todo va a los lotes del constructor (plaza_builder.gd): no añade
## llamadas de dibujo. Siluetas variadas con pocos triángulos: copas de bolas achatadas con el
## lado del sol más claro, hojas de palma de dos tramos y frutos de ocho caras.

const Zone := preload("res://scripts/shared/zone_def.gd")
const Mod := preload("res://scripts/client/plaza_modulos.gd")

const LEAF := Color(0.15, 0.38, 0.2)
const LEAF_LIGHT := Color(0.46, 0.64, 0.24)
const LEAF_DEEP := Color(0.08, 0.24, 0.16)
const BARK := Color(0.4, 0.29, 0.21)
const WOOD := Color(0.5, 0.33, 0.2)
const WOOD_DARK := Color(0.3, 0.2, 0.14)
const TERRACOTTA := Color(0.72, 0.36, 0.24)
const WHITE := Color(0.9, 0.87, 0.8)
const WHITE_SHADE := Color(0.66, 0.62, 0.62)
const IRON := Color(0.1, 0.11, 0.13)
const MAGENTA := Color(0.9, 0.16, 0.5)
const WARM := Color(1.0, 0.78, 0.42)
const NONE := Color(0, 0, 0, 0)

var b                      # plaza_builder.gd
var m: Mod                 # las piezas de arquitectura (para toldos y rótulos)
var _sun := Vector2.ZERO   # hacia dónde está el sol, en planta


func _init(builder, modulos: Mod) -> void:
	b = builder
	m = modulos
	_sun = Vector2(b.SUN_TO.x, b.SUN_TO.z).normalized()


func _r() -> float:
	return b._rng.randf()


# ───────────────────────── Árboles ─────────────────────────

## Copa de bolas achatadas: `blobs` = [dx, dy, dz, radio]. La cara que mira al sol va más clara y
## la panza de cada bola más oscura: da volumen sin texturas.
func canopy(lot: String, at: Vector3, blobs: Array, light: Color, dark: Color, squash := 0.7, sides := 8) -> void:
	for c in blobs:
		var off := Vector2(c[0], c[2])
		var k := 0.55
		if off.length() > 0.3:
			k = 0.5 + 0.5 * off.normalized().dot(_sun)
		k = clampf(k * 0.75 + _r() * 0.3, 0.0, 1.0)
		var col := dark.lerp(light, k)
		b._ball(lot, float(c[3]), col, at + Vector3(c[0], c[1], c[2]), squash, col.darkened(0.5), sides)


## La gran ceiba del centro: copa ancha, en pisos, sobre ramas casi horizontales.
func ceiba(at: Vector3) -> void:
	for br in [[3.6, 6.6, 1.8], [-3.4, 6.8, 2.2], [1.6, 6.5, -3.6], [-2.6, 6.4, -3.2], [5.2, 6.3, -1.2], [-5.4, 6.3, -0.2], [0.4, 6.2, 4.8]]:
		b._limb("obra", at + Vector3(0, 5.0, 0), at + Vector3(br[0], br[1], br[2]), 0.3, 0.14, BARK.lightened(0.05), 5)
	canopy("obra", at, [[0.0, 8.7, 0.0, 4.3], [3.5, 7.7, 1.9, 3.1], [-3.3, 7.9, 2.3, 3.2], [1.7, 7.6, -3.5, 3.0], [-2.7, 7.4, -3.1, 3.0],
		[0.2, 10.8, 0.4, 3.0], [5.8, 7.0, -1.1, 2.3], [-5.8, 7.1, -0.4, 2.4], [0.6, 6.9, 5.2, 2.4], [-0.8, 6.9, -5.6, 2.3],
		[4.2, 6.7, 4.2, 2.0], [-4.4, 6.7, 4.4, 2.1], [4.4, 6.6, -4.4, 2.0], [-4.6, 6.5, -4.2, 2.0], [2.5, 9.8, -1.3, 2.3], [-2.3, 9.9, 1.1, 2.3]],
		LEAF_LIGHT, LEAF.darkened(0.1), 0.62)


## Flamboyán: tronco que se abre en horquilla y copa en sombrilla, encendida de flores.
func flamboyan(at: Vector3, bloom: Color) -> void:
	b._limb("obra", at, at + Vector3(0.2, 2.2, 0.0), 0.36, 0.26, BARK, 6, BARK.darkened(0.3))
	for br in [[1.7, 3.9, 0.5], [-1.6, 4.0, -0.5], [0.3, 3.9, -1.7], [-0.4, 4.0, 1.7]]:
		b._limb("obra", at + Vector3(0.2, 2.1, 0.0), at + Vector3(br[0], br[1], br[2]), 0.2, 0.1, BARK, 5)
	canopy("obra", at, [[0.0, 4.75, 0.0, 2.5], [2.3, 4.4, 0.7, 1.9], [-2.2, 4.5, -0.7, 1.9], [0.5, 4.4, -2.3, 1.8], [-0.6, 4.5, 2.3, 1.8]],
		bloom.lightened(0.12), bloom.darkened(0.25), 0.46)
	canopy("obra", at, [[1.5, 4.95, -1.3, 1.2], [-1.4, 5.0, 1.3, 1.2], [-1.6, 4.3, -2.0, 1.0], [1.9, 4.2, 2.0, 1.0]], LEAF_LIGHT, LEAF, 0.5, 6)


## Lluvia de oro: copa ligera de la que cuelgan racimos amarillos.
func lluvia_de_oro(at: Vector3) -> void:
	b._limb("obra", at, at + Vector3(-0.1, 3.0, 0.1), 0.3, 0.2, BARK.lightened(0.1), 6, BARK.darkened(0.3))
	canopy("obra", at, [[0.0, 4.5, 0.0, 2.2], [1.5, 4.0, 0.6, 1.6], [-1.4, 4.1, -0.5, 1.6], [0.3, 3.9, -1.5, 1.4], [-0.4, 4.0, 1.5, 1.5]],
		Color(0.6, 0.72, 0.28), LEAF, 0.66)
	for k in 14:
		var a := TAU * float(k) / 14.0 + _r() * 0.3
		var r := 1.2 + _r() * 1.5
		var p := at + Vector3(sin(a) * r, 3.25 + _r() * 0.5, cos(a) * r)
		b._emit("det" + str(_quad_of(p)), "oct", Basis.IDENTITY, Vector3(0.34, 0.9 + _r() * 0.5, 0.34), p, Color(1.0, 0.86, 0.25), Color(0.95, 0.66, 0.12))


## Laurel de plaza: copa densa y recortada, con el pie del tronco encalado.
func laurel(at: Vector3) -> void:
	b._limb("obra", at, at + Vector3(0, 1.0, 0), 0.4, 0.36, WHITE, 7, WHITE_SHADE)
	b._limb("obra", at + Vector3(0, 1.0, 0), at + Vector3(0, 3.2, 0), 0.36, 0.26, BARK, 7)
	canopy("obra", at, [[0.0, 4.6, 0.0, 2.4], [1.5, 4.2, 0.8, 1.8], [-1.5, 4.3, -0.6, 1.8], [0.4, 4.1, -1.6, 1.7], [-0.5, 4.2, 1.6, 1.7], [0.0, 5.7, 0.2, 1.6]],
		Color(0.3, 0.5, 0.24), LEAF_DEEP, 0.86)


func _quad_of(p: Vector3) -> int:
	return (1 if p.x >= 0.0 else 0) + (2 if p.z >= 0.0 else 0)


## Palma: tronco anillado que se curva un poco y penacho de hojas en dos tramos.
func palm(lot: String, at: Vector3, h: float, lean := Vector2.ZERO, fronds := 8, scale := 1.0) -> void:
	var prev := at
	for k in 3:
		var t := float(k + 1) / 3.0
		var p := at + Vector3(lean.x * t * t, h * t, lean.y * t * t)
		var grey := Color(0.56, 0.5, 0.42).darkened(0.08 * float(k % 2))
		b._limb(lot, prev, p, (0.3 - 0.05 * float(k)) * scale, (0.25 - 0.05 * float(k)) * scale, grey, 6, grey.darkened(0.25) if k == 0 else NONE)
		prev = p
	var top := prev
	b._emit(lot, "oct", Basis.IDENTITY, Vector3(0.7, 1.3, 0.7) * scale, top + Vector3(0, 0.3, 0), LEAF_LIGHT.darkened(0.1), LEAF)
	for k in fronds:
		var a := TAU * float(k) / float(fronds) + _r() * 0.4
		var dir := Vector3(sin(a), 0.0, cos(a))
		var side := Vector3(dir.z, 0.0, -dir.x)
		var lift := 0.25 + _r() * 0.75
		var p1 := top + (dir * 1.5 + Vector3(0, 0.5 + lift * 0.5, 0)) * scale
		var p2 := top + (dir * (2.7 + lift * 0.5) + Vector3(0, -0.9 + lift * 0.9, 0)) * scale
		var lit := 0.5 + 0.5 * Vector2(dir.x, dir.z).dot(_sun)
		var col := LEAF.lerp(LEAF_LIGHT, lit * 0.8)
		b._quad(lot, top + Vector3(0, 0.3, 0) - side * 0.12 * scale, top + Vector3(0, 0.3, 0) + side * 0.12 * scale, p1 + side * 0.52 * scale, p1 - side * 0.52 * scale, col, col.lightened(0.08), true)
		b._quad(lot, p1 - side * 0.52 * scale, p1 + side * 0.52 * scale, p2 + side * 0.06 * scale, p2 - side * 0.06 * scale, col.lightened(0.08), col.darkened(0.3), true)


## Árbol de fondo (detrás de las casas): tronco y una copa, sin sombra.
func backdrop_tree(at: Vector3, h: float, r: float, light := LEAF_LIGHT) -> void:
	b._limb("suelo", at, at + Vector3(0, h, 0), 0.45, 0.3, BARK.darkened(0.15), 5)
	canopy("suelo", at, [[0.0, h + r * 0.4, 0.0, r], [r * 0.7, h, r * 0.3, r * 0.7], [-r * 0.6, h + 0.2, -r * 0.4, r * 0.72]], light.lerp(LEAF, 0.35), LEAF_DEEP, 0.78, 6)


# ───────────────────────── Plantas ─────────────────────────

## Buganvilia que se derrama por un muro: racimos de flor sobre algo de hoja. Marco de fachada.
func buganvilia(f: Transform3D, x: float, y: float, w: float, drop: float, color := MAGENTA) -> void:
	var n := maxi(3, roundi(w / 0.7))
	for k in n:
		var px := x - w * 0.5 + w * (float(k) + _r() * 0.6) / float(n)
		var fall := drop * _r() * _r()
		var p := Vector3(px, y - fall, 0.22 + _r() * 0.16)
		var r := 0.42 + _r() * 0.3
		var c := color.lerp(Color(1.0, 0.45, 0.62), _r() * 0.5).darkened(_r() * 0.18)
		if k % 3 == 2:
			m.gem(f, "det", Vector3(r * 2.2, r * 1.6, r * 1.1), LEAF.lerp(LEAF_LIGHT, _r()), p + Vector3(0, 0.2, -0.08), LEAF_DEEP)
		else:
			b._emit(m._lot(f, "det", p), "ball|6", f.basis, Vector3(r * 2.3, r * 1.7, r * 1.0), f * p, c.lightened(0.1), c.darkened(0.35))
		# ramas sueltas que cuelgan
		if k % 2 == 0:
			m.gem(f, "det", Vector3(0.34, 0.8 + drop * 0.5 * _r(), 0.26), c, p + Vector3(0.1, -0.6 - fall * 0.3, 0.04), c.darkened(0.3))


## Maceta de barro. kind: 0 mata con flores · 1 henequén (roseta de pencas) · 2 helecho de hojas largas.
func pot(at: Vector3, kind := 0, size := 1.0, flower := MAGENTA) -> void:
	var d := "det" + str(_quad_of(at))
	b._cyl(d, 0.26 * size, 0.46 * size, TERRACOTTA, at, 6, 0.36 * size, TERRACOTTA.darkened(0.3))
	var top := at + Vector3(0, 0.46 * size, 0)
	match kind:
		0:
			b._ball(d, 0.36 * size, LEAF_LIGHT.darkened(0.05), top + Vector3(0, 0.22 * size, 0), 0.85, LEAF, 6)
			for k in 3:
				var a := TAU * float(k) / 3.0 + _r()
				b._emit(d, "oct", Basis.IDENTITY, Vector3(0.2, 0.2, 0.2) * size, top + Vector3(sin(a) * 0.22, 0.44, cos(a) * 0.22) * size, flower, NONE)
		1:
			for k in 7:
				var a := TAU * float(k) / 7.0
				var tilt := 0.5 + 0.35 * float(k % 2)
				var basis := Basis(Vector3.UP, a) * Basis(Vector3.RIGHT, tilt)
				b._cyl(d, 0.09 * size, 0.95 * size, Color(0.45, 0.6, 0.5), top - Vector3(0, 0.05, 0), 4, 0.01, Color(0.24, 0.4, 0.36), basis)
		_:
			for k in 6:
				var a := TAU * float(k) / 6.0 + 0.3
				var dir := Vector3(sin(a), 0.0, cos(a))
				var side := Vector3(dir.z, 0.0, -dir.x) * 0.16 * size
				var tip := top + (dir * 0.75 + Vector3(0, 0.5, 0)) * size
				b._quad(d, top - side, top + side, tip + side * 0.2, tip - side * 0.2, LEAF, LEAF_LIGHT, true)


## Seto bajo recortado, de `a` a `c` (esquinas en planta).
func hedge(x0: float, z0: float, x1: float, z1: float, h := 0.5) -> void:
	var c := Vector3((x0 + x1) * 0.5, h * 0.5, (z0 + z1) * 0.5)
	b._box("det" + str(_quad_of(c)), Vector3(absf(x1 - x0), h, absf(z1 - z0)), Color(0.26, 0.47, 0.22), c, 0.0, LEAF_DEEP)


## Mata de flores a ras de suelo.
func flowers(at: Vector3, color: Color, n := 4, spread := 0.6) -> void:
	var d := "det" + str(_quad_of(at))
	b._ball(d, 0.5, LEAF_LIGHT.darkened(0.12), at + Vector3(0, 0.2, 0), 0.7, LEAF, 6)
	for k in n:
		var a := TAU * float(k) / float(n) + _r()
		b._emit(d, "oct", Basis.IDENTITY, Vector3(0.24, 0.22, 0.24), at + Vector3(sin(a) * spread * 0.55, 0.5 + _r() * 0.12, cos(a) * spread * 0.55), color, color.darkened(0.25))


# ───────────────────────── Mercado ─────────────────────────

## Puesto de mercado sobre su obstáculo (zone_def.STALLS): mesa, cuatro postes, toldo de rayas,
## tablero para el rótulo y su género. kind: 0 frutas · 1 telas y hamacas · 2 barro · 3 antojitos.
## El frente (por donde se compra) es +z del marco; quien vende se pone detrás de la mesa.
func stall(at: Vector3, yaw: float, kind: int, awn: Array) -> void:
	var f := Mod.frame(at, yaw)
	var d := "det" + str(_quad_of(at))
	# tarima, mesa con su mantel y cajones al fondo
	m.box(f, "obra", Vector3(3.0, 0.1, 2.2), WOOD_DARK, Vector3(0, 0.05, 0))
	m.box(f, "obra", Vector3(2.9, 0.75, 0.95), WOOD, Vector3(0, 0.47, 0.6), WOOD_DARK)
	m.box(f, d, Vector3(2.96, 0.07, 1.02), WOOD.lightened(0.18), Vector3(0, 0.88, 0.6))
	var cloth: Color = awn[0]
	m.panel(f, d, -1.46, 1.46, 0.3, 0.84, 1.09, cloth.darkened(0.1), cloth.darkened(0.4))
	m.panel(f, d, -1.46, 1.46, 0.3, 0.42, 1.095, awn[1])
	# postes y travesaños
	for sx: float in [-1.0, 1.0]:
		m.box(f, "obra", Vector3(0.1, 2.95, 0.1), WOOD_DARK, Vector3(sx * 1.42, 1.52, -1.02))
		m.box(f, "obra", Vector3(0.1, 2.5, 0.1), WOOD_DARK, Vector3(sx * 1.42, 1.3, 1.02))
	m.box(f, d, Vector3(2.95, 0.08, 0.08), WOOD_DARK, Vector3(0, 2.5, 1.02))
	m.box(f, d, Vector3(2.95, 0.08, 0.08), WOOD_DARK, Vector3(0, 2.95, -1.02))
	# toldo (arroja sombra) y su fleco
	var n := 6
	for k in n:
		var xa := -1.7 + 3.4 * float(k) / float(n)
		var xb := xa + 3.4 / float(n)
		var c: Color = awn[k % 2]
		m.quad(f, "obra", Vector3(xa, 3.08, -1.25), Vector3(xb, 3.08, -1.25), Vector3(xb, 2.5, 1.5), Vector3(xa, 2.5, 1.5), c, c.darkened(0.2), true)
		m.quad(f, d, Vector3(xa, 2.5, 1.5), Vector3(xb, 2.5, 1.5), Vector3(xb, 2.24, 1.5), Vector3(xa, 2.24, 1.5), c.darkened(0.06), c.darkened(0.3), true)
	# tablero del rótulo sobre el frente y farol bajo el toldo
	m.signboard(f, 0.0, 2.95, 2.3, WOOD_DARK, 1.5)
	b._lantern(f * Vector3(0.9, 2.05, 0.6), 0.3, WARM, 0.14)
	b._pool(f * Vector3(0, 0, 1.4), 3.0, WARM, 0.22)
	match kind:
		0:
			_fruit(f, d)
		1:
			_cloth(f, d)
		2:
			_clay(f, d)
		_:
			_snacks(f, d)


## Cajón inclinado hacia quien compra, lleno de fruta de un color.
func _crate(f: Transform3D, d: String, x: float, z: float, fruit: Color, n := 6, y := 0.92) -> void:
	var tilt := Basis(Vector3.RIGHT, 0.32)
	b._emit(d, "box", f.basis * tilt, Vector3(0.78, 0.2, 0.56), f * Vector3(x, y + 0.14, z), WOOD.lightened(0.1), WOOD_DARK)
	for k in n:
		var px := x - 0.26 + 0.26 * float(k % 3)
		var pz := z - 0.13 + 0.26 * float(k / 3)
		b._emit(d, "oct", f.basis, Vector3(0.25, 0.23, 0.25), f * Vector3(px, y + 0.3 - (pz - z) * 0.3, pz), fruit.lightened(_r() * 0.12), fruit.darkened(0.3))


func _fruit(f: Transform3D, d: String) -> void:
	var kinds: Array = [Color(1.0, 0.55, 0.1), Color(0.86, 0.16, 0.4), Color(0.5, 0.74, 0.2), Color(1.0, 0.82, 0.2), Color(0.8, 0.14, 0.14), Color(0.96, 0.42, 0.2)]
	for k in 3:
		_crate(f, d, -0.95 + 0.95 * float(k), 0.78, kinds[k])
		_crate(f, d, -0.95 + 0.95 * float(k), 0.36, kinds[k + 3], 6, 1.08)
	# racimos de plátano colgados del travesaño y sandías en el suelo
	for k in 3:
		var p := Vector3(-0.9 + 0.5 * float(k), 2.12, 1.02)
		m.box(f, d, Vector3(0.02, 0.36, 0.02), WOOD_DARK, p + Vector3(0, 0.2, 0))
		for q in 3:
			m.gem(f, d, Vector3(0.12, 0.42, 0.12), Color(1.0, 0.84, 0.22), p + Vector3(0.08 * float(q - 1), -0.1, 0.0), Color(0.8, 0.6, 0.1))
	for k in 3:
		b._emit(d, "ball|6", f.basis, Vector3(0.5, 0.42, 0.42), f * Vector3(-1.15 + 0.5 * float(k), 0.31, -0.6 + 0.1 * float(k % 2)), Color(0.3, 0.55, 0.22), Color(0.14, 0.32, 0.14))
	m.box(f, d, Vector3(0.8, 0.5, 0.6), WOOD, Vector3(0.9, 0.35, -0.7), WOOD_DARK)


func _cloth(f: Transform3D, d: String) -> void:
	var dyes: Array = [MAGENTA, Color(0.1, 0.7, 0.74), Color(1.0, 0.8, 0.2), Color(0.56, 0.36, 0.84), Color(1.0, 0.5, 0.12), Color(0.96, 0.94, 0.88), Color(0.3, 0.7, 0.4)]
	# pilas de telas dobladas
	for k in 4:
		for q in 3 + k % 2:
			var c: Color = dyes[(k * 2 + q) % dyes.size()]
			m.box(f, d, Vector3(0.6, 0.085, 0.62), c, Vector3(-1.08 + 0.72 * float(k), 0.96 + 0.09 * float(q), 0.6), c.darkened(0.25))
	# huipiles y rebozos colgados al fondo, con su cenefa
	for k in 5:
		var x := -1.2 + 0.6 * float(k)
		var c: Color = dyes[(k * 3 + 1) % dyes.size()]
		m.panel(f, d, x - 0.26, x + 0.26, 1.55, 2.86, -0.98, c, c.darkened(0.3))
		m.panel(f, d, x - 0.26, x + 0.26, 1.72, 1.9, -0.975, dyes[(k * 3 + 4) % dyes.size()])
	# una hamaca colgada de poste a poste, a un costado
	var prev := Vector3(1.42, 2.3, 1.0)
	for k in 5:
		var t := float(k + 1) / 5.0
		var p := Vector3(1.42, 2.3 - sin(t * PI) * 0.75, 1.0 - 2.0 * t)
		var c: Color = dyes[k % 3]
		m.quad(f, d, prev + Vector3(0, 0.02, 0), p + Vector3(0, 0.02, 0), p + Vector3(0.1, -0.42 * sin(t * PI) - 0.02, 0), prev + Vector3(0.1, -0.42 * sin((t - 0.2) * PI) - 0.02, 0), c, c.darkened(0.25), true)
		prev = p


func _clay(f: Transform3D, d: String) -> void:
	var clay := Color(0.74, 0.4, 0.26)
	var jars: Array = [[-1.15, 0.5, 0.3, 0.5], [-0.55, 0.75, 0.22, 0.34], [0.05, 0.45, 0.34, 0.6], [0.7, 0.75, 0.2, 0.3], [1.15, 0.5, 0.26, 0.42], [-0.15, 0.85, 0.16, 0.24], [0.42, 0.34, 0.18, 0.3]]
	for j in jars:
		var p := f * Vector3(j[0], 0.92, j[1])
		var c := clay.lerp(Color(0.56, 0.3, 0.2), _r() * 0.6)
		b._emit(d, "ball|6", f.basis, Vector3(float(j[2]) * 2.0, float(j[3]), float(j[2]) * 2.0), p + Vector3(0, float(j[3]) * 0.5, 0), c.lightened(0.1), c.darkened(0.3))
		b._cyl(d, float(j[2]) * 0.5, float(j[3]) * 0.3, c, p + Vector3(0, float(j[3]) * 0.9, 0), 6, float(j[2]) * 0.62)
	# platos apoyados al fondo y tinajas en el suelo
	for k in 4:
		m.cyl(f, d, 0.3, 0.05, [clay.lightened(0.15), Color(0.2, 0.5, 0.6), clay, Color(0.9, 0.82, 0.6)][k], Vector3(-1.05 + 0.7 * float(k), 1.75, -0.95), 8, -1.0, NONE, Basis(Vector3.RIGHT, PI * 0.5 - 0.25))
	m.box(f, d, Vector3(2.9, 0.06, 0.3), WOOD, Vector3(0, 1.44, -0.95))
	for k in 2:
		var p := f * Vector3(-1.9 - 0.1 * float(k), 0.0, 0.5 - 0.9 * float(k))
		b._emit(d, "ball|6", Basis.IDENTITY, Vector3(0.75, 0.85, 0.75), p + Vector3(0, 0.42, 0), clay, clay.darkened(0.4))
		b._cyl(d, 0.2, 0.2, clay.darkened(0.1), p + Vector3(0, 0.8, 0), 6, 0.26)


func _snacks(f: Transform3D, d: String) -> void:
	# comal sobre su brasero, con las brasas encendidas
	m.cyl(f, d, 0.36, 0.3, Color(0.3, 0.22, 0.2), Vector3(-0.9, 0.92, 0.6), 7, 0.42)
	m.cyl(f, "brillo", 0.3, 0.05, Color(1.0, 0.45, 0.12), Vector3(-0.9, 1.19, 0.6), 7)
	m.cyl(f, d, 0.46, 0.05, Color(0.16, 0.15, 0.16), Vector3(-0.9, 1.24, 0.6), 8)
	for k in 3:
		m.cyl(f, d, 0.13, 0.025, Color(0.95, 0.82, 0.55), Vector3(-1.05 + 0.16 * float(k), 1.3, 0.52 + 0.1 * float(k % 2)), 6)
	# torre de tortillas, cazuela y tres vitroleros de aguas frescas
	m.cyl(f, d, 0.16, 0.2, Color(0.95, 0.86, 0.62), Vector3(-0.25, 0.92, 0.75), 6, -1.0, Color(0.8, 0.66, 0.4))
	m.cyl(f, d, 0.26, 0.2, TERRACOTTA, Vector3(-0.2, 0.92, 0.36), 7, 0.33, TERRACOTTA.darkened(0.3))
	m.cyl(f, d, 0.24, 0.03, Color(0.5, 0.16, 0.1), Vector3(-0.2, 1.1, 0.36), 7)
	for k in 3:
		var c: Color = [Color(0.75, 0.1, 0.25), Color(0.95, 0.92, 0.84), Color(0.6, 0.8, 0.3)][k]
		m.cyl(f, d, 0.19, 0.46, c, Vector3(0.38 + 0.46 * float(k), 0.92, 0.62), 6, 0.2, c.darkened(0.3))
		m.cyl(f, d, 0.12, 0.08, Color(0.85, 0.9, 0.9), Vector3(0.38 + 0.46 * float(k), 1.38, 0.62), 6)
	# ristras de chile colgadas y olla grande detrás
	for k in 2:
		for q in 4:
			m.gem(f, d, Vector3(0.12, 0.2, 0.12), Color(0.8, 0.12, 0.1).darkened(0.1 * float(q % 2)), Vector3(-1.2 + 2.4 * float(k), 2.3 - 0.17 * float(q), 1.02), Color(0.5, 0.06, 0.06))
	b._emit(d, "ball|6", Basis.IDENTITY, Vector3(0.8, 0.7, 0.8), f * Vector3(1.0, 0.45, -0.7), TERRACOTTA.darkened(0.15), Color(0.2, 0.12, 0.1))


# ───────────────────────── Mobiliario ─────────────────────────

## «Confidente»: dos asientos encontrados unidos por un respaldo en ese. Ocupa el obstáculo del
## banco (`hx`, `hz`: medios lados).
func confidente(at: Vector3, hx: float, hz: float) -> void:
	var f := Mod.frame(at, 0.0 if hx >= hz else PI * 0.5)
	var len := maxf(hx, hz) * 2.0
	var deep := minf(hx, hz) * 2.0
	var d := "det" + str(_quad_of(at))
	m.box(f, d, Vector3(len, 0.34, deep - 0.08), WHITE, Vector3(0, 0.17, 0), WHITE_SHADE)
	m.box(f, d, Vector3(len + 0.06, 0.07, deep + 0.04), Color(0.2, 0.55, 0.52), Vector3(0, 0.375, 0), Color(0.12, 0.36, 0.36))
	# respaldos encontrados y el tramo que los une
	m.box(f, d, Vector3(len * 0.5, 0.52, 0.09), WHITE, Vector3(-len * 0.25, 0.66, -deep * 0.5 + 0.05), WHITE_SHADE)
	m.box(f, d, Vector3(len * 0.5, 0.52, 0.09), WHITE, Vector3(len * 0.25, 0.66, deep * 0.5 - 0.05), WHITE_SHADE)
	m.box(f, d, Vector3(0.09, 0.52, deep), WHITE, Vector3(0, 0.66, 0), WHITE_SHADE)
	for s: float in [-1.0, 1.0]:
		m.box(f, d, Vector3(0.09, 0.3, deep), WHITE, Vector3(s * (len * 0.5 - 0.045), 0.55, 0), WHITE_SHADE)
		m.gem(f, d, Vector3(0.2, 0.2, 0.2), WHITE, Vector3(s * (len * 0.5 - 0.045), 0.78, s * (deep * 0.5 - 0.06)))


## Farola de hierro: fuste con basa y anillo, y un brazo en cruz con dos globos y otro en lo alto.
func lamp(at: Vector3, h: float, color: Color) -> void:
	var d := "det" + str(_quad_of(at))
	b._cyl(d, 0.22, 0.34, IRON, at, 6, 0.11)
	b._cyl(d, 0.075, h, IRON, at, 6, 0.055)
	b._cyl(d, 0.12, 0.1, IRON, at + Vector3(0, h * 0.42, 0), 6)
	var arm := Vector3(0.62, 0.0, 0.0) if absf(at.z) > absf(at.x) else Vector3(0.0, 0.0, 0.62)
	b._beam(d, at + Vector3(0, h - 0.5, 0) - arm, at + Vector3(0, h - 0.5, 0) + arm, 0.045, IRON)
	for s: float in [-1.0, 1.0]:
		var p := at + Vector3(0, h - 0.66, 0) + arm * s
		b._emit("brillo", "oct", Basis.IDENTITY, Vector3(0.3, 0.38, 0.3), p, color, NONE)
		b._cyl(d, 0.13, 0.07, IRON, p + Vector3(0, 0.17, 0), 5, 0.03)
	b._cyl(d, 0.2, 0.12, IRON, at + Vector3(0, h + 0.32, 0), 6, 0.03)
	b._ball("brillo", 0.2, color, at + Vector3(0, h + 0.16, 0), 1.15, NONE, 6)
