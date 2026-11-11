extends Node3D
## Personaje visible: un alux y su forma de Balam, modelados con primitivas.
## No contiene reglas de juego: sólo muestra el estado que decide el servidor.

const SKIN := Color(0.66, 0.44, 0.29)
const STRAW := Color(0.74, 0.56, 0.30)
const EYE := Color(0.35, 1.0, 0.88)

var player_name := "Alux"
var color := Color("#2ec4a6")
var hat := 0
var form := "alux"
var online := true

var _alux: Node3D
var _balam: Node3D
var _label: Label3D
var _phase := 0.0
var _alux_limbs: Array[Node3D] = []
var _balam_legs: Array[Node3D] = []
var _balam_tail: Node3D
var _last_pos := Vector3.ZERO
var _has_last := false


func setup(p_name: String, color_hex: String, p_hat: int) -> void:
	player_name = p_name
	color = Color.from_string(color_hex, Color("#2ec4a6"))
	hat = p_hat
	for c in get_children():
		c.queue_free()
	_alux_limbs.clear()
	_balam_legs.clear()
	_alux = _build_alux()
	_balam = _build_balam()
	add_child(_alux)
	add_child(_balam)
	_label = Label3D.new()
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.no_depth_test = true
	_label.fixed_size = false
	_label.pixel_size = 0.0055
	_label.font_size = 44
	_label.outline_size = 14
	_label.outline_modulate = Color(0.05, 0.08, 0.07, 0.9)
	_label.position = Vector3(0, 2.05, 0)
	add_child(_label)
	_apply()


func set_form(f: String, with_effect := true) -> void:
	if f == form:
		return
	form = f
	_apply()
	if with_effect:
		_puff()


func set_online(on: bool) -> void:
	if on == online:
		return
	online = on
	_apply()


func _apply() -> void:
	if _alux == null:
		return
	_alux.visible = online and form == "alux"
	_balam.visible = online and form == "balam"
	_label.text = player_name if online else player_name + " (desconectado)"
	_label.modulate = Color(1, 1, 1, 1) if online else Color(1, 1, 1, 0.45)
	_label.position.y = 2.05 if form == "alux" else 1.75


## Animación procedimental según lo que se movió desde el cuadro anterior.
func animate(delta: float, grounded: bool, swim: bool) -> void:
	var speed := 0.0
	if _has_last and delta > 0.0:
		var d := global_position - _last_pos
		speed = Vector2(d.x, d.z).length() / delta
	_last_pos = global_position
	_has_last = true
	var moving := speed > 0.4
	_phase += delta * (4.0 + speed * 1.6) if moving else 0.0
	var swing := sin(_phase) * (0.75 if moving else 0.0)
	var bob := absf(sin(_phase)) * 0.05 if moving and grounded else 0.0
	if form == "alux":
		_alux.position.y = bob - (0.35 if swim else 0.0)
		_alux.rotation.x = lerp_angle(_alux.rotation.x, 0.5 if swim else (0.12 if moving else 0.0), minf(1.0, delta * 10.0))
		if _alux_limbs.size() == 4:
			var air := 0.0 if grounded or swim else 0.9
			_alux_limbs[0].rotation.x = swing + air
			_alux_limbs[1].rotation.x = -swing + air
			_alux_limbs[2].rotation.x = -swing - air * 1.4
			_alux_limbs[3].rotation.x = swing - air * 1.4
	else:
		_balam.position.y = bob * 1.4 - (0.3 if swim else 0.0)
		for i in _balam_legs.size():
			var s := swing if (i == 0 or i == 3) else -swing
			_balam_legs[i].rotation.x = s * 0.9 if grounded or swim else (0.9 if i < 2 else -0.9)
		if _balam_tail:
			_balam_tail.rotation.y = sin(Time.get_ticks_msec() * 0.004) * 0.4


func _puff() -> void:
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.explosiveness = 0.95
	p.amount = 28
	p.lifetime = 0.7
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = 0.4
	p.direction = Vector3.UP
	p.spread = 180.0
	p.initial_velocity_min = 2.0
	p.initial_velocity_max = 4.5
	p.gravity = Vector3(0, -3, 0)
	p.scale_amount_min = 0.5
	p.scale_amount_max = 1.2
	var m := SphereMesh.new()
	m.radius = 0.08
	m.height = 0.16
	m.radial_segments = 6
	m.rings = 3
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(1.0, 0.82, 0.3) if form == "balam" else color.lightened(0.3)
	m.material = mat
	p.mesh = m
	p.position = Vector3(0, 0.8, 0)
	add_child(p)
	p.emitting = true
	get_tree().create_timer(1.2).timeout.connect(p.queue_free)


