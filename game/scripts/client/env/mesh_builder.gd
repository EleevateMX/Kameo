extends RefCounted
## Acumula geometría con color por vértice en una sola malla.
## Todo el decorado de piedra se funde así en muy pocas llamadas de dibujo, y el color
## por vértice permite variación, musgo y oscurecido de las bases sin usar texturas.

var _st := SurfaceTool.new()
var _count := 0
var ao := true            # oscurece la parte baja de cada pieza (da "asiento" sin sombras)
var _seed := 1


func _init() -> void:
	_st.begin(Mesh.PRIMITIVE_TRIANGLES)


func rand() -> float:
	_seed = (_seed * 1103515245 + 12345) % 2147483648
	return float(_seed) / 2147483648.0


func reseed(v: int) -> void:
	_seed = maxi(1, v)


func is_empty() -> bool:
	return _count == 0


func commit() -> ArrayMesh:
	_st.generate_normals()
	return _st.commit()


func tri(a: Vector3, b: Vector3, c: Vector3, ca: Color, cb: Color, cc: Color, smooth := false) -> void:
	_st.set_smooth_group(0 if smooth else -1)
	# (Godot considera frontal el sentido horario: se emite a, c, b)
	_st.set_color(ca)
	_st.add_vertex(a)
	_st.set_color(cc)
	_st.add_vertex(c)
	_st.set_color(cb)
	_st.add_vertex(b)
	_count += 1


## Cuadrilátero a-b-c-d (en sentido antihorario visto desde fuera).
func quad(a: Vector3, b: Vector3, c: Vector3, d: Vector3, ca: Color, cb: Color, cc: Color, cd: Color, smooth := false) -> void:
	tri(a, b, c, ca, cb, cc, smooth)
	tri(a, c, d, ca, cc, cd, smooth)


func _shade(color: Color, t: float) -> Color:
	# t = 0 abajo, 1 arriba
	return color.darkened(0.3 * (1.0 - t)) if ao else color


## Tronco de pirámide de base rectangular: de `bottom` (tamaño xz) en y0 a `top` en y1.
func prism(center: Vector2, y0: float, y1: float, bottom: Vector2, top: Vector2, color: Color, rot := 0.0, top_color: Variant = null, jitter := 0.05) -> void:
	var b: Array[Vector3] = []
	var t: Array[Vector3] = []
	var corners: Array[Vector2] = [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]
	for corner in corners:
		var pb := (corner * bottom * 0.5).rotated(-rot)
		var pt := (corner * top * 0.5).rotated(-rot)
		b.append(Vector3(center.x + pb.x, y0, center.y + pb.y))
		t.append(Vector3(center.x + pt.x, y1, center.y + pt.y))
	var cb := _shade(color, 0.0)
	for i in 4:
		var j := (i + 1) % 4
		var c := color.darkened(rand() * jitter)
		var lo := cb.darkened(rand() * jitter)
		quad(t[i], t[j], b[j], b[i], c, c, lo, lo)
	var tc: Color = top_color if top_color != null else color.lightened(0.06)
	quad(t[3], t[2], t[1], t[0], tc, tc, tc, tc)


func box(center: Vector3, size: Vector3, color: Color, rot := 0.0, top_color: Variant = null) -> void:
	var s := Vector2(size.x, size.z)
	prism(Vector2(center.x, center.z), center.y - size.y * 0.5, center.y + size.y * 0.5, s, s, color, rot, top_color)


## Sólido de revolución: perfil = [Vector2(radio, altura), …] de abajo hacia arriba.
func lathe(center: Vector3, profile: Array, seg: int, color: Color, smooth := true, cap := true, top_color: Variant = null) -> void:
	var h0: float = profile[0].y
	var h1: float = profile[profile.size() - 1].y
	for i in profile.size() - 1:
		var p0: Vector2 = profile[i]
		var p1: Vector2 = profile[i + 1]
		var c0 := _shade(color, inverse_lerp(h0, h1, p0.y) if h1 > h0 else 1.0)
		var c1 := _shade(color, inverse_lerp(h0, h1, p1.y) if h1 > h0 else 1.0)
		for s in seg:
			var a0 := TAU * float(s) / seg
			var a1 := TAU * float(s + 1) / seg
			var v00 := center + Vector3(cos(a0) * p0.x, p0.y, sin(a0) * p0.x)
			var v01 := center + Vector3(cos(a1) * p0.x, p0.y, sin(a1) * p0.x)
			var v10 := center + Vector3(cos(a0) * p1.x, p1.y, sin(a0) * p1.x)
			var v11 := center + Vector3(cos(a1) * p1.x, p1.y, sin(a1) * p1.x)
			quad(v10, v11, v01, v00, c1, c1, c0, c0, smooth)
	if cap:
		var last: Vector2 = profile[profile.size() - 1]
		if last.x > 0.001:
			var tc: Color = top_color if top_color != null else color.lightened(0.06)
			var mid := center + Vector3(0, last.y, 0)
			for s in seg:
				var a0 := TAU * float(s) / seg
				var a1 := TAU * float(s + 1) / seg
				tri(mid, center + Vector3(cos(a1) * last.x, last.y, sin(a1) * last.x), center + Vector3(cos(a0) * last.x, last.y, sin(a0) * last.x), tc, tc, tc)


