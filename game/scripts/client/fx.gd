extends RefCounted
## Efectos visuales de combate. Son puramente decorativos: se disparan con los
## eventos que autoriza el servidor (o con la predicción del propio jugador).

static func glow_mat(color: Color, alpha := 1.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Color(color.r, color.g, color.b, alpha)
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	if alpha < 1.0:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	return m


static func _fade_and_free(node: Node3D, mat: StandardMaterial3D, dur: float, grow := Vector3.ONE) -> void:
	var tw := node.create_tween()
	tw.set_parallel(true)
	tw.tween_property(mat, "albedo_color:a", 0.0, dur)
	if grow != Vector3.ONE:
		tw.tween_property(node, "scale", node.scale * grow, dur).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tw.chain().tween_callback(node.queue_free)


## Arco de garra: un abanico plano que se abre frente al atacante.
static func slash(parent: Node, pos: Vector3, yaw: float, radius: float, arc: float, color: Color, dur := 0.22) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var seg := 14
	var inner := radius * 0.45
	for i in seg:
		var a0 := -arc * 0.5 + arc * float(i) / seg
		var a1 := -arc * 0.5 + arc * float(i + 1) / seg
		var p0 := Vector3(sin(a0) * inner, 0, cos(a0) * inner)
		var p1 := Vector3(sin(a0) * radius, 0, cos(a0) * radius)
		var p2 := Vector3(sin(a1) * radius, 0, cos(a1) * radius)
		var p3 := Vector3(sin(a1) * inner, 0, cos(a1) * inner)
		for v in [p0, p1, p2, p0, p2, p3]:
			st.add_vertex(v)
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	var mat := glow_mat(color, 0.85)
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.position = pos
	mi.rotation = Vector3(-0.25, yaw, 0)
	mi.scale = Vector3(0.6, 1, 0.6)
	parent.add_child(mi)
	_fade_and_free(mi, mat, dur, Vector3(1.7, 1, 1.7))


## Onda expansiva a ras de suelo (salto de Balam, golpe del guardián).
static func ring(parent: Node, pos: Vector3, radius: float, color: Color, dur := 0.4) -> void:
	var t := TorusMesh.new()
	t.inner_radius = 0.82
	t.outer_radius = 1.0
	t.rings = 28
	t.ring_segments = 6
	var mi := MeshInstance3D.new()
	mi.mesh = t
	var mat := glow_mat(color, 0.9)
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.position = pos + Vector3(0, 0.08, 0)
	mi.scale = Vector3(0.3, 0.25, 0.3)
	parent.add_child(mi)
	_fade_and_free(mi, mat, dur, Vector3(radius / 0.3, 1, radius / 0.3))


static func burst(parent: Node, pos: Vector3, color: Color, amount := 14, speed := 4.0, size := 0.07, life := 0.5) -> void:
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.explosiveness = 1.0
	p.amount = amount
	p.lifetime = life
	p.direction = Vector3.UP
	p.spread = 180.0
	p.initial_velocity_min = speed * 0.4
	p.initial_velocity_max = speed
	p.gravity = Vector3(0, -6, 0)
	p.scale_amount_min = 0.5
	p.scale_amount_max = 1.3
	var m := SphereMesh.new()
	m.radius = size
	m.height = size * 2.0
	m.radial_segments = 6
	m.rings = 3
	m.material = glow_mat(color)
	p.mesh = m
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.position = pos
	parent.add_child(p)
	p.emitting = true
	parent.get_tree().create_timer(life + 0.4).timeout.connect(p.queue_free)


## Número de daño o curación que sube y se desvanece.
static func number(parent: Node, pos: Vector3, text: String, color: Color, big := false) -> void:
	var l := Label3D.new()
	l.text = text
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.no_depth_test = true
	l.fixed_size = true
	l.pixel_size = 0.0011 if big else 0.0008
	l.font_size = 64
	l.outline_size = 18
	l.modulate = color
	l.outline_modulate = Color(0.05, 0.05, 0.05, 0.9)
	l.position = pos + Vector3(randf_range(-0.3, 0.3), 0, randf_range(-0.3, 0.3))
	parent.add_child(l)
	var tw := l.create_tween()
	tw.set_parallel(true)
	tw.tween_property(l, "position:y", l.position.y + 1.3, 0.8).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tw.tween_property(l, "modulate:a", 0.0, 0.8).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_CUBIC)
	tw.tween_property(l, "outline_modulate:a", 0.0, 0.8).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_CUBIC)
	tw.chain().tween_callback(l.queue_free)


