extends Node3D
## Mundo abierto en el cliente de zonas: todo lo que tiene el «Camino a Motul» y no tenía la plaza.
## zone_client.gd sigue llevando la red, el movimiento, la cámara y la calidad; aquí vive:
##
##   · los pasos entre zonas (F ante el arco, el arco de vuelta y la carreta de regreso);
##   · el escenario del camino (camino_builder.gd), que se construye la primera vez que se pisa,
##     y el arco de salida en la plaza (motul_gate.gd);
##   · las criaturas que manda el servidor (creature_view.gd), el ataque básico (clic o J) y
##     purificar (F): el cliente sólo pide; el servidor decide si dio, cuánto y a quién;
##   · la vida del alux, caer y reaparecer;
##   · los puntos de descubrimiento, la misión, las recompensas que concede la API y el mapa (M).
##
## Nada de aquí es autoritativo. De zone_client usa: _ws, _me, _pred, _cam_yaw, _face, _others,
## _my_num, _audio, _quality, _flash(), _toggle_menu() y sus contenedores de interfaz.
##
## Pruebas (?debug=1): window.ALUX_ACTION admite además `travel` (toma el paso que haya al
## alcance), `attack`, `purify`, `use`, `map`, `quest` (abre el diálogo de la misión) y
## `accept`; `window.__aluxState.world` trae zona, vida, criaturas, pasos, lugares y misión.

const Zone := preload("res://scripts/shared/zone_def.gd")
const Zones := preload("res://scripts/shared/zones.gd")
const Camino := preload("res://scripts/shared/camino_def.gd")
const Wild := preload("res://scripts/shared/wild_def.gd")
const CaminoBuilder := preload("res://scripts/client/camino_builder.gd")
const MotulGate := preload("res://scripts/client/motul_gate.gd")
const CreatureView := preload("res://scripts/client/creature_view.gd")
const WorldMap := preload("res://scripts/client/world_map.gd")
const Avatar := preload("res://scripts/client/avatar.gd")
const Audio := preload("res://scripts/client/audio.gd")
const Fx := preload("res://scripts/client/fx.gd")
const Kit := preload("res://scripts/client/ui/ui_kit.gd")
const Hud := preload("res://scripts/client/hud.gd")

## Quien da la misión: el modelo del alux con un aspecto fijo, como los personajes de la plaza.
## Nombre provisional, en español; pendiente de revisión con la biblia de historia.
const NPC := {"name": "Rosario, la cordelera", "color": "#e4007c", "hat": 3, "look": [2, 3, 2, 5, 2], "yaw": -2.2}
const REWARD_NAMES := {"purify": "Criatura purificada", "enemy": "Criatura vencida", "discovery": "Lugar descubierto", "mission": "Misión cumplida"}


## Barra de vida dibujada por código.
class Bar:
	extends Control
	var value := 1.0
	var text := ""
	var color := Kit.BLOOD

	func _init() -> void:
		custom_minimum_size = Vector2(230, 20)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var r := Rect2(Vector2.ZERO, size)
		draw_style_box(Kit.flat(Color(0, 0, 0, 0.6), 8.0, 1, Color(1, 1, 1, 0.25)), r)
		if value > 0.0:
			draw_style_box(Kit.flat(color, 6.0), Rect2(2, 2, maxf(8.0, (size.x - 4.0) * clampf(value, 0.0, 1.0)), size.y - 4.0))
		var f := Kit.bold_font()
		var w := f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
		draw_string_outline(f, Vector2((size.x - w) * 0.5, size.y - 5.0), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, 4, Color(0, 0, 0, 0.7))
		draw_string(f, Vector2((size.x - w) * 0.5, size.y - 5.0), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color.WHITE)


var zone := "merida"
var hp := 100
var max_hp := 100
var down := false
var known: Array = []
var quest := {"st": "none", "n": 0, "need": 3}

var _c: Node                      # zone_client
var _time := 0.0
var _camino: CaminoBuilder
var _camino_root: Node3D
var _npc: Avatar
var _npc_mark: Label3D
var _creatures := {}              # id -> CreatureView
var _safe := true
var _traveling := 0.0             # segundos que quedan esperando la respuesta de un viaje
var _atk_ready := 0.0
var _danger_until := 0.0
var _pid := ""
var _from := ""                   # la zona de la que se viene (para anunciar la nueva al llegar)
var _level := 0
var _seeds := -1
var _amb_in := 0.0

# Interfaz
var _hud: Control
var _vitals: Control
var _chip: Label
var _bar: Bar
var _stats: Label
var _quest_box: Control
var _quest_title: Label
var _quest_lines: Label
var _toast: Control
var _toast_title: Label
var _toast_sub: Label
var _toast_t := 0.0
var _toasts: Array = []           # [título, texto, color, sonido]
var _feed: VBoxContainer
var _hurt: ColorRect
var _down_label: Label
var _map_box: Control
var _map: WorldMap
var _dialog: Control
var _dialog_body: VBoxContainer
var _recapture := false


