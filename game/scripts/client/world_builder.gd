extends RefCounted
## Construye el Claro de los Aluxes a partir de la misma definición que usa el
## servidor (world_def.gd). Todo es procedimental y con color por vértice: sin texturas.
##
## Para mantener pocas llamadas de dibujo, toda la piedra se funde en una malla, todas
## las incrustaciones luminosas en otra, y la vegetación va instanciada (MultiMesh).

const World := preload("res://scripts/shared/world_def.gd")
const Avatar := preload("res://scripts/client/avatar.gd")
const MB := preload("res://scripts/client/env/mesh_builder.gd")

const LIME := Color(0.86, 0.8, 0.66)          # piedra caliza
const LIME_DARK := Color(0.63, 0.59, 0.5)
const LIME_WARM := Color(0.9, 0.78, 0.58)
const MOSS := Color(0.36, 0.55, 0.27)
const JADE := Color(0.18, 0.95, 0.72)
const AMBER := Color(1.0, 0.66, 0.2)
const MAGENTA := Color(0.98, 0.2, 0.6)
const TURQ := Color(0.25, 0.85, 0.95)
const GOLD := Color(1.0, 0.82, 0.3)
const BARK := Color(0.5, 0.38, 0.27)
const PLATE_COLORS := [JADE, TURQ, AMBER, MAGENTA]

var gate_bars: Node3D
var gate_light: OmniLight3D
var seal_veil: MeshInstance3D
var glyph: Node3D
var sun: DirectionalLight3D
var env: Environment
var fireflies: CPUParticles3D

var _stone := MB.new()
var _glow := MB.new()
var _vc_mat: StandardMaterial3D
var _glow_mat: ShaderMaterial
var _foliage_mat: ShaderMaterial
var _seal_mat: ShaderMaterial
var _plate_glyphs: Array[MeshInstance3D] = []
var _plate_beams: Array[MeshInstance3D] = []
var _plate_on: Array[bool] = [false, false, false, false]
var _plate_mats: Array[ShaderMaterial] = []
var _flame_light: OmniLight3D
var _extras: Array[Node3D] = []     # se ocultan en calidad baja
var _extras_min: Array[Node3D] = [] # se ocultan además en calidad mínima
var _seed := 77123


func _rand() -> float:
	_seed = (_seed * 1103515245 + 12345) % 2147483648
	return float(_seed) / 2147483648.0


func build(root: Node3D) -> void:
	_materials()
	_environment(root)
	_backdrop(root)
	_terrain(root)
	_water(root)
	_plaza(root)
	_pyramid()
	_sanctuary(root)
	_ledge(root)
	_ruins_and_rocks()
	_markers(root)
	_flora(root)
	_particles(root)
	# Una malla para toda la piedra y otra para todo lo que brilla
	var stone := Avatar.part(_stone.commit(), _vc_mat, Vector3.ZERO)
	root.add_child(stone)
	var glow := Avatar.part(_glow.commit(), _glow_mat, Vector3.ZERO)
	glow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(glow)


func _materials() -> void:
	_vc_mat = StandardMaterial3D.new()
	_vc_mat.vertex_color_use_as_albedo = true
	_vc_mat.roughness = 0.95
	_glow_mat = _emissive(1.5)
	var fol := Shader.new()
	fol.code = """
shader_type spatial;
render_mode cull_disabled;
uniform float sway = 0.05;
void vertex() {
	vec3 w = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float k = max(VERTEX.y, 0.0);
	VERTEX.x += sin(TIME * 1.3 + w.x * 0.6 + w.z * 0.4) * sway * k;
	VERTEX.z += cos(TIME * 1.1 + w.z * 0.5) * sway * 0.6 * k;
}
void fragment() {
	ALBEDO = COLOR.rgb;
	ROUGHNESS = 1.0;
	BACKLIGHT = COLOR.rgb * 0.25;
}
"""
	_foliage_mat = ShaderMaterial.new()
	_foliage_mat.shader = fol


static func _emissive(energy: float) -> ShaderMaterial:
	var sh := Shader.new()
	sh.code = """
shader_type spatial;
uniform float energy = 1.5;
uniform vec3 tint : source_color = vec3(1.0);
void fragment() {
	ALBEDO = COLOR.rgb * tint * 0.35;
	EMISSION = COLOR.rgb * tint * energy;
	ROUGHNESS = 0.5;
}
"""
	var m := ShaderMaterial.new()
	m.shader = sh
	m.set_shader_parameter("energy", energy)
	return m


# ───────────────────────── Cielo, luz y fondo ─────────────────────────

func _environment(root: Node3D) -> void:
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.04, 0.38, 0.78)
	sky_mat.sky_horizon_color = Color(1.0, 0.8, 0.54)
	sky_mat.sky_curve = 0.1
	sky_mat.sky_energy_multiplier = 1.15
	sky_mat.ground_bottom_color = Color(0.05, 0.16, 0.13)
	sky_mat.ground_horizon_color = Color(0.98, 0.7, 0.46)
	sky_mat.sun_angle_max = 34.0
	sky_mat.sun_curve = 0.06
	var sky := Sky.new()
	sky.sky_material = sky_mat
	env = Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	# Luz de relleno uniforme y algo fría: las sombras quedan azuladas, nunca negras
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.62, 0.76, 0.8)
	env.ambient_light_energy = 0.95
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 0.98
	env.tonemap_white = 4.5
	env.fog_enabled = true
	env.fog_light_color = Color(0.95, 0.84, 0.66)
	env.fog_density = 0.0028
	env.fog_sky_affect = 0.2
	env.glow_enabled = true
	env.glow_intensity = 0.45
	env.glow_bloom = 0.08
	env.glow_hdr_threshold = 1.0
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.18
	env.adjustment_contrast = 1.06
	var we := WorldEnvironment.new()
	we.environment = env
	root.add_child(we)

	sun = DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-33, 128, 0)
	sun.light_color = Color(1.0, 0.88, 0.68)
	sun.light_energy = 1.2
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 48.0
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	sun.shadow_opacity = 0.62
	sun.shadow_blur = 1.6
	sun.shadow_bias = 0.06
	root.add_child(sun)


## Capas de fondo: selva lejana, una pirámide en la bruma y nubes.
func _backdrop(root: Node3D) -> void:
	var far := MB.new()
	far.ao = false
	for layer in 2:
		var radius := 118.0 + layer * 60.0
		var base := Color(0.2, 0.46, 0.4) if layer == 0 else Color(0.5, 0.68, 0.72)
		var seg := 80
		var heights := []
		for i in seg + 1:
			var a := TAU * float(i % seg) / seg
			heights.append(24.0 + layer * 20.0 + sin(a * 5.0 + layer * 2.0) * 7.0 + sin(a * 13.0) * 4.0 + sin(a * 29.0 + 1.3) * 2.0)
		for i in seg:
			var a0 := TAU * float(i) / seg
			var a1 := TAU * float(i + 1) / seg
			var b0 := Vector3(cos(a0) * radius, -6.0, sin(a0) * radius)
			var b1 := Vector3(cos(a1) * radius, -6.0, sin(a1) * radius)
			var t0 := b0 + Vector3(0, float(heights[i]) + 6.0, 0)
			var t1 := b1 + Vector3(0, float(heights[i + 1]) + 6.0, 0)
			var top := base.lerp(Color(1.0, 0.86, 0.66), 0.28)   # crestas bañadas por el sol
			far.quad(t1, t0, b0, b1, top, top, base, base, true)
	# pirámide lejana, al noreste
	var p := Vector3(88.0, 10.0, -84.0)
	var c := Color(0.62, 0.7, 0.72)
	for i in 5:
		var s := 40.0 - i * 7.0
		far.prism(Vector2(p.x, p.z), p.y + i * 7.0, p.y + (i + 1) * 7.0, Vector2(s, s), Vector2(s - 2.5, s - 2.5), c.lerp(Color(1.0, 0.86, 0.68), 0.12 + i * 0.05), 0.5)
	far.prism(Vector2(p.x, p.z), p.y + 35.0, p.y + 43.0, Vector2(8, 8), Vector2(7, 7), Color(1.0, 0.88, 0.7), 0.5)
	var fm := StandardMaterial3D.new()
	fm.vertex_color_use_as_albedo = true
	fm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	fm.disable_fog = true
	var mi := Avatar.part(far.commit(), fm, Vector3.ZERO)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mi)

	# nubes: racimos aplastados, sin sombreado
	var clouds := MB.new()
	clouds.ao = false
	clouds.reseed(4411)
	for i in 11:
		var a := TAU * float(i) / 11.0 + clouds.rand() * 0.4
		var r := 150.0 + clouds.rand() * 60.0
		var at := Vector3(cos(a) * r, 52.0 + clouds.rand() * 30.0, sin(a) * r)
		var warm := Color(1.0, 0.9, 0.8).lerp(Color(1.0, 0.72, 0.6), clouds.rand())
		for k in 4:
			var off := Vector3((clouds.rand() - 0.5) * 34.0, (clouds.rand() - 0.5) * 5.0, (clouds.rand() - 0.5) * 18.0)
			var sz := 9.0 + clouds.rand() * 9.0
			clouds.rock(at + off, Vector3(sz * 1.7, sz * 0.5, sz), warm.darkened(0.12), warm, 4, 8)
	var cm := StandardMaterial3D.new()
	cm.vertex_color_use_as_albedo = true
	cm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	cm.disable_fog = true
	var cmi := Avatar.part(clouds.commit(), cm, Vector3.ZERO)
	cmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(cmi)
	_extras_min.append(cmi)


