extends RefCounted
## Lotes de geometría para escenarios baratos: cada forma (caja, cilindro, bola, viga, losa…) se
## añade ya colocada a un lote con su color en los vértices, y al final cada lote es UNA malla con
## UN material: una llamada de dibujo. Es la técnica de la plaza (plaza_builder.gd), sacada aquí
## para el Camino a Motul y el arco de salida, que se construyen aparte.
##
##   var sb := SceneBatch.new()
##   sb.box("obra", Vector3(2, 1, 2), color, pos)
##   sb.commit("obra", sb.solid(), parent, true)

const NONE := Color(0, 0, 0, 0)

class Batch:
	var v := PackedVector3Array()
	var n := PackedVector3Array()
	var c := PackedColorArray()
	var i := PackedInt32Array()
	var uv := PackedVector2Array()
	var uv2 := PackedVector2Array()

var stats := {}                  # lote -> triángulos
var _batches := {}
var _unit := {}
var _solid: StandardMaterial3D
var _glow: StandardMaterial3D
var _add: StandardMaterial3D


func batch(name: String) -> Batch:
	if not _batches.has(name):
		_batches[name] = Batch.new()
	return _batches[name]


func has(name: String) -> bool:
	return _batches.has(name)


func _unit_arrays(key: String) -> Array:
	if _unit.has(key):
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


## Añade una forma unitaria (entre −0.5 y 0.5 de alto) al lote, ya colocada. Con dos colores hace
## un degradado de abajo arriba: da volumen sin texturas ni luces.
func emit(b: String, key: String, basis: Basis, scale: Vector3, pos: Vector3, top: Color, bottom := NONE) -> void:
	var bt := batch(b)
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
func box(b: String, size: Vector3, color: Color, pos: Vector3, yaw := 0.0, bottom := NONE) -> void:
	emit(b, "box", Basis(Vector3.UP, yaw) if yaw != 0.0 else Basis.IDENTITY, size, pos, color, bottom)


## Cilindro o cono apoyado en `pos` (`top` = radio de arriba; −1 = el mismo que abajo).
func cyl(b: String, radius: float, height: float, color: Color, pos: Vector3, sides := 8, top := -1.0, bottom := NONE, basis := Basis.IDENTITY) -> void:
	var ratio := 1.0 if top < 0.0 else snappedf(top / radius, 0.01)
	emit(b, "cyl|%d|%s" % [sides, ratio], basis, Vector3(radius, height, radius), pos + basis * Vector3(0, height * 0.5, 0), color, bottom)


## Bola (o copa de árbol, achatada) centrada en `pos`.
func ball(b: String, radius: float, color: Color, pos: Vector3, squash := 1.0, bottom := NONE, sides := 8) -> void:
	emit(b, "ball|%d" % sides, Basis.IDENTITY, Vector3(radius * 2.0, radius * 2.0 * squash, radius * 2.0), pos, color, bottom)


## Viga entre dos puntos (cuerdas, travesaños, ramas).
func beam(b: String, from: Vector3, to: Vector3, thick: float, color: Color, width := -1.0) -> void:
	var d := to - from
	var len := d.length()
	if len < 0.001:
		return
	var z := d / len
	var x := Vector3.UP.cross(z)
	x = Vector3.RIGHT if x.length() < 0.001 else x.normalized()
	emit(b, "box", Basis(x, z.cross(x), z), Vector3(thick if width < 0.0 else width, thick, len), (from + to) * 0.5, color, NONE)


## Hoja o penca: un cono fino que sale de `from` en la dirección `dir`.
func spike(b: String, from: Vector3, dir: Vector3, length: float, radius: float, color: Color, tip := NONE, sides := 4) -> void:
	var y := dir.normalized()
	var x := y.cross(Vector3.UP)
	x = Vector3.RIGHT if x.length() < 0.001 else x.normalized()
	var basis := Basis(x, y, x.cross(y))
	emit(b, "cyl|%d|0.06" % sides, basis, Vector3(radius, length, radius), from + y * (length * 0.5), tip if tip.a > 0.0 else color, color)


## Cuadrilátero suelto (a, b, c, d en orden), con su normal.
func quad(b: String, p0: Vector3, p1: Vector3, p2: Vector3, p3: Vector3, color: Color, color_far := NONE) -> void:
	var bt := batch(b)
	var base := bt.v.size()
	var normal := (p1 - p0).cross(p3 - p0).normalized()
	if normal.dot(Vector3.UP) < 0.0 and absf(normal.y) > 0.5:
		normal = -normal
	var far := color if color_far.a <= 0.0 else color_far
	var k := 0
	for p in [p0, p1, p2, p3]:
		bt.v.append(p)
		bt.n.append(normal)
		bt.c.append(color if k < 2 else far)
		k += 1
	for q in [0, 1, 2, 0, 2, 3]:
		bt.i.append(base + q)
	for q in [0, 2, 1, 0, 3, 2]:   # por las dos caras
		bt.i.append(base + q)


