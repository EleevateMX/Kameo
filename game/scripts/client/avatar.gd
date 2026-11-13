extends Node3D
## Personaje visible: un alux y su forma de Balam.
## No contiene reglas de juego: sólo muestra el estado que decide el servidor.
##
## Usa los modelos de `res://assets/characters/*.glb` (arte hecho en Blender, ver art/README.md)
## cuando existen; si faltan, recurre a modelos de respaldo hechos con primitivas.

const Fx := preload("res://scripts/client/fx.gd")
const Audio := preload("res://scripts/client/audio.gd")

const SKIN := Color(0.66, 0.44, 0.29)
const STRAW := Color(0.74, 0.56, 0.30)
const EYE := Color(0.35, 1.0, 0.88)
const Look := preload("res://scripts/shared/look_def.gd")

## Acción del juego -> animación del .glb, por forma. [nombre, mantener hasta nueva orden]
const GLB_ACTIONS := {
	"alux": {"bolt": "Cast", "dodge": "Dodge", "interact": "Interact", "hit": "Hit"},
	"balam": {"claw": "Claw", "charge_start": "Charge", "charged": "ChargeRelease", "pounce": "Pounce", "pounce_land": "PounceLand", "hit": "Hit"},
}
## Velocidad (m/s) para la que se animó la carrera de cada modelo: a esa velocidad los pies no patinan.
const RUN_SPEED := {"alux": 5.2, "balam": 8.4}

var player_name := "Alux"
var color := Color("#2ec4a6")
var hat := 0
var look: Array = Look.DEFAULT.duplicate()   # vestimenta, accesorio, amuleto, color secundario, piel
var form := "alux"
## Formas que se cargan. En la plaza social nadie se transforma: basta el alux (la mitad de modelos).
var forms: Array = ["alux", "balam"]
var online := true
var dead := false
var uses_glb := false
var is_local := false        # el personaje de este jugador: sin nombre encima y con los sonidos más presentes

var _models := {}            # forma -> Node3D
var _players := {}           # forma -> AnimationPlayer (sólo .glb)
var _label: Label3D
var _phase := 0.0
var _alux_limbs: Array[Node3D] = []
var _balam_legs: Array[Node3D] = []
var _balam_tail: Node3D
var _last_pos := Vector3.ZERO
var _has_last := false
var _act := ""
var _act_t := 0.0
var _act_dur := 0.0
var _hold := ""              # animación que se mantiene (carga, salto ofensivo)
var _morph := 1.0
var _loco := ""
var _squash := 0.0
var _was_grounded := true
var _speed := 0.0
var _stride := 0.0
var _was_swim := false


func setup(p_name: String, color_hex: String, p_hat: int, p_look: Variant = null) -> void:
	player_name = p_name
	color = Color.from_string(color_hex, Color("#2ec4a6"))
	hat = clampi(p_hat, 0, Look.HATS.size() - 1)
	look = Look.clean(p_look)
	for c in get_children():
		c.queue_free()
	_alux_limbs.clear()
	_balam_legs.clear()
	_models.clear()
	_players.clear()
	uses_glb = true
	for f in forms:
		var m := _load_glb(f)
		if m == null:
			uses_glb = false
			m = _build_alux() if f == "alux" else _build_balam()
		_models[f] = m
		add_child(m)
	_label = Label3D.new()
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.no_depth_test = true
	_label.fixed_size = false
	# Nombre discreto: se lee de cerca y no tapa la escena
	_label.pixel_size = 0.0042
	_label.font_size = 34
	_label.outline_size = 10
	_label.outline_modulate = Color(0.05, 0.08, 0.07, 0.9)
	add_child(_label)
	_apply()


# ───────────────────────── Modelos .glb ─────────────────────────

