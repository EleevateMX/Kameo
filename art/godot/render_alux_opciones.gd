extends SceneTree
## El alux con las piezas del personalizador, dibujado con el renderer real de Godot
## (Compatibility/OpenGL) y la luz del juego. Enciende y apaga las mallas por nombre y
## tiñe los materiales igual que game/scripts/client/avatar.gd, así que sirve también
## para comprobar el contrato del modelo. Carga el .glb directamente, sin importarlo.
## Sin GPU funciona con Mesa por software bajo xvfb. Necesita un proyecto vacío:
##   mkdir -p /tmp/alux_godot && touch /tmp/alux_godot/project.godot
##   xvfb-run -a .tools/godot --path /tmp/alux_godot --rendering-driver opengl3 --resolution 480x480 \
##       --script "$PWD/art/godot/render_alux_opciones.gd" -- /carpeta/de/salida ruta.glb tomas.json
## Lo normal es lanzarlo con art/blender/hojas_alux_opciones.py, que escribe tomas.json y
## monta las hojas. Cada toma es un diccionario (todo opcional menos «n»):
##   n: nombre del .png          hat: índice del tocado (0–6)
##   outfit, acc, amu: índices de vestimenta, accesorio y amuleto (0 = ninguno)
##   color, accent, skin: "#rrggbb" del color principal, del secundario y del tono de piel
##   anim, t: animación y segundo        yaw, pitch, dist, target: cámara (yaw 0 = de frente)
##   raw: true = materiales tal como se exportan, sin teñir ni aclarar

## Catálogos: el índice es el del personalizador (game/scripts/shared/look_def.gd)
const HATS := [["Hat_Palma"], ["Hat_Penacho"], ["Hat_Flor"], [], ["Hat_Plumas"], ["Hat_Panuelo"], ["Hat_Hojas"]]
const HAT_NODES := ["Hat_Palma", "Hat_Penacho", "Hat_Flor", "Hat_Plumas", "Hat_Panuelo", "Hat_Hojas"]
const OUTFITS := ["", "Outfit_Capa", "Outfit_Faja", "Outfit_Bordado"]
const ACCESSORIES := ["", "Acc_Morral", "Acc_Sonaja", "Acc_Caracol", "Acc_Farol"]
const AMULETS := ["", "Amu_Jade", "Amu_Concha", "Amu_Obsidiana", "Amu_Semillas"]
## El material «Skin» lleva la piel media en gris 0.75 (el rubor es más claro y un vértice
## no pasa de 1): su albedo es el tono de piel × 4/3. Luego, como «Body», se aclara × 1.12.
const SKIN_GAIN := 4.0 / 3.0
const LIT := 1.12

var out_dir := ""
var glb := ""
var shots: Array = []
var idx := 0
var wait := 0
var world: Node3D
var cam: Camera3D
var sun: DirectionalLight3D
var model: Node3D

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() < 3:
		push_error("uso: -- carpeta_de_salida ruta.glb tomas.json")
		quit(1)
		return
	out_dir = args[0] if args[0].ends_with("/") else args[0] + "/"
	glb = args[1]
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(args[2]))
	if typeof(parsed) != TYPE_ARRAY or (parsed as Array).is_empty():
		push_error("tomas.json no es una lista de tomas")
		quit(1)
		return
	shots = parsed
	DirAccess.make_dir_recursive_absolute(out_dir)
	world = Node3D.new()
	get_root().add_child(world)
	# la luz del juego (game/scripts/client/world_builder.gd): ambiente frío, sol cálido,
	# curva fílmica, resplandor y el ajuste de saturación y contraste
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("#33454d")       # oscuro: el resplandor del juego quema un cielo claro
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.62, 0.76, 0.8)
	env.ambient_light_energy = 0.95
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 0.98
	env.tonemap_white = 4.5
	env.glow_enabled = true
	env.glow_intensity = 0.45
	env.glow_bloom = 0.08
	env.glow_hdr_threshold = 1.0
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.18
	env.adjustment_contrast = 1.06
	var we := WorldEnvironment.new()
	we.environment = env
	world.add_child(we)
	sun = DirectionalLight3D.new()
	sun.light_color = Color(1.0, 0.88, 0.68)
	sun.light_energy = 1.2
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 30.0
	sun.shadow_opacity = 0.62
	sun.shadow_blur = 1.6
	sun.shadow_bias = 0.06
	world.add_child(sun)
	var ground := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(60, 60)
	ground.mesh = pm
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color("#56664f")
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

func _importer_meshes(n: Node, out: Array) -> void:
	if n is ImporterMeshInstance3D:
		out.append(n)
	for c in n.get_children():
		_importer_meshes(c, out)

