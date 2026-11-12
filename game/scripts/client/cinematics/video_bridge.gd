extends RefCounted
## Puente con el reproductor de vídeo del navegador (game/web/static/cine-video.js).
##
## El motor no reproduce MP4 ni WebM en la web, así que los vídeos de las cinemáticas los pone el
## navegador en un <video> encima del juego. Aquí sólo se le dan órdenes y se le pregunta el estado;
## fuera del navegador (servidor, editor, pruebas) todo responde "no hay vídeo" y el juego usa la
## escena del motor.

var _ok := false
var _asked := {}


func _init() -> void:
	_ok = OS.has_feature("web") and int(JavaScriptBridge.eval("(window.ALUX_VIDEO && typeof ALUX_VIDEO.show === 'function') ? 1 : 0", true)) == 1


func available() -> bool:
	return _ok


## Precarga (una vez) los vídeos indicados. Los que no existan en el manifiesto quedan como "absent".
func preload_clips(ids: Array) -> void:
	var fresh := []
	for id in ids:
		if not _asked.has(id):
			_asked[id] = true
			fresh.append(str(id))
	if _ok and not fresh.is_empty():
		_call("preload", [fresh])


## unknown · absent · loading · ready · playing · ended · error
func status(id: String) -> String:
	if not _ok:
		return "absent"
	return str(_call("status", [id]))


## true si ya se sabe qué pasará con este vídeo (está listo, no existe o falló).
func settled(id: String) -> bool:
	return status(id) in ["ready", "absent", "error", "playing", "ended"]


func show(id: String, volume: float, at := 0.0) -> bool:
	return _ok and bool(_call("show", [id, volume, at]))


## Tiempo del vídeo en pantalla, o -1 si no hay, falló o se atascó.
func tick() -> float:
	if not _ok:
		return -1.0
	return float(_call("tick", []))


func hide(instant := false) -> void:
	if _ok:
		_call("hide", [instant])


func caption(who: String, text: String) -> void:
	if _ok:
		_call("caption", [who, text])


func title(text: String) -> void:
	if _ok:
		_call("title", [text])


func note(text: String) -> void:
	if _ok:
		_call("note", [text])


## Estado completo: manifiesto, vídeos, bytes, tiempos y últimos fallos.
func info() -> Dictionary:
	if not _ok:
		return {}
	var parsed: Variant = JSON.parse_string(str(_call("info", [])))
	return parsed if typeof(parsed) == TYPE_DICTIONARY else {}


func _call(fn: String, args: Array) -> Variant:
	var parts := PackedStringArray()
	for a in args:
		parts.append(JSON.stringify(a))   # los textos viajan como literales JSON: nunca como código
	return JavaScriptBridge.eval("window.ALUX_VIDEO.%s(%s)" % [fn, ", ".join(parts)], true)
