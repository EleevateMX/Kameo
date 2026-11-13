extends Node3D
class_name BossView
## Nojoch Tuunich en pantalla. Sólo dibuja lo que dicta el servidor (estado «b» de cada instantánea):
## dónde está, qué hace, cuántos glifos tiene encendidos y en qué fase va. Diseño: docs/BOSS.md.
##
## Cada fase se distingue a la vista: dormido (ojos apagados, vetas tenues), Olvido (ojos y vetas
## magenta, glifos que se van encendiendo en jade), Furia (vetas más vivas), Recuerdo (vetas
## apagándose) y Liberado (sin vetas, ojos y glifos de jade).

const Boss := preload("res://scripts/shared/boss_def.gd")
const World := preload("res://scripts/shared/world_def.gd")
const Avatar := preload("res://scripts/client/avatar.gd")

const MODEL := "res://assets/characters/nojoch.glb"
const JADE := Color(0.24, 0.91, 0.77)
const MAGENTA := Color(1.0, 0.2, 0.61)
const SCAR := Color("#8a7460")        # las vetas apagadas quedan como cicatrices en la caliza
const EYE_OFF := Color("#2e302c")
const GLYPH_OFF := Color("#5a564b")
## Animación de cada estado y si se repite.
const ANIMS := {
	"sleep": ["Sleep", true], "rise": ["Awaken", false], "idle": ["Idle", true], "walk": ["Walk", true],
	"slam_w": ["Slam", false], "sweep_w": ["Sweep", false], "summon_w": ["Summon", false],
	"recover": ["Idle", true], "kneel": ["Kneel", false], "freed": ["Remember", false],
	"transit": ["Walk", true], "rain_w": ["Summon", false], "rain": ["Idle", true],
	"charge_w": ["Charge", true], "charge": ["Charge", true], "stunned": ["Stunned", true],
	"bound": ["Kneel", false], "ritual": ["Kneel", false],
	# Salto a la explanada: se agacha (sigue de rodillas) y en el aire levanta los brazos para caer golpeando
	"leap_w": ["Kneel", false], "leap": ["Slam", false],
}
## Velocidad de la animación en algunos estados (el resto, 1).
## (`Walk` está compuesta para 1.7 m/s: se acelera lo mismo que el paso del guardián.)
## (`Slam` golpea a los 1.2 s: en el salto se frena para que el golpe coincida con la caída.)
const SPEEDS := {"transit": 1.88, "charge_w": 0.5, "charge": 1.0, "leap": 1.2 / 1.7}

var phase := Boss.ASLEEP
var state := "sleep"
var glyphs := 0
var uses_glb := false
var _anim: AnimationPlayer
var _mats := {}                 # nombre del material -> copia propia
var _goal := Vector3(Boss.HOME.x, 0.0, Boss.HOME.y)
var _goal_yaw := Boss.HOME_YAW
var _state_t := 0.0             # segundos que le quedan al estado (lo dice el servidor; se descuenta aquí entre estados)
var _label: Label3D
var _rubble := {}               # clave de posición -> disco en el suelo
var _rubble_mat: StandardMaterial3D
var _pulse := 0.0
var _step_in := 0.0
# Cinemática: mientras dure, la pose y el aspecto los dicta el plano, no el estado del combate
var _cine := false
var _cine_look := -1
var _cine_glow := -1.0
# Rostro: las cejas y la boca no las mueve ninguna animación del cuerpo; se mezclan aquí entre
# las tres expresiones del modelo (Face_Sad, Face_Pain, Face_Serene) según la fase.
const FACE_BONES := ["Brow_L", "Brow_R", "Mouth_L", "Mouth_R"]
const FACE_BY_PHASE := ["Face_Sad", "Face_Sad", "Face_Pain", "Face_Sad", "Face_Serene"]
var calm := 0.0                 # 0–1: cuánto ha recordado ya en la fase 3 (acerca el rostro a la serenidad)
var _crack_src := {}            # valores de exportación de las grietas de la furia (Silence2)
var _skel: Skeleton3D
var _faces := {}                # expresión -> {hueso -> [posición, rotación]}
var _face_rest := {}            # hueso -> [posición, rotación]
var _face_now := {}             # hueso -> [posición, rotación] que se ve ahora mismo
var _face_flash := 0.0          # segundos de «casi recuerda» (al encenderse un glifo)