## Aviso en el suelo de dónde va a caer un golpe enemigo.
static func telegraph(parent: Node, pos: Vector3, radius: float, dur: float) -> void:
	var c := CylinderMesh.new()
	c.top_radius = radius
	c.bottom_radius = radius
	c.height = 0.04
	c.radial_segments = 28
	var mi := MeshInstance3D.new()
	mi.mesh = c
	var mat := glow_mat(Color(1.0, 0.25, 0.2), 0.0)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.position = pos + Vector3(0, 0.06, 0)
	parent.add_child(mi)
	var tw := mi.create_tween()
	tw.tween_property(mat, "albedo_color:a", 0.45, dur)
	tw.tween_property(mat, "albedo_color:a", 0.0, 0.15)
	tw.tween_callback(mi.queue_free)


## Chispa de jade (proyectil del alux). Devuelve el nodo para moverlo y retirarlo.
static func make_bolt(parent: Node, color: Color) -> Node3D:
	var root := Node3D.new()
	var s := SphereMesh.new()
	s.radius = 0.2
	s.height = 0.4
	s.radial_segments = 10
	s.rings = 5
	var core := MeshInstance3D.new()
	core.mesh = s
	core.material_override = glow_mat(Color(0.85, 1.0, 0.95))
	core.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(core)
	var halo := MeshInstance3D.new()
	halo.mesh = s
	halo.scale = Vector3(1.9, 1.9, 1.9)
	halo.material_override = glow_mat(color, 0.35)
	halo.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(halo)
	var trail := CPUParticles3D.new()
	trail.amount = 12
	trail.lifetime = 0.35
	trail.local_coords = false
	trail.gravity = Vector3.ZERO
	trail.initial_velocity_max = 0.4
	trail.spread = 180.0
	trail.scale_amount_min = 0.4
	trail.scale_amount_max = 1.0
	var m := SphereMesh.new()
	m.radius = 0.07
	m.height = 0.14
	m.radial_segments = 6
	m.rings = 3
	m.material = glow_mat(color)
	trail.mesh = m
	trail.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(trail)
	parent.add_child(root)
	return root


## Curación: motas verdes que suben y un aro suave.
static func heal(parent: Node, pos: Vector3) -> void:
	ring(parent, pos, 1.3, Color(0.45, 1.0, 0.6), 0.5)
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.explosiveness = 0.6
	p.amount = 16
	p.lifetime = 0.9
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = 0.5
	p.direction = Vector3.UP
	p.spread = 12.0
	p.initial_velocity_min = 1.2
	p.initial_velocity_max = 2.4
	p.gravity = Vector3(0, 0.5, 0)
	p.scale_amount_min = 0.5
	p.scale_amount_max = 1.2
	var m := SphereMesh.new()
	m.radius = 0.06
	m.height = 0.12
	m.radial_segments = 6
	m.rings = 3
	m.material = glow_mat(Color(0.55, 1.0, 0.65))
	p.mesh = m
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.position = pos + Vector3(0, 0.3, 0)
	parent.add_child(p)
	p.emitting = true
	parent.get_tree().create_timer(1.4).timeout.connect(p.queue_free)


