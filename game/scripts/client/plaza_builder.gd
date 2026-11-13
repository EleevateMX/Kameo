extends RefCounted
## Escenario de la plaza de «Mérida, la Ciudad Blanca»: una interpretación fantástica, no una
## reproducción de la plaza real. En el centro, la gran ceiba con su altar; alrededor, fuente,
## quiosco, mercado, puesto de saberes, tablón, confidentes, farolas y banderines; y cerrando la
## plaza, una ciudad compuesta con piezas modulares (plaza_modulos.gd): el palacio de arcos al
## norte, portales comerciales al oeste, casonas de colores al sur y el templo al este, junto al
## portal del Claro. La vegetación, los puestos y el mobiliario están en plaza_vida.gd. La
## geometría que importa para moverse está en zone_def.gd; esto sólo la dibuja. Sin texturas.
##
## Rendimiento: nada se dibuja pieza a pieza. Cada forma se añade a un lote (`_box`, `_cyl`,
## `_ball`, `_quad`, `_arch`…) con su color en los vértices, y al final cada lote es UNA malla
## con UN material:
##   suelo    losas, andadores y mosaicos, y todo lo que no arroja sombra sobre la plaza: el
##            palacio y el templo (les da el sol de frente), azoteas, palmas y casas del fondo
##   obra     lo que arroja sombra: árboles, quiosco, portal, puestos, soportal, casas del sur y del oeste
##   det0–3   lo pequeño, por cuadrantes; de lejos se oculta (rango de visibilidad)
##   brillo   faroles, velas, ventanas encendidas, vitrales, jade: sin sombrear (no hay luces de verdad)
##   luz      luz pintada en el suelo y en los muros, sumada encima
##   cielo    cúpula del atardecer, nubes, estrellas y siluetas lejanas
## Además: agua, portal, banderines, luciérnagas, aves y «ambiente» (humo y pétalos): un
## sombreador cada uno, animado en la tarjeta gráfica, sin trabajo por cuadro; y las palomas (una
## MultiMesh que se mueve a 8 Hz).

const Zone := preload("res://scripts/shared/zone_def.gd")
const Kit := preload("res://scripts/client/ui/ui_kit.gd")
const Mod := preload("res://scripts/client/plaza_modulos.gd")
const Vida := preload("res://scripts/client/plaza_vida.gd")

const WHITE := Color(0.9, 0.87, 0.8)
const WHITE_SHADE := Color(0.66, 0.62, 0.62)
const OCHRE := Color(0.84, 0.6, 0.24)
const STONE := Color(0.38, 0.36, 0.35)
const STONE_DARK := Color(0.28, 0.27, 0.28)
const PAVE_A := Color(0.62, 0.57, 0.5)          # losas de piedra caliza
const PAVE_B := Color(0.57, 0.52, 0.46)
const PATH := Color(0.46, 0.42, 0.39)           # andadores
const TERRACOTTA := Color(0.72, 0.36, 0.24)
const LEAF := Color(0.16, 0.38, 0.2)
const LEAF_LIGHT := Color(0.42, 0.62, 0.26)
const GRASS := Color(0.27, 0.45, 0.24)
const BARK := Color(0.4, 0.29, 0.21)
const WOOD := Color(0.5, 0.33, 0.2)
const WOOD_DARK := Color(0.3, 0.2, 0.14)
const IRON := Color(0.13, 0.15, 0.17)
const JADE := Color(0.18, 0.95, 0.72)
const GOLD := Color(1.0, 0.8, 0.35)
const WARM := Color(1.0, 0.78, 0.42)
const MAGENTA := Color(0.9, 0.16, 0.5)
const TURQUOISE := Color(0.1, 0.7, 0.74)
const FLAGS: Array = [Color(0.9, 0.16, 0.5), Color(1.0, 0.8, 0.2), Color(0.1, 0.7, 0.74), Color(1.0, 0.5, 0.12),
	Color(0.55, 0.8, 0.25), Color(0.56, 0.36, 0.84), Color(0.96, 0.94, 0.88)]
const NONE := Color(0, 0, 0, 0)

## Hacia dónde está el sol (bajo, al suroeste): las sombras caen hacia el noreste, el palacio y
## el templo lo reciben de cara y las fachadas del oeste y del sur quedan a contraluz
const SUN_TO := Vector3(-0.62, 0.5, 0.6)
## Rótulos del mercado (en el orden de zone_def.STALLS) y de tres tiendas de los portales
const STALL_NAMES: Array = ["FRUTAS", "TELAS", "BARRO", "ANTOJITOS"]
const SHOP_NAMES: Array = ["PANADERÍA", "HAMACAS", "BOTICA"]
const DOVE_HOMES: Array = [Vector2(-9.0, 17.0), Vector2(-21.0, 5.0), Vector2(-6.0, 26.0), Vector2(9.0, 22.0), Vector2(-25.0, 21.0)]

class Batch:
	var v := PackedVector3Array()
	var n := PackedVector3Array()
	var c := PackedColorArray()
	var i := PackedInt32Array()
	var uv := PackedVector2Array()
	var uv2 := PackedVector2Array()

var _root: Node3D
var _batches := {}
var _unit := {}
var _sun: DirectionalLight3D
var _details: Array[MeshInstance3D] = []
var _fireflies: MeshInstance3D
var _ambient: MeshInstance3D
var _mod: Mod
var _vida: Vida
var _doves_mm: MultiMesh
var _doves: Array = []
var _dove_home := 0
var _dove_acc := 0.0
var _dove_time := 0.0
var _rng := RandomNumberGenerator.new()
var _stats := {}


func build(root: Node3D, quality := 0) -> void:
	_root = root
	_rng.seed = 20260413
	_mod = Mod.new(self)
	_vida = Vida.new(self, _mod)
	_environment()
	_sky()
	_ground()
	_tree()
	_fountain()
	_kiosk()
	_arcade()
	_benches()
	_lamps()
	_gardens()
	_cart()
	_shop()
	_board()
	_portal()
	_city()
	_market()
	_commit_all()
	_banners()
	_make_fireflies()
	_make_birds()
	_make_doves()
	_make_ambient()
	_labels()
	_batches.clear()
	_unit.clear()
	_mod = null
	_vida = null
	set_quality(quality)


## Calidad de la plaza: 0 alta · 1 baja · 2 mínima (sin sombras).
func set_quality(level: int) -> void:
	_sun.shadow_enabled = level < 2
	_sun.directional_shadow_max_distance = 46.0 if level == 0 else 30.0
	RenderingServer.directional_shadow_atlas_set_size(2048 if level == 0 else 1024, true)
	RenderingServer.directional_soft_shadow_filter_set_quality(
		RenderingServer.SHADOW_QUALITY_SOFT_LOW if level == 0 else RenderingServer.SHADOW_QUALITY_HARD)
	for d in _details:
		d.visibility_range_end = [75.0, 58.0, 46.0][clampi(level, 0, 2)]
	if _fireflies != null:
		_fireflies.visible = level < 2
	if _ambient != null:
		_ambient.visible = level < 2


## Vida ambiental que necesita al procesador: sólo las palomas, y a baja frecuencia (8 Hz en el
## suelo; cada cuadro sólo mientras vuelan). `me`: dónde está el jugador (se espantan si se acerca).
func update(delta: float, me: Vector3) -> void:
	if _doves_mm == null:
		return
	_dove_acc += delta
	var flying := false
	for d in _doves:
		if d.fly:
			flying = true
			break
	if not flying and _dove_acc < 0.125:
		return
	var dt := _dove_acc
	_dove_acc = 0.0
	_dove_time += dt
	var home: Vector2 = DOVE_HOMES[_dove_home]
	if not flying and Vector2(me.x, me.z).distance_to(home) < 3.4:
		# se espantan: toda la bandada vuela al sitio más alejado del jugador
		var best := _dove_home
		var best_d := 0.0
		for h in DOVE_HOMES.size():
			var dist := Vector2(me.x, me.z).distance_to(DOVE_HOMES[h])
			if h != _dove_home and dist > best_d:
				best = h
				best_d = dist
		_dove_home = best
		for d in _doves:
			d.fly = true
			d.k = -_rng.randf() * 0.25
			d.from = d.p
			var a := _rng.randf() * TAU
			var r := 0.4 + _rng.randf() * 1.6
			d.to = Vector3(DOVE_HOMES[best].x + sin(a) * r, 0.0, DOVE_HOMES[best].y + cos(a) * r)
			d.dur = 2.0 + _rng.randf() * 0.9
	for idx in _doves.size():
		var d: Dictionary = _doves[idx]
		var pitch := 0.0
		var roll := 0.0
		if d.fly:
			d.k += dt / float(d.dur)
			var k := clampf(d.k, 0.0, 1.0)
			var e := k * k * (3.0 - 2.0 * k)
			d.p = (d.from as Vector3).lerp(d.to, e) + Vector3(0, sin(k * PI) * 3.4, 0)
			var to: Vector3 = (d.to as Vector3) - (d.from as Vector3)
			d.yaw = atan2(to.x, to.z)
			roll = sin(_dove_time * 30.0 + float(idx)) * 0.6
			pitch = -0.3
			if d.k >= 1.0:
				d.fly = false
				d.p = d.to
				d.wait = 0.5 + _rng.randf() * 2.0
		else:
			var to: Vector3 = (d.to as Vector3) - (d.p as Vector3)
			if to.length() > 0.08:
				d.p = (d.p as Vector3) + to.normalized() * minf(to.length(), 0.7 * dt)
				d.yaw = atan2(to.x, to.z)
				pitch = sin(_dove_time * 14.0 + float(idx)) * 0.12
			else:
				d.wait -= dt
				pitch = 0.55 * maxf(0.0, sin(_dove_time * 5.0 + float(idx) * 1.7))   # picotea
				if d.wait <= 0.0:
					d.wait = 1.0 + _rng.randf() * 3.5
					var a := _rng.randf() * TAU
					var r := 0.4 + _rng.randf() * 1.8
					d.to = Vector3(DOVE_HOMES[_dove_home].x + sin(a) * r, 0.0, DOVE_HOMES[_dove_home].y + cos(a) * r)
		_doves_mm.set_instance_transform(idx, Transform3D(Basis.from_euler(Vector3(pitch, d.yaw, roll)), d.p))


func info() -> Dictionary:
	return _stats


## Sombra de mancha para el alux propio cuando no hay sombras de verdad (calidad mínima).
func make_blob() -> MeshInstance3D:
	var bt := Batch.new()
	_fan(bt, Vector3.ZERO, 0.62, Color(0, 0, 0, 0.42), Color(0, 0, 0, 0.0), 14)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.vertex_color_use_as_albedo = true
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	var mi := MeshInstance3D.new()
	mi.mesh = _mesh_of(bt)
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


# ───────────────────────── Lotes y formas ─────────────────────────

func _batch(name: String) -> Batch:
	if not _batches.has(name):
		_batches[name] = Batch.new()
	return _batches[name]


## Lote de lo pequeño según el cuadrante en que cae.
func _det(pos: Vector3) -> String:
	return "det%d" % ((1 if pos.x >= 0.0 else 0) + (2 if pos.z >= 0.0 else 0))


func _unit_arrays(key: String) -> Array:
	if _unit.has(key):
		return _unit[key]
	if key == "oct":
		_unit[key] = _oct_arrays()
		return _unit[key]
	var mesh: PrimitiveMesh
	var parts := key.split("|")
	match parts[0]:
		"box":
			mesh = BoxMesh.new()
		"cyl":
			var c := CylinderMesh.new()
			c.height = 1.0
			c.bottom_radius = 1.0
			c.top_radius = parts[2].to_float()
			c.radial_segments = parts[1].to_int()
			c.rings = 0
			mesh = c
		_:
			var s := SphereMesh.new()
			s.radius = 0.5
			s.height = 1.0
			s.radial_segments = parts[1].to_int()
			s.rings = maxi(3, parts[1].to_int() / 2)
			mesh = s
	_unit[key] = mesh.get_mesh_arrays()
	return _unit[key]


## Octaedro unitario: la forma más barata con volumen (frutos, flores, remates, farolillos).
func _oct_arrays() -> Array:
	var vs := PackedVector3Array()
	var ns := PackedVector3Array()
	var ix := PackedInt32Array()
	for sx in [-1.0, 1.0]:
		for sy in [-1.0, 1.0]:
			for sz in [-1.0, 1.0]:
				var tri: Array = [Vector3(sx * 0.5, 0, 0), Vector3(0, sy * 0.5, 0), Vector3(0, 0, sz * 0.5)]
				if sx * sy * sz > 0.0:
					tri = [tri[0], tri[2], tri[1]]
				for p in tri:
					ix.append(vs.size())
					vs.append(p)
					ns.append(Vector3(sx, sy, sz).normalized())
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vs
	arrays[Mesh.ARRAY_NORMAL] = ns
	arrays[Mesh.ARRAY_INDEX] = ix
	return arrays