signal stepped


func setup() -> void:
	if ResourceLoader.exists(MODEL):
		var scene: PackedScene = load(MODEL)
		if scene != null:
			var model := scene.instantiate() as Node3D
			add_child(model)
			_anim = model.find_child("AnimationPlayer", true, false) as AnimationPlayer
			for n in model.find_children("*", "MeshInstance3D", true, false):
				var mi := n as MeshInstance3D
				mi.layers = 2   # capa propia: la luz de jade del cristal no lo tiñe (world_builder)
				for i in mi.mesh.get_surface_count():
					var src := mi.get_active_material(i)
					if src is StandardMaterial3D:
						var own := (src as StandardMaterial3D).duplicate() as StandardMaterial3D
						mi.set_surface_override_material(i, own)
						_mats[src.resource_name] = own
						if src.resource_name == "Silence2":
							_crack_src = {"albedo": own.albedo_color, "vertex": own.vertex_color_use_as_albedo}
			_skel = model.find_child("Skeleton3D", true, false) as Skeleton3D
			_read_faces()
			if _anim != null and not _faces.is_empty():
				_anim.mixer_applied.connect(_apply_face)
			if _anim != null:
				for name in ["Sleep", "Idle", "Walk", "Stunned", "Charge"]:
					if _anim.has_animation(name):
						_anim.get_animation(name).loop_mode = Animation.LOOP_LINEAR
				_anim.play("Sleep")
			uses_glb = true
	if not uses_glb:
		_placeholder()
	_label = Label3D.new()
	_label.text = Boss.NAME
	_label.font_size = 44
	_label.pixel_size = 0.006
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.no_depth_test = true
	_label.outline_size = 10
	_label.modulate = Color(1.0, 0.86, 0.5)
	_label.position = Vector3(0, Boss.HEIGHT + 0.7, 0)
	_label.visible = false
	add_child(_label)
	_rubble_mat = StandardMaterial3D.new()
	_rubble_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_rubble_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_rubble_mat.albedo_color = Color(0.75, 0.12, 0.42, 0.42)
	position = Vector3(Boss.HOME.x, World.terrain_h(Boss.HOME.x, Boss.HOME.y), Boss.HOME.y)
	rotation.y = Boss.HOME_YAW
	_paint()


## Lee las tres expresiones del modelo (animaciones de un cuadro) y las retira del reproductor:
## desde aquí el rostro se mezcla a mano, encima de cualquier animación del cuerpo.
func _read_faces() -> void:
	if _anim == null or _skel == null:
		return
	for bone in FACE_BONES:
		var i := _skel.find_bone(bone)
		if i >= 0:
			_face_rest[bone] = [_skel.get_bone_rest(i).origin, _skel.get_bone_rest(i).basis.get_rotation_quaternion()]
			_face_now[bone] = _face_rest[bone]
	for face in ["Face_Sad", "Face_Pain", "Face_Serene"]:
		if not _anim.has_animation(face):
			continue
		var a := _anim.get_animation(face)
		var pose := {}
		for t in a.get_track_count():
			var bone := str(a.track_get_path(t)).get_slice(":", 1)
			if not _face_rest.has(bone) or a.track_get_key_count(t) == 0:
				continue
			var cur: Array = pose.get(bone, (_face_rest[bone] as Array).duplicate())
			match a.track_get_type(t):
				Animation.TYPE_POSITION_3D:
					cur[0] = a.track_get_key_value(t, 0)
				Animation.TYPE_ROTATION_3D:
					cur[1] = a.track_get_key_value(t, 0)
			pose[bone] = cur
		_faces[face] = pose
	for lib_name in _anim.get_animation_library_list():
		var lib := _anim.get_animation_library(lib_name)
		for face in ["Face_Sad", "Face_Pain", "Face_Serene"]:
			if lib.has_animation(face):
				lib.remove_animation(face)


