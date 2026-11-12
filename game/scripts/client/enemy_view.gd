extends Node3D
## Enemigo visible. Sólo representa lo que dice el servidor: posición, vida y estado.
## Modelos provisionales hechos con primitivas (pendientes de arte definitivo).
## Lo que sí debe leerse siempre: quién es (nombre), qué va a hacer (aviso «!» al preparar
## un golpe), cuándo está aturdido (estrellas girando) y cuándo se puede purificar (anillo de
## jade en el suelo y la tecla F sobre la cabeza).

const Avatar := preload("res://scripts/client/avatar.gd")
const Defs := preload("res://scripts/shared/combat_def.gd")
const Fx := preload("res://scripts/client/fx.gd")
const Audio := preload("res://scripts/client/audio.gd")

const INTERP_DELAY := 0.13

var enemy_id := 0
var kind := "piedra"
var state := "idle"
var hp := 1.0
var max_hp := 1.0
var dying := false

var _buf: Array = []
var _model: Node3D
var _parts := {}
var _bar: Node3D
var _bar_fill: MeshInstance3D
var _phase := 0.0
var _flash := 0.0
var _last := Vector3.ZERO
var _state_t := 0.0
var _eye_mat: StandardMaterial3D
var _height := 1.5
var _mark: Label3D           # «!» de ataque o «F» de purificar
var _name: Label3D
var _stars: Node3D           # aturdido
var _ring: MeshInstance3D    # purificable
var _purifiable := false


func setup(id: int, p_kind: String) -> void:
	enemy_id = id
	kind = p_kind
	_height = Defs.ENEMIES[kind].height
	_model = _build_piedra() if kind == "piedra" else _build_corrupta()
	add_child(_model)
	_build_bar()
	_build_marks()


func push_state(t: float, pos: Vector3, yaw: float, p_hp: float, p_max: float, p_state: String) -> void:
	_buf.append({"t": t, "pos": pos, "yaw": yaw})
	while _buf.size() > 12:
		_buf.pop_front()
	hp = p_hp
	max_hp = p_max
	if p_state != state:
		_on_state(p_state)
		state = p_state
		_state_t = 0.0
	if _buf.size() == 1:
		global_position = pos
		rotation.y = yaw
		_last = pos


func _on_state(next: String) -> void:
	var def: Dictionary = Defs.ENEMIES[kind]
	if next == "windup":
		if kind == "piedra":
			# aviso en el suelo del área que va a golpear
			var fwd := Vector3(sin(rotation.y), 0, cos(rotation.y))
			Fx.telegraph(get_parent(), global_position + fwd * 1.0, def.hit_radius, def.windup)
		else:
			Fx.burst(get_parent(), global_position + Vector3(0, 0.6, 0), Color(1.0, 0.2, 0.7), 8, 2.0, 0.05, 0.35)
		Audio.play(("guardian_llamada" if kind == "piedra" else "criatura_llamada") + "|enemigo_aviso", global_position, -4.0)
	elif next == "dead":
		dying = true


func show_bar_for_prewarm() -> void:
	_bar.visible = true


func hit_flash() -> void:
	_flash = 0.16


## Golpe del guardián de piedra (onda en el suelo).
func slam() -> void:
	var fwd := Vector3(sin(rotation.y), 0, cos(rotation.y))
	Fx.ring(get_parent(), global_position + fwd * 1.0, Defs.ENEMIES[kind].hit_radius, Color(1.0, 0.7, 0.3), 0.35)
	Fx.burst(get_parent(), global_position + fwd * 1.0 + Vector3(0, 0.2, 0), Color(0.75, 0.7, 0.6), 12, 3.5, 0.09, 0.5)


func die(purified: bool) -> void:
	dying = true
	if purified:
		Fx.burst(get_parent(), global_position + Vector3(0, 0.7, 0), Color(0.5, 1.0, 0.7), 30, 5.0, 0.08, 0.9)
		Fx.ring(get_parent(), global_position, 3.0, Color(0.5, 1.0, 0.8), 0.7)
	else:
		var c := Color(0.7, 0.66, 0.58) if kind == "piedra" else Color(0.8, 0.15, 0.6)
		Fx.burst(get_parent(), global_position + Vector3(0, 0.6, 0), c, 20, 4.5, 0.1, 0.7)


