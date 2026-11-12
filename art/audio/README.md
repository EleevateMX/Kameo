# Audio provisional de ALUX

Primera capa de sonido del juego: 4 bucles (dos ambientes y dos músicas) y 34 efectos.
Segunda capa, para el jefe Nojoch Tuunich y sus dos cinemáticas: 3 músicas y 28 efectos
(ver «Jefe Nojoch Tuunich»). En total, 69 archivos.
**Es audio provisional y sintetizado**: todo sale de `gen_audio.py` (senos, ruido filtrado
y envolventes), sin grabaciones ni muestras de terceros. Es original y no tiene licencias
que cumplir. Nadie lo ha escuchado todavía: se ha comprobado con mediciones (niveles,
espectro, costuras, seguimiento de tono), no de oído. Habrá que sustituirlo o retocarlo
cuando alguien lo oiga en el juego.

Formato de todos los archivos: WAV mono, 22050 Hz, 16 bits PCM, en `game/assets/audio/`.

## Cómo regenerar

Solo hace falta Python con numpy (sirve el entorno de Blender del proyecto; no usa `bpy`):

```bash
.tools/blender-venv/bin/python art/audio/gen_audio.py              # genera todo y lo comprueba
.tools/blender-venv/bin/python art/audio/gen_audio.py --check      # solo comprueba lo que hay en disco
.tools/blender-venv/bin/python art/audio/gen_audio.py --compacto   # variante corta, ver «Tamaño»
.tools/blender-venv/bin/python art/audio/gen_audio.py --salida DIR # escribe en otra carpeta
```

Tarda unos 6 s. Las semillas son fijas (cada sonido deriva la suya de su nombre), así que
dos ejecuciones dan archivos idénticos byte a byte (comprobado con numpy 2.5.4; con otra
versión de numpy o en otra máquina podría cambiar algún bit por redondeo).

Para cambiar un sonido se edita su función en `gen_audio.py` (una por sonido, con el
mismo nombre que el archivo) o su fila en las tablas `BUCLES` y `EFECTOS` (las del jefe,
`BUCLES_JEFE` y `EFECTOS_JEFE`: duración, nivel, corte de agudos, fundido final) y se
vuelve a ejecutar. Añadir sonidos no cambia los que ya había: cada uno tiene su semilla.

## Qué es cada sonido

Bucles (se construyen de forma circular: el final empalma con el principio):

| Archivo | Duración | Qué es |
| --- | --- | --- |
| `amb_selva.wav` | 10.0 s | Selva de día: viento y hojas, insectos agudos con trémolo y ocho cantos de ave dispersos. |
| `amb_brasero.wav` | 4.0 s | Fuego del brasero: retumbo grave, rugido medio y chasquidos. |
| `mus_claro.wav` | 19.2 s | Música de exploración. Re menor pentatónica, 75 BPM, 6 compases de 4/4: colchón, kalimba, flauta de barro y tambor de mano muy suave. |
| `mus_emboscada.wav` | 9.6 s | Música de emboscada. 150 BPM, 6 compases de 4/4: tom grave, palmada, sonaja, dron que late y ostinato de dos notas en la kalimba. |

Efectos (empiezan y acaban en cero):

