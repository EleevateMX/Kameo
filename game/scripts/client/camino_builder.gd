extends RefCounted
## Escenario del «Camino a Motul»: un camino blanco entre albarradas y monte bajo que sale de la
## muralla de Mérida y llega al cartel de bienvenida de Motul, con una milpa, un cenote a ras de
## suelo y un henequenal a los lados. Interpretación fantástica: no reproduce ningún lugar real.
## La geometría que importa para moverse está en camino_def.gd; esto sólo la dibuja.
##
## Rendimiento: las mismas reglas que la plaza (scene_batch.gd). Todo lo estático va fundido en
## lotes con el color en los vértices, troceados a lo largo del camino para que la cámara descarte
## lo que no ve:
##   suelo      monte, pasillo pisado, camino blanco, claros
##   obraN      lo grande que arroja sombra: muralla, árboles del camino, cartel, troje, veleta
##   monteN     albarradas, muralla, arbustos y árboles de más allá (sin sombra, con rango de visibilidad)
##   detN       lo pequeño: matas, flores, piedras, maíz, henequén (rango de visibilidad corto)
##   brillo     jade, faroles, ventanas: sin sombrear · luz: charcos de luz sumados
##   cielo      cúpula del atardecer; sigue al jugador
## Aves, mariposas y agua se animan en sombreadores; lo único que se mueve por cuadro es la rueda
## de la veleta y la cúpula del cielo. Ninguna luz salvo el sol.

const Camino := preload("res://scripts/shared/camino_def.gd")
const SceneBatch := preload("res://scripts/client/scene_batch.gd")
const Kit := preload("res://scripts/client/ui/ui_kit.gd")

const SASCAB := Color(0.87, 0.84, 0.74)          # el camino blanco
const DUST := Color(0.66, 0.6, 0.47)
const EARTH := Color(0.47, 0.45, 0.3)            # lo pisado entre albarradas
const MONTE := Color(0.24, 0.32, 0.19)
const STONE := Color(0.7, 0.68, 0.62)
const STONE_DARK := Color(0.44, 0.43, 0.41)
const WHITE := Color(0.84, 0.82, 0.76)
const WHITE_SHADE := Color(0.6, 0.58, 0.58)
const OCHRE := Color(0.84, 0.6, 0.24)
const LEAF := Color(0.2, 0.4, 0.2)
const LEAF_DRY := Color(0.42, 0.5, 0.24)
const LEAF_LIGHT := Color(0.46, 0.62, 0.26)
const BARK := Color(0.42, 0.31, 0.22)
const WOOD := Color(0.52, 0.35, 0.2)
const WOOD_DARK := Color(0.3, 0.2, 0.14)
const AGAVE := Color(0.4, 0.56, 0.5)
const AGAVE_DARK := Color(0.2, 0.34, 0.32)
const CORN := Color(0.62, 0.66, 0.26)
const HUANO := Color(0.66, 0.56, 0.34)           # techo de palma
const FLAME := Color(0.95, 0.32, 0.12)           # flamboyán en flor
const JADE := Color(0.18, 0.95, 0.72)
const GOLD := Color(1.0, 0.8, 0.35)
const WARM := Color(1.0, 0.78, 0.42)
const WATER := Color(0.1, 0.62, 0.66)
const NONE := Color(0, 0, 0, 0)

## Hacia dónde está el sol: bajo, al oeste-suroeste, a la espalda de quien va hacia Motul
const SUN_TO := Vector3(-0.72, 0.42, 0.55)
const CHUNK := 48.0
const CHUNKS := 6

var _root: Node3D
var _sb := SceneBatch.new()
var _rng := RandomNumberGenerator.new()
var _sun: DirectionalLight3D
var _sky: MeshInstance3D
var _details: Array[MeshInstance3D] = []
var _monte: Array[MeshInstance3D] = []
var _wheel: Node3D
var _stats := {}


func build(root: Node3D, quality := 0) -> void:
	_root = root
	_rng.seed = 20261113
	_environment()
	_sky_dome()
	_ground()
	_walls()
	_road_trees()
	_merida_wall()
	_quest_corner()
	_markers()
	_milpa()
	_cenote()
	_henequenal()
	_motul()
	_scatter()
	_commit_all()
	_water()
	_birds()
	_butterflies()
	_labels()
	_stats = _sb.stats
	set_quality(quality)


## Calidad: 0 alta · 1 baja · 2 mínima (sin sombras), como en la plaza.
func set_quality(level: int) -> void:
	_sun.shadow_enabled = level < 2
	_sun.directional_shadow_max_distance = 40.0 if level == 0 else 28.0
	for d in _details:
		d.visibility_range_end = [70.0, 52.0, 40.0][clampi(level, 0, 2)]
	for m in _monte:
		m.visibility_range_end = [150.0, 115.0, 90.0][clampi(level, 0, 2)]


## Por cuadro: el cielo acompaña al jugador y la veleta gira.
func update(delta: float, me: Vector3) -> void:
	if _sky != null:
		_sky.position = Vector3(me.x, 0.0, me.z)
	if _wheel != null:
		_wheel.rotate_object_local(Vector3.FORWARD, delta * 1.3)


func info() -> Dictionary:
	return _stats


# ───────────────────────── Utilidades ─────────────────────────

func _chunk(x: float) -> int:
	return clampi(int((x + 20.0) / CHUNK), 0, CHUNKS - 1)


func _b(kind: String, pos: Vector3) -> String:
	return "%s%d" % [kind, _chunk(pos.x)]


func _v3(p: Vector2, y := 0.0) -> Vector3:
	return Vector3(p.x, y, p.y)


## Distancia con signo al borde de lo transitable (negativa = dentro).
func _sd(p: Vector2) -> float:
	var best := INF
	for i in range(Camino.ROAD.size() - 1):
		var a: Vector2 = Camino.ROAD[i]
		var ab: Vector2 = (Camino.ROAD[i + 1] as Vector2) - a
		best = minf(best, p.distance_to(a + ab * clampf((p - a).dot(ab) / ab.length_squared(), 0.0, 1.0)) - Camino.ROAD_HALF)
	for cl in Camino.CLEARINGS:
		best = minf(best, p.distance_to(Vector2(float(cl[0]), float(cl[1]))) - float(cl[2]))
	return best


## Puntos del borde de lo transitable, cada `step` metros: [posición, hacia fuera].
func _boundary(step: float) -> Array:
	var out := []
	var half := Camino.ROAD_HALF
	for i in range(Camino.ROAD.size() - 1):
		var a: Vector2 = Camino.ROAD[i]
		var ab: Vector2 = (Camino.ROAD[i + 1] as Vector2) - a
		var dir := ab.normalized()
		var nrm := Vector2(-dir.y, dir.x)
		var n := maxi(1, int(ab.length() / step))
		for k in n:
			for side in [-1.0, 1.0]:
				var p: Vector2 = a + ab * (float(k) / float(n)) + nrm * side * half
				if _sd(p) > -0.3:
					out.append([p, nrm * side])
	var circles := []
	for p in Camino.ROAD:
		circles.append([p, half])
	for cl in Camino.CLEARINGS:
		circles.append([Vector2(float(cl[0]), float(cl[1])), float(cl[2])])
	for c in circles:
		var n := maxi(8, int(TAU * float(c[1]) / step))
		for k in n:
			var a := TAU * float(k) / float(n)
			var dir := Vector2(sin(a), cos(a))
			var p: Vector2 = (c[0] as Vector2) + dir * float(c[1])
			if _sd(p) > -0.3:
				out.append([p, dir])
	return out