func update_view(now: float, delta: float) -> void:
	_state_t += delta
	# Interpolación entre estados del servidor
	if not _buf.is_empty():
		var rt := now - INTERP_DELAY
		var a: Dictionary = _buf[0]
		var b: Dictionary = _buf[_buf.size() - 1]
		for i in range(_buf.size() - 1, 0, -1):
			if _buf[i - 1].t <= rt:
				a = _buf[i - 1]
				b = _buf[i]
				break
		var span: float = b.t - a.t
		var k := clampf((rt - a.t) / span, 0.0, 1.0) if span > 0.0001 else 1.0
		global_position = (a.pos as Vector3).lerp(b.pos, k)
		rotation.y = lerp_angle(a.yaw, b.yaw, k)

	var speed := 0.0
	if delta > 0.0:
		speed = Vector2(global_position.x - _last.x, global_position.z - _last.z).length() / delta
	_last = global_position
	_phase += delta * (3.0 + speed * 2.2)

	# Animación según el estado
	var m := _model
	var target_scale := Vector3.ONE
	var lean := 0.0
	var lift := 0.0
	match state:
		"idle", "return", "chase":
			lift = absf(sin(_phase)) * (0.06 if speed > 0.3 else 0.02)
			lean = 0.12 if state == "chase" and speed > 0.5 else 0.0
		"windup":
			var k := clampf(_state_t / float(Defs.ENEMIES[kind].windup), 0.0, 1.0)
			lean = -0.35 * k
			target_scale = Vector3.ONE * (1.0 + 0.14 * k)
			lift = 0.15 * k if kind == "piedra" else 0.0
		"strike":
			lean = 0.55
			target_scale = Vector3(0.9, 0.85, 1.3)
		"recover":
			lean = 0.3
			target_scale = Vector3(1.05, 0.9, 1.05)
		"stun":
			m.rotation.z = sin(_state_t * 14.0) * 0.18
			target_scale = Vector3(1.0, 0.92, 1.0)
		"dead":
			target_scale = Vector3(1.15, 0.05, 1.15)
	if state != "stun":
		m.rotation.z = lerp_angle(m.rotation.z, 0.0, minf(1.0, delta * 10.0))
	m.rotation.x = lerp_angle(m.rotation.x, lean, minf(1.0, delta * 12.0))
	m.position.y = lerpf(m.position.y, lift, minf(1.0, delta * 12.0))
	if _flash > 0.0:
		_flash -= delta
		target_scale *= 1.18
	m.scale = m.scale.lerp(target_scale, minf(1.0, delta * (5.0 if state == "dead" else 16.0)))

	# Partes móviles
	if kind == "piedra":
		var arm := sin(_phase) * (0.5 if speed > 0.3 else 0.08)
		var raise := -2.2 * clampf(_state_t / 0.7, 0.0, 1.0) if state == "windup" else (0.9 if state == "recover" else 0.0)
		(_parts.arm_l as Node3D).rotation.x = arm + raise
		(_parts.arm_r as Node3D).rotation.x = -arm + raise
	else:
		for i in 4:
			var leg: Node3D = _parts["leg%d" % i]
			leg.rotation.x = sin(_phase * 1.6 + (PI if i % 2 == 0 else 0.0)) * (0.8 if speed > 0.3 else 0.05)
		(_parts.tail as Node3D).rotation.y = sin(_phase * 0.8) * 0.5

	if _eye_mat:
		var hot := state == "windup" or state == "strike"
		_eye_mat.emission_energy_multiplier = lerpf(_eye_mat.emission_energy_multiplier, 5.0 if hot else 1.8, minf(1.0, delta * 10.0))

	_update_marks(delta)

	# Barra de vida: visible cuando está herido o en combate
	var bar_on := state != "dead" and (hp < max_hp or state != "idle")
	_bar.visible = bar_on
	# el nombre sólo de cerca: con muchos enemigos juntos las etiquetas se pisan
	var cam := get_viewport().get_camera_3d()
	_name.visible = bar_on and cam != null and cam.global_position.distance_to(global_position) < 13.0
	if bar_on:
		var f := clampf(hp / max_hp, 0.0, 1.0)
		_bar_fill.scale.x = maxf(f, 0.001)
		_bar_fill.position.x = -(1.0 - f) * 0.5
		var purify_at: float = Defs.ENEMIES[kind].purify_at
		var col := Color(0.5, 1.0, 0.75) if purify_at > 0.0 and f <= purify_at else Color(0.95, 0.25, 0.3)
		(_bar_fill.material_override as StandardMaterial3D).albedo_color = col