# ───────────────────────── Construcción de modelos ─────────────────────────

static func mat(c: Color, emission := 0.0, rough := 0.85) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	if emission > 0.0:
		m.emission_enabled = true
		m.emission = c
		m.emission_energy_multiplier = emission
	return m


static func part(mesh: Mesh, material: Material, pos: Vector3, rot := Vector3.ZERO, scl := Vector3.ONE) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = material
	mi.position = pos
	mi.rotation = rot
	mi.scale = scl
	return mi


static func _sphere(r: float) -> SphereMesh:
	var s := SphereMesh.new()
	s.radius = r
	s.height = r * 2.0
	s.radial_segments = 20
	s.rings = 10
	return s


static func _capsule(r: float, h: float) -> CapsuleMesh:
	var c := CapsuleMesh.new()
	c.radius = r
	c.height = h
	c.radial_segments = 14
	c.rings = 4
	return c


static func _cone(top: float, bottom: float, h: float, seg := 20) -> CylinderMesh:
	var c := CylinderMesh.new()
	c.top_radius = top
	c.bottom_radius = bottom
	c.height = h
	c.radial_segments = seg
	c.rings = 1
	return c


## Extremidad con el pivote arriba, para poder balancearla.
static func _limb(r: float, h: float, material: Material, pos: Vector3) -> Node3D:
	var pivot := Node3D.new()
	pivot.position = pos
	pivot.add_child(part(_capsule(r, h), material, Vector3(0, -h * 0.5 + r, 0)))
	return pivot


func _build_alux() -> Node3D:
	var root := Node3D.new()
	var skin := mat(SKIN)
	var tunic := mat(color)
	var tunic_light := mat(color.lightened(0.25))
	var gold := mat(Color(0.95, 0.75, 0.25), 0.15, 0.4)
	var eye := mat(EYE, 1.5, 0.2)

	# piernas y brazos (con pivote para animar)
	var leg_l := _limb(0.09, 0.36, skin, Vector3(0.12, 0.36, 0))
	var leg_r := _limb(0.09, 0.36, skin, Vector3(-0.12, 0.36, 0))
	var arm_l := _limb(0.07, 0.36, skin, Vector3(0.3, 0.78, 0))
	var arm_r := _limb(0.07, 0.36, skin, Vector3(-0.3, 0.78, 0))
	for l in [leg_l, leg_r, arm_l, arm_r]:
		root.add_child(l)
		_alux_limbs.append(l)

	# túnica en dos capas, como plumas
	root.add_child(part(_cone(0.2, 0.34, 0.5), tunic, Vector3(0, 0.55, 0)))
	root.add_child(part(_cone(0.24, 0.33, 0.2, 12), tunic_light, Vector3(0, 0.72, 0)))
	root.add_child(part(_cone(0.26, 0.27, 0.06), gold, Vector3(0, 0.52, 0)))

	# cabeza grande y ojos que brillan
	root.add_child(part(_sphere(0.3), skin, Vector3(0, 1.03, 0)))
	root.add_child(part(_sphere(0.085), eye, Vector3(0.115, 1.06, 0.245)))
	root.add_child(part(_sphere(0.085), eye, Vector3(-0.115, 1.06, 0.245)))
	root.add_child(part(_sphere(0.09), skin, Vector3(0.3, 1.02, 0), Vector3.ZERO, Vector3(0.5, 1, 0.8)))
	root.add_child(part(_sphere(0.09), skin, Vector3(-0.3, 1.02, 0), Vector3.ZERO, Vector3(0.5, 1, 0.8)))

	match hat:
		0:  # sombrero de palma
			root.add_child(part(_cone(0.03, 0.52, 0.4, 16), mat(STRAW), Vector3(0, 1.42, 0)))
			root.add_child(part(_cone(0.5, 0.53, 0.04, 16), mat(STRAW.darkened(0.2)), Vector3(0, 1.22, 0)))
		1:  # penacho
			root.add_child(part(_cone(0.3, 0.31, 0.08), gold, Vector3(0, 1.25, 0)))
			var box := BoxMesh.new()
			box.size = Vector3(0.1, 0.5, 0.03)
			for i in 7:
				var a := (float(i) - 3.0) * 0.28
				var fc := color if i % 2 == 0 else Color(0.95, 0.85, 0.3)
				root.add_child(part(box, mat(fc), Vector3(sin(a) * 0.3, 1.45 + cos(a) * 0.14, -0.1), Vector3(-0.25, 0, -a)))
		2:  # flor de mayo
			root.add_child(part(_sphere(0.31), mat(Color(0.12, 0.09, 0.08)), Vector3(0, 1.08, -0.03), Vector3.ZERO, Vector3(1, 0.85, 1)))
			for i in 5:
				var a := float(i) / 5.0 * TAU
				root.add_child(part(_sphere(0.07), mat(Color(1, 0.95, 0.9)), Vector3(0.2 + cos(a) * 0.07, 1.3 + sin(a) * 0.07, 0.12)))
			root.add_child(part(_sphere(0.05), mat(Color(1, 0.8, 0.2), 0.6), Vector3(0.2, 1.3, 0.15)))
		_:  # sin sombrero: cabello
			root.add_child(part(_sphere(0.31), mat(Color(0.12, 0.09, 0.08)), Vector3(0, 1.08, -0.03), Vector3.ZERO, Vector3(1, 0.85, 1)))
	return root


