extends SceneTree
## Nojoch Tuunich con el renderer real de Godot (Compatibility/OpenGL) y la luz del juego,
## para verlo como se verá jugando: caras de un solo lado, color de vértice, materiales
## emisivos y animaciones. Carga el .glb directamente, sin importarlo en el proyecto.
## Sin GPU funciona con Mesa por software bajo xvfb. Necesita un proyecto vacío:
##   mkdir -p /tmp/nojoch_godot && touch /tmp/nojoch_godot/project.godot
##   xvfb-run -a .tools/godot --path /tmp/nojoch_godot --rendering-driver opengl3 --resolution 640x640 \
##       --script "$PWD/art/godot/render_nojoch.gd" -- /carpeta/de/salida [ruta.glb] [opciones]
##
## Opciones (clave=valor, en cualquier orden):
##   modo=tomas   (por omisión) las capturas fijas de TOMAS: n01_….png
##   modo=anim    cada animación cuadro a cuadro: <salida>/<Anim>/f0001.png … (para los vídeos)
##   anims=Walk,Charge   solo esas animaciones (modo=anim)
##   fps=15       cuadros por segundo (modo=anim)
##   giro=90      fuerza el giro de la cámara en todas las animaciones (modo=anim)
##   rotulo=0     sin el nombre de la animación sobreimpreso (modo=anim)
##   estado=olvido   un mismo estado para todas las animaciones en modo=anim (por omisión,
##                   cada una lleva el estado en que el juego la usa: ver CAMARAS)
##   efectos=0    sin el resplandor ni el ajuste de saturación y contraste del juego
##   toma=Anim,seg,giro,elev,dist,x,y,z,estado,cara,nombre   una captura suelta (se puede repetir)
##
## Estados (ESTADOS): dormido, olvido, olvido0 (sin glifos), furia, recuerdo, liberado y
## «glb» (los materiales tal como se exportan). Cambian los materiales por nombre, como
## hace el juego. Caras: Face_Sad, Face_Pain, Face_Serene o «A:B:peso» para mezclar dos;
## se leen de las animaciones de un cuadro y se ponen en los huesos después de la
## animación del cuerpo (las del cuerpo no llevan pista en Brow_* ni Mouth_*).

const JADE := Color(0.24, 0.91, 0.77)
const MAGENTA := Color(1.0, 0.2, 0.61)
const VETA_APAGADA := Color("#8a7460")       # las vetas base cuando ya no hay Silencio: cicatrices
const GLIFO_APAGADO := Color("#5a564b")
const OJO_APAGADO := Color("#2e302c")
const HUESOS_CARA := ["Brow_L", "Brow_R", "Mouth_L", "Mouth_R", "Lids", "Jaw"]

## ojos: [color | null (apagados), energía]; vetas / vetas2: energía de emisión (0 = apagadas);
## glifos: cuántos encendidos; corazon: energía; cara: pose facial
const ESTADOS := {
	"dormido": {"ojos": [null, 0.0], "vetas": 0.25, "vetas2": 0.0, "glifos": 0, "corazon": 0.5, "cara": ""},
	"olvido": {"ojos": [MAGENTA, 1.6], "vetas": 1.7, "vetas2": 0.0, "glifos": 2, "corazon": 1.4, "cara": "Face_Sad"},
	"olvido0": {"ojos": [MAGENTA, 1.6], "vetas": 1.7, "vetas2": 0.0, "glifos": 0, "corazon": 1.4, "cara": "Face_Sad"},
	"furia": {"ojos": [MAGENTA, 2.6], "vetas": 2.6, "vetas2": 2.4, "glifos": 4, "corazon": 1.4, "cara": "Face_Pain"},
	"recuerdo": {"ojos": [JADE, 1.6], "vetas": 0.7, "vetas2": 0.0, "glifos": 4, "corazon": 2.0, "cara": "Face_Sad:Face_Serene:0.5"},
	"liberado": {"ojos": [JADE, 1.6], "vetas": 0.0, "vetas2": 0.0, "glifos": 4, "corazon": 2.4, "cara": "Face_Serene"},
}