# ───────────────────────── Ambiente y cielo ─────────────────────────

func _environment() -> void:
	# La misma tarde que en la plaza, un poco antes: sol bajo y dorado a la espalda del caminante
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.5, 0.36, 0.4)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.56, 0.58, 0.74)
	env.ambient_light_energy = 0.62
	env.fog_enabled = true
	env.fog_light_color = Color(0.72, 0.52, 0.44)
	env.fog_density = 0.0042
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 0.95
	env.tonemap_white = 4.5
	var we := WorldEnvironment.new()
	we.environment = env
	_root.add_child(we)
	_sun = DirectionalLight3D.new()
	_sun.basis = Basis.looking_at(-SUN_TO.normalized(), Vector3.UP)
	_sun.light_color = Color(1.0, 0.78, 0.54)
	_sun.light_energy = 1.05
	_sun.shadow_enabled = true
	_sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	_sun.directional_shadow_max_distance = 40.0
	_sun.shadow_bias = 0.06
	_sun.shadow_normal_bias = 1.4
	_root.add_child(_sun)


func _sky_dome() -> void:
	var bt := _sb.batch("cielo")
	var radius := 190.0
	var sun_az := Vector2(SUN_TO.x, SUN_TO.z).normalized()
	var top := Color(0.16, 0.22, 0.46)
	var mid := Color(0.5, 0.4, 0.58)
	var low := Color(1.0, 0.66, 0.38)
	var haze := Color(0.62, 0.44, 0.4)
	var rows := 9
	var cols := 24
	for r in rows + 1:
		var e := -0.12 + 1.12 * float(r) / float(rows)
		var y := sin(e * PI * 0.5)
		var flat := cos(e * PI * 0.5)
		for c in cols:
			var a := TAU * float(c) / float(cols)
			var dir := Vector2(sin(a), cos(a))
			var toward := clampf(dir.dot(sun_az) * 0.5 + 0.5, 0.0, 1.0)
			var col := haze.lerp(low, smoothstep(-0.12, 0.02, e))
			col = col.lerp(mid, smoothstep(0.03, 0.36, e))
			col = col.lerp(top, smoothstep(0.3, 0.85, e))
			var burn := pow(toward, 3.0) * (1.0 - smoothstep(0.0, 0.42, absf(e)))
			col = col.lerp(Color(1.0, 0.86, 0.52), burn * 0.85)
			bt.v.append(Vector3(dir.x * flat, y, dir.y * flat) * radius)
			bt.c.append(col)
	for r in rows:
		for c in cols:
			var a0 := r * cols + c
			var a1 := r * cols + (c + 1) % cols
			for q in [a0, a1, a1 + cols, a0, a1 + cols, a0 + cols]:
				bt.i.append(q)
	var sun_dir := SUN_TO.normalized()
	_sb.emit("cielo", "ball|8", Basis.IDENTITY, Vector3(15, 15, 15), sun_dir * 178.0 + Vector3(0, -22.0, 0), Color(1.0, 0.92, 0.66), Color(1.0, 0.8, 0.5))
	for k in 12:
		var a := _rng.randf() * TAU
		var h := 34.0 + _rng.randf() * 55.0
		var w := 26.0 + _rng.randf() * 34.0
		var near_sun := clampf(Vector2(sin(a), cos(a)).dot(sun_az) * 0.5 + 0.5, 0.0, 1.0)
		var col := Color(0.62, 0.48, 0.6).lerp(Color(1.0, 0.7, 0.5), near_sun)
		_sb.emit("cielo", "ball|8", Basis(Vector3.UP, a), Vector3(w, 3.0 + _rng.randf() * 3.0, w * 0.5), Vector3(sin(a) * 165.0, h, cos(a) * 165.0), col, col.darkened(0.25))
	# El monte lejano: una franja baja y oscura en todo el horizonte (la península es llana)
	for k in 28:
		var a := TAU * float(k) / 28.0 + _rng.randf() * 0.1
		var d := 150.0 + _rng.randf() * 12.0
		var col := Color(0.16, 0.24, 0.2).lerp(Color(0.3, 0.3, 0.26), _rng.randf() * 0.6)
		_sb.emit("cielo", "ball|8", Basis(Vector3.UP, a), Vector3(52.0, 7.0 + _rng.randf() * 7.0, 26.0), Vector3(sin(a) * d, -1.0, cos(a) * d), col, col.darkened(0.3))


# ───────────────────────── Suelo y camino ─────────────────────────

func _ground() -> void:
	_sb.tile("suelo", -100.0, -200.0, 320.0, 120.0, -0.07, MONTE)
	# Lo pisado entre albarradas, un poco más claro que el monte
	var axis: Array = []
	var len := Camino.road_length()
	var d := 0.0
	while d < len:
		axis.append(Camino.road_at(d)[0])
		d += 3.0
	axis.append(Camino.ROAD[Camino.ROAD.size() - 1])
	_sb.ribbon("suelo", axis, Camino.ROAD_HALF + 0.5, -0.05, EARTH, EARTH.lerp(MONTE, 0.55), 0.05)
	for p in Camino.ROAD:
		_sb.fan("suelo", _v3(p, -0.052), Camino.ROAD_HALF + 0.5, EARTH, EARTH.lerp(MONTE, 0.55), 20)
	for cl in Camino.CLEARINGS:
		_sb.fan("suelo", Vector3(float(cl[0]), -0.045, float(cl[1])), float(cl[2]) + 0.6, EARTH.lightened(0.04), EARTH.lerp(MONTE, 0.5), 28)
	# El camino blanco de sascab, con su orilla de polvo
	_sb.ribbon("suelo", axis, Camino.ROAD_WHITE + 0.9, -0.03, DUST, EARTH, 0.04)
	_sb.ribbon("suelo", axis, Camino.ROAD_WHITE, -0.015, SASCAB, SASCAB.lerp(DUST, 0.45), 0.06)
	for p in Camino.ROAD:
		_sb.fan("suelo", _v3(p, -0.028), Camino.ROAD_WHITE + 0.9, DUST, EARTH, 14)
		_sb.fan("suelo", _v3(p, -0.013), Camino.ROAD_WHITE, SASCAB, SASCAB.lerp(DUST, 0.45), 14)
	# Explanadas de los dos extremos
	_sb.fan("suelo", Vector3(1.5, -0.012, 0.0), 6.5, SASCAB.darkened(0.04), DUST, 24)
	_sb.fan("suelo", Vector3(float(Camino.CLEARINGS[4][0]), -0.012, float(Camino.CLEARINGS[4][1])), 8.5, SASCAB.darkened(0.04), DUST, 24)