# ───────────────────────── Terreno ─────────────────────────

static func _hash(x: float, z: float) -> float:
	var v := sin(x * 12.9898 + z * 78.233) * 43758.5453
	return v - floorf(v)


static func _path_weight(x: float, z: float, n: float) -> float:
	var w := 0.0
	var p := Vector2(x, z)
	for target in [World.PYRAMID + Vector2(0, 9.5), World.SANCTUARY - Vector2(7, 0), World.CENOTE + Vector2(8.5, -6), World.LEDGE - Vector2(4, 4)]:
		var t: Vector2 = target
		var k := clampf(p.dot(t) / t.length_squared(), 0.0, 1.0)
		var d := (p - t * k).length()
		w = maxf(w, 1.0 - smoothstep(0.9, 2.3, d + n * 0.7))
	return w


func _terrain_color(x: float, z: float, h: float) -> Color:
	var n := _hash(floorf(x * 0.9), floorf(z * 0.9))
	var n2 := _hash(floorf(x * 0.23) + 7.0, floorf(z * 0.23))
	# hierba con manchas cálidas y frías
	var grass := Color(0.32, 0.66, 0.2).lerp(Color(0.18, 0.5, 0.18), n)
	grass = grass.lerp(Color(0.56, 0.72, 0.24), n2 * 0.45)
	var c := grass
	c = c.lerp(Color(0.72, 0.56, 0.36), _path_weight(x, z, n) * 0.9)
	var dp := Vector2(x, z).length()
	# la plaza va enlosada aparte: debajo, tierra apisonada
	c = c.lerp(Color(0.6, 0.52, 0.4), 1.0 - smoothstep(9.2, 10.4, dp))
	var dpy := maxf(absf(x - World.PYRAMID.x), absf(z - World.PYRAMID.y))
	c = c.lerp(Color(0.66, 0.58, 0.44), (1.0 - smoothstep(9.0, 11.5, dpy)) * 0.85)
	var dsan := maxf(absf(x - World.SANCTUARY.x), absf(z - World.SANCTUARY.y))
	c = c.lerp(Color(0.62, 0.56, 0.48), (1.0 - smoothstep(7.0, 9.5, dsan)) * 0.8)
	# orilla y fondo del cenote
	var dc := Vector2(x - World.CENOTE.x, z - World.CENOTE.y).length() / World.CENOTE_R
	c = c.lerp(Color(0.9, 0.84, 0.66), 1.0 - smoothstep(0.98, 1.4, dc))
	if h < World.WATER_LEVEL:
		c = c.lerp(Color(0.08, 0.42, 0.46), clampf((World.WATER_LEVEL - h) * 0.9, 0.0, 1.0))
	# laderas del borde: más oscuras y azuladas
	c = c.lerp(Color(0.12, 0.36, 0.2), smoothstep(40.0, 58.0, dp))
	return c


## Altura VISUAL del terreno. Dentro del claro es exactamente la del servidor; fuera
## (donde nadie puede pisar) se suaviza en lomas bajas para dejar ver el horizonte.
static func _ground(x: float, z: float) -> float:
	var h := World.terrain_h(x, z)
	var r := Vector2(x, z).length()
	if r <= World.RADIUS:
		return h
	var rim := 5.8 + (r - World.RADIUS) * 0.16 + sin(x * 0.21) * 0.9 + cos(z * 0.17) * 0.9
	return minf(h, rim)


func _terrain(root: Node3D) -> void:
	var n := 150
	var half := 78.0
	var step := half * 2.0 / n
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for iz in n + 1:
		for ix in n + 1:
			var x := -half + ix * step
			var z := -half + iz * step
			var h := _ground(x, z)
			var e := 0.4
			var nx := _ground(x - e, z) - _ground(x + e, z)
			var nz := _ground(x, z - e) - _ground(x, z + e)
			st.set_color(_terrain_color(x, z, h))
			st.set_normal(Vector3(nx, 2.0 * e, nz).normalized())
			st.add_vertex(Vector3(x, h, z))
	for iz in n:
		for ix in n:
			var i := iz * (n + 1) + ix
			st.add_index(i)
			st.add_index(i + 1)
			st.add_index(i + n + 2)
			st.add_index(i)
			st.add_index(i + n + 2)
			st.add_index(i + n + 1)
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.roughness = 1.0
	var ground := Avatar.part(st.commit(), m, Vector3.ZERO)
	# el suelo recibe sombras pero no las proyecta (ahorra el pase de sombras del terreno entero)
	ground.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(ground)

	# Losas irregulares a lo largo de los senderos
	_stone.reseed(9931)
	for target in [World.PYRAMID + Vector2(0, 9.5), World.SANCTUARY - Vector2(7.5, 0), World.CENOTE + Vector2(8.5, -6), World.LEDGE - Vector2(4, 4)]:
		var t: Vector2 = target
		var steps := int(t.length() / 1.25)
		for i in range(8, steps):
			var p := t * (float(i) / steps) + Vector2(_stone.rand() - 0.5, _stone.rand() - 0.5) * 1.1
			if p.length() < 10.0:
				continue
			var y := World.terrain_h(p.x, p.y)
			var s := 0.55 + _stone.rand() * 0.5
			_stone.prism(p, y - 0.1, y + 0.05, Vector2(s * 1.3, s), Vector2(s * 1.2, s * 0.9), LIME_DARK.lerp(LIME, _stone.rand()), _stone.rand() * TAU, null, 0.1)


# ───────────────────────── Cenote ─────────────────────────

func _water(root: Node3D) -> void:
	var c := World.CENOTE
	var disc := CylinderMesh.new()
	disc.top_radius = World.CENOTE_R * 1.32
	disc.bottom_radius = disc.top_radius
	disc.height = 0.02
	disc.radial_segments = 56
	var sh := Shader.new()
	sh.code = """
shader_type spatial;
render_mode blend_mix, cull_back;
uniform vec2 center;
uniform float radius;
varying vec3 wpos;
void vertex() { wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }
float caustic(vec2 p, float t) {
	float a = sin(p.x * 2.1 + t) + sin(p.y * 2.3 - t * 1.2) + sin((p.x + p.y) * 1.6 + t * 0.7) + sin(length(p) * 2.6 - t * 1.4);
	return pow(clamp(0.5 + 0.25 * a, 0.0, 1.0), 4.0);
}
void fragment() {
	float d = clamp(length(wpos.xz - center) / radius, 0.0, 1.0);
	vec3 deep = vec3(0.01, 0.22, 0.42);
	vec3 mid = vec3(0.05, 0.62, 0.72);
	vec3 shallow = vec3(0.45, 0.98, 0.9);
	vec3 col = mix(deep, mid, smoothstep(0.0, 0.55, d));
	col = mix(col, shallow, smoothstep(0.55, 0.98, d));
	float ca = caustic(wpos.xz * 0.9, TIME * 0.9) * (0.35 + 0.65 * d);
	float foam = smoothstep(0.9, 0.99, d) * (0.6 + 0.4 * sin(d * 60.0 - TIME * 2.0));
	ALBEDO = col + ca * 0.5 + foam * 0.35;
	EMISSION = col * 0.35 + vec3(0.3, 1.0, 0.9) * ca * 0.5;
	ALPHA = mix(0.93, 0.55, smoothstep(0.6, 1.0, d));
	ROUGHNESS = 0.05;
	SPECULAR = 0.9;
}
"""
	var mat := ShaderMaterial.new()
	mat.shader = sh
	mat.set_shader_parameter("center", c)
	mat.set_shader_parameter("radius", World.CENOTE_R * 1.32)
	var mi := Avatar.part(disc, mat, Vector3(c.x, World.WATER_LEVEL, c.y))
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mi)

	# Rocas de caliza en la orilla (sólo donde no estorban el paso: bajas)
	_stone.reseed(5512)
	for i in 26:
		var a := TAU * float(i) / 26.0 + _stone.rand() * 0.2
		var r := World.CENOTE_R * (1.36 + _stone.rand() * 0.14)
		var p := Vector2(c.x + cos(a) * r, c.y + sin(a) * r)
		var y := World.terrain_h(p.x, p.y)
		var s := 0.35 + _stone.rand() * 0.45
		_stone.rock(Vector3(p.x, y + s * 0.2, p.y), Vector3(s * 1.4, s * 0.55, s * 1.1), LIME_DARK, LIME.lerp(MOSS, _stone.rand() * 0.6))

	# Nenúfares con flor
	var pads := MB.new()
	pads.ao = false
	pads.reseed(812)
	for i in 9:
		var a := pads.rand() * TAU
		var r := World.CENOTE_R * (0.25 + pads.rand() * 0.75)
		var p := Vector3(c.x + cos(a) * r, World.WATER_LEVEL + 0.03, c.y + sin(a) * r)
		var s := 0.45 + pads.rand() * 0.4
		pads.lathe(p, [Vector2(s, 0.0), Vector2(s * 0.96, 0.03)], 9, Color(0.2, 0.62, 0.3), false, true, Color(0.3, 0.75, 0.36))
		if i % 2 == 0:
			for k in 6:
				var pa := TAU * float(k) / 6.0
				pads.blade(p + Vector3(0, 0.05, 0), Vector3(cos(pa), 0.9, sin(pa)).normalized(), 0.28, 0.16, 0.5, Color(1.0, 0.75, 0.86), Color(1.0, 0.96, 0.98), 3)
	var pmi := Avatar.part(pads.commit(), _vc_mat, Vector3.ZERO)
	pmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(pmi)

	# Haces de luz sobre el agua
	var shafts := MB.new()
	shafts.ao = false
	for i in 3:
		var base := Vector3(c.x - 3.0 + i * 3.2, World.WATER_LEVEL, c.y - 1.0 + i * 1.4)
		var top := base + Vector3(5.0, 16.0, -4.0)
		var w0 := 1.0 + i * 0.25
		var side := Vector3(1, 0, 0.4).normalized()
		var lo := Color(0.7, 1.0, 0.9, 0.0)
		var hi := Color(1.0, 0.95, 0.7, 0.0)
		shafts.quad(top - side * w0 * 0.4, top + side * w0 * 0.4, base + side * w0, base - side * w0, hi, hi, lo, lo, true)
		shafts.quad(top + side * w0 * 0.4, top - side * w0 * 0.4, base - side * w0, base + side * w0, hi, hi, lo, lo, true)
	var sm := ShaderMaterial.new()
	var ssh := Shader.new()
	ssh.code = """
shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled;
void fragment() {
	ALBEDO = COLOR.rgb;
	ALPHA = 0.06 * (0.75 + 0.25 * sin(TIME * 0.7 + COLOR.r * 9.0));
}
"""
	sm.shader = ssh
	var smi := Avatar.part(shafts.commit(), sm, Vector3.ZERO)
	smi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(smi)
	_extras.append(smi)