## Un glifo se enciende: por un instante el rostro se ablanda, como si fuera a recordar.
func flash_memory() -> void:
	_face_flash = 1.6


func has_faces() -> bool:
	return _faces.size() == 3


func _update_face(delta: float) -> void:
	if _skel == null or _faces.is_empty():
		return
	var look := _cine_look if _cine_look >= 0 else phase
	var want: String = FACE_BY_PHASE[clampi(look, 0, 4)]
	_face_flash = maxf(0.0, _face_flash - delta)
	var k := minf(1.0, delta * (1.2 if look == Boss.FREED else 3.0))
	for bone in _face_rest:
		var target: Array = (_faces.get(want, {}) as Dictionary).get(bone, _face_rest[bone])
		if look == Boss.RECUERDO and calm > 0.0 and _faces.has("Face_Serene"):
			var serene: Array = (_faces["Face_Serene"] as Dictionary).get(bone, _face_rest[bone])
			target = [(target[0] as Vector3).lerp(serene[0], calm), (target[1] as Quaternion).slerp(serene[1], calm)]
		if _face_flash > 0.0 and _faces.has("Face_Serene") and look != Boss.FREED:
			var calm: Array = (_faces["Face_Serene"] as Dictionary).get(bone, _face_rest[bone])
			var w := 0.6 * sin(clampf(_face_flash / 1.6, 0.0, 1.0) * PI)
			target = [(target[0] as Vector3).lerp(calm[0], w), (target[1] as Quaternion).slerp(calm[1], w)]
		var now: Array = _face_now[bone]
		now = [(now[0] as Vector3).lerp(target[0], k), (now[1] as Quaternion).slerp(target[1], k)]
		_face_now[bone] = now
	_apply_face()


## Escribe el rostro en el esqueleto. El reproductor devuelve a su pose de reposo los huesos que
## su animación no lleva, así que se reescribe cada vez que termina de aplicar un cuadro.
func _apply_face() -> void:
	if _skel == null:
		return
	for bone in _face_now:
		var now: Array = _face_now[bone]
		var i := _skel.find_bone(bone)
		_skel.set_bone_pose_position(i, now[0])
		_skel.set_bone_pose_rotation(i, now[1])


## Sin modelo (no debería pasar): un coloso de bloques, para que el combate siga viéndose.
func _placeholder() -> void:
	var stone := Avatar.mat(Color(0.8, 0.75, 0.62))
	for part in [[Vector3(0, 1.0, 0), Vector3(1.6, 2.0, 1.2)], [Vector3(0, 2.9, 0), Vector3(2.6, 1.9, 1.5)], [Vector3(0, 4.3, 0), Vector3(1.5, 1.1, 1.3)],
			[Vector3(1.7, 2.6, 0), Vector3(0.8, 2.6, 0.9)], [Vector3(-1.7, 2.6, 0), Vector3(0.8, 2.6, 0.9)]]:
		var box := BoxMesh.new()
		box.size = part[1]
		add_child(Avatar.part(box, stone, part[0]))


## Aplica el estado que manda el servidor (ver server/boss.gd, snapshot()).
func apply(b: Array) -> void:
	if b.size() < 10:
		return
	var new_phase := int(b[0])
	var new_state: String = Boss.STATES[clampi(int(b[4]), 0, Boss.STATES.size() - 1)]
	_goal = Vector3(float(b[1]), World.terrain_h(float(b[1]), float(b[2])), float(b[2]))
	_goal_yaw = float(b[3])
	_state_t = float(b[5])
	var repaint := new_phase != phase or int(b[7]) != glyphs
	if b.size() >= 24 and new_phase == Boss.RECUERDO:
		calm = clampf(0.35 * float(b[19]) / maxf(1.0, float(b[20])) + 0.65 * float(b[21]) / 100.0, 0.0, 1.0)
	else:
		calm = 0.0
	phase = new_phase
	glyphs = int(b[7])
	if new_state != state:
		state = new_state
		if not _cine:
			_play()
	if repaint:
		_paint()
	_label.visible = phase != Boss.ASLEEP and not _cine
	_sync_rubble(b[13] if b.size() > 13 else [])


