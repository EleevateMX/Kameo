extends RefCounted
## Escenario de la plaza de «Mérida, la Ciudad Blanca»: una interpretación fantástica (arcos
## blancos, un gran árbol, una fuente, un quiosco, faroles al atardecer), no una reproducción de
## la plaza real. La geometría que importa para moverse está en zone_def.gd; esto sólo la dibuja.
## Prototipo: formas sencillas con el color del juego, sin texturas.

const Zone := preload("res://scripts/shared/zone_def.gd")

const WHITE := Color(0.86, 0.83, 0.77)
const WHITE_SHADE := Color(0.72, 0.69, 0.63)
const STONE := Color(0.6, 0.55, 0.46)
const STONE_DARK := Color(0.66, 0.6, 0.5)
const TILE := Color(0.7, 0.65, 0.55)
const TERRACOTTA := Color(0.76, 0.42, 0.28)
const LEAF := Color(0.24, 0.5, 0.25)
const LEAF_LIGHT := Color(0.38, 0.62, 0.3)
const BARK := Color(0.45, 0.33, 0.24)
const JADE := Color(0.18, 0.95, 0.72)
const WATER := Color(0.25, 0.75, 0.85)
const IRON := Color(0.16, 0.2, 0.2)

var portal_glow: MeshInstance3D
var water: MeshInstance3D
var _root: Node3D
var _mats := {}


func build(root: Node3D) -> void:
	_root = root
	_environment()
	_ground()
	_tree()
	_fountain()
	_kiosk()
	_arcade()
	_benches()
	_lamps()
	_portal()
	_edges()


func update(time: float) -> void:
	if portal_glow != null:
		var m := portal_glow.material_override as StandardMaterial3D
		m.emission_energy_multiplier = 1.0 + 0.35 * sin(time * 2.1)
	if water != null:
		water.position.y = 0.52 + 0.015 * sin(time * 1.7)


func _mat(color: Color, emission := 0.0, alpha := 1.0) -> StandardMaterial3D:
	var key := "%s|%s|%s" % [color.to_html(), emission, alpha]
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(color.r, color.g, color.b, alpha)
	m.roughness = 0.9
	if emission > 0.0:
		m.emission_enabled = true
		m.emission = color
		m.emission_energy_multiplier = emission
	if alpha < 1.0:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
	_mats[key] = m
	return m


func _add(mesh: Mesh, mat: Material, pos: Vector3, rot := Vector3.ZERO, shadow := true) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	mi.rotation = rot
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadow else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_root.add_child(mi)
	return mi


func _box(size: Vector3, color: Color, pos: Vector3, rot := Vector3.ZERO, shadow := true) -> MeshInstance3D:
	var m := BoxMesh.new()
	m.size = size
	return _add(m, _mat(color), pos, rot, shadow)


func _cyl(radius: float, height: float, color: Color, pos: Vector3, sides := 16, top := -1.0, shadow := true) -> MeshInstance3D:
	var m := CylinderMesh.new()
	m.bottom_radius = radius
	m.top_radius = radius if top < 0.0 else top
	m.height = height
	m.radial_segments = sides
	m.rings = 1
	return _add(m, _mat(color), pos + Vector3(0, height * 0.5, 0), Vector3.ZERO, shadow)


func _ball(radius: float, color: Color, pos: Vector3, squash := 1.0, emission := 0.0) -> MeshInstance3D:
	var m := SphereMesh.new()
	m.radius = radius
	m.height = radius * 2.0 * squash
	m.radial_segments = 12
	m.rings = 6
	return _add(m, _mat(color, emission), pos, Vector3.ZERO, emission <= 0.0)


func _environment() -> void:
	# Atardecer: cielo cálido, sol bajo y faroles encendidos
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.2, 0.3, 0.55)
	sky_mat.sky_horizon_color = Color(0.95, 0.6, 0.4)
	sky_mat.sky_energy_multiplier = 0.8
	sky_mat.ground_bottom_color = Color(0.2, 0.18, 0.2)
	sky_mat.ground_horizon_color = Color(0.9, 0.6, 0.42)
	sky_mat.sun_angle_max = 20.0
	var sky := Sky.new()
	sky.sky_material = sky_mat
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.62, 0.56, 0.66)
	env.ambient_light_energy = 0.5
	env.fog_enabled = true
	env.fog_light_color = Color(0.8, 0.56, 0.42)
	env.fog_density = 0.0016
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var we := WorldEnvironment.new()
	we.environment = env
	_root.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-24.0, -118.0, 0.0)
	sun.light_color = Color(1.0, 0.8, 0.58)
	sun.light_energy = 0.85
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	sun.directional_shadow_max_distance = 70.0
	_root.add_child(sun)


