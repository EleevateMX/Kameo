extends Node3D
## Personaje no jugador con el que se puede hablar (por ahora, Chiich Yaxché).
## Usa su propio modelo (art/blender/build_yaxche.py); si faltara, un respaldo con primitivas.
## No tiene colisión ni reglas: es presentación del cliente. Su posición y su alcance
## vienen de shared/story_def.gd, que es lo que comprueba el servidor.

const Avatar := preload("res://scripts/client/avatar.gd")
const Fx := preload("res://scripts/client/fx.gd")
const Story := preload("res://scripts/shared/story_def.gd")
const World := preload("res://scripts/shared/world_def.gd")

var npc_id := ""
var talk_range := 3.0
var _av: Avatar               # sólo si falta el modelo propio
var _model: Node3D
var _anim: AnimationPlayer
var _bud: StandardMaterial3D  # brote de jade del bastón
var _halo: MeshInstance3D
var _was_talking := false
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

	if not _load_model("res://assets/characters/%s.glb" % id):
		_build_placeholder(def)

	# Nombre sobre la cabeza
	var label := Label3D.new()
	label.text = str(def.name)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.pixel_size = 0.0042
	label.font_size = 34
	label.outline_size = 10
	label.modulate = Color(1.0, 0.9, 0.6)
	label.outline_modulate = Color(0.05, 0.08, 0.07, 0.9)
	label.position = Vector3(0, 2.25, 0)
	add_child(label)

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


## Carga el modelo propio del personaje (art/blender/build_yaxche.py). Devuelve false si no existe.
func _load_model(path: String) -> bool:
	if not ResourceLoader.exists(path):
		return false
	var scene := load(path) as PackedScene
	if scene == null:
		return false
	_model = scene.instantiate() as Node3D
	if _model == null:
		return false
	_model.scale = Vector3.ONE * 1.15
	add_child(_model)
	var players := _model.find_children("*", "AnimationPlayer", true, false)
	if not players.is_empty():
		_anim = players[0] as AnimationPlayer
		for n in ["Idle", "Talk"]:
			if _anim.has_animation(n):
				_anim.get_animation(n).loop_mode = Animation.LOOP_LINEAR
		if _anim.has_animation("Idle"):
			_anim.play("Idle")
	# El brote de jade del bastón late por su cuenta (material propio: el collar no cambia)
	var staff := _model.find_child("Staff", true, false) as MeshInstance3D
	if staff != null and staff.mesh != null:
		for i in staff.mesh.get_surface_count():
			var mat := staff.mesh.surface_get_material(i)
			if mat is StandardMaterial3D and str(mat.resource_name) == "Jade":
				_bud = mat.duplicate() as StandardMaterial3D
				_bud.emission_enabled = true
				staff.set_surface_override_material(i, _bud)
	return true


## Respaldo si falta el modelo: el alux con rebozo y bastón hechos con primitivas.
func _build_placeholder(def: Dictionary) -> void:
	_av = Avatar.new()
	add_child(_av)
	_av.setup(" ", str(def.color), 2)
	_av.scale = Vector3.ONE * 1.12
	var shawl := CylinderMesh.new()
	shawl.top_radius = 0.2
	shawl.bottom_radius = 0.5
	shawl.height = 0.42
	shawl.radial_segments = 14
	add_child(Avatar.part(shawl, Avatar.mat(Color(0.96, 0.93, 0.84), 0.12), Vector3(0, 0.98, 0)))
	var staff := CylinderMesh.new()
	staff.top_radius = 0.035
	staff.bottom_radius = 0.05
	staff.height = 1.7
	staff.radial_segments = 8
	add_child(Avatar.part(staff, Avatar.mat(Color(0.42, 0.29, 0.18)), Vector3(0.55, 0.85, 0.18), Vector3(0, 0, -0.06)))


## Distancia en el plano a un punto del mundo.
func distance_to(p: Vector3) -> float:
	return Vector2(p.x - position.x, p.z - position.z).length()


## near: el jugador está a distancia de hablar · attention: con quién habla (o null).
func update_view(delta: float, near: bool, look_at_pos: Variant, talking: bool) -> void:
	_time += delta
	_halo.scale = Vector3.ONE * (1.0 + 0.06 * sin(_time * 2.4))
	_prompt.visible = near and not talking
	_prompt.scale = Vector3.ONE * (0.62 + 0.05 * sin(_time * 5.0))
	# Mira a quien se le acerca; si no hay nadie, vuelve a su postura
	var want := _home_yaw
	if look_at_pos is Vector3 and (near or talking):
		var d: Vector3 = (look_at_pos as Vector3) - position
		want = atan2(d.x, d.z)
	rotation.y = lerp_angle(rotation.y, want, minf(1.0, delta * 5.0))
	if _bud != null:
		_bud.emission_energy_multiplier = 1.4 + 0.7 * sin(_time * 2.2) + (1.2 if talking else 0.0)
	if _anim != null:
		# Habla mientras dura el diálogo; al terminar, un gesto y vuelve al reposo
		if talking and not _was_talking and _anim.has_animation("Talk"):
			_anim.play("Talk", 0.25)
		elif not talking and _was_talking:
			_anim.play("Idle", 0.3)
		elif not talking and not _anim.is_playing():
			_anim.play("Idle", 0.3)
	elif _av != null:
		_av.animate(delta, true, false)
		if talking:
			_gesture_in -= delta
			if _gesture_in <= 0.0:
				_gesture_in = 2.6
				_av.play_action("interact")
	_was_talking = talking


## Gesto suelto (p. ej. «Scold» al regañar, «Bless» al despedir).
func gesture(anim: String) -> void:
	if _anim != null and _anim.has_animation(anim):
		_anim.play(anim, 0.15)