## Añade una forma unitaria (entre −0.5 y 0.5 de alto) al lote, ya colocada. Con dos colores
## hace un degradado de abajo arriba: da volumen sin texturas ni luces.
func _emit(b: String, key: String, basis: Basis, scale: Vector3, pos: Vector3, top: Color, bottom: Color) -> void:
	var bt := _batch(b)
	var arrays := _unit_arrays(key)
	var vs: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var ns: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var ix: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var base := bt.v.size()
	var inv := Vector3(1.0 / scale.x, 1.0 / scale.y, 1.0 / scale.z)
	var grad := bottom.a > 0.0 and bottom != top
	for k in vs.size():
		var p := vs[k]
		bt.v.append(pos + basis * (p * scale))
		bt.n.append((basis * (ns[k] * inv)).normalized())
		bt.c.append(bottom.lerp(top, clampf(p.y + 0.5, 0.0, 1.0)) if grad else top)
	for k in ix:
		bt.i.append(base + k)


## Caja centrada en `pos`.
func _box(b: String, size: Vector3, color: Color, pos: Vector3, yaw := 0.0, bottom := NONE) -> void:
	_emit(b, "box", Basis(Vector3.UP, yaw) if yaw != 0.0 else Basis.IDENTITY, size, pos, color, bottom)


## Cilindro o cono apoyado en `pos` (`top` = radio de arriba; −1 = el mismo que abajo).
func _cyl(b: String, radius: float, height: float, color: Color, pos: Vector3, sides := 8, top := -1.0, bottom := NONE, basis := Basis.IDENTITY) -> void:
	var ratio := 1.0 if top < 0.0 else snappedf(top / radius, 0.01)
	_emit(b, "cyl|%d|%s" % [sides, ratio], basis, Vector3(radius, height, radius), pos + basis * Vector3(0, height * 0.5, 0), color, bottom)


## Bola (o copa de árbol, achatada) centrada en `pos`.
func _ball(b: String, radius: float, color: Color, pos: Vector3, squash := 1.0, bottom := NONE, sides := 8) -> void:
	_emit(b, "ball|%d" % sides, Basis.IDENTITY, Vector3(radius * 2.0, radius * 2.0 * squash, radius * 2.0), pos, color, bottom)


## Viga entre dos puntos (cuerdas, arcos, toldos).
func _beam(b: String, from: Vector3, to: Vector3, thick: float, color: Color, width := -1.0) -> void:
	var d := to - from
	var len := d.length()
	if len < 0.001:
		return
	var z := d / len
	var x := Vector3.UP.cross(z)
	x = Vector3.RIGHT if x.length() < 0.001 else x.normalized()
	_emit(b, "box", Basis(x, z.cross(x), z), Vector3(thick if width < 0.0 else width, thick, len), (from + to) * 0.5, color, NONE)


## Losa plana (mira hacia arriba) entre dos esquinas.
func _tile(b: String, x0: float, z0: float, x1: float, z1: float, y: float, color: Color) -> void:
	var bt := _batch(b)
	var base := bt.v.size()
	for p in [Vector3(x0, y, z0), Vector3(x1, y, z0), Vector3(x1, y, z1), Vector3(x0, y, z1)]:
		bt.v.append(p)
		bt.n.append(Vector3.UP)
		bt.c.append(color)
	for k in [0, 1, 2, 0, 2, 3]:
		bt.i.append(base + k)


## Corona plana (o disco, con r_in = 0) que mira hacia arriba.
func _ring(b: String, center: Vector3, r_in: float, r_out: float, color: Color, sides := 32, outer := NONE) -> void:
	var bt := _batch(b)
	var out_c := color if outer.a <= 0.0 and outer == NONE else outer
	if r_in <= 0.0:
		_fan(bt, center, r_out, color, out_c, sides)
		return
	var base := bt.v.size()
	for k in sides:
		var a := TAU * float(k) / float(sides)
		var dir := Vector3(sin(a), 0.0, cos(a))
		bt.v.append(center + dir * r_in)
		bt.v.append(center + dir * r_out)
		bt.n.append(Vector3.UP)
		bt.n.append(Vector3.UP)
		bt.c.append(color)
		bt.c.append(out_c)
	for k in sides:
		var a0 := base + k * 2
		var a1 := base + ((k + 1) % sides) * 2
		for q in [a0, a1 + 1, a0 + 1, a0, a1, a1 + 1]:
			bt.i.append(q)


func _fan(bt: Batch, center: Vector3, radius: float, color: Color, edge: Color, sides: int) -> void:
	var base := bt.v.size()
	bt.v.append(center)
	bt.n.append(Vector3.UP)
	bt.c.append(color)
	for k in sides:
		var a := TAU * float(k) / float(sides)
		bt.v.append(center + Vector3(sin(a), 0.0, cos(a)) * radius)
		bt.n.append(Vector3.UP)
		bt.c.append(edge)
	for k in sides:
		bt.i.append(base)
		bt.i.append(base + 1 + (k + 1) % sides)
		bt.i.append(base + 1 + k)


## Charco de luz pintado en el suelo (se suma: no es una luz de verdad).
func _pool(pos: Vector3, radius: float, color: Color, strength := 0.3) -> void:
	_fan(_batch("luz"), Vector3(pos.x, 0.035, pos.z), radius, Color(color.r * strength, color.g * strength, color.b * strength), Color(0, 0, 0), 16)


## Farolillo colgado: cuerda, capuchón y luz.
func _lantern(pos: Vector3, hang := 0.5, color := WARM, radius := 0.16) -> void:
	if hang > 0.0:
		_box(_det(pos), Vector3(0.025, hang, 0.025), IRON, pos + Vector3(0, radius + hang * 0.5, 0))
	_cyl(_det(pos), radius * 0.9, radius * 0.5, IRON, pos + Vector3(0, radius * 0.7, 0), 6, 0.02)
	_ball("brillo", radius, color, pos, 1.15, NONE, 6)


## Cuadrilátero suelto (dos triángulos) con su normal: p0 y p1 llevan `color`; p2 y p3, `low`
## (si se da). El frente es la cara desde la que p0→p1→p2 gira como el reloj. `both`: dos caras.
func _quad(b: String, p0: Vector3, p1: Vector3, p2: Vector3, p3: Vector3, color: Color, low := NONE, both := false) -> void:
	var bt := _batch(b)
	var n := (p2 - p0).cross(p1 - p0).normalized()
	var c2 := color if low.a <= 0.0 else low
	for side in (2 if both else 1):
		var base := bt.v.size()
		for p in [p0, p1, p2, p3]:
			bt.v.append(p)
			bt.n.append(n if side == 0 else -n)
		bt.c.append(color)
		bt.c.append(color)
		bt.c.append(c2)
		bt.c.append(c2)
		for k in ([0, 1, 2, 0, 2, 3] if side == 0 else [0, 2, 1, 0, 3, 2]):
			bt.i.append(base + k)


## Disco o sector plano en el plano de los ejes `ax` y `ay` (mira hacia ax × ay), con el centro
## de un color y el borde de otro.
func _disc(b: String, center: Vector3, ax: Vector3, ay: Vector3, radius: float, color: Color, edge: Color, sides := 12, a0 := 0.0, a1 := TAU) -> void:
	var bt := _batch(b)
	var n := ax.cross(ay).normalized()
	var base := bt.v.size()
	bt.v.append(center)
	bt.n.append(n)
	bt.c.append(color)
	for k in sides + 1:
		var a := lerpf(a0, a1, float(k) / float(sides))
		bt.v.append(center + (ax * cos(a) + ay * sin(a)) * radius)
		bt.n.append(n)
		bt.c.append(edge)
	for k in sides:
		bt.i.append(base)
		bt.i.append(base + 2 + k)
		bt.i.append(base + 1 + k)


## Tronco o rama: cilindro (o cono truncado) de un punto a otro.
func _limb(b: String, from: Vector3, to: Vector3, r0: float, r1: float, color: Color, sides := 6, bottom := NONE) -> void:
	var d := to - from
	var len := d.length()
	if len < 0.001:
		return
	var y := d / len
	var x := y.cross(Vector3.FORWARD)
	x = Vector3.RIGHT if x.length() < 0.001 else x.normalized()
	_cyl(b, r0, len, color, from, sides, r1, bottom, Basis(x, y, x.cross(y)))


## Paño con un vano en arco, en el marco `f` (x a lo ancho, y arriba, z hacia quien mira). El paño
## va de x0 a x1 y de y0 a y1, con `thick` de grueso centrado en z = 0. El vano, centrado, mide
## `open` de ancho: sus jambas suben `spring` y encima va el arco, de `rise` de alto.
## shape: 0 arco (de medio punto o rebajado, según `rise`) · 1 falso arco, en trapecio.
## `back`: también la cara de atrás (si la cámara puede pasar al otro lado).
func _arch(b: String, f: Transform3D, x0: float, x1: float, y0: float, y1: float, thick: float, open: float, spring: float, rise: float, color: Color, shade: Color, shape := 0, back := false, segs := 8) -> void:
	var cx := (x0 + x1) * 0.5
	var a := open * 0.5
	var pts: Array[Vector2] = [Vector2(cx - a, y0)]
	if shape == 1:
		for q in [[-1.0, 0.0], [-0.44, 1.0], [0.44, 1.0], [1.0, 0.0]]:
			pts.append(Vector2(cx + a * float(q[0]), y0 + spring + rise * float(q[1])))
	else:
		for k in segs + 1:
			var t := PI * float(k) / float(segs)
			pts.append(Vector2(cx - cos(t) * a, y0 + spring + sin(t) * rise))
	pts.append(Vector2(cx + a, y0))
	var zf := thick * 0.5
	var last := pts.size() - 1
	for side in ([1.0, -1.0] if back else [1.0]):
		var z: float = zf * side
		# machones a los lados del vano y enjutas sobre el arco
		var strips: Array = [[x0, pts[0].x, y0, y0], [pts[last].x, x1, y0, y0]]
		for k in range(1, last - 1):
			strips.append([pts[k].x, pts[k + 1].x, pts[k].y, pts[k + 1].y])
		for st in strips:
			var xa: float = st[0]
			var xb: float = st[1]
			if xb - xa < 0.001:
				continue
			var low := shade.lerp(color, clampf(((float(st[2]) + float(st[3])) * 0.5 - y0) / maxf(0.01, y1 - y0), 0.0, 1.0))
			if side > 0.0:
				_quad(b, f * Vector3(xa, y1, z), f * Vector3(xb, y1, z), f * Vector3(xb, st[3], z), f * Vector3(xa, st[2], z), color, low)
			else:
				_quad(b, f * Vector3(xb, y1, z), f * Vector3(xa, y1, z), f * Vector3(xa, st[2], z), f * Vector3(xb, st[3], z), color, low)
	# intradós: la cara de dentro del vano, siempre mirando a su centro
	var center := f * Vector3(cx, y0 + spring * 0.5, 0.0)
	for k in last:
		var p := pts[k]
		var q := pts[k + 1]
		var c0 := f * Vector3(p.x, p.y, zf)
		var c1 := f * Vector3(q.x, q.y, zf)
		var c2 := f * Vector3(q.x, q.y, -zf)
		var c3 := f * Vector3(p.x, p.y, -zf)
		if (c2 - c0).cross(c1 - c0).dot(center - c0) < 0.0:
			_quad(b, c1, c0, c3, c2, shade, shade.darkened(0.15))
		else:
			_quad(b, c0, c1, c2, c3, shade, shade.darkened(0.15))


func _mesh_of(bt: Batch) -> ArrayMesh:
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = bt.v
	if bt.n.size() == bt.v.size():
		arr[Mesh.ARRAY_NORMAL] = bt.n
	arr[Mesh.ARRAY_COLOR] = bt.c
	if bt.uv.size() == bt.v.size():
		arr[Mesh.ARRAY_TEX_UV] = bt.uv
	if bt.uv2.size() == bt.v.size():
		arr[Mesh.ARRAY_TEX_UV2] = bt.uv2
	arr[Mesh.ARRAY_INDEX] = bt.i
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return mesh


func _commit(name: String, mat: Material, shadow: bool) -> MeshInstance3D:
	if not _batches.has(name):
		return null
	var bt: Batch = _batches[name]
	var mi := MeshInstance3D.new()
	mi.name = name
	mi.mesh = _mesh_of(bt)
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadow else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_root.add_child(mi)
	_stats[name] = bt.i.size() / 3
	return mi


func _commit_all() -> void:
	# Un solo material sombreado para todo: el color va en los vértices
	var solid := StandardMaterial3D.new()
	solid.vertex_color_use_as_albedo = true
	solid.vertex_color_is_srgb = true
	solid.roughness = 1.0
	solid.metallic_specular = 0.0
	solid.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	var glow := StandardMaterial3D.new()
	glow.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	glow.vertex_color_use_as_albedo = true
	glow.vertex_color_is_srgb = true
	var add := StandardMaterial3D.new()
	add.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	add.vertex_color_use_as_albedo = true
	add.vertex_color_is_srgb = true
	add.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	add.disable_fog = true
	var sky := StandardMaterial3D.new()
	sky.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	sky.vertex_color_use_as_albedo = true
	sky.vertex_color_is_srgb = true
	sky.cull_mode = BaseMaterial3D.CULL_DISABLED
	sky.disable_fog = true
	_commit("cielo", sky, false)
	_commit("suelo", solid, false)
	_commit("obra", solid, true)
	for q in 4:
		var d := _commit("det%d" % q, solid, false)
		if d != null:
			_details.append(d)
	_commit("brillo", glow, false)
	_commit("luz", add, false)


# ───────────────────────── Ambiente ─────────────────────────

