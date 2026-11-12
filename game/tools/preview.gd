extends SceneTree
## Vista previa sin servidor: construye el escenario real, el HUD y unos personajes,
## y guarda capturas desde varias cámaras. Sirve para iterar el arte rápido.
##   xvfb-run -a .tools/godot --rendering-driver opengl3 --path game --resolution 1280x720 \
##       --script res://tools/preview.gd -- /carpeta/de/salida [nombres de toma…]

const WorldBuilder := preload("res://scripts/client/world_builder.gd")
const Hud := preload("res://scripts/client/hud.gd")
const Avatar := preload("res://scripts/client/avatar.gd")
const EnemyView := preload("res://scripts/client/enemy_view.gd")
const World := preload("res://scripts/shared/world_def.gd")
const Fx := preload("res://scripts/client/fx.gd")
const Story := preload("res://scripts/shared/story_def.gd")
const Cutscene := preload("res://scripts/client/cinematics/cutscene.gd")
const NpcView := preload("res://scripts/client/npc_view.gd")
const BossView := preload("res://scripts/client/boss_view.gd")
const BossArena := preload("res://scripts/client/boss_arena.gd")
const BossDef := preload("res://scripts/shared/boss_def.gd")

## nombre, objetivo de cámara, giro, inclinación, distancia, mostrar HUD
var shots := [
	["plaza", Vector3(2.6, 1.25, 2.6), PI, 0.42, 7.0, true],
	["cerca", Vector3(2.6, 1.0, 2.6), 0.2, 0.2, 3.2, false],
	["piramide", Vector3(0, 2.0, -17.0), PI, 0.25, 15.0, false],
	["santuario", Vector3(19.0, 1.6, 0.0), PI * 0.5, 0.2, 11.0, false],
	["cenote", Vector3(-17.0, 0.5, 12.0), -2.2, 0.5, 16.0, false],
	["mirador", Vector3(11.0, 1.5, 19.0), -0.5, 0.3, 11.0, false],
	["panoramica", Vector3(0, 3.0, 0), PI * 0.85, 0.62, 44.0, false],
	["horizonte", Vector3(5.0, 2.6, -3.0), 2.36, -0.08, 8.0, false],
	["brasero", Vector3(0.0, 1.6, 0.0), 2.6, 0.18, 5.5, false],
	["cine_1", Vector3.ZERO, 0.0, 0.0, 1.0, true],
	["cine_3", Vector3.ZERO, 0.0, 0.0, 1.0, true],
	["cine_4", Vector3.ZERO, 0.0, 0.0, 1.0, true],
	["dialogo", Vector3(-4.4, 1.15, 1.5), -1.94, 0.16, 4.6, true],
	["sello_1", Vector3.ZERO, 0.0, 0.0, 1.0, true],
	["sello_2", Vector3.ZERO, 0.0, 0.0, 1.0, true],
	["ref_yaxche", Vector3(-5.2, 0.95, 1.2), 1.2 + PI + 0.25, 0.08, 2.9, false],
	["objetivo_yaxche", Vector3(2.6, 1.25, 2.6), PI, 0.42, 7.0, true],
	["bienvenida", Vector3(2.6, 1.25, 2.6), PI, 0.42, 7.0, true],
	["menu", Vector3(2.6, 1.25, 2.6), PI, 0.42, 7.0, true],
	["esperando", Vector3(2.6, 1.25, 2.6), PI, 0.42, 7.0, true],
	["reconectando", Vector3(2.6, 1.25, 2.6), PI, 0.42, 7.0, true],
	# Cuadros limpios (sin nombres ni interfaz) para usar como referencia o primer cuadro de un vídeo
	["ref_balam", Vector3(-3.4, 0.7, -1.6), 0.9 + PI - 0.75, 0.1, 3.4, false],
	["ref_alux", Vector3(2.6, 0.9, 2.6), 0.3 + PI - 0.35, 0.08, 2.6, false],
	["retrato_alux", Vector3(2.6, 0.95, 2.6), 0.3 + PI - 0.35, 0.1, 2.3, false],
	["retrato_balam", Vector3(-3.4, 0.75, -1.6), 0.9 + PI - 0.6, 0.12, 2.9, false],
	# Nojoch Tuunich en el patio: dormido, en la fase 1 con la interfaz, y cuadros clave de sus escenas
	["jefe_dormido", Vector3.ZERO, 0.0, 0.0, 1.0, false],
	["jefe_fase1", Vector3.ZERO, 0.0, 0.0, 1.0, true],
	["jefe_cerca", Vector3.ZERO, 0.0, 0.0, 1.0, false],
	# Fases 2 y 3 en la explanada, con la interfaz, y el guardián liberado con la Pluma de Jade
	["jefe_fase2", Vector3.ZERO, 0.0, 0.0, 1.0, true],
	["jefe_embestida", Vector3.ZERO, 0.0, 0.0, 1.0, true],
	["jefe_corazon", Vector3.ZERO, 0.0, 0.0, 1.0, true],
	["jefe_fase3", Vector3.ZERO, 0.0, 0.0, 1.0, true],
	["jefe_contacto", Vector3.ZERO, 0.0, 0.0, 1.0, true],
	["jefe_liberado", Vector3.ZERO, 0.0, 0.0, 1.0, false],
	# Cuadros clave de las dos cinemáticas del jefe (docs/BOSS.md)
	["kf_despertar_1a", Vector3.ZERO, 0.0, 0.0, 1.0, false],
	["kf_despertar_1b", Vector3.ZERO, 0.0, 0.0, 1.0, false],
	["kf_despertar_2a", Vector3.ZERO, 0.0, 0.0, 1.0, false],
	["kf_despertar_2b", Vector3.ZERO, 0.0, 0.0, 1.0, false],
	["kf_despertar_3a", Vector3.ZERO, 0.0, 0.0, 1.0, false],
	["kf_despertar_3b", Vector3.ZERO, 0.0, 0.0, 1.0, false],
	["kf_despertar_4a", Vector3.ZERO, 0.0, 0.0, 1.0, false],
	["kf_despertar_4b", Vector3.ZERO, 0.0, 0.0, 1.0, false],
	["kf_liberacion_1a", Vector3.ZERO, 0.0, 0.0, 1.0, false],
	["kf_liberacion_1b", Vector3.ZERO, 0.0, 0.0, 1.0, false],
	["kf_liberacion_2a", Vector3.ZERO, 0.0, 0.0, 1.0, false],
	["kf_liberacion_2b", Vector3.ZERO, 0.0, 0.0, 1.0, false],
	["kf_liberacion_3a", Vector3.ZERO, 0.0, 0.0, 1.0, false],
	["kf_liberacion_3b", Vector3.ZERO, 0.0, 0.0, 1.0, false],
	# El santuario unos segundos después de romperse el sello: lo que queda de la cinemática
	["secuelas_1", Vector3.ZERO, 0.0, 0.0, 1.0, false],
	["secuelas_2", Vector3.ZERO, 0.0, 0.0, 1.0, false],
	["secuelas_3", Vector3.ZERO, 0.0, 0.0, 1.0, false],
	# Cuadros clave de «El sello cede» (ver KEYFRAMES): primer y último cuadro de cada plano
	["kf_sello_1a", Vector3.ZERO, 0.0, 0.0, 1.0, false],
	["kf_sello_1b", Vector3.ZERO, 0.0, 0.0, 1.0, false],
	["kf_sello_2a", Vector3.ZERO, 0.0, 0.0, 1.0, false],
	["kf_sello_2b", Vector3.ZERO, 0.0, 0.0, 1.0, false],
	["kf_sello_3a", Vector3.ZERO, 0.0, 0.0, 1.0, false],
	["kf_sello_3b", Vector3.ZERO, 0.0, 0.0, 1.0, false],
	["combate", Vector3(14.0, 1.2, -1.0), PI * 0.5, 0.35, 8.0, true],
	["victoria", Vector3(14.0, 1.2, -1.0), PI * 0.5, 0.35, 8.0, true],
	["derrota", Vector3(14.0, 1.2, -1.0), PI * 0.5, 0.35, 8.0, true],
]
## Cuadros clave para producir vídeos (docs/CINEMATICS.md): la cámara exacta del principio (a) y
## del final (b) de cada plano, sin interfaz ni jugadores (su aspecto lo elige cada quien, así que
## no pueden salir en un vídeo). gate: 0 sellado, 1 abierto. foes: enemigos a la vista.
const KEYFRAMES := {
	# boss: [fase, x, z, giro, estado, t, silencio, glifos, necesarios, objetivo, golpeX, golpeZ, giroBarrido, escombros]
	"jefe_dormido": {"pos": Vector3(21.2, 2.2, 0.6), "look": Vector3(31.5, 2.2, 0.0), "gate": 1.0, "foes": false, "after": 60.0,
		"boss": [0, 32.0, 0.0, -1.5708, 0, 0.0, 100, 0, 3, -1, 0.0, 0.0, 0.0, []]},
	"jefe_fase1": {"pos": Vector3(22.6, 3.4, -3.4), "look": Vector3(29.5, 2.0, 0.6), "gate": 1.0, "foes": false, "after": 60.0,
		"boss": [1, 29.6, 0.8, -1.9, 4, 0.6, 100, 2, 3, 0, 26.2, -0.6, 0.0, [[27.0, 2.6, 2.4, 8.0]]], "t": 0.9},
	"jefe_cerca": {"pos": Vector3(27.6, 2.9, 2.2), "look": Vector3(30.2, 3.4, 0.2), "gate": 1.0, "foes": false, "after": 60.0,
		"boss": [1, 30.4, 0.0, -1.2, 2, 0.0, 100, 2, 3, 0, 0.0, 0.0, 0.0, []], "t": 1.0},
	# «El despertar de Nojoch Tuunich»: la estatua, las grietas del pecho, los ojos y de pie
	# Las dos cinemáticas del jefe salen del propio guion (Story.CUTSCENES): primer y último cuadro de cada plano
	"kf_despertar_1a": {"cine": ["despertar", 0, 0.0], "gate": 1.0, "foes": false, "after": 60.0, "boss": [0, 32.0, 0.0, -1.5708, 0, 0.0, 100, 0, 3, -1, 0.0, 0.0, 0.0, []]},
	"kf_despertar_1b": {"cine": ["despertar", 0, 1.0], "gate": 1.0, "foes": false, "after": 60.0, "boss": [0, 32.0, 0.0, -1.5708, 0, 0.0, 100, 0, 3, -1, 0.0, 0.0, 0.0, []]},
	"kf_despertar_2a": {"cine": ["despertar", 1, 0.0], "gate": 1.0, "foes": false, "after": 60.0, "boss": [0, 32.0, 0.0, -1.5708, 0, 0.0, 100, 0, 3, -1, 0.0, 0.0, 0.0, []]},
	"kf_despertar_2b": {"cine": ["despertar", 1, 1.0], "gate": 1.0, "foes": false, "after": 60.0, "boss": [0, 32.0, 0.0, -1.5708, 0, 0.0, 100, 0, 3, -1, 0.0, 0.0, 0.0, []]},
	"kf_despertar_3a": {"cine": ["despertar", 2, 0.0], "gate": 1.0, "foes": false, "after": 60.0, "boss": [1, 32.0, 0.0, -1.5708, 1, 0.0, 100, 0, 3, -1, 0.0, 0.0, 0.0, []]},
	"kf_despertar_3b": {"cine": ["despertar", 2, 1.0], "gate": 1.0, "foes": false, "after": 60.0, "boss": [1, 32.0, 0.0, -1.5708, 1, 0.0, 100, 0, 3, -1, 0.0, 0.0, 0.0, []]},
	"kf_despertar_4a": {"cine": ["despertar", 3, 0.0], "gate": 1.0, "foes": false, "after": 60.0, "boss": [1, 32.0, 0.0, -1.5708, 1, 0.0, 100, 0, 3, -1, 0.0, 0.0, 0.0, []]},
	"kf_despertar_4b": {"cine": ["despertar", 3, 1.0], "gate": 1.0, "foes": false, "after": 60.0, "boss": [1, 32.0, 0.0, -1.5708, 1, 0.0, 100, 0, 3, -1, 0.0, 0.0, 0.0, []]},
	"kf_liberacion_1a": {"cine": ["liberacion", 0, 0.0], "gate": 1.0, "foes": false, "after": 60.0, "boss": [4, 15.5, 0.0, -1.5708, 9, 0.0, 0, 4, 4, -1, 0.0, 0.0, 0.0, [], 0, 1, [], 0, 3, 3, 3, 100, 0, 3]},
	"kf_liberacion_1b": {"cine": ["liberacion", 0, 1.0], "gate": 1.0, "foes": false, "after": 60.0, "boss": [4, 15.5, 0.0, -1.5708, 9, 0.0, 0, 4, 4, -1, 0.0, 0.0, 0.0, [], 0, 1, [], 0, 3, 3, 3, 100, 0, 3]},
	"kf_liberacion_2a": {"cine": ["liberacion", 1, 0.0], "gate": 1.0, "foes": false, "after": 60.0, "boss": [4, 15.5, 0.0, -1.5708, 9, 0.0, 0, 4, 4, -1, 0.0, 0.0, 0.0, [], 0, 1, [], 0, 3, 3, 3, 100, 0, 3]},
	"kf_liberacion_2b": {"cine": ["liberacion", 1, 1.0], "gate": 1.0, "foes": false, "after": 60.0, "boss": [4, 15.5, 0.0, -1.5708, 9, 0.0, 0, 4, 4, -1, 0.0, 0.0, 0.0, [], 0, 1, [], 0, 3, 3, 3, 100, 0, 3]},
	"kf_liberacion_3a": {"cine": ["liberacion", 2, 0.0], "gate": 1.0, "foes": false, "after": 60.0, "boss": [4, 15.5, 0.0, -1.5708, 9, 0.0, 0, 4, 4, -1, 0.0, 0.0, 0.0, [], 0, 1, [], 0, 3, 3, 3, 100, 0, 3]},
	"kf_liberacion_3b": {"cine": ["liberacion", 2, 1.0], "gate": 1.0, "foes": false, "after": 60.0, "boss": [4, 15.5, 0.0, -1.5708, 9, 0.0, 0, 4, 4, -1, 0.0, 0.0, 0.0, [], 0, 1, [], 0, 3, 3, 3, 100, 0, 3]},
	# Fases 2 y 3 en la explanada
	"jefe_fase2": {"pos": Vector3(6.6, 5.2, 6.4), "look": Vector3(15.0, 1.6, 0.0), "gate": 1.0, "foes": false, "after": 60.0,
		"boss": [2, 16.4, 0.6, -1.9, 2, 0.4, 66, 3, 3, 0, 0.0, 0.0, 0.0, [], 0, 1, [[0, 40.0], [1, 44.0], [5, 30.0]], 100, 0, 0, 1, 0, 0, 1]},
	"jefe_embestida": {"pos": Vector3(7.0, 3.4, -6.6), "look": Vector3(14.6, 1.6, -1.2), "gate": 1.0, "foes": false, "after": 60.0,
		"boss": [2, 18.6, 1.4, -2.16, 14, 0.4, 55, 3, 3, 0, 0.0, 0.0, -2.16, [], 0, 1, [[0, 40.0], [1, 44.0]], 100, 1, 0, 1, 0, 0, 1], "anim": ["Charge", 0.2]},
	"jefe_corazon": {"pos": Vector3(19.6, 4.4, -5.6), "look": Vector3(13.6, 2.2, -1.6), "gate": 1.0, "foes": false, "after": 60.0,
		"boss": [2, 13.6, -1.8, -1.9, 17, 6.0, 55, 3, 3, -1, 0.0, 0.0, 0.0, [], 3, 2, [[1, 44.0]], 62, 1, 0, 1, 0, 0, 1], "anim": ["Kneel", 9.0]},
	"jefe_fase3": {"pos": Vector3(8.2, 4.6, 5.4), "look": Vector3(15.2, 1.8, 0.0), "gate": 1.0, "foes": true, "after": 60.0,
		"boss": [3, 15.5, 0.0, -1.5708, 18, 0.0, 33, 3, 3, -1, 0.0, 0.0, 0.0, [], 0, 1, [], 0, 3, 1, 3, 0, 0, 3], "anim": ["Kneel", 9.0]},
	"jefe_contacto": {"pos": Vector3(8.6, 3.6, -4.8), "look": Vector3(15.2, 1.8, 0.0), "gate": 1.0, "foes": false, "after": 60.0,
		"boss": [3, 15.5, 0.0, -1.5708, 18, 0.0, 33, 3, 3, -1, 0.0, 0.0, 0.0, [], 0, 1, [], 0, 3, 3, 3, 58, 3, 3], "anim": ["Kneel", 9.0]},
	"jefe_liberado": {"pos": Vector3(8.8, 2.6, 2.8), "look": Vector3(14.6, 2.3, 0.0), "gate": 1.0, "foes": false, "after": 60.0,
		"boss": [4, 15.5, 0.0, -1.5708, 9, 0.0, 0, 4, 4, -1, 0.0, 0.0, 0.0, [], 0, 1, [], 0, 3, 3, 3, 100, 0, 3], "anim": ["Remember", 9.0]},
	"secuelas_1": {"pos": Vector3(15.8, 2.6, 3.6), "look": Vector3(26.0, 2.6, 0.0), "gate": 1.0, "foes": false, "after": 3.0},
	"secuelas_2": {"pos": Vector3(20.6, 2.1, 0.4), "look": Vector3(28.0, 1.6, 0.0), "gate": 1.0, "foes": false, "after": 3.0},
	"secuelas_3": {"pos": Vector3(15.8, 2.6, 3.6), "look": Vector3(26.0, 2.6, 0.0), "gate": 1.0, "foes": false, "after": 60.0},
	"kf_sello_1a": {"pos": Vector3(15.6, 0.9, -8.0), "look": Vector3(22.5, 2.4, -0.4), "gate": 0.0, "foes": false},
	"kf_sello_1b": {"pos": Vector3(16.4, 1.3, -4.2), "look": Vector3(26.0, 2.8, 0.0), "gate": 0.0, "foes": false},
	"kf_sello_2a": {"pos": Vector3(15.5, 3.2, 4.0), "look": Vector3(26.0, 3.2, 0.0), "gate": 0.0, "foes": false},
	"kf_sello_2b": {"pos": Vector3(17.5, 2.6, 2.2), "look": Vector3(27.0, 3.8, 0.0), "gate": 1.0, "foes": false},
	"kf_sello_3a": {"pos": Vector3(20.4, 2.1, 0.0), "look": Vector3(28.0, 1.5, 0.0), "gate": 1.0, "foes": false},
	"kf_sello_3b": {"pos": Vector3(24.6, 1.8, 0.6), "look": Vector3(28.0, 1.7, 0.0), "gate": 1.0, "foes": false},
}
var out := "user://"
var only: Array = []
var frame := 0
var idx := -1
var wait := 0
var world: Node3D
var cam: Camera3D
var hud: Hud
var avatars: Array = []
var foes: Array = []
var time := 0.0
var npc: NpcView
var boss: BossView
var arena: BossArena
var cine := Cutscene.new()


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out = args[0]
	only = args.slice(1)
	if not out.ends_with("/"):
		out += "/"
	DirAccess.make_dir_recursive_absolute(out)
	world = Node3D.new()
	get_root().add_child(world)
	var builder := WorldBuilder.new()
	builder.build(world)
	world.set_meta("builder", builder)
	cam = Camera3D.new()
	cam.fov = 62.0
	cam.far = 400.0
	world.add_child(cam)
	cam.make_current()
	hud = Hud.new()
	get_root().add_child(hud)