## Albarradas: piedra suelta apilada a lo largo de todo el borde de lo transitable.
func _walls() -> void:
	for bp in _boundary(0.95):
		var p: Vector2 = bp[0]
		if p.x < -5.6:
			continue   # ahí está la muralla de Mérida
		if p.x > 217.5 and absf(p.y + 81.0) < 3.4:
			continue   # la tranca de Motul
		var out: Vector2 = bp[1]
		var yaw := atan2(out.x, out.y) + PI * 0.5 + _rng.randf_range(-0.3, 0.3)
		var b := _b("monte", _v3(p))   # albarradas y monte: mismo material, sin sombra, una malla por tramo
		var tone := STONE.lerp(STONE_DARK, _rng.randf() * 0.5)
		var w := 0.85 + _rng.randf() * 0.4
		var at := p + out * _rng.randf_range(0.1, 0.4)
		_sb.box(b, Vector3(w, 0.5, 0.6), tone, Vector3(at.x, 0.24, at.y), yaw, tone.darkened(0.35))
		var top := tone.lightened(0.12)
		_sb.box(b, Vector3(w * 0.72, 0.38, 0.46), top, Vector3(at.x + _rng.randf_range(-0.15, 0.15), 0.64, at.y + _rng.randf_range(-0.15, 0.15)), yaw + _rng.randf_range(-0.5, 0.5), tone)
		if _rng.randf() < 0.3:
			_sb.box(b, Vector3(0.42, 0.26, 0.36), top.lightened(0.06), Vector3(at.x, 0.94, at.y), yaw + 0.8, tone)
	# Más allá: monte bajo. Arbustos pegados a la albarrada y árboles detrás
	var k := 0
	for bp in _boundary(2.6):
		var p: Vector2 = bp[0]
		var out: Vector2 = bp[1]
		k += 1
		if p.x < -5.0 or p.x > 216.0:
			continue
		var bush: Vector2 = p + out * _rng.randf_range(1.6, 3.2) + Vector2(_rng.randf_range(-0.8, 0.8), _rng.randf_range(-0.8, 0.8))
		if _sd(bush) > 1.2 and not _reserved(bush):
			var r := 0.9 + _rng.randf() * 0.9
			var col := LEAF.lerp(LEAF_DRY, _rng.randf() * 0.8)
			_sb.ball(_b("monte", _v3(bush)), r, col.lightened(0.08), Vector3(bush.x, r * 0.5, bush.y), 0.8, col.darkened(0.45), 6)
		if k % 2 == 0:
			var tree: Vector2 = p + out * _rng.randf_range(4.5, 13.0) + Vector2(_rng.randf_range(-1.5, 1.5), _rng.randf_range(-1.5, 1.5))
			if _sd(tree) > 3.0 and not _reserved(tree):
				_tree(_b("monte", _v3(tree)), tree, 2.6 + _rng.randf() * 2.6, 1.7 + _rng.randf() * 1.5, LEAF.lerp(LEAF_LIGHT, _rng.randf() * 0.5), 6)


## Sitios de fuera del camino donde no debe crecer el monte: henequenal, casas de Motul, maizal.
func _reserved(p: Vector2) -> bool:
	if p.distance_to(Camino.HENEQUENAL) < 34.0 and p.y > -44.0:
		return true
	if p.x > 214.0 and p.y > -112.0 and p.y < -52.0:
		return true
	if p.distance_to(Camino.MILPA) < 22.0 and p.y > 8.0:
		return true
	return false


func _tree(b: String, at: Vector2, height: float, crown: float, leaf: Color, sides := 8) -> void:
	_sb.cyl(b, 0.22 + crown * 0.06, height, BARK, Vector3(at.x, 0.0, at.y), 6, 0.12, BARK.darkened(0.3))
	_sb.ball(b, crown, leaf.lightened(0.1), Vector3(at.x, height + crown * 0.35, at.y), 0.72, leaf.darkened(0.45), sides)
	if crown > 2.2:
		_sb.ball(b, crown * 0.62, leaf.lightened(0.16), Vector3(at.x + crown * 0.55, height + crown * 0.1, at.y - crown * 0.3), 0.75, leaf.darkened(0.4), sides)


## Árboles dentro del pasillo (chocan: están en camino_def.TREES). Dan sombra sobre el camino.
func _road_trees() -> void:
	for i in range(1, Camino.TREES.size() - 1):
		var t: Array = Camino.TREES[i]
		var at := Vector2(float(t[0]), float(t[1]))
		var h := 3.6 + _rng.randf() * 1.6
		var b := _b("obra", _v3(at))
		_sb.cyl(b, float(t[2]) * 0.8, h, BARK, _v3(at), 7, float(t[2]) * 0.45, BARK.darkened(0.35))
		var leaf := LEAF.lerp(LEAF_LIGHT, _rng.randf() * 0.6)
		_sb.ball(b, 3.0, leaf.lightened(0.1), Vector3(at.x, h + 1.3, at.y), 0.7, leaf.darkened(0.45))
		_sb.ball(b, 1.9, leaf.lightened(0.16), Vector3(at.x + 1.8, h + 0.6, at.y + 1.0), 0.75, leaf.darkened(0.4))
		_sb.ball(b, 1.6, leaf, Vector3(at.x - 1.7, h + 0.7, at.y - 0.9), 0.75, leaf.darkened(0.45))


# ───────────────────────── La salida de Mérida ─────────────────────────

func _merida_wall() -> void:
	var w: Array = Camino.WALLS[0]
	var x := float(w[0])
	var b := "monte0"   # sin sombra: con el sol bajo a su espalda dejaría a oscuras la llegada
	# Muralla blanca con remate ocre y almenas redondeadas
	_sb.box(b, Vector3(float(w[2]) * 2.0, 4.6, float(w[3]) * 2.0 + 30.0), WHITE, Vector3(x, 2.3, 0.0), 0.0, WHITE_SHADE)
	_sb.box(b, Vector3(float(w[2]) * 2.0 + 0.3, 0.35, float(w[3]) * 2.0 + 30.0), OCHRE, Vector3(x, 4.75, 0.0))
	var z := -30.0
	while z <= 30.0:
		if absf(z) > 4.5:
			_sb.ball(b, 0.55, WHITE, Vector3(x, 5.1, z), 1.0, WHITE_SHADE, 6)
		z += 3.0
	# El arco: jambas, dintel y un vano en sombra por el que se ve la ciudad encendida
	var front := x + float(w[2])
	for j in Camino.ARCH_JAMBS:
		_sb.cyl(b, float(j[2]) + 0.1, 5.2, WHITE, Vector3(j[0], 0.0, j[1]), 8, float(j[2]) - 0.05, WHITE_SHADE)
		_sb.box(b, Vector3(1.7, 0.4, 1.7), OCHRE.darkened(0.1), Vector3(j[0], 0.2, j[1]))
		_sb.box(b, Vector3(1.5, 0.3, 1.5), OCHRE, Vector3(j[0], 5.25, j[1]))
		_sb.ball("brillo", 0.22, WARM, Vector3(float(j[0]) + 0.75, 3.1, j[1]), 1.2, NONE, 6)
		_sb.pool("luz", Vector3(float(j[0]) + 1.6, 0.0, j[1]), 4.5, WARM, 0.22)
	_sb.box(b, Vector3(1.5, 1.2, 7.4), WHITE, Vector3(-5.2, 6.0, 0.0), 0.0, WHITE_SHADE)
	_sb.box(b, Vector3(1.7, 0.3, 7.8), OCHRE, Vector3(-5.2, 6.75, 0.0))
	_sb.box(b, Vector3(1.0, 0.7, 3.2), WHITE.lightened(0.05), Vector3(-5.2, 7.25, 0.0))
	# el vano: fondo cálido (la plaza al atardecer) con siluetas de casas y faroles
	_sb.quad("brillo", Vector3(front + 0.04, 0.0, -2.1), Vector3(front + 0.04, 0.0, 2.1), Vector3(front + 0.04, 5.3, 2.1), Vector3(front + 0.04, 5.3, -2.1),
		Color(0.2, 0.12, 0.16), Color(0.86, 0.5, 0.3))
	for h in [[-1.4, 1.5, 2.3], [-0.2, 1.1, 3.0], [1.2, 1.4, 2.0]]:
		_sb.box("brillo", Vector3(0.04, float(h[2]), float(h[1])), Color(0.3, 0.2, 0.24), Vector3(front + 0.08, float(h[2]) * 0.5, h[0]))
		_sb.box("brillo", Vector3(0.04, 0.3, 0.25), WARM, Vector3(front + 0.11, float(h[2]) * 0.6, h[0]))
	_sb.box("brillo", Vector3(0.04, 0.02, 2.6), SASCAB, Vector3(front + 0.09, 0.02, 0.0))
	_sb.pool("luz", Vector3(-3.0, 0.0, 0.0), 6.0, WARM, 0.2)


