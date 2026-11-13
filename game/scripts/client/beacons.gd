extends Node3D
## Balizas del objetivo activo: un haz de luz y una flecha que sube y baja sobre cada punto al
## que hay que ir (un glifo, un ancla, una criatura que purificar, el corazón del guardián).
## Sólo es dibujo del cliente: el servidor no sabe nada de esto.

const MAX := 4

var _nodes: Array = []          # [raíz, flecha]
var _beam_mat: StandardMaterial3D
var _arrow_mat: StandardMaterial3D
var _time := 0.0
var _arrow_h := 3.2
var _shown := 0


func _ready() -> void:
	_beam_mat = _mat(0.26)
	_arrow_mat = _mat(0.95)
	var beam := CylinderMesh.new()
	beam.top_radius = 0.1
	beam.bottom_radius = 0.3
	beam.height = 9.0
	beam.radial_segments = 8
	beam.rings = 1
	var cone := CylinderMesh.new()
	cone.top_radius = 0.46
	cone.bottom_radius = 0.0
	cone.height = 0.85
	cone.radial_segments = 4
	cone.rings = 1
	for i in MAX:
		var root := Node3D.new()
		root.visible = false
		add_child(root)
		var b := MeshInstance3D.new()
		b.mesh = beam
		b.material_override = _beam_mat
		b.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		b.position.y = 4.5
		root.add_child(b)
		var a := MeshInstance3D.new()
		a.mesh = cone
		a.material_override = _arrow_mat
		a.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(a)
		_nodes.append([root, a])


static func _mat(alpha: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.albedo_color = Color(1, 1, 1, alpha)
	return m


## Enseña una baliza en cada punto (como mucho MAX; los primeros de la lista). `arrow_h`: a qué
## altura flota la flecha sobre el suelo del punto.
func show_at(points: Array, color: Color, arrow_h := 3.2) -> void:
	_arrow_h = arrow_h
	_beam_mat.albedo_color = Color(color.r, color.g, color.b, 0.26)
	_arrow_mat.albedo_color = Color(color.r, color.g, color.b, 0.95)
	_shown = mini(points.size(), MAX)
	for i in MAX:
		var root: Node3D = _nodes[i][0]
		root.visible = i < _shown
		if i < _shown:
			root.position = points[i]


func count() -> int:
	return _shown


func _process(delta: float) -> void:
	if _shown == 0:
		return
	_time += delta
	for i in _shown:
		var arrow: MeshInstance3D = _nodes[i][1]
		arrow.position.y = _arrow_h + 0.28 * sin(_time * 4.0 + float(i))
		arrow.rotation.y = _time * 1.6