func setup(client: Node, ui_root: Control, plaza_root: Node3D) -> void:
	_c = client
	MotulGate.new().build(plaza_root)
	_build_hud(ui_root)


# ───────────────────────── Zonas ─────────────────────────

## Muestra el escenario de la zona (el de la plaza lo quita y lo pone zone_client).
func show_zone(z: String) -> void:
	_from = zone
	zone = z
	var wild := Zones.is_wild(z)
	if wild and _camino_root == null:
		# Se construye la primera vez que se pisa: la plaza no paga el camino
		_camino_root = Node3D.new()
		_camino_root.name = "Camino"
		_camino = CaminoBuilder.new()
		_camino.build(_camino_root, int(_c._quality))
		_spawn_npc()
	if _camino_root != null:
		if wild and _camino_root.get_parent() == null:
			add_child(_camino_root)
		elif not wild and _camino_root.get_parent() != null:
			remove_child(_camino_root)
	if not wild:
		_clear_creatures()
	_vitals.visible = wild
	_down_label.visible = false


## Bienvenida o cambio de sitio (`welcome` y `zone`): vida, lugares conocidos y misión.
func enter(m: Dictionary) -> void:
	if m.has("id"):
		_pid = str(m.id)
		_load_known()
	_traveling = 0.0
	if m.has("hp"):
		hp = int(m.hp)
	if m.has("maxhp"):
		max_hp = maxi(1, int(m.maxhp))
	for id in m.get("known", []):
		if not known.has(str(id)):
			known.append(str(id))
	_save_known()
	if m.get("quest") is Dictionary:
		_set_quest(m.quest, false)
	_set_down(false)
	var arrived := _from != zone
	_from = zone
	if str(m.get("t", "")) == "zone":
		Audio.play("reaparecer|ui_confirmar", null, -6.0)
	if arrived and Zones.is_wild(zone):
		_push_toast(str(Zones.NAMES[zone]).to_upper(), "Dentro de las mojoneras de jade estás a salvo. Más allá: clic o J lanza una chispa, F purifica a las criaturas débiles.", Kit.GOLD, "")
	elif arrived and str(m.get("t", "")) == "zone":
		_push_toast(str(Zones.NAMES[zone]).to_upper(), str(Zones.ALIASES[zone]), Kit.GOLD, "")
	_safe = true


func set_quality(level: int) -> void:
	if _camino != null:
		_camino.set_quality(level)


## Música y ambientes del camino (los de la plaza los lleva zone_client).
func soundscape(delta: float, at: Vector3) -> void:
	_amb_in -= delta
	if _amb_in > 0.0:
		return
	_amb_in = 0.5
	var water := clampf(1.0 - (Vector2(at.x, at.z).distance_to(Camino.CENOTE) - Camino.CENOTE_R) / 18.0, 0.0, 1.0)
	_c._audio.ambience({"amb_aves": 0.35, "amb_viento": 0.3, "amb_selva": 0.35, "amb_insectos": 0.2, "amb_agua": snappedf(0.5 * water * water, 0.05)})
	var music := "mus_peligro" if _time < _danger_until else "mus_exploracion"
	if not _c._audio.has(music):
		music = "mus_claro"
	_c._audio.set_music(music)


# ───────────────────────── Mensajes del servidor ─────────────────────────

## Estado periódico: mi vida y las criaturas a la vista.
func on_state(m: Dictionary) -> void:
	if m.has("h"):
		hp = int(m.h)
	if not m.has("c") or _camino_root == null:
		return
	for e in m.c:
		var id := int(e[0])
		var cv: CreatureView = _creatures.get(id)
		if cv == null:
			if id < 0 or id >= Camino.SPAWNS.size():
				continue
			cv = CreatureView.new()
			cv.setup(id, str(Camino.SPAWNS[id][0]))
			_camino_root.add_child(cv)
			_creatures[id] = cv
		var st := int(e[5])
		cv.push_state(_time, Vector3(float(e[1]), 0.0, float(e[2])), float(e[3]), float(e[4]), Wild.STATES[st] if st >= 0 and st < Wild.STATES.size() else "idle")
		if e.size() > 6 and int(e[6]) == int(_c._my_num) and st != 0:
			_danger_until = _time + 5.0


func on_message(m: Dictionary) -> bool:
	match str(m.get("t", "")):
		"ev":
			_on_event(m)
		"disc":
			_on_discovery(str(m.get("id", "")), bool(m.get("new", true)))
		"reward":
			_on_reward(m)
		"quest":
			_set_quest(m, true)
		"atk_no":
			if str(m.get("why", "")) == "safe":
				_c._flash("En la zona segura no se combate: sal más allá de las mojoneras de jade")
		"travel_no":
			_traveling = 0.0
			_c._set_overlay("")
			_c._flash("Acércate más para tomar el camino")
		_:
			return false
	return true