func _setup() -> void:
	var cast := [["Ixchel", "#19b4d6", 0, "alux", Vector3(2.6, 0, 2.6), 0.3], ["Nicte", "#e4007c", 1, "alux", Vector3(0.4, 0, -3.4), 0.2],
		["Balam Kin", "#ffd23f", 2, "balam", Vector3(-3.4, 0, -1.6), 0.9], ["Chaac", "#ff7a1a", 0, "alux", Vector3(5.2, 0, -2.2), -0.5]]
	var roster := []
	var team := {}
	for i in cast.size():
		var c: Array = cast[i]
		var av := Avatar.new()
		world.add_child(av)
		av.setup(c[0], c[1], c[2])
		av.set_form(c[3], false)
		av.global_position = c[4] + Vector3(0, World.terrain_h(c[4].x, c[4].z), 0)
		av.rotation.y = c[5]
		avatars.append(av)
		roster.append({"id": str(i), "slot": i, "name": c[0], "color": c[1], "hat": c[2], "on": i != 3})
		team[i] = {"hp": [100.0, 72.0, 41.0, 0.0][i], "form": c[3], "dead": i == 3}
	for e in [["piedra", Vector3(16.5, 0, -2.5), -1.2, 44.0, "windup"], ["corrupta", Vector3(13.0, 0, 1.8), 1.9, 12.0, "chase"], ["corrupta", Vector3(17.0, 0, 2.0), 2.4, 30.0, "stun"]]:
		var v := EnemyView.new()
		world.add_child(v)
		v.setup(foes.size() + 1, e[0])
		var max_hp: float = 60.0 if e[0] == "piedra" else 40.0
		v.push_state(0.0, e[1] + Vector3(0, World.terrain_h(e[1].x, e[1].z), 0), e[2], e[3], max_hp, e[4])
		foes.append(v)
	npc = NpcView.new()
	world.add_child(npc)
	npc.setup("yaxche")
	boss = BossView.new()
	world.add_child(boss)
	boss.setup()
	arena = BossArena.new()
	world.add_child(arena)
	arena.setup(false)
	hud.set_overlay("")
	hud.set_room("Q7KM2X")
	hud.set_roster(roster, "0")
	hud.set_team(team)
	hud.set_objective("Pisen 4 altares al mismo tiempo  (2/4)", "goal", "Un alux en cada altar  ·  están marcados en la brújula")
	hud.set_altars(true, 0b0101)
	hud.set_vitals(100.0, 62.0)
	hud.set_abilities("alux", [0.0, 0.55, 0.0], 62.0, 0.0)
	hud.set_forms(["alux", "balam"], "alux", 0.0)
	hud.hint("Ratón para mirar  ·  H muestra los controles  ·  Esc abre el menú", 2.0)


