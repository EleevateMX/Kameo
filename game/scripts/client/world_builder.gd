extends RefCounted
## Construye el escenario 3D del Claro de los Aluxes a partir de la misma
## definición que usa el servidor (world_def.gd). Todo es procedimental.

const World := preload("res://scripts/shared/world_def.gd")
const Avatar := preload("res://scripts/client/avatar.gd")

const STONE := Color(0.66, 0.62, 0.52)
const STONE_DARK := Color(0.5, 0.48, 0.42)
const JADE := Color(0.18, 0.9, 0.7)
const AMBER := Color(1.0, 0.66, 0.2)
const MAGENTA := Color(0.95, 0.1, 0.55)

var gate_bars: Node3D
var gate_light: OmniLight3D
var seal_veil: MeshInstance3D
var seal_mat: StandardMaterial3D
var plate_rings: Array[MeshInstance3D] = []
var plate_beams: Array[MeshInstance3D] = []
var glyph: Node3D
var sun: DirectionalLight3D
var env: Environment
var fireflies: CPUParticles3D
var _plate_idle: StandardMaterial3D
var _plate_on: StandardMaterial3D
var _seed := 77123


func _rand() -> float:
	_seed = (_seed * 1103515245 + 12345) % 2147483648
	return float(_seed) / 2147483648.0


func build(root: Node3D) -> void:
	_environment(root)
	_terrain(root)
	_water(root)
	_plaza(root)
	_boxes(root)
	_trees(root)
	_bushes(root)
	_plates(root)
	_fireflies(root)


func _environment(root: Node3D) -> void:
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.16, 0.42, 0.66)
	sky_mat.sky_horizon_color = Color(1.0, 0.78, 0.55)
	sky_mat.sky_curve = 0.12
	sky_mat.ground_bottom_color = Color(0.08, 0.2, 0.14)
	sky_mat.ground_horizon_color = Color(0.95, 0.72, 0.5)
	sky_mat.sun_angle_max = 28.0
	sky_mat.sun_curve = 0.08
	var sky := Sky.new()
	sky.sky_material = sky_mat
	env = Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 1.0
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.fog_enabled = true
	env.fog_light_color = Color(0.86, 0.8, 0.62)
	env.fog_density = 0.0038
	env.fog_sky_affect = 0.25
	env.glow_enabled = true
	env.glow_intensity = 0.35
	env.glow_bloom = 0.05
	env.glow_hdr_threshold = 1.1
	env.tonemap_exposure = 0.92
	env.tonemap_white = 4.0
	var we := WorldEnvironment.new()
	we.environment = env
	root.add_child(we)

	sun = DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-36, 132, 0)
	sun.light_color = Color(1.0, 0.9, 0.72)
	sun.light_energy = 1.05
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 48.0
	sun.shadow_blur = 1.6
	sun.shadow_bias = 0.06
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	sun.shadow_opacity = 0.6
	root.add_child(sun)


static func _hash(x: float, z: float) -> float:
	var v := sin(x * 12.9898 + z * 78.233) * 43758.5453
	return v - floorf(v)