func _avatar_of(num: int) -> Avatar:
	if num == int(_c._my_num):
		return _c._me
	var o: Dictionary = _c._others.get(num, {})
	return o.av if not o.is_empty() else null


func _on_event(m: Dictionary) -> void:
	var num := int(m.get("i", 0))
	var mine := num == int(_c._my_num)
	var av := _avatar_of(num)
	match str(m.get("e", "")):
		"atk":
			if av == null or _camino_root == null:
				return
			var from := av.global_position + Vector3(0, 1.0, 0)
			var cv: CreatureView = _creatures.get(int(m.get("c", -1)))
			var yaw := float(m.get("r", 0.0))
			var to := from + Vector3(sin(yaw), 0.0, cos(yaw)) * float(Wild.ATTACK.range)
			if cv != null:
				to = cv.global_position + Vector3(0, 0.7, 0)
				cv.hit_flash()
			if not mine:
				av.play_action("bolt")
			_spark(from, to, cv != null, float(m.get("d", 0.0)))
			Audio.play("chispa", from, -3.0 if mine else -8.0)
		"hit":
			if av != null:
				av.play_action("hit")
				Fx.burst(_camino_root, av.global_position + Vector3(0, 1.0, 0), Color(1.0, 0.4, 0.3), 8, 3.0, 0.06, 0.4)
			if mine:
				_hurt.color.a = 0.38
				_danger_until = _time + 6.0
				Audio.play("dano", null, -2.0)
				if av != null:
					Fx.number(_camino_root, av.global_position + Vector3(0, 2.0, 0), "-%d" % int(m.get("d", 0)), Color(1.0, 0.4, 0.35))
		"die":
			var cv: CreatureView = _creatures.get(int(m.get("c", -1)))
			if cv != null:
				_creatures.erase(cv.creature_id)
				cv.die(int(m.get("p", 0)) == 1)
		"down":
			if mine:
				_set_down(true)
			elif av != null:
				av.set_dead(true)
				Audio.play("aliado_caido", av.global_position, -6.0)
		"up":
			if not mine and av != null:
				av.set_dead(false)


## La chispa de jade: una mota de luz que va del alux a donde dio (o se pierde si no dio).
func _spark(from: Vector3, to: Vector3, hit: bool, dmg: float) -> void:
	var s := SphereMesh.new()
	s.radius = 0.16
	s.height = 0.32
	s.radial_segments = 8
	s.rings = 4
	var mi := MeshInstance3D.new()
	mi.mesh = s
	mi.material_override = Fx.glow_mat(Color(0.7, 1.0, 0.9))
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.position = from
	_camino_root.add_child(mi)
	var tw := mi.create_tween()
	tw.tween_property(mi, "position", to, clampf(from.distance_to(to) / 40.0, 0.05, 0.18))
	tw.tween_callback(func() -> void:
		if hit:
			Fx.burst(_camino_root, to, Color(0.5, 1.0, 0.8), 12, 4.0, 0.07, 0.4)
			Fx.number(_camino_root, to + Vector3(0, 0.6, 0), str(snappedf(dmg, 0.1)).trim_suffix(".0"), Color(0.75, 1.0, 0.9))
			Audio.play("chispa_impacto|enemigo_dano", to, -4.0)
		mi.queue_free())


func _set_down(d: bool) -> void:
	if d == down:
		return
	down = d
	if _c._me != null:
		(_c._me as Avatar).set_dead(d)
	_down_label.visible = d
	if d:
		Audio.play("caida|derrota", null, -3.0)
		_close_dialog(false)
		_toggle_map(false)


func _on_discovery(id: String, fresh: bool) -> void:
	if not known.has(id):
		known.append(id)
		_save_known()
	var name := id
	for d in Camino.DISCOVERIES:
		if str(d.id) == id:
			name = str(d.name)
	if fresh:
		_push_toast("LUGAR DESCUBIERTO", name, Color(0.4, 0.92, 1.0), "punto_control|ui_recompensa")
	else:
		_feed_line("Ya conocías este lugar: %s" % name, Color(1, 1, 1, 0.7))


func _on_reward(m: Dictionary) -> void:
	var kind := str(m.get("kind", ""))
	if bool(m.get("applied", false)):
		_level = int(m.get("level", _level))
		_seeds = int(m.get("tseeds", _seeds))
		_feed_line("%s   +%d XP  ·  +%d semillas" % [str(REWARD_NAMES.get(kind, "Recompensa")), int(m.get("xp", 0)), int(m.get("seeds", 0))], Kit.GOLD)
		Audio.play("recoger|ui_recompensa", null, -8.0)
		if bool(m.get("up", false)):
			_push_toast("¡NIVEL %d!" % _level, "Tu alux ha crecido", Kit.GOLD, "ui_recompensa")
		return
	var reason := str(m.get("reason", ""))
	if reason == "offline":
		_feed_line("%s: recompensa sin registrar (no hubo respuesta del servidor)" % str(REWARD_NAMES.get(kind, "Recompensa")), Kit.AMBER)
	elif reason == "duplicate":
		if kind == "mission":
			_feed_line("Esta misión ya la habías cobrado", Color(1, 1, 1, 0.7))
	else:
		_feed_line("%s: sin recompensa por hoy (tope diario)" % str(REWARD_NAMES.get(kind, "Recompensa")), Color(1, 1, 1, 0.7))