## anim, segundos, giro, elevación, distancia, objetivo, estado, cara ("" = la del estado), nombre
var TOMAS := [
	["Idle", 0.0, 25.0, 8.0, 15.0, Vector3(0, 2.5, 0), "olvido", "", "n01_olvido_frente"],
	["Idle", 0.0, 155.0, 12.0, 15.0, Vector3(0, 2.5, 0), "olvido", "", "n02_olvido_espalda"],
	["Idle", 0.0, 200.0, -20.0, 14.0, Vector3(0, 2.6, 0), "olvido", "", "n03_desde_abajo"],
	["Sleep", 0.0, 35.0, 30.0, 14.0, Vector3(0, 1.5, -0.6), "dormido", "", "n04_dormido"],
	["Slam", 1.5, 60.0, 14.0, 17.0, Vector3(0, 1.6, 1.2), "furia", "", "n05_furia_golpe"],
	["Kneel", 2.0, 140.0, 20.0, 15.0, Vector3(0, 2.0, 0), "furia", "", "n06_furia_de_rodillas"],
	["Remember", 3.0, 25.0, 10.0, 15.0, Vector3(0, 2.2, 0.4), "liberado", "", "n07_liberado"],
	["Remember", 3.0, 160.0, 14.0, 15.0, Vector3(0, 2.2, 0), "liberado", "", "n08_liberado_espalda"],
	["Idle", 0.0, 10.0, 4.0, 5.2, Vector3(0, 3.78, 0.3), "olvido", "Face_Sad", "n09_cara_triste"],
	["Idle", 0.0, 10.0, 4.0, 5.2, Vector3(0, 3.78, 0.3), "furia", "Face_Pain", "n10_cara_dolor"],
	["Idle", 0.0, 10.0, 4.0, 5.2, Vector3(0, 3.78, 0.3), "liberado", "Face_Serene", "n11_cara_serena"],
	["Idle", 0.0, 320.0, 10.0, 15.0, Vector3(0, 2.5, 0), "glb", "", "n12_como_se_exporta"],
]

## Cámara de cada animación en modo=anim: giro, elevación, distancia, objetivo, velocidad
## (m/s) a la que el juego la desplaza (la cámara le sigue y el suelo enseña si patina),
## cuántas veces se repite (los ciclos cortos) y el estado en que el juego la usa.
const CAMARAS := {
	"Sleep": [35.0, 14.0, 10.5, Vector3(0, 1.7, -0.5), 0.0, 1, "dormido"],
	"Awaken": [35.0, 10.0, 12.5, Vector3(0, 2.4, -0.2), 0.0, 1, "olvido0"],
	"Idle": [30.0, 8.0, 11.5, Vector3(0, 2.6, 0), 0.0, 1, "olvido0"],
	"Walk": [62.0, 10.0, 12.0, Vector3(0, 2.5, 0), 1.7, 4, "olvido"],
	"Slam": [-52.0, 12.0, 14.0, Vector3(0, 2.7, 1.3), 0.0, 1, "olvido"],
	"Sweep": [18.0, 32.0, 15.0, Vector3(0, 1.9, 0.8), 0.0, 1, "olvido"],
	"Summon": [52.0, 12.0, 14.0, Vector3(0, 2.7, 1.0), 0.0, 1, "olvido"],
	"Charge": [48.0, 10.0, 12.5, Vector3(0, 2.2, 0.3), 12.0, 4, "furia"],
	"Stunned": [30.0, 10.0, 11.5, Vector3(0, 2.5, 0), 0.0, 2, "furia"],
	"Kneel": [38.0, 10.0, 11.5, Vector3(0, 2.3, 0.2), 0.0, 1, "furia"],
	"Remember": [32.0, 10.0, 11.0, Vector3(0, 2.2, 0.5), 0.0, 1, "liberado"],
}
const ORDEN := ["Sleep", "Awaken", "Idle", "Walk", "Slam", "Sweep", "Summon", "Charge", "Stunned", "Kneel", "Remember"]

