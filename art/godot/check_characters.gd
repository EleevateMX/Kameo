extends SceneTree
## Comprobación sin ventana de los personajes importados.
## Uso (desde la raíz del repo, después de `--import`):
##   .tools/godot --headless --path game --script "$PWD/art/godot/check_characters.gd"
## Imprime el árbol de nodos, materiales por superficie, AABB, huesos y animaciones.
## Para el alux comprueba además el contrato del personalizador (nodos por prefijo,
## materiales que el juego tiñe, esqueleto y animaciones): acaba con «CONTRATO ALUX: OK»
## o con la lista de lo que falla, y entonces el proceso sale con código 1.

## ── Contrato de alux.glb (game/scripts/shared/look_def.gd y game/scripts/client/avatar.gd) ──
## prefijo que busca el juego -> materiales que debe llevar esa malla
const ALUX_NODES := {
	"Alux": ["Body", "Skin", "Tunic", "Trim", "Eye", "Jade"],
	"Hair": ["Headwear"],
	"Hat_Palma": ["Headwear", "Jade"], "Hat_Penacho": ["Headwear", "Jade"], "Hat_Flor": ["Headwear"],
	"Hat_Plumas": ["Headwear"], "Hat_Panuelo": ["Trim"], "Hat_Hojas": ["Headwear"],
	"Outfit_Capa": ["Trim", "Body"], "Outfit_Faja": ["Trim", "Body"], "Outfit_Bordado": ["Trim", "Body"],
	"Acc_Morral": ["Trim", "Body"], "Acc_Sonaja": ["Body"], "Acc_Caracol": ["Body"], "Acc_Farol": ["Body", "Firefly"],
	"Amu_Jade": ["Body", "Jade"], "Amu_Concha": ["Body"], "Amu_Obsidiana": ["Body", "Obsidian"], "Amu_Semillas": ["Body"],
}
## piezas del personalizador: presupuesto de 60 a 400 triángulos cada una
const ALUX_PIECES := ["Hat_Plumas", "Hat_Panuelo", "Hat_Hojas", "Outfit_Capa", "Outfit_Faja", "Outfit_Bordado",
	"Acc_Morral", "Acc_Sonaja", "Acc_Caracol", "Acc_Farol", "Amu_Jade", "Amu_Concha", "Amu_Obsidiana", "Amu_Semillas"]
## materiales que el juego tiñe (solo cambia albedo_color) y su color de fábrica
const ALUX_TINTS := {"Tunic": "2ec4a6", "Trim": "f8efdc", "Skin": "e19764"}
const ALUX_EMISSIVE := ["Eye", "Jade", "Firefly"]
const ALUX_BONES := ["Root", "Hips", "Spine", "Chest", "Head", "Mouth", "Amulet", "SashTail", "Bag",
	"Ear_L", "EarTip_L", "Lid_L", "LidLow_L", "Brow_L", "UpperArm_L", "Forearm_L", "Hand_L", "Fingers_L",
	"Thigh_L", "Shin_L", "Foot_L",
	"Ear_R", "EarTip_R", "Lid_R", "LidLow_R", "Brow_R", "UpperArm_R", "Forearm_R", "Hand_R", "Fingers_R",
	"Thigh_R", "Shin_R", "Foot_R"]
## animación -> duración en segundos (todas se importan sin bucle; el juego lo pone)
const ALUX_ANIMS := {"Idle": 3.0, "Run": 0.333, "Jump": 0.4, "Fall": 0.6, "Land": 0.267, "Swim": 1.2,
	"Cast": 0.4, "Dodge": 0.3, "Interact": 0.6, "Hit": 0.3, "Death": 0.9, "Transform": 0.5}

var failed := false

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