func _load_glb(f: String) -> Node3D:
	var path := "res://assets/characters/%s.glb" % f
	if not ResourceLoader.exists(path):
		return null
	var scene := load(path) as PackedScene
	if scene == null:
		return null
	var inst := scene.instantiate() as Node3D
	if inst == null:
		return null
	var players := inst.find_children("*", "AnimationPlayer", true, false)
	if players.is_empty():
		inst.free()
		return null
	var ap := players[0] as AnimationPlayer
	for n in ["Idle", "Run", "Fall", "Swim", "Charge"]:
		if ap.has_animation(n):
			ap.get_animation(n).loop_mode = Animation.LOOP_LINEAR
	_players[f] = ap
	# Colores del jugador: el principal en la túnica (alux) y en el collar (Balam); en el alux,
	# además, el secundario en ribetes y telas añadidas y el tono de piel
	var target := "Tunic" if f == "alux" else "Collar"
	var accent := Color.from_string(str(Look.ACCENTS[int(look[Look.ACCENT])]), Color.WHITE)
	var skin := Color.from_string(str(Look.SKINS[int(look[Look.SKIN])]), SKIN)
	for mi in inst.find_children("*", "MeshInstance3D", true, false):
		var mesh := (mi as MeshInstance3D).mesh
		if mesh == null:
			continue
		for i in mesh.get_surface_count():
			var mat := mesh.surface_get_material(i)
			if not (mat is StandardMaterial3D):
				continue
			var mat_name := str(mat.resource_name)
			var tint: Variant = null
			if mat_name.begins_with(target):
				tint = color
			elif f == "alux" and mat_name.begins_with("Trim"):
				tint = accent
			elif f == "alux" and mat_name.begins_with("Skin"):
				# La piel lleva sus matices en el vértice; el tono medio va en gris 0,75 para que el
				# rubor y las palmas, que son más claros, quepan. Por eso el tinte es el tono × 4/3,
				# y × 1,12 más para aclararla como al resto del cuerpo.
				var k := 1.12 * 4.0 / 3.0
				tint = Color(skin.r * k, skin.g * k, skin.b * k)
			elif mat_name == "Body" or mat_name == "Headwear":
				# El color vive en los vértices: se aclara un poco el conjunto para que la cara
				# se lea a la sombra del sombrero y de los árboles (sin textura ni luz extra)
				tint = Color(1.12, 1.12, 1.12)
			if tint != null:
				var own := mat.duplicate() as StandardMaterial3D
				own.albedo_color = tint
				(mi as MeshInstance3D).set_surface_override_material(i, own)
	if f == "alux":
		# Tocado (el cabello va también bajo el sombrero y el penacho: sin él la nuca queda calva)
		var keep: Array = Look.HATS[hat][1]
		for n in Look.HAT_NODES:
			for node in inst.find_children(n + "*", "Node3D", true, false):
				(node as Node3D).visible = keep.has(n)
		# Vestimenta, accesorio y amuleto: de cada familia se ve sólo la pieza elegida
		for family in [[Look.OUTFITS, Look.OUTFIT], [Look.ACCESSORIES, Look.ACCESSORY], [Look.AMULETS, Look.AMULET]]:
			var chosen := str(family[0][int(look[family[1]])][1])
			for option in family[0]:
				var prefix := str(option[1])
				if prefix.is_empty():
					continue
				for node in inst.find_children(prefix + "*", "Node3D", true, false):
					(node as Node3D).visible = prefix == chosen
	ap.play("Idle")
	return inst


# ───────────────────────── Personalizador ─────────────────────────

## ¿Trae el modelo del alux alguna pieza cuyo nodo empiece por `prefix`? (el personalizador sólo
## ofrece lo que existe de verdad)
func has_part(prefix: String) -> bool:
	var m: Node3D = _models.get("alux")
	return m != null and not m.find_children(prefix + "*", "Node3D", true, false).is_empty()