func _terrain_color(x: float, z: float, h: float) -> Color:
	var n := _hash(floorf(x * 0.8), floorf(z * 0.8))
	var grass := Color(0.3, 0.62, 0.18).lerp(Color(0.18, 0.47, 0.15), n)
	var c := grass
	# senderos de tierra hacia cada punto de interés
	var path_w := 0.0
	for target in [World.PYRAMID + Vector2(0, 9), World.SANCTUARY - Vector2(7, 0), World.CENOTE + Vector2(8, -6), World.LEDGE - Vector2(3, 4)]:
		var t: Vector2 = target
		var p := Vector2(x, z)
		var k := clampf(p.dot(t) / t.length_squared(), 0.0, 1.0)
		var d := (p - t * k).length()
		path_w = maxf(path_w, 1.0 - smoothstep(1.0, 2.4, d + n * 0.6))
	c = c.lerp(Color(0.62, 0.48, 0.3), path_w * 0.85)
	# plaza y explanadas de piedra
	var dp := Vector2(x, z).length()
	c = c.lerp(Color(0.6, 0.56, 0.46).lerp(Color(0.52, 0.49, 0.42), n), 1.0 - smoothstep(8.6, 9.6, dp))
	var dpy := maxf(absf(x - World.PYRAMID.x), absf(z - World.PYRAMID.y))
	c = c.lerp(Color(0.56, 0.51, 0.41), (1.0 - smoothstep(9.0, 11.0, dpy)) * 0.8)
	# orilla y fondo del cenote
	var dc := Vector2(x - World.CENOTE.x, z - World.CENOTE.y).length() / World.CENOTE_R
	c = c.lerp(Color(0.86, 0.8, 0.62), 1.0 - smoothstep(0.95, 1.35, dc))
	if h < World.WATER_LEVEL:
		c = c.lerp(Color(0.1, 0.36, 0.38), clampf((World.WATER_LEVEL - h) * 0.8, 0.0, 1.0))
	# colinas del borde
	c = c.lerp(Color(0.12, 0.3, 0.14), smoothstep(40.0, 52.0, dp))
	return c


func _terrain(root: Node3D) -> void:
	var n := 128
	var half := 60.0
	var step := half * 2.0 / n
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for iz in n + 1:
		for ix in n + 1:
			var x := -half + ix * step
			var z := -half + iz * step
			var h := World.terrain_h(x, z)
			var e := 0.4
			var nx := World.terrain_h(x - e, z) - World.terrain_h(x + e, z)
			var nz := World.terrain_h(x, z - e) - World.terrain_h(x, z + e)
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
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = m
	root.add_child(mi)


func _water(root: Node3D) -> void:
	var disc := CylinderMesh.new()
	disc.top_radius = World.CENOTE_R * 1.3
	disc.bottom_radius = disc.top_radius
	disc.height = 0.02
	disc.radial_segments = 48
	var sh := Shader.new()
	sh.code = """
shader_type spatial;
render_mode blend_mix, cull_back;
uniform vec2 center;
uniform float radius;
varying vec3 wpos;
void vertex() { wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }
void fragment() {
	float d = clamp(length(wpos.xz - center) / radius, 0.0, 1.0);
	float w = sin(wpos.x * 1.7 + TIME * 1.3) * sin(wpos.z * 1.9 - TIME * 1.1) * 0.5 + 0.5;
	float ring = sin(d * 26.0 - TIME * 1.5) * 0.5 + 0.5;
	vec3 deep = vec3(0.02, 0.32, 0.46);
	vec3 shallow = vec3(0.2, 0.88, 0.82);
	vec3 c = mix(deep, shallow, smoothstep(0.25, 1.0, d));
	ALBEDO = c + w * 0.05 + ring * 0.03;
	EMISSION = c * 0.22;
	ALPHA = mix(0.9, 0.62, smoothstep(0.5, 1.0, d));
	ROUGHNESS = 0.06;
	SPECULAR = 0.8;
}
"""
	var mat := ShaderMaterial.new()
	mat.shader = sh
	mat.set_shader_parameter("center", World.CENOTE)
	mat.set_shader_parameter("radius", World.CENOTE_R * 1.3)
	var mi := Avatar.part(disc, mat, Vector3(World.CENOTE.x, World.WATER_LEVEL, World.CENOTE.y))
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mi)