## Roca facetada: esfera baja deformada.
func rock(center: Vector3, radius: Vector3, color: Color, top_color: Variant = null, rings := 4, seg := 7) -> void:
	var pts := []
	for r in rings + 1:
		var row := []
		var phi := PI * float(r) / rings
		for s in seg:
			var th := TAU * float(s) / seg + (0.5 if r % 2 == 1 else 0.0) * TAU / seg
			var k := 0.78 + rand() * 0.42
			if r == 0 or r == rings:
				k = 0.9
			row.append(center + Vector3(sin(phi) * cos(th) * radius.x, cos(phi) * radius.y, sin(phi) * sin(th) * radius.z) * k)
		pts.append(row)
	var tc: Color = top_color if top_color != null else color.lightened(0.1)
	for r in rings:
		for s in seg:
			var s1 := (s + 1) % seg
			var a: Vector3 = pts[r][s]
			var b: Vector3 = pts[r][s1]
			var c: Vector3 = pts[r + 1][s1]
			var d: Vector3 = pts[r + 1][s]
			var t0 := 1.0 - float(r) / rings
			var t1 := 1.0 - float(r + 1) / rings
			var ca := color.lerp(tc, smoothstep(0.55, 1.0, t0)).darkened(0.28 * (1.0 - t0) + rand() * 0.06)
			var cc := color.lerp(tc, smoothstep(0.55, 1.0, t1)).darkened(0.28 * (1.0 - t1))
			if r > 0:
				tri(a, b, c, ca, ca, cc)
			if r < rings - 1:
				tri(a, c, d, ca, cc, cc)


## Tubo que sigue una curva (raíces, lianas, ramas). radios[i] por punto.
func tube(points: Array, radii: Array, seg: int, color: Color, tip_color: Variant = null) -> void:
	var rings := []
	for i in points.size():
		var p: Vector3 = points[i]
		var dir: Vector3 = (points[mini(i + 1, points.size() - 1)] - points[maxi(i - 1, 0)]).normalized()
		var side := dir.cross(Vector3.UP)
		if side.length() < 0.05:
			side = dir.cross(Vector3.RIGHT)
		side = side.normalized()
		var up := side.cross(dir).normalized()
		var ring := []
		for s in seg:
			var a := TAU * float(s) / seg
			ring.append(p + (side * cos(a) + up * sin(a)) * float(radii[i]))
		rings.append(ring)
	var tc: Color = tip_color if tip_color != null else color
	for i in points.size() - 1:
		var c0 := color.lerp(tc, float(i) / (points.size() - 1))
		var c1 := color.lerp(tc, float(i + 1) / (points.size() - 1))
		for s in seg:
			var s1 := (s + 1) % seg
			quad(rings[i + 1][s], rings[i + 1][s1], rings[i][s1], rings[i][s], c1, c1, c0, c0, true)


## Hoja o pétalo plano de dos caras (banda curvada de `n` tramos).
func blade(base: Vector3, dir: Vector3, length: float, width: float, droop: float, color: Color, tip: Color, n := 4) -> void:
	var side := dir.cross(Vector3.UP).normalized()
	if side.length() < 0.05:
		side = Vector3.RIGHT
	var prev_l := base
	var prev_r := base
	var prev_c := color
	for i in range(1, n + 1):
		var t := float(i) / n
		var p := base + dir * length * t + Vector3.DOWN * droop * t * t * length
		var w := width * sin(t * PI) * 0.5 + (0.0 if i < n else 0.0)
		var l := p - side * w
		var r := p + side * w
		var c := color.lerp(tip, t)
		tri(prev_l, l, r, prev_c, c, c)
		tri(prev_l, r, prev_r, prev_c, c, prev_c)
		tri(prev_l, r, l, prev_c, c, c)        # cara inferior
		tri(prev_l, prev_r, r, prev_c, prev_c, c)
		prev_l = l
		prev_r = r
		prev_c = c
