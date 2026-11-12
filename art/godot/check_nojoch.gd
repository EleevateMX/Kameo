extends SceneTree
## Comprobación sin ventana del modelo de Nojoch Tuunich: carga el .glb directamente (no
## hace falta importarlo en el proyecto del juego), lista mallas, materiales, huesos y
## animaciones tal como los ve Godot y comprueba el contrato con el juego:
##   · un solo nodo de malla «Nojoch» con piel, un solo esqueleto, ≤ 14 000 triángulos y ≤ 1.7 MB;
##   · los materiales, huesos y animaciones que el juego busca por nombre, con su duración;
##   · «Silence2» y los glifos se exportan apagados (sin emisión);
##   · las animaciones del cuerpo no llevan pista en «Brow_*» ni «Mouth_*», y las tres
##     expresiones («Face_*») solo llevan pistas de huesos de la cara;
##   · una expresión puesta con el AnimationPlayer se conserva al reproducir después una
##     animación del cuerpo.
## Uso (desde la raíz del repo):
##   .tools/godot --headless --script "$PWD/art/godot/check_nojoch.gd" -- [ruta.glb]
## Sin ruta, comprueba art/propuestas/nojoch/nojoch.glb.

const MATERIALES := ["Body", "Eye", "Glyph1", "Glyph2", "Glyph3", "Glyph4", "Heart", "Silence", "Silence2"]
const APAGADOS := ["Glyph1", "Glyph2", "Glyph3", "Glyph4", "Silence2"]
## animación → duración (s)
const CUERPO := {"Sleep": 4.0, "Awaken": 4.0, "Idle": 4.0, "Walk": 1.2, "Slam": 2.6, "Sweep": 2.2, "Summon": 2.6,
		"Charge": 0.8, "Stunned": 2.4, "Kneel": 2.0, "Remember": 3.0}
const CARAS := ["Face_Sad", "Face_Pain", "Face_Serene"]
const HUESOS_CARA := ["Brow_L", "Brow_R", "Mouth_L", "Mouth_R", "Lids", "Jaw"]
const SOLO_CARA := ["Brow_L", "Brow_R", "Mouth_L", "Mouth_R"]
const HUESOS := ["Root", "Hips", "Spine", "Chest", "Head", "Jaw", "Lids", "HeartBone",
		"UpperArm_L", "Forearm_L", "Hand_L", "Fingers_L", "FingerTips_L", "Thumb_L", "Thigh_L", "Shin_L", "Foot_L",
		"UpperArm_R", "Forearm_R", "Hand_R", "Fingers_R", "FingerTips_R", "Thumb_R", "Thigh_R", "Shin_R", "Foot_R",
		"Brow_L", "Mouth_L", "Brow_R", "Mouth_R"]
const MAX_TRIS := 14000
const MAX_BYTES := 1700000

var fallos := 0

func _fallo(msg: String) -> void:
	print("FALLO: ", msg)
	fallos += 1

func _walk(n: Node, depth: int, out: Array) -> void:
	out.append([n, depth])
	for c in n.get_children():
		_walk(c, depth + 1, out)

func _mat(m: Material) -> String:
	if m == null:
		return "<null>"
	var s := m.resource_name
	if m is BaseMaterial3D:
		var b := m as BaseMaterial3D
		s += " #" + b.albedo_color.to_html(false)
		if b.vertex_color_use_as_albedo:
			s += " vcol"
		if b.cull_mode != BaseMaterial3D.CULL_BACK:
			s += " cull=" + str(b.cull_mode)
		if b.emission_enabled:
			s += " emis=#" + b.emission.to_html(false) + "x" + str(snapped(b.emission_energy_multiplier, 0.01))
	return s

func _huesos_de(an: Animation) -> Dictionary:
	var out := {}
	for ti in an.get_track_count():
		out[an.track_get_path(ti).get_subname(0)] = true
	return out