func _plaza(root: Node3D) -> void:
	var ring := TorusMesh.new()
	ring.inner_radius = 5.82
	ring.outer_radius = 6.0
	ring.rings = 48
	ring.ring_segments = 6
	root.add_child(Avatar.part(ring, Avatar.mat(JADE, 0.45, 0.5), Vector3(0, 0.02, 0), Vector3.ZERO, Vector3(1, 0.15, 1)))
	# brasero central
	var bowl := CylinderMesh.new()
	bowl.top_radius = 0.9
	bowl.bottom_radius = 0.55
	bowl.height = 0.7
	root.add_child(Avatar.part(bowl, Avatar.mat(STONE_DARK), Vector3(0, 0.35, 0)))
	# llama: dos conos encendidos y chispas que suben
	var flame := CylinderMesh.new()
	flame.top_radius = 0.0
	flame.bottom_radius = 0.5
	flame.height = 1.1
	flame.radial_segments = 10
	root.add_child(Avatar.part(flame, Avatar.mat(Color(1.0, 0.45, 0.1), 2.2), Vector3(0, 1.2, 0)))
	root.add_child(Avatar.part(flame, Avatar.mat(Color(1.0, 0.85, 0.35), 2.6), Vector3(0, 1.0, 0), Vector3.ZERO, Vector3(0.55, 0.7, 0.55)))
	var sparks := CPUParticles3D.new()
	sparks.amount = 14
	sparks.lifetime = 1.6
	sparks.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	sparks.emission_sphere_radius = 0.3
	sparks.direction = Vector3.UP
	sparks.spread = 18.0
	sparks.initial_velocity_min = 0.8
	sparks.initial_velocity_max = 1.8
	sparks.gravity = Vector3(0, 0.6, 0)
	var spark_mesh := SphereMesh.new()
	spark_mesh.radius = 0.04
	spark_mesh.height = 0.08
	spark_mesh.radial_segments = 6
	spark_mesh.rings = 3
	var spark_mat := StandardMaterial3D.new()
	spark_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	spark_mat.albedo_color = Color(1.0, 0.75, 0.3)
	spark_mesh.material = spark_mat
	sparks.mesh = spark_mesh
	sparks.position = Vector3(0, 1.3, 0)
	root.add_child(sparks)
	var fire := OmniLight3D.new()
	fire.light_color = AMBER
	fire.light_energy = 0.9
	fire.omni_range = 8.0
	fire.position = Vector3(0, 1.6, 0)
	root.add_child(fire)


func _box_mesh(b: Dictionary, material: Material) -> MeshInstance3D:
	var bm := BoxMesh.new()
	bm.size = Vector3(b.x1 - b.x0, b.top - b.y0, b.z1 - b.z0)
	return Avatar.part(bm, material, Vector3((b.x0 + b.x1) * 0.5, (b.top + b.y0) * 0.5, (b.z0 + b.z1) * 0.5))


func _boxes(root: Node3D) -> void:
	for b in World.boxes():
		match b.kind:
			"pyramid":
				var tier := int(str(b.id).trim_prefix("pyr"))
				root.add_child(_box_mesh(b, Avatar.mat(STONE.darkened(0.06 * tier).lerp(Color(0.8, 0.7, 0.5), 0.15))))
				# greca de jade en el frente de cada nivel
				var w: float = b.x1 - b.x0
				var trim := BoxMesh.new()
				trim.size = Vector3(w * 0.5, 0.12, 0.06)
				root.add_child(Avatar.part(trim, Avatar.mat(JADE, 1.2, 0.4), Vector3(World.PYRAMID.x, b.top - 0.4, b.z1 + 0.03)))
			"gate":
				_gate(root, b)
			"seal":
				_seal(root)
			"altar":
				root.add_child(_box_mesh(b, Avatar.mat(STONE.lightened(0.1))))
				_glyph(root, Vector3((b.x0 + b.x1) * 0.5, b.top + 1.1, (b.z0 + b.z1) * 0.5))
			"ledge":
				root.add_child(_box_mesh(b, Avatar.mat(STONE_DARK.lerp(Color(0.7, 0.45, 0.25), 0.25))))
				var paw := CylinderMesh.new()
				paw.top_radius = 1.2
				paw.bottom_radius = 1.2
				paw.height = 0.05
				root.add_child(Avatar.part(paw, Avatar.mat(AMBER, 1.6, 0.4), Vector3(World.LEDGE.x, b.top + 0.02, World.LEDGE.y)))
				var lamp := OmniLight3D.new()
				lamp.light_color = AMBER
				lamp.light_energy = 1.4
				lamp.omni_range = 7.0
				lamp.position = Vector3(World.LEDGE.x, b.top + 1.5, World.LEDGE.y)
				root.add_child(lamp)
			"wall":
				root.add_child(_box_mesh(b, Avatar.mat(STONE.darkened(0.12))))
			_:
				root.add_child(_box_mesh(b, Avatar.mat(STONE.lerp(Color(0.35, 0.5, 0.3), _rand() * 0.35))))

	# templo en la cima de la pirámide
	var top := BoxMesh.new()
	top.size = Vector3(2.6, 1.9, 2.6)
	root.add_child(Avatar.part(top, Avatar.mat(STONE.darkened(0.2)), Vector3(World.PYRAMID.x, 4.95, World.PYRAMID.y - 0.4)))
	var door := BoxMesh.new()
	door.size = Vector3(0.9, 1.3, 0.1)
	root.add_child(Avatar.part(door, Avatar.mat(JADE, 2.0), Vector3(World.PYRAMID.x, 4.65, World.PYRAMID.y + 0.92)))
	var roof := BoxMesh.new()
	roof.size = Vector3(3.1, 0.3, 3.1)
	root.add_child(Avatar.part(roof, Avatar.mat(STONE), Vector3(World.PYRAMID.x, 6.05, World.PYRAMID.y - 0.4)))

	# columnas
	for c in World.cylinders():
		if c.kind != "pillar":
			continue
		var cm := CylinderMesh.new()
		cm.top_radius = c.r * 0.85
		cm.bottom_radius = c.r
		cm.height = c.h
		cm.radial_segments = 12
		var y := World.terrain_h(c.x, c.z)
		root.add_child(Avatar.part(cm, Avatar.mat(STONE), Vector3(c.x, y + c.h * 0.5, c.z)))
		var cap := BoxMesh.new()
		cap.size = Vector3(c.r * 2.4, 0.3, c.r * 2.4)
		root.add_child(Avatar.part(cap, Avatar.mat(STONE_DARK), Vector3(c.x, y + c.h + 0.15, c.z)))