func _environment() -> void:
	# Atardecer dorado: sol bajo del suroeste, cálido y con fuerza, y un ambiente violáceo que
	# rellena la sombra. Lo que mira al sol (el palacio, el templo) arde y lo que le da la espalda
	# (portales del oeste, casonas del sur) se enfría y vive de sus faroles: el contraste entre
	# zonas lo pone la dirección de la luz, no más luces. El cielo es una cúpula pintada (lote
	# «cielo»): el fondo del motor es un color liso, sin pase de cielo.
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.36, 0.27, 0.42)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.5, 0.5, 0.72)
	env.ambient_light_energy = 0.7
	env.fog_enabled = true
	env.fog_light_color = Color(0.74, 0.5, 0.44)
	env.fog_density = 0.0022
	env.fog_sun_scatter = 0.2
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 0.88
	env.tonemap_white = 4.2
	var we := WorldEnvironment.new()
	we.environment = env
	_root.add_child(we)
	_sun = DirectionalLight3D.new()
	_sun.basis = Basis.looking_at(-SUN_TO.normalized(), Vector3.UP)
	_sun.light_color = Color(1.0, 0.8, 0.55)
	_sun.light_energy = 1.2
	_sun.shadow_enabled = true
	# Una sola sombra direccional, barata: un único mapa y poca distancia
	_sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	_sun.directional_shadow_max_distance = 46.0
	_sun.shadow_bias = 0.06
	_sun.shadow_normal_bias = 1.4
	_root.add_child(_sun)


func _sky() -> void:
	var bt := _batch("cielo")
	var radius := 190.0
	var sun_az := Vector2(SUN_TO.x, SUN_TO.z).normalized()
	var top := Color(0.1, 0.15, 0.4)
	var mid := Color(0.5, 0.34, 0.58)
	var low := Color(1.0, 0.6, 0.34)
	var haze := Color(0.56, 0.38, 0.42)
	var rows := 9
	var cols := 24
	for r in rows + 1:
		var e := -0.12 + 1.12 * float(r) / float(rows)     # seno de la altura
		var y := sin(e * PI * 0.5)
		var flat := cos(e * PI * 0.5)
		for c in cols:
			var a := TAU * float(c) / float(cols)
			var dir := Vector2(sin(a), cos(a))
			var toward := clampf(dir.dot(sun_az) * 0.5 + 0.5, 0.0, 1.0)
			var col := haze.lerp(low, smoothstep(-0.12, 0.02, e))
			col = col.lerp(mid, smoothstep(0.03, 0.36, e) * (1.0 - toward * 0.35))
			col = col.lerp(top, smoothstep(0.3, 0.85, e))
			# hacia el sol el horizonte arde; al otro lado ya es de noche
			var burn := pow(toward, 2.5) * (1.0 - smoothstep(0.0, 0.5, absf(e)))
			col = col.lerp(Color(1.0, 0.84, 0.5), burn * 0.9)
			col = col.lerp(Color(0.2, 0.2, 0.44), (1.0 - toward) * 0.3 * smoothstep(0.0, 0.5, e))
			bt.v.append(Vector3(dir.x * flat, y, dir.y * flat) * radius)
			bt.c.append(col)
	for r in rows:
		for c in cols:
			var a0 := r * cols + c
			var a1 := r * cols + (c + 1) % cols
			for q in [a0, a1, a1 + cols, a0, a1 + cols, a0 + cols]:
				bt.i.append(q)
	# Sol con su halo, nubes y siluetas: mismo lote (sin sombrear, sin niebla)
	var sun_dir := SUN_TO.normalized()
	_sky_blob(sun_dir * 181.0 + Vector3(0, -30.0, 0), Vector3(44, 30, 44), Color(1.0, 0.8, 0.46), Color(1.0, 0.7, 0.4))
	_sky_blob(sun_dir * 178.0 + Vector3(0, -30.0, 0), Vector3(17, 17, 17), Color(1.0, 0.95, 0.74), Color(1.0, 0.9, 0.62))
	# Nubes largas: lomo malva y panza encendida por el sol que se va
	for k in 15:
		var a := _rng.randf() * TAU
		var h := 26.0 + _rng.randf() * 60.0
		var w := 30.0 + _rng.randf() * 44.0
		var near_sun := clampf(Vector2(sin(a), cos(a)).dot(sun_az) * 0.5 + 0.5, 0.0, 1.0)
		var back := Color(0.46, 0.33, 0.52).lerp(Color(0.86, 0.5, 0.46), near_sun)
		var belly := Color(0.74, 0.44, 0.5).lerp(Color(1.0, 0.72, 0.42), near_sun)
		_sky_blob(Vector3(sin(a) * 165.0, h, cos(a) * 165.0), Vector3(w, 2.6 + _rng.randf() * 3.4, w * 0.45), back, belly, a)
	# Primeras estrellas, en lo alto y lejos del sol
	for k in 46:
		var a := _rng.randf() * TAU
		var e := 0.42 + _rng.randf() * 0.56
		var dir := Vector3(sin(a) * cos(e * PI * 0.5), sin(e * PI * 0.5), cos(a) * cos(e * PI * 0.5))
		if Vector2(dir.x, dir.z).dot(sun_az) > 0.55 and e < 0.7:
			continue
		var s := 0.5 + _rng.randf() * 0.7
		_emit("cielo", "oct", Basis.IDENTITY, Vector3(s, s, s), dir * 184.0, Color(1.0, 0.95, 0.8).darkened(_rng.randf() * 0.3), NONE)
	# Lomas y torres lejanas, a contraluz
	for k in 20:
		var a := TAU * float(k) / 20.0 + _rng.randf() * 0.2
		var d := 120.0 + _rng.randf() * 30.0
		var col := Color(0.2, 0.17, 0.3).lerp(Color(0.34, 0.24, 0.34), _rng.randf())
		_sky_blob(Vector3(sin(a) * d, -2.0, cos(a) * d), Vector3(46.0 + _rng.randf() * 30.0, 10.0 + _rng.randf() * 12.0, 30.0), col, col.darkened(0.25), a)
	for t in [[-52.0, -92.0, 24.0], [46.0, -96.0, 21.0], [-78.0, -70.0, 17.0], [80.0, -66.0, 18.0], [-90.0, 30.0, 16.0], [-84.0, -20.0, 19.0], [30.0, 96.0, 17.0]]:
		var col := Color(0.26, 0.2, 0.32)
		_box("cielo", Vector3(6.0, float(t[2]), 6.0), col, Vector3(t[0], float(t[2]) * 0.5, t[1]))
		_cyl("cielo", 4.4, 5.0, col.darkened(0.15), Vector3(t[0], t[2], t[1]), 4, 0.3)
		var to_plaza := Vector3(-float(t[0]), 0.0, -float(t[1])).normalized()
		_box("cielo", Vector3(1.4, 2.0, 1.4), Color(1.0, 0.76, 0.4), Vector3(t[0], float(t[2]) - 4.0, t[1]) + to_plaza * 2.6)


func _sky_blob(pos: Vector3, size: Vector3, color: Color, under: Color, yaw := 0.0) -> void:
	_emit("cielo", "ball|8", Basis(Vector3.UP, yaw), size, pos, color, under)


# ───────────────────────── Suelo ─────────────────────────

func _ground() -> void:
	var half := Zone.HALF
	_tile("suelo", -150.0, -150.0, 150.0, 150.0, -0.08, Color(0.2, 0.27, 0.2))                           # campo alrededor
	_tile("suelo", -half - 13.0, -half - 13.0, half + 13.0, half + 13.0, -0.04, Color(0.3, 0.27, 0.29))  # calles
	# Banqueta al pie de las fachadas del oeste, del sur y del templo
	var walk := PAVE_B.darkened(0.2)
	_tile("suelo", -half - 1.0, -29.0, -half, half + 1.0, -0.004, walk)
	_tile("suelo", -half, half, half + 1.0, half + 1.0, -0.004, walk)
	_tile("suelo", half, 11.0, half + 1.0, half, -0.004, walk)
	# Losas de 2 m, cada una con su tono: andadores en cruz, cenefa, jardineras, mercado y atrio
	# salen del color. El sombreado va pintado en los vértices (ver _floor_tint).
	var bt := _batch("suelo")
	var n := int(half)
	for ix in n:
		for iz in n:
			var x0 := -half + 2.0 * float(ix)
			var z0 := -half + 2.0 * float(iz)
			var cx := x0 + 1.0
			var cz := z0 + 1.0
			var jitter := fposmod(sin(float(ix) * 12.9898 + float(iz) * 78.233) * 43758.5453, 1.0)
			var col := PAVE_A if (ix + iz) % 2 == 0 else PAVE_B
			if ix == 0 or iz == 0 or ix == n - 1 or iz == n - 1:
				col = TERRACOTTA.darkened(0.12)
			elif absf(cx) > 16.0 and absf(cx) < 24.0 and absf(cz) > 20.0 and absf(cz) < 26.0:
				col = GRASS.lerp(LEAF_LIGHT, jitter * 0.35)
			elif absf(cz) < 2.0 and cx > 7.0:
				col = Color(0.3, 0.38, 0.36)           # el camino al portal: piedra antigua, verdosa
			elif absf(cx) < 2.0 or absf(cz) < 2.0:
				col = PATH
			elif ix == 1 or iz == 1 or ix == n - 2 or iz == n - 2:
				col = Color(0.52, 0.42, 0.35)
			elif cx > 24.0 and cz > 12.0:
				col = Color(0.7, 0.66, 0.58) if (ix + iz) % 2 == 0 else Color(0.58, 0.36, 0.28)   # atrio del templo
			elif cx < -3.0 and cx > -30.0 and cz < -5.0 and cz > -21.0:
				col = Color(0.6, 0.5, 0.4).lerp(Color(0.5, 0.42, 0.36), jitter)                  # el mercado: canto rodado
			col = col.lightened(jitter * 0.07 - 0.02)
			var base := bt.v.size()
			for corner in [Vector2(x0, z0), Vector2(x0 + 2.0, z0), Vector2(x0 + 2.0, z0 + 2.0), Vector2(x0, z0 + 2.0)]:
				bt.v.append(Vector3(corner.x, 0.0, corner.y))
				bt.n.append(Vector3.UP)
				bt.c.append(_floor_tint(col, corner.x, corner.y))
			for k in [0, 1, 2, 0, 2, 3]:
				bt.i.append(base + k)
	# Olambrillas: rombos de barro en los cruces de las losas, salvo donde hay otro dibujo
	for ix in range(2, n - 1, 2):
		for iz in range(2, n - 1, 2):
			var p := Vector3(-half + 2.0 * float(ix), 0.012, -half + 2.0 * float(iz))
			if absf(p.x) < 3.0 or absf(p.z) < 3.0 or Vector2(p.x, p.z).length() < 8.5 or Vector2(p.x, p.z - Zone.SPAWN_CENTER.y).length() < 7.0:
				continue
			if absf(p.x) > 15.0 and absf(p.x) < 25.0 and absf(p.z) > 19.0 and absf(p.z) < 27.0:
				continue
			if p.x > 23.0 and p.z > 11.0:
				continue
			_ring("suelo", p, 0.0, 0.34, _floor_tint(TERRACOTTA.darkened(0.05), p.x, p.z), 4)
	# Anillo alrededor del árbol
	_ring("suelo", Vector3(0, 0.014, 0), 5.3, 7.3, PATH.lightened(0.05), 40)
	_ring("suelo", Vector3(0, 0.014, 0), 5.1, 5.3, OCHRE.darkened(0.25), 40)
	_ring("suelo", Vector3(0, 0.014, 0), 2.6, 5.1, PAVE_A.darkened(0.14), 40)
	_ring("suelo", Vector3(0, 0.016, 0), 7.3, 7.5, TERRACOTTA.darkened(0.1), 40)
	# El corro de llegada: un mosaico al sur del árbol, con el guía en el centro
	var c := Vector3(Zone.SPAWN_CENTER.x, 0.016, Zone.SPAWN_CENTER.y)
	_ring("suelo", c, 0.0, 1.1, OCHRE.darkened(0.1), 20)
	_ring("suelo", c, 1.1, 1.25, Color(0.92, 0.82, 0.55), 28)
	_ring("suelo", c, 1.25, 2.9, Color(0.2, 0.42, 0.38), 28)
	_ring("suelo", c, 2.9, 3.05, Color(0.92, 0.82, 0.55), 36)
	_ring("suelo", c, 3.05, 3.5, STONE_DARK, 36)
	_ring("suelo", c, Zone.SPAWN_RADIUS - 0.08, Zone.SPAWN_RADIUS + 0.08, OCHRE.darkened(0.2), 48)
	for k in 8:
		var a := TAU * float(k) / 8.0
		_ring("suelo", c + Vector3(sin(a) * 2.08, 0.004, cos(a) * 2.08), 0.0, 0.3, Color(0.92, 0.82, 0.55), 4)
	_ring("brillo", c + Vector3(0, 0.008, 0), 0.95, 1.06, GOLD.darkened(0.1), 24)   # aquí hay alguien con quien hablar
	# Luces de jade en el suelo: el camino del este lleva al portal
	var x := 8.5
	while x < 27.5:
		_ring("brillo", Vector3(x, 0.02, 0.0), 0.0, 0.3, JADE, 4)
		_pool(Vector3(x, 0, 0), 1.6, JADE, 0.2)
		x += 2.5
	# Dónde ponerse para usar el puesto y el tablón
	for p in Zone.POIS:
		if p.id != "guide":
			_ring("suelo", Vector3(p.at.x, 0.015, p.at.y), 0.0, 1.5, Color(0.2, 0.42, 0.38), 20)
			_ring("suelo", Vector3(p.at.x, 0.017, p.at.y), 1.5, 1.66, Color(0.92, 0.82, 0.55), 20)
			_ring("brillo", Vector3(p.at.x, 0.02, p.at.y), 0.62, 0.72, GOLD.darkened(0.15), 20)