# ───────────────────────── Glifos inventados ─────────────────────────

## Glifo propio de ALUX: rejilla simétrica de trazos (barras, puntos, escuadras, marcos).
## `right` y `up` definen el plano tal como lo ve quien lo mira de frente.
func _glyph_on(mb: MB, origin: Vector3, right: Vector3, up: Vector3, size: float, seed_v: int, color: Color) -> void:
	var out := right.cross(up).normalized() * 0.03
	var s := seed_v
	var cell := size / 3.0
	for row in 3:
		for col in 2:
			s = (s * 1103515245 + 12345) % 2147483648
			var kind := (s >> 8) % 6
			for mirror in ([1.0, -1.0] if col == 0 else [0.0]):
				var mir: float = mirror
				var cx: float = (-cell if col == 0 else 0.0) * (mir if col == 0 else 1.0)
				var cy := (row - 1) * cell
				var rects := []
				match kind:
					0: rects = [[0.0, 0.0, 0.8, 0.22]]
					1: rects = [[0.0, 0.0, 0.22, 0.8]]
					2: rects = [[0.0, 0.0, 0.34, 0.34]]
					3: rects = [[0.0, -0.28, 0.8, 0.2], [0.3 * (mir if col == 0 else 1.0), 0.06, 0.2, 0.52]]
					4: rects = [[0.0, 0.3, 0.8, 0.16], [0.0, -0.3, 0.8, 0.16], [-0.32, 0.0, 0.16, 0.76], [0.32, 0.0, 0.16, 0.76]]
					5: rects = [[0.0, 0.22, 0.6, 0.18], [0.0, -0.22, 0.6, 0.18]]
				for r in rects:
					var c: Vector3 = origin + out + right * (cx + float(r[0]) * cell) + up * (cy + float(r[1]) * cell)
					var hw: Vector3 = right * (float(r[2]) * cell * 0.5)
					var hh: Vector3 = up * (float(r[3]) * cell * 0.5)
					mb.quad(c - hw - hh, c + hw - hh, c + hw + hh, c - hw + hh, color, color, color, color)


## Estela tallada (decorativa, pegada a un muro o columna): losa con remate curvo y glifo.
func _stela(at: Vector3, yaw: float, height: float, seed_v: int, color: Color) -> void:
	var c := Vector2(at.x, at.z)
	_stone.prism(c, at.y - 0.3, at.y + height * 0.82, Vector2(0.95, 0.34), Vector2(0.86, 0.3), LIME, yaw)
	_stone.prism(c, at.y + height * 0.82, at.y + height, Vector2(0.86, 0.3), Vector2(0.5, 0.26), LIME.lightened(0.05), yaw)
	_stone.prism(c, at.y - 0.3, at.y + 0.22, Vector2(1.2, 0.56), Vector2(1.1, 0.5), LIME_DARK, yaw)
	var right := Vector3(cos(yaw), 0, -sin(yaw))
	var fwd := Vector3(sin(yaw), 0, cos(yaw))
	_glyph_on(_glow, at + Vector3(0, height * 0.5, 0) + fwd * 0.17, right, Vector3.UP, 0.62, seed_v, color)
	_glyph_on(_glow, at + Vector3(0, height * 0.5, 0) - fwd * 0.17, -right, Vector3.UP, 0.62, seed_v + 7, color)


# ───────────────────────── Plaza y brasero ─────────────────────────

func _plaza(root: Node3D) -> void:
	_stone.reseed(31337)
	# Enlosado en anillos, con algunas losas de jade
	var ring_r := 1.9
	var ring := 0
	while ring_r < 9.3:
		var depth := 0.95 if ring % 3 != 2 else 0.5
		var tiles := int(TAU * ring_r / (1.25 if depth > 0.6 else 0.7))
		var off := _stone.rand()
		for i in tiles:
			var a0 := TAU * (float(i) + off + 0.04) / tiles
			var a1 := TAU * (float(i) + off + 0.96) / tiles
			var r0 := ring_r + 0.03
			var r1 := ring_r + depth - 0.03
			var y := 0.045 + _stone.rand() * 0.02
			var col := LIME.lerp(LIME_DARK, _stone.rand() * 0.7)
			if ring % 3 == 2:
				col = LIME_WARM.lerp(LIME_DARK, _stone.rand() * 0.4)
			var p00 := Vector3(cos(a0) * r0, y, sin(a0) * r0)
			var p01 := Vector3(cos(a1) * r0, y, sin(a1) * r0)
			var p10 := Vector3(cos(a0) * r1, y, sin(a0) * r1)
			var p11 := Vector3(cos(a1) * r1, y, sin(a1) * r1)
			_stone.quad(p00, p01, p11, p10, col, col, col, col)
			if ring % 3 == 2 and i % 4 == 0:
				var gy := y + 0.012
				var m0 := (a0 + a1) * 0.5
				var gc := Vector3(cos(m0) * (r0 + r1) * 0.5, gy, sin(m0) * (r0 + r1) * 0.5)
				var tr := Vector3(-sin(m0), 0, cos(m0)) * 0.16
				var rr := Vector3(cos(m0), 0, sin(m0)) * 0.16
				_glow.quad(gc - rr, gc + tr, gc + rr, gc - tr, JADE, JADE, JADE, JADE)
		ring_r += depth
		ring += 1
	# Aro de jade incrustado
	for i in 64:
		var a0 := TAU * float(i) / 64.0
		var a1 := TAU * float(i + 1) / 64.0
		var r0 := 9.35
		var r1 := 9.6
		_glow.quad(Vector3(cos(a0) * r0, 0.07, sin(a0) * r0), Vector3(cos(a1) * r0, 0.07, sin(a1) * r0),
			Vector3(cos(a1) * r1, 0.07, sin(a1) * r1), Vector3(cos(a0) * r1, 0.07, sin(a0) * r1), JADE, JADE, JADE, JADE)

	# Brasero: pedestal escalonado, cuenco tallado y cuatro glifos
	_stone.lathe(Vector3.ZERO, [Vector2(1.75, 0.0), Vector2(1.75, 0.16), Vector2(1.42, 0.16), Vector2(1.42, 0.34), Vector2(1.12, 0.34),
		Vector2(0.72, 0.62), Vector2(0.62, 0.95), Vector2(1.0, 1.25), Vector2(1.14, 1.42), Vector2(1.05, 1.46), Vector2(0.82, 1.3)], 12, LIME, false, false)
	_stone.lathe(Vector3.ZERO, [Vector2(0.84, 1.26), Vector2(0.84, 1.3)], 12, Color(0.2, 0.12, 0.08), false, true, Color(0.25, 0.13, 0.07))
	for i in 4:
		var a := PI * 0.25 + i * PI * 0.5
		var n := Vector3(cos(a), 0, sin(a))
		_glyph_on(_glow, n * 1.06 + Vector3(0, 1.3, 0), Vector3(-n.z, 0, n.x), Vector3.UP, 0.34, 40 + i, AMBER)
	var flame := _flame(1.25, 1.9)
	flame.position = Vector3(0, 1.3, 0)
	root.add_child(flame)
	_flame_light = OmniLight3D.new()
	_flame_light.light_color = Color(1.0, 0.7, 0.35)
	_flame_light.light_energy = 1.3
	_flame_light.omni_range = 9.0
	_flame_light.position = Vector3(0, 2.3, 0)
	root.add_child(_flame_light)

	# Columnas talladas con banda de jade y remate
	var k := 0
	for c in World.cylinders():
		if c.kind != "pillar":
			continue
		var y := World.terrain_h(c.x, c.z)
		var at := Vector3(c.x, y, c.z)
		var r: float = c.r
		_stone.lathe(at, [Vector2(r * 1.35, -0.2), Vector2(r * 1.35, 0.3), Vector2(r * 1.05, 0.42), Vector2(r * 0.95, 1.5), Vector2(r * 1.08, 1.58),
			Vector2(r * 1.08, 1.8), Vector2(r * 0.92, 1.88), Vector2(r * 0.86, 3.0), Vector2(r * 1.3, 3.25), Vector2(r * 1.3, 3.5)], 8, LIME, false, true)
		_glow.lathe(at + Vector3(0, 1.62, 0), [Vector2(r * 1.1, 0.0), Vector2(r * 1.1, 0.14)], 8, JADE, false, false)
		# cuenco con llama pequeña en lo alto de dos columnas alternas
		if k % 2 == 0:
			var f := _flame(0.5, 0.8)
			f.position = at + Vector3(0, 3.5, 0)
			root.add_child(f)
			_extras.append(f)
		k += 1