## ¿Se puede purificar ahora? (criaturas con poca vida)
func purifiable() -> bool:
	var at: float = Defs.ENEMIES[kind].purify_at
	return at > 0.0 and state != "dead" and not dying and hp <= max_hp * at


func _build_marks() -> void:
	# Nombre pequeño sobre la barra de vida
	_name = Label3D.new()
	_name.text = str(Defs.ENEMIES[kind].name)
	_name.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_name.no_depth_test = true
	_name.pixel_size = 0.0036
	_name.font_size = 28
	_name.outline_size = 8
	_name.modulate = Color(1.0, 0.86, 0.8) if kind == "piedra" else Color(1.0, 0.7, 0.9)
	_name.outline_modulate = Color(0.05, 0.03, 0.05, 0.9)
	_name.position = Vector3(0, _height + 0.78, 0)
	_name.visible = false
	add_child(_name)
	# Aviso sobre la cabeza
	_mark = Label3D.new()
	_mark.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_mark.no_depth_test = true
	_mark.pixel_size = 0.008
	_mark.font_size = 96
	_mark.outline_size = 22
	_mark.outline_modulate = Color(0.05, 0.03, 0.03, 0.95)
	_mark.position = Vector3(0, _height + 1.25, 0)
	_mark.visible = false
	add_child(_mark)
	# Estrellas de aturdimiento
	_stars = Node3D.new()
	_stars.position = Vector3(0, _height + 0.35, 0)
	var star := SphereMesh.new()
	star.radius = 0.09
	star.height = 0.18
	star.radial_segments = 6
	star.rings = 3
	var sm := Fx.glow_mat(Color(1.0, 0.9, 0.3))
	for i in 3:
		var mi := MeshInstance3D.new()
		mi.mesh = star
		mi.material_override = sm
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.position = Vector3(cos(i * TAU / 3.0), 0, sin(i * TAU / 3.0)) * 0.5
		_stars.add_child(mi)
	_stars.visible = false
	add_child(_stars)
	# Anillo de jade en el suelo: "ya se puede purificar"
	var torus := TorusMesh.new()
	torus.inner_radius = 0.92
	torus.outer_radius = 1.06
	torus.rings = 28
	torus.ring_segments = 6
	_ring = MeshInstance3D.new()
	_ring.mesh = torus
	_ring.material_override = Fx.glow_mat(Color(0.4, 1.0, 0.75), 0.9)
	_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_ring.position = Vector3(0, 0.08, 0)
	_ring.visible = false
	add_child(_ring)


func _update_marks(delta: float) -> void:
	var can := purifiable()
	if can and not _purifiable:
		# acaba de quedar purificable: destello para que el grupo lo vea
		Fx.ring(get_parent(), global_position, 1.8, Color(0.5, 1.0, 0.8), 0.5)
		Audio.play("objetivo", global_position, -6.0)
	_purifiable = can
	_ring.visible = can
	if can:
		var k := 1.0 + 0.12 * sin(_state_t * 6.0 + _phase)
		_ring.scale = Vector3(k, 1.0, k)
	_stars.visible = state == "stun"
	if _stars.visible:
		_stars.rotation.y += delta * 6.0
	var warn := state == "windup"
	_mark.visible = (warn or can) and state != "dead"
	if warn:
		_mark.text = "!"
		_mark.modulate = Color(1.0, 0.35, 0.2)
		var k := clampf(_state_t / float(Defs.ENEMIES[kind].windup), 0.0, 1.0)
		_mark.scale = Vector3.ONE * (0.55 + 0.45 * k)
	elif can:
		_mark.text = "F"
		_mark.modulate = Color(0.5, 1.0, 0.8)
		_mark.scale = Vector3.ONE * (0.6 + 0.06 * sin(_state_t * 6.0))