## Sombreado pintado del suelo: más oscuro y frío al pie de las fachadas que dan la espalda al sol
## (oeste y sur), junto al palacio y bajo la ceiba. Es lo único que da volumen al suelo en calidad
## mínima, que no tiene sombras; con sombras de verdad apenas se suma.
func _floor_tint(col: Color, x: float, z: float) -> Color:
	var half := Zone.HALF
	var k := 0.34 * smoothstep(8.0, 0.0, x + half)
	k = maxf(k, 0.34 * smoothstep(8.0, 0.0, half - z))
	k = maxf(k, 0.14 * smoothstep(4.0, 0.0, z + 29.0))
	k = maxf(k, 0.18 * smoothstep(8.0, 2.5, Vector2(x, z).length()))
	return col.lerp(Color(col.r * 0.5, col.g * 0.52, col.b * 0.74), k)


# ───────────────────────── Centro: el gran árbol y su altar ─────────────────────────

func _tree() -> void:
	_cyl("obra", 2.6, 0.55, WHITE, Vector3.ZERO, 16, -1.0, WHITE_SHADE)
	_cyl("obra", 2.3, 0.6, Color(0.26, 0.2, 0.15), Vector3.ZERO, 16)
	_cyl("obra", 1.05, 6.4, BARK.lightened(0.08), Vector3.ZERO, 9, 0.62, BARK.darkened(0.35))
	for k in 6:
		var a := TAU * float(k) / 6.0 + 0.3
		_cyl("obra", 0.6, 2.4, BARK, Vector3(sin(a) * 0.95, 0.4, cos(a) * 0.95), 5, 0.1, BARK.darkened(0.3))
	_vida.ceiba(Vector3.ZERO)
	# Farolillos colgados de la copa
	for k in 7:
		var a := TAU * float(k) / 7.0 + 0.5
		var r := 3.3 + 1.1 * float(k % 2)
		_lantern(Vector3(sin(a) * r, 3.7 + 0.5 * float(k % 3), cos(a) * r), 1.6, WARM if k % 3 != 0 else Color(1.0, 0.55, 0.4))
	_pool(Vector3.ZERO, 8.5, WARM, 0.17)
	# Altar a los pies del árbol, mirando al corro de llegada (va sobre el arriate: no estorba)
	_box("obra", Vector3(2.2, 0.5, 0.8), STONE.lightened(0.1), Vector3(0, 0.8, 2.05), 0.0, STONE_DARK)
	_box("obra", Vector3(1.5, 0.45, 0.55), STONE.lightened(0.16), Vector3(0, 1.27, 1.9))
	_box("obra", Vector3(0.7, 0.8, 0.22), STONE_DARK, Vector3(0, 1.9, 1.74))
	_box("brillo", Vector3(0.3, 0.3, 0.04), JADE, Vector3(0, 1.95, 1.86), PI * 0.25)
	for k in 7:
		var cx := -0.95 + 0.32 * float(k)
		var h := 0.16 + 0.1 * float((k * 3) % 4)
		var step := 1.05 if absf(cx) > 0.7 else 1.5
		var cz := 2.25 if absf(cx) > 0.7 else 2.05
		_cyl(_det(Vector3(cx, 0, cz)), 0.045, h, Color(0.95, 0.92, 0.8), Vector3(cx, step, cz), 5)
		_cyl("brillo", 0.045, 0.11, Color(1.0, 0.85, 0.45), Vector3(cx, step + h, cz), 4, 0.0)
	for k in 9:
		var a := -1.2 + 2.4 * float(k) / 8.0
		_emit(_det(Vector3(sin(a), 0, 2.4)), "oct", Basis.IDENTITY, Vector3(0.28, 0.24, 0.28), Vector3(sin(a) * 1.9, 0.68, cos(a) * 2.35), [Color(1.0, 0.6, 0.1), MAGENTA, Color(1.0, 0.82, 0.2)][k % 3], NONE)
	_pool(Vector3(0, 0, 3.4), 3.0, Color(1.0, 0.7, 0.35), 0.3)


func _fountain() -> void:
	var at := Vector3(-15.0, 0.0, 12.0)
	_cyl("obra", 2.5, 0.6, WHITE, at, 16, -1.0, WHITE_SHADE)
	_cyl("obra", 2.75, 0.14, WHITE_SHADE, at, 16)
	_cyl("obra", 0.42, 1.5, WHITE_SHADE, at, 8, 0.3)
	_cyl("obra", 0.3, 0.2, WHITE, at + Vector3(0, 1.5, 0), 10, 1.05)
	_cyl("obra", 1.05, 0.2, WHITE, at + Vector3(0, 1.55, 0), 10, -1.0, WHITE_SHADE)
	_ball("brillo", 0.24, JADE, at + Vector3(0, 2.05, 0), 1.0, NONE, 6)
	_ring("suelo", at + Vector3(0, 0.013, 0), 2.75, 3.9, PATH.lightened(0.06), 16)
	_ring("suelo", at + Vector3(0, 0.014, 0), 3.9, 4.1, TERRACOTTA.darkened(0.1), 16)
	for k in 4:
		var ja := PI * 0.5 * float(k) + PI * 0.25
		_cyl("brillo", 0.05, 0.5, Color(0.6, 0.95, 0.95), at + Vector3(sin(ja) * 1.5, 0.5, cos(ja) * 1.5), 4, 0.0)
	_ring("brillo", at + Vector3(0, 1.76, 0), 0.0, 0.92, Color(0.35, 0.85, 0.9), 12)
	_pool(at, 5.0, Color(0.3, 0.9, 0.95), 0.2)
	# El agua, con ondas que hace el sombreador
	var disc := CylinderMesh.new()
	disc.top_radius = 2.2
	disc.bottom_radius = 2.2
	disc.height = 0.02
	disc.radial_segments = 20
	disc.rings = 0
	var sh := Shader.new()
	sh.code = """shader_type spatial;
render_mode unshaded, cull_back, shadows_disabled;
varying vec2 lp;
void vertex() {
	lp = VERTEX.xz;
}
void fragment() {
	float d = length(lp) / 2.2;
	float w = sin(d * 26.0 - TIME * 2.6) * 0.5 + 0.5;
	vec3 deep = vec3(0.03, 0.22, 0.3);
	vec3 lit = vec3(0.2, 0.75, 0.8);
	ALBEDO = mix(deep, lit, w * w * 0.55 + 0.12);
	ALPHA = 0.86;
}
"""
	var mat := ShaderMaterial.new()
	mat.shader = sh
	var water := MeshInstance3D.new()
	water.name = "agua"
	water.mesh = disc
	water.material_override = mat
	water.position = at + Vector3(0, 0.5, 0)
	water.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	water.visibility_range_end = 60.0
	_root.add_child(water)


func _kiosk() -> void:
	var at := Vector3(15.0, 0.0, -13.0)
	_ring("suelo", at + Vector3(0, 0.013, 0), 3.15, 4.3, PATH.lightened(0.06), 8)
	_ring("suelo", at + Vector3(0, 0.014, 0), 4.3, 4.5, TERRACOTTA.darkened(0.1), 8)
	_cyl("obra", 3.15, 0.22, WHITE_SHADE, at, 8)
	_cyl("obra", 2.9, 0.5, WHITE, at, 8, -1.0, WHITE_SHADE)
	_ring("suelo", at + Vector3(0, 0.51, 0), 0.0, 2.7, Color(0.62, 0.36, 0.27), 8)
	for i in 8:
		var a := TAU * float(i) / 8.0 + TAU / 16.0
		var p := at + Vector3(sin(a) * 2.5, 0.5, cos(a) * 2.5)
		_cyl(_det(p), 0.09, 2.6, IRON, p, 6)
		_cyl(_det(p), 0.15, 0.2, IRON, p, 6, 0.09)
		var a2 := TAU * float(i + 1) / 8.0 + TAU / 16.0
		var p2 := at + Vector3(sin(a2) * 2.5, 0.5, cos(a2) * 2.5)
		if i != 5:   # un hueco para subir
			_beam(_det(p), p + Vector3(0, 0.8, 0), p2 + Vector3(0, 0.8, 0), 0.05, IRON)
			_beam(_det(p), p + Vector3(0, 0.4, 0), p2 + Vector3(0, 0.4, 0), 0.04, IRON)
		# cenefa de hierro bajo el alero y un farolillo en cada esquina
		_beam(_det(p), p + Vector3(0, 2.36, 0), p2 + Vector3(0, 2.36, 0), 0.03, IRON, 0.02)
		_emit("brillo", "oct", Basis.IDENTITY, Vector3(0.2, 0.3, 0.2), at + Vector3(sin(a) * 3.2, 2.8, cos(a) * 3.2), WARM, NONE)
	_cyl("obra", 3.5, 0.14, WHITE, at + Vector3(0, 3.05, 0), 8)
	_cyl("obra", 3.4, 1.0, TERRACOTTA.lightened(0.08), at + Vector3(0, 3.19, 0), 8, 1.3, TERRACOTTA.darkened(0.2))
	_cyl("obra", 1.3, 0.5, WHITE, at + Vector3(0, 4.19, 0), 8, -1.0, WHITE_SHADE)
	_cyl("obra", 1.6, 0.9, TERRACOTTA.lightened(0.08), at + Vector3(0, 4.69, 0), 8, 0.08, TERRACOTTA.darkened(0.2))
	_emit("brillo", "oct", Basis.IDENTITY, Vector3(0.36, 0.6, 0.36), at + Vector3(0, 5.9, 0), GOLD, NONE)
	for k in 4:
		var a := PI * 0.5 * float(k) + PI * 0.25
		_box("brillo", Vector3(0.5, 0.26, 0.04), Color(1.0, 0.8, 0.5), at + Vector3(sin(a) * 1.22, 4.44, cos(a) * 1.22), a)
	_lantern(at + Vector3(0, 2.45, 0), 0.55, WARM, 0.22)
	_pool(at, 5.2, WARM, 0.28)


# ───────────────────────── Norte: el edificio de los arcos ─────────────────────────

