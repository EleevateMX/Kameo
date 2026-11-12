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
const STONE := Color(0.42, 0.46, 0.42)
## Animación de cada estado y si se repite.
const ANIMS := {
	"sleep": ["Sleep", true], "rise": ["Awaken", false], "idle": ["Idle", true], "walk": ["Walk", true],
	"slam_w": ["Slam", false], "sweep_w": ["Sweep", false], "summon_w": ["Summon", false],
	"recover": ["Idle", true], "kneel": ["Kneel", false], "freed": ["Remember", false],
}

var phase := Boss.ASLEEP
var state := "sleep"
var glyphs := 0
var uses_glb := false
var _anim: AnimationPlayer
var _mats := {}                 # nombre del material -> copia propia
var _goal := Vector3(Boss.HOME.x, 0.0, Boss.HOME.y)
var _goal_yaw := Boss.HOME_YAW
var _label: Label3D
var _rubble := {}               # clave de posición -> disco en el suelo
var _rubble_mat: StandardMaterial3D
var _pulse := 0.0


func setup() -> void:
	if ResourceLoader.exists(MODEL):
		var scene: PackedScene = load(MODEL)
		if scene != null:
			var model := scene.instantiate() as Node3D
			add_child(model)
			_anim = model.find_child("AnimationPlayer", true, false) as AnimationPlayer
			for n in model.find_children("*", "MeshInstance3D", true, false):
				var mi := n as MeshInstance3D
				for i in mi.mesh.get_surface_count():
					var src := mi.get_active_material(i)
					if src is StandardMaterial3D:
						var own := (src as StandardMaterial3D).duplicate() as StandardMaterial3D
						mi.set_surface_override_material(i, own)
						_mats[src.resource_name] = own
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
	var repaint := new_phase != phase or int(b[7]) != glyphs
	phase = new_phase
	glyphs = int(b[7])
	if new_state != state:
		state = new_state
		_play()
	if repaint:
		_paint()
	_label.visible = phase != Boss.ASLEEP
	_sync_rubble(b[13] if b.size() > 13 else [])


func _play() -> void:
	if _anim == null:
		return
	var a: Array = ANIMS.get(state, ["Idle", true])
	if not _anim.has_animation(a[0]):
		return
	_anim.play(a[0], 0.25)
	# Los golpes se ven desde el principio del gesto aunque el aviso llegue con algo de retraso
	if not bool(a[1]):
		_anim.seek(0.0, true)


## Glifos, ojos y vetas según la fase.
func _paint() -> void:
	for i in Boss.GLYPHS:
		var m: StandardMaterial3D = _mats.get("Glyph%d" % (i + 1))
		if m == null:
			continue
		var lit := i < glyphs or phase == Boss.FREED
		m.albedo_color = Color(1, 1, 1) if lit else Color(0.34, 0.38, 0.36)
		m.emission_enabled = lit
		m.emission = JADE
		m.emission_energy_multiplier = 2.4
	var veins: StandardMaterial3D = _mats.get("Silence")
	if veins != null:
		var e: float = [0.25, 1.7, 2.6, 0.7, 0.0][clampi(phase, 0, 4)]
		veins.emission_enabled = e > 0.0
		veins.emission = MAGENTA
		veins.emission_energy_multiplier = e
		veins.albedo_color = Color(1, 1, 1) if phase != Boss.FREED else STONE
		veins.vertex_color_use_as_albedo = phase != Boss.FREED
	var eyes: StandardMaterial3D = _mats.get("Eye")
	if eyes != null:
		var calm := phase == Boss.FREED or phase == Boss.RECUERDO
		eyes.emission_enabled = phase != Boss.ASLEEP
		eyes.emission = JADE if calm else MAGENTA
		eyes.emission_energy_multiplier = 1.6 if phase != Boss.FURIA else 2.6
		eyes.albedo_color = (JADE if calm else MAGENTA) if phase != Boss.ASLEEP else Color(0.2, 0.22, 0.22)
		eyes.vertex_color_use_as_albedo = false
	var heart: StandardMaterial3D = _mats.get("Heart")
	if heart != null:
		heart.emission_energy_multiplier = 0.5 if phase == Boss.ASLEEP else 1.4


func update_view(delta: float) -> void:
	position = position.lerp(_goal, minf(1.0, delta * 9.0))
	rotation.y = lerp_angle(rotation.y, _goal_yaw, minf(1.0, delta * 6.0))
	# Las vetas laten mientras está olvidado
	_pulse += delta
	var veins: StandardMaterial3D = _mats.get("Silence")
	if veins != null and veins.emission_enabled and phase != Boss.ASLEEP:
		var base: float = [0.25, 1.7, 2.6, 0.7, 0.0][clampi(phase, 0, 4)]
		veins.emission_energy_multiplier = base * (0.82 + 0.18 * sin(_pulse * (3.0 if phase != Boss.FURIA else 6.0)))


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
