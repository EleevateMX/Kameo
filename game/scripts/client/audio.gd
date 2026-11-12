extends Node
## Sonido del cliente: efectos, interfaz, ambiente, música y bandas sonoras de las cinemáticas.
##
## Dos caminos, según lo que el motor puede hacer bien en la exportación web (docs/AUDIO.md):
##   · Efectos e interfaz: archivos de res://assets/audio/*.wav, reproducidos por el motor en los
##     buses SFX y UI. Son cortos y necesitan respuesta inmediata.
##   · Música, ambientes y cinemáticas: archivos de game/web/static/audio, reproducidos por el
##     mezclador de la página (alux-audio.js), que hace bucles sin corte, fundidos, atenuación de
##     la música y limitación de picos. Fuera del navegador no hay mezclador: se intenta con el
##     motor y, si el archivo no está en res://, simplemente no suena.
## Si falta un archivo, no suena y el juego sigue: nada depende del audio.
## Cualquier script puede llamar a `Audio.play("nombre", posición)`; sin instancia (servidor
## dedicado, herramientas) las llamadas no hacen nada.

const World := preload("res://scripts/shared/world_def.gd")
const DIR := "res://assets/audio/"
## Buses de res://default_bus_layout.tres. NO se crean en ejecución (ver _ready).
const BUSES := ["Music", "Ambience", "SFX", "UI", "Cinematics", "Voice"]
const VOICES := 16
## A partir de esta distancia (m) un efecto empieza a perder volumen, y a esta otra deja de oírse.
const NEAR := 5.0
const FAR := 38.0
## Avisos que no pertenecen al mundo sino a la interfaz (además de todo lo que empieza por «ui_»)
const UI_SOUNDS := ["objetivo", "sin_energia", "aliado_caido", "aliado_revive", "punto_control"]

static var inst: Node = null

var listener := Vector3.ZERO
var _cache := {}
var _variants := {}          # nombre -> [nombre, nombre_2, …] (variantes para no repetir)
var _last_variant := {}
var _voices: Array[AudioStreamPlayer] = []
var _next := 0
var _loops := {}             # sin mezclador: nombre -> AudioStreamPlayer
var _layers := {}            # con mezclador: capa de ambiente -> volumen 0–1 pedido
var _music := ""
var _cine := ""
var _last_played := {}       # nombre -> instante (evita apilar el mismo efecto en el mismo cuadro)
var _time := 0.0
var _web := false            # hay mezclador propio en la página


## Reproduce un efecto. Con `pos` se atenúa por distancia al jugador.
static func play(sound: String, pos: Variant = null, volume_db := 0.0, pitch_var := 0.05) -> void:
	if inst != null:
		inst._play(sound, pos, volume_db, pitch_var)


## Baja la música un momento para dejar sitio a un golpe grande.
static func duck(db := -8.0, hold := 0.5, release := 0.7) -> void:
	if inst != null and inst._web:
		inst._snd("duck(%s,0.05,%s,%s)" % [db, hold, release])


func _ready() -> void:
	inst = self
	# Los buses vienen de res://default_bus_layout.tres. NO se crean aquí: en la exportación web
	# AudioServer.add_bus() coloca el bus nuevo en la posición 0 del mezclador del navegador y deja
	# el maestro sin conexión con la salida (todo «suena» y no se oye nada). Ver docs/AUDIO.md.
	for b in BUSES:
		if AudioServer.get_bus_index(b) < 0:
			push_error("Audio: falta el bus «%s» en default_bus_layout.tres" % b)
	_web = OS.has_feature("web") and bool(JavaScriptBridge.eval("!!(window.ALUX_SND&&ALUX_SND.ok)"))
	for i in VOICES:
		var p := AudioStreamPlayer.new()
		p.bus = "SFX"
		add_child(p)
		_voices.append(p)


func _exit_tree() -> void:
	if inst == self:
		inst = null


func _process(delta: float) -> void:
	_time += delta


## Llama al mezclador de la página. Nunca lanza: un fallo de audio no puede parar el juego.
func _snd(code: String) -> void:
	JavaScriptBridge.eval("try{ALUX_SND.%s}catch(e){}" % code)


func _stream(sound: String, looped := false) -> AudioStream:
	if _cache.has(sound):
		return _cache[sound]
	var path := DIR + sound + ".wav"
	var st: AudioStream = null
	if ResourceLoader.exists(path):
		st = load(path) as AudioStream
		if looped and st is AudioStreamWAV:
			var wav := st as AudioStreamWAV
			wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
			wav.loop_begin = 0
			wav.loop_end = int(round(wav.get_length() * float(wav.mix_rate)))
	_cache[sound] = st
	return st