func _arcade() -> void:
	# El palacio: soportal de arcos rebajados en la planta baja (sus columnas son obstáculos:
	# zone_def.ARCADE), terraza con balaustrada encima, planta alta de color con una puerta-ventana
	# por arco, azotea con pináculos y la torre del reloj. El muro es el mismo de siempre (z = −29).
	var half := Zone.HALF
	var m := _mod
	var f := Mod.frame(Vector3(-half, 0.0, -29.0), 0.0)   # x de oeste a este, desde la esquina
	var w := half * 2.0
	var top0 := 4.95
	var top1 := 8.7
	var upper := Color(0.93, 0.68, 0.54)
	# (el cuerpo va en «suelo»: el sol le da de frente y su sombra cae fuera de la plaza)
	m.wall(f, -9.0, w, 0.0, top0, 5.0, WHITE, "suelo", 0.2)
	m.wall(f, -9.0, w, top0, top1, 5.0, upper, "suelo", 0.12)
	m.plinth(f, 0.0, w, OCHRE, 0.9, "suelo")
	m.cornice(f, -1.0, w, top1, WHITE, 0.34, 0.36, "suelo")
	m.parapet(f, -1.0, w, top1 + 0.34, 1, WHITE, 6.0, "suelo")
	m.quad(f, "suelo", Vector3(-9.0, top1 + 0.36, -5.0), Vector3(w, top1 + 0.36, -5.0), Vector3(w, top1 + 0.36, -0.1), Vector3(-9.0, top1 + 0.36, -0.1), Mod.AZOTEA)
	# Soportal
	var g := Mod.frame(Vector3(0.0, 0.0, -27.5), 0.0)
	for p in Zone.ARCADE:
		m.column(g, float(p[0]), 0.0, 3.12, WHITE, 0.46)
	for i in Zone.ARCADE.size() - 1:
		var xa := float(Zone.ARCADE[i][0])
		var xb := float(Zone.ARCADE[i + 1][0])
		_arch("obra", g, xa, xb, 3.12, top0 - 0.24, 1.1, xb - xa - 1.0, 0.0, 1.05, WHITE, WHITE_SHADE, 0, true)
		# un farol en la clave de cada arco
		_lantern(Vector3((xa + xb) * 0.5, 3.2, -27.5), 0.3, WARM, 0.18)
		_pool(Vector3((xa + xb) * 0.5, 0, -27.0), 3.2, WARM, 0.24)
	_box("obra", Vector3(61.2, 0.24, 3.5), WHITE.darkened(0.06), Vector3(0, top0 - 0.12, -28.25))
	_box("obra", Vector3(60.4, 0.12, 1.24), OCHRE, Vector3(0, 3.06, -27.5))
	m.parapet(Mod.frame(Vector3(-30.0, 0.0, -26.75), 0.0), 0.0, 60.0, top0, 3, WHITE, 6.0)
	# Planta baja: puertas de colores (las de medio punto, con el abanico encendido)
	var doors: Array = [TURQUOISE.darkened(0.25), WOOD, OCHRE.darkened(0.15), Color(0.62, 0.22, 0.3), WOOD_DARK, TURQUOISE.darkened(0.4), WOOD, Color(0.3, 0.42, 0.3), WOOD]
	for i in 9:
		var x := half - 24.0 + 6.0 * float(i)
		if i == 4:
			m.door(f, x, doors[i], 2)
		else:
			m.door(f, x, doors[i], 1 if i % 2 == 0 else 0, i % 4 == 0)
	for x in [2.2, w - 2.2]:
		m.window(f, x, Mod.SILL, x < half, 0)
	# Planta alta: una puerta-ventana sobre cada arco y una ventana sobre cada columna
	for i in 9:
		m.window(f, half - 24.0 + 6.0 * float(i), top0 + 0.06, i % 2 == 1 or i == 4, 1)
	for i in 10:
		if i != 4 and i != 5:
			m.window(f, half - 27.0 + 6.0 * float(i), top0 + 1.15, i % 3 == 0, 2)
	# Torre del reloj, sobre el eje de la plaza
	m.box(f, "suelo", Vector3(7.0, top1 - top0 + 0.9, 0.5), WHITE, Vector3(half, (top0 + top1 + 0.9) * 0.5, 0.05), WHITE_SHADE)
	for s in [-1.0, 1.0]:
		m.box(f, "suelo", Vector3(0.6, top1 - top0 + 0.9, 0.24), WHITE, Vector3(half + s * 3.2, (top0 + top1 + 0.9) * 0.5, 0.36), WHITE_SHADE)
	m.tower(f, half, -2.25, 4.8, 13.6, WHITE, "suelo", 3.0)
	m.cyl(f, "suelo", 1.22, 0.24, WHITE, Vector3(half, 11.6, 0.1), 12, -1.0, WHITE_SHADE, Basis(Vector3.RIGHT, PI * 0.5))
	m.disc(f, "brillo", Vector3(half, 11.6, 0.36), 0.98, Color(1.0, 0.95, 0.74), Color(1.0, 0.82, 0.5), 12)
	m.quad(f, "det", Vector3(half - 0.05, 12.3, 0.38), Vector3(half + 0.05, 12.3, 0.38), Vector3(half + 0.05, 11.55, 0.38), Vector3(half - 0.05, 11.55, 0.38), IRON)
	m.quad(f, "det", Vector3(half - 0.04, 11.66, 0.38), Vector3(half + 0.5, 11.3, 0.38), Vector3(half + 0.46, 11.22, 0.38), Vector3(half - 0.04, 11.54, 0.38), IRON)
	m.wash(f, half, 11.6, 2.4, WARM, 0.14, 0.4)


func _benches() -> void:
	for bn in Zone.BENCHES:
		_vida.confidente(Vector3(bn[0], 0.0, bn[1]), float(bn[2]), float(bn[3]))


func _lamps() -> void:
	for i in Zone.LAMPS.size():
		var p: Array = Zone.LAMPS[i]
		var at := Vector3(p[0], 0.0, p[1])
		var plaza := i < 8   # las del camino al portal son más altas y de luz de jade
		_vida.lamp(at, 3.2 if plaza else 4.6, WARM if plaza else Color(0.75, 1.0, 0.8))
		_pool(at, 5.4, WARM if plaza else Color(0.7, 1.0, 0.8), 0.36)


func _gardens() -> void:
	var v := _vida
	for i in Zone.GARDEN_TREES.size():
		var p: Array = Zone.GARDEN_TREES[i]
		var sx := signf(float(p[0]))
		var sz := signf(float(p[1]))
		var c := Vector3(sx * 20.0, 0.0, sz * 23.0)
		var d := _det(c)
		# bordillo de la jardinera (8 × 6 m)
		_box(d, Vector3(8.3, 0.22, 0.3), WHITE_SHADE, c + Vector3(0, 0.11, -3.0))
		_box(d, Vector3(8.3, 0.22, 0.3), WHITE_SHADE, c + Vector3(0, 0.11, 3.0))
		_box(d, Vector3(0.3, 0.22, 6.0), WHITE_SHADE, c + Vector3(-4.0, 0.11, 0))
		_box(d, Vector3(0.3, 0.22, 6.0), WHITE_SHADE, c + Vector3(4.0, 0.11, 0))
		# cada jardinera, su árbol: flamboyán, lluvia de oro, laurel y palma real
		var at := Vector3(p[0], 0.0, p[1])
		var bloom := MAGENTA
		match i:
			0:
				v.flamboyan(at, Color(0.92, 0.3, 0.12))
				bloom = Color(1.0, 0.55, 0.15)
			1:
				v.lluvia_de_oro(at)
				bloom = Color(1.0, 0.86, 0.3)
			2:
				v.laurel(at)
			_:
				# (frente al templo: una palma no lo tapa)
				v.palm("obra", at, 7.6, Vector2(0.5, -0.3), 9, 1.15)
				bloom = Color(0.96, 0.94, 0.88)
		# seto en el lado de fuera y matas de flor a los lados del árbol
		v.hedge(c.x - 3.7, c.z + sz * 2.2, c.x + 3.7, c.z + sz * 2.75)
		for k in 4:
			var bp := c + Vector3(-3.0 + 2.0 * float(k), 0.0, -sz * (1.9 if k % 2 == 0 else 0.6))
			if bp.distance_to(at) > 1.3:
				v.flowers(bp, bloom if k % 2 == 0 else MAGENTA, 4)


## Carreta de flores (decorado): al noroeste, para dar color frente al quiosco.
func _cart() -> void:
	var at := Vector3(Zone.SOLIDS[3][0], 0.0, Zone.SOLIDS[3][1])
	var d := _det(at)
	_box("obra", Vector3(2.4, 0.5, 1.3), WOOD, at + Vector3(0, 0.95, 0), 0.5, WOOD_DARK)
	for s in [-1.0, 1.0]:
		var off := Basis(Vector3.UP, 0.5) * Vector3(0.7, 0.0, 0.72 * s)
		_cyl("obra", 0.6, 0.12, WOOD_DARK, at + off + Vector3(0, 0.6, 0), 10, -1.0, NONE, Basis(Vector3.UP, 0.5) * Basis(Vector3.RIGHT, PI * 0.5))
	for k in 4:
		var corner := Basis(Vector3.UP, 0.5) * Vector3(1.1 * (1.0 if k % 2 == 0 else -1.0), 0.0, 0.58 * (1.0 if k < 2 else -1.0))
		_cyl(d, 0.04, 1.5, WOOD_DARK, at + corner + Vector3(0, 1.2, 0), 5)
	for k in 5:
		var stripe := Basis(Vector3.UP, 0.5) * Vector3(-1.04 + 0.52 * float(k), 0.0, 0.0)
		_box("obra", Vector3(0.5, 0.06, 1.5), FLAGS[k % 2 * 2 + 1] if k % 2 == 0 else FLAGS[6], at + stripe + Vector3(0, 2.72, 0), 0.5)
	for k in 10:
		var pos := Basis(Vector3.UP, 0.5) * Vector3(-0.95 + 0.42 * float(k % 5), 0.0, -0.3 + 0.6 * float(k / 5))
		_ball(d, 0.2, [MAGENTA, Color(1.0, 0.6, 0.1), Color(1.0, 0.85, 0.2), FLAGS[5], Color(0.95, 0.3, 0.25)][k % 5], at + pos + Vector3(0, 1.3, 0), 0.9, LEAF, 6)
	for k in 3:
		var pos := at + Vector3(-1.4 + 0.5 * float(k), 0.0, 1.1 + 0.2 * float(k))
		_cyl(d, 0.22, 0.4, TERRACOTTA, pos, 7, 0.3)
		_ball(d, 0.28, LEAF_LIGHT, pos + Vector3(0, 0.6, 0), 0.9, LEAF, 6)


# ───────────────────────── Puntos de interés ─────────────────────────

## Puesto de saberes: mostrador al oeste (hacia el árbol), toldo de rayas y estantes al fondo.
func _shop() -> void:
	var s: Array = Zone.STANDS[0]
	var c := Vector3(s[0], 0.0, s[1])
	var hx := float(s[2])
	var hz := float(s[3])
	_box("obra", Vector3(hx * 2.0, 0.12, hz * 2.0), WOOD_DARK, c + Vector3(0, 0.06, 0))
	_box("obra", Vector3(0.7, 0.68, hz * 2.0 - 0.5), WOOD, c + Vector3(-hx + 0.4, 0.46, 0), 0.0, WOOD_DARK)
	_box("obra", Vector3(0.9, 0.08, hz * 2.0 - 0.3), WOOD.lightened(0.2), c + Vector3(-hx + 0.4, 0.84, 0))
	_box("obra", Vector3(0.4, 2.3, hz * 2.0 - 0.3), WOOD_DARK, c + Vector3(hx - 0.25, 1.25, 0))
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			_cyl("obra", 0.08, 3.0 if sx > 0 else 2.5, WOOD_DARK, c + Vector3(sx * (hx - 0.12), 0.1, sz * (hz - 0.12)), 6)
	# Toldo de rayas: alto al fondo, bajo y volado hacia delante
	for k in 8:
		var z := -hz + 0.25 + 0.5 * float(k)
		# (va con lo pequeño: no arroja sombra, así el sol de la tarde entra hasta la tendera)
		_beam(_det(c), c + Vector3(hx + 0.1, 3.2, z), c + Vector3(-hx - 0.7, 2.55, z), 0.06, [MAGENTA, FLAGS[6], TURQUOISE, FLAGS[6]][k % 4], 0.5)
		_box(_det(c), Vector3(0.05, 0.3, 0.42), [MAGENTA, FLAGS[1], TURQUOISE, FLAGS[3]][k % 4], c + Vector3(-hx - 0.7, 2.37, z))
	# Rótulo sobre el toldo (el texto es una etiqueta: ver _labels)
	_box(_det(c), Vector3(0.14, 0.8, 3.0), WOOD_DARK, c + Vector3(-hx - 0.2, 3.35, 0))
	_box(_det(c), Vector3(0.06, 0.62, 2.8), WOOD.lightened(0.25), c + Vector3(-hx - 0.29, 3.35, 0))
	# Sobre el mostrador: tres «saberes» que brillan, pergaminos y tarros
	for k in 3:
		var p := c + Vector3(-hx + 0.4, 0.88, -1.2 + 1.2 * float(k))
		_cyl(_det(c), 0.13, 0.1, STONE, p, 6, 0.6)
		_ball("brillo", 0.13, [JADE, GOLD, Color(1.0, 0.45, 0.75)][k], p + Vector3(0, 0.25, 0), 1.0, NONE, 6)
	_pool(c + Vector3(-hx - 0.4, 0, 0), 3.4, Color(0.7, 1.0, 0.8), 0.22)
	for k in 9:
		var row := float(k / 3)
		var p := c + Vector3(hx - 0.5, 0.75 + 0.62 * row, -1.2 + 1.2 * float(k % 3))
		match k % 4:
			0:
				_cyl(_det(c), 0.16, 0.32, TERRACOTTA.lightened(0.1), p, 6, 0.6)
			1:
				_box(_det(c), Vector3(0.12, 0.3, 0.5), FLAGS[k % 7], p + Vector3(0, 0.15, 0))
			2:
				_ball("brillo", 0.1, JADE.darkened(0.1), p + Vector3(0, 0.12, 0), 1.0, NONE, 6)
			_:
				_cyl(_det(c), 0.07, 0.4, Color(0.92, 0.86, 0.7), p + Vector3(0, 0.07, -0.2), 5, -1.0, NONE, Basis(Vector3.RIGHT, PI * 0.5))
	_box("obra", Vector3(0.34, 0.05, hz * 2.0 - 0.4), WOOD, c + Vector3(hx - 0.5, 0.72, 0))
	_box("obra", Vector3(0.34, 0.05, hz * 2.0 - 0.4), WOOD, c + Vector3(hx - 0.5, 1.34, 0))
	_box("obra", Vector3(0.34, 0.05, hz * 2.0 - 0.4), WOOD, c + Vector3(hx - 0.5, 1.96, 0))
	_lantern(c + Vector3(-hx - 0.55, 2.0, -hz + 0.3), 0.3)
	_lantern(c + Vector3(-hx - 0.55, 2.0, hz - 0.3), 0.3)
	_ring("suelo", Vector3(c.x + 0.1, 0.132, c.z), 0.0, 0.5, WOOD_DARK.darkened(0.4), 12)   # sombra de la tendera
	# un mástil con su joya de jade: el puesto se reconoce desde toda la plaza
	_cyl("obra", 0.07, 4.9, WOOD_DARK, c + Vector3(hx - 0.12, 0.1, -hz + 0.12), 6)
	_emit("brillo", "oct", Basis.IDENTITY, Vector3(0.5, 0.8, 0.5), c + Vector3(hx - 0.12, 5.3, -hz + 0.12), JADE, NONE)
	_pool(c + Vector3(hx - 0.12, 0, -hz + 0.12), 2.2, JADE, 0.14)