## El rincón de la cordelera: un flamboyán en flor, su rueda de corchar y rollos de soga.
func _quest_corner() -> void:
	var t: Array = Camino.TREES[0]
	var at := Vector2(float(t[0]), float(t[1]))
	var b := "obra0"
	_sb.cyl(b, 0.6, 3.4, BARK, _v3(at), 7, 0.34, BARK.darkened(0.35))
	_sb.beam(b, Vector3(at.x, 3.0, at.y), Vector3(at.x - 2.6, 4.3, at.y + 1.2), 0.24, BARK)
	_sb.beam(b, Vector3(at.x, 3.0, at.y), Vector3(at.x + 2.2, 4.4, at.y - 1.4), 0.22, BARK)
	for c in [[0.0, 5.0, 0.0, 3.4], [-2.9, 4.6, 1.4, 2.3], [2.5, 4.7, -1.6, 2.2], [0.6, 5.6, 2.2, 1.9]]:
		_sb.ball(b, float(c[3]), FLAME.lightened(0.08), Vector3(at.x + float(c[0]), c[1], at.y + float(c[2])), 0.5, FLAME.darkened(0.45).lerp(LEAF, 0.4))
	for k in 26:   # pétalos caídos
		var a := _rng.randf() * TAU
		var r := sqrt(_rng.randf()) * 5.5
		_sb.fan("suelo", Vector3(at.x + sin(a) * r, -0.008, at.y + cos(a) * r), 0.16 + _rng.randf() * 0.12, FLAME.lerp(EARTH, 0.25), FLAME.lerp(EARTH, 0.25), 5)
	# La rueda de corchar (para torcer la soga): un bastidor con su rueda de madera
	var w: Array = Camino.PROPS[0]
	var wp := Vector3(float(w[0]), 0.0, float(w[1]))
	_sb.box(b, Vector3(0.14, 1.5, 0.14), WOOD_DARK, wp + Vector3(-0.3, 0.75, 0))
	_sb.box(b, Vector3(0.14, 1.5, 0.14), WOOD_DARK, wp + Vector3(0.3, 0.75, 0))
	_sb.box(b, Vector3(1.1, 0.12, 0.5), WOOD_DARK, wp + Vector3(0, 0.06, 0))
	_sb.cyl(b, 0.62, 0.1, WOOD, wp + Vector3(0, 1.1, -0.05), 12, -1.0, WOOD_DARK, Basis(Vector3.RIGHT, PI * 0.5))
	_sb.cyl(b, 0.12, 0.34, WOOD_DARK, wp + Vector3(0, 1.1, -0.17), 6, -1.0, NONE, Basis(Vector3.RIGHT, PI * 0.5))
	# sogas: una tendida hasta una estaca y rollos en el suelo
	_sb.beam(b, wp + Vector3(0, 1.1, 0.1), Vector3(wp.x + 0.4, 0.5, wp.z - 4.2), 0.06, HUANO)
	_sb.box(b, Vector3(0.1, 0.7, 0.1), WOOD_DARK, Vector3(wp.x + 0.4, 0.35, wp.z - 4.2))
	for c in [[1.3, 0.4], [1.7, -0.5], [-1.2, 0.8]]:
		for ring in 3:
			_sb.cyl(b, 0.34 - 0.04 * float(ring), 0.1, HUANO.lightened(0.05 * float(ring)), wp + Vector3(c[0], 0.1 * float(ring), c[1]), 8, -1.0, HUANO.darkened(0.3))
	# aquí hay alguien con quien hablar
	var n := Camino.QUEST_NPC
	_sb.ring("brillo", Vector3(n.x, 0.012, n.y), 0.95, 1.06, GOLD.darkened(0.1), 24)
	_sb.fan("suelo", Vector3(n.x, -0.006, n.y), 1.7, Color(0.62, 0.3, 0.26), Color(0.5, 0.24, 0.22), 18)


## Mojoneras de jade: dónde acaba cada zona segura. Entre cada par, una línea de luces en el suelo.
func _markers() -> void:
	for i in range(0, Camino.MARKERS.size(), 2):
		var a := Vector2(float(Camino.MARKERS[i][0]), float(Camino.MARKERS[i][1]))
		var c := Vector2(float(Camino.MARKERS[i + 1][0]), float(Camino.MARKERS[i + 1][1]))
		for p in [a, c]:
			var b := _b("obra", _v3(p))
			_sb.cyl(b, 0.45, 1.5, STONE, _v3(p), 6, 0.3, STONE_DARK)
			_sb.cyl("brillo", 0.36, 0.16, JADE, Vector3(p.x, 1.0, p.y), 6, 0.34)
			_sb.ball("brillo", 0.2, JADE.lightened(0.3), Vector3(p.x, 1.7, p.y), 1.0, NONE, 6)
			_sb.pool("luz", _v3(p), 3.2, JADE, 0.22)
		for k in range(1, 10):
			var p := a.lerp(c, float(k) / 10.0)
			_sb.fan("brillo", Vector3(p.x, 0.0, p.y), 0.16, JADE, JADE, 4)


# ───────────────────────── La milpa ─────────────────────────

func _milpa() -> void:
	var c := Camino.MILPA
	# surcos y maíz (no estorba el paso: el alux cabe entre las cañas)
	var row := -9.0
	while row <= 9.0:
		var along := -10.0
		while along <= 10.0:
			var p := c + Vector2(along + _rng.randf_range(-0.25, 0.25), row + _rng.randf_range(-0.2, 0.2))
			along += 1.25
			if p.distance_to(c) > 10.6 or p.y < 1.0 or _sd(p) > -0.9:
				continue
			if p.distance_to(Vector2(44.0, 8.0)) < 2.2 or p.distance_to(Vector2(49.5, 11.5)) < 3.4 or p.distance_to(Vector2(40.0, 12.5)) < 1.2:
				continue
			var h := 1.5 + _rng.randf() * 0.7
			_sb.box("det0" if p.x < 28.0 else "det1", Vector3(0.07, h, 0.07), CORN.darkened(0.1), Vector3(p.x, h * 0.5, p.y))
			for l in 3:
				var a := _rng.randf() * TAU
				_sb.spike("det0" if p.x < 28.0 else "det1", Vector3(p.x, h * (0.35 + 0.2 * float(l)), p.y), Vector3(sin(a), 0.55, cos(a)), 0.75, 0.07, CORN, CORN.lightened(0.15), 3)
			_sb.ball("det0" if p.x < 28.0 else "det1", 0.09, Color(0.92, 0.8, 0.4), Vector3(p.x, h + 0.08, p.y), 1.8, NONE, 6)
		_sb.box("suelo", Vector3(20.0, 0.02, 0.5), EARTH.darkened(0.22), Vector3(c.x, -0.03, c.y + row))
		row += 1.5
	# El troje: paredes de bajareque y techo de huano a dos aguas
	var h: Array = Camino.HUTS[0]
	var hp := Vector3(float(h[0]), 0.0, float(h[1]))
	_sb.box("obra1", Vector3(float(h[2]) * 2.0, 2.0, float(h[3]) * 2.0), Color(0.74, 0.62, 0.46), hp + Vector3(0, 1.0, 0), 0.0, Color(0.5, 0.4, 0.3))
	_sb.cyl("obra1", 2.9, 1.7, HUANO, hp + Vector3(0, 2.0, 0), 4, 0.2, HUANO.darkened(0.3), Basis(Vector3.UP, PI * 0.25))
	_sb.box("obra1", Vector3(0.9, 1.5, 0.08), WOOD_DARK, hp + Vector3(-0.3, 0.75, -float(h[3]) - 0.02))
	# Espantapájaros con sombrero
	var s: Array = Camino.PROPS[2]
	var sp := Vector3(float(s[0]), 0.0, float(s[1]))
	_sb.box("obra1", Vector3(0.1, 2.1, 0.1), WOOD_DARK, sp + Vector3(0, 1.05, 0))
	_sb.box("obra1", Vector3(1.5, 0.09, 0.09), WOOD_DARK, sp + Vector3(0, 1.55, 0))
	_sb.box("obra1", Vector3(0.7, 0.75, 0.3), Color(0.76, 0.3, 0.24), sp + Vector3(0, 1.4, 0), 0.0, Color(0.5, 0.2, 0.2))
	_sb.ball("obra1", 0.24, Color(0.84, 0.74, 0.5), sp + Vector3(0, 2.05, 0), 1.0, NONE, 6)
	_sb.cyl("obra1", 0.5, 0.06, HUANO, sp + Vector3(0, 2.2, 0), 8)
	_sb.cyl("obra1", 0.24, 0.22, HUANO.darkened(0.1), sp + Vector3(0, 2.25, 0), 8, 0.16)
	_place_stone(Camino.DISCOVERIES[0].at)