## ¿Tiene el modelo del alux un material cuyo nombre empiece por `prefix`?
func has_material(prefix: String) -> bool:
	var m: Node3D = _models.get("alux")
	if m == null:
		return false
	for mi in m.find_children("*", "MeshInstance3D", true, false):
		var mesh := (mi as MeshInstance3D).mesh
		if mesh == null:
			continue
		for i in mesh.get_surface_count():
			var mat := mesh.surface_get_material(i)
			if mat != null and str(mat.resource_name).begins_with(prefix):
				return true
	return false


## Vista previa de una animación del alux (reposo, carrera, salto) sin pasar por el juego.
func preview_anim(anim: String) -> void:
	var ap: AnimationPlayer = _players.get("alux")
	if ap == null or not ap.has_animation(anim):
		return
	ap.speed_scale = 1.0
	if anim == "Jump":
		ap.get_animation(anim).loop_mode = Animation.LOOP_LINEAR
	ap.play(anim, 0.15)


# ───────────────────────── Estado ─────────────────────────

func set_form(f: String, with_effect := true) -> void:
	if f == form:
		return
	form = f
	_act = ""
	_hold = ""
	_loco = ""
	_apply()
	if with_effect:
		# Transformación: el modelo nuevo brota girando dentro de una columna de luz
		_morph = 0.0
		var gold := Color(1.0, 0.72, 0.25)
		Fx.transform_burst(get_parent(), global_position, gold if form == "balam" else EYE, color.lightened(0.25))
		Audio.play("transformar", global_position, 0.0 if is_local else -6.0)
		if form == "balam":
			Audio.play("balam_grunido", global_position, -1.0 if is_local else -7.0)   # (el acorde de la transformación lo tapaba)
		if _players.has(form) and (_players[form] as AnimationPlayer).has_animation("Transform"):
			(_players[form] as AnimationPlayer).speed_scale = 1.0
			(_players[form] as AnimationPlayer).play("Transform", 0.0)
			_act = "transform"
			_act_t = 0.0
			_act_dur = (_players[form] as AnimationPlayer).get_animation("Transform").length


func set_online(on: bool) -> void:
	if on == online:
		return
	online = on
	_apply()


func set_dead(d: bool) -> void:
	if d == dead:
		return
	dead = d
	_act = ""
	_hold = ""
	_loco = ""
	if dead and _players.has(form):
		var ap: AnimationPlayer = _players[form]
		if ap.has_animation("Death"):
			ap.speed_scale = 1.0
			ap.play("Death", 0.1)
	_apply()


func _apply() -> void:
	if _label == null:
		return
	for f in _models:
		var on: bool = online and f == form
		(_models[f] as Node3D).visible = on
		if _players.has(f):
			(_players[f] as AnimationPlayer).active = on  # la forma oculta no gasta animación
	var suffix := ""
	if not online:
		suffix = " (desconectado)"
	elif dead:
		suffix = " (caído)"
	_label.text = player_name + suffix
	_label.modulate = Color(1, 1, 1, 0.9) if online and not dead else Color(1, 1, 1, 0.5)
	_label.position.y = 2.0 if form == "alux" else 1.7
	# el propio nombre no hace falta (ya está en el panel de grupo), salvo caído o desconectado
	_label.visible = not is_local or dead or not online


## Reproduce una acción de combate (la decide el servidor o la predicción local).
func play_action(kind: String) -> void:
	if dead:
		return
	match kind:
		"charge_start":
			_hold = "charge"
		"charged", "charge_cancel":
			_hold = ""
		"pounce":
			_hold = "pounce"
		"pounce_land":
			_hold = ""
	var durations := {"bolt": 0.3, "dodge": 0.22, "interact": 0.5, "hit": 0.25, "claw": 0.3, "charged": 0.42, "pounce": 0.5, "pounce_land": 0.36}
	if durations.has(kind):
		_act = kind
		_act_t = 0.0
		_act_dur = durations[kind]
	if _players.has(form):
		var ap: AnimationPlayer = _players[form]
		var anim: String = GLB_ACTIONS[form].get(kind, "")
		if anim != "" and ap.has_animation(anim):
			ap.speed_scale = 1.0
			ap.play(anim, 0.06)
			ap.seek(0.0, true)
			_loco = ""