| Archivo | Duración | Qué es |
| --- | --- | --- |
| `paso_1.wav`, `paso_2.wav`, `paso_3.wav` | 0.12 s | Pasos suaves sobre piedra y tierra (tres variantes para alternar). |
| `salto.wav` | 0.20 s | Salto: soplido que sube. |
| `aterrizar.wav` | 0.20 s | Aterrizaje: golpe sordo con algo de polvo. |
| `chapoteo.wav` | 0.50 s | Chapoteo: impacto, rocío y gotas. |
| `chispa.wav` | 0.30 s | Chispa de jade: gorjeo vítreo ascendente con destellos. |
| `chispa_impacto.wav` | 0.30 s | Impacto de la chispa: estallido vítreo corto. |
| `esquiva.wav` | 0.25 s | Esquiva: soplido de aire. |
| `garras.wav` | 0.25 s | Garras: tres tajos rápidos. |
| `zarpazo_carga.wav` | 0.80 s | Carga del zarpazo: retumbo y quejido que suben. |
| `zarpazo.wav` | 0.50 s | Zarpazo cargado: golpe grave y chasquido. |
| `salto_jaguar.wav` | 0.50 s | Salto ofensivo: gruñido grave y soplido. |
| `salto_impacto.wav` | 0.40 s | Impacto del salto contra el suelo. |
| `golpe.wav` | 0.15 s | Un enemigo recibe un golpe. |
| `dano.wav` | 0.30 s | El jugador recibe daño: golpe sordo y tono que cae. |
| `caida.wav` | 0.90 s | El jugador cae: tres notas tristes que bajan (La, Fa, Re). |
| `reaparecer.wav` | 0.90 s | Reaparición: campanitas que suben con brillo. |
| `curar.wav` | 0.80 s | Curación: arpegio cálido ascendente con destellos. |
| `purificar.wav` | 1.00 s | Purificación: acorde de campanas que florece (Fa mayor). |
| `transformar.wav` | 0.70 s | Transformación: remolino de aire y acorde brillante. |
| `enemigo_aviso.wav` | 0.35 s | Aviso de ataque enemigo: dos tonos tensos que suben. |
| `enemigo_golpe.wav` | 0.40 s | Golpe del guardián de piedra, con escombros. |
| `enemigo_muere.wav` | 0.50 s | Enemigo derrotado: se desmorona y se disuelve. |
| `altar_on.wav` | 0.40 s | Altar activado: piedra que resuena y campana. |
| `altar_off.wav` | 0.25 s | Altar liberado: más grave y apagado. |
| `santuario_abre.wav` | 2.20 s | Se disuelve el sello del santuario: piedra que roza y acorde que crece. |
| `emboscada.wav` | 1.60 s | Aviso de emboscada: caracol grave y tambor. |
| `victoria.wav` | 3.20 s | Victoria: frase pentatónica ascendente (kalimba y flauta) y acorde final. |
| `derrota.wav` | 2.60 s | Derrota: frase lenta descendente, suave. |
| `ui_click.wav` | 0.06 s | Clic de interfaz, como de madera. |
| `ui_abrir.wav` | 0.20 s | Abrir menú: ola suave. |
| `sin_energia.wav` | 0.15 s | Habilidad no disponible: doble pitido apagado. |
| `objetivo.wav` | 0.50 s | Objetivo actualizado: dos notas de campanita. |

Toda la parte tonal usa las mismas cinco notas (Re, Fa, Sol, La, Do), así que los efectos
no desafinan con la música. Las melodías son propias; no imitan ninguna obra existente.

## Jefe Nojoch Tuunich

Sonidos del combate contra el primer jefe (`docs/BOSS.md`) y de sus dos cinemáticas. Mismo
formato y mismo generador. Pico y RMS están medidos sobre los archivos (dBFS); «RMS 50 ms»
es el tramo más fuerte y sirve para comparar pegada (`enemigo_golpe`: −5.0 / −16.8 / −10.4;
`objetivo`: −12.0 / −25.5 / −20.4; `mus_emboscada`: −7.9 / −22.0 / −16.8).

Efectos del combate (bus SFX):