func _gate(root: Node3D, b: Dictionary) -> void:
	var cx: float = (b.x0 + b.x1) * 0.5
	var cz: float = (b.z0 + b.z1) * 0.5
	var base: float = b.top - 3.2
	# dintel fijo
	var lintel := BoxMesh.new()
	lintel.size = Vector3(1.3, 0.6, 4.6)
	root.add_child(Avatar.part(lintel, Avatar.mat(STONE_DARK), Vector3(cx, b.top + 0.3, cz)))
	# barrotes de energía que bajan cuando se abre
	gate_bars = Node3D.new()
	gate_bars.position = Vector3(cx, base, cz)
	var bar := CylinderMesh.new()
	bar.top_radius = 0.11
	bar.bottom_radius = 0.11
	bar.height = 3.2
	bar.radial_segments = 8
	var bar_mat := Avatar.mat(MAGENTA, 2.4, 0.3)
	for i in 7:
		gate_bars.add_child(Avatar.part(bar, bar_mat, Vector3(0, 1.6, -1.8 + i * 0.6)))
	var veil := BoxMesh.new()
	veil.size = Vector3(0.1, 3.2, 4.0)
	var veil_mat := StandardMaterial3D.new()
	veil_mat.albedo_color = Color(MAGENTA.r, MAGENTA.g, MAGENTA.b, 0.22)
	veil_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	veil_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	veil_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	gate_bars.add_child(Avatar.part(veil, veil_mat, Vector3(0, 1.6, 0)))
	root.add_child(gate_bars)
	gate_light = OmniLight3D.new()
	gate_light.light_color = MAGENTA
	gate_light.light_energy = 1.8
	gate_light.omni_range = 8.0
	gate_light.position = Vector3(cx - 1.0, base + 2.0, cz)
	root.add_child(gate_light)


## Velo de energía que cubre el santuario mientras está sellado (el sólido real es la caja "seal").
func _seal(root: Node3D) -> void:
	var dome := SphereMesh.new()
	dome.radius = 8.6
	dome.height = 11.0
	dome.radial_segments = 28
	dome.rings = 12
	dome.is_hemisphere = true
	seal_mat = StandardMaterial3D.new()
	seal_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	seal_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	seal_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	seal_mat.albedo_color = Color(MAGENTA.r, MAGENTA.g, MAGENTA.b, 0.16)
	seal_veil = Avatar.part(dome, seal_mat, Vector3(World.SANCTUARY.x, 0.0, World.SANCTUARY.y))
	seal_veil.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(seal_veil)


