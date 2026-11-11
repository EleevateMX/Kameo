extends RefCounted
## Definición del "Claro de los Aluxes", compartida por cliente y servidor.
## El servidor la usa para validar el movimiento y el cliente para predecirlo
## y para construir el escenario 3D, así ambos ven exactamente el mismo mundo.

const RADIUS := 46.0
const WATER_LEVEL := -0.9
const CENOTE := Vector2(-21.0, 15.0)
const CENOTE_R := 10.0
const PYRAMID := Vector2(0.0, -27.0)
const SANCTUARY := Vector2(28.0, 0.0)
const LEDGE := Vector2(12.0, 21.0)
const PLATE_R := 1.4
const GATE_ID := "gate"

const SPAWNS: Array[Vector2] = [
	Vector2(2.6, 2.6), Vector2(-2.6, 2.6), Vector2(2.6, -2.6), Vector2(-2.6, -2.6),
]

## Altares de presión del acertijo cooperativo (x, z)
const PLATES: Array[Vector2] = [
	Vector2(0.0, -15.5),   # frente a la pirámide
	Vector2(-11.0, 7.0),   # orilla del cenote
	Vector2(8.0, 16.0),    # junto al mirador de Balam
	Vector2(17.5, -5.0),   # frente al santuario
]

## Zonas aplanadas (x, z, radio)
const FLAT_ZONES: Array[Vector3] = [
	Vector3(0.0, 0.0, 11.0),
	Vector3(0.0, -27.0, 13.0),
	Vector3(28.0, 0.0, 11.0),
]

static var _boxes: Array = []
static var _cyls: Array = []
static var _built := false


static func terrain_h(x: float, z: float) -> float:
	var h := 0.7 * sin(x * 0.09) * cos(z * 0.08) + 0.35 * sin((x + z) * 0.17) + 0.25 * cos((x - z) * 0.13)
	# zonas planas para plaza, pirámide y santuario
	var w := 0.0
	for fz in FLAT_ZONES:
		var d := Vector2(x - fz.x, z - fz.y).length()
		w = maxf(w, 1.0 - smoothstep(fz.z, fz.z + 6.0, d))
	h = lerpf(h, 0.0, w)
	# cenote
	var dc := Vector2(x - CENOTE.x, z - CENOTE.y).length() / CENOTE_R
	if dc < 1.3:
		var k := 1.0 - smoothstep(0.15, 1.3, dc)
		h = lerpf(h, -3.2, k)
	# colinas que cierran el claro
	var r := Vector2(x, z).length()
	if r > 38.0:
		h += (r - 38.0) * (r - 38.0) * 0.09
	return h