var out_dir := "user://"
var glb := ""
var modo := "tomas"
var fps := 15.0
var giro_forzado := NAN
var rotulo := true
var estado_anim := ""
var solo: PackedStringArray = []
var efectos := true

var idx := 0
var cuadro := 0
var wait := 0
var cam: Camera3D
var model: Node3D
var world: Node3D
var ap: AnimationPlayer
var sk: Skeleton3D
var mi: MeshInstance3D
var label: Label
var originales := {}
var cara_actual := ""
var lista: Array = []

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
		var m := MeshInstance3D.new()
		m.name = im.name
		m.transform = im.transform
		m.mesh = im.mesh.get_mesh()
		m.skin = im.skin
		m.skeleton = im.skeleton_path
		im.replace_by(m)
		im.free()
	return root

## Materiales de un estado, por nombre de superficie y con copia propia, como hace el juego.
func _estado(nombre: String) -> void:
	for i in mi.mesh.get_surface_count():
		var m: BaseMaterial3D = mi.mesh.surface_get_material(i)
		var n := m.resource_name
		if not originales.has(n):
			originales[n] = m
		if nombre == "glb" or not ESTADOS.has(nombre):
			mi.set_surface_override_material(i, null)
			continue
		var e: Dictionary = ESTADOS[nombre]
		var c: BaseMaterial3D = originales[n].duplicate()
		if n == "Silence":
			var v: float = e["vetas"]
			c.emission_enabled = v > 0.0
			c.emission = MAGENTA
			c.emission_energy_multiplier = v
			if v <= 0.0:                    # sin Silencio: cicatrices de piedra
				c.albedo_color = VETA_APAGADA
				c.vertex_color_use_as_albedo = false
		elif n == "Silence2":
			var v2: float = e["vetas2"]
			c.emission_enabled = v2 > 0.0   # apagado se queda como se exporta: piedra
			c.emission = MAGENTA
			c.emission_energy_multiplier = v2
			if v2 > 0.0:
				c.albedo_color = MAGENTA
				c.vertex_color_use_as_albedo = false
		elif n.begins_with("Glyph"):
			var lit: bool = int(n.substr(5)) <= int(e["glifos"])
			c.emission_enabled = lit
			c.emission = JADE
			c.emission_energy_multiplier = 2.4
			c.albedo_color = Color(1, 1, 1) if lit else GLIFO_APAGADO
		elif n == "Eye":
			var col = e["ojos"][0]
			c.vertex_color_use_as_albedo = false
			c.emission_enabled = col != null
			if col != null:
				c.emission = col
				c.emission_energy_multiplier = e["ojos"][1]
				c.albedo_color = col
			else:
				c.albedo_color = OJO_APAGADO
		elif n == "Heart":
			c.emission_enabled = true
			c.emission_energy_multiplier = e["corazon"]
		mi.set_surface_override_material(i, c)

func _valor(nombre: String, hueso: String, tipo: int):
	if not ap.has_animation(nombre):
		return null
	var an := ap.get_animation(nombre)
	for ti in an.get_track_count():
		if an.track_get_type(ti) == tipo and an.track_get_path(ti).get_subname(0) == hueso and an.track_get_key_count(ti) > 0:
			return an.track_get_key_value(ti, 0)
	return null

