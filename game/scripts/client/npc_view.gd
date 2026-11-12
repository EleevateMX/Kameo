extends Node3D
## Personaje no jugador con el que se puede hablar (por ahora, Chiich Yaxché).
## Modelo PROVISIONAL: reutiliza el del alux con rebozo, bastón y un halo de espíritu.
## No tiene colisión ni reglas: es presentación del cliente. Su posición y su alcance
## vienen de shared/story_def.gd, que es lo que comprueba el servidor.

const Avatar := preload("res://scripts/client/avatar.gd")
const Fx := preload("res://scripts/client/fx.gd")
const Story := preload("res://scripts/shared/story_def.gd")
const World := preload("res://scripts/shared/world_def.gd")

var npc_id := ""
var talk_range := 3.0
var _av: Avatar
var _halo: MeshInstance3D
var _orb: MeshInstance3D
var _prompt: Label3D
var _time := 0.0
var _home_yaw := 0.0
var _gesture_in := 0.0


func setup(id: String) -> void:
	npc_id = id
	var def: Dictionary = Story.NPCS[id]
	talk_range = float(def.range)
	var at: Vector2 = def.pos
	position = Vector3(at.x, World.terrain_h(at.x, at.y), at.y)
	_home_yaw = float(def.yaw)
	rotation.y = _home_yaw

	_av = Avatar.new()
	add_child(_av)
	_av.setup(str(def.name), str(def.color), 2)
	_av.scale = Vector3.ONE * 1.12

	# Rebozo claro con cenefa bordada (distingue a la abuela de los aluxes jugadores)
	var shawl := CylinderMesh.new()
	shawl.top_radius = 0.2
	shawl.bottom_radius = 0.5
	shawl.height = 0.42
	shawl.radial_segments = 14
	add_child(Avatar.part(shawl, Avatar.mat(Color(0.96, 0.93, 0.84), 0.12), Vector3(0, 0.98, 0)))
	var band := CylinderMesh.new()
	band.top_radius = 0.5
	band.bottom_radius = 0.52
	band.height = 0.07
	band.radial_segments = 14
	add_child(Avatar.part(band, Avatar.mat(Color(0.93, 0.25, 0.45), 0.25), Vector3(0, 0.78, 0)))

	# Bastón de ceiba con un brote de jade encendido
	var staff := CylinderMesh.new()
	staff.top_radius = 0.035
	staff.bottom_radius = 0.05
	staff.height = 1.7
	staff.radial_segments = 8
	add_child(Avatar.part(staff, Avatar.mat(Color(0.42, 0.29, 0.18)), Vector3(0.55, 0.85, 0.18), Vector3(0, 0, -0.06)))
	var orb := SphereMesh.new()
	orb.radius = 0.13
	orb.height = 0.26
	orb.radial_segments = 10
	orb.rings = 5
	_orb = Avatar.part(orb, Fx.glow_mat(Color(0.45, 1.0, 0.8)), Vector3(0.6, 1.78, 0.18))
	add_child(_orb)
	# (sin luz propia: en el navegador, cada luz extra obliga a redibujar todo lo que alcanza)

	# Halo en el suelo: aquí hay alguien con quien hablar
	var ring := TorusMesh.new()
	ring.inner_radius = 0.95
	ring.outer_radius = 1.08
	ring.rings = 32
	ring.ring_segments = 6
	_halo = MeshInstance3D.new()
	_halo.mesh = ring
	_halo.material_override = Fx.glow_mat(Color(1.0, 0.85, 0.4), 0.7)
	_halo.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_halo.position = Vector3(0, 0.06, 0)
	add_child(_halo)

	# Indicador sobre la cabeza cuando el jugador está a distancia de hablar
	_prompt = Label3D.new()
	_prompt.text = "F"
	_prompt.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_prompt.no_depth_test = true
	_prompt.pixel_size = 0.007
	_prompt.font_size = 72
	_prompt.outline_size = 18
	_prompt.modulate = Color(1.0, 0.86, 0.4)
	_prompt.outline_modulate = Color(0.06, 0.04, 0.02, 0.95)
	_prompt.position = Vector3(0, 2.75, 0)
	_prompt.visible = false
	add_child(_prompt)


## Distancia en el plano a un punto del mundo.
func distance_to(p: Vector3) -> float:
	return Vector2(p.x - position.x, p.z - position.z).length()


## near: el jugador está a distancia de hablar · attention: con quién habla (o null).
func update_view(delta: float, near: bool, look_at_pos: Variant, talking: bool) -> void:
	_time += delta
	_av.animate(delta, true, false)
	_halo.scale = Vector3.ONE * (1.0 + 0.06 * sin(_time * 2.4))
	_orb.position.y = 1.78 + 0.03 * sin(_time * 3.1)
	_prompt.visible = near and not talking
	_prompt.scale = Vector3.ONE * (0.62 + 0.05 * sin(_time * 5.0))
	# Mira a quien se le acerca; si no hay nadie, vuelve a su postura
	var want := _home_yaw
	if look_at_pos is Vector3 and (near or talking):
		var d: Vector3 = (look_at_pos as Vector3) - position
		want = atan2(d.x, d.z)
	rotation.y = lerp_angle(rotation.y, want, minf(1.0, delta * 5.0))
	# Gesticula al hablar
	if talking:
		_gesture_in -= delta
		if _gesture_in <= 0.0:
			_gesture_in = 2.6
			_av.play_action("interact")