func _set_quest(m: Dictionary, announce: bool) -> void:
	var before := quest
	quest = {"st": str(m.get("st", "none")), "n": int(m.get("n", 0)), "need": int(m.get("need", 3))}
	if not announce:
		return
	var name := str(Wild.MISSIONS[Wild.MISSION].name)
	if str(before.st) == "none" and str(quest.st) == "active":
		_push_toast("MISIÓN ACEPTADA", name, Kit.GOLD, "ui_confirmar")
	elif str(before.st) == "active" and str(quest.st) == "done":
		_push_toast("MISIÓN CUMPLIDA", name, Kit.GOLD, "victoria|ui_recompensa")
	elif str(quest.st) == "active" and int(quest.n) > int(before.n):
		_feed_line("Criaturas purificadas: %d de %d" % [int(quest.n), int(quest.need)], Kit.JADE)
		Audio.play("objetivo", null, -6.0)
		if int(quest.n) >= int(quest.need):
			_push_toast("EL CAMINO ESTÁ ABIERTO", "Lleva el recado hasta el cartel de Motul", Kit.JADE, "")
	if _dialog.visible:
		_fill_dialog()


# ───────────────────────── Bucle ─────────────────────────

func process(delta: float, at: Vector3) -> void:
	_time += delta
	if _traveling > 0.0:
		_traveling -= delta
		if _traveling <= 0.0:
			_c._set_overlay("")
			_c._flash("El camino no respondió. Inténtalo otra vez.")
	var wild := Zones.is_wild(zone)
	if wild and _camino != null:
		_camino.update(delta, at)
		for id in _creatures.keys():
			var cv: CreatureView = _creatures[id]
			if _time - cv.seen > 1.6:
				_creatures.erase(id)   # dejó de llegar: lejos, o muerta sin que viéramos el suceso
				cv.queue_free()
			else:
				cv.update_view(_time, delta, at)
		_update_npc(delta, at)
		var safe := Camino.is_safe(at.x, at.z)
		if safe != _safe:
			_safe = safe
			_feed_line("Zona segura" if safe else "Sales de la zona segura: el monte está abierto", Kit.JADE if safe else Kit.AMBER)
			Audio.play("ui_mover|ui_click", null, -6.0)
	_update_hud(delta, wild)


func _update_npc(delta: float, at: Vector3) -> void:
	if _npc == null:
		return
	var d := Vector2(_npc.position.x, _npc.position.z).distance_to(Vector2(at.x, at.z))
	var want := float(NPC.yaw)
	if d < 9.0 and d > 0.3:
		want = atan2(at.x - _npc.position.x, at.z - _npc.position.z)
	if absf(angle_difference(_npc.rotation.y, want)) > 0.01:
		_npc.rotation.y = lerp_angle(_npc.rotation.y, want, minf(1.0, delta * 4.0))
	_npc_mark.visible = str(quest.st) == "none" and d < 40.0
	if _npc_mark.visible:
		_npc_mark.position.y = 2.75 + sin(_time * 3.0) * 0.08


func _spawn_npc() -> void:
	_npc = Avatar.new()
	_npc.forms = ["alux"]
	_camino_root.add_child(_npc)
	_npc.setup(str(NPC.name), str(NPC.color), int(NPC.hat), NPC.look)
	_npc.set_lod(0, false)   # sin sombra propia, como los personajes de la plaza
	_npc.position = Vector3(Camino.QUEST_NPC.x, 0.0, Camino.QUEST_NPC.y)
	_npc.rotation.y = float(NPC.yaw)
	_npc_mark = Label3D.new()
	_npc_mark.text = "!"
	_npc_mark.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_npc_mark.pixel_size = 0.009
	_npc_mark.font_size = 96
	_npc_mark.outline_size = 22
	_npc_mark.modulate = Kit.GOLD
	_npc_mark.outline_modulate = Color(0.1, 0.06, 0.02, 0.95)
	_npc_mark.position = Vector3(0, 2.75, 0)
	_npc.add_child(_npc_mark)


func _clear_creatures() -> void:
	for id in _creatures.keys():
		(_creatures[id] as CreatureView).queue_free()
	_creatures.clear()


# ───────────────────────── Acciones del jugador ─────────────────────────

func _me() -> Vector2:
	return Vector2(float(_c._pred[0]), float(_c._pred[2]))


func _send(msg: Dictionary) -> void:
	var ws: WebSocketPeer = _c._ws
	if ws != null and ws.get_ready_state() == WebSocketPeer.STATE_OPEN:
		ws.send_text(JSON.stringify(msg))