func has(sound: String) -> bool:
	if _web and (sound.begins_with("mus_") or sound.begins_with("amb_")):
		return bool(JavaScriptBridge.eval("ALUX_SND.has(%s)" % JSON.stringify(sound)))
	return _stream(sound) != null


## Nombres de los efectos cargados hasta ahora (para las pruebas automáticas).
func loaded() -> Array:
	var out := []
	for k in _cache:
		if _cache[k] != null:
			out.append(k)
	out.sort()
	return out


func music() -> String:
	return _music


func has_mixer() -> bool:
	return _web


## Volumen pedido para una capa de ambiente (0 si no suena).
func layer(sound: String) -> float:
	return float(_layers.get(sound, 0.0))


## Estado real del audio en el navegador: contexto, nivel que está saliendo, pistas, errores.
## Fuera del navegador sólo dice que no hay mezclador.
func info() -> Dictionary:
	if not _web:
		return {"ok": false, "ctx": "sin mezclador", "rms": 0.0, "peak": 0.0, "peakMax": 0.0, "errors": []}
	var parsed: Variant = JSON.parse_string(str(JavaScriptBridge.eval("ALUX_SND.state()")))
	return parsed if parsed is Dictionary else {"ok": false, "ctx": "sin respuesta", "rms": 0.0, "peak": 0.0, "peakMax": 0.0, "errors": []}


## Sonido de prueba del menú. Se mide después con info().peak: no basta con haber llamado a play().
func test() -> void:
	if _web:
		_snd("resume('prueba')")
		_snd("resetPeak()")
	if _stream("ui_prueba") != null:
		_play("ui_prueba", null, 0.0, 0.0)
	elif _web:
		_snd("beep()")
	else:
		_play("objetivo", null, 0.0, 0.0)


## Variantes numeradas de un efecto («chispa», «chispa_2», «chispa_3»): se elige una distinta de
## la anterior para que una ráfaga no suene a máquina.
func _variant(sound: String) -> String:
	if not _variants.has(sound):
		var list := [sound]
		var base := sound
		var first := 2
		if sound.ends_with("_1"):
			base = sound.trim_suffix("_1")
		for i in range(first, 6):
			if not ResourceLoader.exists(DIR + "%s_%d.wav" % [base, i]):
				break
			list.append("%s_%d" % [base, i])
		_variants[sound] = list
	var options: Array = _variants[sound]
	if options.size() == 1:
		return sound
	var pick := randi() % options.size()
	if pick == int(_last_variant.get(sound, -1)):
		pick = (pick + 1) % options.size()
	_last_variant[sound] = pick
	return str(options[pick])


## Qué pisa quien está en `pos`: "agua", "piedra" (plaza, pirámide, santuario) o "hierba".
static func ground_at(pos: Vector3) -> String:
	var here := Vector2(pos.x, pos.z)
	if World.terrain_h(pos.x, pos.z) < World.WATER_LEVEL + 0.3:
		return "agua"
	if here.length() < 7.5 or here.distance_to(World.SANCTUARY) < 15.0 or here.distance_to(World.PYRAMID) < 9.0:
		return "piedra"
	return "hierba"


## `sound` puede traer alternativas, «nuevo|antiguo»: suena la primera que exista.
func _play(sound: String, pos: Variant, volume_db: float, pitch_var: float) -> void:
	if "|" in sound:
		for option in sound.split("|"):
			if ResourceLoader.exists(DIR + option + ".wav"):
				_play(option, pos, volume_db, pitch_var)
				return
		return
	# el mismo efecto no se dispara dos veces en menos de 40 ms (varios golpes en un mismo estado)
	if _time - float(_last_played.get(sound, -1.0)) < 0.04:
		return
	var st := _stream(_variant(sound))
	if st == null:
		return
	_last_played[sound] = _time
	var gain := 1.0
	if pos is Vector3:
		var d := (pos as Vector3).distance_to(listener)
		if d >= FAR:
			return
		gain = 1.0 - clampf((d - NEAR) / (FAR - NEAR), 0.0, 1.0)
		gain = gain * gain
	var p := _voices[_next]
	_next = (_next + 1) % VOICES
	p.stop()
	p.stream = st
	p.bus = "UI" if (sound.begins_with("ui_") or sound in UI_SOUNDS) else "SFX"
	p.volume_db = volume_db + linear_to_db(maxf(gain, 0.001))
	p.pitch_scale = 1.0 + randf_range(-pitch_var, pitch_var)
	p.play()


