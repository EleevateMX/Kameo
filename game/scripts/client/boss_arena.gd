extends Node3D
class_name BossArena
## Lo que el combate con Nojoch Tuunich añade a la explanada: anclas mágicas, zócalos y columnas,
## cadenas de jade, lluvia de piedra, el carril de la embestida, los glifos del ritual y la Pluma
## de Jade. Sólo dibuja el estado que manda el servidor (estado «b»): aquí no se decide nada.

const Boss := preload("res://scripts/shared/boss_def.gd")
const World := preload("res://scripts/shared/world_def.gd")
const Avatar := preload("res://scripts/client/avatar.gd")
const Fx := preload("res://scripts/client/fx.gd")

const JADE := Color(0.24, 0.91, 0.77)
const MAGENTA := Color(1.0, 0.2, 0.61)
const GOLD := Color(1.0, 0.86, 0.5)
const STONE := Color(0.86, 0.8, 0.66)

var _phase := Boss.ASLEEP
var _state := "sleep"
var _t := 0.0
var _time := 0.0
var _boss_at := Vector3.ZERO
var _aim_yaw := 0.0
var _anchor_nodes: Array = []      # [disco, material, haz]
var _anchors := 0
var _socket_nodes: Array = []      # [glifo, material, columna, material de refugio, anillo]
var _pillars := {}                 # zócalo -> altura visible (0..1)
var _up := {}                      # zócalo -> true si el servidor la da por levantada
var _chains: Array = []            # una por ancla
var _lane: MeshInstance3D
var _lane_mat: StandardMaterial3D
var _ritual_nodes: Array = []      # [glifo, material]
var _ritual_ring: MeshInstance3D
var _ritual_ring_mat: StandardMaterial3D
var _lit := 0
var _contact := false
var _beams: Array = []             # un haz por slot
var _channel := 0
var _feather: Node3D
var _rain_in := 0.0
var _lite := false
var _rng := RandomNumberGenerator.new()
## Durante una cinemática: -1 la pluma sigue al estado; 0 oculta; 1 a la vista.
var cine_feather := -1
var _feather_k := 0.0


