extends SceneTree
## Comprobación sin ventana de los personajes importados.
## Uso (desde la raíz del repo, después de `--import`):
##   .tools/godot --headless --path game --script "$PWD/art/godot/check_characters.gd"
## Imprime el árbol de nodos, materiales por superficie, AABB, huesos y animaciones.

func _walk(n: Node, depth: int, out: Array) -> void:
	out.append([n, depth])
	for c in n.get_children():
		_walk(c, depth + 1, out)

func _gt(n: Node, root: Node) -> Transform3D:
	var t := Transform3D()
	var c: Node = n
	while c != null and c != root.get_parent():
		if c is Node3D:
			t = (c as Node3D).transform * t
		c = c.get_parent()
	return t

func _check(path: String) -> void:
	print("\n===== ", path, " =====")
	var ps: PackedScene = load(path)
	if ps == null:
		print("NO SE PUDO CARGAR")
		return
	var root: Node = ps.instantiate()
	var nodes: Array = []
	_walk(root, 0, nodes)
	print("-- arbol --")
	for e in nodes:
		var n: Node = e[0]
		print("  ".repeat(e[1]), n.name, " [", n.get_class(), "]")
	var ap: AnimationPlayer = null
	var total := AABB()
	var first := true
	print("-- mallas --")
	for e in nodes:
		var n: Node = e[0]
		if n is AnimationPlayer:
			ap = n
		if n is MeshInstance3D:
			var mi: MeshInstance3D = n
			var names := []
			var tris := 0
			for i in mi.mesh.get_surface_count():
				var m: Material = mi.mesh.surface_get_material(i)
				var extra := ""
				if m is BaseMaterial3D:
					extra = " #" + (m as BaseMaterial3D).albedo_color.to_html(false)
					if (m as BaseMaterial3D).vertex_color_use_as_albedo:
						extra += " vcol"
					if (m as BaseMaterial3D).cull_mode != BaseMaterial3D.CULL_BACK:
						extra += " cull=" + str((m as BaseMaterial3D).cull_mode)
					if (m as BaseMaterial3D).emission_enabled:
						extra += " emis=" + str(snapped((m as BaseMaterial3D).emission_energy_multiplier, 0.01))
				names.append((m.resource_name if m else "<null>") + extra)
				tris += mi.mesh.surface_get_array_index_len(i) / 3
			print("  ", mi.name, " tris=", tris, " skin=", mi.skin != null, " mats=", names)
			var ab: AABB = _gt(mi, root) * mi.get_aabb()
			if first:
				total = ab
				first = false
			else:
				total = total.merge(ab)
		if n is Skeleton3D:
			var sk: Skeleton3D = n
			var bn := []
			for i in sk.get_bone_count():
				bn.append(sk.get_bone_name(i))
			print("  esqueleto ", sk.name, " huesos=", sk.get_bone_count(), " ", bn)
	print("-- AABB total: pos=", total.position, " size=", total.size, " end=", total.end)
	if ap:
		print("-- animaciones (", ap.name, ") --")
		for a in ap.get_animation_list():
			var an: Animation = ap.get_animation(a)
			var kinds := {}
			for ti in an.get_track_count():
				var k: int = an.track_get_type(ti)
				kinds[k] = kinds.get(k, 0) + 1
			print("  ", a, " len=", snapped(an.length, 0.001), " tracks=", an.get_track_count(), " (pos/rot/scale=", kinds.get(Animation.TYPE_POSITION_3D, 0), "/", kinds.get(Animation.TYPE_ROTATION_3D, 0), "/", kinds.get(Animation.TYPE_SCALE_3D, 0), ") loop=", an.loop_mode)
	else:
		print("SIN AnimationPlayer")
	# orientación: posición global de huesos clave en reposo
	for e in nodes:
		if e[0] is Skeleton3D:
			var sk: Skeleton3D = e[0]
			for bname in ["Head", "Mouth", "Ear_L", "Foot_L", "Jaw", "Tail4", "FrontPaw_L", "Hand_R", "StaffBone", "Sprout", "Fireflies"]:
				var i := sk.find_bone(bname)
				if i >= 0:
					print("  hueso ", bname, " en ", (_gt(sk, root) * sk.get_bone_global_rest(i)).origin.snapped(Vector3(0.001, 0.001, 0.001)))
	root.queue_free()

func _init() -> void:
	for p in ["res://assets/characters/alux.glb", "res://assets/characters/balam.glb",
			"res://assets/characters/yaxche.glb"]:
		if ResourceLoader.exists(p):
			_check(p)
		else:
			print("no existe ", p)
	quit()
