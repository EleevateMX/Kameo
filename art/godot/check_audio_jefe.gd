extends SceneTree
## Comprobación sin ventana del audio del jefe Nojoch Tuunich (art/audio/README.md).
## Carga cada sonido nuevo igual que el juego (`audio.gd`: res://assets/audio/<nombre>.wav)
## y comprueba tipo, duración, frecuencia de muestreo, canales y, en la música, el bucle.
## Uso (desde la raíz del repo, después de `--import`):
##   .tools/godot --headless --path game --script "$PWD/art/godot/check_audio_jefe.gd"
## Devuelve 0 si todo carga y 1 si algo falta o no cuadra.

const Audio := preload("res://scripts/client/audio.gd")

## nombre -> duración esperada (s)
const EFECTOS := {
	"jefe_despierta": 3.9, "jefe_paso": 0.5, "jefe_aviso": 0.8, "jefe_losa": 1.2,
	"jefe_barrido": 0.9, "jefe_llamada": 1.5, "jefe_embestida": 1.4, "jefe_choque": 1.8,
	"jefe_aturdido": 1.5, "pilar_sube": 1.0, "lluvia_piedra": 4.0, "ancla_activa": 0.6,
	"cadenas_jade": 1.2, "corazon_expuesto": 1.0, "corazon_golpe": 0.4, "corazon_libre": 1.6,
	"glifo_restaurado": 1.2, "ritual_toque": 2.0, "silencio_grieta": 0.8, "liberacion": 4.0,
	"pluma_jade": 2.5,
	"cine_patio_silencio": 4.0, "cine_grietas": 4.0, "cine_ojos": 4.0, "cine_en_pie": 4.0,
	"cine_silencio_se_va": 4.0, "cine_pluma": 4.0, "cine_cenote": 4.0,
}
## Música: con el perfil --compacto dura menos, así que sólo se exige un mínimo.
const MUSICA := {"mus_jefe": 12.0, "mus_jefe_furia": 12.0, "mus_recuerdo": 12.0}


func _init() -> void:
	var audio: Node = Audio.new()  # sin árbol: sólo se usa su carga de recursos
	var fallos := 0
	print("%-22s %-15s %7s %7s %6s %-8s %s" % ["sonido", "tipo", "dur s", "Hz", "canal", "bucle", "estado"])
	for grupo in [EFECTOS, MUSICA]:
		var es_musica: bool = grupo == MUSICA
		for nombre in grupo:
			var problemas := PackedStringArray()
			var st: AudioStream = audio._stream(nombre, es_musica)
			var wav := st as AudioStreamWAV
			if st == null:
				problemas.append("no carga (¿falta el .wav o el --import?)")
			elif wav == null:
				problemas.append("no es AudioStreamWAV")
			else:
				var dur := wav.get_length()
				var esperado: float = grupo[nombre]
				if es_musica:
					if dur < esperado:
						problemas.append("dura menos de %.1f s" % esperado)
					var muestras := int(round(dur * float(wav.mix_rate)))
					if wav.loop_mode != AudioStreamWAV.LOOP_FORWARD or wav.loop_begin != 0 or wav.loop_end != muestras:
						problemas.append("bucle mal puesto")
				else:
					if absf(dur - esperado) > 0.01:
						problemas.append("duración ≠ %.2f s" % esperado)
					if wav.loop_mode != AudioStreamWAV.LOOP_DISABLED:
						problemas.append("no debería ir en bucle")
				if wav.mix_rate != 22050:
					problemas.append("frecuencia ≠ 22050 Hz")
				if wav.stereo:
					problemas.append("no es mono")
				if not audio.has(nombre):
					problemas.append("Audio.has() dice que no")
			fallos += 1 if problemas.size() > 0 else 0
			print("%-22s %-15s %7.3f %7d %6s %-8s %s" % [
				nombre, st.get_class() if st != null else "-",
				wav.get_length() if wav != null else 0.0, wav.mix_rate if wav != null else 0,
				("mono" if not wav.stereo else "estéreo") if wav != null else "-",
				("adelante" if wav.loop_mode == AudioStreamWAV.LOOP_FORWARD else "no") if wav != null else "-",
				"ok" if problemas.is_empty() else "FALLO: " + ", ".join(problemas)])
	var cargados: Array = audio.loaded()
	print("\n%d sonidos del jefe cargados por audio.gd; %d con fallos" % [cargados.size(), fallos])
	audio.free()
	quit(1 if fallos > 0 else 0)