func _build_balam() -> Node3D:
	var root := Node3D.new()
	var fur := mat(Color(0.93, 0.6, 0.2))
	var cream := mat(Color(0.98, 0.9, 0.72))
	var dark := mat(Color(0.2, 0.12, 0.06))
	var eye := mat(EYE, 1.5, 0.2)
	var collar := mat(color, 0.4)

	root.add_child(part(_capsule(0.3, 1.25), fur, Vector3(0, 0.66, 0), Vector3(PI * 0.5, 0, 0)))
	root.add_child(part(_capsule(0.24, 1.0), cream, Vector3(0, 0.56, 0), Vector3(PI * 0.5, 0, 0), Vector3(0.9, 1, 0.8)))
	root.add_child(part(_sphere(0.3), fur, Vector3(0, 0.92, 0.66)))
	root.add_child(part(_sphere(0.16), cream, Vector3(0, 0.83, 0.9)))
	root.add_child(part(_sphere(0.05), dark, Vector3(0, 0.88, 1.04)))
	root.add_child(part(_sphere(0.07), eye, Vector3(0.13, 0.99, 0.9)))
	root.add_child(part(_sphere(0.07), eye, Vector3(-0.13, 0.99, 0.9)))
	root.add_child(part(_cone(0.0, 0.1, 0.16, 8), fur, Vector3(0.19, 1.2, 0.6)))
	root.add_child(part(_cone(0.0, 0.1, 0.16, 8), fur, Vector3(-0.19, 1.2, 0.6)))

	# collar con el color del jugador, para reconocerlo transformado
	var torus := TorusMesh.new()
	torus.inner_radius = 0.25
	torus.outer_radius = 0.34
	torus.rings = 20
	torus.ring_segments = 8
	root.add_child(part(torus, collar, Vector3(0, 0.78, 0.42), Vector3(PI * 0.5, 0, 0)))

	for p in [Vector3(0.2, 0.52, 0.42), Vector3(-0.2, 0.52, 0.42), Vector3(0.2, 0.52, -0.42), Vector3(-0.2, 0.52, -0.42)]:
		var leg := _limb(0.095, 0.54, fur, p)
		root.add_child(leg)
		_balam_legs.append(leg)

	_balam_tail = Node3D.new()
	_balam_tail.position = Vector3(0, 0.8, -0.6)
	_balam_tail.add_child(part(_capsule(0.055, 0.8), fur, Vector3(0, 0.2, -0.3), Vector3(-1.0, 0, 0)))
	_balam_tail.add_child(part(_sphere(0.08), dark, Vector3(0, 0.42, -0.62)))
	root.add_child(_balam_tail)

	# manchas
	var spots := [
		Vector3(0.24, 0.85, 0.2), Vector3(-0.25, 0.8, 0.05), Vector3(0.2, 0.9, -0.2), Vector3(-0.2, 0.9, -0.3),
		Vector3(0.0, 0.96, 0.1), Vector3(0.0, 0.96, -0.25), Vector3(0.27, 0.7, -0.05), Vector3(-0.27, 0.68, 0.3),
	]
	for s in spots:
		root.add_child(part(_sphere(0.06), dark, s, Vector3.ZERO, Vector3(1, 0.5, 1)))
	return root