static func _ensure() -> void:
	if _built:
		return
	_built = true
	_boxes = []
	_cyls = []

	# Pirámide escalonada: 4 niveles de 1 m
	var sizes := [16.0, 12.0, 8.0, 4.0]
	for i in sizes.size():
		_add_box("pyr%d" % i, PYRAMID.x, PYRAMID.y, sizes[i], sizes[i], float(i + 1), "pyramid")

	# Santuario: muros + puerta sellada
	var sx := SANCTUARY.x
	var sz := SANCTUARY.y
	_add_box("san_n", sx, sz - 6.0, 13.0, 1.0, 3.2, "wall")
	_add_box("san_s", sx, sz + 6.0, 13.0, 1.0, 3.2, "wall")
	_add_box("san_e", sx + 6.0, sz, 1.0, 13.0, 3.2, "wall")
	_add_box("san_w1", sx - 6.0, sz - 4.25, 1.0, 4.5, 3.2, "wall")
	_add_box("san_w2", sx - 6.0, sz + 4.25, 1.0, 4.5, 3.2, "wall")
	_add_box(GATE_ID, sx - 6.0, sz, 0.7, 4.0, 3.2, "gate")
	_add_box("altar", sx + 1.5, sz, 2.2, 2.2, 0.8, "altar")
	# Sello de energía: mientras la puerta está cerrada cubre todo el interior, de modo
	# que tampoco se puede entrar saltando los muros desde la ladera.
	# Abarca también los muros para que no queden rincones entre sello y pared.
	_add_box("seal", sx, sz, 13.0, 13.0, 40.0, "seal")

	# Mirador de Balam: sólo se alcanza con el salto del jaguar
	_add_box("ledge", LEDGE.x, LEDGE.y, 4.5, 4.5, 2.0, "ledge")
	# (pegado al mirador: entre dos sólidos no debe quedar un hueco más estrecho que el cuerpo)
	_add_box("ledge_step", LEDGE.x - 3.25, LEDGE.y + 0.5, 2.0, 2.0, 0.45, "ruin")

	# Ruinas sueltas alrededor de la plaza
	_add_box("ruin1", -7.0, -9.5, 2.4, 1.4, 0.45, "ruin")
	_add_box("ruin2", -9.2, -9.0, 1.6, 1.6, 0.95, "ruin")
	_add_box("ruin3", 9.5, 8.5, 2.0, 2.0, 0.9, "ruin")
	_add_box("ruin4", 7.0, -10.5, 3.0, 1.2, 0.45, "ruin")
	_add_box("ruin5", -13.5, -2.0, 1.5, 3.2, 0.9, "ruin")

	# Columnas de la plaza
	for a in [PI * 0.25, PI * 0.75, PI * 1.25, PI * 1.75]:
		_cyls.append({"x": cos(a) * 8.5, "z": sin(a) * 8.5, "r": 0.55, "h": 3.4, "kind": "pillar"})

	# Brasero de la plaza (sólido; además cura y es punto de reaparición)
	_cyls.append({"x": 0.0, "z": 0.0, "r": 0.95, "h": 1.0, "kind": "brazier"})

	# Árboles (generador propio para que sea idéntico en todas las plataformas)
	var seed_v := 20261109
	var tries := 0
	while _cyls.size() < 75 and tries < 900:
		tries += 1
		seed_v = (seed_v * 1103515245 + 12345) % 2147483648
		var ang := float(seed_v) / 2147483648.0 * TAU
		seed_v = (seed_v * 1103515245 + 12345) % 2147483648
		var rad := 14.0 + float(seed_v) / 2147483648.0 * 31.0
		seed_v = (seed_v * 1103515245 + 12345) % 2147483648
		var scale := 0.8 + float(seed_v) / 2147483648.0 * 0.7
		var tx := cos(ang) * rad
		var tz := sin(ang) * rad
		if _tree_blocked(tx, tz):
			continue
		_cyls.append({"x": tx, "z": tz, "r": 0.45 * scale, "h": 5.0 * scale, "kind": "tree", "s": scale})


static func _tree_blocked(x: float, z: float) -> bool:
	if Vector2(x - CENOTE.x, z - CENOTE.y).length() < CENOTE_R + 3.0:
		return true
	if absf(x - PYRAMID.x) < 11.0 and absf(z - PYRAMID.y) < 11.5:
		return true
	if absf(x - SANCTUARY.x) < 9.5 and absf(z - SANCTUARY.y) < 9.5:
		return true
	if absf(x - SANCTUARY.x + 9.0) < 6.0 and absf(z - SANCTUARY.y) < 4.0:
		return true  # camino hacia la puerta
	if Vector2(x - LEDGE.x, z - LEDGE.y).length() < 6.5:
		return true
	for p in PLATES:
		if Vector2(x - p.x, z - p.y).length() < 3.5:
			return true
	for c in _cyls:
		if Vector2(x - c.x, z - c.z).length() < 3.0:
			return true
	return false


static func _add_box(id: String, cx: float, cz: float, sx: float, sz: float, height: float, kind: String) -> void:
	var base := terrain_h(cx, cz)
	_boxes.append({
		"id": id, "kind": kind,
		"x0": cx - sx * 0.5, "x1": cx + sx * 0.5,
		"z0": cz - sz * 0.5, "z1": cz + sz * 0.5,
		"y0": base - 2.5, "top": base + height,
		# "sealed": desaparece cuando el santuario se abre
		"sealed": kind == "gate" or kind == "seal",
	})


static func boxes() -> Array:
	_ensure()
	return _boxes


static func cylinders() -> Array:
	_ensure()
	return _cyls


static func plate_pos(i: int) -> Vector3:
	var p: Vector2 = PLATES[i]
	return Vector3(p.x, terrain_h(p.x, p.y), p.y)


static func spawn_pos(i: int) -> Vector3:
	var p: Vector2 = SPAWNS[i % SPAWNS.size()]
	return Vector3(p.x, terrain_h(p.x, p.y), p.y)