## Tablón de misiones: mira al sur, hacia el camino del portal.
func _board() -> void:
	var s: Array = Zone.STANDS[1]
	var c := Vector3(s[0], 0.0, s[1])
	for sx in [-1.0, 1.0]:
		_cyl("obra", 0.1, 3.0, WOOD_DARK, c + Vector3(sx * 1.35, 0, 0), 6)
	_box("obra", Vector3(2.7, 1.7, 0.12), WOOD, c + Vector3(0, 1.75, 0), 0.0, WOOD_DARK)
	_beam("obra", c + Vector3(-1.75, 2.75, 0), c + Vector3(0, 3.4, 0), 0.1, TERRACOTTA, 0.9)
	_beam("obra", c + Vector3(1.75, 2.75, 0), c + Vector3(0, 3.4, 0), 0.1, TERRACOTTA, 0.9)
	var d := _det(c)
	# La misión que hay, enmarcada en oro; a los lados, hojas borrosas de lo que vendrá
	_box("brillo", Vector3(0.96, 1.16, 0.02), GOLD.darkened(0.05), c + Vector3(-0.55, 1.78, 0.07))
	_box("brillo", Vector3(0.84, 1.04, 0.03), Color(0.8, 0.74, 0.58), c + Vector3(-0.55, 1.78, 0.085))
	_box("brillo", Vector3(0.3, 0.3, 0.02), JADE, c + Vector3(-0.55, 2.0, 0.105), 0.0)
	for k in 3:
		_box(d, Vector3(0.6, 0.05, 0.02), WOOD_DARK, c + Vector3(-0.55, 1.62 - 0.13 * float(k), 0.105))
	_box("brillo", Vector3(0.6, 0.72, 0.03), Color(0.46, 0.43, 0.37), c + Vector3(0.38, 1.98, 0.075), 0.0)
	_box("brillo", Vector3(0.52, 0.6, 0.03), Color(0.42, 0.39, 0.34), c + Vector3(0.92, 1.5, 0.075), 0.0)
	_box("brillo", Vector3(0.5, 0.5, 0.03), Color(0.44, 0.41, 0.36), c + Vector3(0.3, 1.28, 0.075), 0.0)
	_lantern(c + Vector3(-1.75, 2.35, 0.25), 0.3)
	_lantern(c + Vector3(1.75, 2.35, 0.25), 0.3)
	_pool(c + Vector3(0, 0, 1.2), 3.2, WARM, 0.26)
	_emit("brillo", "oct", Basis.IDENTITY, Vector3(0.4, 0.62, 0.4), c + Vector3(0, 3.95, 0), GOLD, NONE)


# ───────────────────────── Este: el portal al Claro ─────────────────────────

func _portal() -> void:
	var c := Zone.PORTAL
	# Piedra antigua, más oscura que la plaza, con glifos de jade encendidos
	_box("obra", Vector3(4.6, 0.06, 9.4), STONE_DARK.lightened(0.08), Vector3(c.x - 0.6, 0.03, c.y))
	_box("obra", Vector3(3.2, 0.06, 8.0), STONE, Vector3(c.x + 0.1, 0.09, c.y))
	for z in [-2.4, 2.4]:
		_cyl("obra", 0.75, 4.6, STONE.lightened(0.05), Vector3(c.x, 0.0, c.y + z), 6, 0.86, STONE_DARK.darkened(0.2))
		_box("obra", Vector3(1.7, 0.4, 1.7), STONE_DARK, Vector3(c.x, 0.32, c.y + z))
		for k in 3:
			_box("brillo", Vector3(0.2, 0.34, 0.34), JADE, Vector3(c.x - 0.7 + 0.03 * float(k), 1.5 + 0.9 * float(k), c.y + z), 0.0)
	_box("obra", Vector3(1.6, 0.95, 7.0), STONE, Vector3(c.x, 5.0, c.y), 0.0, STONE_DARK)
	_box("obra", Vector3(1.1, 0.45, 3.4), STONE.lightened(0.08), Vector3(c.x, 5.7, c.y))
	_box("brillo", Vector3(0.05, 0.5, 0.5), JADE, Vector3(c.x - 0.82, 5.0, c.y), 0.0)
	# Braseros de jade a los lados del camino
	for z in [-3.9, 3.9]:
		var p := Vector3(c.x - 2.2, 0.06, c.y + z)
		_cyl("obra", 0.42, 0.9, STONE_DARK, p, 6, 0.7)
		_cyl("obra", 0.62, 0.3, STONE, p + Vector3(0, 0.9, 0), 6, 1.25)
		_cyl("brillo", 0.36, 0.95, JADE, p + Vector3(0, 1.15, 0), 5, 0.0, Color(0.85, 1.0, 0.8))
		_pool(p, 4.0, JADE, 0.2)
	_pool(Vector3(c.x - 2.6, 0, c.y), 6.5, JADE, 0.2)
	# La selva del Claro asoma detrás
	for t in [[5.0, -6.0, 5.4], [7.5, 5.0, 6.2], [4.5, 9.5, 4.6], [10.0, -1.5, 7.0], [5.5, -12.0, 4.8]]:
		var at := Vector3(c.x + float(t[0]), 0.0, c.y + float(t[1]))
		_cyl("obra", 0.55, float(t[2]), BARK.darkened(0.2), at, 6, 0.35)
		_ball("obra", float(t[2]) * 0.62, LEAF.lightened(0.06), at + Vector3(0, float(t[2]) + 1.2, 0), 0.75, LEAF.darkened(0.45))
	# El velo del portal: un remolino de jade que hace el sombreador
	var plane := QuadMesh.new()
	plane.size = Vector2(4.1, 4.5)
	var sh := Shader.new()
	sh.code = """shader_type spatial;
render_mode unshaded, cull_disabled, shadows_disabled, blend_add, depth_draw_never;
void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p);
	float a = atan(p.y, p.x);
	float swirl = sin(a * 3.0 + r * 7.0 - TIME * 1.6) * 0.5 + 0.5;
	float rings = sin(r * 14.0 - TIME * 2.2) * 0.5 + 0.5;
	float edge = smoothstep(1.0, 0.72, max(abs(p.x), abs(p.y)));
	float pulse = 0.82 + 0.18 * sin(TIME * 2.1);
	vec3 col = mix(vec3(0.02, 0.5, 0.42), vec3(0.45, 1.0, 0.8), swirl * 0.6 + rings * 0.3);
	ALBEDO = col * pulse;
	ALPHA = edge * (0.5 + 0.4 * swirl);
}
"""
	var mat := ShaderMaterial.new()
	mat.shader = sh
	var veil := MeshInstance3D.new()
	veil.name = "portal"
	veil.mesh = plane
	veil.material_override = mat
	veil.position = Vector3(c.x + 0.1, 2.65, c.y)
	veil.rotation.y = -PI * 0.5
	veil.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_root.add_child(veil)
	_box("obra", Vector3(0.3, 4.4, 4.2), Color(0.02, 0.1, 0.1), Vector3(c.x + 0.45, 2.6, c.y))   # fondo oscuro tras el velo


# ───────────────────────── La ciudad alrededor ─────────────────────────

## El perímetro: la ciudad que rodea la plaza, compuesta con las piezas de plaza_modulos.gd. Las
## fachadas van un metro más allá de donde llega un alux (no hacen falta obstáculos nuevos).
##   sur     casonas de colores y dos callejones: dan la espalda al sol, viven de ventanas y faroles
##   oeste   portales comerciales entre dos casonas; bajos, para que entre el sol de la tarde
##   este    al sur del portal, el templo, de cara al sol; el portal con su selva; y al norte
##           (z < −11), sólo el pretil de siempre: tramo reservado para otra salida
func _city() -> void:
	var half := Zone.HALF
	var m := _mod
	var v := _vida
	var e := half + 1.0
	var cream: Color = FLAGS[6]
	# ── Sur ──
	var s := Mod.frame(Vector3(e, 0.0, e), PI)
	m.casona(s, 0.0, 13.0, Color(0.56, 0.76, 0.84), "VAVT", "BVVB", 1, TURQUOISE.darkened(0.4), {"toldo": [FLAGS[1], cream]})
	m.alley(s, 13.0, 2.0)
	m.casona(s, 15.0, 12.0, Color(0.96, 0.8, 0.44), "VPVV", "", 3, Color(0.3, 0.42, 0.3))
	m.casona(s, 27.0, 16.0, Color(0.92, 0.6, 0.56), "VVZVV", "BVBVB", 2, WOOD_DARK)
	m.casona(s, 43.0, 12.0, Color(0.7, 0.82, 0.6), "TVPV", "", 4, Color(0.62, 0.22, 0.3), {"toldo": [TURQUOISE, cream]})
	m.alley(s, 55.0, 2.0)
	m.casona(s, 57.0, 13.0, Color(0.9, 0.64, 0.32), "VAVV", "VBBV", 1, WOOD)
	# ── Oeste ──
	var w := Mod.frame(Vector3(-e, 0.0, e), PI * 0.5)
	m.casona(w, 0.0, 14.0, Color(0.8, 0.7, 0.86), "VPVT", "BVVB", 1, WOOD_DARK, {"toldo": [FLAGS[3], cream]})
	var shops: Array = [[Color(0.62, 0.22, 0.3), [MAGENTA, cream]], [TURQUOISE.darkened(0.3), null], [WOOD, [FLAGS[1], cream]], [Color(0.3, 0.42, 0.3), null],
		[OCHRE.darkened(0.2), [TURQUOISE, cream]], [Color(0.4, 0.3, 0.6), null], [WOOD_DARK, [FLAGS[3], cream]]]
	m.portales(w, 14.0, 7, Color(0.95, 0.86, 0.64), shops)
	m.casona(w, 56.0, 8.0, Color(0.88, 0.54, 0.44), "VPV", "", 3, TURQUOISE.darkened(0.3))
	# género a la puerta de las tiendas, bajo los arcos
	for k in 7:
		var gx := 14.0 + 6.0 * float(k) + (1.9 if k % 2 == 0 else -1.9)
		var gp := Vector3(gx, 0.1, -2.5)
		match k % 3:
			0:
				for q in 3:
					m.gem(w, "det", Vector3(0.7, 0.5, 0.56), Color(0.78, 0.68, 0.5), gp + Vector3(0.36 * float(q) - 0.36, 0.25 + 0.3 * float(q % 2), 0.1 * float(q)), Color(0.5, 0.42, 0.3))
			1:
				m.cyl(w, "det", 0.34, 0.8, WOOD, gp, 7, 0.3, WOOD_DARK)
				m.cyl(w, "det", 0.3, 0.7, WOOD.lightened(0.1), gp + Vector3(0.7, 0.0, 0.2), 7, 0.27, WOOD_DARK)
			_:
				m.box(w, "det", Vector3(0.9, 0.5, 0.7), WOOD, gp + Vector3(0, 0.25, 0), WOOD_DARK)
				for q in 4:
					m.gem(w, "det", Vector3(0.26, 0.24, 0.26), [Color(1.0, 0.55, 0.1), Color(0.5, 0.74, 0.2)][q % 2], gp + Vector3(-0.24 + 0.48 * float(q % 2), 0.6, -0.16 + 0.32 * float(q / 2)))
	# ── Este, al sur del portal: el templo, con henequenes a los lados de la escalinata ──
	var t := Mod.frame(Vector3(e, 0.0, 11.0), -PI * 0.5)
	m.templo(t)
	for x in [3.0, 6.4, 17.6, 21.0]:
		v.pot(t * Vector3(x, 0.0, 0.56), 1, 1.35)
	# esquinas del sureste y del suroeste, tras las fachadas
	_box("suelo", Vector3(12.0, 8.0, 8.0), Mod.STONE.darkened(0.1), Vector3(e + 6.0, 4.0, e + 4.0), 0.0, Mod.STONE_SHADE)
	_box("suelo", Vector3(8.0, 8.0, 8.0), WHITE_SHADE, Vector3(-e - 4.0, 4.0, e + 4.0))
	# ── Este: pretil con pilastras a los lados del portal y en el tramo norte (reservado) ──
	_box("obra", Vector3(0.6, 1.1, half - 4.6), WHITE, Vector3(half + 0.3, 0.55, -(half + 4.6) * 0.5), 0.0, WHITE_SHADE)
	_box("obra", Vector3(0.6, 1.1, 6.4), WHITE, Vector3(half + 0.3, 0.55, 7.8), 0.0, WHITE_SHADE)
	for k in 9:
		var z := -half + half * 2.0 * float(k) / 8.0
		if absf(z) < 6.0 or z > 10.0:
			continue   # el hueco del portal; más al sur ya es el templo
		var p := Vector3(half + 0.3, 0.0, z)
		var d := _det(p)
		_box(d, Vector3(0.85, 1.45, 0.85), WHITE, p + Vector3(0, 0.72, 0), 0.0, WHITE_SHADE)
		_box(d, Vector3(1.0, 0.14, 1.0), OCHRE, p + Vector3(0, 1.5, 0))
		if k % 2 == 0:
			_cyl(d, 0.26, 0.36, TERRACOTTA, p + Vector3(0, 1.57, 0), 7, 0.36)
			_ball(d, 0.36, LEAF_LIGHT, p + Vector3(0, 2.1, 0), 0.9, LEAF, 6)
			_emit(d, "oct", Basis.IDENTITY, Vector3(0.26, 0.26, 0.26), p + Vector3(0.18, 2.3, 0.1), MAGENTA, NONE)
		else:
			_ball(d, 0.26, WHITE, p + Vector3(0, 1.8, 0), 1.0, WHITE_SHADE, 6)
	# Chimeneas de cocina (su humo, en _make_ambient)
	_box("suelo", Vector3(0.8, 1.9, 0.8), WHITE_SHADE, Vector3(-14.0, 6.2, half + 5.0))
	_box("suelo", Vector3(0.8, 1.6, 0.8), WHITE_SHADE, Vector3(-half - 5.5, 5.6, -25.0))
	# Iguanas tomando el último sol sobre el pretil (decorado: no se mueven ni se atacan)
	for g in [[half + 0.3, 8.6, 2.6], [half + 0.3, -9.6, -0.4]]:
		_iguana(Vector3(g[0], 1.1, g[1]), float(g[2]))
	# Lo de siempre más allá del tramo reservado: una casa y un árbol, lejos
	_box("suelo", Vector3(8.0, 5.5, 11.0), Color(0.86, 0.56, 0.5), Vector3(53.0, 2.75, -42.0), 0.0, Color(0.56, 0.36, 0.33))
	_box("suelo", Vector3(8.5, 0.4, 11.5), TERRACOTTA.darkened(0.05), Vector3(53.0, 5.7, -42.0))
	v.backdrop_tree(Vector3(50.0, 0.0, -28.0), 3.4, 3.0)
	# ── Verde ──
	# Buganvilias que se derraman por muros y callejones
	v.buganvilia(s, 14.0, 4.5, 3.4, 1.5)
	v.buganvilia(s, 56.0, 4.5, 3.4, 1.3, Color(1.0, 0.5, 0.18))
	v.buganvilia(s, 24.2, 5.7, 4.4, 2.4)
	v.buganvilia(s, 35.0, 4.1, 2.6, 0.8, Color(0.96, 0.94, 0.88))
	v.buganvilia(w, 62.6, 5.7, 3.0, 2.2, Color(1.0, 0.5, 0.18))
	v.buganvilia(w, 1.6, 4.1, 2.6, 1.6)
	var east := Mod.frame(Vector3(half, 0.0, -half), -PI * 0.5)
	v.buganvilia(east, half + 8.2, 1.5, 4.4, 0.9)
	v.buganvilia(east, half - 8.4, 1.5, 3.6, 0.9, Color(1.0, 0.5, 0.18))
	# Macetas al pie de las fachadas (fuera del paso)
	var n := 0
	for x in [1.6, 4.9, 11.4, 16.5, 22.5, 25.6, 29.0, 32.4, 37.6, 41.2, 44.8, 50.6, 53.6, 58.6, 65.0, 68.4]:
		v.pot(s * Vector3(x, 0.0, 0.5), n % 3, 1.0 + 0.2 * float(n % 2), [MAGENTA, Color(1.0, 0.6, 0.1), Color(0.96, 0.94, 0.88)][n % 3])
		n += 1
	for x in [1.7, 5.2, 12.3, 57.6, 62.4]:
		v.pot(w * Vector3(x, 0.0, 0.5), n % 3, 1.1, Color(1.0, 0.6, 0.1))
		n += 1
	# Palmas y copas a contraluz, más allá de las azoteas (lote «suelo»: sin sombra)
	for p in [[-31.0, 46.5, 12.0], [-14.0, 48.0, 13.5], [3.0, 46.5, 11.0], [16.0, 47.5, 12.5], [29.0, 46.0, 13.0],
			[-46.5, 27.0, 12.5], [-47.0, 9.0, 9.5], [-46.0, -6.0, 10.5], [-47.5, -24.0, 11.5],
			[-21.0, -38.5, 14.0], [-13.5, -39.0, 12.6], [19.0, -38.5, 14.2], [51.0, 30.0, 14.0]]:
		v.palm("suelo", Vector3(p[0], 0.0, p[1]), float(p[2]), Vector2(_rng.randf() * 2.4 - 1.2, _rng.randf() * 2.4 - 1.2), 9, 1.3)
	for p in [[-49.0, 17.0, 6.0, 4.6], [-50.0, -15.0, 5.5, 4.4], [-7.0, 49.0, 7.5, 4.6], [24.0, 50.0, 7.5, 4.8], [-40.0, 50.0, 7.0, 5.0]]:
		v.backdrop_tree(Vector3(p[0], 0.0, p[1]), float(p[2]), float(p[3]))