func _glyph(root: Node3D, pos: Vector3) -> void:
	glyph = Node3D.new()
	glyph.position = pos
	var prism := PrismMesh.new()
	prism.size = Vector3(0.7, 0.9, 0.7)
	glyph.add_child(Avatar.part(prism, Avatar.mat(JADE, 3.0, 0.2), Vector3(0, 0.25, 0)))
	glyph.add_child(Avatar.part(prism, Avatar.mat(JADE, 3.0, 0.2), Vector3(0, -0.25, 0), Vector3(PI, 0, 0)))
	var light := OmniLight3D.new()
	light.light_color = JADE
	light.light_energy = 2.0
	light.omni_range = 9.0
	glyph.add_child(light)
	root.add_child(glyph)


func _trees(root: Node3D) -> void:
	var trees: Array = []
	for c in World.cylinders():
		if c.kind == "tree":
			trees.append(c)
	var trunk := CylinderMesh.new()
	trunk.top_radius = 0.28
	trunk.bottom_radius = 0.48
	trunk.height = 1.0
	trunk.radial_segments = 8
	var canopy := SphereMesh.new()
	canopy.radius = 1.0
	canopy.height = 1.5
	canopy.radial_segments = 10
	canopy.rings = 5
	var vc := StandardMaterial3D.new()
	vc.vertex_color_use_as_albedo = true
	vc.roughness = 1.0

	var mm_t := MultiMesh.new()
	mm_t.transform_format = MultiMesh.TRANSFORM_3D
	mm_t.use_colors = true
	mm_t.mesh = trunk
	mm_t.instance_count = trees.size()
	var mm_c := MultiMesh.new()
	mm_c.transform_format = MultiMesh.TRANSFORM_3D
	mm_c.use_colors = true
	mm_c.mesh = canopy
	mm_c.instance_count = trees.size() * 3
	for i in trees.size():
		var t: Dictionary = trees[i]
		var s: float = t.s
		var y := World.terrain_h(t.x, t.z)
		var h: float = t.h
		mm_t.set_instance_transform(i, Transform3D(Basis().scaled(Vector3(s, h, s)), Vector3(t.x, y + h * 0.5, t.z)))
		mm_t.set_instance_color(i, Color(0.42, 0.3, 0.2).lerp(Color(0.55, 0.48, 0.4), _rand()))
		for k in 3:
			var off := Vector3((_rand() - 0.5) * 2.2 * s, h + (_rand() - 0.2) * 1.2 * s, (_rand() - 0.5) * 2.2 * s)
			var r := (1.9 + _rand() * 1.1) * s
			mm_c.set_instance_transform(i * 3 + k, Transform3D(Basis().scaled(Vector3(r, r * 0.85, r)), Vector3(t.x, y, t.z) + off))
			mm_c.set_instance_color(i * 3 + k, Color(0.16, 0.45, 0.18).lerp(Color(0.3, 0.6, 0.2), _rand()))
	for mm in [mm_t, mm_c]:
		var inst := MultiMeshInstance3D.new()
		inst.multimesh = mm
		inst.material_override = vc
		root.add_child(inst)


