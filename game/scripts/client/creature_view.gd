extends Node3D
## Criatura del mundo abierto, vista. Sólo representa lo que dice el servidor de zonas (posición,
## vida y estado); no decide nada. Diseños originales con formas simples, baratos de dibujar: el
## cuerpo de cada tipo es UNA malla fundida (más otra sin sombrear para lo que brilla), compartida
## por todas las criaturas de ese tipo.
##
##   zarza      «Zarza errante»: una bola de monte espinoso con brasas del Silencio, que rueda
##   henequen   «Henequén bravo»: una mata de henequén desarraigada que barre con sus pencas
##
## Lo que debe leerse siempre: qué es (nombre), cuándo va a golpear («!» y círculo en el suelo),
## cuánta vida le queda y cuándo se puede purificar (aro de jade y la tecla F).

const Wild := preload("res://scripts/shared/wild_def.gd")
const SceneBatch := preload("res://scripts/client/scene_batch.gd")
const Fx := preload("res://scripts/client/fx.gd")
const Audio := preload("res://scripts/client/audio.gd")

const INTERP_DELAY := 0.16
const SILENCE := Color(1.0, 0.2, 0.62)     # el magenta del Silencio (como en el Claro)
const EMBER := Color(1.0, 0.62, 0.15)

static var _meshes := {}                    # tipo -> [cuerpo, brillo]
static var _mats := {}

var creature_id := 0
var kind := "zarza"
var state := "idle"
var hp := 1.0
var max_hp := 1.0
var seen := 0.0                             # cuándo llegó su último estado
var dying := false

var _def: Dictionary
var _buf: Array = []
var _body: Node3D
var _bar: Node3D
var _bar_fill: MeshInstance3D
var _mark: Label3D
var _name: Label3D
var _ring: MeshInstance3D
var _phase := 0.0
var _flash := 0.0
var _state_t := 0.0
var _roll := 0.0
var _last := Vector3.ZERO
var _was_weak := false


func setup(id: int, p_kind: String) -> void:
	creature_id = id
	kind = p_kind
	_def = Wild.CREATURES[kind]
	max_hp = float(_def.hp)
	hp = max_hp
	_phase = float(id) * 1.7
	if not _meshes.has(kind):
		_meshes[kind] = _build_zarza() if kind == "zarza" else _build_henequen()
	if _mats.is_empty():
		var sb := SceneBatch.new()
		_mats = {"solid": sb.solid(), "glow": sb.glow()}
	_body = Node3D.new()
	add_child(_body)
	for k in 2:
		var mi := MeshInstance3D.new()
		mi.mesh = _meshes[kind][k]
		mi.material_override = _mats.solid if k == 0 else _mats.glow
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if k == 0 else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_body.add_child(mi)
	_build_marks()


func push_state(t: float, pos: Vector3, yaw: float, p_hp: float, p_state: String) -> void:
	_buf.append([t, pos, yaw])
	while _buf.size() > 10:
		_buf.pop_front()
	seen = t
	hp = p_hp
	if p_state != state:
		_on_state(p_state)
		state = p_state
		_state_t = 0.0
	if _buf.size() == 1:
		position = pos
		rotation.y = yaw
		_last = pos


func _on_state(next: String) -> void:
	if next == "windup":
		# El aviso: un círculo en el suelo donde va a caer el golpe, y su grito
		var fwd := Vector3(sin(rotation.y), 0, cos(rotation.y))
		Fx.telegraph(get_parent(), global_position + fwd * float(_def.reach), float(_def.hit_radius), float(_def.windup))
		Audio.play("criatura_llamada|enemigo_aviso", global_position, -5.0)
	elif next == "recover" and state == "windup":
		var fwd := Vector3(sin(rotation.y), 0, cos(rotation.y))
		Fx.ring(get_parent(), global_position + fwd * float(_def.reach), float(_def.hit_radius), EMBER, 0.32)
		Audio.play("criatura_ataque|enemigo_golpe", global_position, -5.0)
	elif next == "weak":
		Fx.ring(get_parent(), global_position, 1.8, Color(0.5, 1.0, 0.8), 0.5)
		Audio.play("objetivo", global_position, -6.0)


func hit_flash() -> void:
	_flash = 0.16


func die(purified: bool) -> void:
	if dying:
		return
	dying = true
	if purified:
		Fx.burst(get_parent(), global_position + Vector3(0, 0.7, 0), Color(0.5, 1.0, 0.7), 30, 5.0, 0.08, 0.9)
		Fx.ring(get_parent(), global_position, 3.0, Color(0.5, 1.0, 0.8), 0.7)
		Audio.play("enemigo_purificado|purificar", global_position, -2.0)
	else:
		Fx.burst(get_parent(), global_position + Vector3(0, 0.6, 0), Color(0.5, 0.42, 0.3), 20, 4.5, 0.1, 0.7)
		Audio.play("enemigo_muere", global_position, -3.0)
	queue_free()


func purifiable() -> bool:
	return state == "weak" and not dying