## El mercado, al noroeste: cuatro puestos (obstáculos en zone_def.STALLS) alrededor de la
## carreta de flores, abiertos hacia el árbol.
func _market() -> void:
	var cream: Color = FLAGS[6]
	var awnings: Array = [[Color(0.95, 0.5, 0.12), cream], [MAGENTA, cream], [TURQUOISE, cream], [Color(0.8, 0.2, 0.18), Color(1.0, 0.8, 0.2)]]
	for i in Zone.STALLS.size():
		var st: Array = Zone.STALLS[i]
		_vida.stall(Vector3(st[0], 0.0, st[1]), _stall_yaw(i), i, awnings[i])
	# costales, cántaros y una mesa baja con flores entre los puestos (dentro de sus obstáculos no:
	# van pegados a la carreta, que ya lo es)
	var cart := Vector3(Zone.SOLIDS[3][0], 0.0, Zone.SOLIDS[3][1])
	for k in 4:
		var a := 2.2 + 0.7 * float(k)
		var p := cart + Vector3(sin(a) * 1.25, 0.0, cos(a) * 1.25)
		_emit(_det(p), "oct", Basis.IDENTITY, Vector3(0.62, 0.7, 0.62), p + Vector3(0, 0.3, 0), Color(0.8, 0.7, 0.52), Color(0.5, 0.42, 0.3))


## Hacia dónde mira cada puesto: los dos del oeste, al este; los dos del norte, al sur.
func _stall_yaw(i: int) -> float:
	var st: Array = Zone.STALLS[i]
	return PI * 0.5 if float(st[3]) > float(st[2]) else 0.0


func _iguana(pos: Vector3, yaw: float) -> void:
	var d := _det(pos)
	var b := Basis(Vector3.UP, yaw)
	var green := Color(0.36, 0.5, 0.3)
	_emit(d, "ball|6", b, Vector3(0.24, 0.17, 0.62), pos + Vector3(0, 0.1, 0), green.lightened(0.15), green.darkened(0.3))
	_emit(d, "ball|6", b, Vector3(0.17, 0.15, 0.24), pos + b * Vector3(0, 0.19, 0.36), green.lightened(0.2), green.darkened(0.2))
	_emit(d, "cyl|5|0.05", b * Basis(Vector3.RIGHT, -PI * 0.5 - 0.06), Vector3(0.07, 0.75, 0.07), pos + b * Vector3(0, 0.07, -0.62), green.darkened(0.15), NONE)
	for k in 4:
		_emit(d, "box", b, Vector3(0.03, 0.07, 0.06), pos + b * Vector3(0, 0.2, 0.12 - 0.12 * float(k)), Color(0.75, 0.6, 0.3), NONE)


# ───────────────────────── Vida ambiental (sombreadores) ─────────────────────────

func _shader_mesh(name: String, bt: Batch, code: String, margin: float) -> MeshInstance3D:
	var sh := Shader.new()
	sh.code = code
	var mat := ShaderMaterial.new()
	mat.shader = sh
	var mi := MeshInstance3D.new()
	mi.name = name
	mi.mesh = _mesh_of(bt)
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.extra_cull_margin = margin
	_root.add_child(mi)
	_stats[name] = bt.i.size() / 3
	return mi


## Banderines de papel entre farolas, del árbol a las farolas y a lo largo del camino al portal.
## Cada banderín cuelga de su borde de arriba; el de abajo lo mece el sombreador.
func _banners() -> void:
	var bt := Batch.new()
	var spans := []
	var top := 3.35
	var l: Array = Zone.LAMPS
	# Del árbol a las cuatro farolas, al quiosco y al edificio de los arcos: por encima de la cámara
	for k in 4:
		spans.append([Vector3(signf(float(l[k][0])), 6.1, signf(float(l[k][1]))) * Vector3(0.6, 1.0, 0.6), Vector3(l[k][0], top, l[k][1])])
	spans.append([Vector3(0.7, 6.2, -0.6), Vector3(Zone.SOLIDS[2][0], 4.7, Zone.SOLIDS[2][1])])
	spans.append([Vector3(-0.5, 6.4, -0.8), Vector3(-9.0, 6.9, -28.9)])
	spans.append([Vector3(0.5, 6.4, -0.8), Vector3(9.0, 6.9, -28.9)])
	# Camino al portal: farolas altas a los lados, guirnaldas de una a otra y hasta el dintel
	var high := 4.75
	for s in [-1.0, 1.0]:
		spans.append([Vector3(17.5, high, 3.2 * s), Vector3(24.5, high, 3.2 * s)])
		spans.append([Vector3(24.5, high, 3.2 * s), Vector3(Zone.PORTAL.x - 0.4, 5.3, 2.6 * s)])
	spans.append([Vector3(17.5, high, -3.2), Vector3(17.5, high, 3.2)])
	spans.append([Vector3(24.5, high, -3.2), Vector3(24.5, high, 3.2)])
	var n := 0
	for sp in spans:
		var a: Vector3 = sp[0]
		var b: Vector3 = sp[1]
		var len := a.distance_to(b)
		var count := maxi(2, int(len / 0.62))
		var along := (b - a).normalized()
		var side := Vector3(along.z, 0.0, -along.x).normalized()   # hacia dónde ondea
		var prev := a
		for k in count + 1:
			var t := float(k) / float(count)
			var p := a.lerp(b, t) - Vector3(0, len * 0.045 * 4.0 * t * (1.0 - t), 0)
			if k > 0:
				# la cuerda (no se mece)
				_flag_quad(bt, prev + Vector3(0, 0.012, 0), p + Vector3(0, 0.012, 0), prev - Vector3(0, 0.012, 0), p - Vector3(0, 0.012, 0), IRON, side, 0.0, 0.0)
				var mid := (prev + p) * 0.5
				var half := along * 0.22
				var color: Color = FLAGS[n % FLAGS.size()]
				n += 1
				_flag_quad(bt, mid - half, mid + half, mid - half - Vector3(0, 0.36, 0), mid + half - Vector3(0, 0.36, 0), color.darkened(0.12), side, 0.0, 1.0)
			prev = p
	_shader_mesh("banderines", bt, """shader_type spatial;
render_mode unshaded, cull_disabled, shadows_disabled;
void vertex() {
	float ph = VERTEX.x * 0.9 + VERTEX.z * 0.7;
	VERTEX += NORMAL * (sin(TIME * 2.4 + ph) * 0.1 + sin(TIME * 3.7 + ph * 1.7) * 0.04) * UV.y;
}
void fragment() {
	ALBEDO = pow(COLOR.rgb, vec3(2.2)) * 0.85;
}
""", 0.5).visibility_range_end = 70.0


func _flag_quad(bt: Batch, a: Vector3, b: Vector3, c: Vector3, d: Vector3, color: Color, normal: Vector3, sway_top: float, sway_bottom: float) -> void:
	var base := bt.v.size()
	for p in [a, b, c, d]:
		bt.v.append(p)
		bt.n.append(normal)
		bt.c.append(color)
	bt.uv.append(Vector2(0, sway_top))
	bt.uv.append(Vector2(1, sway_top))
	bt.uv.append(Vector2(0, sway_bottom))
	bt.uv.append(Vector2(1, sway_bottom))
	for k in [0, 1, 2, 1, 3, 2]:
		bt.i.append(base + k)


## Luciérnagas: cada una es un cuadrado que mira a la cámara; deriva y parpadea en el sombreador.
func _make_fireflies() -> void:
	var bt := Batch.new()
	var spots := [[0.0, 0.0, 7.0, 16], [-20.0, 23.0, 5.0, 9], [20.0, 23.0, 5.0, 9], [-20.0, -23.0, 5.0, 8], [20.0, -23.0, 5.0, 8],
		[-15.0, 12.0, 4.5, 8], [28.0, 0.0, 5.0, 10], [0.0, 13.0, 6.0, 8]]
	for s in spots:
		for k in int(s[3]):
			var a := _rng.randf() * TAU
			var r := sqrt(_rng.randf()) * float(s[2])
			var center := Vector3(float(s[0]) + sin(a) * r, 0.5 + _rng.randf() * 2.6, float(s[1]) + cos(a) * r)
			var base := bt.v.size()
			var phase := Vector2(_rng.randf(), 0.35 + _rng.randf() * 0.5)
			var col := Color(0.8, 1.0, 0.4) if k % 4 != 0 else Color(0.45, 1.0, 0.8)
			for corner in [Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)]:
				bt.v.append(center)
				bt.c.append(col)
				bt.uv.append(corner)
				bt.uv2.append(phase)
			for q in [0, 1, 2, 0, 2, 3]:
				bt.i.append(base + q)
	_fireflies = _shader_mesh("luciernagas", bt, """shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled, skip_vertex_transform;
varying float glow;
void vertex() {
	float ph = UV2.x;
	float t = TIME * UV2.y + ph * 6.2831;
	vec3 c = VERTEX + vec3(sin(t) * 0.9, sin(t * 1.7 + ph * 9.0) * 0.35, cos(t * 0.8 + ph * 4.0) * 0.9);
	c += (INV_VIEW_MATRIX[0].xyz * (UV.x - 0.5) + INV_VIEW_MATRIX[1].xyz * (UV.y - 0.5)) * 0.2;
	VERTEX = (VIEW_MATRIX * vec4(c, 1.0)).xyz;
	glow = 0.2 + 0.8 * max(0.0, sin(t * 2.3 + ph * 20.0));
}
void fragment() {
	float g = clamp(1.0 - length(UV - vec2(0.5)) * 2.0, 0.0, 1.0);
	ALBEDO = COLOR.rgb;
	ALPHA = g * g * glow;
}
""", 3.0)
	_fireflies.visibility_range_end = 60.0