func setup(lite: bool) -> void:
	_lite = lite
	_rng.randomize()
	# Anclas: discos de jade en el suelo con un haz que las señala cuando hacen falta
	for i in Boss.ANCHORS.size():
		var a: Vector2 = Boss.ANCHORS[i]
		var h := World.terrain_h(a.x, a.y)
		var disc := CylinderMesh.new()
		disc.top_radius = Boss.ANCHOR_R
		disc.bottom_radius = Boss.ANCHOR_R
		disc.height = 0.05
		disc.radial_segments = 24
		var mat := Fx.glow_mat(JADE, 0.2)
		var mi := Avatar.part(disc, mat, Vector3(a.x, h + 0.05, a.y))
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)
		var ring := TorusMesh.new()
		ring.inner_radius = Boss.ANCHOR_R - 0.12
		ring.outer_radius = Boss.ANCHOR_R
		ring.rings = 24
		ring.ring_segments = 6
		var rim := Avatar.part(ring, Fx.glow_mat(JADE, 0.7), Vector3(0, 0.02, 0))
		rim.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.add_child(rim)
		var beam_mesh := CylinderMesh.new()
		beam_mesh.top_radius = 0.1
		beam_mesh.bottom_radius = 0.42
		beam_mesh.height = 7.0
		beam_mesh.radial_segments = 10
		beam_mesh.cap_top = false
		beam_mesh.cap_bottom = false
		var beam_mat := Fx.glow_mat(JADE, 0.4)
		beam_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		var beam := Avatar.part(beam_mesh, beam_mat, Vector3(0, 3.5, 0))
		beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		beam.visible = false
		mi.add_child(beam)
		mi.visible = false
		_anchor_nodes.append([mi, mat, beam])
		# Cadena hasta el guardián (se estira cada cuadro)
		var link := BoxMesh.new()
		link.size = Vector3(0.16, 0.16, 1.0)
		var chain_mat := Fx.glow_mat(JADE, 0.9)
		var chain := Avatar.part(link, chain_mat, Vector3.ZERO)
		chain.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		chain.visible = false
		add_child(chain)
		_chains.append(chain)

	# Zócalos: el glifo dormido de cada columna, la columna y el círculo de refugio
	for i in Boss.PILLAR_SPOTS.size():
		var s: Vector2 = Boss.PILLAR_SPOTS[i]
		var h := World.terrain_h(s.x, s.y)
		var glyph := CylinderMesh.new()
		glyph.top_radius = float(Boss.PILLARS.radius)
		glyph.bottom_radius = float(Boss.PILLARS.radius)
		glyph.height = 0.05
		glyph.radial_segments = 6
		var gmat := Fx.glow_mat(GOLD, 0.3)
		var g := Avatar.part(glyph, gmat, Vector3(s.x, h + 0.05, s.y))
		g.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		g.visible = false
		add_child(g)
		var col := CylinderMesh.new()
		col.top_radius = float(Boss.PILLARS.radius) * 0.86
		col.bottom_radius = float(Boss.PILLARS.radius)
		col.height = 3.6
		col.radial_segments = 8
		var column := Avatar.part(col, Avatar.mat(STONE), Vector3(s.x, h - 1.9, s.y))
		column.visible = false
		add_child(column)
		# Banda de glifos encendida en la columna
		var band := CylinderMesh.new()
		band.top_radius = float(Boss.PILLARS.radius) * 0.93
		band.bottom_radius = float(Boss.PILLARS.radius) * 0.95
		band.height = 0.28
		band.radial_segments = 8
		band.cap_top = false
		band.cap_bottom = false
		column.add_child(Avatar.part(band, Fx.glow_mat(JADE, 0.95), Vector3(0, 0.9, 0)))
		var shelter := TorusMesh.new()
		shelter.inner_radius = float(Boss.PILLARS.shelter) - 0.1
		shelter.outer_radius = float(Boss.PILLARS.shelter)
		shelter.rings = 28
		shelter.ring_segments = 5
		var smat := Fx.glow_mat(JADE, 0.0)
		smat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		var ring2 := Avatar.part(shelter, smat, Vector3(s.x, h + 0.07, s.y))
		ring2.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		ring2.visible = false
		add_child(ring2)
		_socket_nodes.append([g, gmat, column, smat, ring2])

	# Carril de la embestida
	var lane := BoxMesh.new()
	lane.size = Vector3(float(Boss.CHARGE.hit_r) * 2.0, 0.04, float(Boss.CHARGE.dist))
	_lane_mat = Fx.glow_mat(MAGENTA, 0.3)
	_lane = Avatar.part(lane, _lane_mat, Vector3.ZERO)
	_lane.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_lane.visible = false
	add_child(_lane)

	# Ritual: glifos de memoria en el suelo, el círculo de contacto y un haz por jugador
	for i in Boss.RITUAL_SPOTS.size():
		var glyph := CylinderMesh.new()
		glyph.top_radius = 0.95
		glyph.bottom_radius = 0.95
		glyph.height = 0.05
		glyph.radial_segments = 5
		var gmat := Fx.glow_mat(JADE, 0.18)
		var g := Avatar.part(glyph, gmat, Vector3.ZERO)
		g.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		g.visible = false
		add_child(g)
		_ritual_nodes.append([g, gmat])
	var reach := TorusMesh.new()
	reach.inner_radius = float(Boss.RITUAL.range) - 0.12
	reach.outer_radius = float(Boss.RITUAL.range)
	reach.rings = 40
	reach.ring_segments = 5
	_ritual_ring_mat = Fx.glow_mat(JADE, 0.5)
	_ritual_ring = Avatar.part(reach, _ritual_ring_mat, Vector3.ZERO)
	_ritual_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_ritual_ring.visible = false
	add_child(_ritual_ring)
	for i in 4:
		var link := BoxMesh.new()
		link.size = Vector3(0.1, 0.1, 1.0)
		var bm := Fx.glow_mat(JADE, 0.85)
		bm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		var beam := Avatar.part(link, bm, Vector3.ZERO)
		beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		beam.visible = false
		add_child(beam)
		_beams.append(beam)

	_feather = _build_feather()
	_feather.visible = false
	add_child(_feather)


## La Pluma de Jade: un objeto, no un personaje. Flota ante el guardián liberado.
## Pluma larga de quetzal: raquis dorado, barbas de jade a los dos lados y la punta más clara.
func _build_feather() -> Node3D:
	var root := Node3D.new()
	var body := Node3D.new()
	root.add_child(body)
	var leaf := SphereMesh.new()
	leaf.radius = 0.5
	leaf.height = 1.0
	leaf.radial_segments = 10
	leaf.rings = 5
	var jade := Avatar.mat(JADE, 1.6, 0.35)
	var pale := Avatar.mat(Color(0.7, 1.0, 0.92), 2.2, 0.3)
	var deep := Avatar.mat(Color(0.1, 0.62, 0.52), 1.0, 0.4)
	# Barbas: láminas inclinadas a cada lado del raquis, más cortas hacia la punta
	for i in 9:
		var k := float(i) / 8.0
		var y := lerpf(-0.42, 0.78, k)
		var half := lerpf(0.3, 0.07, k * k) * (0.72 if i == 0 else 1.0)
		for side in [-1.0, 1.0]:
			var barb := Avatar.part(leaf, pale if i >= 7 else (deep if i % 3 == 1 else jade),
				Vector3(side * half * 0.5, y, 0.0), Vector3(0.0, 0.0, side * -0.62), Vector3(half * 1.25, 0.2, 0.035))
			barb.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			body.add_child(barb)
	var quill := CylinderMesh.new()
	quill.top_radius = 0.008
	quill.bottom_radius = 0.026
	quill.height = 1.9
	quill.radial_segments = 6
	body.add_child(Avatar.part(quill, Avatar.mat(GOLD, 1.8, 0.4), Vector3(0, 0.0, 0)))
	# Punta curvada: un toque de ojo de pluma
	body.add_child(Avatar.part(leaf, pale, Vector3(0.03, 0.9, 0.0), Vector3(0, 0, -0.25), Vector3(0.1, 0.22, 0.04)))
	root.rotation = Vector3(0.0, 0.0, 0.3)
	return root