## Pose de un plano de cinemática: animación `anim` en el segundo `t`, pintado como en la fase
## `look` y con las vetas a `glow` de brillo (negativo: el de la fase).
func cine_pose(anim: String, t: float, look: int, glow := -1.0) -> void:
	_cine = true
	_label.visible = false
	if _anim != null and _anim.has_animation(anim):
		var a := _anim.get_animation(anim)
		if _anim.current_animation != anim:
			_anim.play(anim, 0.0, 0.0)
		var at := fmod(t, a.length) if a.loop_mode != Animation.LOOP_NONE else clampf(t, 0.0, a.length - 0.02)
		_anim.seek(at, true)
	if look != _cine_look or absf(glow - _cine_glow) > 0.02:
		_cine_look = look
		_cine_glow = glow
		_paint()


func cine_release() -> void:
	if not _cine:
		return
	_cine = false
	_cine_look = -1
	_cine_glow = -1.0
	_label.visible = phase != Boss.ASLEEP
	_play()
	_paint()


func _play() -> void:
	if _anim == null:
		return
	var a: Array = ANIMS.get(state, ["Idle", true])
	if not _anim.has_animation(a[0]):
		return
	# De rodillas sigue de rodillas: no vuelve a levantarse para arrodillarse otra vez
	if not bool(a[1]) and _anim.current_animation == str(a[0]) and (not state.ends_with("_w") or state == "leap_w"):
		return
	var speed := float(SPEEDS.get(state, 1.0))
	if state == "walk" and phase == Boss.FURIA:
		speed = 1.35
	_anim.play(a[0], 0.25, speed)
	# Los golpes se ven desde el principio del gesto aunque el aviso llegue con algo de retraso
	if not bool(a[1]):
		_anim.seek(0.0, true)


## Glifos, ojos, vetas, grietas y corazón según la fase (art/propuestas/nojoch/README.md, «Estados»).
func _paint() -> void:
	var phase := _cine_look if _cine_look >= 0 else self.phase
	for i in Boss.GLYPHS:
		var m: StandardMaterial3D = _mats.get("Glyph%d" % (i + 1))
		if m == null:
			continue
		var lit := i < glyphs or phase == Boss.FREED
		m.albedo_color = Color(1, 1, 1) if lit else GLYPH_OFF
		m.emission_enabled = lit
		m.emission = JADE
		m.emission_energy_multiplier = 2.4
	var veins: StandardMaterial3D = _mats.get("Silence")
	if veins != null:
		var e: float = [0.25, 1.7, 2.6, 0.7, 0.0][clampi(phase, 0, 4)]
		if _cine_glow >= 0.0:
			e = _cine_glow
		veins.emission_enabled = e > 0.0
		veins.emission = MAGENTA
		veins.emission_energy_multiplier = e
		# Apagadas del todo quedan como cicatrices del color de la piedra
		veins.albedo_color = Color(1, 1, 1) if e > 0.0 else SCAR
		veins.vertex_color_use_as_albedo = e > 0.0
	# Las grietas de la furia sólo se ven en la fase 2
	var cracks: StandardMaterial3D = _mats.get("Silence2")
	if cracks != null and not _crack_src.is_empty():
		var on := phase == Boss.FURIA
		cracks.emission_enabled = on
		cracks.emission = MAGENTA
		cracks.emission_energy_multiplier = 2.4
		cracks.albedo_color = MAGENTA if on else _crack_src.albedo
		cracks.vertex_color_use_as_albedo = false if on else bool(_crack_src.vertex)
	var eyes: StandardMaterial3D = _mats.get("Eye")
	if eyes != null:
		var jade := phase == Boss.FREED or phase == Boss.RECUERDO
		eyes.emission_enabled = phase != Boss.ASLEEP
		eyes.emission = JADE if jade else MAGENTA
		eyes.emission_energy_multiplier = 1.6 if phase != Boss.FURIA else 2.6
		eyes.albedo_color = (JADE if jade else MAGENTA) if phase != Boss.ASLEEP else EYE_OFF
		eyes.vertex_color_use_as_albedo = false
	var heart: StandardMaterial3D = _mats.get("Heart")
	if heart != null:
		heart.emission_energy_multiplier = [0.5, 1.4, 1.4, 2.0, 2.4][clampi(phase, 0, 4)]