## Llama: capas superpuestas que ondulan y se desvanecen hacia la punta (sin texturas).
func _flame(width: float, height: float) -> MeshInstance3D:
	var mb := MB.new()
	mb.ao = false
	var cols := [Color(1.0, 0.28, 0.05), Color(1.0, 0.55, 0.1), Color(1.0, 0.85, 0.35)]
	for layer in 3:
		var w := width * (0.42 - layer * 0.11)
		var h := height * (1.0 - layer * 0.24)
		mb.lathe(Vector3(0, 0.0, 0), [Vector2(w * 0.7, 0.0), Vector2(w, h * 0.16), Vector2(w * 0.8, h * 0.38), Vector2(w * 0.42, h * 0.68), Vector2(0.0, h)], 9, cols[layer], true, false)
	var sh := Shader.new()
	sh.code = """
shader_type spatial;
render_mode unshaded, cull_disabled, shadows_disabled, blend_add, depth_draw_never;
uniform float height = 1.0;
varying float h;
void vertex() {
	h = clamp(VERTEX.y / height, 0.0, 1.0);
	float k = h * h;
	VERTEX.x += (sin(TIME * 9.0 + VERTEX.y * 6.0) * 0.1 + sin(TIME * 4.3) * 0.05) * k * height;
	VERTEX.z += cos(TIME * 7.0 + VERTEX.y * 5.0) * 0.09 * k * height;
	VERTEX.y *= 1.0 + sin(TIME * 11.0 + VERTEX.x * 3.0) * 0.07;
}
void fragment() {
	ALBEDO = COLOR.rgb * 1.3;
	ALPHA = pow(1.0 - h, 0.8) * 0.85;
}
"""
	var m := ShaderMaterial.new()
	m.shader = sh
	m.set_shader_parameter("height", height)
	var mi := Avatar.part(mb.commit(), m, Vector3.ZERO)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


# ───────────────────────── Pirámide ─────────────────────────

func _pyramid() -> void:
	_stone.reseed(2025)
	var px := World.PYRAMID.x
	var pz := World.PYRAMID.y
	var front := 0.0
	for b in World.boxes():
		if b.kind == "pyramid":
			var tier := int(str(b.id).trim_prefix("pyr"))
			var w: float = b.x1 - b.x0
			var col := LIME.lerp(LIME_WARM, 0.25).darkened(0.04 * tier)
			# cuerpo en talud y cornisa
			_stone.prism(Vector2(px, pz), b.top - 1.0 - (2.5 if tier == 0 else 0.0), b.top - 0.22, Vector2(w + 0.25, w + 0.25), Vector2(w - 0.1, w - 0.1), col)
			_stone.prism(Vector2(px, pz), b.top - 0.22, b.top, Vector2(w + 0.12, w + 0.12), Vector2(w + 0.12, w + 0.12), col.lightened(0.07), 0.0, LIME.lerp(MOSS, 0.25))
			# banda de glifos en las cuatro caras
			var half := w * 0.5 + 0.08
			var count := int(w / 2.4)
			for i in count:
				var o := (float(i) - (count - 1) * 0.5) * 2.2
				if absf(o) < World.STAIR_W * 0.5 + 0.9:
					continue  # hueco de la escalinata (sólo en la cara sur)
				_glyph_on(_glow, Vector3(px + o, b.top - 0.6, pz + half), Vector3.RIGHT, Vector3.UP, 0.5, 100 + tier * 10 + i, JADE)
			for i in count:
				var o := (float(i) - (count - 1) * 0.5) * 2.2
				_glyph_on(_glow, Vector3(px + half, b.top - 0.6, pz + o), Vector3.FORWARD, Vector3.UP, 0.5, 300 + tier * 10 + i, JADE)
				_glyph_on(_glow, Vector3(px - half, b.top - 0.6, pz + o), Vector3.BACK, Vector3.UP, 0.5, 500 + tier * 10 + i, JADE)
			if tier == 0:
				front = b.z1
		elif b.kind == "stair":
			_stone.box(Vector3((b.x0 + b.x1) * 0.5, b.top - 0.6, (b.z0 + b.z1) * 0.5), Vector3(b.x1 - b.x0, 1.2, b.z1 - b.z0), LIME_WARM.lightened(0.04), 0.0, LIME.lightened(0.08))
	# Alfardas a los lados de la escalinata, rematadas con un bloque en espiral
	for side in [-1.0, 1.0]:
		var x: float = px + side * (World.STAIR_W * 0.5 + 0.32)
		for tier in 4:
			var zf := pz + (8.0 - tier * 2.0)
			_stone.prism(Vector2(x, zf + 0.6), float(tier) - 0.05, float(tier) + 1.12, Vector2(0.62, 1.4), Vector2(0.62, 0.5), LIME.darkened(0.05))
		var head := Vector3(x, 0.0, front + 1.75)
		_stone.box(head + Vector3(0, 0.42, 0), Vector3(0.95, 0.84, 1.1), LIME)
		_stone.box(head + Vector3(0, 0.98, -0.12), Vector3(0.72, 0.3, 0.72), LIME.lightened(0.06))
		_glyph_on(_glow, head + Vector3(0, 0.46, 0.56), Vector3.RIGHT, Vector3.UP, 0.56, 900 + int(side), JADE)
	# Templo: muros, puerta de jade, techo y crestería calada
	var ty := 4.0
	_stone.prism(Vector2(px, pz - 0.3), ty, ty + 2.0, Vector2(3.0, 2.8), Vector2(2.8, 2.6), LIME.darkened(0.08))
	_stone.prism(Vector2(px, pz - 0.3), ty + 2.0, ty + 2.35, Vector2(3.5, 3.3), Vector2(3.5, 3.3), LIME.lightened(0.04))
	_glow.quad(Vector3(px - 0.5, ty + 0.02, pz + 1.12), Vector3(px + 0.5, ty + 0.02, pz + 1.12), Vector3(px + 0.5, ty + 1.5, pz + 1.12), Vector3(px - 0.5, ty + 1.5, pz + 1.12), JADE, JADE, JADE.lightened(0.4), JADE.lightened(0.4))
	for i in 5:
		var cx := px + (i - 2) * 0.68
		var h := 1.3 if i % 2 == 0 else 0.85
		_stone.prism(Vector2(cx, pz - 0.3), ty + 2.35, ty + 2.35 + h, Vector2(0.42, 0.5), Vector2(0.3, 0.4), LIME)
	_stone.prism(Vector2(px, pz - 0.3), ty + 3.3, ty + 3.5, Vector2(3.0, 0.5), Vector2(3.0, 0.5), LIME.lightened(0.05))
	_glyph_on(_glow, Vector3(px, ty + 2.95, pz - 0.02), Vector3.RIGHT, Vector3.UP, 0.5, 77, GOLD)


# ───────────────────────── Santuario ─────────────────────────

