extends RefCounted
## El arco de la salida hacia Motul, en la plaza de Mérida. Es una pieza APARTE del escenario de
## la plaza (plaza_builder.gd no sabe de ella): se construye desde aquí y se cuelga del mismo nodo,
## así que se puede mover, cambiar o quitar sin tocar la plaza.
##
## Dónde: lado este de la plaza, al norte del portal del Claro —Motul queda al este-noreste de
## Mérida—, en zone_def.GATE_MOTUL, entre las jambas zone_def.MOTUL_JAMBS (lo único que choca).
## Qué se ve: un arco blanco con remate ocre, faroles cálidos (el jade queda para el portal de las
## misiones), el rótulo «A MOTUL» y, en el vano, el camino blanco perdiéndose en el monte al
## atardecer: una vista pintada, porque detrás está el pretil de la plaza.
## Cuesta tres llamadas de dibujo y un rótulo.

const Zone := preload("res://scripts/shared/zone_def.gd")
const SceneBatch := preload("res://scripts/client/scene_batch.gd")
const Kit := preload("res://scripts/client/ui/ui_kit.gd")

const WHITE := Color(0.82, 0.8, 0.75)
const WHITE_SHADE := Color(0.6, 0.58, 0.58)
const OCHRE := Color(0.84, 0.6, 0.24)
const WARM := Color(1.0, 0.78, 0.42)
const GOLD := Color(1.0, 0.8, 0.35)
const SASCAB := Color(0.87, 0.84, 0.74)
const WOOD_DARK := Color(0.3, 0.2, 0.14)
const NONE := Color(0, 0, 0, 0)