## Mientras tanto el jugador no anda (caído, viajando, con el mapa o un diálogo abiertos).
func blocks_input() -> bool:
	return down or _traveling > 0.0 or _map_box.visible or _dialog.visible


func _gate() -> Dictionary:
	var at := _me()
	return Zones.gate_at(zone, at.x, at.y)


func _weak_near() -> CreatureView:
	var at := _me()
	var best: CreatureView = null
	var best_d := INF
	for id in _creatures:
		var cv: CreatureView = _creatures[id]
		var d := Vector2(cv.position.x, cv.position.z).distance_to(at)
		if cv.purifiable() and d <= Wild.PURIFY_RANGE + float(Wild.CREATURES[cv.kind].radius) and d < best_d:
			best_d = d
			best = cv
	return best


func _at_npc() -> bool:
	return Zones.is_wild(zone) and _me().distance_to(Camino.QUEST_NPC) <= Camino.NPC_R


## El aviso de la tecla F, o "" si aquí no hay nada que hacer.
func prompt() -> String:
	if blocks_input():
		return ""
	if Zones.is_wild(zone):
		if _weak_near() != null:
			return "F  ·  Purificar"
		if _at_npc():
			return "F  ·  Hablar con %s" % str(NPC.name)
	var g := _gate()
	if not g.is_empty():
		return "F  ·  %s" % str(g.verb)
	return ""


## Tecla F. Devuelve true si aquí había algo que hacer.
func use() -> bool:
	if blocks_input():
		return _dialog.visible
	if Zones.is_wild(zone):
		if _weak_near() != null:
			_send({"t": "purify"})
			if _c._me != null:
				(_c._me as Avatar).play_action("interact")
			Audio.play("interactuar", null, -4.0)
			return true
		if _at_npc():
			_open_dialog()
			return true
	var g := _gate()
	if not g.is_empty():
		_travel(g)
		return true
	return false


func _travel(g: Dictionary) -> void:
	_traveling = 5.0
	_c._set_overlay(str(g.travel))
	Audio.play("santuario_abre|ui_confirmar", null, -8.0)
	_send({"t": "travel", "to": str(g.to)})


## Ataque básico: la chispa sale hacia donde mira la cámara; si hay una criatura a tiro por
## delante, hacia ella. El servidor decide si da.
func attack() -> void:
	if not Zones.is_wild(zone) or blocks_input() or _time < _atk_ready or _c._me == null:
		return
	_atk_ready = _time + float(Wild.ATTACK.cd)
	var at := _me()
	var yaw := float(_c._cam_yaw)
	var aim := Vector2(sin(yaw), cos(yaw))
	var best_d := INF
	for id in _creatures:
		var cv: CreatureView = _creatures[id]
		var to := Vector2(cv.position.x, cv.position.z) - at
		var d := to.length()
		if d <= float(Wild.ATTACK.range) + float(Wild.CREATURES[cv.kind].radius) and d < best_d and (d < 1.5 or absf(aim.angle_to(to)) < 1.1):
			best_d = d
			yaw = atan2(to.x, to.y)
	_c._face = yaw
	(_c._me as Avatar).play_action("bolt")
	_send({"t": "atk", "r": snappedf(yaw, 0.01)})