func update_view(delta: float) -> void:
	_update_face(delta)
	position = position.lerp(_goal, minf(1.0, delta * 9.0))
	# Salto a la explanada: el servidor lo lleva en línea recta; la altura del arco sólo se dibuja.
	# Antes de despegar se encoge (toma impulso) y al caer se aplasta un instante.
	_state_t = maxf(0.0, _state_t - delta)
	var squash := 1.0
	if state == "leap":
		var p := 1.0 - _state_t / float(Boss.LEAP.time)
		position.y = _goal.y + Boss.leap_height(p)
		squash = 1.0 + 0.08 * sin(p * PI)
	elif state == "leap_w":
		squash = 0.84 + 0.16 * clampf(_state_t / float(Boss.LEAP.windup), 0.0, 1.0)
	scale.y = lerpf(scale.y, squash, minf(1.0, delta * 10.0))
	rotation.y = lerp_angle(rotation.y, _goal_yaw, minf(1.0, delta * 6.0))
	# Las vetas laten mientras está olvidado
	_pulse += delta
	var veins: StandardMaterial3D = _mats.get("Silence")
	if veins != null and veins.emission_enabled and phase != Boss.ASLEEP and not _cine:
		var base: float = [0.25, 1.7, 2.6, 0.7, 0.0][clampi(phase, 0, 4)]
		veins.emission_energy_multiplier = base * (0.82 + 0.18 * sin(_pulse * (3.0 if phase != Boss.FURIA else 6.0)))
	# Corazón expuesto: late fuerte mientras las cadenas lo sujetan
	var heart: StandardMaterial3D = _mats.get("Heart")
	if heart != null and phase == Boss.FURIA and not _cine:
		heart.emission_energy_multiplier = 3.4 + 1.8 * sin(_pulse * 9.0) if state == "bound" else 1.4
	# Las grietas de la furia laten con las vetas
	var cracks: StandardMaterial3D = _mats.get("Silence2")
	if cracks != null and cracks.emission_enabled and not _cine:
		cracks.emission_energy_multiplier = 2.4 * (0.75 + 0.25 * sin(_pulse * 6.0))
	# Pasos: tiembla un poco el suelo mientras camina o embiste (lo oye quien esté cerca)
	if state == "walk" or state == "transit" or state == "charge":
		_step_in -= delta
		if _step_in <= 0.0:
			_step_in = 0.62 if state == "walk" else (0.4 if state == "transit" else 0.2)
			stepped.emit()


## Escombros del golpe de losa: discos en el suelo mientras duren.
func _sync_rubble(list: Array) -> void:
	var seen := {}
	for r in list:
		var key := "%.1f,%.1f" % [float(r[0]), float(r[1])]
		seen[key] = true
		if not _rubble.has(key):
			var disc := CylinderMesh.new()
			disc.top_radius = float(r[2])
			disc.bottom_radius = float(r[2])
			disc.height = 0.04
			disc.radial_segments = 20
			var mi := Avatar.part(disc, _rubble_mat, Vector3.ZERO)
			mi.top_level = true
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			add_child(mi)
			mi.global_position = Vector3(float(r[0]), World.terrain_h(float(r[0]), float(r[1])) + 0.05, float(r[1]))
			_rubble[key] = mi
	for key in _rubble.keys():
		if not seen.has(key):
			(_rubble[key] as Node).queue_free()
			_rubble.erase(key)