## Piedra de hallazgo: marca un lugar por descubrir (un disco tallado con un aro turquesa).
func _place_stone(at: Vector2) -> void:
	var b := _b("obra", _v3(at))
	_sb.cyl(b, 0.62, 0.22, STONE, _v3(at), 10, 0.52, STONE_DARK)
	_sb.ring("brillo", Vector3(at.x, 0.235, at.y), 0.3, 0.42, Color(0.3, 0.9, 1.0), 16)
	_sb.fan("brillo", Vector3(at.x, 0.236, at.y), 0.12, Color(0.3, 0.9, 1.0), Color(0.3, 0.9, 1.0), 4)
	_sb.pool("luz", _v3(at), 2.6, Color(0.3, 0.9, 1.0), 0.16)


# ───────────────────────── El cenote ─────────────────────────

func _cenote() -> void:
	var c := Camino.CENOTE
	var r := Camino.CENOTE_R
	# Brocal de roca caliza alrededor del ojo de agua (el agua va en su propia malla)
	_sb.ring("suelo", Vector3(c.x, -0.01, c.y), r - 0.4, r + 1.6, STONE.lightened(0.05), 30, EARTH)
	for k in 22:
		var a := TAU * float(k) / 22.0 + _rng.randf_range(-0.08, 0.08)
		var rr := r + _rng.randf_range(0.0, 0.5)
		var s := 0.5 + _rng.randf() * 0.55
		var tone := STONE.lerp(STONE_DARK, _rng.randf() * 0.5)
		_sb.ball("obra1" if c.x < 76.0 else "obra2", s, tone.lightened(0.1), Vector3(c.x + sin(a) * rr, s * 0.3, c.y + cos(a) * rr), 0.7, tone.darkened(0.4), 6)
	# carrizos en la orilla norte
	for k in 26:
		var a := PI + _rng.randf_range(-1.1, 1.1)
		var rr := r + 0.5 + _rng.randf() * 1.2
		var p := Vector3(c.x + sin(a) * rr, 0.0, c.y + cos(a) * rr)
		_sb.spike("det2" if p.x > 76.0 else "det1", p, Vector3(_rng.randf_range(-0.12, 0.12), 1.0, _rng.randf_range(-0.12, 0.12)), 1.3 + _rng.randf() * 0.9, 0.06, LEAF_LIGHT.darkened(0.1), LEAF_LIGHT.lightened(0.2), 3)
	# El árbol grande, con raíces que bajan a beber
	var t: Array = Camino.TREES[Camino.TREES.size() - 1]
	var at := Vector2(float(t[0]), float(t[1]))
	var b := "obra2"
	_sb.cyl(b, 1.05, 6.4, BARK.lightened(0.05), _v3(at), 8, 0.6, BARK.darkened(0.4))
	for root in [[-2.4, 0.6], [-1.6, -1.9], [-2.6, 2.0]]:
		_sb.beam(b, Vector3(at.x, 1.6, at.y), Vector3(at.x + float(root[0]), 0.0, at.y + float(root[1])), 0.34, BARK.darkened(0.15))
	for cr in [[0.0, 8.2, 0.0, 5.0], [-3.6, 7.2, 1.6, 3.2], [3.0, 7.4, -2.0, 3.0], [0.8, 9.6, 2.6, 2.6]]:
		_sb.ball(b, float(cr[3]), LEAF.lightened(0.12), Vector3(at.x + float(cr[0]), cr[1], at.y + float(cr[2])), 0.62, LEAF.darkened(0.5))
	_place_stone(Camino.DISCOVERIES[1].at)


# ───────────────────────── El henequenal ─────────────────────────

func _agave(b: String, at: Vector3, size: float, sides := 4) -> void:
	_sb.ball(b, 0.32 * size, AGAVE_DARK.lightened(0.1), at + Vector3(0, 0.26 * size, 0), 1.1, AGAVE_DARK, 6)
	var n := 9
	for k in n:
		var a := TAU * float(k) / float(n) + _rng.randf_range(-0.15, 0.15)
		var lift := 0.55 + 0.5 * float(k % 3) / 2.0
		_sb.spike(b, at + Vector3(0, 0.2 * size, 0), Vector3(sin(a), lift, cos(a)), (1.25 + _rng.randf() * 0.3) * size, 0.15 * size, AGAVE_DARK, AGAVE.lightened(0.1), sides)