func _load_model() -> Node3D:
	var doc := GLTFDocument.new()
	var st := GLTFState.new()
	if doc.append_from_file(glb, st) != OK:
		push_error("no se pudo cargar " + glb)
		return null
	var root: Node3D = doc.generate_scene(st)
	# fuera del importador del editor las mallas llegan como ImporterMeshInstance3D
	var pending: Array = []
	_importer_meshes(root, pending)
	for im in pending:
		var m := MeshInstance3D.new()
		m.name = im.name
		m.transform = im.transform
		m.mesh = im.mesh.get_mesh()
		m.skin = im.skin
		m.skeleton = im.skeleton_path
		im.replace_by(m)
		im.free()
	return root

## Lo mismo que hace avatar.gd: tiñe por nombre de material y enciende por nombre de nodo
func _apply_look(inst: Node3D, s: Dictionary) -> void:
	var raw := bool(s.get("raw", false))
	var color := Color.from_string(str(s.get("color", "#2ec4a6")), Color("#2ec4a6"))
	var accent := Color.from_string(str(s.get("accent", "#fff7ec")), Color.WHITE)
	var skin := Color.from_string(str(s.get("skin", "#a9714b")), Color("#a9714b"))
	for mi in inst.find_children("*", "MeshInstance3D", true, false):
		var mesh := (mi as MeshInstance3D).mesh
		for i in mesh.get_surface_count():
			var mat := mesh.surface_get_material(i)
			if raw or not (mat is StandardMaterial3D):
				continue
			var mat_name := str(mat.resource_name)
			var tint: Variant = null
			if mat_name.begins_with("Tunic"):
				tint = color
			elif mat_name.begins_with("Trim"):
				tint = accent
			elif mat_name.begins_with("Skin"):
				tint = Color(skin.r * SKIN_GAIN * LIT, skin.g * SKIN_GAIN * LIT, skin.b * SKIN_GAIN * LIT)
			elif mat_name == "Body" or mat_name == "Headwear":
				tint = Color(LIT, LIT, LIT)
			if tint != null:
				var own := mat.duplicate() as StandardMaterial3D
				own.albedo_color = tint
				(mi as MeshInstance3D).set_surface_override_material(i, own)
	var keep: Array = HATS[clampi(int(s.get("hat", 0)), 0, HATS.size() - 1)]
	for n in HAT_NODES:
		for node in inst.find_children(n + "*", "Node3D", true, false):
			(node as Node3D).visible = keep.has(n)
	for family in [[OUTFITS, "outfit"], [ACCESSORIES, "acc"], [AMULETS, "amu"]]:
		var options: Array = family[0]
		var chosen := str(options[clampi(int(s.get(family[1], 0)), 0, options.size() - 1)])
		for prefix in options:
			if str(prefix).is_empty():
				continue
			for node in inst.find_children(str(prefix) + "*", "Node3D", true, false):
				(node as Node3D).visible = str(prefix) == chosen

func _setup_shot() -> void:
	if model:
		model.queue_free()
		model = null
	var s: Dictionary = shots[idx]
	model = _load_model()
	if model == null:
		quit(1)
		return
	world.add_child(model)
	_apply_look(model, s)
	var ap: AnimationPlayer = _find(model, "AnimationPlayer")
	var anim := str(s.get("anim", ""))
	if anim != "" and ap != null:
		if ap.has_animation(anim):
			ap.play(anim)
			ap.seek(float(s.get("t", 0.0)), true)
			ap.pause()
		else:
			push_warning("falta la animación " + anim)
	var yaw := deg_to_rad(float(s.get("yaw", 0.0)))
	var pitch := deg_to_rad(float(s.get("pitch", 6.0)))
	var tg: Array = s.get("target", [0.0, 0.72, 0.0])
	var target := Vector3(float(tg[0]), float(tg[1]), float(tg[2]))
	# yaw 0 = cámara delante del personaje (que mira a +Z); 90 = a su izquierda (+X)
	var off := Vector3(sin(yaw) * cos(pitch), sin(pitch), cos(yaw) * cos(pitch)) * float(s.get("dist", 3.2))
	cam.look_at_from_position(target + off, target, Vector3.UP)
	# el sol acompaña a la cámara (algo a su izquierda y por encima) para que cada vista se lea
	sun.rotation_degrees = Vector3(-38.0, float(s.get("yaw", 0.0)) + 32.0, 0.0)
	world.get_node("Ground").visible = float(s.get("pitch", 6.0)) >= 0.0
	wait = 0

func _process(_delta: float) -> bool:
	if model == null:
		return true
	wait += 1
	if wait < 4:
		return false
	var img := get_root().get_texture().get_image()
	img.save_png(out_dir + str(shots[idx]["n"]) + ".png")
	idx += 1
	if idx >= shots.size():
		return true
	_setup_shot()
	return false
