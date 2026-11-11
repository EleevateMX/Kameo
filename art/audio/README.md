# Audio provisional de ALUX

Primera capa de sonido del juego: 4 bucles (dos ambientes y dos músicas) y 34 efectos.
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

Tarda unos 2 s. Las semillas son fijas (cada sonido deriva la suya de su nombre), así que
dos ejecuciones dan archivos idénticos byte a byte (comprobado con numpy 2.5.4; con otra
versión de numpy o en otra máquina podría cambiar algún bit por redondeo).

Para cambiar un sonido se edita su función en `gen_audio.py` (una por sonido, con el
mismo nombre que el archivo) o su fila en las tablas `BUCLES` y `EFECTOS` (duración,
nivel, corte de agudos, fundido final) y se vuelve a ejecutar.

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

## Niveles

Cada archivo se ajusta según su papel, no todos al mismo pico:

- Ambientes: RMS de −28 dBFS. Música: RMS de −22 dBFS.
- Efectos comunes: pico entre −10 y −4 dBFS (los de movimiento, más bajos; los golpes
  pesados, más altos; los tonales sostenidos, a −8 para que no suenen más fuertes que
  los golpes).
- Avisos largos (`santuario_abre`, `emboscada`, `victoria`): pico de −3 a −3.5 dBFS.
  `derrota` se queda en −8 a propósito, para que no castigue.
- Pasos e interfaz: pico de −12 a −15 dBFS.

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

El conjunto ocupa 2.85 MB en bruto. **Supera el presupuesto de 2.2 MB que se pidió**: con
las duraciones pedidas (64.5 s en total) y este formato (44.1 kB por segundo) no cabe.
Se ha dado prioridad a las duraciones. Hay dos salidas:

1. Comprimir al importar. Godot 4.5 importa los WAV con `compress/mode=2` (QOA) por
   defecto, que deja el audio en torno a una quinta parte (unos 0.6 MB en el paquete).
2. `--compacto`: música de 4 compases (12.8 s y 6.4 s), selva de 6.5 s con seis cantos y
   brasero de 2.4 s. Total 2.199 MB en bruto. La música se repite antes y el fuego se
   nota más cíclico. Los efectos no cambian.

## Qué mide la comprobación

`--check` lee los WAV del disco e imprime, por archivo: duración, pico, RMS, RMS máximo
en ventanas de 50 ms, componente continua, reparto de energía por bandas (<200 Hz,
200 Hz–2 kHz, 2–6 kHz, >6 kHz) y los primeros caracteres de su SHA-256. En los bucles
compara el salto entre la última muestra y la primera con los saltos normales entre
muestras vecinas. Avisa (y devuelve un código de error) si un archivo falta, no dura lo
esperado, pasa de −1 dBFS, está casi en silencio, tiene continua, concentra la energía
por encima de 6 kHz, no empieza o acaba en cero, tiene silencio sobrante o salta en la
costura. El exceso de tamaño total se avisa, pero no cuenta como error.