func build(parent: Node3D) -> Node3D:
	var root := Node3D.new()
	root.name = "ArcoMotul"
	parent.add_child(root)
	var sb := SceneBatch.new()
	var g := Zone.GATE_MOTUL
	var x := float(Zone.MOTUL_JAMBS[0][0])
	var z0 := float(Zone.MOTUL_JAMBS[0][1])
	var z1 := float(Zone.MOTUL_JAMBS[1][1])
	var zc := (z0 + z1) * 0.5
	var span := absf(z1 - z0)
	# Jambas, con su zócalo ocre y un farol cada una
	for j in Zone.MOTUL_JAMBS:
		var p := Vector3(j[0], 0.0, j[1])
		sb.box("obra", Vector3(1.5, 0.4, 1.5), OCHRE.darkened(0.12), p + Vector3(0, 0.2, 0))
		sb.cyl("obra", float(j[2]), 4.5, WHITE, p + Vector3(0, 0.3, 0), 8, float(j[2]) - 0.08, WHITE_SHADE)
		sb.box("obra", Vector3(1.4, 0.28, 1.4), OCHRE, p + Vector3(0, 4.9, 0))
		sb.box("obra", Vector3(0.05, 0.5, 0.05), WOOD_DARK, p + Vector3(-0.75, 3.35, 0))
		sb.ball("brillo", 0.2, WARM, p + Vector3(-0.75, 3.0, 0), 1.2, NONE, 6)
		sb.pool("luz", p + Vector3(-1.6, 0, 0), 4.0, WARM, 0.24)
	# Dintel curvo (un arco de dovelas) y frontón con el rótulo
	var prev := Vector3(x, 5.0, z0)
	for k in range(1, 9):
		var t := float(k) / 8.0
		var p := Vector3(x, 5.0 + sin(t * PI) * 1.0, lerpf(z0, z1, t))
		sb.beam("obra", prev, p, 0.7, WHITE, 1.2)
		prev = p
	sb.box("obra", Vector3(1.0, 1.0, span * 0.62), WHITE, Vector3(x, 6.7, zc), 0.0, WHITE_SHADE)
	sb.box("obra", Vector3(1.2, 0.22, span * 0.7), OCHRE, Vector3(x, 7.3, zc))
	sb.ball("obra", 0.36, WHITE, Vector3(x, 7.7, zc), 1.0, WHITE_SHADE, 6)
	# El vano: una vista pintada del camino al atardecer (sin sombrear)
	var back := x + 0.42
	sb.quad("brillo", Vector3(back, 0.0, z0), Vector3(back, 0.0, z1), Vector3(back, 2.2, z1), Vector3(back, 2.2, z0), Color(0.22, 0.3, 0.18), Color(0.3, 0.36, 0.2))
	sb.quad("brillo", Vector3(back, 2.2, z0), Vector3(back, 2.2, z1), Vector3(back, 6.0, z1), Vector3(back, 6.0, z0), Color(1.0, 0.68, 0.4), Color(0.32, 0.3, 0.52))
	# el camino blanco, que se estrecha hacia el horizonte
	sb.quad("brillo", Vector3(back - 0.03, 0.0, zc - 1.7), Vector3(back - 0.03, 0.0, zc + 1.7), Vector3(back - 0.03, 2.2, zc + 0.22), Vector3(back - 0.03, 2.2, zc - 0.22), SASCAB, SASCAB.darkened(0.12))
	# monte a los lados y un sol bajo
	for t in [[-1.9, 1.5, 1.3], [-1.2, 1.9, 0.8], [1.6, 1.7, 1.2], [1.0, 2.0, 0.7], [-0.55, 2.15, 0.4], [0.5, 2.15, 0.36]]:
		sb.emit("brillo", "ball|6", Basis.IDENTITY, Vector3(0.05, float(t[2]) * 1.5, float(t[2]) * 1.7), Vector3(back - 0.05, t[1], zc + float(t[0])), Color(0.16, 0.26, 0.16), Color(0.1, 0.16, 0.12))
	sb.emit("brillo", "ball|8", Basis.IDENTITY, Vector3(0.04, 0.7, 0.7), Vector3(back - 0.02, 2.75, zc + 0.5), Color(1.0, 0.92, 0.66), NONE)
	# Suelo: el camino blanco empieza ya dentro de la plaza
	for k in 4:
		var tx := g.x - 5.0 + 1.6 * float(k)
		sb.tile("suelo", tx, zc - 1.5, tx + 1.5, zc + 1.5, 0.022, SASCAB.darkened(0.05 * float(3 - k)))
	sb.tile("suelo", g.x + 1.4, zc - 1.7, back, zc + 1.7, 0.022, SASCAB)
	sb.ring("brillo", Vector3(g.x - 0.6, 0.03, zc), 0.95, 1.06, GOLD.darkened(0.1), 24)
	sb.pool("luz", Vector3(g.x - 1.0, 0, zc), 5.5, WARM, 0.2)
	# Poste indicador con su flecha
	var post := Vector3(g.x - 3.4, 0.0, z1 + 1.3)
	sb.box("obra", Vector3(0.14, 2.6, 0.14), WOOD_DARK, post + Vector3(0, 1.3, 0))
	sb.box("obra", Vector3(1.5, 0.42, 0.08), Color(0.56, 0.4, 0.24), post + Vector3(0.35, 2.2, 0), 0.0, WOOD_DARK)
	sb.commit("suelo", sb.solid(), root)
	sb.commit("obra", sb.solid(), root, true)
	sb.commit("brillo", sb.glow(), root)
	sb.commit("luz", sb.additive(), root)
	_label(root, "A MOTUL", Vector3(x - 0.52, 6.68, zc), -PI * 0.5, 0.0072, Color(0.36, 0.24, 0.16), 60.0, false)
	_label(root, "Motul →", post + Vector3(0.35, 2.2, 0.06), 0.0, 0.0034, Color(1.0, 0.92, 0.7), 26.0, true)
	return root


func _label(root: Node3D, text: String, pos: Vector3, yaw: float, pixel: float, color: Color, range_end: float, outline: bool) -> void:
	var label := Label3D.new()
	label.text = text
	label.font = Kit.title_font()
	label.font_size = 64
	label.pixel_size = pixel
	label.outline_size = 14 if outline else 0
	label.modulate = color
	label.outline_modulate = Color(0.04, 0.06, 0.06, 0.95)
	label.position = pos
	label.rotation.y = yaw
	label.visibility_range_end = range_end
	root.add_child(label)