## Columna de luz que sube y se desvanece (transformación, reaparición).
static func pillar(parent: Node, pos: Vector3, color: Color, height := 6.0, radius := 0.9, dur := 0.55) -> void:
	var c := CylinderMesh.new()
	c.top_radius = radius * 0.55
	c.bottom_radius = radius
	c.height = height
	c.radial_segments = 14
	c.cap_top = false
	c.cap_bottom = false
	var mi := MeshInstance3D.new()
	mi.mesh = c
	var mat := glow_mat(color, 0.55)
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.position = pos + Vector3(0, height * 0.5, 0)
	mi.scale = Vector3(1.0, 0.15, 1.0)
	parent.add_child(mi)
	var tw := mi.create_tween()
	tw.set_parallel(true)
	tw.tween_property(mi, "scale", Vector3(0.25, 1.0, 0.25), dur).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUART)
	tw.tween_property(mat, "albedo_color:a", 0.0, dur).set_ease(Tween.EASE_IN)
	tw.chain().tween_callback(mi.queue_free)


## Transformación: columna de luz, dos ondas, chispas en espiral y un glifo que gira en el suelo.
static func transform_burst(parent: Node, pos: Vector3, color: Color, accent: Color) -> void:
	pillar(parent, pos, color.lightened(0.3), 7.0, 1.1)
	ring(parent, pos, 2.6, color, 0.5)
	ring(parent, pos + Vector3(0, 0.05, 0), 1.5, accent, 0.7)
	burst(parent, pos + Vector3(0, 0.9, 0), accent, 34, 5.5, 0.07, 0.8)
	# chispas que suben en espiral
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.explosiveness = 0.2
	p.amount = 26
	p.lifetime = 0.9
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_RING
	p.emission_ring_axis = Vector3.UP
	p.emission_ring_radius = 0.9
	p.emission_ring_inner_radius = 0.7
	p.emission_ring_height = 0.1
	p.direction = Vector3.UP
	p.spread = 6.0
	p.initial_velocity_min = 2.5
	p.initial_velocity_max = 4.5
	p.orbit_velocity_min = 0.9
	p.orbit_velocity_max = 1.4
	p.gravity = Vector3.ZERO
	p.scale_amount_min = 0.6
	p.scale_amount_max = 1.3
	var m := SphereMesh.new()
	m.radius = 0.06
	m.height = 0.12
	m.radial_segments = 6
	m.rings = 3
	m.material = glow_mat(color.lightened(0.5))
	p.mesh = m
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.position = pos + Vector3(0, 0.2, 0)
	parent.add_child(p)
	p.emitting = true
	parent.get_tree().create_timer(1.5).timeout.connect(p.queue_free)
	# glifo de ocho trazos en el suelo
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in 8:
		var a := TAU * float(i) / 8.0
		var d := Vector3(cos(a), 0, sin(a))
		var t := Vector3(-sin(a), 0, cos(a)) * 0.09
		for v in [d * 0.7 - t, d * 0.7 + t, d * 1.5 + t, d * 0.7 - t, d * 1.5 + t, d * 1.5 - t]:
			st.add_vertex(v)
	var gi := MeshInstance3D.new()
	gi.mesh = st.commit()
	var gm := glow_mat(accent, 0.9)
	gi.material_override = gm
	gi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	gi.position = pos + Vector3(0, 0.1, 0)
	parent.add_child(gi)
	var gt := gi.create_tween()
	gt.set_parallel(true)
	gt.tween_property(gi, "rotation:y", 2.4, 0.8).set_ease(Tween.EASE_OUT)
	gt.tween_property(gi, "scale", Vector3(1.5, 1, 1.5), 0.8).set_ease(Tween.EASE_OUT)
	gt.tween_property(gm, "albedo_color:a", 0.0, 0.8).set_ease(Tween.EASE_IN)
	gt.chain().tween_callback(gi.queue_free)


## Tres zarpazos paralelos (garras de Balam).
static func claws(parent: Node, pos: Vector3, yaw: float, radius: float, arc: float, color: Color, dur := 0.22) -> void:
	for i in 3:
		var offset := Vector3(0, 0.28 * (i - 1), 0)
		slash(parent, pos + offset, yaw + 0.05 * (i - 1), radius * (1.0 - 0.06 * absf(i - 1.0)), arc * 0.9, color.lightened(0.15 * i), dur + 0.03 * i)
