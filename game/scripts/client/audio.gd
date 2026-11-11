extends Node
## Sonido del cliente: ambiente, música y efectos.
##
## Los archivos viven en res://assets/audio/*.wav (audio provisional generado por código, ver
## art/audio/README.md). Si falta alguno, simplemente no suena: el juego no depende del audio.
## Cualquier script puede llamar a `Audio.play("nombre", posición)`; sin instancia (servidor
## dedicado, herramientas) las llamadas no hacen nada.

const DIR := "res://assets/audio/"
const BUSES := ["Music", "SFX", "Ambience"]
const VOICES := 12
## A partir de esta distancia (m) un efecto empieza a perder volumen, y a esta otra deja de oírse.
const NEAR := 5.0
const FAR := 38.0

static var inst: Node = null

var listener := Vector3.ZERO
var _cache := {}
var _voices: Array[AudioStreamPlayer] = []
var _next := 0
var _loops := {}             # nombre -> AudioStreamPlayer
var _music := ""
var _last_played := {}       # nombre -> instante (evita apilar el mismo efecto en el mismo cuadro)
var _time := 0.0


## Reproduce un efecto. Con `pos` se atenúa por distancia al jugador.
static func play(sound: String, pos: Variant = null, volume_db := 0.0, pitch_var := 0.05) -> void:
	if inst != null:
		inst._play(sound, pos, volume_db, pitch_var)


func _ready() -> void:
	inst = self
	for b in BUSES:
		if AudioServer.get_bus_index(b) < 0:
			var i := AudioServer.bus_count
			AudioServer.add_bus(i)
			AudioServer.set_bus_name(i, b)
			AudioServer.set_bus_send(i, "Master")
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
	return _stream(sound) != null


## Nombres de los sonidos cargados hasta ahora (para las pruebas automáticas).
func loaded() -> Array:
	var out := []
	for k in _cache:
		if _cache[k] != null:
			out.append(k)
	out.sort()
	return out


func music() -> String:
	return _music


func _play(sound: String, pos: Variant, volume_db: float, pitch_var: float) -> void:
	var st := _stream(sound)
	if st == null:
		return
	# el mismo efecto no se dispara dos veces en menos de 40 ms (varios golpes en un mismo estado)
	if _time - float(_last_played.get(sound, -1.0)) < 0.04:
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
	p.volume_db = volume_db + linear_to_db(maxf(gain, 0.001))
	p.pitch_scale = 1.0 + randf_range(-pitch_var, pitch_var)
	p.play()


## Deja sonando un bucle (ambiente, brasero…) en el bus indicado.
func loop(sound: String, bus := "Ambience", volume_db := 0.0) -> void:
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


## Volumen de un bucle según la distancia a su fuente (p. ej. el brasero).
func set_loop_distance(sound: String, source: Vector3, base_db := 0.0, far := 22.0) -> void:
	var gain := 1.0 - clampf((source.distance_to(listener) - 2.0) / far, 0.0, 1.0)
	set_loop_volume(sound, base_db + linear_to_db(maxf(gain * gain, 0.001)))


## Cambia la música de fondo ("" la apaga). La anterior se desvanece.
func set_music(sound: String) -> void:
	if sound == _music:
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
	var st := _stream(sound, true)
	if st == null:
		return
	var p := AudioStreamPlayer.new()
	p.stream = st
	p.bus = "Music"
	p.volume_db = -30.0
	add_child(p)
	p.play()
	_loops[sound] = p
	p.create_tween().tween_property(p, "volume_db", 0.0, 1.0)


## Volumen de un bus (0–1). bus: "Master", "Music", "SFX" o "Ambience".
func set_volume(bus: String, value: float) -> void:
	var i := AudioServer.get_bus_index(bus)
	if i < 0:
		return
	AudioServer.set_bus_mute(i, value <= 0.001)
	AudioServer.set_bus_volume_db(i, linear_to_db(clampf(value, 0.001, 1.0)))