## Estado del servidor (ver server/boss.gd, snapshot()).
func apply(b: Array) -> void:
	if b.size() < 24:
		return
	_phase = int(b[0])
	_state = Boss.STATES[clampi(int(b[4]), 0, Boss.STATES.size() - 1)]
	_t = float(b[5])
	_aim_yaw = float(b[12])
	_anchors = int(b[14])
	var up := {}
	for pl in b[16]:
		up[int(pl[0])] = true
	_up = up
	_lit = int(b[19])
	_contact = _phase == Boss.RECUERDO and _state == "ritual" and _lit >= int(b[20])
	_channel = int(b[22])


func pillar_up(i: int) -> bool:
	return _up.has(i)


## `boss_at`: dónde se ve al guardián. `players`: slot -> posición de quien esté en la sala.
func update_view(delta: float, boss_at: Vector3, players: Dictionary) -> void:
	_time += delta
	_boss_at = boss_at
	var furia := _phase == Boss.FURIA
	var calling := furia and (_state == "stunned" or _state == "bound")
	var pulse := 0.5 + 0.5 * sin(_time * 6.0)

	for i in _anchor_nodes.size():
		var node: MeshInstance3D = _anchor_nodes[i][0]
		var mat: StandardMaterial3D = _anchor_nodes[i][1]
		var beam: MeshInstance3D = _anchor_nodes[i][2]
		var on := (_anchors & (1 << i)) != 0
		node.visible = furia
		beam.visible = calling and not on
		mat.albedo_color.a = 0.75 if on else (0.25 + 0.3 * pulse if calling else 0.14)
		var chain: MeshInstance3D = _chains[i]
		chain.visible = furia and on
		if chain.visible:
			_stretch(chain, node.global_position + Vector3(0, 0.1, 0), boss_at + Vector3(0, 2.7, 0))

	var raining := furia and (_state == "rain_w" or _state == "rain")
	for i in _socket_nodes.size():
		var glyph: MeshInstance3D = _socket_nodes[i][0]
		var gmat: StandardMaterial3D = _socket_nodes[i][1]
		var column: MeshInstance3D = _socket_nodes[i][2]
		var smat: StandardMaterial3D = _socket_nodes[i][3]
		var ring: MeshInstance3D = _socket_nodes[i][4]
		var up := _up.has(i) and furia
		var h: float = _pillars.get(i, 0.0)
		h = move_toward(h, 1.0 if up else 0.0, delta * (2.6 if up else 3.5))
		_pillars[i] = h
		glyph.visible = furia and not up
		gmat.albedo_color.a = 0.2 + 0.18 * pulse
		column.visible = h > 0.01
		var s: Vector2 = Boss.PILLAR_SPOTS[i]
		column.position.y = World.terrain_h(s.x, s.y) - 1.9 + 3.6 * h
		# El círculo de refugio se enciende cuando va a llover piedra
		ring.visible = up and raining
		smat.albedo_color.a = 0.45 + 0.35 * pulse

	_lane.visible = furia and _state == "charge_w"
	if _lane.visible:
		var dir := Vector3(sin(_aim_yaw), 0.0, cos(_aim_yaw))
		_lane.global_position = boss_at + dir * (float(Boss.CHARGE.dist) * 0.5) + Vector3(0, 0.09, 0)
		_lane.rotation.y = _aim_yaw
		# Fijada la dirección, el carril se enciende: ya no va a cambiar
		var locked := _t <= float(Boss.CHARGE.lock)
		_lane_mat.albedo_color = Color(1.0, 0.85, 0.5, 0.55) if locked else Color(MAGENTA.r, MAGENTA.g, MAGENTA.b, 0.22 + 0.12 * pulse)

	# Lluvia de piedra: cascotes que caen por la explanada mientras dura
	if furia and _state == "rain":
		_rain_in -= delta
		if _rain_in <= 0.0:
			_rain_in = 0.16 if _lite else 0.07
			var a := _rng.randf() * TAU
			var r := sqrt(_rng.randf()) * Boss.P2_RADIUS
			var p := Vector3(Boss.P2_HOME.x + cos(a) * r, 0.0, Boss.P2_HOME.y + sin(a) * r)
			p.y = World.terrain_h(p.x, p.z)
			_drop_rock(p)

	var ritual := _phase == Boss.RECUERDO and _state == "ritual"
	for i in _ritual_nodes.size():
		var g: MeshInstance3D = _ritual_nodes[i][0]
		var gm: StandardMaterial3D = _ritual_nodes[i][1]
		var off: Vector2 = Boss.RITUAL_SPOTS[i]
		g.visible = ritual or _phase == Boss.FREED
		g.global_position = Vector3(boss_at.x + off.x, World.terrain_h(boss_at.x + off.x, boss_at.z + off.y) + 0.06, boss_at.z + off.y)
		g.rotation.y = _time * 0.4
		var on := i < _lit or _phase == Boss.FREED
		gm.albedo_color = Color(JADE.r, JADE.g, JADE.b, 0.85) if on else Color(MAGENTA.r, MAGENTA.g, MAGENTA.b, 0.16 + 0.1 * pulse)
	_ritual_ring.visible = _contact
	if _contact:
		_ritual_ring.global_position = Vector3(boss_at.x, boss_at.y + 0.08, boss_at.z)
		_ritual_ring_mat.albedo_color.a = 0.35 + 0.4 * pulse
	for slot in _beams.size():
		var beam: MeshInstance3D = _beams[slot]
		beam.visible = _contact and (_channel & (1 << slot)) != 0 and players.has(slot)
		if beam.visible:
			_stretch(beam, (players[slot] as Vector3) + Vector3(0, 0.8, 0), boss_at + Vector3(0, 2.0, 0))

	var show_feather := _phase == Boss.FREED if cine_feather < 0 else cine_feather > 0
	# Sale de sus manos: al aparecer sube y se acerca al grupo
	_feather_k = move_toward(_feather_k, 1.0 if show_feather else 0.0, delta * (0.45 if show_feather else 4.0))
	_feather.visible = _feather_k > 0.01
	if _feather.visible:
		var fwd := Vector3(sin(Boss.HOME_YAW), 0.0, cos(Boss.HOME_YAW))
		var e := _feather_k * _feather_k * (3.0 - 2.0 * _feather_k)
		_feather.global_position = boss_at + fwd * lerpf(1.5, 2.6, e) + Vector3(0, lerpf(1.5, 2.1, e) + 0.18 * sin(_time * 1.7), 0)
		_feather.rotation.y = _time * 0.9
		_feather.scale = Vector3.ONE * lerpf(0.35, 1.0, e)