func _bushes(root: Node3D) -> void:
	var blob := SphereMesh.new()
	blob.radius = 0.5
	blob.height = 0.7
	blob.radial_segments = 8
	blob.rings = 4
	var vc := StandardMaterial3D.new()
	vc.vertex_color_use_as_albedo = true
	vc.roughness = 1.0
	var spots: Array[Transform3D] = []
	var cols: Array[Color] = []
	var tries := 0
	while spots.size() < 220 and tries < 2000:
		tries += 1
		var a := _rand() * TAU
		var r := 10.5 + _rand() * 36.0
		var x := cos(a) * r
		var z := sin(a) * r
		if Vector2(x - World.CENOTE.x, z - World.CENOTE.y).length() < World.CENOTE_R * 1.15:
			continue
		if absf(x - World.PYRAMID.x) < 9.0 and absf(z - World.PYRAMID.y) < 9.0:
			continue
		if absf(x - World.SANCTUARY.x) < 7.5 and absf(z - World.SANCTUARY.y) < 7.5:
			continue
		var blocked := false
		for p in World.PLATES:
			if Vector2(x - p.x, z - p.y).length() < 2.4:
				blocked = true
		if blocked:
			continue
		var s := 0.5 + _rand() * 1.1
		spots.append(Transform3D(Basis().scaled(Vector3(s * 1.3, s, s * 1.3)), Vector3(x, World.terrain_h(x, z) + 0.12 * s, z)))
		var flower := _rand() < 0.16
		cols.append(Color(0.95, 0.3, 0.6).lerp(Color(1.0, 0.8, 0.25), _rand()) if flower else Color(0.2, 0.5, 0.2).lerp(Color(0.38, 0.66, 0.24), _rand()))
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = blob
	mm.instance_count = spots.size()
	for i in spots.size():
		mm.set_instance_transform(i, spots[i])
		mm.set_instance_color(i, cols[i])
	var inst := MultiMeshInstance3D.new()
	inst.multimesh = mm
	inst.material_override = vc
	inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(inst)


func _plates(root: Node3D) -> void:
	_plate_idle = Avatar.mat(AMBER, 1.3, 0.4)
	_plate_on = Avatar.mat(JADE, 3.2, 0.4)
	var base := CylinderMesh.new()
	base.top_radius = World.PLATE_R
	base.bottom_radius = World.PLATE_R + 0.2
	base.height = 0.14
	base.radial_segments = 28
	var ring := TorusMesh.new()
	ring.inner_radius = World.PLATE_R - 0.3
	ring.outer_radius = World.PLATE_R - 0.08
	ring.rings = 32
	ring.ring_segments = 6
	var beam := CylinderMesh.new()
	beam.top_radius = World.PLATE_R * 0.75
	beam.bottom_radius = World.PLATE_R * 0.75
	beam.height = 7.0
	beam.radial_segments = 20
	beam.cap_top = false
	beam.cap_bottom = false
	var beam_mat := StandardMaterial3D.new()
	beam_mat.albedo_color = Color(JADE.r, JADE.g, JADE.b, 0.2)
	beam_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	beam_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	beam_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	for i in World.PLATES.size():
		var p := World.plate_pos(i)
		root.add_child(Avatar.part(base, Avatar.mat(STONE_DARK), p + Vector3(0, 0.03, 0)))
		var r := Avatar.part(ring, _plate_idle, p + Vector3(0, 0.11, 0), Vector3.ZERO, Vector3(1, 0.3, 1))
		root.add_child(r)
		plate_rings.append(r)
		var bm := Avatar.part(beam, beam_mat, p + Vector3(0, 3.5, 0))
		bm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		bm.visible = false
		root.add_child(bm)
		plate_beams.append(bm)


func set_plate(i: int, on: bool) -> void:
	plate_rings[i].material_override = _plate_on if on else _plate_idle
	plate_beams[i].visible = on


func _fireflies(root: Node3D) -> void:
	var p := CPUParticles3D.new()
	fireflies = p
	p.amount = 90
	p.lifetime = 7.0
	p.preprocess = 7.0
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	p.emission_box_extents = Vector3(40, 1.6, 40)
	p.position = Vector3(0, 2.0, 0)
	p.gravity = Vector3.ZERO
	p.direction = Vector3(1, 0.2, 0)
	p.spread = 180.0
	p.initial_velocity_min = 0.2
	p.initial_velocity_max = 0.7
	p.scale_amount_min = 0.6
	p.scale_amount_max = 1.4
	var m := SphereMesh.new()
	m.radius = 0.05
	m.height = 0.1
	m.radial_segments = 6
	m.rings = 3
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(1.0, 0.92, 0.45)
	m.material = mat
	p.mesh = m
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(p)
