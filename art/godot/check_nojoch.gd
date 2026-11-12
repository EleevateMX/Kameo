extends SceneTree
## Comprobación sin ventana de la propuesta de Nojoch Tuunich: carga el .glb directamente
## (no hace falta importarlo en el proyecto del juego) y lista mallas, materiales, huesos
## y animaciones tal como los ve Godot.
## Uso (desde la raíz del repo):
##   .tools/godot --headless --script "$PWD/art/godot/check_nojoch.gd" -- [ruta.glb]
## Sin ruta, comprueba art/propuestas/nojoch/nojoch.glb.

const ESPERADOS := ["Body", "Eye", "Glyph1", "Glyph2", "Glyph3", "Glyph4", "Heart", "Silence"]
const ANIMACIONES := ["Sleep", "Awaken", "Idle", "Walk", "Slam", "Sweep", "Summon", "Charge", "Stunned", "Kneel", "Remember"]

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

func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var path: String = args[0] if args.size() > 0 else (get_script() as Script).resource_path.get_base_dir().path_join("../propuestas/nojoch/nojoch.glb")
	if not FileAccess.file_exists(path):
		print("no existe ", path)
		quit(1)
		return
	print("===== ", path, " (", FileAccess.get_file_as_bytes(path).size(), " bytes) =====")
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
	var fallos := 0
	var total_tris := 0
	print("-- mallas --")
	for e in nodes:
		var n: Node = e[0]
		if n is MeshInstance3D:
			var mi := n as MeshInstance3D
			var lo := Vector3(INF, INF, INF)
			var hi := -lo
			for i in mi.mesh.get_surface_count():
				var arr: Array = mi.mesh.surface_get_arrays(i)
				var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
				var tris := (arr[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3
				total_tris += tris
				for v in verts:
					lo = lo.min(v)
					hi = hi.max(v)
				var m: Material = mi.mesh.surface_get_material(i)
				vistos[m.resource_name if m else ""] = true
				print("  ", mi.name, " superficie ", i, ": ", _mat(m), "  tris=", tris, " verts=", verts.size(),
						" color=", arr[Mesh.ARRAY_COLOR] != null, " huesos=", arr[Mesh.ARRAY_BONES] != null)
			print("  ", mi.name, " skin=", mi.skin != null, " caja (reposo): de ", lo.snapped(Vector3(0.01, 0.01, 0.01)), " a ", hi.snapped(Vector3(0.01, 0.01, 0.01)))
		if n is ImporterMeshInstance3D:
			var im := (n as ImporterMeshInstance3D).mesh
			for i in im.get_surface_count():
				var arr2: Array = im.get_surface_arrays(i)
				var tris2 := (arr2[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3
				total_tris += tris2
				var m2: Material = im.get_surface_material(i)
				vistos[m2.resource_name if m2 else ""] = true
				print("  ", n.name, " superficie ", i, ": ", _mat(m2), "  tris=", tris2, " verts=", (arr2[Mesh.ARRAY_VERTEX] as PackedVector3Array).size(),
						" color=", arr2[Mesh.ARRAY_COLOR] != null, " huesos=", arr2[Mesh.ARRAY_BONES] != null)
		if n is Skeleton3D:
			var sk := n as Skeleton3D
			var bn := []
			for i in sk.get_bone_count():
				bn.append(sk.get_bone_name(i))
			print("-- esqueleto ", sk.name, ": ", sk.get_bone_count(), " huesos --")
			print("  ", bn)
			for bname in ["Head", "HeartBone", "Hand_L", "Hand_R", "Foot_L"]:
				var bi := sk.find_bone(bname)
				if bi >= 0:
					print("  hueso ", bname, " en ", sk.get_bone_global_rest(bi).origin.snapped(Vector3(0.001, 0.001, 0.001)))
		if n is AnimationPlayer:
			var ap := n as AnimationPlayer
			print("-- animaciones (", ap.get_animation_list().size(), ") --")
			for a in ap.get_animation_list():
				var an: Animation = ap.get_animation(a)
				var kinds := {}
				for ti in an.get_track_count():
					var k: int = an.track_get_type(ti)
					kinds[k] = kinds.get(k, 0) + 1
				print("  ", a, " len=", snapped(an.length, 0.001), " pistas=", an.get_track_count(), " (pos/rot/escala=",
						kinds.get(Animation.TYPE_POSITION_3D, 0), "/", kinds.get(Animation.TYPE_ROTATION_3D, 0), "/", kinds.get(Animation.TYPE_SCALE_3D, 0), ")")
			for a in ANIMACIONES:
				if not ap.has_animation(a):
					print("  FALTA la animación ", a)
					fallos += 1
	print("-- total: ", total_tris, " triángulos --")
	for m in ESPERADOS:
		if not vistos.has(m):
			print("FALTA el material ", m)
			fallos += 1
	print("RESULTADO: ", "correcto" if fallos == 0 else str(fallos) + " fallos")
	root.free()
	quit(0 if fallos == 0 else 1)
