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
	["bienvenida", Vector3(2.6, 1.25, 2.6), PI, 0.42, 7.0, true],
	["menu", Vector3(2.6, 1.25, 2.6), PI, 0.42, 7.0, true],
	["esperando", Vector3(2.6, 1.25, 2.6), PI, 0.42, 7.0, true],
	["reconectando", Vector3(2.6, 1.25, 2.6), PI, 0.42, 7.0, true],
	["retrato_alux", Vector3(2.6, 0.95, 2.6), 0.3 + PI - 0.35, 0.1, 2.3, false],
	["retrato_balam", Vector3(-3.4, 0.75, -1.6), 0.9 + PI - 0.6, 0.12, 2.9, false],
	["combate", Vector3(14.0, 1.2, -1.0), PI * 0.5, 0.35, 8.0, true],
	["victoria", Vector3(14.0, 1.2, -1.0), PI * 0.5, 0.35, 8.0, true],
	["derrota", Vector3(14.0, 1.2, -1.0), PI * 0.5, 0.35, 8.0, true],
]
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
	match str(s[0]):
		"bienvenida":
			hud.show_intro()
		"menu":
			hud.show_menu({"sens": 0.5, "vol_master": 0.8, "vol_music": 0.55, "vol_sfx": 0.9, "vol_amb": 0.7}, "alta", "")
		"esperando":
			hud.set_objective("Quédate en el altar  (2/4)", "wait", "Esperando a que el grupo pise los demás altares")
		"reconectando":
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