## Capas de ambiente que deben sonar ahora: { "amb_selva": 0.8, "amb_aves": 0.5 }. Las que no
## estén se apagan con un fundido. Cada capa es un bucle sin corte.
func ambience(mix: Dictionary, secs := 1.2) -> void:
	if _web:
		if mix.hash() == _layers.hash():
			return
		_layers = mix.duplicate()
		_snd("ambience(%s,%s)" % [JSON.stringify(mix), secs])
		return
	for sound in mix:
		_loop(str(sound), "Ambience", linear_to_db(maxf(float(mix[sound]), 0.001)))
		set_loop_volume(str(sound), linear_to_db(maxf(float(mix[sound]), 0.001)))
	for sound in _loops.keys():
		if sound != _music and not mix.has(sound):
			(_loops[sound] as AudioStreamPlayer).queue_free()
			_loops.erase(sound)


## Volumen de una capa que ya suena, según la distancia a su fuente (p. ej. el brasero).
func set_layer_distance(sound: String, source: Vector3, base := 1.0, far := 22.0) -> void:
	var gain := 1.0 - clampf((source.distance_to(listener) - 2.0) / far, 0.0, 1.0)
	gain = base * gain * gain
	if _web:
		if _layers.has(sound) and absf(float(_layers[sound]) - gain) > 0.02:
			_layers[sound] = gain
			_snd("loopGain(%s,%s)" % [JSON.stringify(sound), snappedf(gain, 0.001)])
		return
	set_loop_volume(sound, linear_to_db(maxf(gain, 0.001)))


func _loop(sound: String, bus: String, volume_db: float) -> void:
	if _loops.has(sound):
		return
	var st := _stream(sound, true)
	if st == null:
		return
	var p := AudioStreamPlayer.new()
	p.stream = st
	p.bus = bus
	p.volume_db = volume_db
	add_child(p)
	p.play()
	_loops[sound] = p


func set_loop_volume(sound: String, volume_db: float) -> void:
	var p: AudioStreamPlayer = _loops.get(sound)
	if p != null and absf(p.volume_db - volume_db) > 0.5:
		p.volume_db = volume_db


## Cambia la música de fondo ("" la apaga) con un fundido cruzado.
func set_music(sound: String, fade := 1.6) -> void:
	if sound == _music:
		return
	if _web:
		_music = sound
		_snd("music(%s,%s)" % [JSON.stringify(sound), fade])
		return
	var old: AudioStreamPlayer = _loops.get(_music)
	if old != null:
		_loops.erase(_music)
		var tw := old.create_tween()
		tw.tween_property(old, "volume_db", -50.0, 1.2)
		tw.tween_callback(old.queue_free)
	_music = sound
	if sound.is_empty():
		return
	_loop(sound, "Music", -30.0)
	var p: AudioStreamPlayer = _loops.get(sound)
	if p != null:
		p.create_tween().tween_property(p, "volume_db", 0.0, 1.0)


## Una pieza suelta sobre la música (fanfarria), que baja mientras suena.
func sting(sound: String, duck_db := -12.0, hold := 6.0) -> void:
	if _web and has(sound):
		_snd("shot(%s,'Music',0)" % JSON.stringify(sound))
		_snd("duck(%s,0.2,%s,2.0)" % [duck_db, hold])


## Banda sonora de una cinemática (efectos y música en pistas separadas), empezando en el segundo
## `offset` de la escena. Es la misma se vea como vídeo o con el motor, y suena una sola vez.
## Devuelve false si no hay banda sonora: entonces quien llama usa los efectos por plano.
func cine_start(id: String, offset := 0.0) -> bool:
	if not _web or not bool(JavaScriptBridge.eval("ALUX_SND.hasCine(%s)&&ALUX_SND.manifestReady" % JSON.stringify(id))):
		return false
	_cine = id
	_snd("cine(%s,%s)" % [JSON.stringify(id), snappedf(offset, 0.01)])
	return true


## Fin de la cinemática: `fade` corto si se omite, largo si terminó sola (deja la cola).
func cine_stop(fade := 0.3) -> void:
	if _cine.is_empty():
		return
	_cine = ""
	if _web:
		_snd("cineStop(%s)" % fade)


## Volumen de un bus (0–1): "Master", "Music", "Ambience", "SFX", "UI", "Cinematics" o "Voice".
func set_volume(bus: String, value: float) -> void:
	var i := AudioServer.get_bus_index(bus)
	if i >= 0:
		AudioServer.set_bus_mute(i, value <= 0.001)
		AudioServer.set_bus_volume_db(i, linear_to_db(clampf(value, 0.001, 1.0)))
	if _web:
		_snd("volume(%s,%s)" % [JSON.stringify(bus), snappedf(value, 0.001)])
		if bus == "Master":
			_snd("setMuted(%s)" % ("true" if value <= 0.001 else "false"))