## Aves que dan vueltas sobre la plaza, a contraluz. Todo el movimiento va en el sombreador.
func _make_birds() -> void:
	var bt := Batch.new()
	for k in 11:
		var center := Vector3(_rng.randf() * 8.0 - 4.0, 13.0 + _rng.randf() * 7.0, _rng.randf() * 8.0 - 4.0)
		var orbit := 10.0 + _rng.randf() * 16.0
		var phase := Vector2(_rng.randf(), (0.16 + _rng.randf() * 0.12) * (1.0 if k % 4 != 0 else -1.0))
		var col := Color(0.12, 0.1, 0.16)
		var base := bt.v.size()
		# NORMAL lleva la forma: x a los lados, y arriba, z adelante. UV.x = cuánto aletea ese vértice
		var pts := [[Vector3(0, 0, 0.32), 0.0], [Vector3(0, 0, -0.3), 0.0], [Vector3(0.85, 0, -0.12), 1.0], [Vector3(-0.85, 0, -0.12), 1.0]]
		for pt in pts:
			bt.v.append(center)
			bt.n.append(pt[0])
			bt.c.append(col)
			bt.uv.append(Vector2(float(pt[1]), orbit / 30.0))
			bt.uv2.append(phase)
		for q in [0, 1, 2, 0, 3, 1]:
			bt.i.append(base + q)
	var birds := _shader_mesh("aves", bt, """shader_type spatial;
render_mode unshaded, cull_disabled, shadows_disabled, skip_vertex_transform;
void vertex() {
	float ph = UV2.x * 6.2831;
	float a = TIME * UV2.y + ph;
	float r = UV.y * 30.0;
	vec3 c = VERTEX + vec3(cos(a) * r, sin(a * 2.0 + ph) * 1.2, sin(a) * r);
	vec2 dir = vec2(-sin(a), cos(a)) * sign(UV2.y);
	vec3 o = NORMAL;
	o.y += UV.x * sin(TIME * 7.0 + ph * 5.0) * 0.5;
	vec3 wp = c + vec3(-dir.y, 0.0, dir.x) * o.x + vec3(0.0, o.y, 0.0) + vec3(dir.x, 0.0, dir.y) * o.z;
	VERTEX = (VIEW_MATRIX * vec4(wp, 1.0)).xyz;
	NORMAL = vec3(0.0, 0.0, 1.0);
}
void fragment() {
	ALBEDO = pow(COLOR.rgb, vec3(2.2));
}
""", 0.0)
	birds.custom_aabb = AABB(Vector3(-36, 8, -36), Vector3(72, 20, 72))


## Palomas: una bandada que picotea por la plaza y sale volando si un alux se acerca.
func _make_doves() -> void:
	var tmp := "paloma"
	var grey := Color(0.78, 0.78, 0.82)
	_emit(tmp, "ball|6", Basis.IDENTITY, Vector3(0.17, 0.16, 0.3), Vector3(0, 0.13, 0), grey.lightened(0.3), grey.darkened(0.2))
	_emit(tmp, "ball|6", Basis.IDENTITY, Vector3(0.1, 0.1, 0.11), Vector3(0, 0.25, 0.12), grey.lightened(0.35), NONE)
	_emit(tmp, "box", Basis.IDENTITY, Vector3(0.11, 0.02, 0.16), Vector3(0, 0.13, -0.2), grey.darkened(0.25), NONE)
	_emit(tmp, "box", Basis.IDENTITY, Vector3(0.025, 0.02, 0.05), Vector3(0, 0.24, 0.19), Color(0.9, 0.6, 0.3), NONE)
	for s in [-1.0, 1.0]:
		_emit(tmp, "box", Basis(Vector3.FORWARD, 0.25 * s), Vector3(0.14, 0.015, 0.2), Vector3(0.1 * s, 0.16, -0.03), grey.darkened(0.1), NONE)
	var solid := StandardMaterial3D.new()
	solid.vertex_color_use_as_albedo = true
	solid.vertex_color_is_srgb = true
	solid.roughness = 1.0
	solid.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	_doves_mm = MultiMesh.new()
	_doves_mm.transform_format = MultiMesh.TRANSFORM_3D
	_doves_mm.mesh = _mesh_of(_batches[tmp])
	_doves_mm.instance_count = 9
	for k in _doves_mm.instance_count:
		var a := _rng.randf() * TAU
		var r := 0.4 + _rng.randf() * 1.6
		var p := Vector3(DOVE_HOMES[0].x + sin(a) * r, 0.0, DOVE_HOMES[0].y + cos(a) * r)
		_doves.append({"p": p, "to": p, "from": p, "yaw": a, "fly": false, "k": 0.0, "dur": 2.0, "wait": _rng.randf() * 3.0})
		_doves_mm.set_instance_transform(k, Transform3D(Basis(Vector3.UP, a), p))
	var mi := MultiMeshInstance3D.new()
	mi.name = "palomas"
	mi.multimesh = _doves_mm
	mi.material_override = solid
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.custom_aabb = AABB(Vector3(-36, -1, -36), Vector3(72, 8, 72))
	_root.add_child(mi)


## Humo de cocina y de copal, y pétalos que caen de los árboles en flor: cuadrados que miran a la
## cámara y que mueve el sombreador (una sola malla, sin trabajo por cuadro; en calidad mínima se
## oculta). En cada vértice: VERTEX = dónde nace, NORMAL = cuánto viaja en una vida (si sube, es
## humo; si baja, pétalo), COLOR.a = tamaño y UV2 = (fase, vidas por segundo).
func _make_ambient() -> void:
	var bt := Batch.new()
	var d := Zone.STALLS[3] as Array
	var smoke: Array = [[Mod.frame(Vector3(d[0], 0.0, d[1]), _stall_yaw(3)) * Vector3(-0.9, 1.35, 0.6), 6, 0.5],
		[Vector3(Zone.HALF + 0.5, 1.5, 17.7), 4, 0.4], [Vector3(Zone.HALF + 0.5, 1.5, 28.3), 4, 0.4],
		[Vector3(-14.0, 7.3, Zone.HALF + 5.0), 5, 0.62], [Vector3(-Zone.HALF - 5.5, 6.5, -25.0), 5, 0.62]]
	for sm in smoke:
		for k in int(sm[1]):
			var grey := 0.62 + _rng.randf() * 0.2
			_puff(bt, sm[0], Vector3(0.7 + _rng.randf() * 0.8, 3.0 + _rng.randf() * 1.6, -0.5 - _rng.randf() * 0.6), Color(grey, grey * 0.96, grey * 0.94, float(sm[2])),
				float(k) / float(sm[1]) + _rng.randf() * 0.1, 0.15 + _rng.randf() * 0.05)
	var trees: Array = [[Vector3(Zone.GARDEN_TREES[0][0], 4.4, Zone.GARDEN_TREES[0][1]), 12, Color(0.95, 0.36, 0.14), 2.6],
		[Vector3(Zone.GARDEN_TREES[1][0], 4.0, Zone.GARDEN_TREES[1][1]), 12, Color(1.0, 0.86, 0.3), 2.2],
		[Vector3(0.0, 6.4, 0.0), 14, Color(0.62, 0.72, 0.28), 6.0], [Vector3(11.0, 5.2, Zone.HALF + 0.6), 7, MAGENTA, 1.6]]
	for tr in trees:
		for k in int(tr[1]):
			var a := _rng.randf() * TAU
			var r := sqrt(_rng.randf()) * float(tr[3])
			_puff(bt, (tr[0] as Vector3) + Vector3(sin(a) * r, _rng.randf() * 0.8, cos(a) * r), Vector3(0.8 + _rng.randf(), -(tr[0] as Vector3).y - 0.3, -0.6 - _rng.randf() * 0.8),
				Color(tr[2].r, tr[2].g, tr[2].b, 0.085 + _rng.randf() * 0.03), _rng.randf(), 0.09 + _rng.randf() * 0.07)
	_ambient = _shader_mesh("ambiente", bt, """shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled, skip_vertex_transform;
varying float fade;
varying float soft;
void vertex() {
	float life = fract(TIME * UV2.y + UV2.x);
	float rise = step(0.0, NORMAL.y);
	float ph = UV2.x * 40.0;
	vec3 c = VERTEX + NORMAL * life;
	c.x += sin(TIME * 0.9 + ph) * mix(0.45, 0.15 + life * 0.5, rise);
	c.z += cos(TIME * 0.7 + ph * 1.3) * mix(0.45, 0.12 + life * 0.4, rise);
	float size = COLOR.a * 2.0 * mix(1.0, 0.5 + life * 1.7, rise);
	float spin = mix(TIME * 2.0 + ph, ph, rise);
	vec2 q = UV - vec2(0.5);
	q = vec2(q.x * cos(spin) - q.y * sin(spin), q.x * sin(spin) + q.y * cos(spin));
	c += (INV_VIEW_MATRIX[0].xyz * q.x + INV_VIEW_MATRIX[1].xyz * q.y) * size;
	VERTEX = (VIEW_MATRIX * vec4(c, 1.0)).xyz;
	NORMAL = vec3(0.0, 0.0, 1.0);
	fade = smoothstep(0.0, 0.12, life) * (1.0 - smoothstep(0.5, 1.0, life)) * mix(0.95, 0.34, rise);
	soft = rise;
}
void fragment() {
	vec2 p = UV - vec2(0.5);
	float blob = clamp(1.0 - length(p) * 2.0, 0.0, 1.0);
	float petal = step(abs(p.x) + abs(p.y) * 1.6, 0.42);
	ALBEDO = pow(COLOR.rgb, vec3(2.2));
	ALPHA = clamp(fade * mix(petal, blob * blob * 1.5, soft), 0.0, 1.0);
}
""", 6.0)


func _puff(bt: Batch, at: Vector3, travel: Vector3, color: Color, phase: float, rate: float) -> void:
	var base := bt.v.size()
	for corner in [Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)]:
		bt.v.append(at)
		bt.n.append(travel)
		bt.c.append(color)
		bt.uv.append(corner)
		bt.uv2.append(Vector2(phase, rate))
	for q in [0, 1, 2, 0, 2, 3]:
		bt.i.append(base + q)


# ───────────────────────── Rótulos ─────────────────────────

func _labels() -> void:
	var c := Zone.PORTAL
	_label("Claro de los Aluxes", Vector3(c.x - 0.95, 5.02, c.y), -PI * 0.5, 0.0062, Color(0.85, 1.0, 0.95), 60.0)
	var s: Array = Zone.STANDS[0]
	_label("SABERES", Vector3(float(s[0]) - float(s[2]) - 0.33, 3.35, s[1]), -PI * 0.5, 0.0068, Color(1.0, 0.88, 0.5), 45.0)
	var b: Array = Zone.STANDS[1]
	_label("MISIONES", Vector3(b[0], 2.84, float(b[1]) + 0.12), 0.0, 0.0056, Color(1.0, 0.88, 0.5), 45.0)
	# Rótulos del mercado y de tres tiendas de los portales: sólo se dibujan de cerca
	var ink := Color(0.24, 0.13, 0.08)
	for i in Zone.STALLS.size():
		var st: Array = Zone.STALLS[i]
		var f := Mod.frame(Vector3(st[0], 0.0, st[1]), _stall_yaw(i))
		_label(STALL_NAMES[i], f * Vector3(0.0, 2.95, 1.63), _stall_yaw(i), 0.0046, ink, 24.0, false)
	var w := Mod.frame(Vector3(-Zone.HALF - 1.0, 0.0, Zone.HALF + 1.0), PI * 0.5)
	for k in SHOP_NAMES.size():
		_label(SHOP_NAMES[k], w * Vector3(14.0 + 6.0 * float(k * 2 + 1) + 3.0, 3.6, -3.2 + 0.19), PI * 0.5, 0.0046, ink, 22.0, false)


func _label(text: String, pos: Vector3, yaw: float, pixel: float, color: Color, range_end: float, outline := true) -> void:
	var label := Label3D.new()
	label.text = text
	label.font = Kit.title_font()
	label.font_size = 64
	label.pixel_size = pixel
	label.outline_size = 14 if outline else 0
	label.modulate = color
	label.outline_modulate = Color(0.04, 0.06, 0.06, 0.95)
	label.position = pos
	label.rotation.y = yaw
	label.visibility_range_end = range_end
	_root.add_child(label)