func _henequenal() -> void:
	var c := Camino.HENEQUENAL
	# Las matas de dentro del claro (estorban: están en camino_def.AGAVES)
	for a in Camino.AGAVES:
		_agave("obra2" if float(a[0]) < 124.0 else "obra3", Vector3(a[0], 0.0, a[1]), 1.25, 5)
	# El plantío: hileras hasta donde alcanza la vista, al otro lado de la albarrada
	var row := 0
	var z := c.y - 16.0
	while z <= c.y + 34.0:
		var x := c.x - 34.0 + (1.6 if row % 2 == 1 else 0.0)
		while x <= c.x + 36.0:
			var p := Vector2(x + _rng.randf_range(-0.2, 0.2), z + _rng.randf_range(-0.2, 0.2))
			x += 3.2
			if _sd(p) < 1.6 or p.distance_to(c) > 38.0:
				continue
			_agave(_b("det", _v3(p)), _v3(p), 0.85 + _rng.randf() * 0.3, 3)
		z += 3.4
		row += 1
	# La veleta: torre de celosía con su rueda de aspas (la rueda gira; es un nodo aparte)
	var v: Array = Camino.PROPS[1]
	var vp := Vector3(float(v[0]), 0.0, float(v[1]))
	var b := "obra3"
	for leg in [[-0.8, -0.8], [0.8, -0.8], [0.8, 0.8], [-0.8, 0.8]]:
		_sb.beam(b, vp + Vector3(leg[0], 0.0, leg[1]), vp + Vector3(float(leg[0]) * 0.18, 7.2, float(leg[1]) * 0.18), 0.1, Color(0.36, 0.38, 0.4))
	for lvl in 4:
		var y := 1.2 + 1.6 * float(lvl)
		var w := 0.8 * (1.0 - y / 9.0)
		_sb.box(b, Vector3(w * 2.0 + 0.1, 0.07, 0.07), Color(0.3, 0.32, 0.34), vp + Vector3(0, y, -w))
		_sb.box(b, Vector3(w * 2.0 + 0.1, 0.07, 0.07), Color(0.3, 0.32, 0.34), vp + Vector3(0, y, w))
		_sb.box(b, Vector3(0.07, 0.07, w * 2.0 + 0.1), Color(0.3, 0.32, 0.34), vp + Vector3(-w, y, 0))
		_sb.box(b, Vector3(0.07, 0.07, w * 2.0 + 0.1), Color(0.3, 0.32, 0.34), vp + Vector3(w, y, 0))
	_sb.box(b, Vector3(0.1, 0.5, 1.5), Color(0.72, 0.3, 0.24), vp + Vector3(0.0, 7.4, 1.1))       # la cola
	var wb := SceneBatch.new()
	for k in 12:
		var a := TAU * float(k) / 12.0
		wb.emit("rueda", "box", Basis(Vector3.FORWARD, a) * Basis(Vector3.UP, 0.35), Vector3(0.34, 1.25, 0.03), Basis(Vector3.FORWARD, a) * Vector3(0, 0.85, 0), Color(0.78, 0.8, 0.8), NONE)
	wb.cyl("rueda", 0.16, 0.2, Color(0.3, 0.32, 0.34), Vector3(0, 0, -0.1), 8, -1.0, NONE, Basis(Vector3.RIGHT, PI * 0.5))
	var wheel := wb.commit("rueda", _sb.solid(), _root, false)
	wheel.position = vp + Vector3(0.0, 7.4, -0.5)
	wheel.visibility_range_end = 120.0
	_wheel = wheel
	# La pila: tanque de mampostería donde cae el agua de la veleta
	var t: Array = Camino.HUTS[1]
	var tp := Vector3(float(t[0]), 0.0, float(t[1]))
	_sb.box(b, Vector3(float(t[2]) * 2.0, 0.9, float(t[3]) * 2.0), WHITE, tp + Vector3(0, 0.45, 0), 0.0, WHITE_SHADE)
	_sb.box("brillo", Vector3(float(t[2]) * 2.0 - 0.4, 0.02, float(t[3]) * 2.0 - 0.4), WATER.lightened(0.15), tp + Vector3(0, 0.91, 0))
	_sb.beam(b, vp + Vector3(0, 0.4, 0), tp + Vector3(1.0, 0.95, 0.4), 0.1, Color(0.3, 0.32, 0.34))
	# pencas cortadas, atadas en manojos
	for k in 3:
		var at := Vector3(c.x - 3.5 + 1.1 * float(k), 0.18, c.y + 6.0)
		_sb.box(b, Vector3(0.5, 0.34, 1.5), AGAVE.darkened(0.1), at, 0.3 * float(k), AGAVE_DARK)
		_sb.box(b, Vector3(0.54, 0.36, 0.08), HUANO, at, 0.3 * float(k))
	_place_stone(Camino.DISCOVERIES[2].at)


# ───────────────────────── La llegada a Motul ─────────────────────────

func _motul() -> void:
	var b := "obra5"
	var a := Vector3(Camino.SIGN_POSTS[0][0], 0.0, Camino.SIGN_POSTS[0][1])
	var c := Vector3(Camino.SIGN_POSTS[1][0], 0.0, Camino.SIGN_POSTS[1][1])
	var across := (c - a).normalized()
	var yaw := atan2(across.x, across.z)
	# El cartel de bienvenida: dos pilares encalados y un tablero de lado a lado del camino
	for p in [a, c]:
		_sb.box(b, Vector3(1.1, 0.5, 1.1), OCHRE.darkened(0.12), p + Vector3(0, 0.25, 0), yaw)
		_sb.box(b, Vector3(0.78, 5.4, 0.78), WHITE, p + Vector3(0, 3.2, 0), yaw, WHITE_SHADE)
		_sb.box(b, Vector3(0.98, 0.26, 0.98), OCHRE, p + Vector3(0, 5.95, 0), yaw)
		_sb.ball("brillo", 0.26, WARM, p + Vector3(0, 6.4, 0), 1.15, NONE, 6)
		_sb.pool("luz", p, 4.2, WARM, 0.2)
	var mid := (a + c) * 0.5
	_sb.beam(b, a + Vector3(0, 4.9, 0), c + Vector3(0, 4.9, 0), 1.7, Color(0.2, 0.36, 0.34), 0.3)        # tablero verde hoja
	_sb.beam(b, a + Vector3(0, 5.82, 0), c + Vector3(0, 5.82, 0), 0.16, OCHRE, 0.42)
	_sb.beam(b, a + Vector3(0, 3.98, 0), c + Vector3(0, 3.98, 0), 0.16, OCHRE, 0.42)
	# el emblema: una mata de henequén sobre el tablero (icono propio; no es el escudo del municipio)
	_agave(b, mid + Vector3(0, 5.9, 0), 1.0, 5)
	# sogas en guirnalda entre los pilares (Motul, tierra de cordeleros)
	var prev := a + Vector3(0, 3.9, 0)
	for k in range(1, 9):
		var t := float(k) / 8.0
		var p := a.lerp(c, t) + Vector3(0, 3.9 - sin(t * PI) * 0.55, 0)
		_sb.beam(b, prev, p, 0.07, HUANO)
		prev = p
	# La carreta de regreso, con sus rollos de soga y un farol
	var h: Array = Camino.HUTS[2]
	var cp := Vector3(float(h[0]), 0.0, float(h[1]))
	_sb.box(b, Vector3(2.8, 0.2, 1.7), WOOD, cp + Vector3(0, 0.85, 0), 0.0, WOOD_DARK)
	for side in [-1.0, 1.0]:
		_sb.cyl(b, 0.72, 0.14, WOOD_DARK, cp + Vector3(0.3, 0.72, side * 0.98), 10, -1.0, NONE, Basis(Vector3.RIGHT, PI * 0.5))
		_sb.box(b, Vector3(2.8, 0.5, 0.08), WOOD_DARK, cp + Vector3(0, 1.2, side * 0.82))
		_sb.beam(b, cp + Vector3(-1.4, 0.85, side * 0.5), cp + Vector3(-3.3, 0.55, side * 0.5), 0.09, WOOD_DARK)
	for k in 3:
		_sb.cyl(b, 0.36, 0.34, HUANO.lightened(0.04 * float(k)), cp + Vector3(-0.7 + 0.75 * float(k), 0.95, 0.1), 8, -1.0, HUANO.darkened(0.3))
	_sb.box(b, Vector3(0.07, 1.5, 0.07), WOOD_DARK, cp + Vector3(1.3, 1.7, 0.7))
	_sb.ball("brillo", 0.2, WARM, cp + Vector3(1.3, 2.45, 0.7), 1.2, NONE, 6)
	_sb.pool("luz", cp + Vector3(-1.2, 0, 1.0), 4.0, WARM, 0.22)
	_sb.ring("brillo", Vector3(Camino.GATE_CART.x, 0.012, Camino.GATE_CART.y), 0.7, 0.8, GOLD.darkened(0.15), 20)
	# La tranca: Motul queda al otro lado (la ciudad aún no está construida)
	for z in [-84.0, -78.0]:
		_sb.box(b, Vector3(0.3, 1.5, 0.3), WOOD_DARK, Vector3(219.4, 0.75, z))
	for y in [0.55, 1.1]:
		_sb.box(b, Vector3(0.12, 0.14, 6.2), WOOD, Vector3(219.4, y, -81.0))
	# Motul a lo lejos: casas de colores, árboles y más henequén
	var paints: Array = [Color(0.93, 0.78, 0.42), Color(0.86, 0.56, 0.5), Color(0.6, 0.78, 0.8), WHITE, Color(0.7, 0.8, 0.56)]
	var n := 0
	for hs in [[232.0, -96.0, 9.0, 4.6], [234.0, -82.0, 8.0, 5.4], [233.0, -68.0, 10.0, 4.4], [248.0, -90.0, 9.0, 6.0], [249.0, -74.0, 9.0, 5.0], [246.0, -104.0, 8.0, 4.4]]:
		var paint: Color = paints[n % paints.size()]
		n += 1
		var at := Vector3(hs[0], 0.0, hs[1])
		_sb.box("monte5", Vector3(8.0, float(hs[3]), float(hs[2])), paint, at + Vector3(0, float(hs[3]) * 0.5, 0), 0.0, paint.darkened(0.35))
		_sb.box("monte5", Vector3(8.5, 0.4, float(hs[2]) + 0.5), Color(0.72, 0.36, 0.24), at + Vector3(0, float(hs[3]) + 0.2, 0))
		for win in 2:
			_sb.box("brillo", Vector3(0.1, 1.3, 1.1), Color(1.0, 0.74, 0.4), at + Vector3(-4.03, float(hs[3]) * 0.55, float(win) * 3.2 - 1.6))
	for t in [[226.0, -90.0], [227.0, -72.0], [240.0, -60.0], [241.0, -110.0]]:
		_tree("monte5", Vector2(t[0], t[1]), 3.4, 2.8, LEAF_LIGHT.lerp(LEAF, 0.4))
	_sb.ribbon("suelo", [Vector2(213.0, -81.0), Vector2(262.0, -84.0)], Camino.ROAD_WHITE, -0.02, SASCAB.darkened(0.06), DUST)