func _sanctuary(root: Node3D) -> void:
	_stone.reseed(808)
	var sx := World.SANCTUARY.x
	var sz := World.SANCTUARY.y
	var gate: Dictionary = {}
	for b in World.boxes():
		var cx: float = (b.x0 + b.x1) * 0.5
		var cz: float = (b.z0 + b.z1) * 0.5
		var w: float = b.x1 - b.x0
		var d: float = b.z1 - b.z0
		if b.kind == "wall":
			var wb: float = b.top - 3.2
			_stone.prism(Vector2(cx, cz), wb - 2.0, wb + 0.7, Vector2(w + 0.3, d + 0.3), Vector2(w + 0.1, d + 0.1), LIME_DARK)
			_stone.prism(Vector2(cx, cz), wb + 0.7, b.top - 0.3, Vector2(w, d), Vector2(w - 0.06, d - 0.06), LIME.darkened(0.06))
			_stone.prism(Vector2(cx, cz), b.top - 0.3, b.top, Vector2(w + 0.22, d + 0.22), Vector2(w + 0.22, d + 0.22), LIME.lightened(0.05), 0.0, LIME.lerp(MOSS, 0.3))
			# almenas escalonadas
			var along_x := w > d
			var n := int((w if along_x else d) / 1.3)
			for i in n:
				var o := (float(i) - (n - 1) * 0.5) * 1.3
				var p := Vector2(cx + (o if along_x else 0.0), cz + (0.0 if along_x else o))
				_stone.prism(p, b.top, b.top + 0.5, Vector2(0.7, 0.7), Vector2(0.42, 0.42), LIME)
		elif b.kind == "gate":
			gate = b
		elif b.kind == "altar":
			_stone.lathe(Vector3(cx, b.top - 0.8, cz), [Vector2(1.35, 0.0), Vector2(1.35, 0.25), Vector2(1.05, 0.25), Vector2(0.95, 0.62), Vector2(1.15, 0.8)], 8, LIME.lightened(0.06), false, true)
			_glow.lathe(Vector3(cx, b.top + 0.01, cz), [Vector2(0.7, 0.0), Vector2(0.7, 0.02)], 8, JADE, false, true)
			_floating_glyph(root, Vector3(cx, b.top + 1.2, cz))
		elif b.kind == "seal":
			_seal(root)
	if gate.is_empty():
		return
	var gx: float = (gate.x0 + gate.x1) * 0.5
	var gz: float = (gate.z0 + gate.z1) * 0.5
	var base: float = gate.top - 3.2
	# Portada monumental: jambas, dintel, frontón escalonado y sol de jade
	for side in [-1.0, 1.0]:
		_stone.prism(Vector2(gx - 0.1, gz + side * 2.55), base - 1.0, base + 4.3, Vector2(1.7, 1.2), Vector2(1.5, 1.0), LIME.lightened(0.02))
		_stone.prism(Vector2(gx - 0.1, gz + side * 2.55), base + 4.3, base + 4.75, Vector2(1.9, 1.4), Vector2(1.9, 1.4), LIME.lightened(0.08))
		_stela(Vector3(gx - 1.15, base, gz + side * 4.4), -PI * 0.5, 2.5, 60 + int(side) * 3, MAGENTA.lerp(JADE, 0.5))
		_glyph_on(_glow, Vector3(gx - 0.96, base + 2.6, gz + side * 2.55), Vector3.BACK, Vector3.UP, 0.7, 210 + int(side), JADE)
	_stone.prism(Vector2(gx - 0.1, gz), base + 3.25, base + 4.3, Vector2(1.6, 6.4), Vector2(1.6, 6.4), LIME)
	_stone.prism(Vector2(gx - 0.1, gz), base + 4.3, base + 5.3, Vector2(1.3, 4.4), Vector2(1.1, 2.6), LIME.lightened(0.04))
	_stone.prism(Vector2(gx - 0.1, gz), base + 5.3, base + 6.0, Vector2(1.0, 1.9), Vector2(0.8, 0.9), LIME.lightened(0.08))
	# sol de ocho rayos en el frontón
	var sc := Vector3(gx - 0.92, base + 4.78, gz)
	for i in 8:
		var a := TAU * float(i) / 8.0
		var dir := Vector3(0, sin(a), cos(a))
		var perp := Vector3(0, cos(a), -sin(a)) * 0.07
		_glow.quad(sc + dir * 0.3 - perp, sc + dir * 0.3 + perp, sc + dir * 0.62 + perp * 0.3, sc + dir * 0.62 - perp * 0.3, GOLD, GOLD, GOLD, GOLD)
		_glow.quad(sc + dir * 0.3 + perp, sc + dir * 0.3 - perp, sc + dir * 0.62 - perp * 0.3, sc + dir * 0.62 + perp * 0.3, GOLD, GOLD, GOLD, GOLD)
	for i in 10:
		var a0 := TAU * float(i) / 10.0
		var a1 := TAU * float(i + 1) / 10.0
		_glow.tri(sc, sc + Vector3(0, sin(a1), cos(a1)) * 0.24, sc + Vector3(0, sin(a0), cos(a0)) * 0.24, GOLD, GOLD, GOLD)
		_glow.tri(sc, sc + Vector3(0, sin(a0), cos(a0)) * 0.24, sc + Vector3(0, sin(a1), cos(a1)) * 0.24, GOLD, GOLD, GOLD)
	# Círculo ritual frente a la puerta (donde despierta la emboscada)
	var rc := Vector3(gx - 6.5, 0.0, gz)
	for ring in [[3.0, 3.18], [1.9, 2.0]]:
		for i in 48:
			if ring[0] > 2.5 and i % 6 == 5:
				continue
			var a0 := TAU * float(i) / 48.0
			var a1 := TAU * float(i + 1) / 48.0
			var y0 := World.terrain_h(rc.x + cos(a0) * ring[0], rc.z + sin(a0) * ring[0]) + 0.06
			var y1 := World.terrain_h(rc.x + cos(a1) * ring[0], rc.z + sin(a1) * ring[0]) + 0.06
			_glow.quad(rc + Vector3(cos(a0) * ring[0], y0, sin(a0) * ring[0]), rc + Vector3(cos(a1) * ring[0], y1, sin(a1) * ring[0]),
				rc + Vector3(cos(a1) * ring[1], y1, sin(a1) * ring[1]), rc + Vector3(cos(a0) * ring[1], y0, sin(a0) * ring[1]), MAGENTA, MAGENTA, MAGENTA, MAGENTA)

	# Barrotes de energía (bajan al abrirse)
	gate_bars = Node3D.new()
	gate_bars.position = Vector3(gx, base, gz)
	var bar := CylinderMesh.new()
	bar.top_radius = 0.1
	bar.bottom_radius = 0.1
	bar.height = 3.2
	bar.radial_segments = 6
	var bar_mat := Avatar.mat(MAGENTA, 2.4, 0.3)
	for i in 7:
		gate_bars.add_child(Avatar.part(bar, bar_mat, Vector3(0, 1.6, -1.8 + i * 0.6)))
	root.add_child(gate_bars)
	gate_light = OmniLight3D.new()
	gate_light.light_color = MAGENTA
	gate_light.light_energy = 1.8
	gate_light.omni_range = 9.0
	gate_light.position = Vector3(gx - 1.4, base + 2.0, gz)
	root.add_child(gate_light)


## Cúpula de energía que cubre el santuario mientras está sellado (el sólido real es la caja "seal").
func _seal(root: Node3D) -> void:
	var dome := SphereMesh.new()
	dome.radius = 9.4
	dome.height = 12.5
	dome.radial_segments = 36
	dome.rings = 14
	dome.is_hemisphere = true
	var sh := Shader.new()
	sh.code = """
shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled;
uniform float strength = 1.0;
uniform vec3 tint : source_color = vec3(0.98, 0.2, 0.6);
varying vec3 lpos;
void vertex() { lpos = VERTEX; }
void fragment() {
	// celdas hexagonales que respiran y un barrido que sube
	vec2 p = vec2(atan(lpos.z, lpos.x) * 6.0, lpos.y * 1.1);
	vec2 g = abs(fract(p + vec2(0.5 * floor(p.y), 0.0)) - 0.5);
	float cell = smoothstep(0.42, 0.5, max(g.x, g.y));
	float sweep = pow(0.5 + 0.5 * sin(lpos.y * 1.4 - TIME * 1.6), 6.0);
	float rim = pow(1.0 - abs(dot(normalize(NORMAL), normalize(VIEW))), 2.0);
	float a = (0.05 + cell * 0.22 + sweep * 0.12 + rim * 0.3) * strength;
	ALBEDO = mix(tint, vec3(1.0, 0.75, 0.9), cell * 0.5 + sweep * 0.3);
	ALPHA = clamp(a, 0.0, 1.0);
}
"""
	_seal_mat = ShaderMaterial.new()
	_seal_mat.shader = sh
	seal_veil = Avatar.part(dome, _seal_mat, Vector3(World.SANCTUARY.x, 0.0, World.SANCTUARY.y))
	seal_veil.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(seal_veil)


func _floating_glyph(root: Node3D, pos: Vector3) -> void:
	glyph = Node3D.new()
	glyph.position = pos
	var mb := MB.new()
	mb.ao = false
	mb.prism(Vector2.ZERO, 0.0, 0.62, Vector2(0.62, 0.62), Vector2(0.0, 0.0), JADE.lightened(0.2))
	mb.prism(Vector2.ZERO, -0.62, 0.0, Vector2(0.0, 0.0), Vector2(0.62, 0.62), JADE)
	glyph.add_child(Avatar.part(mb.commit(), _emissive(2.6), Vector3.ZERO))
	var light := OmniLight3D.new()
	light.light_color = JADE
	light.light_energy = 2.0
	light.omni_range = 9.0
	glyph.add_child(light)
	root.add_child(glyph)