## Animación según lo que se movió desde el cuadro anterior.
func animate(delta: float, grounded: bool, swim: bool) -> void:
	var speed := 0.0
	var rising := false
	if _has_last and delta > 0.0:
		var d := global_position - _last_pos
		speed = Vector2(d.x, d.z).length() / delta
		rising = d.y > 0.0
	_speed = lerpf(_speed, speed, minf(1.0, delta * 10.0))
	_last_pos = global_position
	# Pasos: uno cada cierto tramo recorrido en el suelo
	if grounded and not swim and not dead and speed > 1.0 and speed < 30.0:
		_stride += speed * delta
		if _stride > (1.5 if form == "alux" else 2.3):
			_stride = 0.0
			# el paso suena a lo que se pisa: hierba, losa o agua somera (con el paso genérico de respaldo)
			Audio.play("paso_%s_1|paso_1" % Audio.ground_at(global_position), global_position, 4.0 if is_local else -5.0, 0.12)
	if swim != _was_swim:
		_was_swim = swim
		if _has_last:
			Audio.play("chapoteo", global_position, 0.0 if is_local else -8.0)
	_has_last = true
	var moving := speed > 0.4
	if _act != "":
		_act_t += delta
		if _act_t >= _act_dur:
			_act = ""
	var model: Node3D = _models.get(form)
	if model == null:
		return

	# Estirar al despegar y aplastar al caer (se recupera solo)
	if grounded != _was_grounded and not swim:
		_squash = -0.2 if grounded else 0.16
		if grounded:
			_play_glb_once("Land")
			Audio.play("aterrizar", global_position, -3.0 if is_local else -12.0)
		elif rising:
			_play_glb_once("Jump")
			Audio.play("salto", global_position, -3.0 if is_local else -12.0)
	_was_grounded = grounded
	_squash = lerpf(_squash, 0.0, minf(1.0, delta * 9.0))
	var stretch := Vector3(1.0 - _squash * 0.5, 1.0 + _squash, 1.0 - _squash * 0.5)

	# Transformación: el modelo crece girando
	if _morph < 1.0:
		_morph = minf(1.0, _morph + delta / 0.36)
		var k := 1.0 - pow(1.0 - _morph, 3.0)
		model.scale = stretch * (0.2 + 0.8 * k + sin(_morph * PI) * 0.22)
		model.rotation.y = (1.0 - k) * TAU * 1.5
	else:
		model.scale = stretch
		model.rotation.y = 0.0

	if _players.has(form):
		_animate_glb(_players[form], moving, grounded, swim)
		return

	# ── Modelos de respaldo (primitivas) ──
	_phase += delta * (4.0 + speed * 1.6) if moving else 0.0
	var swing := sin(_phase) * (0.75 if moving else 0.0)
	var bob := absf(sin(_phase)) * 0.05 if moving and grounded else 0.0
	var k_act := sin(clampf(_act_t / maxf(_act_dur, 0.01), 0.0, 1.0) * PI) if _act != "" else 0.0
	if form == "alux":
		var tilt := 0.5 if swim else (0.12 if moving else 0.0)
		var y := bob - (0.35 if swim else 0.0)
		if dead:
			tilt = -1.45
			y = 0.2
		elif _act == "dodge":
			tilt = TAU * clampf(_act_t / _act_dur, 0.0, 1.0)
			y += 0.25 * k_act
		elif _act == "hit":
			tilt = -0.35 * k_act
		model.position.y = y
		model.rotation.x = tilt if _act == "dodge" else lerp_angle(model.rotation.x, tilt, minf(1.0, delta * 12.0))
		if _alux_limbs.size() == 4:
			var air := 0.0 if grounded or swim else 0.9
			_alux_limbs[0].rotation.x = swing + air
			_alux_limbs[1].rotation.x = -swing + air
			_alux_limbs[2].rotation.x = -swing - air * 1.4
			_alux_limbs[3].rotation.x = swing - air * 1.4
			if _act == "bolt":
				_alux_limbs[3].rotation.x = -1.7 * k_act
			elif _act == "interact":
				_alux_limbs[2].rotation.x = -1.3 * k_act
				_alux_limbs[3].rotation.x = -1.3 * k_act
	else:
		var tilt := 0.0
		var y := bob * 1.4 - (0.3 if swim else 0.0)
		var roll := 0.0
		var squash := 1.0
		if dead:
			roll = 1.45
			y = 0.1
		elif _hold == "charge":
			squash = 0.82
			tilt = 0.18
			model.position.x = sin(Time.get_ticks_msec() * 0.06) * 0.02
		elif _hold == "pounce":
			tilt = -0.45
		elif _act == "claw":
			tilt = -0.3 * k_act
		elif _act == "charged":
			tilt = -0.6 * k_act
			y += 0.2 * k_act
		elif _act == "hit":
			tilt = 0.3 * k_act
		if _hold != "charge":
			model.position.x = 0.0
		model.position.y = y
		model.rotation.x = lerp_angle(model.rotation.x, tilt, minf(1.0, delta * 14.0))
		model.rotation.z = lerp_angle(model.rotation.z, roll, minf(1.0, delta * 8.0))
		model.scale.y *= squash
		for i in _balam_legs.size():
			var s := swing if (i == 0 or i == 3) else -swing
			var r := s * 0.9 if grounded or swim else (0.9 if i < 2 else -0.9)
			if i < 2 and (_act == "claw" or _act == "charged"):
				r = -1.5 * k_act
			if _hold == "pounce":
				r = -1.2 if i < 2 else 1.0
			_balam_legs[i].rotation.x = r
		if _balam_tail:
			_balam_tail.rotation.y = sin(Time.get_ticks_msec() * 0.004) * 0.4