| Archivo | Duración | Para qué sirve | Pico | RMS | RMS 50 ms |
| --- | --- | --- | --- | --- | --- |
| `jefe_despierta.wav` | 3.5 s | El coloso despierta: 1.7 s de grietas que se agolpan y un rugido grave de roca que se desplaza, con un asiento final. | −3.0 | −22.5 | −15.2 |
| `jefe_paso.wav` | 0.5 s | Pisada pesada de piedra; se repite a cada paso, por eso va más baja que los golpes. | −8.0 | −24.0 | −15.5 |
| `jefe_aviso.wav` | 0.8 s | Anticipación de un golpe: la piedra se tensa y cruje cada vez más rápido y más agudo. Acaba fuerte. | −7.0 | −22.9 | −18.0 |
| `jefe_losa.wav` | 1.2 s | Golpe de losa: impacto enorme contra el suelo y cola de escombros. Es el efecto con más pegada del juego. | −3.0 | −17.7 | −8.9 |
| `jefe_barrido.wav` | 0.9 s | Barrido: silbido grave de una masa que pasa, con roce de piedra. | −6.0 | −19.9 | −15.4 |
| `jefe_llamada.wav` | 1.5 s | Llamada del Silencio: doble golpe en el suelo y zumbido oscuro que crece. | −4.0 | −20.7 | −15.3 |
| `jefe_embestida.wav` | 1.4 s | Embestida: arrastre de piedra y zancadas que se aceleran. Acaba en su punto más fuerte para enlazar con `jefe_choque`. | −5.0 | −22.6 | −17.1 |
| `jefe_choque.wav` | 1.3 s | Choque contra una columna, que se parte y cae a trozos. | −3.0 | −19.0 | −10.2 |
| `jefe_aturdido.wav` | 1.5 s | Aturdido: la piedra cruje y se asienta, con un gemido grave que se hunde. | −7.0 | −21.7 | −17.6 |
| `pilar_sube.wav` | 1.0 s | Una columna emerge del suelo y encaja con un tope a los 0.78 s. | −5.0 | −24.7 | −17.8 |
| `lluvia_piedra.wav` | 4.0 s | Lluvia de piedra: 44 caídas de tamaños distintos a destiempo (las grandes se oyen venir). No es un bucle; las últimas caen a los 3.5 s. | −5.0 | −23.4 | −15.8 |
| `ancla_activa.wav` | 0.6 s | Un alux pisa un ancla: tono de jade limpio (Re). | −9.0 | −25.2 | −18.1 |
| `cadenas_jade.wav` | 1.2 s | Cadenas de energía que se tensan: eslabones vítreos cada vez más juntos y agudos, y un tirón final que queda vibrando. Sin timbre metálico. | −7.0 | −25.7 | −17.6 |
| `corazon_expuesto.wav` | 1.0 s | El corazón queda expuesto: latido de cristal (dos pulsos) y brillo que asciende. | −7.0 | −20.8 | −16.4 |
| `corazon_golpe.wav` | 0.4 s | Golpe de Balam sobre el corazón: chasquido y resonancia vítrea (La). | −6.0 | −25.8 | −18.4 |
| `corazon_libre.wav` | 1.6 s | El corazón se suelta: el cristal cede y sube un acorde de Fa mayor. | −5.0 | −19.0 | −13.6 |
| `glifo_restaurado.wav` | 1.2 s | Se enciende un glifo del pecho: campana de jade grave y larga con armónicos y una respuesta aguda. Más ceremonial que `objetivo`. | −9.0 | −20.9 | −15.0 |
| `ritual_toque.wav` | 2.0 s | Canalizar el toque: acorde cálido de Fa, sostenido, que crece y se abre. Se encadena (ver «Uso»). | −10.0 | −21.2 | −18.6 |
| `silencio_grieta.wav` | 0.8 s | El Silencio se agrieta: el zumbido sube, se quiebra a los 0.3 s y cae en esquirlas. | −6.0 | −26.3 | −19.0 |
| `liberacion.wav` | 4.0 s | El Silencio se disuelve: zumbido oscuro cuyo tritono resbala a quinta justa, se apaga y florece un acorde de Fa mayor con campanas. | −3.0 | −18.8 | −11.9 |
| `pluma_jade.wav` | 2.5 s | Aparece la Pluma de Jade: el motivo del guardián, seis notas (Do Fa La, Sol Fa Do). | −6.0 | −19.6 | −14.1 |

Cinemáticas (bus SFX; una por plano, 4 s; `cutscene.gd` las lanza a −6 dB y sin variar el tono):

| Archivo | Plano | Para qué sirve | Pico | RMS | RMS 50 ms |
| --- | --- | --- | --- | --- | --- |
| `cine_patio_silencio.wav` | Despertar 1 | Patio casi vacío: aire quieto, un grave que apenas se mueve, dos agudos que baten, y un único latido de cristal a los 2 s. | −8.0 | −26.6 | −16.3 |
| `cine_grietas.wav` | Despertar 2 | Crujidos que crecen, seis grietas gordas cada vez más fuertes, raíces que se parten y polvo. | −4.0 | −27.3 | −17.8 |
| `cine_ojos.wav` | Despertar 3 | El jade parpadea y se tiñe, el zumbido magenta sube tres segundos y los ojos se abren: dos golpes secos (3.0 y 3.38 s). | −3.0 | −23.0 | −14.6 |
| `cine_en_pie.wav` | Despertar 4 | El coloso se incorpora: arrastre grave y temblor que crecen, una pausa y el golpe final a los 3 s, con escombros. | −3.0 | −22.8 | −13.2 |
| `cine_silencio_se_va.wav` | Liberación 1 | El zumbido oscuro se apaga y entran cuatro notas de jade, una por glifo (Do, Fa, La, Do; a 0.55, 1.3, 2.05 y 2.8 s). | −6.0 | −20.1 | −14.5 |
| `cine_pluma.wav` | Liberación 2 | Brillo y el motivo de `pluma_jade` al doble de lento. | −6.0 | −19.8 | −14.1 |
| `cine_cenote.wav` | Liberación 3 | Calma: viento suave y, a los 2.3 s, un destello lejano de agua. Es el más bajo a propósito. | −11.0 | −28.1 | −20.8 |