## Teclas y ratón del mundo abierto. Devuelve true si el suceso ya está atendido.
func input(event: InputEvent) -> bool:
	if event is InputEventMouseButton and (event as InputEventMouseButton).pressed:
		if _map_box.visible or _dialog.visible:
			return true   # un clic fuera del mapa o del diálogo no captura el ratón
		if (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT and Zones.is_wild(zone) and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and not blocks_input():
			attack()
			return true
		return false
	if not (event is InputEventKey) or not (event as InputEventKey).pressed or (event as InputEventKey).echo:
		return false
	var key := (event as InputEventKey).physical_keycode
	if _map_box.visible:
		if key == KEY_M or key == KEY_ESCAPE:
			_toggle_map(false)
		return key != KEY_F3 and key != KEY_F4
	if _dialog.visible:
		if key == KEY_ESCAPE:
			_close_dialog(true)
		elif key == KEY_F or key == KEY_ENTER:
			_dialog_confirm()
		return key != KEY_F3 and key != KEY_F4
	if key == KEY_M:
		_toggle_map(true)
		return true
	if key == KEY_J:
		attack()
		return true
	if key == KEY_F:
		return use()
	return false


# ───────────────────────── Interfaz ─────────────────────────

func _build_hud(root: Control) -> void:
	_hud = Control.new()
	_hud.set_anchors_preset(Control.PRESET_FULL_RECT)
	_hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_hud)
	root.move_child(_hud, 0)   # por debajo de los menús y paneles de la plaza
	# Golpe recibido: un velo rojo que se va
	_hurt = ColorRect.new()
	_hurt.set_anchors_preset(Control.PRESET_FULL_RECT)
	_hurt.color = Color(0.8, 0.08, 0.1, 0.0)
	_hurt.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud.add_child(_hurt)
	# Columna izquierda, bajo la placa de la zona: vida y misión
	var column := VBoxContainer.new()
	column.position = Vector2(16, 84)
	column.add_theme_constant_override("separation", 8)
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud.add_child(column)
	_vitals = Hud.Plaque.new(10)
	_vitals.modulate.a = 0.94
	_vitals.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	column.add_child(_vitals)
	var vv := VBoxContainer.new()
	vv.add_theme_constant_override("separation", 4)
	_vitals.add_child(vv)
	_chip = Kit.label("ZONA SEGURA", 12, Kit.JADE, Kit.bold_font())
	vv.add_child(_chip)
	_bar = Bar.new()
	vv.add_child(_bar)
	_stats = Kit.label("Clic o J: chispa  ·  F: purificar  ·  M: mapa", 11, Color(1, 1, 1, 0.6))
	vv.add_child(_stats)
	_vitals.visible = false
	_quest_box = Hud.Plaque.new(10, Kit.GOLD)
	_quest_box.modulate.a = 0.94
	_quest_box.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	column.add_child(_quest_box)
	var qv := VBoxContainer.new()
	qv.add_theme_constant_override("separation", 2)
	_quest_box.add_child(qv)
	_quest_title = Kit.label("", 13, Kit.GOLD, Kit.bold_font())
	qv.add_child(_quest_title)
	_quest_lines = Kit.label("", 12, Kit.LIME)
	qv.add_child(_quest_lines)
	_quest_box.visible = false
	# Avisos grandes, arriba y al centro
	var top := CenterContainer.new()
	top.set_anchors_preset(Control.PRESET_TOP_WIDE)
	top.position.y = 74
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud.add_child(top)
	_toast = Hud.Plaque.new(16, Kit.GOLD)
	top.add_child(_toast)
	var tv := VBoxContainer.new()
	tv.add_theme_constant_override("separation", 2)
	tv.custom_minimum_size = Vector2(380, 0)
	_toast.add_child(tv)
	_toast_title = Kit.label("", 22, Kit.GOLD, Kit.title_font())
	_toast_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tv.add_child(_toast_title)
	_toast_sub = Kit.label("", 14, Kit.LIME)
	_toast_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast_sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_toast_sub.custom_minimum_size = Vector2(380, 0)
	tv.add_child(_toast_sub)
	_toast.visible = false
	# Lo que se va ganando: líneas a la derecha, que se apagan solas
	_feed = VBoxContainer.new()
	_feed.set_anchors_preset(Control.PRESET_CENTER_RIGHT)
	_feed.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_feed.grow_vertical = Control.GROW_DIRECTION_BOTH
	_feed.position = Vector2(-20, 0)
	_feed.alignment = BoxContainer.ALIGNMENT_CENTER
	_feed.add_theme_constant_override("separation", 4)
	_feed.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud.add_child(_feed)
	_down_label = Kit.label("Has caído…\nVuelves a la zona segura en un momento, sin perder nada.", 22, Color.WHITE, Kit.bold_font())
	_down_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	_down_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_down_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_down_label.visible = false
	_hud.add_child(_down_label)
	# Mapa (M)
	_map_box = CenterContainer.new()
	_map_box.set_anchors_preset(Control.PRESET_FULL_RECT)
	_map_box.visible = false
	root.add_child(_map_box)
	_map = WorldMap.new()
	_map_box.add_child(_map)
	# Diálogo de la misión
	_dialog = CenterContainer.new()
	_dialog.set_anchors_preset(Control.PRESET_FULL_RECT)
	_dialog.visible = false
	root.add_child(_dialog)
	var dp := Hud.Plaque.new(22, Kit.GOLD)
	_dialog.add_child(dp)
	_dialog_body = VBoxContainer.new()
	_dialog_body.add_theme_constant_override("separation", 6)
	_dialog_body.custom_minimum_size = Vector2(540, 0)
	dp.add_child(_dialog_body)