func _ground() -> void:
	var half := Zone.HALF
	_box(Vector3(half * 2.0 + 60.0, 0.2, half * 2.0 + 60.0), Color(0.52, 0.5, 0.36), Vector3(0, -0.14, 0), Vector3.ZERO, false)   # alrededores
	_box(Vector3(half * 2.0 + 1.2, 0.2, half * 2.0 + 1.2), TILE, Vector3(0, -0.1, 0), Vector3.ZERO, false)                          # losas de la plaza
	# Andadores en cruz y un anillo alrededor del árbol, de piedra más oscura
	_box(Vector3(half * 2.0, 0.02, 4.0), STONE, Vector3(0, 0.005, 0), Vector3.ZERO, false)
	_box(Vector3(4.0, 0.02, half * 2.0), STONE, Vector3(0, 0.006, 0), Vector3.ZERO, false)
	_cyl(7.0, 0.02, STONE, Vector3(0, -0.003, 0), 32, -1.0, false)
	_cyl(5.6, 0.02, TILE, Vector3(0, 0.0, 0), 32, -1.0, false)
	# Jardineras en los cuatro cuadrantes
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			_box(Vector3(9.0, 0.05, 6.0), Color(0.36, 0.56, 0.3), Vector3(sx * 20.0, 0.02, sz * 22.0), Vector3.ZERO, false)


func _tree() -> void:
	# El gran árbol del centro, con su arriate
	_cyl(2.6, 0.55, STONE_DARK, Vector3.ZERO, 20)
	_cyl(2.3, 0.6, Color(0.3, 0.24, 0.18), Vector3.ZERO, 20)
	_cyl(1.0, 6.0, BARK, Vector3.ZERO, 10, 0.7)
	for b in [[0.0, 7.4, 0.0, 4.6], [2.6, 6.6, 1.4, 3.2], [-2.4, 6.8, 1.8, 3.4], [1.2, 6.4, -2.6, 3.0], [-1.8, 6.2, -2.2, 3.1], [0.0, 9.0, 0.4, 3.0]]:
		_ball(float(b[3]), LEAF if int(b[3] * 10.0) % 2 == 0 else LEAF_LIGHT, Vector3(b[0], b[1], b[2]), 0.72)


func _fountain() -> void:
	var at := Vector3(-15.0, 0.0, 12.0)
	_cyl(2.5, 0.6, WHITE, at, 20)
	water = _add(_disc(2.15), _mat(WATER, 0.25, 0.85), at + Vector3(0, 0.52, 0), Vector3.ZERO, false)
	_cyl(0.45, 1.5, WHITE_SHADE, at, 10)
	_cyl(1.0, 0.18, WHITE, at + Vector3(0, 1.5, 0), 14)
	_ball(0.28, WATER, at + Vector3(0, 1.95, 0), 1.0, 0.6)


func _disc(radius: float) -> CylinderMesh:
	var m := CylinderMesh.new()
	m.bottom_radius = radius
	m.top_radius = radius
	m.height = 0.02
	m.radial_segments = 20
	return m


func _kiosk() -> void:
	var at := Vector3(15.0, 0.0, -13.0)
	_cyl(2.9, 0.5, WHITE, at, 8)
	for i in 8:
		var a := TAU * float(i) / 8.0 + TAU / 16.0
		_cyl(0.11, 2.6, IRON, at + Vector3(sin(a) * 2.5, 0.5, cos(a) * 2.5), 6)
	_cyl(3.3, 1.3, TERRACOTTA, at + Vector3(0, 3.1, 0), 8, 0.25)
	_ball(0.22, WHITE, at + Vector3(0, 4.55, 0))


func _arcade() -> void:
	# Lado norte: un edificio blanco con soportales
	_box(Vector3(Zone.HALF * 2.0, 6.5, 5.0), WHITE, Vector3(0, 3.25, -31.5))
	_box(Vector3(Zone.HALF * 2.0 + 0.6, 0.5, 5.6), TERRACOTTA, Vector3(0, 6.7, -31.5))
	_box(Vector3(60.0, 0.9, 1.5), WHITE, Vector3(0, 4.15, -27.5))        # dintel sobre las columnas
	_box(Vector3(60.0, 0.25, 3.4), WHITE_SHADE, Vector3(0, 4.7, -28.4))  # techo del soportal
	for p in Zone.PILLARS:
		if float(p[1]) == -27.5:
			_cyl(0.48, 3.7, WHITE, Vector3(p[0], 0.0, p[1]), 10)
			_box(Vector3(1.2, 0.25, 1.2), WHITE_SHADE, Vector3(p[0], 0.12, p[1]))
	# Puertas y ventanas (pintadas): oscuras en la pared
	for i in 9:
		var x := -24.0 + 6.0 * float(i)
		_box(Vector3(1.9, 3.0, 0.08), Color(0.3, 0.2, 0.16), Vector3(x, 1.5, -28.96), Vector3.ZERO, false)
		_box(Vector3(1.4, 1.2, 0.08), Color(0.2, 0.26, 0.3), Vector3(x, 5.2, -28.96), Vector3.ZERO, false)