Música (bus Music, bucles circulares como `mus_emboscada`):

| Archivo | Duración | Para qué sirve | Pico | RMS | RMS 50 ms |
| --- | --- | --- | --- | --- | --- |
| `mus_jefe.wav` | 24.0 s | Combate, fases de olvido y recuerdo. Re menor, 120 BPM a medio tiempo, 12 compases: bombo de piedra, choque de losas, dron que late en negras y el motivo en trompa de caracol. Más grave y lenta de pulso que `mus_emboscada`. | −7.9 | −22.0 | −14.2 |
| `mus_jefe_furia.wav` | 24.0 s | Fase de furia. Misma tonalidad, tempo, armonía y posición del motivo que `mus_jefe`, con el pulso doblado, sonaja en semicorcheas, dron en corcheas, ostinato de kalimba y el motivo también a la octava. | −8.4 | −22.0 | −16.4 |
| `mus_recuerdo.wav` | 24.0 s | El guardián recuerda. Fa mayor, 80 BPM, 8 compases: el mismo motivo en modo mayor (kalimba y flauta), con dos respuestas, colchón, bajo y tambor de mano muy suave. | −9.3 | −22.0 | −15.8 |

**El motivo del guardián.** Seis notas con ritmo corta-corta-larga dos veces, grados
5-1-3 | 2-1-5. En Re menor (La Re Fa | Mi Re La) suena en `mus_jefe` y `mus_jefe_furia`; en
Fa mayor, su relativo (Do Fa La | Sol Fa Do), en `pluma_jade`, `cine_pluma` y
`mus_recuerdo`. El Mi de paso de la versión menor es la única nota del juego fuera de las
cinco de siempre; solo aparece en la música del combate. Es propio; no cita ninguna obra.

**Uso.**

- `audio.gd` no necesita cambios: carga por nombre de archivo y pone el bucle en código al
  pedir música (`set_music("mus_jefe")`). Como las dos músicas del combate comparten tempo
  y armonía, el fundido de `set_music` no mezcla acordes distintos; no las sincroniza al
  compás (la nueva empieza desde su principio).
- `ritual_toque` entra en 0.15 s y sale en 0.3 s. Para sostener el toque más de 2 s se
  relanza cada 1.75 s con `pitch_var = 0`: las copias se solapan y hacen de fundido cruzado
  (en simulación, el nivel oscila unos 5 dB, como una respiración; relanzado cada 2 s
  dejaría un hueco).
- `jefe_aviso` y `jefe_embestida` acaban fuertes, como `zarpazo_carga`: lo natural es que
  les siga el golpe (`jefe_losa`, `jefe_choque`).
- `jefe_paso` y `glifo_restaurado` se repiten: conviene dejarles la variación de tono por
  defecto de `Audio.play`.
- Comprobación de carga sin ventana (después de `--import`):
  `.tools/godot --headless --path game --script "$PWD/art/godot/check_audio_jefe.gd"`.
  Carga los 31 sonidos con `audio.gd` y comprueba tipo, duración, frecuencia, canales y bucle.

**Comprobado con mediciones, no de oído:** niveles (tablas), evolución de cada efecto en
16 tramos (que lo que debe crecer crezca y los golpes caigan donde dice la tabla), tono
de cada nota del motivo en los cinco archivos que lo llevan (desvío máximo, 2 centésimas
de semitono) y costura de los tres bucles. El salto entre la última muestra y la primera
es como el salto típico entre muestras vecinas en `mus_jefe` (0.004 frente a 0.004) y
`mus_jefe_furia` (0.001 frente a 0.007), y queda lejos del percentil 99.9 en
`mus_recuerdo` (0.025 frente a 0.078); tampoco hay salto de pendiente ni más energía
aguda en la costura que en cualquier otro golpe de compás.

## Niveles

