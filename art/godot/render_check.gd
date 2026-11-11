extends SceneTree
## Capturas con el renderer real de Godot (Compatibility/OpenGL), para ver los .glb
## tal como se verán en el juego. Sin GPU funciona con Mesa por software bajo xvfb:
##   xvfb-run -a .tools/godot --rendering-driver opengl3 --path game --resolution 480x480 \
##       --script "$PWD/art/godot/render_check.gd" -- /carpeta/de/salida
var out_dir := "user://"
var shots := [
	# glb, anim, t, yaw, pitch, dist, target, hat, name
	["alux", "", 0.0, 30.0, 10.0, 3.2, Vector3(0, 0.78, 0), "Hat_Palma", "a01"],
	["alux", "", 0.0, 155.0, 14.0, 3.2, Vector3(0, 0.78, 0), "Hat_Penacho", "a02"],
	["alux", "", 0.0, 12.0, 3.0, 1.7, Vector3(0, 1.04, 0), "Hat_Flor", "a03"],
	["alux", "Idle", 0.5, 20.0, -25.0, 2.6, Vector3(0, 0.8, 0), "Hat_Palma", "a04"],
	["alux", "Run", 0.0667, 80.0, 6.0, 3.2, Vector3(0, 0.7, 0), "", "a05"],
	["alux", "Cast", 0.1, 50.0, 8.0, 3.2, Vector3(0, 0.78, 0), "Hat_Palma", "a06"],
	["alux", "Transform", 0.1, 25.0, 8.0, 3.4, Vector3(0, 0.85, 0), "Hat_Flor", "a07"],
	["alux", "Death", 0.9, 55.0, 30.0, 3.3, Vector3(0, 0.3, -0.4), "Hat_Flor", "a08"],
	["balam", "", 0.0, 35.0, 12.0, 3.9, Vector3(0, 0.55, -0.15), "", "b01"],
	["balam", "", 0.0, 150.0, 16.0, 3.9, Vector3(0, 0.55, -0.15), "", "b02"],
	["balam", "", 0.0, 28.0, 8.0, 1.7, Vector3(0, 0.85, 0.6), "", "b03"],
	["balam", "Run", 0.2, 90.0, 4.0, 4.0, Vector3(0, 0.55, -0.15), "", "b04"],
	["balam", "Claw", 0.1, 330.0, 8.0, 3.6, Vector3(0, 0.6, 0.1), "", "b05"],
	["balam", "Pounce", 0.25, 80.0, 5.0, 4.2, Vector3(0, 0.65, 0), "", "b06"],
	["balam", "Transform", 0.25, 60.0, 5.0, 4.4, Vector3(0, 0.8, 0), "", "b07"],
	["balam", "Charge", 0.2, 40.0, -15.0, 3.6, Vector3(0, 0.5, 0), "", "b08"],
]
var idx := 0
var wait := 0
var cam: Camera3D
var model: Node3D
var world: Node3D

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out_dir = args[0]
	if not out_dir.ends_with("/"):
		out_dir += "/"
	DirAccess.make_dir_recursive_absolute(out_dir)
	get_root().size = Vector2i(480, 480)
	world = Node3D.new()
	get_root().add_child(world)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("#b9d3e6")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.75, 0.82, 0.9)
	env.ambient_light_energy = 0.7
	var we := WorldEnvironment.new()
	we.environment = env
	world.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, 145, 0)
	sun.light_energy = 1.3
	sun.shadow_enabled = true
	world.add_child(sun)
	var ground := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(40, 40)
	ground.mesh = pm
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color("#5d7a4a")
	ground.material_override = gm
	ground.name = "Ground"
	world.add_child(ground)
	cam = Camera3D.new()
	cam.fov = 33.4
	world.add_child(cam)
	cam.current = true
	_setup_shot()

func _find(n: Node, cls: String) -> Node:
	if n.get_class() == cls:
		return n
	for c in n.get_children():
		var r := _find(c, cls)
		if r:
			return r
	return null

func _setup_shot() -> void:
	if model:
		model.queue_free()
		model = null
	var s: Array = shots[idx]
	var ps: PackedScene = load("res://assets/characters/%s.glb" % s[0])
	model = ps.instantiate()
	world.add_child(model)
	for hat in ["Hat_Palma", "Hat_Penacho", "Hat_Flor", "Hair"]:
		var n := model.find_child(hat, true, false)
		if n:
			n.visible = (hat == s[7]) or (hat == "Hair" and s[7] in ["Hat_Flor", "Hat_Penacho", ""])
	var ap: AnimationPlayer = _find(model, "AnimationPlayer")
	if s[1] != "":
		if not ap.has_animation(s[1]):
			push_warning("falta la animación " + s[1])
			wait = 0
			return
		ap.play(s[1])
		ap.seek(s[2], true)
		ap.pause()
	var yaw := deg_to_rad(s[3])
	var pitch := deg_to_rad(s[4])
	# yaw 0 = cámara delante del personaje (que mira a +Z); 90 = a su izquierda (+X)
	var off := Vector3(sin(yaw) * cos(pitch), sin(pitch), cos(yaw) * cos(pitch)) * float(s[5])
	cam.look_at_from_position((s[6] as Vector3) + off, s[6], Vector3.UP)
	world.get_node("Ground").visible = s[4] >= 0.0
	wait = 0

func _process(_delta: float) -> bool:
	wait += 1
	if wait < 4:
		return false
	var img := get_root().get_texture().get_image()
	img.save_png(out_dir + shots[idx][8] + ".png")
	idx += 1
	if idx >= shots.size():
		return true
	_setup_shot()
	return false
