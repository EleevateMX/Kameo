extends Node
## Regulador de resolución: mide los cuadros por segundo reales y sube o baja la escala del 3D
## (`Viewport.scaling_3d_scale`) para sostener el objetivo. La interfaz 2D no se toca: siempre se
## dibuja nítida, a la resolución del lienzo.
##
## Uso mínimo (dos líneas, sirve tal cual en la mazmorra):
##     const PerfGovernor := preload("res://scripts/client/perf_governor.gd")
##     var _gov := PerfGovernor.new()
##     add_child(_gov)                       # desde aquí regula solo el viewport principal
##
## Interfaz:
##     configure({...})   cambia cualquiera de estos ajustes (los que falten se quedan como están):
##         target_fps  (55)       cuadros por segundo que se quieren sostener
##         min_scale   (0.5)      suelo de la escala en ventanas normales
##         max_scale   (1.0)      techo de la escala
##         max_pixels  (2.6e6)    píxeles 3D como mucho: acota las pantallas de alta densidad (4K,
##                                «retina»), donde el lienzo mide ancho × alto × devicePixelRatio
##         min_pixels  (5.2e5)    en lienzos enormes el suelo baja hasta dejar el 3D en ~960×540
##     enabled = false    deja de regular (la escala se queda donde esté); set_scale(x) la fija a mano
##     scale              escala actual (sólo lectura)
##     info()             {scale, fps, target, min, max, enabled, changes, struggling, pixel_bound}
##     señal scale_changed(scale)     cada vez que cambia la escala
##     señal struggling()             sigue por debajo del objetivo y la resolución ya no da más de
##                                    sí (está en el suelo, o bajarla no mejora nada): quien la
##                                    escuche puede bajar la calidad gráfica y llamar a configure()
##
## Cómo decide: mide por ventanas de un segundo (cuenta cuadros; no usa el contador del motor).
## Si faltan cuadros dos ventanas seguidas (un tirón suelto no cuenta) baja, en proporción a lo que
## falta (el coste por píxel va con el cuadrado de la escala). Si sobran, sube despacio, de 0.05 en 0.05, y sólo tras varios segundos
## estables; si una subida provoca una caída, vuelve atrás y tarda el doble en volver a intentarlo
## (histéresis: no oscila). Si dos bajadas seguidas no mejoran nada, el límite no son los píxeles
## (procesador, o una pantalla que va a 30 Hz): deshace esas bajadas y espera un rato sin tocar nada,
## en vez de emborronar la imagen para nada. Ignora los cuadros larguísimos (pestaña en segundo
## plano, carga) y los primeros segundos. Cada cambio reasigna los búferes del 3D, por eso se cambia
## poco y a pasos.
##
## Pendiente de medir en un navegador con tarjeta gráfica real: los umbrales (objetivo, márgenes,
## segundos de espera) están razonados, no afinados; el entorno de desarrollo dibuja por software.

signal scale_changed(scale: float)
signal struggling()

const STEP := 0.05
const WINDOW := 1.0            # segundos por medida
const WARMUP := 3.0            # al arrancar (o al reconfigurar) no se decide nada
const DOWN_MARGIN := 0.9       # por debajo del 90 % del objetivo se baja
const UP_MARGIN := 0.97        # por encima del 97 % se considera que va sobrado
const STRUGGLE_WINDOWS := 4    # ventanas lentas seguidas en el suelo antes de avisar
const HOLD_WINDOWS := 20       # espera tras comprobar que bajar la escala no ayuda

var enabled := true
var scale := 1.0

var _target := 55.0
var _min := 0.5
var _max := 1.0
var _max_pixels := 2.6e6
var _min_pixels := 5.2e5
var _frames := 0
var _time := 0.0
var _warm := WARMUP
var _fps := 0.0
var _good := 0                 # ventanas buenas seguidas
var _slow := 0                 # ventanas lentas seguidas
var _long := 0                 # cuadros de más de un segundo seguidos
var _need_good := 4            # las que hacen falta para subir (se dobla si la subida sale mal)
var _slow_at_floor := 0
var _rose := false             # la última decisión fue subir
var _changes := 0
var _floor := 0.5              # límites efectivos para el tamaño actual del lienzo
var _ceil := 1.0
var _last_size := Vector2i.ZERO
var _struggling := false
var _probe := false            # la última decisión fue bajar: ¿sirvió?
var _probe_fps := 0.0
var _probe_from := 1.0
var _useless := 0              # bajadas seguidas que no mejoraron nada
var _hold := 0
var _pixel_bound := true


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_refresh_limits()
	_apply(_ceil)


func configure(opts: Dictionary) -> void:
	_target = float(opts.get("target_fps", _target))
	_min = clampf(float(opts.get("min_scale", _min)), 0.25, 1.0)
	_max = clampf(float(opts.get("max_scale", _max)), _min, 1.0)
	_max_pixels = float(opts.get("max_pixels", _max_pixels))
	_min_pixels = float(opts.get("min_pixels", _min_pixels))
	_warm = maxf(_warm, 1.5)
	_good = 0
	_slow = 0
	_slow_at_floor = 0
	_struggling = false
	_probe = false
	_useless = 0
	_hold = 0
	if is_inside_tree():
		_refresh_limits()
		_apply(clampf(scale, _floor, _ceil))