## Reproduce una animación corta del .glb si existe (aterrizaje, impacto…).
func _play_glb_once(anim: String) -> void:
	if dead or not _players.has(form) or _hold != "":
		return
	var ap: AnimationPlayer = _players[form]
	if not ap.has_animation(anim) or (_act != "" and _act != "land"):
		return
	ap.speed_scale = 1.0
	ap.play(anim, 0.04)
	_act = "land"
	_act_t = 0.0
	_act_dur = ap.get_animation(anim).length
	_loco = ""


func _animate_glb(ap: AnimationPlayer, moving: bool, grounded: bool, swim: bool) -> void:
	if dead:
		return
	if _hold == "charge" or _hold == "pounce":
		return  # la animación mantenida ya está sonando
	if _act != "" and ap.is_playing() and not ["Idle", "Run", "Fall", "Swim", "Jump"].has(str(ap.current_animation)):
		return  # dejar terminar la acción
	var want := "Idle"
	if swim:
		want = "Swim"
	elif not grounded:
		want = "Fall"
	elif moving:
		want = "Run"
	if want != _loco and ap.has_animation(want):
		_loco = want
		ap.play(want, 0.14)
	# La carrera se reproduce al ritmo de la velocidad real: así el pie apoyado no patina
	if _loco == "Run":
		ap.speed_scale = clampf(_speed / float(RUN_SPEED.get(form, 5.2)), 0.55, 1.5)
	else:
		ap.speed_scale = 1.0


# ───────────────────────── Modelos de respaldo (primitivas) ─────────────────────────

static func mat(c: Color, emission := 0.0, rough := 0.85) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	if emission > 0.0:
		m.emission_enabled = true
		m.emission = c
		m.emission_energy_multiplier = emission
	return m


static func part(mesh: Mesh, material: Material, pos: Vector3, rot := Vector3.ZERO, scl := Vector3.ONE) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = material
	mi.position = pos
	mi.rotation = rot
	mi.scale = scl
	return mi