func _process(delta: float) -> bool:
	frame += 1
	time += delta
	if frame == 3:
		_setup()
	if frame < 4:
		return false
	for av in avatars:
		av.animate(delta, true, false)
	for v in foes:
		v.update_view(time, delta)
	if arena:
		arena.update_view(0.5 if wait > 0 else delta, boss.position, {0: Vector3(13.2, 0.2, 2.6), 1: Vector3(13.4, 0.2, -2.6), 2: Vector3(17.9, 0.0, 2.6)})
	if npc:
		npc.update_view(delta, idx >= 0 and str(shots[idx][0]) == "objetivo_yaxche", avatars[0].global_position, idx >= 0 and str(shots[idx][0]) == "dialogo")
	hud.set_compass(cam.rotation.y + PI, cam.global_position)
	if wait > 0:
		wait -= 1
		if wait == 0:
			var s: Array = shots[idx]
			get_root().get_texture().get_image().save_png(out + s[0] + ".png")
			print("captura: ", s[0])
		return false
	idx += 1
	while idx < shots.size() and not only.is_empty() and not only.has(shots[idx][0]):
		idx += 1
	if idx >= shots.size():
		return true
	var s: Array = shots[idx]
	var key: Dictionary = KEYFRAMES.get(str(s[0]), {})
	for av in avatars:
		av.visible = key.is_empty()
	for v in foes:
		v.visible = key.is_empty() or bool(key.foes)
	(world.get_meta("builder") as WorldBuilder).update(time, 0.0, float(key.get("gate", 0.0)))
	if key.has("after"):
		(world.get_meta("builder") as WorldBuilder).preview_aftermath(float(key.after))
	# El jefe: dormido en su sitio salvo que la toma diga otra cosa
	var bstate: Array = key.get("boss", [0, BossDef.HOME.x, BossDef.HOME.y, BossDef.HOME_YAW, 0, 0.0, 100, 0, 3, -1, 0.0, 0.0, 0.0, []])
	bstate = bstate.duplicate()
	bstate.append_array([0, 1, [], 100, 0, 0, 1, 0, 0, 1].slice(bstate.size() - 14))
	boss.cine_release()
	boss.apply(bstate)
	arena.apply(bstate)
	arena.cine_feather = -1
	boss.position = Vector3(float(bstate[1]), World.terrain_h(float(bstate[1]), float(bstate[2])), float(bstate[2]))
	boss.rotation.y = float(bstate[3])
	if boss._anim != null and key.has("t"):
		boss._anim.seek(float(key.t), true)
	if boss._anim != null and key.has("anim"):
		boss._anim.play(str(key.anim[0]))
		boss._anim.seek(float(key.anim[1]), true)
		boss._anim.pause()
	boss._label.visible = boss._label.visible and not str(s[0]).begins_with("kf_")
	if key.has("boss") and int(bstate[0]) in [1, 2, 3] and bool(s[5]):
		var bst: String = BossDef.STATES[int(bstate[4])]
		match int(bstate[0]):
			1:
				hud.set_boss(true, BossDef.PHASE_NAMES[1], float(bstate[6]) / 100.0, int(bstate[7]), int(bstate[8]), "No tiene vida: devuélvele la memoria")
				hud.set_objective("Enciende los glifos del guardián  (%d/%d)" % [int(bstate[7]), int(bstate[8])], "alert", "Debilita a una criatura y tócala con F junto a él  ·  los golpes no le hacen nada")
			2:
				hud.set_boss(true, BossDef.PHASE_NAMES[2], float(bstate[6]) / 100.0, 0, 0, "corazones liberados %d/3" % int(bstate[18]),
					"CORAZÓN EXPUESTO  ·  ¡garras de Balam!" if bst == "bound" else "CORAZÓN DE PIEDRA", float(bstate[17]) / 100.0, Color(1.0, 0.55, 0.3))
				if bst == "bound":
					hud.set_objective("¡Corazón expuesto!  (%d/3)" % int(bstate[18]), "success", "Golpéalo como Balam (2)  ·  quien pise un ancla, que no la suelte")
				else:
					hud.set_objective("Haz que embista contra una columna  (%d/3)" % int(bstate[18]), "alert", "Ponte detrás de ella cuando te apunte  ·  quedará aturdido")
			3:
				var open := int(bstate[19]) >= int(bstate[20])
				hud.set_boss(true, BossDef.PHASE_NAMES[3], float(bstate[6]) / 100.0, 0, 0, "glifos de memoria %d/%d" % [int(bstate[19]), int(bstate[20])],
					"CONTACTO  ·  2 de %d lo tocan" % int(bstate[23]), float(bstate[21]) / 100.0 if open else -1.0)
				if open:
					hud.set_objective("Tóquenlo todos a la vez  (2/%d)" % int(bstate[23]), "success", "Como alux, junto a él, mantén F  ·  un golpe corta el contacto")
				else:
					hud.set_objective("Enciende los glifos de memoria  (%d/%d)" % [int(bstate[19]), int(bstate[20])], "alert", "Purifica criaturas junto a él (F)  ·  son lo último que le queda al Silencio")
		hud.set_altars(false, 0)
	else:
		hud.set_boss(false)
	var yaw: float = s[2]
	var pitch: float = s[3]
	var fwd := Vector3(sin(yaw) * cos(pitch), -sin(pitch), cos(yaw) * cos(pitch))
	var target: Vector3 = s[1]
	cam.global_position = target - fwd * float(s[4])
	cam.look_at(target, Vector3.UP)
	hud.visible = s[5]
	hud.hide_intro()
	hud.hide_menu()
	hud.hide_result()
	hud.set_net("")
	hud.banner("", Color.WHITE, 0.01)
	for av in avatars:
		av.is_local = str(s[0]).begins_with("ref_")   # sin nombre sobre la cabeza en los cuadros de referencia
		av._apply()
	if npc:
		npc.visible = not str(s[0]).begins_with("ref_") or str(s[0]) == "ref_yaxche"
	hud.set_cine(false)
	hud.hide_dialogue()
	hud.context_hint("")
	hud.set_npc_mark("")
	if not key.is_empty():
		if key.has("cine"):
			# Un cuadro exacto de una cinemática del jefe: [id, plano, fracción del plano]
			var shot: Dictionary = Story.CUTSCENES[str(key.cine[0])].shots[int(key.cine[1])]
			var k := float(key.cine[2])
			var e := k * k * (3.0 - 2.0 * k)
			cam.look_at_from_position((shot.from[0] as Vector3).lerp(shot.to[0], e), (shot.from[1] as Vector3).lerp(shot.to[1], e), Vector3.UP)
			var pose: Dictionary = shot.boss
			var look := int(pose.look_to) if pose.has("look_to") and k >= float(pose.get("look_at", 0.5)) else int(pose.look)
			boss.cine_pose(str(pose.anim), float(pose.at) + k * float(shot.dur) * float(pose.speed), look, lerpf(float(pose.glow[0]), float(pose.glow[1]), k))
			if shot.has("feather"):
				arena.cine_feather = 1 if bool(shot.feather) else 0
				arena._feather_k = (1.0 if bool(shot.feather) else 0.0) * clampf(0.35 + k * 0.65, 0.0, 1.0)
		else:
			cam.look_at_from_position(key.pos, key.look, Vector3.UP)
		npc.visible = false
	if str(s[0]).begins_with("cine_") or str(s[0]).begins_with("sello_"):
		# Un plano de una cinemática, a mitad de su recorrido
		var which := "llamado" if str(s[0]).begins_with("cine_") else "sello"
		var n := int(str(s[0]).get_slice("_", 1)) - 1
		var script: Dictionary = Story.CUTSCENES[which].duplicate(true)
		script.shots = [script.shots[n]]
		cine.play(which, script, cam, hud, {"yaxche": Story.NPCS.yaxche.name})
		if which == "sello":
			hud.cine_skip_text("Enter  ·  votar para omitir  (1/3)")
		cine.seek(float(script.shots[0].dur) * 0.5)
		cine.process(0.0)
	boss._update_face(1.0)
	boss._update_face(1.0)
	if str(s[0]).begins_with("kf_"):
		boss._label.visible = false
	match str(s[0]):
		"dialogo":
			var lines := []
			for l in Story.dialogue("yaxche", 0, 0):
				lines.append(str(l[1]))
			hud.show_dialogue(Story.NPCS.yaxche.name, Story.NPCS.yaxche.title, lines, Color(1.0, 0.82, 0.3), "yaxche")
			hud.advance_dialogue()
			hud.advance_dialogue()
			hud.advance_dialogue()
		"objetivo_yaxche":
			hud.set_npc_mark("yaxche", Story.npc_pos("yaxche"))
			hud.set_objective("Habla con Chiich Yaxché", "goal", "Te espera junto al brasero  ·  acércate y pulsa F")
			hud.context_hint("F  ·  Hablar con Chiich Yaxché")
		"bienvenida":
			hud.show_intro()
		"menu":
			hud.show_menu({"sens": 0.5, "vol_master": 0.8, "vol_music": 0.55, "vol_sfx": 0.9, "vol_amb": 0.7}, "alta", "")
		"esperando":
			hud.set_objective("Quédate en el altar  (2/4)", "wait", "Esperando a que el grupo pise los demás altares")
		"reconectando":
			hud.set_objective("Pisen 4 altares al mismo tiempo  (2/4)", "goal", "Un alux en cada altar  ·  están marcados en la brújula")
			hud.set_net("warn", "Reconectando…  intento 2")
			hud.banner("Se perdió la conexión  ·  reconectando", Color(1.0, 0.75, 0.4), 30.0)
		"victoria":
			hud.set_altars(false, 0)
			hud.set_objective("Santuario liberado", "success", "Otra ronda: 1 de 4 listos  ·  Esc para unirte")
			hud.show_result("victory", "¡VICTORIA!", "El santuario está libre y el claro vuelve a respirar.", [
				["Tiempo", "2:47"], ["Criaturas purificadas", "3"], ["Enemigos vencidos", "5"], ["Caídas del grupo", "2"],
				["Sello del Claro", "guardado en tu perfil"]], [
				["again", "Jugar otra ronda", true], ["close", "Seguir explorando", false], ["exit", "Salir al portal", false]])
			hud.set_result_note("Otra ronda: 1 de 4 listos")
		"derrota":
			hud.set_altars(false, 0)
			hud.set_objective("Derrota  ·  el santuario se selló de nuevo", "alert", "Los altares despiertan en 5 s")
			hud.show_result("defeat", "DERROTA", "Todo el grupo cayó y el santuario se selló de nuevo. Reúnanse en el brasero, cúrense con F y vuelvan a pisar los altares.", [
				["Tiempo", "1:12"], ["Enemigos que quedaban", "4"], ["Caídas del grupo", "4"]], [
				["retry", "Reintentar", true], ["exit", "Salir al portal", false]])
	if s[0] == "combate":
		hud.set_altars(false, 0)
		hud.set_objective("¡Emboscada!  Quedan 5 enemigos", "alert", "Véncelos o purifícalos  ·  si cae todo el grupo, se pierde")
		hud.deny(2, "")
		hud.set_vitals(58.0, 30.0)
		hud.set_abilities("balam", [0.4, 0.0, 0.8], 30.0, 0.6)
		hud.set_forms(["alux", "balam"], "balam", 0.0)
		avatars[0].set_form("balam", true)
		avatars[0].global_position = Vector3(14.0, World.terrain_h(14.0, -1.0), -1.0)
		avatars[0].rotation.y = PI * 0.5
		avatars[0].play_action("claw")
		Fx.slash(world, avatars[0].global_position + Vector3(0, 0.8, 0), PI * 0.5, 2.3, 1.9, Color(1.0, 0.75, 0.3), 2.0)
		Fx.number(world, Vector3(16.5, 2.2, -2.5), "16", Color(1.0, 0.82, 0.3), true)
	wait = 14
	return false