# ───────────────────────── Mirador, ruinas y rocas ─────────────────────────

func _ledge(root: Node3D) -> void:
	_stone.reseed(4242)
	for b in World.boxes():
		if b.kind != "ledge":
			continue
		var c := Vector2((b.x0 + b.x1) * 0.5, (b.z0 + b.z1) * 0.5)
		var w: float = b.x1 - b.x0
		var base: float = b.top - 2.0
		_stone.prism(c, base - 2.0, b.top - 0.3, Vector2(w + 0.5, w + 0.5), Vector2(w - 0.1, w - 0.1), LIME_DARK.lerp(LIME_WARM, 0.4))
		_stone.prism(c, b.top - 0.3, b.top, Vector2(w + 0.2, w + 0.2), Vector2(w + 0.2, w + 0.2), LIME.lightened(0.04), 0.0, LIME_WARM)
		# cabeza de jaguar geométrica en la cara que mira a la plaza y huella luminosa arriba
		_glyph_on(_glow, Vector3(c.x - w * 0.5 - 0.22, base + 1.1, c.y - 0.6), Vector3.BACK, Vector3.UP, 1.0, 5150, AMBER)
		_glow.lathe(Vector3(c.x, b.top + 0.02, c.y), [Vector2(0.7, 0.0), Vector2(0.7, 0.02)], 10, AMBER, false, true)
		for p in [Vector2(-0.75, -0.75), Vector2(0, -1.05), Vector2(0.75, -0.75)]:
			_glow.lathe(Vector3(c.x + p.x, b.top + 0.02, c.y + p.y), [Vector2(0.28, 0.0), Vector2(0.28, 0.02)], 8, AMBER, false, true)
		# postes con estandarte en dos esquinas
		for corner in [Vector2(1, 1), Vector2(-1, 1)]:
			var pc: Vector2 = c + corner * (w * 0.5 - 0.3)
			_stone.lathe(Vector3(pc.x, b.top, pc.y), [Vector2(0.12, 0.0), Vector2(0.09, 2.6), Vector2(0.16, 2.7)], 6, BARK, true, true)
			_banner(Vector3(pc.x, b.top + 2.5, pc.y), Vector3(-corner.x, 0, 0), AMBER, Color(0.9, 0.25, 0.3))
		var lamp := OmniLight3D.new()
		lamp.light_color = AMBER
		lamp.light_energy = 1.2
		lamp.omni_range = 7.0
		lamp.position = Vector3(c.x, b.top + 1.5, c.y)
		root.add_child(lamp)
		_extras.append(lamp)


## Estandarte triangular de tela (dos caras), colgado de un poste.
func _banner(top: Vector3, dir: Vector3, c1: Color, c2: Color) -> void:
	var a := top
	var b := top + dir * 0.75
	var tip := top + dir * 0.36 + Vector3(0, -1.25, 0)
	_stone.tri(a, b, tip, c1, c1, c2)
	_stone.tri(a, tip, b, c1, c2, c1)


func _ruins_and_rocks() -> void:
	_stone.reseed(6060)
	for b in World.boxes():
		if b.kind != "ruin":
			continue
		var c := Vector2((b.x0 + b.x1) * 0.5, (b.z0 + b.z1) * 0.5)
		var w: float = b.x1 - b.x0
		var d: float = b.z1 - b.z0
		var col := LIME.lerp(MOSS, _stone.rand() * 0.25)
		_stone.prism(c, b.top - 2.6, b.top, Vector2(w + 0.12, d + 0.12), Vector2(w - 0.05, d - 0.05), col, 0.0, col.lerp(MOSS, 0.45))
		if b.top - World.terrain_h(c.x, c.y) > 0.7:
			_glyph_on(_glow, Vector3(c.x, b.top - 0.45, b.z1 + 0.02), Vector3.RIGHT, Vector3.UP, 0.5, int(c.x * 13.0) + 400, JADE.darkened(0.2))
	# Rocas sueltas en grupos, lejos de los caminos
	var placed := 0
	var tries := 0
	while placed < 26 and tries < 400:
		tries += 1
		var a := _stone.rand() * TAU
		var r := 12.0 + _stone.rand() * 33.0
		var p := Vector2(cos(a) * r, sin(a) * r)
		if _decor_blocked(p, 2.6):
			continue
		placed += 1
		for k in 1 + int(_stone.rand() * 3.0):
			var o := p + Vector2(_stone.rand() - 0.5, _stone.rand() - 0.5) * 1.6
			var s := 0.22 + _stone.rand() * 0.3   # bajas: no estorban al caminar
			_stone.rock(Vector3(o.x, World.terrain_h(o.x, o.y) + s * 0.25, o.y), Vector3(s * 1.5, s, s * 1.2), LIME_DARK.lerp(LIME, _stone.rand() * 0.5), LIME.lerp(MOSS, _stone.rand() * 0.7))


## ¿Hay algo jugable (camino, altar, sólido, agua) a menos de `margin` de p?
func _decor_blocked(p: Vector2, margin: float) -> bool:
	if p.length() < 10.5 or p.length() > 45.0:
		return true
	if _path_weight(p.x, p.y, 0.0) > 0.05:
		return true
	if Vector2(p.x - World.CENOTE.x, p.y - World.CENOTE.y).length() < World.CENOTE_R * 1.45:
		return true
	if absf(p.x - World.SANCTUARY.x) < 8.0 and absf(p.y - World.SANCTUARY.y) < 8.0:
		return true
	if absf(p.x - (World.SANCTUARY.x - 12.0)) < 5.0 and absf(p.y - World.SANCTUARY.y) < 5.0:
		return true  # explanada de la emboscada: despejada para pelear
	for q in World.PLATES:
		if p.distance_to(q) < 2.6 + margin:
			return true
	for c in World.cylinders():
		if p.distance_to(Vector2(c.x, c.z)) < float(c.r) + margin:
			return true
	for b in World.boxes():
		if b.kind == "seal":
			continue
		if p.x > b.x0 - margin and p.x < b.x1 + margin and p.y > b.z0 - margin and p.y < b.z1 + margin:
			return true
	return false


# ───────────────────────── Altares ─────────────────────────

func _markers(root: Node3D) -> void:
	_stone.reseed(1212)
	for i in World.PLATES.size():
		var p := World.plate_pos(i)
		var col: Color = PLATE_COLORS[i]
		# losa circular tallada en dos escalones
		_stone.lathe(p + Vector3(0, -0.2, 0), [Vector2(World.PLATE_R + 0.45, 0.0), Vector2(World.PLATE_R + 0.45, 0.24), Vector2(World.PLATE_R + 0.12, 0.24),
			Vector2(World.PLATE_R + 0.12, 0.3)], 14, LIME_DARK, false, true, LIME)
		# glifo del altar (cambia de color al pisarlo)
		var gm := MB.new()
		gm.ao = false
		_glyph_on(gm, Vector3(0, 0.0, 0), Vector3.RIGHT, Vector3.FORWARD, 1.45, 700 + i * 37, Color.WHITE)
		for k in 40:
			var a0 := TAU * float(k) / 40.0
			var a1 := TAU * float(k + 1) / 40.0
			var r0 := World.PLATE_R - 0.16
			var r1 := World.PLATE_R - 0.02
			gm.quad(Vector3(cos(a0) * r0, 0.03, sin(a0) * r0), Vector3(cos(a1) * r0, 0.03, sin(a1) * r0), Vector3(cos(a1) * r1, 0.03, sin(a1) * r1), Vector3(cos(a0) * r1, 0.03, sin(a0) * r1), Color.WHITE, Color.WHITE, Color.WHITE, Color.WHITE)
		var mat := _emissive(1.0)
		mat.set_shader_parameter("tint", AMBER.lerp(col, 0.35))
		var gi := Avatar.part(gm.commit(), mat, p + Vector3(0, 0.115, 0))
		gi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(gi)
		_plate_glyphs.append(gi)
		_plate_mats.append(mat)
		# haz de luz al activarse
		var beam := CylinderMesh.new()
		beam.top_radius = World.PLATE_R * 0.55
		beam.bottom_radius = World.PLATE_R * 0.95
		beam.height = 9.0
		beam.radial_segments = 18
		beam.cap_top = false
		beam.cap_bottom = false
		var bm := StandardMaterial3D.new()
		bm.albedo_color = Color(col.r, col.g, col.b, 0.22)
		bm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		bm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		bm.cull_mode = BaseMaterial3D.CULL_DISABLED
		bm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		var bi := Avatar.part(beam, bm, p + Vector3(0, 4.5, 0))
		bi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		bi.visible = false
		root.add_child(bi)
		_plate_beams.append(bi)
	# Piedras señaleras con su color y estandarte
	for c in World.cylinders():
		if c.kind != "marker":
			continue
		var i := int(c.i)
		var col: Color = PLATE_COLORS[i]
		var at := Vector3(c.x, World.terrain_h(c.x, c.z), c.z)
		var r: float = c.r
		_stone.lathe(at + Vector3(0, -0.3, 0), [Vector2(r * 1.5, 0.0), Vector2(r * 1.5, 0.5), Vector2(r * 1.05, 0.62), Vector2(r * 0.9, 2.1), Vector2(r * 1.15, 2.25), Vector2(r * 0.55, 2.7)], 6, LIME, false, true)
		_glow.lathe(at + Vector3(0, 1.72, 0), [Vector2(r * 1.0, 0.0), Vector2(r * 0.98, 0.16)], 6, col, false, false)
		var to_plate := (Vector3(World.PLATES[i].x, 0, World.PLATES[i].y) - Vector3(c.x, 0, c.z)).normalized()
		_glyph_on(_glow, at + Vector3(0, 1.15, 0) + to_plate * (r * 0.98), Vector3(to_plate.z, 0, -to_plate.x), Vector3.UP, 0.42, 700 + i * 37, col)
		_banner(at + Vector3(0, 2.5, 0), Vector3(-to_plate.z, 0, to_plate.x), col, col.darkened(0.45))