func feather_position() -> Vector3:
	return _feather.global_position


## Estira una barra entre dos puntos (cadenas y haces).
func _stretch(bar: MeshInstance3D, from: Vector3, to: Vector3) -> void:
	var d := to - from
	var len := d.length()
	if len < 0.05:
		bar.visible = false
		return
	bar.global_position = from + d * 0.5
	bar.look_at(to, Vector3.UP if absf(d.normalized().y) < 0.98 else Vector3.RIGHT)
	bar.scale = Vector3(1.0, 1.0, len)


func _drop_rock(ground: Vector3) -> void:
	var box := BoxMesh.new()
	var s := _rng.randf_range(0.18, 0.42)
	box.size = Vector3(s, s, s)
	var rock := Avatar.part(box, Avatar.mat(STONE.darkened(0.15)), ground + Vector3(0, 9.0, 0),
		Vector3(_rng.randf() * TAU, _rng.randf() * TAU, 0.0))
	rock.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(rock)
	var tw := rock.create_tween()
	tw.tween_property(rock, "position:y", ground.y + 0.1, 0.42).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	tw.tween_callback(func() -> void:
		Fx.burst(self, ground + Vector3(0, 0.2, 0), STONE, 4 if _lite else 7, 3.0, 0.07, 0.4)
		rock.queue_free())


## Una columna despierta o se rompe: polvo y cascotes en su sitio.
func pillar_fx(i: int, broken: bool) -> void:
	var s: Vector2 = Boss.PILLAR_SPOTS[clampi(i, 0, Boss.PILLAR_SPOTS.size() - 1)]
	var p := Vector3(s.x, World.terrain_h(s.x, s.y), s.y)
	if broken:
		_pillars[i] = 0.0
		Fx.burst(self, p + Vector3(0, 1.6, 0), STONE, 16 if _lite else 34, 7.5, 0.16, 0.9)
		Fx.ring(self, p + Vector3(0, 0.1, 0), 3.2, GOLD, 0.5)
	else:
		Fx.burst(self, p + Vector3(0, 0.3, 0), STONE, 8 if _lite else 14, 3.5, 0.09, 0.6)
		Fx.pillar(self, p, JADE, 5.0, 1.0, 0.6)