func _build_bar() -> void:
	_bar = Node3D.new()
	_bar.position = Vector3(0, _height + 0.55, 0)
	var q := QuadMesh.new()
	q.size = Vector2(1.0, 0.11)
	var back := MeshInstance3D.new()
	back.mesh = q
	var bm := Fx.glow_mat(Color(0.05, 0.05, 0.05), 0.75)
	bm.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	bm.no_depth_test = true
	back.material_override = bm
	back.scale = Vector3(1.06, 1.5, 1)
	_bar.add_child(back)
	_bar_fill = MeshInstance3D.new()
	_bar_fill.mesh = q
	var fm := Fx.glow_mat(Color(0.95, 0.25, 0.3))
	fm.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	fm.no_depth_test = true
	fm.render_priority = 1
	_bar_fill.material_override = fm
	_bar.add_child(_bar_fill)
	for mi in [back, _bar_fill]:
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_bar)
	_bar.visible = false


static func _sphere(r: float, squash := 1.0) -> SphereMesh:
	var s := SphereMesh.new()
	s.radius = r
	s.height = r * 2.0 * squash
	s.radial_segments = 14
	s.rings = 7
	return s


## Guardián pequeño de piedra: bloques tallados con musgo, glifo y ojos de ámbar.
func _build_piedra() -> Node3D:
	var root := Node3D.new()
	# misma caliza tallada que las ruinas del claro, con vetas de corrupción magenta
	var stone := Avatar.mat(Color(0.8, 0.74, 0.6), 0.0, 1.0)
	var dark := Avatar.mat(Color(0.56, 0.52, 0.44), 0.0, 1.0)
	var moss := Avatar.mat(Color(0.36, 0.58, 0.27), 0.0, 1.0)
	var vein := Avatar.mat(Color(0.98, 0.2, 0.6), 1.6, 0.4)
	_eye_mat = Avatar.mat(Color(1.0, 0.62, 0.15), 1.8, 0.3)
	var box := BoxMesh.new()
	box.size = Vector3(1.0, 1.0, 1.0)
	# cuerpo y cabeza
	root.add_child(Avatar.part(box, stone, Vector3(0, 0.62, 0), Vector3(0, 0.1, 0), Vector3(1.05, 0.85, 0.8)))
	root.add_child(Avatar.part(box, dark, Vector3(0, 0.2, 0), Vector3.ZERO, Vector3(0.8, 0.35, 0.65)))
	root.add_child(Avatar.part(box, stone, Vector3(0, 1.22, 0.05), Vector3(0, -0.08, 0), Vector3(0.72, 0.5, 0.62)))
	root.add_child(Avatar.part(_sphere(0.4, 0.4), moss, Vector3(0.1, 1.5, 0)))
	root.add_child(Avatar.part(_sphere(0.3, 0.4), moss, Vector3(-0.35, 1.02, -0.1)))
	# ojos y glifo del pecho
	root.add_child(Avatar.part(box, _eye_mat, Vector3(0.17, 1.26, 0.37), Vector3.ZERO, Vector3(0.16, 0.1, 0.04)))
	root.add_child(Avatar.part(box, _eye_mat, Vector3(-0.17, 1.26, 0.37), Vector3.ZERO, Vector3(0.16, 0.1, 0.04)))
	root.add_child(Avatar.part(box, dark, Vector3(0, 1.08, 0.37), Vector3.ZERO, Vector3(0.34, 0.05, 0.04)))
	for i in 3:
		root.add_child(Avatar.part(box, _eye_mat, Vector3(-0.2 + 0.2 * i, 0.68, 0.42), Vector3(0, 0, 0.78), Vector3(0.1, 0.1, 0.03)))
	for v in [[Vector3(0.36, 0.5, 0.41), 0.5], [Vector3(-0.4, 0.84, 0.41), -0.7], [Vector3(0.2, 1.44, 0.32), 1.1]]:
		root.add_child(Avatar.part(box, vein, v[0], Vector3(0, 0, v[1]), Vector3(0.3, 0.045, 0.03)))
	# brazos con puños
	for side in [1.0, -1.0]:
		var pivot := Node3D.new()
		pivot.position = Vector3(0.68 * side, 0.95, 0)
		pivot.add_child(Avatar.part(box, dark, Vector3(0, -0.3, 0), Vector3.ZERO, Vector3(0.26, 0.6, 0.26)))
		pivot.add_child(Avatar.part(box, stone, Vector3(0, -0.7, 0.03), Vector3(0.2, 0.3, 0), Vector3(0.42, 0.4, 0.42)))
		root.add_child(pivot)
		_parts["arm_l" if side > 0 else "arm_r"] = pivot
	return root