## Pone una cara: «Face_X» o «Face_A:Face_B:peso». Va después de la animación del cuerpo.
func _cara(spec: String) -> void:
	if spec == "":
		return
	var p := spec.split(":")
	var a := p[0]
	var b := p[1] if p.size() > 2 else p[0]
	var w := float(p[2]) if p.size() > 2 else 0.0
	for h in HUESOS_CARA:
		var bi := sk.find_bone(h)
		if bi < 0:
			continue
		var ra = _valor(a, h, Animation.TYPE_ROTATION_3D)
		var rb = _valor(b, h, Animation.TYPE_ROTATION_3D)
		if ra != null and rb != null:
			sk.set_bone_pose_rotation(bi, (ra as Quaternion).slerp(rb, w))
		var pa = _valor(a, h, Animation.TYPE_POSITION_3D)
		var pb = _valor(b, h, Animation.TYPE_POSITION_3D)
		if pa != null and pb != null:
			sk.set_bone_pose_position(bi, (pa as Vector3).lerp(pb, w))

func _camara(giro: float, elev: float, dist: float, objetivo: Vector3) -> void:
	var yaw := deg_to_rad(giro)
	var pitch := deg_to_rad(elev)
	# giro 0 = cámara delante del personaje (que mira a +Z); 90 = a su izquierda (+X)
	var off := Vector3(sin(yaw) * cos(pitch), sin(pitch), cos(yaw) * cos(pitch)) * dist
	cam.look_at_from_position(objetivo + off, objetivo, Vector3.UP)
	world.get_node("Ground").visible = elev >= 0.0

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var libres: Array = []
	var sueltas: Array = []
	for a in args:
		var kv := a.split("=", true, 1)
		if kv.size() < 2:
			libres.append(a)
			continue
		match kv[0]:
			"modo": modo = kv[1]
			"fps": fps = float(kv[1])
			"giro": giro_forzado = float(kv[1])
			"rotulo": rotulo = kv[1] != "0"
			"estado": estado_anim = kv[1]
			"anims": solo = kv[1].split(",")
			"efectos": efectos = kv[1] != "0"
			"toma":
				var q := kv[1].split(",")
				sueltas.append([q[0], float(q[1]), float(q[2]), float(q[3]), float(q[4]),
						Vector3(float(q[5]), float(q[6]), float(q[7])), q[8], q[9], q[10]])
	if libres.size() > 0:
		out_dir = libres[0]
	if not out_dir.ends_with("/"):
		out_dir += "/"
	glb = libres[1] if libres.size() > 1 else (get_script() as Script).resource_path.get_base_dir().path_join("../propuestas/nojoch/nojoch.glb")
	if sueltas.size() > 0:
		TOMAS = sueltas
	DirAccess.make_dir_recursive_absolute(out_dir)
	world = Node3D.new()
	get_root().add_child(world)
	# la luz del juego (game/scripts/client/world_builder.gd): ambiente frío, sol cálido,
	# curva fílmica, resplandor y el ajuste de saturación y contraste
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("#b9d3e6")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.62, 0.76, 0.8)
	env.ambient_light_energy = 0.95
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 0.98
	env.tonemap_white = 4.5
	env.glow_enabled = efectos
	env.glow_intensity = 0.45
	env.glow_bloom = 0.08
	env.glow_hdr_threshold = 1.0
	env.adjustment_enabled = efectos
	env.adjustment_saturation = 1.18
	env.adjustment_contrast = 1.06
	var we := WorldEnvironment.new()
	we.environment = env
	world.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-33, 128, 0)
	sun.light_color = Color(1.0, 0.88, 0.68)
	sun.light_energy = 1.2
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 48.0
	sun.shadow_opacity = 0.62
	sun.shadow_blur = 1.6
	sun.shadow_bias = 0.06
	sun.name = "Sun"
	world.add_child(sun)
	# suelo de losas de piedra de 2 m, en dos tonos y con juntas, para ver si los pies patinan
	var ground := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(400, 400)
	ground.mesh = pm
	var sh := Shader.new()
	sh.code = """shader_type spatial;
varying vec3 wp;
void vertex() { wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }
void fragment() {
	vec2 g = wp.xz / 2.0;
	vec2 c = floor(g);
	float k = mod(c.x + c.y, 2.0);
	float h = fract(sin(dot(c, vec2(12.9898, 78.233))) * 43758.5453);
	vec2 f = abs(fract(g) - 0.5);
	float junta = step(0.47, max(f.x, f.y));
	vec3 a = mix(vec3(0.33, 0.31, 0.27), vec3(0.38, 0.36, 0.31), k) * (0.9 + 0.2 * h);
	ALBEDO = mix(a, vec3(0.17, 0.16, 0.14), junta);
	ROUGHNESS = 1.0;
}"""
	var gm := ShaderMaterial.new()
	gm.shader = sh
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
	ap = _find(model, "AnimationPlayer")
	sk = _find(model, "Skeleton3D")
	mi = _find(model, "MeshInstance3D")
	if modo == "anim":
		var cl := CanvasLayer.new()
		get_root().add_child(cl)
		label = Label.new()
		label.position = Vector2(14, 8)
		label.add_theme_font_size_override("font_size", 22)
		label.add_theme_color_override("font_color", Color(1, 1, 1))
		label.add_theme_color_override("font_outline_color", Color(0, 0, 0))
		label.add_theme_constant_override("outline_size", 6)
		label.visible = rotulo
		cl.add_child(label)
		for a in ORDEN:
			if ap.has_animation(a) and (solo.is_empty() or a in solo):
				lista.append(a)
		_cuadro_anim()
	else:
		_setup_shot()