func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var path: String = args[0] if args.size() > 0 else (get_script() as Script).resource_path.get_base_dir().path_join("../propuestas/nojoch/nojoch.glb")
	if not FileAccess.file_exists(path):
		print("no existe ", path)
		quit(1)
		return
	var bytes := FileAccess.get_file_as_bytes(path).size()
	print("===== ", path, " (", bytes, " bytes) =====")
	if bytes > MAX_BYTES:
		_fallo("pesa más de %d bytes" % MAX_BYTES)
	var doc := GLTFDocument.new()
	var st := GLTFState.new()
	var err := doc.append_from_file(path, st)
	if err != OK:
		print("NO SE PUDO CARGAR: error ", err)
		quit(1)
		return
	var root: Node = doc.generate_scene(st)
	var nodes: Array = []
	_walk(root, 0, nodes)
	print("-- arbol --")
	for e in nodes:
		print("  ".repeat(e[1]), e[0].name, " [", e[0].get_class(), "]")
	var vistos := {}
	var total_tris := 0
	var mallas := 0
	var esqueletos := 0
	var sk: Skeleton3D
	var ap: AnimationPlayer
	print("-- mallas --")
	for e in nodes:
		var n: Node = e[0]
		if n is ImporterMeshInstance3D:
			mallas += 1
			if n.name != "Nojoch":
				_fallo("la malla se llama «%s», no «Nojoch»" % n.name)
			var im := (n as ImporterMeshInstance3D).mesh
			var lo := Vector3(INF, INF, INF)
			var hi := -lo
			for i in im.get_surface_count():
				var arr: Array = im.get_surface_arrays(i)
				var tris := (arr[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3
				total_tris += tris
				for v in (arr[Mesh.ARRAY_VERTEX] as PackedVector3Array):
					lo = lo.min(v)
					hi = hi.max(v)
				var m: Material = im.get_surface_material(i)
				var nombre := m.resource_name if m else ""
				vistos[nombre] = m
				print("  ", n.name, " superficie ", i, ": ", _mat(m), "  tris=", tris, " verts=", (arr[Mesh.ARRAY_VERTEX] as PackedVector3Array).size(),
						" color=", arr[Mesh.ARRAY_COLOR] != null, " huesos=", arr[Mesh.ARRAY_BONES] != null)
				if arr[Mesh.ARRAY_COLOR] == null or arr[Mesh.ARRAY_BONES] == null:
					_fallo("la superficie «%s» no lleva color de vértice o piel" % nombre)
			print("  caja (reposo): de ", lo.snapped(Vector3(0.01, 0.01, 0.01)), " a ", hi.snapped(Vector3(0.01, 0.01, 0.01)))
			if absf(hi.y - 5.0) > 0.02 or absf(lo.y) > 0.02:
				_fallo("de pie no mide 5.0 m con los pies en el suelo")
		if n is Skeleton3D:
			esqueletos += 1
			sk = n as Skeleton3D
			var bn := []
			for i in sk.get_bone_count():
				bn.append(sk.get_bone_name(i))
			print("-- esqueleto ", sk.name, ": ", sk.get_bone_count(), " huesos --")
			print("  ", bn)
			for h in HUESOS:
				if sk.find_bone(h) < 0:
					_fallo("falta el hueso " + h)
			for bname in ["Head", "HeartBone", "Hand_L", "Hand_R", "Foot_L", "Brow_L", "Mouth_L"]:
				var bi := sk.find_bone(bname)
				if bi >= 0:
					print("  hueso ", bname, " en ", sk.get_bone_global_rest(bi).origin.snapped(Vector3(0.001, 0.001, 0.001)))
		if n is AnimationPlayer:
			ap = n as AnimationPlayer
	print("-- total: ", total_tris, " triángulos en ", mallas, " malla(s), ", esqueletos, " esqueleto(s) --")
	if mallas != 1 or esqueletos != 1:
		_fallo("debe haber una sola malla y un solo esqueleto")
	if total_tris > MAX_TRIS:
		_fallo("más de %d triángulos" % MAX_TRIS)
	for m in MATERIALES:
		if not vistos.has(m):
			_fallo("falta el material " + m)
	for m in APAGADOS:
		if vistos.has(m) and (vistos[m] as BaseMaterial3D).emission_enabled:
			_fallo("el material %s debería exportarse apagado" % m)
	if ap == null:
		_fallo("no hay AnimationPlayer")
	else:
		print("-- animaciones (", ap.get_animation_list().size(), ") --")
		for a in ap.get_animation_list():
			var an: Animation = ap.get_animation(a)
			var kinds := {}
			for ti in an.get_track_count():
				var k: int = an.track_get_type(ti)
				kinds[k] = kinds.get(k, 0) + 1
			print("  ", a, " len=", snapped(an.length, 0.001), " pistas=", an.get_track_count(), " (pos/rot/escala=",
					kinds.get(Animation.TYPE_POSITION_3D, 0), "/", kinds.get(Animation.TYPE_ROTATION_3D, 0), "/", kinds.get(Animation.TYPE_SCALE_3D, 0), ")")
		for a in CUERPO:
			if not ap.has_animation(a):
				_fallo("falta la animación " + a)
				continue
			var an2: Animation = ap.get_animation(a)
			if absf(an2.length - float(CUERPO[a])) > 0.02:
				_fallo("%s dura %.3f s y no %.1f" % [a, an2.length, CUERPO[a]])
			var hs := _huesos_de(an2)
			for h in SOLO_CARA:
				if hs.has(h):
					_fallo("%s lleva pista en %s (pisaría la expresión)" % [a, h])
			for h in HUESOS:
				if not (h in SOLO_CARA) and h != "Root" and not hs.has(h):
					_fallo("%s no lleva pista en %s" % [a, h])
		for a in CARAS:
			if not ap.has_animation(a):
				_fallo("falta la expresión " + a)
				continue
			var hs2 := _huesos_de(ap.get_animation(a))
			for h in hs2:
				if not (h in HUESOS_CARA):
					_fallo("%s mueve %s, que no es de la cara" % [a, h])
			for h in HUESOS_CARA:
				if not hs2.has(h):
					_fallo("%s no lleva pista en %s" % [a, h])
		# una expresión puesta con el reproductor se conserva bajo una animación del cuerpo
		if sk != null and ap.has_animation("Face_Serene") and ap.has_animation("Idle"):
			get_root().add_child(root)
			var bi2 := sk.find_bone("Brow_L")
			var reposo := sk.get_bone_pose_rotation(bi2)
			ap.play("Face_Serene")
			ap.advance(0.0)
			var serena := sk.get_bone_pose_rotation(bi2)
			ap.play("Idle")
			ap.advance(0.5)
			var despues := sk.get_bone_pose_rotation(bi2)
			print("-- expresión: Brow_L gira ", snapped(rad_to_deg(reposo.angle_to(serena)), 0.1), "° de triste a serena; tras 0.5 s de Idle se desvía ",
					snapped(rad_to_deg(serena.angle_to(despues)), 0.01), "° --")
			if reposo.angle_to(serena) < deg_to_rad(5.0):
				_fallo("Face_Serene no mueve la ceja")
			if serena.angle_to(despues) > deg_to_rad(0.5):
				_fallo("Idle pisa la expresión puesta con Face_Serene")
			get_root().remove_child(root)
	print("RESULTADO: ", "correcto" if fallos == 0 else str(fallos) + " fallos")
	root.free()
	quit(0 if fallos == 0 else 1)