static func _sphere(r: float) -> SphereMesh:
	var s := SphereMesh.new()
	s.radius = r
	s.height = r * 2.0
	s.radial_segments = 20
	s.rings = 10
	return s


static func _capsule(r: float, h: float) -> CapsuleMesh:
	var c := CapsuleMesh.new()
	c.radius = r
	c.height = h
	c.radial_segments = 14
	c.rings = 4
	return c


static func _cone(top: float, bottom: float, h: float, seg := 20) -> CylinderMesh:
	var c := CylinderMesh.new()
	c.top_radius = top
	c.bottom_radius = bottom
	c.height = h
	c.radial_segments = seg
	c.rings = 1
	return c


## Extremidad con el pivote arriba, para poder balancearla.
static func _limb(r: float, h: float, material: Material, pos: Vector3) -> Node3D:
	var pivot := Node3D.new()
	pivot.position = pos
	pivot.add_child(part(_capsule(r, h), material, Vector3(0, -h * 0.5 + r, 0)))
	return pivot


func _build_alux() -> Node3D:
	var root := Node3D.new()
	var skin := mat(SKIN)
	var tunic := mat(color)
	var tunic_light := mat(color.lightened(0.25))
	var gold := mat(Color(0.95, 0.75, 0.25), 0.15, 0.4)
	var eye := mat(EYE, 1.5, 0.2)

	var leg_l := _limb(0.09, 0.36, skin, Vector3(0.12, 0.36, 0))
	var leg_r := _limb(0.09, 0.36, skin, Vector3(-0.12, 0.36, 0))
	var arm_l := _limb(0.07, 0.36, skin, Vector3(0.3, 0.78, 0))
	var arm_r := _limb(0.07, 0.36, skin, Vector3(-0.3, 0.78, 0))
	for l in [leg_l, leg_r, arm_l, arm_r]:
		root.add_child(l)
		_alux_limbs.append(l)

	root.add_child(part(_cone(0.2, 0.34, 0.5), tunic, Vector3(0, 0.55, 0)))
	root.add_child(part(_cone(0.24, 0.33, 0.2, 12), tunic_light, Vector3(0, 0.72, 0)))
	root.add_child(part(_cone(0.26, 0.27, 0.06), gold, Vector3(0, 0.52, 0)))

	root.add_child(part(_sphere(0.3), skin, Vector3(0, 1.03, 0)))
	root.add_child(part(_sphere(0.085), eye, Vector3(0.115, 1.06, 0.245)))
	root.add_child(part(_sphere(0.085), eye, Vector3(-0.115, 1.06, 0.245)))
	# orejas puntiagudas
	for side in [1.0, -1.0]:
		root.add_child(part(_cone(0.0, 0.09, 0.3, 8), skin, Vector3(0.36 * side, 1.08, -0.02), Vector3(0, 0, -1.25 * side)))

	match hat:
		0:
			root.add_child(part(_cone(0.03, 0.52, 0.4, 16), mat(STRAW), Vector3(0, 1.42, 0)))
			root.add_child(part(_cone(0.5, 0.53, 0.04, 16), mat(STRAW.darkened(0.2)), Vector3(0, 1.22, 0)))
		1:
			root.add_child(part(_cone(0.3, 0.31, 0.08), gold, Vector3(0, 1.25, 0)))
			var box := BoxMesh.new()
			box.size = Vector3(0.1, 0.5, 0.03)
			for i in 7:
				var a := (float(i) - 3.0) * 0.28
				var fc := color if i % 2 == 0 else Color(0.95, 0.85, 0.3)
				root.add_child(part(box, mat(fc), Vector3(sin(a) * 0.3, 1.45 + cos(a) * 0.14, -0.1), Vector3(-0.25, 0, -a)))
		2:
			root.add_child(part(_sphere(0.31), mat(Color(0.12, 0.09, 0.08)), Vector3(0, 1.08, -0.03), Vector3.ZERO, Vector3(1, 0.85, 1)))
			for i in 5:
				var a := float(i) / 5.0 * TAU
				root.add_child(part(_sphere(0.07), mat(Color(1, 0.95, 0.9)), Vector3(0.2 + cos(a) * 0.07, 1.3 + sin(a) * 0.07, 0.12)))
			root.add_child(part(_sphere(0.05), mat(Color(1, 0.8, 0.2), 0.6), Vector3(0.2, 1.3, 0.15)))
		_:
			root.add_child(part(_sphere(0.31), mat(Color(0.12, 0.09, 0.08)), Vector3(0, 1.08, -0.03), Vector3.ZERO, Vector3(1, 0.85, 1)))
	return root