# ───────────────────────── Matas, flores y piedras ─────────────────────────

func _scatter() -> void:
	var len := Camino.road_length()
	for k in 230:
		var along := _rng.randf() * len
		var ra: Array = Camino.road_at(along)
		var dir: Vector2 = ra[1]
		var side := -1.0 if _rng.randf() < 0.5 else 1.0
		var p: Vector2 = (ra[0] as Vector2) + Vector2(-dir.y, dir.x) * side * _rng.randf_range(Camino.ROAD_WHITE + 1.2, Camino.ROAD_HALF - 0.6)
		var b := _b("det", _v3(p))
		var kind := _rng.randf()
		if kind < 0.62:
			var col := LEAF_DRY.lerp(LEAF_LIGHT, _rng.randf())
			for s in 3:
				_sb.spike(b, _v3(p), Vector3(_rng.randf_range(-0.5, 0.5), 1.0, _rng.randf_range(-0.5, 0.5)), 0.35 + _rng.randf() * 0.4, 0.07, col.darkened(0.25), col, 3)
		elif kind < 0.82:
			var tone := STONE.lerp(STONE_DARK, _rng.randf() * 0.6)
			var s := 0.25 + _rng.randf() * 0.4
			_sb.ball(b, s, tone.lightened(0.1), Vector3(p.x, s * 0.25, p.y), 0.6, tone.darkened(0.4), 6)
		else:
			var petal: Color = [Color(1.0, 0.82, 0.25), Color(0.95, 0.45, 0.7), Color(0.98, 0.96, 0.9), Color(1.0, 0.55, 0.2)][_rng.randi() % 4]
			_sb.spike(b, _v3(p), Vector3(0, 1, 0), 0.34, 0.03, LEAF_LIGHT, LEAF_LIGHT, 3)
			_sb.box(b, Vector3(0.2, 0.05, 0.2), petal, Vector3(p.x, 0.36, p.y), _rng.randf() * PI)
	# Iguanas tomando el último sol sobre la albarrada (decorado: no se mueven ni se atacan)
	var walls := _boundary(17.0)
	for i in range(0, walls.size(), 3):
		var p: Vector2 = walls[i][0]
		if p.x < 0.0 or p.x > 214.0:
			continue
		var out: Vector2 = walls[i][1]
		_iguana(Vector3(p.x + out.x * 0.25, 0.86, p.y + out.y * 0.25), atan2(out.x, out.y) + PI * 0.5)


func _iguana(pos: Vector3, yaw: float) -> void:
	var d := _b("det", pos)
	var b := Basis(Vector3.UP, yaw)
	var green := Color(0.4, 0.5, 0.3)
	_sb.emit(d, "ball|6", b, Vector3(0.24, 0.17, 0.62), pos + Vector3(0, 0.1, 0), green.lightened(0.15), green.darkened(0.3))
	_sb.emit(d, "ball|6", b, Vector3(0.17, 0.15, 0.24), pos + b * Vector3(0, 0.19, 0.36), green.lightened(0.2), green.darkened(0.2))
	_sb.emit(d, "cyl|5|0.05", b * Basis(Vector3.RIGHT, -PI * 0.5 - 0.06), Vector3(0.07, 0.75, 0.07), pos + b * Vector3(0, 0.07, -0.62), green.darkened(0.15), NONE)


func _commit_all() -> void:
	_sky = _sb.commit("cielo", _sb.sky(), _root)
	_sky.custom_aabb = AABB(Vector3(-200, -40, -200), Vector3(400, 260, 400))
	_sb.commit("suelo", _sb.solid(), _root)
	for k in CHUNKS:
		_sb.commit("obra%d" % k, _sb.solid(), _root, true)
		var m := _sb.commit("monte%d" % k, _sb.solid(), _root)
		if m != null:
			_monte.append(m)
		var d := _sb.commit("det%d" % k, _sb.solid(), _root)
		if d != null:
			_details.append(d)
	_sb.commit("brillo", _sb.glow(), _root)
	_sb.commit("luz", _sb.additive(), _root)


# ───────────────────────── Vida ambiental (sombreadores) ─────────────────────────

## El agua del cenote: un disco turquesa con ondas, más oscuro en el centro.
func _water() -> void:
	var c := Camino.CENOTE
	var bt := _sb.batch("agua")
	var sides := 28
	bt.v.append(Vector3(c.x, 0.03, c.y))
	bt.c.append(Color.WHITE)
	bt.uv.append(Vector2(0.0, 0.0))
	for k in sides:
		var a := TAU * float(k) / float(sides)
		bt.v.append(Vector3(c.x + sin(a) * (Camino.CENOTE_R + 0.1), 0.03, c.y + cos(a) * (Camino.CENOTE_R + 0.1)))
		bt.c.append(Color.WHITE)
		bt.uv.append(Vector2(1.0, a))
	for k in sides:
		bt.i.append(0)
		bt.i.append(1 + (k + 1) % sides)
		bt.i.append(1 + k)
	_sb.commit_shader("agua", """shader_type spatial;
render_mode unshaded, shadows_disabled;
void fragment() {
	float r = UV.x;
	float rings = sin(r * 22.0 - TIME * 1.4) * 0.5 + 0.5;
	float swell = sin(UV.y * 5.0 + TIME * 0.6 + r * 4.0) * 0.5 + 0.5;
	vec3 deep = vec3(0.01, 0.12, 0.2);
	vec3 shallow = vec3(0.08, 0.62, 0.62);
	vec3 col = mix(deep, shallow, smoothstep(0.15, 1.0, r));
	col += vec3(0.25, 0.4, 0.36) * rings * swell * 0.22 * smoothstep(0.1, 0.9, r);
	col += vec3(1.0, 0.7, 0.45) * pow(swell * rings, 6.0) * 0.5;
	ALBEDO = col;
}
""", _root, 0.5)