func set_plate(i: int, on: bool) -> void:
	if _plate_on[i] == on:
		return
	_plate_on[i] = on
	var col: Color = PLATE_COLORS[i]
	_plate_mats[i].set_shader_parameter("tint", col.lightened(0.25) if on else AMBER.lerp(col, 0.35))
	_plate_mats[i].set_shader_parameter("energy", 3.2 if on else 1.0)
	_plate_beams[i].visible = on


# ───────────────────────── Vegetación ─────────────────────────

func _multimesh(root: Node3D, mesh: Mesh, xforms: Array, colors: Array, shadows := true) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = mesh
	mm.instance_count = xforms.size()
	for i in xforms.size():
		mm.set_instance_transform(i, xforms[i])
		mm.set_instance_color(i, colors[i])
	var inst := MultiMeshInstance3D.new()
	inst.multimesh = mm
	inst.material_override = _foliage_mat
	if not shadows:
		inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(inst)
	return inst


## Árbol frondoso: tronco con contrafuertes, ramas y copa en racimos (verde claro arriba).
func _broadleaf_mesh(seed_v: int, squat: bool) -> ArrayMesh:
	var mb := MB.new()
	mb.reseed(seed_v)
	var h := 1.0
	mb.lathe(Vector3.ZERO, [Vector2(0.22, -0.08), Vector2(0.15, 0.06), Vector2(0.1, 0.22), Vector2(0.085, 0.62), Vector2(0.075, h)], 7, BARK, true, false)
	for i in 5:
		var a := TAU * float(i) / 5.0 + mb.rand() * 0.5
		var d := Vector3(cos(a), 0, sin(a))
		mb.tube([d * 0.08 + Vector3(0, 0.2, 0), d * 0.2 + Vector3(0, 0.05, 0), d * 0.32 + Vector3(0, -0.04, 0)], [0.05, 0.035, 0.012], 5, BARK, BARK.darkened(0.2))
	mb.ao = false
	var top := Color(0.5, 0.86, 0.3)
	var low := Color(0.12, 0.42, 0.2)
	var blobs := 6 if not squat else 5
	for i in blobs:
		var a := TAU * float(i) / blobs + mb.rand() * 0.8
		var r := (0.22 + mb.rand() * 0.2) * (1.25 if squat else 1.0)
		var off := Vector3(cos(a) * r, h + (mb.rand() - 0.3) * 0.22 + (0.0 if i > 0 else 0.16), sin(a) * r)
		if i == 0:
			off = Vector3(0, h + 0.14, 0)
		var s := 0.26 + mb.rand() * 0.12
		mb.rock(off, Vector3(s * 1.25, s * (0.62 if squat else 0.8), s * 1.25), low, top, 4, 7)
	return mb.commit()


## Palma de huano: tronco curvo y abanico de hojas.
func _palm_mesh() -> ArrayMesh:
	var mb := MB.new()
	mb.reseed(55)
	var pts := []
	var radii := []
	for i in 7:
		var t := float(i) / 6.0
		pts.append(Vector3(sin(t * 1.2) * 0.12, t * 1.05, 0))
		radii.append(0.07 - t * 0.028)
	mb.tube(pts, radii, 6, BARK.lerp(Color(0.62, 0.52, 0.38), 0.5), BARK)
	mb.ao = false
	var crown: Vector3 = pts[6]
	for i in 9:
		var a := TAU * float(i) / 9.0
		var d := Vector3(cos(a), 0.55, sin(a)).normalized()
		mb.blade(crown, d, 0.62 + (i % 2) * 0.1, 0.34, 0.75, Color(0.16, 0.5, 0.2), Color(0.55, 0.85, 0.3), 5)
	for i in 5:
		var a := TAU * float(i) / 5.0 + 0.3
		mb.blade(crown, Vector3(cos(a), 1.3, sin(a)).normalized(), 0.42, 0.24, 0.3, Color(0.3, 0.68, 0.24), Color(0.7, 0.92, 0.4), 4)
	return mb.commit()