func _benches() -> void:
	for b in Zone.BOXES:
		if float(b[2]) > 5.0:
			continue   # (el edificio ya está dibujado)
		_box(Vector3(float(b[2]) * 2.0, 0.42, float(b[3]) * 2.0), WHITE, Vector3(b[0], 0.21, b[1]))
		_box(Vector3(float(b[2]) * 2.0 + 0.12, 0.08, float(b[3]) * 2.0 + 0.12), Color(0.46, 0.32, 0.22), Vector3(b[0], 0.46, b[1]))


func _lamps() -> void:
	var n := 0
	for p in Zone.PILLARS:
		if float(p[2]) != 0.25:
			continue
		var at := Vector3(p[0], 0.0, p[1])
		_cyl(0.09, 3.2, IRON, at, 6)
		_ball(0.2, Color(1.0, 0.82, 0.5), at + Vector3(0, 3.33, 0), 1.0, 1.1)
		# (pocas luces de verdad: el resto de faroles sólo brilla)
		if n < 4:
			var light := OmniLight3D.new()
			light.position = at + Vector3(0, 3.3, 0)
			light.light_color = Color(1.0, 0.78, 0.45)
			light.light_energy = 0.9
			light.omni_range = 10.0
			_root.add_child(light)
		n += 1


func _portal() -> void:
	# Lado este: el portal al Claro de los Aluxes, de piedra antigua y con luz de jade
	var c := Zone.PORTAL
	for z in [-2.4, 2.4]:
		_cyl(0.7, 4.4, STONE_DARK, Vector3(c.x, 0.0, c.y + z), 8)
	_box(Vector3(1.5, 0.9, 6.6), STONE_DARK, Vector3(c.x, 4.8, c.y))
	_box(Vector3(1.0, 0.4, 3.0), STONE, Vector3(c.x, 5.45, c.y))
	var plane := QuadMesh.new()
	plane.size = Vector2(3.4, 4.2)
	portal_glow = _add(plane, _mat(JADE, 1.2, 0.5), Vector3(c.x + 0.15, 2.2, c.y), Vector3(0, -PI * 0.5, 0), false)
	var light := OmniLight3D.new()
	light.position = Vector3(c.x - 1.5, 2.2, c.y)
	light.light_color = JADE
	light.light_energy = 1.0
	light.omni_range = 8.0
	_root.add_child(light)
	var label := Label3D.new()
	label.text = "Claro de los Aluxes"
	label.font_size = 64
	label.pixel_size = 0.006
	label.outline_size = 14
	label.modulate = Color(0.85, 1.0, 0.95)
	label.position = Vector3(c.x - 0.9, 5.5, c.y)
	label.rotation.y = -PI * 0.5
	_root.add_child(label)
	# Camino de piedra antigua hasta el portal
	_box(Vector3(14.0, 0.03, 4.4), STONE_DARK, Vector3(c.x - 7.0, 0.012, c.y), Vector3.ZERO, false)


func _edges() -> void:
	var half := Zone.HALF
	# Pretiles bajos en los lados oeste, sur y este (el norte es el edificio)
	_box(Vector3(0.6, 1.1, half * 2.0), WHITE, Vector3(-half - 0.3, 0.55, 0))
	_box(Vector3(half * 2.0 + 1.2, 1.1, 0.6), WHITE, Vector3(0, 0.55, half + 0.3))
	_box(Vector3(0.6, 1.1, half - 3.6), WHITE, Vector3(half + 0.3, 0.55, -(half + 3.6) * 0.5))
	_box(Vector3(0.6, 1.1, half - 3.6), WHITE, Vector3(half + 0.3, 0.55, (half + 3.6) * 0.5))
	# Árboles y casas bajas más allá, para que la plaza no flote en el vacío
	for i in 14:
		var a := TAU * float(i) / 14.0 + 0.2
		var r := half + 9.0 + 5.0 * float(i % 3)
		var at := Vector3(sin(a) * r, 0.0, cos(a) * r)
		if at.z < -half:
			continue
		if i % 2 == 0:
			_cyl(0.35, 3.0, BARK, at, 6)
			_ball(2.6, LEAF if i % 4 == 0 else LEAF_LIGHT, at + Vector3(0, 4.4, 0), 0.8)
		else:
			_box(Vector3(7.0, 4.0, 6.0), [WHITE, Color(0.95, 0.8, 0.5), Color(0.85, 0.6, 0.55)][i % 3], at + Vector3(0, 2.0, 0))
			_box(Vector3(7.4, 0.4, 6.4), TERRACOTTA, at + Vector3(0, 4.2, 0))