## Fija la escala a mano (dentro de los límites). Con `enabled = true` el regulador sigue desde ahí.
func set_scale(value: float) -> void:
	_apply(clampf(value, _floor, _ceil))
	_good = 0


func info() -> Dictionary:
	return {"scale": snappedf(scale, 0.01), "fps": snappedf(_fps, 0.1), "target": _target, "min": snappedf(_floor, 0.01),
		"max": snappedf(_ceil, 0.01), "enabled": enabled, "changes": _changes, "struggling": _struggling, "pixel_bound": _pixel_bound}


func _process(delta: float) -> void:
	# El lienzo cambió de tamaño (ventana, pantalla completa, otra pantalla): límites nuevos
	var size := get_window().size
	if size != _last_size:
		_refresh_limits()
		if scale > _ceil or scale < _floor:
			_apply(clampf(scale, _floor, _ceil))
	if not enabled:
		return
	if delta > 1.0:
		# Un cuadro larguísimo suelto es la pestaña que vuelve del segundo plano o una carga: no es
		# una medida de la tarjeta gráfica. Tres seguidos sí lo son: el equipo va a menos de 1 FPS.
		_long += 1
		if _long < 3:
			_frames = 0
			_time = 0.0
			return
	else:
		_long = 0
	if _warm > 0.0:
		_warm -= delta
		return
	_frames += 1
	_time += delta
	if _time < WINDOW:
		return
	_fps = float(_frames) / _time
	_frames = 0
	_time = 0.0
	_decide()


func _decide() -> void:
	if _hold > 0:
		_hold -= 1
		return
	if _probe:
		_probe = false
		if _fps < _probe_fps * 1.04:
			_useless += 1
			if _useless >= 2:
				# dos bajadas sin mejora: el cuello de botella no es la resolución
				_useless = 0
				_hold = HOLD_WINDOWS
				_pixel_bound = false
				_apply(clampf(_probe_from, _floor, _ceil))
				# Bajar la calidad (menos pases y sombras) sí puede ayudar; salvo que el equipo vaya
				# clavado a 30: eso es una pantalla o un navegador limitado a 30 Hz, no falta de potencia
				if absf(_fps - 30.0) > 1.6:
					_struggling = true
					struggling.emit()
				return
		else:
			_useless = 0
			_pixel_bound = true
	if _fps < _target * DOWN_MARGIN:
		_slow += 1
		if _slow < 2:
			return
		if _rose:
			_need_good = mini(_need_good * 2, 64)   # la subida no se sostuvo: la próxima, más tarde
		_rose = false
		_good = 0
		if scale > _floor + 0.001:
			_slow_at_floor = 0
			# el coste por píxel va con el cuadrado de la escala; nunca más de un 30 % de golpe
			var want := scale * clampf(sqrt(_fps / _target), 0.7, 0.95)
			if _useless == 0:
				_probe_from = scale
			_probe = true
			_probe_fps = _fps
			_apply(clampf(floorf(want / STEP) * STEP, _floor, _ceil))
		else:
			_slow_at_floor += 1
			if _slow_at_floor >= STRUGGLE_WINDOWS:
				_slow_at_floor = 0
				_struggling = true
				struggling.emit()
	elif _fps >= _target * UP_MARGIN:
		_slow = 0
		_slow_at_floor = 0
		_struggling = false
		_good += 1
		if _good >= _need_good and scale < _ceil - 0.001:
			_good = 0
			_rose = true
			_apply(minf(scale + STEP, _ceil))
		elif _good >= _need_good * 3:
			# lleva mucho rato estable tras una subida: se da por buena
			_rose = false
			_need_good = maxi(4, _need_good / 2)
			_good = 0
	else:
		# entre los dos márgenes: ni sube ni baja
		_slow = 0
		_good = 0
		_slow_at_floor = 0


func _refresh_limits() -> void:
	_last_size = get_window().size
	var pixels := maxf(1.0, float(_last_size.x) * float(_last_size.y))
	_ceil = clampf(minf(_max, sqrt(_max_pixels / pixels)), 0.25, 1.0)
	_floor = minf(clampf(sqrt(_min_pixels / pixels), 0.25, _min), _ceil)


func _apply(value: float) -> void:
	value = snappedf(value, 0.01)
	var vp := get_viewport()
	if vp == null:
		return
	if is_equal_approx(value, scale) and is_equal_approx(vp.scaling_3d_scale, value):
		return
	scale = value
	vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
	vp.scaling_3d_scale = value
	_changes += 1
	_warm = maxf(_warm, 0.6)   # el cambio mismo cuesta un tirón: no se mide
	scale_changed.emit(value)