## Losa plana (mira hacia arriba) entre dos esquinas.
func tile(b: String, x0: float, z0: float, x1: float, z1: float, y: float, color: Color) -> void:
	var bt := batch(b)
	var base := bt.v.size()
	for p in [Vector3(x0, y, z0), Vector3(x1, y, z0), Vector3(x1, y, z1), Vector3(x0, y, z1)]:
		bt.v.append(p)
		bt.n.append(Vector3.UP)
		bt.c.append(color)
	for k in [0, 1, 2, 0, 2, 3]:
		bt.i.append(base + k)


## Cinta plana a lo largo de una línea de puntos (un camino): `half` de medio ancho, a la altura `y`.
## `tone` (opcional) devuelve el color de cada tramo según su índice.
func ribbon(b: String, points: Array, half: float, y: float, color: Color, edge := NONE, jitter := 0.0) -> void:
	var bt := batch(b)
	var side_c := color if edge.a <= 0.0 else edge
	for k in range(points.size() - 1):
		var a: Vector2 = points[k]
		var c: Vector2 = points[k + 1]
		var dir := (c - a).normalized()
		var nrm := Vector2(-dir.y, dir.x) * half
		var tone := color.lightened(jitter * fposmod(sin(float(k) * 12.9898) * 43758.5453, 1.0) - jitter * 0.5) if jitter > 0.0 else color
		var base := bt.v.size()
		for p in [a - nrm, a, a + nrm, c - nrm, c, c + nrm]:
			bt.v.append(Vector3(p.x, y, p.y))
			bt.n.append(Vector3.UP)
		for col in [side_c, tone, side_c, side_c, tone, side_c]:
			bt.c.append(col)
		for q in [0, 3, 1, 1, 3, 4, 1, 4, 2, 2, 4, 5]:
			bt.i.append(base + q)


## Corona plana (o disco, con r_in = 0) que mira hacia arriba.
func ring(b: String, center: Vector3, r_in: float, r_out: float, color: Color, sides := 32, outer := NONE) -> void:
	var bt := batch(b)
	var out_c := color if outer.a <= 0.0 and outer == NONE else outer
	if r_in <= 0.0:
		fan(b, center, r_out, color, out_c, sides)
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


func fan(b: String, center: Vector3, radius: float, color: Color, edge: Color, sides: int) -> void:
	var bt := batch(b)
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
func pool(b: String, pos: Vector3, radius: float, color: Color, strength := 0.3) -> void:
	fan(b, Vector3(pos.x, pos.y + 0.035, pos.z), radius, Color(color.r * strength, color.g * strength, color.b * strength), Color(0, 0, 0), 16)


# ───────────────────────── Mallas y materiales ─────────────────────────

func mesh_of(name: String) -> ArrayMesh:
	var bt: Batch = _batches[name]
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


## Convierte un lote en una malla con su material y lo cuelga de `parent`. Devuelve null si el
## lote está vacío. El lote se olvida: no se puede seguir añadiendo.
func commit(name: String, mat: Material, parent: Node, shadow := false) -> MeshInstance3D:
	if not _batches.has(name) or (_batches[name] as Batch).i.is_empty():
		return null
	var mi := MeshInstance3D.new()
	mi.name = name
	mi.mesh = mesh_of(name)
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadow else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	stats[name] = (_batches[name] as Batch).i.size() / 3
	_batches.erase(name)
	return mi


## Malla con sombreador propio (aves, mariposas, agua).
func commit_shader(name: String, code: String, parent: Node, margin := 0.0) -> MeshInstance3D:
	var sh := Shader.new()
	sh.code = code
	var mat := ShaderMaterial.new()
	mat.shader = sh
	var mi := commit(name, mat, parent, false)
	if mi != null:
		mi.extra_cull_margin = margin
	return mi


## Material sombreado único: el color va en los vértices.
func solid() -> StandardMaterial3D:
	if _solid == null:
		_solid = StandardMaterial3D.new()
		_solid.vertex_color_use_as_albedo = true
		_solid.vertex_color_is_srgb = true
		_solid.roughness = 1.0
		_solid.metallic_specular = 0.0
		_solid.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	return _solid


## Sin sombrear: faroles, jade, ventanas encendidas (no hay luces de verdad).
func glow() -> StandardMaterial3D:
	if _glow == null:
		_glow = StandardMaterial3D.new()
		_glow.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_glow.vertex_color_use_as_albedo = true
		_glow.vertex_color_is_srgb = true
	return _glow


## Sumado encima: charcos de luz.
func additive() -> StandardMaterial3D:
	if _add == null:
		_add = StandardMaterial3D.new()
		_add.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_add.vertex_color_use_as_albedo = true
		_add.vertex_color_is_srgb = true
		_add.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		_add.disable_fog = true
	return _add


## Cúpula de cielo: sin sombrear, sin niebla, por las dos caras.
func sky() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.vertex_color_use_as_albedo = true
	m.vertex_color_is_srgb = true
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.disable_fog = true
	return m
