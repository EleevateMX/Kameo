extends SceneTree
## Capturas de la propuesta de Nojoch Tuunich con el renderer real de Godot
## (Compatibility/OpenGL), para verlo como se verá en el juego: caras de un solo lado,
## color de vértice y materiales emisivos. Carga el .glb directamente, sin importarlo
## en el proyecto. Sin GPU funciona con Mesa por software bajo xvfb:
##   xvfb-run -a .tools/godot --rendering-driver opengl3 --resolution 640x640 \
##       --script "$PWD/art/godot/render_nojoch.gd" -- /carpeta/de/salida [ruta.glb]
## Las tomas marcadas con «recuerda» cambian los materiales por nombre, como hará el
## juego: apagan «Silence» y encienden «Glyph1»…«Glyph4», «Heart» y «Eye».
var out_dir := "user://"
var glb := ""
var shots := [
	# anim, t, yaw, pitch, dist, target, recuerda, name
	["Idle", 0.0, 25.0, 8.0, 15.0, Vector3(0, 2.5, 0), false, "n01_frente"],
	["Idle", 0.0, 155.0, 12.0, 15.0, Vector3(0, 2.5, 0), false, "n02_espalda"],
	["Idle", 0.0, 200.0, -20.0, 14.0, Vector3(0, 2.6, 0), false, "n03_desde_abajo"],
	["Sleep", 0.0, 35.0, 30.0, 14.0, Vector3(0, 1.5, 0), false, "n04_dormido"],
	["Slam", 1.5, 60.0, 14.0, 17.0, Vector3(0, 1.6, 1.2), false, "n05_golpe"],
	["Kneel", 2.0, 140.0, 20.0, 15.0, Vector3(0, 2.0, 0), false, "n06_de_rodillas"],
	["Remember", 3.0, 25.0, 10.0, 15.0, Vector3(0, 2.2, 0.4), true, "n07_recuerda"],
	["Remember", 3.0, 160.0, 14.0, 15.0, Vector3(0, 2.2, 0), true, "n08_recuerda_espalda"],
]
var idx := 0
var wait := 0
var cam: Camera3D
var model: Node3D
var world: Node3D
var originales := {}

func _find(n: Node, cls: String) -> Node:
	if n.get_class() == cls:
		return n
	for c in n.get_children():
		var r := _find(c, cls)
		if r:
			return r
	return null

func _mallas(n: Node, out: Array) -> void:
	if n is ImporterMeshInstance3D:
		out.append(n)
	for c in n.get_children():
		_mallas(c, out)

func _cargar() -> Node3D:
	var doc := GLTFDocument.new()
	var st := GLTFState.new()
	if doc.append_from_file(glb, st) != OK:
		push_error("no se pudo cargar " + glb)
		return null
	var root: Node3D = doc.generate_scene(st)
	# fuera del importador del editor las mallas llegan como ImporterMeshInstance3D
	var pendientes: Array = []
	_mallas(root, pendientes)
	for im in pendientes:
		var mi := MeshInstance3D.new()
		mi.name = im.name
		mi.transform = im.transform
		mi.mesh = im.mesh.get_mesh()
		mi.skin = im.skin
		mi.skeleton = im.skeleton_path
		im.replace_by(mi)
		im.free()
	return root

func _recordar(si: bool) -> void:
	var mi: MeshInstance3D = _find(model, "MeshInstance3D")
	for i in mi.mesh.get_surface_count():
		var m: BaseMaterial3D = mi.mesh.surface_get_material(i)
		var nombre := m.resource_name
		if not originales.has(nombre):
			originales[nombre] = m
		if not si:
			mi.set_surface_override_material(i, null)
			continue
		var c: BaseMaterial3D = originales[nombre].duplicate()
		if nombre == "Silence":
			c.emission_enabled = false
			c.albedo_color = Color("#4d423b")
		elif nombre.begins_with("Glyph") or nombre == "Heart" or nombre == "Eye":
			c.emission_enabled = true
			c.emission = Color("#59ffe0")
			c.emission_energy_multiplier = 2.5
		mi.set_surface_override_material(i, c)

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out_dir = args[0]
	if not out_dir.ends_with("/"):
		out_dir += "/"
	glb = args[1] if args.size() > 1 else (get_script() as Script).resource_path.get_base_dir().path_join("../propuestas/nojoch/nojoch.glb")
	DirAccess.make_dir_recursive_absolute(out_dir)
	world = Node3D.new()
	get_root().add_child(world)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("#b9d3e6")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	# la luz del juego (game/scripts/client/world_builder.gd): ambiente, sol cálido y curva fílmica
	env.ambient_light_color = Color(0.62, 0.76, 0.8)
	env.ambient_light_energy = 0.95
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 0.98
	env.tonemap_white = 4.5
	var we := WorldEnvironment.new()
	we.environment = env
	world.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, 145, 0)
	sun.light_color = Color(1.0, 0.88, 0.68)
	sun.light_energy = 1.2
	sun.shadow_enabled = true
	world.add_child(sun)
	var ground := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(60, 60)
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
	model = _cargar()
	if model == null:
		quit(1)
		return
	world.add_child(model)
	_setup_shot()

func _setup_shot() -> void:
	var s: Array = shots[idx]
	var ap: AnimationPlayer = _find(model, "AnimationPlayer")
	ap.play(s[0])
	ap.seek(s[1], true)
	ap.pause()
	_recordar(s[6])
	var yaw := deg_to_rad(s[2])
	var pitch := deg_to_rad(s[3])
	# yaw 0 = cámara delante del personaje (que mira a +Z); 90 = a su izquierda (+X)
	var off := Vector3(sin(yaw) * cos(pitch), sin(pitch), cos(yaw) * cos(pitch)) * float(s[4])
	cam.look_at_from_position((s[5] as Vector3) + off, s[5], Vector3.UP)
	world.get_node("Ground").visible = s[3] >= 0.0
	wait = 0

func _process(_delta: float) -> bool:
	wait += 1
	if wait < 4:
		return false
	var img := get_root().get_texture().get_image()
	img.save_png(out_dir + shots[idx][7] + ".png")
	print("captura ", out_dir + shots[idx][7] + ".png")
	idx += 1
	if idx >= shots.size():
		return true
	_setup_shot()
	return false