func _setup_shot() -> void:
	var s: Array = TOMAS[idx]
	ap.play(s[0])
	ap.seek(s[1], true)
	ap.pause()
	_estado(s[6])
	cara_actual = s[7] if s[7] != "" else (ESTADOS[s[6]]["cara"] if ESTADOS.has(s[6]) else "")
	_cara(cara_actual)
	_camara(s[2], s[3], s[4], s[5])
	wait = 0

func _cuadro_anim() -> void:
	var a: String = lista[idx]
	var an := ap.get_animation(a)
	var c: Array = CAMARAS[a]
	var n := int(round(an.length * fps * int(c[5])))
	var t := cuadro / fps
	ap.play(a)
	ap.seek(fmod(t, an.length) if int(c[5]) > 1 else minf(an.length, t), true)
	ap.pause()
	_cara(cara_actual)
	var avance := Vector3(0, 0, float(c[4]) * t)
	model.position = avance
	_camara(c[0] if is_nan(giro_forzado) else giro_forzado, c[1], c[2], (c[3] as Vector3) + avance)
	if label:
		label.text = "%s   %.2f s%s" % [a, t, ("   ·   %.1f m/s" % c[4]) if c[4] > 0.0 else ""]
	wait = 0
	if cuadro == 0:
		var e: String = estado_anim if estado_anim != "" else c[6]
		_estado(e)
		cara_actual = ESTADOS[e]["cara"] if ESTADOS.has(e) else ""
		_cara(cara_actual)
		DirAccess.make_dir_recursive_absolute(out_dir + a)
		print("anim ", a, ": ", n, " cuadros a ", fps, " c/s")

func _process(_delta: float) -> bool:
	wait += 1
	if modo == "anim":
		_cara(cara_actual)
		if wait < 3:
			return false
		var a: String = lista[idx]
		get_root().get_texture().get_image().save_png("%s%s/f%04d.png" % [out_dir, a, cuadro + 1])
		cuadro += 1
		if cuadro >= int(round(ap.get_animation(a).length * fps * int(CAMARAS[a][5]))):
			cuadro = 0
			idx += 1
			if idx >= lista.size():
				return true
		_cuadro_anim()
		return false
	_cara(cara_actual)
	if wait < 4:
		return false
	var img := get_root().get_texture().get_image()
	img.save_png(out_dir + TOMAS[idx][8] + ".png")
	print("captura ", out_dir + TOMAS[idx][8] + ".png")
	idx += 1
	if idx >= TOMAS.size():
		return true
	_setup_shot()
	return false