func _build_balam() -> Node3D:
	var root := Node3D.new()
	var fur := mat(Color(0.93, 0.6, 0.2))
	var cream := mat(Color(0.98, 0.9, 0.72))
	var dark := mat(Color(0.2, 0.12, 0.06))
	var eye := mat(EYE, 1.5, 0.2)
	var collar := mat(color, 0.4)

	root.add_child(part(_capsule(0.3, 1.25), fur, Vector3(0, 0.66, 0), Vector3(PI * 0.5, 0, 0)))
	root.add_child(part(_capsule(0.24, 1.0), cream, Vector3(0, 0.56, 0), Vector3(PI * 0.5, 0, 0), Vector3(0.9, 1, 0.8)))
	root.add_child(part(_sphere(0.3), fur, Vector3(0, 0.92, 0.66)))
	root.add_child(part(_sphere(0.16), cream, Vector3(0, 0.83, 0.9)))
	root.add_child(part(_sphere(0.05), dark, Vector3(0, 0.88, 1.04)))
	root.add_child(part(_sphere(0.07), eye, Vector3(0.13, 0.99, 0.9)))
	root.add_child(part(_sphere(0.07), eye, Vector3(-0.13, 0.99, 0.9)))
	root.add_child(part(_cone(0.0, 0.1, 0.16, 8), fur, Vector3(0.19, 1.2, 0.6)))
	root.add_child(part(_cone(0.0, 0.1, 0.16, 8), fur, Vector3(-0.19, 1.2, 0.6)))

	var torus := TorusMesh.new()
	torus.inner_radius = 0.25
	torus.outer_radius = 0.34
	torus.rings = 20
	torus.ring_segments = 8
	root.add_child(part(torus, collar, Vector3(0, 0.78, 0.42), Vector3(PI * 0.5, 0, 0)))

	for p in [Vector3(0.2, 0.52, 0.42), Vector3(-0.2, 0.52, 0.42), Vector3(0.2, 0.52, -0.42), Vector3(-0.2, 0.52, -0.42)]:
		var leg := _limb(0.095, 0.54, fur, p)
		root.add_child(leg)
		_balam_legs.append(leg)

	_balam_tail = Node3D.new()
	_balam_tail.position = Vector3(0, 0.8, -0.6)
	_balam_tail.add_child(part(_capsule(0.055, 0.8), fur, Vector3(0, 0.2, -0.3), Vector3(-1.0, 0, 0)))
	_balam_tail.add_child(part(_sphere(0.08), dark, Vector3(0, 0.42, -0.62)))
	root.add_child(_balam_tail)

	var spots := [
		Vector3(0.24, 0.85, 0.2), Vector3(-0.25, 0.8, 0.05), Vector3(0.2, 0.9, -0.2), Vector3(-0.2, 0.9, -0.3),
		Vector3(0.0, 0.96, 0.1), Vector3(0.0, 0.96, -0.25), Vector3(0.27, 0.7, -0.05), Vector3(-0.27, 0.68, 0.3),
	]
	for s in spots:
		root.add_child(part(_sphere(0.06), dark, s, Vector3.ZERO, Vector3(1, 0.5, 1)))
	return root