func _update_hud(delta: float, wild: bool) -> void:
	if _hurt.color.a > 0.0:
		_hurt.color.a = maxf(0.0, _hurt.color.a - delta * 0.9)
	if wild:
		_chip.text = "ZONA SEGURA" if _safe else "MONTE ABIERTO  ·  hay criaturas"
		_chip.add_theme_color_override("font_color", Kit.JADE if _safe else Kit.AMBER)
		var f := float(hp) / float(max_hp)
		_bar.value = f
		_bar.color = Kit.BLOOD if f > 0.3 else Kit.AMBER
		_bar.text = "Vida  %d / %d" % [hp, max_hp]
		_bar.queue_redraw()
		if _seeds >= 0:
			_stats.text = "Nivel %d  ·  %d semillas  ·  Clic o J: chispa  ·  F: purificar  ·  M: mapa" % [_level, _seeds]
	# Misión en curso
	var st := str(quest.st)
	_quest_box.visible = st == "active"
	if st == "active":
		var mdef: Dictionary = Wild.MISSIONS[Wild.MISSION]
		var enough := int(quest.n) >= int(quest.need)
		_quest_title.text = "MISIÓN  ·  %s" % str(mdef.name)
		_quest_lines.text = "%s  %s  (%d de %d)\n%s  %s" % ["✔" if enough else "•", str(mdef.steps[0]), int(quest.n), int(quest.need), "•", str(mdef.steps[1])]
	# Avisos grandes: de uno en uno
	if _toast_t > 0.0:
		_toast_t -= delta
		_toast.modulate.a = clampf(minf(_toast_t * 2.5, (4.2 - _toast_t) * 4.0), 0.0, 1.0)
		if _toast_t <= 0.0:
			_toast.visible = false
	elif not _toasts.is_empty() and not _map_box.visible and not _dialog.visible:
		var t: Array = _toasts.pop_front()
		_toast_title.text = str(t[0])
		_toast_title.add_theme_color_override("font_color", t[2])
		_toast_sub.text = str(t[1])
		(_toast as Hud.Plaque).set_accent(t[2])
		_toast.visible = true
		_toast.modulate.a = 0.0
		_toast_t = 4.2
		if not str(t[3]).is_empty():
			Audio.play(str(t[3]), null, -3.0)
	if _map_box.visible:
		_map.refresh(zone, _progress(), known, quest)


func _progress() -> float:
	if not Zones.is_wild(zone):
		return 0.0
	var at := _me()
	var len := Camino.road_length()
	var best := 0.0
	var best_d := INF
	var d := 0.0
	while d <= len:
		var gap := (Camino.road_at(d)[0] as Vector2).distance_to(at)
		if gap < best_d:
			best_d = gap
			best = d
		d += 4.0
	return best / len


func _push_toast(title: String, text: String, color: Color, sound: String) -> void:
	_toasts.append([title, text, color, sound])


func _feed_line(text: String, color: Color) -> void:
	var l := Kit.label(text, 14, color, Kit.bold_font())
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_feed.add_child(l)
	while _feed.get_child_count() > 5:
		var old := _feed.get_child(0)
		_feed.remove_child(old)
		old.queue_free()
	var tw := l.create_tween()
	tw.tween_interval(4.5)
	tw.tween_property(l, "modulate:a", 0.0, 0.8)
	tw.tween_callback(l.queue_free)


func _toggle_map(open: bool) -> void:
	if open == _map_box.visible or (open and (down or _dialog.visible)):
		return
	if open:
		_recapture = Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		_c._was_captured = false
		_map.refresh(zone, _progress(), known, quest)
	elif _recapture:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_map_box.visible = open
	Audio.play("ui_abrir" if open else "ui_cerrar|ui_click")


func open_map() -> void:
	_toggle_map(true)


# ───────────────────────── Diálogo de la misión ─────────────────────────

func _open_dialog() -> void:
	if _dialog.visible or down:
		return
	_recapture = Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_c._was_captured = false
	_fill_dialog()
	_dialog.visible = true
	Audio.play("ui_abrir")


func _close_dialog(recapture: bool) -> void:
	if not _dialog.visible:
		return
	_dialog.visible = false
	Audio.play("ui_cerrar|ui_click")
	if recapture and _recapture:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


## F o Intro con el diálogo abierto: aceptar la misión si aún no se tiene; si no, cerrar.
func _dialog_confirm() -> void:
	if str(quest.st) == "none":
		_send({"t": "quest", "a": "accept"})
	_close_dialog(true)


func _d_label(text: String, size: int, color: Color, font: Font = null, center := false) -> void:
	var l := Kit.label(text, size, color, font)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(540, 0)
	if center:
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_dialog_body.add_child(l)