## Contrato del alux con el personalizador. Devuelve la lista de fallos (vacía = bien).
func _check_alux(root: Node) -> Array:
	var bad: Array = []
	var meshes := {}
	for n in root.find_children("*", "MeshInstance3D", true, false):
		meshes[str(n.name)] = n
	# 1) cada prefijo encuentra su malla, y solo la suya, como la busca el juego
	for prefix in ALUX_NODES:
		var found: Array = []
		for n in root.find_children(prefix + "*", "Node3D", true, false):
			found.append(str(n.name))
		if found != [prefix]:
			bad.append("find_children(\"%s*\") da %s y debería dar solo [\"%s\"]" % [prefix, found, prefix])
			continue
		var mi := meshes.get(prefix) as MeshInstance3D
		if mi == null or mi.mesh == null:
			bad.append(prefix + " no es una malla")
			continue
		if mi.skin == null:
			bad.append(prefix + " no va con piel sobre el esqueleto")
		var mats: Array = []
		var tris := 0
		for i in mi.mesh.get_surface_count():
			var m := mi.mesh.surface_get_material(i) as BaseMaterial3D
			tris += mi.mesh.surface_get_array_index_len(i) / 3
			if m == null:
				bad.append("%s: superficie %d sin material" % [prefix, i])
				continue
			var mat_name := str(m.resource_name)
			mats.append(mat_name)
			if not m.vertex_color_use_as_albedo:
				bad.append("%s/%s sin color de vértice" % [prefix, mat_name])
			if m.cull_mode != BaseMaterial3D.CULL_BACK:
				bad.append("%s/%s no es de una sola cara" % [prefix, mat_name])
			if ALUX_TINTS.has(mat_name) and m.albedo_color.to_html(false) != ALUX_TINTS[mat_name]:
				bad.append("%s/%s: albedo #%s en vez de #%s" % [prefix, mat_name, m.albedo_color.to_html(false), ALUX_TINTS[mat_name]])
			if ALUX_EMISSIVE.has(mat_name) != m.emission_enabled:
				bad.append("%s/%s: emisión %s" % [prefix, mat_name, "apagada" if not m.emission_enabled else "inesperada"])
			if (ALUX_TINTS.has(mat_name) or mat_name == "Body" or mat_name == "Headwear") and mat_name != "Tunic":
				# los vértices de estos materiales llevan color o matiz: no pueden ser todos blancos
				var cols: PackedColorArray = mi.mesh.surface_get_arrays(i)[Mesh.ARRAY_COLOR]
				if cols.is_empty():
					bad.append("%s/%s sin COLOR_0" % [prefix, mat_name])
		for want in ALUX_NODES[prefix]:
			if not mats.has(want):
				bad.append("%s: falta el material %s (tiene %s)" % [prefix, want, mats])
		for have in mats:
			if not (ALUX_NODES[prefix] as Array).has(have):
				bad.append("%s: material inesperado %s" % [prefix, have])
		if ALUX_PIECES.has(prefix) and (tris < 60 or tris > 400):
			bad.append("%s: %d triángulos (presupuesto: 60 a 400)" % [prefix, tris])
	for mesh_name in meshes:
		if not ALUX_NODES.has(mesh_name):
			bad.append("malla que el juego no conoce: " + mesh_name)
	# 2) la piel: matiz como factor (la piel media en gris 0.75, nunca blanco ni color)
	var body := meshes.get("Alux") as MeshInstance3D
	if body != null and body.mesh != null:
		for i in body.mesh.get_surface_count():
			var m := body.mesh.surface_get_material(i)
			if m != null and str(m.resource_name) == "Skin":
				var cols: PackedColorArray = body.mesh.surface_get_arrays(i)[Mesh.ARRAY_COLOR]
				var sum := Vector3.ZERO
				var top := 0.0
				for c in cols:
					sum += Vector3(c.r, c.g, c.b)
					top = maxf(top, maxf(c.r, maxf(c.g, c.b)))
				var mean := sum / maxf(1.0, float(cols.size()))
				print("  piel: matiz medio ", mean.snapped(Vector3(0.001, 0.001, 0.001)), " máximo ", snapped(top, 0.001))
				if absf(mean.x - mean.z) > 0.08 or mean.y < 0.5 or mean.y > 0.8:
					bad.append("Skin: el matiz medio %s no es un gris en torno a 0.7" % [mean])
	# 3) esqueleto y animaciones: los de siempre
	var sk: Skeleton3D = null
	for n in root.find_children("*", "Skeleton3D", true, false):
		sk = n
	if sk == null:
		bad.append("sin Skeleton3D")
	else:
		var bones: Array = []
		for i in sk.get_bone_count():
			bones.append(sk.get_bone_name(i))
		for b in ALUX_BONES:
			if not bones.has(b):
				bad.append("falta el hueso " + b)
		for b in bones:
			if not ALUX_BONES.has(b):
				bad.append("hueso nuevo: " + str(b))
	var ap: AnimationPlayer = null
	for n in root.find_children("*", "AnimationPlayer", true, false):
		ap = n
	if ap == null:
		bad.append("sin AnimationPlayer")
	else:
		var tracks := -1
		for a in ALUX_ANIMS:
			if not ap.has_animation(a):
				bad.append("falta la animación " + a)
				continue
			var an: Animation = ap.get_animation(a)
			if absf(an.length - float(ALUX_ANIMS[a])) > 0.002:
				bad.append("%s dura %s s en vez de %s" % [a, snapped(an.length, 0.001), ALUX_ANIMS[a]])
			if an.loop_mode != Animation.LOOP_NONE:
				bad.append(a + " se importa con bucle")
			if tracks >= 0 and an.get_track_count() != tracks:
				bad.append("%s tiene %d pistas y las demás %d" % [a, an.get_track_count(), tracks])
			tracks = an.get_track_count()
		for a in ap.get_animation_list():
			if not ALUX_ANIMS.has(a):
				bad.append("animación nueva: " + str(a))
	return bad

func _init() -> void:
	for p in ["res://assets/characters/alux.glb", "res://assets/characters/balam.glb",
			"res://assets/characters/yaxche.glb"]:
		if ResourceLoader.exists(p):
			_check(p)
		else:
			print("no existe ", p)
	var alux: PackedScene = load("res://assets/characters/alux.glb")
	if alux != null:
		print("\n===== contrato del personalizador (alux.glb) =====")
		var root: Node = alux.instantiate()
		var bad := _check_alux(root)
		root.queue_free()
		if bad.is_empty():
			print("CONTRATO ALUX: OK (", ALUX_NODES.size(), " mallas, ", ALUX_BONES.size(), " huesos, ", ALUX_ANIMS.size(), " animaciones)")
		else:
			failed = true
			print("CONTRATO ALUX: ", bad.size(), " FALLOS")
			for b in bad:
				print("  - ", b)
	quit(1 if failed else 0)
