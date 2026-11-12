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
##
## Un plano puede llevar un vídeo (campo `video`). Si el navegador lo tiene listo se muestra
## encima del juego mientras dura el plano; el plano del motor sigue corriendo por debajo, así que
## si el vídeo falta, falla o se atasca basta con quitarlo para seguir viendo la escena.

const World := preload("res://scripts/shared/world_def.gd")
const Audio := preload("res://scripts/client/audio.gd")

signal finished(id: String, skipped: bool)
## El vídeo tapa (o deja de tapar) el juego: sirve para no dibujar el mundo mientras no se ve.
signal covered(on: bool)

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

## Puente de vídeo (video_bridge.gd) y volumen con el que suenan los vídeos que traen sonido.
var video: RefCounted
var volume := 1.0
## Para las métricas: planos que se vieron como vídeo y veces que hubo que volver al motor.
var video_shots := 0
var fallbacks := 0
var ended_on_video := false
var _video_on := false
var _poll := 0.0
## La escena se mide con el reloj real, no sumando cuadros: si el navegador va lento o se queda
## parado un momento, la escena no se retrasa respecto al servidor ni a los demás jugadores.
var _clock_ms := 0          # instante (ms) en que la escena estaría en su segundo cero
var _shot_from := 0.0       # segundo de la escena en que empezó el plano en curso
var _last_ms := 0


## names: id de personaje -> nombre que se muestra en los subtítulos.
## start_at: segundos ya transcurridos (quien llega a mitad de una compartida se engancha ahí).
func play(p_id: String, script: Dictionary, cam: Camera3D, hud: Node, names := {}, start_at := 0.0) -> void:
	id = p_id
	shared = bool(script.get("shared", false))
	_shots = script.get("shots", [])
	_cam = cam
	_hud = hud
	_names = names
	_fov_before = cam.fov
	video_shots = 0
	fallbacks = 0
	ended_on_video = false
	_i = -1
	_t = 0.0
	active = not _shots.is_empty()
	if not active:
		finished.emit(id, false)
		return
	hud.set_cine(true, true)
	_clock_ms = Time.get_ticks_msec() - int(maxf(start_at, 0.0) * 1000.0)
	_last_ms = Time.get_ticks_msec()
	_shot_from = 0.0
	# Salta los planos que ya pasaron
	var skip := maxf(start_at, 0.0)
	while _i + 1 < _shots.size() - 1 and skip >= float(_shots[_i + 1].get("dur", 4.0)):
		skip -= float(_shots[_i + 1].get("dur", 4.0))
		_shot_from += float(_shots[_i + 1].get("dur", 4.0))
		_i += 1
	_next(skip)


## Adelanta la escena `seconds` segundos (capturas y pruebas).
func seek(seconds: float) -> void:
	_clock_ms -= int(seconds * 1000.0)


func _next(offset := 0.0) -> void:
	_i += 1
	_t = offset
	if _i >= _shots.size():
		_end(false)
		return
	var shot: Dictionary = _shots[_i]
	var dur := maxf(0.1, float(shot.get("dur", 4.0)))
	# Vídeo del plano, si está listo; si no, se ve el plano del motor
	var clip := str(shot.get("video", ""))
	if not clip.is_empty() and video != null and video.status(clip) == "ready" and video.show(clip, volume, offset):
		video_shots += 1
		_poll = 0.6
		if not _video_on:
			_video_on = true
			covered.emit(true)
	elif _video_on:
		_drop_video(true)
	var who := str(shot.get("who", ""))
	var speaker := str(_names.get(who, "")) if not who.is_empty() else ""
	var text := str(shot.get("text", ""))
	var title := str(shot.get("title", ""))
	_hud.cine_subtitle(speaker, text)
	_hud.cine_title(title)
	if video != null:
		video.caption(speaker, text)
		video.title(title)
	if shot.has("sound") and offset < 0.5:
		Audio.play(str(shot.sound), null, -6.0, 0.0)
	_apply(clampf(_t / dur, 0.0, 1.0))


## Quita el vídeo y deja a la vista la escena del motor.
func _drop_video(instant: bool) -> void:
	if not _video_on:
		return
	_video_on = false
	covered.emit(false)
	video.hide(instant)


func using_video() -> bool:
	return _video_on


## Segundos transcurridos del plano en curso y fracción (0–1) de su duración.
func shot_time() -> float:
	return _t


func shot_k() -> float:
	return clampf(_t / _dur(_i), 0.0, 1.0) if active else 0.0


## Plano en curso ({} si no hay ninguno).
func current_shot() -> Dictionary:
	return _shots[_i] if active and _i >= 0 and _i < _shots.size() else {}


## Avanza la cinemática. Devuelve true mientras siga controlando la cámara.
func process(_delta: float) -> bool:
	if not active:
		return false
	var now := Time.get_ticks_msec()
	var delta := float(now - _last_ms) / 1000.0
	_last_ms = now
	var elapsed := float(now - _clock_ms) / 1000.0
	if elapsed - _shot_from >= _dur(_i):
		# Toca cambiar de plano; tras un parón se pasan de largo los que ya quedaron atrás
		while _i < _shots.size() and elapsed - _shot_from >= _dur(_i):
			_shot_from += _dur(_i)
			_i += 1
		if _i >= _shots.size():
			_end(false)
			return false
		_i -= 1
		_next(elapsed - _shot_from)
		return active
	_t = elapsed - _shot_from
	if _video_on:
		# El vídeo tiene que avanzar: si falla o se atasca, se sigue con el motor sin detener nada
		_poll -= delta
		if _poll <= 0.0:
			_poll = 0.3
			if video.tick() < 0.0:
				fallbacks += 1
				_drop_video(true)
	_apply(clampf(_t / _dur(_i), 0.0, 1.0))
	return active


func _dur(i: int) -> float:
	return maxf(0.1, float(_shots[i].get("dur", 4.0))) if i >= 0 and i < _shots.size() else 0.1


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
	ended_on_video = _video_on
	_drop_video(false)   # con fundido a negro: quien la usa decide cómo se vuelve al juego
	_cam.fov = _fov_before
	_hud.set_cine(false)
	finished.emit(id, skipped)