func _fill_dialog() -> void:
	for c in _dialog_body.get_children():
		_dialog_body.remove_child(c)
		c.queue_free()
	var mdef: Dictionary = Wild.MISSIONS[Wild.MISSION]
	var st := str(quest.st)
	_d_label(str(NPC.name).to_upper(), 24, Kit.GOLD, Kit.title_font(), true)
	_d_label("Camino a Motul  ·  a la salida de Mérida", 13, Color(1, 1, 1, 0.7), null, true)
	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.add_theme_constant_override("separation", 10)
	if st == "none":
		_d_label(str(mdef.offer), 14, Color(1.0, 0.95, 0.8))
		_d_label("MISIÓN  ·  %s" % str(mdef.name).to_upper(), 12, Kit.JADE, Kit.bold_font())
		_d_label("1.  Purifica %d criaturas del camino: déjalas débiles con la chispa (clic o J) y tócalas con F." % int(mdef.purify), 14, Kit.LIME)
		_d_label("2.  Llega al cartel de bienvenida de Motul, al final del camino blanco.", 14, Kit.LIME)
		_d_label("Las criaturas no cruzan las mojoneras de jade: si te ves en apuros, vuelve a la zona segura.", 12, Color(1, 1, 1, 0.6))
		buttons.add_child(_button("Aceptar la misión  ·  F", _dialog_confirm, true))
		buttons.add_child(_button("Ahora no", func() -> void: _close_dialog(true), false))
	elif st == "active":
		var left := maxi(0, int(quest.need) - int(quest.n))
		_d_label("«¿Ya vienes del monte? %s»" % ("Me faltan %d criaturas por ver tranquilas… y luego, el recado al cartel de Motul." % left if left > 0 else "El monte está en calma. Ahora lleva mi recado hasta el cartel de Motul."), 14, Color(1.0, 0.95, 0.8))
		_d_label("Purificadas: %d de %d" % [int(quest.n), int(quest.need)], 14, Kit.LIME, Kit.bold_font())
		buttons.add_child(_button("Entendido  ·  F", func() -> void: _close_dialog(true), true))
	else:
		_d_label("«¡Llegó el recado! Motul vuelve a pedir soga. Gracias, alux: el camino blanco es otra vez de todos.»", 14, Color(1.0, 0.95, 0.8))
		_d_label("Misión cumplida. Más encargos: próximamente.", 12, Color(1, 1, 1, 0.6))
		buttons.add_child(_button("Entendido  ·  F", func() -> void: _close_dialog(true), true))
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 6)
	_dialog_body.add_child(gap)
	_dialog_body.add_child(buttons)


func _button(text: String, on_press: Callable, primary: bool) -> Button:
	var b: Button = _c._button(text, on_press, primary)
	b.custom_minimum_size = Vector2(220, 40)
	return b


# ───────────────────────── Memoria local del mapa ─────────────────────────

## Los lugares descubiertos los recuerda la API (no paga dos veces), pero el contrato no los
## devuelve al entrar: para que el mapa los pinte en la siguiente visita se guardan también en
## este navegador, por jugador. Es sólo para el dibujo; no concede nada.
func _load_known() -> void:
	if not OS.has_feature("web") or _pid.is_empty():
		return
	var raw: Variant = JavaScriptBridge.eval("(function(){try{return localStorage.getItem('alux_lugares_%s')||''}catch(e){return ''}})()" % _pid.substr(0, 8))
	var parsed: Variant = JSON.parse_string(str(raw)) if typeof(raw) == TYPE_STRING and not str(raw).is_empty() else null
	if parsed is Array:
		for id in parsed:
			if typeof(id) == TYPE_STRING and not known.has(id) and Camino.DISCOVERIES.any(func(d: Dictionary) -> bool: return str(d.id) == id):
				known.append(id)


func _save_known() -> void:
	if not OS.has_feature("web") or _pid.is_empty():
		return
	JavaScriptBridge.eval("(function(){try{localStorage.setItem('alux_lugares_%s',%s)}catch(e){}})()" % [_pid.substr(0, 8), JSON.stringify(JSON.stringify(known))])


# ───────────────────────── Pruebas ─────────────────────────

func debug_action(act: String) -> bool:
	match act:
		"travel":
			var g := _gate()
			if not g.is_empty():
				_travel(g)
		"attack":
			# (pruebas) apunta la cámara a la criatura viva más cercana antes de lanzar
			var best_d := INF
			for id in _creatures:
				var cv: CreatureView = _creatures[id]
				var to := Vector2(cv.position.x, cv.position.z) - _me()
				if to.length() < best_d:
					best_d = to.length()
					_c._cam_yaw = atan2(to.x, to.y)
			attack()
		"purify":
			_send({"t": "purify"})
		"use":
			use()
		"map":
			_toggle_map(not _map_box.visible)
		"quest":
			_open_dialog()
		"accept":
			_send({"t": "quest", "a": "accept"})
			_close_dialog(false)
		"closeworld":
			_close_dialog(false)
			_toggle_map(false)
		_:
			return false
	return true


func debug_state() -> Dictionary:
	var creatures := []
	for id in _creatures:
		var cv: CreatureView = _creatures[id]
		creatures.append({"id": id, "kind": cv.kind, "st": cv.state, "hp": cv.hp, "x": snappedf(cv.position.x, 0.01), "z": snappedf(cv.position.z, 0.01)})
	var gates := []
	for g in Zones.GATES.get(zone, []):
		gates.append({"id": g.id, "to": g.to, "x": (g.at as Vector2).x, "z": (g.at as Vector2).y, "r": g.r})
	var g := _gate()
	return {"zone": zone, "wild": Zones.is_wild(zone), "hp": hp, "maxhp": max_hp, "down": down, "safe": _safe, "known": known, "quest": quest,
		"creatures": creatures, "gates": gates, "gate": g.get("id", ""), "prompt": prompt(), "map": _map_box.visible, "dialog": _dialog.visible,
		"toast": _toast_title.text if _toast.visible else "", "toasts": _toasts.size(), "level": _level, "seeds": _seeds,
		"scene": _camino.info() if _camino != null else {}}