## Aves a contraluz dando vueltas sobre tres tramos del camino.
func _birds() -> void:
	var bt := _sb.batch("aves")
	for flock in [[40.0, -6.0], [112.0, -40.0], [178.0, -70.0]]:
		for k in 6:
			var center := Vector3(float(flock[0]) + _rng.randf() * 8.0 - 4.0, 13.0 + _rng.randf() * 8.0, float(flock[1]) + _rng.randf() * 8.0 - 4.0)
			var orbit := 9.0 + _rng.randf() * 15.0
			var phase := Vector2(_rng.randf(), (0.16 + _rng.randf() * 0.12) * (1.0 if k % 3 != 0 else -1.0))
			var col := Color(0.14, 0.12, 0.16)
			var base := bt.v.size()
			# NORMAL lleva la forma: x a los lados, y arriba, z adelante. UV.x = cuánto aletea ese vértice
			for pt in [[Vector3(0, 0, 0.32), 0.0], [Vector3(0, 0, -0.3), 0.0], [Vector3(0.85, 0, -0.12), 1.0], [Vector3(-0.85, 0, -0.12), 1.0]]:
				bt.v.append(center)
				bt.n.append(pt[0])
				bt.c.append(col)
				bt.uv.append(Vector2(float(pt[1]), orbit / 30.0))
				bt.uv2.append(phase)
			for q in [0, 1, 2, 0, 3, 1]:
				bt.i.append(base + q)
	var birds := _sb.commit_shader("aves", """shader_type spatial;
render_mode unshaded, cull_disabled, shadows_disabled, skip_vertex_transform;
void vertex() {
	float ph = UV2.x * 6.2831;
	float a = TIME * UV2.y + ph;
	float r = UV.y * 30.0;
	vec3 c = VERTEX + vec3(cos(a) * r, sin(a * 2.0 + ph) * 1.2, sin(a) * r);
	vec2 dir = vec2(-sin(a), cos(a)) * sign(UV2.y);
	vec3 o = NORMAL;
	o.y += UV.x * sin(TIME * 7.0 + ph * 5.0) * 0.5;
	vec3 wp = c + vec3(-dir.y, 0.0, dir.x) * o.x + vec3(0.0, o.y, 0.0) + vec3(dir.x, 0.0, dir.y) * o.z;
	VERTEX = (VIEW_MATRIX * vec4(wp, 1.0)).xyz;
	NORMAL = vec3(0.0, 0.0, 1.0);
}
void fragment() {
	ALBEDO = pow(COLOR.rgb, vec3(2.2));
}
""", _root)
	birds.custom_aabb = AABB(Vector3(-10, 6, -110), Vector3(240, 26, 140))


## Mariposas en las flores del camino y libélulas sobre el cenote: tarjetas que aletean y vagan.
func _butterflies() -> void:
	var bt := _sb.batch("mariposas")
	var spots: Array = [[14.0, 2.0, 5.0, 7, 0], [44.0, 6.0, 9.0, 10, 0], [66.0, -17.0, 6.0, 6, 0], [92.0, -47.0, 7.0, 12, 1],
		[120.0, -46.0, 6.0, 6, 0], [140.0, -38.0, 9.0, 8, 0], [168.0, -66.0, 6.0, 6, 0], [204.0, -80.0, 8.0, 8, 0]]
	var wings: Array = [Color(1.0, 0.72, 0.15), Color(0.98, 0.95, 0.85), Color(0.95, 0.4, 0.6), Color(0.45, 0.75, 1.0)]
	for s in spots:
		for k in int(s[3]):
			var a := _rng.randf() * TAU
			var r := sqrt(_rng.randf()) * float(s[2])
			var center := Vector3(float(s[0]) + sin(a) * r, 0.5 + _rng.randf() * 1.5, float(s[1]) + cos(a) * r)
			var col: Color = Color(0.3, 0.95, 0.9) if int(s[4]) == 1 else wings[_rng.randi() % wings.size()]
			var phase := Vector2(_rng.randf(), 0.5 + _rng.randf() * 0.6)
			var base := bt.v.size()
			# dos alas: cada una un triángulo que sale del cuerpo. UV.x = lado (−1/1), UV.y = punta
			for pt in [[0.0, 0.0], [-1.0, 1.0], [-1.0, -0.6], [1.0, 1.0], [1.0, -0.6]]:
				bt.v.append(center)
				bt.c.append(col)
				bt.uv.append(Vector2(pt[0], pt[1]))
				bt.uv2.append(phase)
			for q in [0, 1, 2, 0, 4, 3]:
				bt.i.append(base + q)
	var mi := _sb.commit_shader("mariposas", """shader_type spatial;
render_mode unshaded, cull_disabled, shadows_disabled, skip_vertex_transform;
void vertex() {
	float ph = UV2.x * 6.2831;
	float t = TIME * UV2.y + ph;
	vec3 c = VERTEX + vec3(sin(t * 0.7) * 1.6, sin(t * 1.9 + ph) * 0.4, cos(t * 0.53 + ph * 2.0) * 1.6);
	float head = t * 0.7 + ph;
	vec3 fwd = vec3(cos(head), 0.0, -sin(head));
	vec3 side = vec3(-fwd.z, 0.0, fwd.x);
	float flap = sin(TIME * 16.0 + ph * 9.0) * 0.9;
	float span = abs(UV.x) * 0.17;
	vec3 wp = c + side * sign(UV.x) * span * cos(flap) + vec3(0.0, span * sin(flap) + 0.02, 0.0) + fwd * UV.y * 0.13 * abs(UV.x);
	VERTEX = (VIEW_MATRIX * vec4(wp, 1.0)).xyz;
	NORMAL = vec3(0.0, 0.0, 1.0);
}
void fragment() {
	ALBEDO = pow(COLOR.rgb, vec3(2.2));
}
""", _root, 4.0)
	mi.visibility_range_end = 60.0
	_details.append(mi)


# ───────────────────────── Rótulos ─────────────────────────

func _labels() -> void:
	var a := Vector3(Camino.SIGN_POSTS[0][0], 0.0, Camino.SIGN_POSTS[0][1])
	var c := Vector3(Camino.SIGN_POSTS[1][0], 0.0, Camino.SIGN_POSTS[1][1])
	var mid := (a + c) * 0.5
	# El tablero se lee viniendo de Mérida
	var back: Vector2 = -(Camino.road_at(Camino.road_length())[1] as Vector2)
	var yaw := atan2(back.x, back.y)
	_label("BIENVENIDOS A", mid + Vector3(back.x * 0.17, 5.4, back.y * 0.17), yaw, 0.0085, Color(1.0, 0.9, 0.62), 90.0)
	_label("MOTUL", mid + Vector3(back.x * 0.17, 4.62, back.y * 0.17), yaw, 0.0165, Color(1.0, 0.97, 0.9), 120.0)
	_label("Motul  ·  próximamente", Vector3(219.2, 1.75, -81.0), -PI * 0.5, 0.0058, Color(1.0, 0.88, 0.5), 30.0)
	_label("MÉRIDA", Vector3(-4.4, 6.0, 0.0), PI * 0.5, 0.0085, Color(0.36, 0.24, 0.16), 60.0, false)


func _label(text: String, pos: Vector3, yaw: float, pixel: float, color: Color, range_end: float, outline := true) -> void:
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
	_root.add_child(label)
