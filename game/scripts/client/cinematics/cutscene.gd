extends RefCounted
## Reproductor de cinemáticas dentro del motor.
##
## Una cinemática es una lista de planos (ver CUTSCENES en shared/story_def.gd). Mientras
## suena, este objeto mueve la cámara y dicta subtítulos, rótulos y sonidos; quien lo usa
## (game_client.gd) deja quieta la cámara de juego y la recupera al terminar.
##
## Dos clases de cinemática (docs/CINEMATICS.md):
##  - local: cada jugador la ve en su pantalla y puede omitirla; la partida de los demás sigue.
##  - compartida: la empieza y la termina el servidor para todos; omitirla es un voto.
##    (Prevista para el jefe; todavía no hay ninguna.)

const World := preload("res://scripts/shared/world_def.gd")
const Audio := preload("res://scripts/client/audio.gd")

signal finished(id: String, skipped: bool)

var active := false
var id := ""
var shared := false
var _shots: Array = []
var _i := -1
var _t := 0.0
var _cam: Camera3D
var _hud: Node
var _names := {}
var _fov_before := 62.0


## names: id de personaje -> nombre que se muestra en los subtítulos.
func play(p_id: String, script: Dictionary, cam: Camera3D, hud: Node, names := {}) -> void:
	id = p_id
	shared = bool(script.get("shared", false))
	_shots = script.get("shots", [])
	_cam = cam
	_hud = hud
	_names = names
	_fov_before = cam.fov
	_i = -1
	_t = 0.0
	active = not _shots.is_empty()
	if not active:
		finished.emit(id, false)
		return
	hud.set_cine(true, not shared)
	_next()


func _next() -> void:
	_i += 1
	_t = 0.0
	if _i >= _shots.size():
		_end(false)
		return
	var shot: Dictionary = _shots[_i]
	var who := str(shot.get("who", ""))
	_hud.cine_subtitle(str(_names.get(who, "")) if not who.is_empty() else "", str(shot.get("text", "")))
	_hud.cine_title(str(shot.get("title", "")))
	if shot.has("sound"):
		Audio.play(str(shot.sound), null, -6.0, 0.0)
	_apply(0.0)


## Avanza la cinemática. Devuelve true mientras siga controlando la cámara.
func process(delta: float) -> bool:
	if not active:
		return false
	var shot: Dictionary = _shots[_i]
	_t += delta
	var dur := maxf(0.1, float(shot.get("dur", 4.0)))
	_apply(clampf(_t / dur, 0.0, 1.0))
	if _t >= dur:
		_next()
	return active


func _apply(k: float) -> void:
	var shot: Dictionary = _shots[_i]
	var e := k * k * (3.0 - 2.0 * k)   # arranque y llegada suaves
	var from: Array = shot.from
	var to: Array = shot.get("to", shot.from)
	var pos: Vector3 = (from[0] as Vector3).lerp(to[0], e)
	var look: Vector3 = (from[1] as Vector3).lerp(to[1], e)
	# la cámara nunca se mete bajo el terreno
	pos.y = maxf(pos.y, World.terrain_h(pos.x, pos.z) + 0.6)
	if pos.distance_to(look) > 0.05:
		_cam.look_at_from_position(pos, look, Vector3.UP)
	_cam.fov = float(shot.get("fov", 62.0))


## Omite lo que queda (sólo las locales; en las compartidas decide el servidor).
func skip() -> void:
	if active and not shared:
		_end(true)


func stop() -> void:
	if active:
		_end(true)


func _end(skipped: bool) -> void:
	active = false
	_cam.fov = _fov_before
	_hud.set_cine(false)
	finished.emit(id, skipped)