## Criatura corrompida de la selva: cuerpo de enredadera oscura con espinas y brillo magenta.
func _build_corrupta() -> Node3D:
	var root := Node3D.new()
	var hide := Avatar.mat(Color(0.2, 0.26, 0.2), 0.0, 0.9)
	var vine := Avatar.mat(Color(0.33, 0.14, 0.36), 0.0, 0.8)
	var glow := Avatar.mat(Color(1.0, 0.15, 0.65), 1.6, 0.4)
	_eye_mat = Avatar.mat(Color(1.0, 0.2, 0.7), 1.8, 0.3)
	root.add_child(Avatar.part(_sphere(0.45, 0.8), hide, Vector3(0, 0.55, -0.05), Vector3.ZERO, Vector3(1.0, 1.0, 1.35)))
	root.add_child(Avatar.part(_sphere(0.33), hide, Vector3(0, 0.66, 0.55), Vector3.ZERO, Vector3(1.0, 0.85, 1.1)))
	# hocico, colmillos y ojos
	root.add_child(Avatar.part(_sphere(0.17), vine, Vector3(0, 0.56, 0.86)))
	var fang := CylinderMesh.new()
	fang.top_radius = 0.0
	fang.bottom_radius = 0.04
	fang.height = 0.16
	fang.radial_segments = 6
	for sx in [0.1, -0.1]:
		root.add_child(Avatar.part(fang, Avatar.mat(Color(0.95, 0.92, 0.8)), Vector3(sx, 0.46, 0.9), Vector3(PI, 0, 0)))
		root.add_child(Avatar.part(_sphere(0.075), _eye_mat, Vector3(sx * 1.6, 0.78, 0.78)))
	# espinas a lo largo del lomo
	var thorn := CylinderMesh.new()
	thorn.top_radius = 0.0
	thorn.bottom_radius = 0.09
	thorn.height = 0.42
	thorn.radial_segments = 6
	for i in 5:
		var z := 0.45 - i * 0.24
		root.add_child(Avatar.part(thorn, vine, Vector3(0, 0.98 - absf(i - 2.0) * 0.05, z), Vector3(-0.35, 0, 0)))
	for i in 4:
		root.add_child(Avatar.part(_sphere(0.07), glow, Vector3(0.3 * (1 if i % 2 == 0 else -1), 0.6, 0.25 - i * 0.2)))
	# patas
	var legs := [Vector3(0.3, 0.42, 0.32), Vector3(-0.3, 0.42, 0.32), Vector3(0.3, 0.42, -0.36), Vector3(-0.3, 0.42, -0.36)]
	var cap := CapsuleMesh.new()
	cap.radius = 0.09
	cap.height = 0.5
	for i in 4:
		var pivot := Node3D.new()
		pivot.position = legs[i]
		pivot.add_child(Avatar.part(cap, vine, Vector3(0, -0.2, 0)))
		root.add_child(pivot)
		_parts["leg%d" % i] = pivot
	# cola de enredadera
	var tail := Node3D.new()
	tail.position = Vector3(0, 0.6, -0.6)
	var tc := CapsuleMesh.new()
	tc.radius = 0.06
	tc.height = 0.8
	tail.add_child(Avatar.part(tc, vine, Vector3(0, 0.1, -0.35), Vector3(-1.1, 0, 0)))
	tail.add_child(Avatar.part(_sphere(0.1), glow, Vector3(0, 0.3, -0.7)))
	root.add_child(tail)
	_parts["tail"] = tail
	return root