Cada archivo se ajusta según su papel, no todos al mismo pico:

- Ambientes: RMS de −28 dBFS. Música: RMS de −22 dBFS.
- Efectos comunes: pico entre −10 y −4 dBFS (los de movimiento, más bajos; los golpes
  pesados, más altos; los tonales sostenidos, a −8 para que no suenen más fuertes que
  los golpes).
- Avisos largos (`santuario_abre`, `emboscada`, `victoria`): pico de −3 a −3.5 dBFS.
  `derrota` se queda en −8 a propósito, para que no castigue.
- Pasos e interfaz: pico de −12 a −15 dBFS.
- Jefe: los golpes grandes (`jefe_losa`, `jefe_choque`) a −3 y su pisada a −8; avisos y
  movimiento entre −7 y −4; los tonales de jade y cristal entre −10 y −5; `jefe_despierta`
  y `liberacion` a −3, como los avisos largos. Las de cinemática, de −11 a −3 según el plano
  (el juego las baja otros 6 dB). Las tres músicas, a RMS −22 como las demás.

Ningún archivo pasa de −1 dBFS ni tiene componente continua. Casi todo lleva un
pasa-bajos entre 4.5 y 7.5 kHz para que no resulte áspero.

## Uso en Godot

- **Los bucles no se repiten solos.** Los WAV no llevan puntos de bucle y Godot los
  importa con `edit/loop_mode=0` (detectar). Hay que poner el modo «Forward» en la
  importación (`edit/loop_mode=2`) o en código: `stream.loop_mode =
  AudioStreamWAV.LOOP_FORWARD` (con `loop_begin = 0` y `loop_end` igual al número de
  muestras). El bucle es el archivo entero.
- Los tres pasos están pensados para alternarse, con una ligera variación de tono al
  reproducirlos.
- `zarpazo_carga` acaba en su punto más fuerte para enlazar con `zarpazo`.

## Tamaño

La primera capa ocupa 2.85 MB en bruto. **Supera el presupuesto de 2.2 MB que se pidió**: con
las duraciones pedidas (64.5 s en total) y este formato (44.1 kB por segundo) no cabe.
Se ha dado prioridad a las duraciones. Hay dos salidas:

1. Comprimir al importar. Godot 4.5 importa los WAV con `compress/mode=2` (QOA) por
   defecto, que deja el audio en torno a una quinta parte (unos 0.6 MB en el paquete).
2. `--compacto`: música de 4 compases (12.8 s y 6.4 s), selva de 6.5 s con seis cantos y
   brasero de 2.4 s. Total 2.199 MB en bruto. La música se repite antes y el fuego se
   nota más cíclico. Los efectos no cambian.

**La capa del jefe ocupa 5.86 MB en bruto y supera el objetivo de unos 3 MB.** Los 28
efectos con las duraciones pedidas ya suman 60.9 s (2.69 MB), así que ninguna música
razonable cabía en lo que quedaba; las tres se han dejado en 24 s, el mínimo pedido. Lo
que viaja en el juego no son los WAV sino las muestras QOA que Godot genera al importar:
**la capa del jefe añade 1.20 MB al paquete** (medido en `game/.godot/imported/`: 0.21 MB
por música y 0.55 MB entre los 28 efectos), y las 69 juntas, 1.79 MB. Si hiciera falta
bajar más, `--compacto` deja `mus_jefe` y `mus_jefe_furia` en 8 compases (16 s, sin la
sección central) y `mus_recuerdo` en 4 (12 s): 4.63 MB en bruto para esta capa, unos
0.95 MB en el paquete.

## Qué mide la comprobación

`--check` lee los WAV del disco e imprime, por archivo: duración, pico, RMS, RMS máximo
en ventanas de 50 ms, componente continua, reparto de energía por bandas (<200 Hz,
200 Hz–2 kHz, 2–6 kHz, >6 kHz) y los primeros caracteres de su SHA-256. En los bucles
compara el salto entre la última muestra y la primera con los saltos normales entre
muestras vecinas. Avisa (y devuelve un código de error) si un archivo falta, no dura lo
esperado, pasa de −1 dBFS, está casi en silencio, tiene continua, concentra la energía
por encima de 6 kHz, no empieza o acaba en cero, tiene silencio sobrante o salta en la
costura. El tamaño se da en total y por capas (primera capa y jefe); el exceso se avisa,
pero no cuenta como error.