func update_view(now: float, delta: float, me: Vector3) -> void:
	_state_t += delta
	if not _buf.is_empty():
		var rt := now - INTERP_DELAY
		var a: Array = _buf[0]
		var b: Array = _buf[-1]
		for i in range(_buf.size() - 1, 0, -1):
			if float(_buf[i - 1][0]) <= rt:
				a = _buf[i - 1]
				b = _buf[i]
				break
		var span := float(b[0]) - float(a[0])
		var k := clampf((rt - float(a[0])) / span, 0.0, 1.0) if span > 0.0001 else 1.0
		position = (a[1] as Vector3).lerp(b[1], k)
		rotation.y = lerp_angle(float(a[2]), float(b[2]), k)
	var moved := Vector2(position.x - _last.x, position.z - _last.z).length()
	_last = position
	# Movimiento propio de cada una, todo con transformaciones del cuerpo (una sola malla)
	var squash := Vector3.ONE
	var lift := 0.0
	if kind == "zarza":
		_roll += moved / 0.55
		_body.rotation.x = _roll
		lift = 0.55 + absf(sin(_roll * 0.5)) * 0.08
	else:
		_body.rotation.y += moved * 0.6
		_body.rotation.z = sin(now * 5.0 + _phase) * 0.05 * (1.0 if moved > 0.001 else 0.3)
	match state:
		"windup":
			var k := clampf(_state_t / float(_def.windup), 0.0, 1.0)
			squash = Vector3(1.0 - 0.18 * k, 1.0 + 0.3 * k, 1.0 - 0.18 * k) if kind == "henequen" else Vector3.ONE * (1.0 + 0.25 * k)
			_body.position.x = sin(now * 46.0) * 0.04 * k
		"recover":
			var k := clampf(_state_t / 0.3, 0.0, 1.0)
			if kind == "henequen":
				_body.rotation.y += delta * 14.0 * (1.0 - k)
				squash = Vector3(1.3 - 0.3 * k, 0.65 + 0.35 * k, 1.3 - 0.3 * k)
			else:
				squash = Vector3.ONE * (1.25 - 0.25 * k)
			_body.position.x = 0.0
		"weak":
			squash = Vector3(1.08, 0.78, 1.08)
			_body.rotation.z = sin(now * 3.0 + _phase) * 0.12
			_body.position.x = 0.0
		_:
			_body.position.x = 0.0
	if _flash > 0.0:
		_flash -= delta
		squash *= 1.0 + _flash * 1.2
	_body.scale = _body.scale.lerp(squash, minf(1.0, delta * 14.0))
	_body.position.y = lift
	# Marcas: sólo de cerca
	var d := position.distance_to(me)
	var near := d < 26.0
	var weak := purifiable()
	if weak and not _was_weak:
		_was_weak = true
	elif not weak:
		_was_weak = false
	_ring.visible = weak
	if weak:
		var k := 1.0 + 0.12 * sin(_state_t * 6.0)
		_ring.scale = Vector3(k, 1.0, k)
	var warn := state == "windup"
	_mark.visible = (warn or weak) and near
	if warn:
		_mark.text = "!"
		_mark.modulate = Color(1.0, 0.35, 0.2)
		_mark.scale = Vector3.ONE * (0.55 + 0.45 * clampf(_state_t / float(_def.windup), 0.0, 1.0))
	elif weak:
		_mark.text = "F"
		_mark.modulate = Color(0.5, 1.0, 0.8)
		_mark.scale = Vector3.ONE * (0.6 + 0.06 * sin(_state_t * 6.0))
	var hurt := hp < max_hp - 0.5
	_bar.visible = near and (hurt or state != "idle")
	_name.visible = _bar.visible and d < 16.0
	if _bar.visible:
		var f := clampf(hp / max_hp, 0.0, 1.0)
		_bar_fill.scale = Vector3(maxf(f, 0.001), 1.0, 1.0)
		_bar_fill.position.x = -0.5 * (1.0 - f)
		(_bar_fill.material_override as StandardMaterial3D).albedo_color = Color(0.5, 1.0, 0.75) if f <= float(_def.purify_at) else Color(0.95, 0.25, 0.3)


func _build_marks() -> void:
	var height := float(_def.height)
	_name = Label3D.new()
	_name.text = str(_def.name)
	_name.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_name.no_depth_test = true
	_name.pixel_size = 0.0036
	_name.font_size = 28
	_name.outline_size = 8
	_name.modulate = Color(1.0, 0.8, 0.9)
	_name.outline_modulate = Color(0.05, 0.03, 0.05, 0.9)
	_name.position = Vector3(0, height + 0.78, 0)
	_name.visible = false
	add_child(_name)
	_mark = Label3D.new()
	_mark.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_mark.no_depth_test = true
	_mark.pixel_size = 0.008
	_mark.font_size = 96
	_mark.outline_size = 22
	_mark.outline_modulate = Color(0.05, 0.03, 0.03, 0.95)
	_mark.position = Vector3(0, height + 1.25, 0)
	_mark.visible = false
	add_child(_mark)
	var torus := TorusMesh.new()
	torus.inner_radius = 0.92
	torus.outer_radius = 1.06
	torus.rings = 24
	torus.ring_segments = 5
	_ring = MeshInstance3D.new()
	_ring.mesh = torus
	_ring.material_override = Fx.glow_mat(Color(0.4, 1.0, 0.75), 0.9)
	_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_ring.position = Vector3(0, 0.08, 0)
	_ring.visible = false
	add_child(_ring)
	_bar = Node3D.new()
	_bar.position = Vector3(0, height + 0.5, 0)
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