func _flora(root: Node3D) -> void:
	# ── Árboles (mismas posiciones que los sólidos del servidor) ──
	var meshes := [_broadleaf_mesh(11, false), _broadleaf_mesh(29, true), _palm_mesh()]
	var xf := [[], [], []]
	var cols := [[], [], []]
	for c in World.cylinders():
		if c.kind != "tree":
			continue
		var v := int(c.get("v", 0))
		var s: float = c.s
		var y := World.terrain_h(c.x, c.z)
		var h: float = c.h
		# la malla mide 1 de alto con tronco de radio ~0.1 → se escala para casar con el sólido
		var basis := Basis(Vector3.UP, _rand() * TAU).scaled(Vector3(s * 4.6, h * (1.05 if v < 2 else 1.25), s * 4.6))
		xf[v].append(Transform3D(basis, Vector3(c.x, y, c.z)))
		cols[v].append(Color(1, 1, 1).lerp(Color(0.86, 1.0, 0.8), _rand()).darkened(_rand() * 0.14))
	for v in 3:
		_multimesh(root, meshes[v], xf[v], cols[v])
	# Selva que rodea el claro: fuera del radio jugable, más alta y oscura (plano medio).
	# Va en mallas aparte y sin proyectar sombra: es fondo y así no cuesta en el pase de sombras.
	xf = [[], [], []]
	cols = [[], [], []]
	for i in 90:
		var a := TAU * float(i) / 90.0 + _rand() * 0.05
		var r := World.RADIUS + 2.5 + _rand() * 16.0
		var p := Vector2(cos(a) * r, sin(a) * r)
		var v := i % 3
		var s := 1.3 + _rand() * 1.1
		var h := (6.5 + _rand() * 5.0) * (1.0 if v < 2 else 1.2)
		xf[v].append(Transform3D(Basis(Vector3.UP, _rand() * TAU).scaled(Vector3(s * 4.6, h, s * 4.6)), Vector3(p.x, _ground(p.x, p.y) - 0.3, p.y)))
		cols[v].append(Color(0.62, 0.82, 0.66).darkened(_rand() * 0.22))
	for v in 3:
		_extras_min.append(_multimesh(root, meshes[v], xf[v], cols[v], false))

	# ── Gran ceiba: tronco monumental con contrafuertes, ramas y copa enorme ──
	var cb := MB.new()
	cb.reseed(909)
	var cx := World.CEIBA.x
	var cz := World.CEIBA.y
	var cy := World.terrain_h(cx, cz)
	var base := Vector3(cx, cy, cz)
	var trunk := BARK.lerp(Color(0.72, 0.68, 0.6), 0.45)
	cb.lathe(base, [Vector2(2.3, -0.6), Vector2(1.75, 0.5), Vector2(1.45, 1.6), Vector2(1.3, 4.0), Vector2(1.15, 8.0), Vector2(1.0, 10.5)], 10, trunk, true, false)
	for i in 7:
		var a := TAU * float(i) / 7.0 + cb.rand() * 0.4
		var d := Vector3(cos(a), 0, sin(a))
		cb.tube([base + d * 1.2 + Vector3(0, 2.4, 0), base + d * 2.2 + Vector3(0, 0.9, 0), base + d * 3.6 + Vector3(0, 0.15, 0), base + d * 5.2 + Vector3(0, -0.25, 0)],
			[0.5, 0.42, 0.26, 0.06], 6, trunk, trunk.darkened(0.25))
	for i in 6:
		var a := TAU * float(i) / 6.0 + 0.3
		var d := Vector3(cos(a), 0, sin(a))
		cb.tube([base + Vector3(0, 9.0, 0), base + d * 2.6 + Vector3(0, 11.2, 0), base + d * 5.4 + Vector3(0, 12.4, 0)], [0.6, 0.38, 0.14], 6, trunk)
	var ceiba_trunk := Avatar.part(cb.commit(), _vc_mat, Vector3.ZERO)
	root.add_child(ceiba_trunk)
	var canopy := MB.new()
	canopy.ao = false
	canopy.reseed(910)
	for i in 13:
		var a := TAU * float(i) / 13.0 + canopy.rand() * 0.5
		var r := 0.0 if i == 0 else 3.4 + canopy.rand() * 3.2
		var s := 3.4 + canopy.rand() * 1.6
		canopy.rock(base + Vector3(cos(a) * r, 13.0 + canopy.rand() * 2.0 + (1.6 if i == 0 else 0.0), sin(a) * r), Vector3(s * 1.2, s * 0.62, s * 1.2), Color(0.1, 0.4, 0.2), Color(0.5, 0.86, 0.32), 5, 9)
	# lianas que cuelgan
	for i in 10:
		var a := canopy.rand() * TAU
		var r := 2.5 + canopy.rand() * 4.5
		var top := base + Vector3(cos(a) * r, 11.4, sin(a) * r)
		var len := 3.0 + canopy.rand() * 4.0
		canopy.tube([top, top + Vector3(0.15, -len * 0.5, 0.1), top + Vector3(0.05, -len, -0.1)], [0.05, 0.04, 0.02], 4, Color(0.2, 0.46, 0.2), Color(0.4, 0.7, 0.3))
	root.add_child(Avatar.part(canopy.commit(), _foliage_mat, Vector3.ZERO))

	# ── Matas, helechos y flores ──
	var fern := MB.new()
	fern.ao = false
	for i in 7:
		var a := TAU * float(i) / 7.0
		fern.blade(Vector3.ZERO, Vector3(cos(a), 0.75, sin(a)).normalized(), 1.0, 0.42, 0.7, Color(0.7, 0.7, 0.7), Color.WHITE, 4)
	var bush := MB.new()
	bush.ao = false
	bush.reseed(5)
	for i in 3:
		bush.rock(Vector3((i - 1) * 0.42, 0.26, (i % 2) * 0.2), Vector3(0.5, 0.36, 0.46), Color(0.6, 0.6, 0.6), Color.WHITE, 3, 6)
	var flower := MB.new()
	flower.ao = false
	for i in 5:
		var a := TAU * float(i) / 5.0
		flower.blade(Vector3(0, 0.34, 0), Vector3(cos(a), 0.35, sin(a)).normalized(), 0.2, 0.16, 0.2, Color.WHITE, Color.WHITE, 2)
	flower.tube([Vector3.ZERO, Vector3(0, 0.34, 0)], [0.015, 0.012], 3, Color(0.35, 0.8, 0.35))
	var fx := []
	var fc := []
	var bx := []
	var bc := []
	var lx := []
	var lc := []
	var tries := 0
	while fx.size() + bx.size() < 300 and tries < 3000:
		tries += 1
		var a := _rand() * TAU
		var r := 10.6 + _rand() * 37.0
		var p := Vector2(cos(a) * r, sin(a) * r)
		if _decor_blocked(p, 0.9):
			continue
		var y := World.terrain_h(p.x, p.y)
		var s := 0.55 + _rand() * 0.9
		var t := Transform3D(Basis(Vector3.UP, _rand() * TAU).scaled(Vector3(s, s * (0.8 + _rand() * 0.5), s)), Vector3(p.x, y, p.y))
		var green := Color(0.16, 0.52, 0.2).lerp(Color(0.42, 0.78, 0.26), _rand())
		if _rand() < 0.55:
			fx.append(t)
			fc.append(green)
		else:
			bx.append(t)
			bc.append(green.darkened(0.1))
		# racimos de flores junto a algunas matas
		if _rand() < 0.3:
			var petal: Color = [Color(1.0, 0.35, 0.6), Color(1.0, 0.8, 0.25), Color(1.0, 0.96, 0.9), Color(0.6, 0.45, 1.0)][int(_rand() * 4.0)]
			for k in 3:
				var o := p + Vector2(_rand() - 0.5, _rand() - 0.5) * 1.3
				var fs := 0.7 + _rand() * 0.7
				lx.append(Transform3D(Basis(Vector3.UP, _rand() * TAU).scaled(Vector3(fs, fs, fs)), Vector3(o.x, World.terrain_h(o.x, o.y), o.y)))
				lc.append(petal)
	_extras_min.append(_multimesh(root, fern.commit(), fx, fc, false))
	_extras_min.append(_multimesh(root, bush.commit(), bx, bc, false))
	_extras.append(_multimesh(root, flower.commit(), lx, lc, false))

	# ── Hierba alta en penachos (sólo en calidad alta) ──
	var tuft := MB.new()
	tuft.ao = false
	for i in 5:
		var a := TAU * float(i) / 5.0
		tuft.blade(Vector3(cos(a) * 0.05, 0, sin(a) * 0.05), Vector3(cos(a) * 0.35, 1.0, sin(a) * 0.35).normalized(), 0.5, 0.1, 0.25, Color(0.55, 0.55, 0.55), Color.WHITE, 2)
	var gx := []
	var gc := []
	tries = 0
	while gx.size() < 1100 and tries < 6000:
		tries += 1
		var a := _rand() * TAU
		var r := 10.4 + sqrt(_rand()) * 36.0
		var p := Vector2(cos(a) * r, sin(a) * r)
		if _decor_blocked(p, 0.3):
			continue
		var s := 0.6 + _rand() * 0.9
		gx.append(Transform3D(Basis(Vector3.UP, _rand() * TAU).scaled(Vector3(s, s, s)), Vector3(p.x, World.terrain_h(p.x, p.y), p.y)))
		gc.append(Color(0.3, 0.66, 0.22).lerp(Color(0.62, 0.82, 0.3), _rand()))
	_extras.append(_multimesh(root, tuft.commit(), gx, gc, false))


# ───────────────────────── Partículas ─────────────────────────

func _motes(root: Node3D, amount: int, life: float, extents: Vector3, at: Vector3, color: Color, size: float, speed: float, rise := 0.0) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.amount = amount
	p.lifetime = life
	p.preprocess = life
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	p.emission_box_extents = extents
	p.position = at
	p.gravity = Vector3(0, rise, 0)
	p.direction = Vector3(1, 0.2, 0)
	p.spread = 180.0
	p.initial_velocity_min = speed * 0.3
	p.initial_velocity_max = speed
	p.scale_amount_min = 0.5
	p.scale_amount_max = 1.4
	var m := SphereMesh.new()
	m.radius = size
	m.height = size * 2.0
	m.radial_segments = 6
	m.rings = 3
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = color
	m.material = mat
	p.mesh = m
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(p)
	return p


func _particles(root: Node3D) -> void:
	fireflies = _motes(root, 90, 7.0, Vector3(40, 1.6, 40), Vector3(0, 2.0, 0), Color(1.0, 0.92, 0.45), 0.05, 0.7)
	# polen y polvo a contraluz
	_extras.append(_motes(root, 70, 9.0, Vector3(30, 4.0, 30), Vector3(0, 4.5, 0), Color(1.0, 1.0, 0.9, 0.7), 0.025, 0.3))
	# energía ritual que sube del brasero y del santuario
	_extras.append(_motes(root, 14, 2.4, Vector3(0.6, 0.2, 0.6), Vector3(0, 1.8, 0), Color(1.0, 0.7, 0.3), 0.04, 0.4, 1.6))
	_extras.append(_motes(root, 26, 4.0, Vector3(5.0, 0.5, 5.0), Vector3(World.SANCTUARY.x, 1.0, World.SANCTUARY.y), Color(1.0, 0.45, 0.8), 0.045, 0.3, 1.1))
	# destellos sobre el cenote
	_extras.append(_motes(root, 30, 5.0, Vector3(8.0, 0.4, 8.0), Vector3(World.CENOTE.x, World.WATER_LEVEL + 0.6, World.CENOTE.y), Color(0.6, 1.0, 0.95), 0.035, 0.25, 0.25))


# ───────────────────────── Vida del escenario ─────────────────────────

## Se llama cada cuadro: puerta, sello, glifo flotante y fuego.
func update(time: float, delta: float, gate_anim: float) -> void:
	if gate_bars:
		var base_y := World.terrain_h(World.SANCTUARY.x - 6.0, World.SANCTUARY.y)
		gate_bars.position.y = base_y - gate_anim * 3.6
		gate_bars.visible = gate_anim < 1.0
		gate_light.light_energy = 1.8 * (1.0 - gate_anim) * (0.85 + 0.15 * sin(time * 3.0))
	if seal_veil:
		seal_veil.visible = gate_anim < 1.0
		_seal_mat.set_shader_parameter("strength", 1.0 - gate_anim)
		seal_veil.scale = Vector3.ONE * (1.0 + gate_anim * 0.25)
	if glyph:
		glyph.rotation.y += delta * 1.2
		glyph.position.y += sin(time * 2.0) * delta * 0.25
	if _flame_light:
		_flame_light.light_energy = 1.3 + sin(time * 11.0) * 0.15 + sin(time * 17.0) * 0.1


## Calidad: 0 alta · 1 baja (sin sombras, resplandor ni adornos caros) ·
## 2 mínima (además sin selva de fondo, matas, helechos ni nubes).
func set_quality(level: int) -> void:
	sun.shadow_enabled = level == 0
	env.glow_enabled = level == 0
	fireflies.emitting = level == 0
	fireflies.visible = level == 0
	for n in _extras:
		n.visible = level == 0
	for n in _extras_min:
		n.visible = level < 2