# ───────────────────────── Diseños ─────────────────────────

## Zarza errante: una maraña redonda de ramas secas y espinas, con brasas del Silencio dentro.
## Centrada en el origen (rueda sobre sí misma); el cuerpo se sube a su radio.
static func _build_zarza() -> Array:
	var sb := SceneBatch.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = 77
	var twig := Color(0.36, 0.3, 0.2)
	var dry := Color(0.5, 0.46, 0.28)
	sb.ball("c", 0.34, twig.darkened(0.25), Vector3.ZERO, 1.0, twig.darkened(0.5), 6)
	# aros de rama cruzados: la silueta redonda de la maraña
	for k in 5:
		var basis := Basis(Vector3(rng.randf_range(-1, 1), rng.randf_range(-1, 1), rng.randf_range(-1, 1)).normalized(), rng.randf() * TAU)
		var prev := basis * Vector3(0.52, 0, 0)
		for s in range(1, 9):
			var a := TAU * float(s) / 8.0
			var p := basis * (Vector3(cos(a), 0, sin(a)) * (0.5 + rng.randf_range(-0.05, 0.05)))
			sb.beam("c", prev, p, 0.05, twig.lerp(dry, rng.randf()))
			prev = p
	# espinas
	for k in 26:
		var dir := Vector3(rng.randf_range(-1, 1), rng.randf_range(-1, 1), rng.randf_range(-1, 1)).normalized()
		sb.spike("c", dir * 0.42, dir, 0.26 + rng.randf() * 0.2, 0.035, dry.darkened(0.2), Color(0.86, 0.8, 0.6), 3)
	# brasas del Silencio entre las ramas
	for k in 7:
		var dir := Vector3(rng.randf_range(-1, 1), rng.randf_range(-1, 1), rng.randf_range(-1, 1)).normalized()
		sb.ball("g", 0.07 + rng.randf() * 0.04, SILENCE if k % 3 != 0 else EMBER, dir * 0.3, 1.0, SceneBatch.NONE, 6)
	sb.ball("g", 0.16, SILENCE.darkened(0.2), Vector3.ZERO, 1.0, SceneBatch.NONE, 6)
	return [sb.mesh_of("c"), sb.mesh_of("g")]


## Henequén bravo: la piña de un henequén sobre tres raíces, con las pencas abiertas y dos ojos de ámbar.
static func _build_henequen() -> Array:
	var sb := SceneBatch.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = 91
	var agave := Color(0.4, 0.56, 0.5)
	var dark := Color(0.2, 0.34, 0.32)
	var root := Color(0.42, 0.32, 0.22)
	# raíces que hacen de patas
	for k in 3:
		var a := TAU * float(k) / 3.0
		sb.beam("c", Vector3(sin(a) * 0.2, 0.5, cos(a) * 0.2), Vector3(sin(a) * 0.55, 0.0, cos(a) * 0.55), 0.16, root)
	# la piña
	sb.ball("c", 0.46, dark.lightened(0.12), Vector3(0, 0.78, 0), 1.2, dark.darkened(0.3), 8)
	# pencas: una corona abierta y otra más alzada
	for k in 9:
		var a := TAU * float(k) / 9.0
		sb.spike("c", Vector3(0, 0.75, 0), Vector3(sin(a), 0.5, cos(a)), 1.2, 0.15, dark, agave.lightened(0.12), 5)
	for k in 6:
		var a := TAU * (float(k) + 0.5) / 6.0
		sb.spike("c", Vector3(0, 0.9, 0), Vector3(sin(a) * 0.5, 1.0, cos(a) * 0.5), 1.0, 0.13, dark, agave.lightened(0.18), 5)
	# espina negra en la punta de las pencas de abajo
	for k in 9:
		var a := TAU * float(k) / 9.0
		var dir := Vector3(sin(a), 0.5, cos(a)).normalized()
		sb.spike("c", Vector3(0, 0.75, 0) + dir * 1.15, dir, 0.16, 0.03, Color(0.12, 0.1, 0.1), Color(0.12, 0.1, 0.1), 3)
	# ojos de ámbar y vetas del Silencio
	for sx in [-0.17, 0.17]:
		sb.ball("g", 0.085, EMBER, Vector3(sx, 0.86, 0.4), 1.0, SceneBatch.NONE, 6)
	for k in 4:
		var a := 1.2 + 1.3 * float(k)
		sb.box("g", Vector3(0.05, 0.3, 0.04), SILENCE, Vector3(sin(a) * 0.43, 0.7 + 0.08 * float(k % 2), cos(a) * 0.43), a)
	return [sb.mesh_of("c"), sb.mesh_of("g")]
