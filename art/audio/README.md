# Audio provisional de ALUX

Primera capa de sonido del juego: 4 bucles (dos ambientes y dos músicas) y 34 efectos.
Segunda capa, para el jefe Nojoch Tuunich y sus dos cinemáticas: 3 músicas y 28 efectos
(ver «Jefe Nojoch Tuunich»). Tercera capa, el banco de efectos de la Alpha 0.3.1: 50
efectos más (ver «Alpha 0.3.1: banco de efectos»). En total, 119 archivos.
**Es audio provisional y sintetizado**: todo sale de `gen_audio.py` (senos, ruido filtrado,
envolventes y modelos sencillos), sin grabaciones ni muestras de terceros. Es original y no
tiene licencias que cumplir. **Nadie lo ha escuchado todavía**: se ha comprobado con
mediciones (niveles, espectro, costuras, seguimiento de tono) y, en la capa 0.3.1, mirando
espectrogramas; no de oído. Habrá que sustituirlo o retocarlo cuando alguien lo oiga en el
juego.

Formato de todos los archivos: WAV mono, 16 bits PCM, en `game/assets/audio/`. Todo va a
22050 Hz salvo 11 efectos de la capa 0.3.1 que necesitan brillo, a 44100 Hz (columna «kHz»
de sus tablas). La procedencia de cada archivo está en `manifiesto_efectos.json`.

## Cómo regenerar

Solo hace falta Python con numpy (sirve el entorno de Blender del proyecto; no usa `bpy`):

```bash
.tools/blender-venv/bin/python art/audio/gen_audio.py                 # genera todo y lo comprueba
.tools/blender-venv/bin/python art/audio/gen_audio.py --check         # solo comprueba lo que hay en disco
.tools/blender-venv/bin/python art/audio/gen_audio.py --compacto      # variante corta, ver «Tamaño»
.tools/blender-venv/bin/python art/audio/gen_audio.py --salida DIR    # escribe en otra carpeta
.tools/blender-venv/bin/python art/audio/gen_audio.py --solo alfa031  # solo una capa (base, jefe, alfa031)…
.tools/blender-venv/bin/python art/audio/gen_audio.py --solo 'ui_*,chispa_?'   # …o unos nombres o patrones
.tools/blender-venv/bin/python art/audio/gen_audio.py --check --manifiesto     # reescribe manifiesto_efectos.json
```

`--solo` genera y comprueba únicamente los sonidos elegidos y no toca los demás archivos:
es la forma de regenerar una capa sin pisar lo que otro generador haya dejado en la carpeta.

Tarda unos 7 s. Las semillas son fijas (cada sonido deriva la suya de su nombre), así que
dos ejecuciones dan archivos idénticos byte a byte (comprobado con numpy 2.5.4; con otra
versión de numpy o en otra máquina podría cambiar algún bit por redondeo).

Para cambiar un sonido se edita su función en `gen_audio.py` (una por sonido, con el
mismo nombre que el archivo) o su fila en las tablas `BUCLES` y `EFECTOS` (las del jefe,
`BUCLES_JEFE` y `EFECTOS_JEFE`; las de la capa 0.3.1, `EFECTOS_031`: duración, nivel,
corte de agudos, fundido final y, en esta última, frecuencia de muestreo y familia) y se
vuelve a ejecutar. Añadir sonidos no cambia los que ya había: cada uno tiene su semilla
(al añadir la capa 0.3.1 se comprobó con sumas SHA-256 que los 69 anteriores salen
idénticos byte a byte).

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

## Alpha 0.3.1: banco de efectos

50 efectos que completan el banco: pasos por superficie, avisos de compañeros, habilidades
del alux, voz y golpes de Balam, los dos tipos de enemigo, cinco más del jefe y la interfaz.
Mismo generador y mismas reglas (síntesis propia, semilla por nombre). Los nombres son los
que pide el código del juego. Pico, RMS y «RMS 50 ms» están medidos sobre los archivos (dBFS).

**Personaje y pasos**

| Archivo | Duración | kHz | Qué es | Pico | RMS | RMS 50 ms |
| --- | --- | --- | --- | --- | --- | --- |
| `paso_hierba_1.wav` | 0.18 s | 22.05 | Paso sobre hierba y hojas: dos roces suaves (talón y punta) y briznas que crujen. Sin golpe. | −20.0 | −39.0 | −35.5 |
| `paso_hierba_2.wav` | 0.18 s | 22.05 | Variante más aguda y crujiente (roces más juntos, siete briznas). | −20.0 | −37.5 | −34.3 |
| `paso_hierba_3.wav` | 0.18 s | 22.05 | Variante más grave y lenta (roces más separados, cuatro briznas). | −20.0 | −37.9 | −34.7 |
| `paso_piedra_1.wav` | 0.08 s | 22.05 | Paso sobre losa: toque seco de la suela (resonancia de 640 Hz) y arenilla. | −20.0 | −37.1 | −35.1 |
| `paso_piedra_2.wav` | 0.08 s | 22.05 | Variante más aguda y seca (760 Hz). | −20.0 | −37.4 | −35.4 |
| `paso_piedra_3.wav` | 0.08 s | 22.05 | Variante más grave (560 Hz). | −20.0 | −40.3 | −38.3 |
| `paso_agua_1.wav` | 0.30 s | 22.05 | Paso en agua somera: plof corto, salpicadura y tres burbujas. | −20.0 | −40.1 | −33.2 |
| `paso_agua_2.wav` | 0.30 s | 22.05 | Variante más grave, con más rocío y cuatro burbujas. | −20.0 | −39.8 | −34.4 |
| `recoger.wav` | 0.35 s | 44.1 | Recoger un objeto: una pulsación brillante de kalimba (Do) con su octava de campana y un destello que sube. Una sola nota, a propósito. | −10.0 | −24.8 | −18.7 |
| `interactuar.wav` | 0.30 s | 22.05 | Tocar o activar algo: toque de madera hueca y una nota de kalimba (Re). | −10.0 | −25.6 | −19.2 |
| `dano_fuerte.wav` | 0.55 s | 22.05 | Golpe fuerte recibido: porrazo grave con chasquido, rebote y un quejido que cae. Más grave, más largo y 5 dB más denso que `dano`. | −5.0 | −18.9 | −11.4 |
| `aliado_caido.wav` | 0.80 s | 22.05 | Un compañero cae: dos notas que bajan (Fa, Re) con flauta y kalimba, como `caida` una octava arriba para que se oiga de lejos. | −6.0 | −16.3 | −12.2 |
| `aliado_revive.wav` | 0.80 s | 44.1 | Un compañero vuelve: dos notas que suben (Re, La) con campana, aire que asciende y destellos. | −6.0 | −18.9 | −13.9 |

**Alux**

| Archivo | Duración | kHz | Qué es | Pico | RMS | RMS 50 ms |
| --- | --- | --- | --- | --- | --- | --- |
| `chispa_2.wav` | 0.30 s | 22.05 | Variante de `chispa`: el mismo gorjeo vítreo dos semitonos arriba, sube más deprisa, ocho destellos. | −7.0 | −20.7 | −14.5 |
| `chispa_3.wav` | 0.30 s | 22.05 | Variante de `chispa`: tres semitonos abajo, sube más despacio, seis destellos. | −7.0 | −19.6 | −13.9 |
| `luz_alux.wav` | 0.60 s | 44.1 | Estallido de luz: golpe de aire al encenderse y una campana cálida (Re) que se hincha hasta los 0.15 s y se apaga, con halo agudo. | −8.0 | −19.6 | −14.7 |
| `escudo_alux.wav` | 0.70 s | 44.1 | Escudo que se levanta: soplido que sube 0.3 s, la cúpula vítrea que se cierra y un tono sostenido breve (Re y La) que bate despacio. | −8.0 | −24.2 | −18.7 |
| `escudo_golpe.wav` | 0.40 s | 22.05 | El escudo absorbe un golpe: «dong» vítreo amortiguado (Re grave) que cede un poco de tono. | −8.0 | −25.6 | −18.0 |
| `apoyo_alux.wav` | 0.80 s | 44.1 | Apoyo a un compañero: tres notas de kalimba que suben (Do, Fa, La) con su octava de campana y destellos. | −8.0 | −20.8 | −16.7 |

**Balam**

| Archivo | Duración | kHz | Qué es | Pico | RMS | RMS 50 ms |
| --- | --- | --- | --- | --- | --- | --- |
| `balam_rugido.wav` | 1.00 s | 22.05 | Rugido: fuente ronca (pulsos graves de 82 → 116 → 60 Hz, con subarmónico) por formantes de garganta grande; la boca se abre y se cierra y acaba en gruñido gutural. | −5.0 | −17.2 | −12.9 |
| `balam_grunido.wav` | 0.45 s | 22.05 | Gruñido corto, al transformarse: boca casi cerrada, áspero, cae de 94 a 64 Hz. | −5.0 | −17.4 | −12.8 |
| `garras_2.wav` | 0.25 s | 22.05 | Variante de `garras`: tres tajos con otro orden de alturas y otro compás. | −6.0 | −22.5 | −18.4 |
| `garras_3.wav` | 0.25 s | 22.05 | Variante de `garras`: tajos algo más largos y más separados. | −6.0 | −21.9 | −18.3 |
| `balam_golpe.wav` | 0.35 s | 22.05 | La garra impacta: golpe con cuerpo y una rasgadura que baja a tirones. | −5.0 | −21.2 | −14.0 |
| `balam_especial.wav` | 0.90 s | 22.05 | Ataque especial: rugido corto y, a los 0.38 s, la onda de choque (bombazo grave y anillo de aire que se abre). | −5.0 | −15.9 | −10.7 |

**Enemigos**

| Archivo | Duración | kHz | Qué es | Pico | RMS | RMS 50 ms |
| --- | --- | --- | --- | --- | --- | --- |
| `enemigo_aparece.wav` | 0.80 s | 22.05 | Un enemigo surge de la piedra corrompida: grieta, retumbo y zumbido oscuro que suben, y el golpe al salir (0.58 s). Sirve para los dos tipos. | −8.0 | −21.5 | −16.1 |
| `enemigo_dano.wav` | 0.20 s | 22.05 | Un enemigo recibe daño: salta una lasca y suelta un quejido oscuro muy corto. `golpe` es el impacto del arma; este es la reacción del enemigo. | −8.0 | −25.1 | −19.7 |
| `enemigo_purificado.wav` | 0.70 s | 44.1 | Purificado: el zumbido oscuro se deshace hacia arriba como ceniza y queda una campanilla limpia (La, Re). `enemigo_muere` es el que se desmorona. | −8.0 | −23.5 | −18.2 |
| `enemigo_paso.wav` | 0.25 s | 22.05 | Movimiento: arrastre corto de piedra y el toque seco al asentarse (el pico es ese toque; el arrastre va unos 10 dB por debajo). | −8.0 | −25.1 | −19.4 |
| `guardian_llamada.wav` | 0.90 s | 22.05 | Guardián de piedra: gemido grave que sube y se hunde, con el rechinar de sus bloques. | −8.0 | −22.2 | −18.3 |
| `guardian_ataque.wav` | 0.50 s | 22.05 | Guardián de piedra: el brazo corta el aire y descarga el mazazo (a los 0.13 s), con cascotes. `enemigo_golpe` es solo el impacto. | −8.0 | −23.0 | −15.5 |
| `criatura_llamada.wav` | 0.60 s | 22.05 | Criatura corrompida: castañeteo hueco que se acelera (de 16 a 34 chasquidos por segundo, uno de cada tres salta un tritono) y un chirrido fino por debajo. | −8.0 | −25.7 | −21.1 |
| `criatura_ataque.wav` | 0.25 s | 22.05 | Criatura corrompida: dos arañazos muy rápidos y el chasquido de la mordida (a los 0.09 s). | −8.0 | −25.9 | −21.7 |

**Nojoch Tuunich**

| Archivo | Duración | kHz | Qué es | Pico | RMS | RMS 50 ms |
| --- | --- | --- | --- | --- | --- | --- |
| `jefe_respira.wav` | 3.00 s | 22.05 | Respiración dormida: un pulmón de piedra. Inspira 1.35 s (el soplo sube), pausa y espira 1.5 s (baja), con granos de piedra que rozan. No es un bucle. | −10.0 | −23.8 | −17.4 |
| `jefe_fase.wav` | 1.80 s | 22.05 | Cambio de fase: trompa grave (Re2 y Re3) y un crujido que recorre la piedra de abajo arriba hasta partirla a los 1.3 s. | −3.0 | −16.3 | −12.1 |
| `jefe_cae.wav` | 1.40 s | 22.05 | Cae de rodillas: dos impactos enormes (0 y 0.24 s), quejido de roca que se hunde y escombros. | −3.0 | −15.9 | −8.9 |
| `pilar_rompe.wav` | 1.00 s | 22.05 | Una columna se hace pedazos: chasquido seco que la parte, siete trozos grandes que caen cada vez más espaciados y polvo. | −3.0 | −16.3 | −10.5 |
| `ritual_pulso.wav` | 1.20 s | 22.05 | Pulso de Silencio: hinchazón invertida (un eco oscuro al revés, 0.88 s) que acaba en un golpe sordo. | −3.0 | −20.2 | −10.8 |

**Interfaz**

| Archivo | Duración | kHz | Qué es | Pico | RMS | RMS 50 ms |
| --- | --- | --- | --- | --- | --- | --- |
| `ui_mover.wav` | 0.05 s | 44.1 | Mover la selección: tic mínimo de madera. | −12.0 | −28.6 | −28.6 |
| `ui_confirmar.wav` | 0.22 s | 44.1 | Confirmar: toque de madera y dos notas de kalimba que suben una quinta (Re, La). | −12.0 | −24.5 | −20.6 |
| `ui_cancelar.wav` | 0.20 s | 22.05 | Cancelar o volver: dos notas apagadas que bajan (La, Re) sobre un toque hueco. | −12.0 | −23.3 | −20.6 |
| `ui_cerrar.wav` | 0.20 s | 22.05 | Cerrar un panel: la ola de `ui_abrir` al revés (baja de tono) y un toque hueco al posarse. | −12.0 | −23.4 | −19.7 |
| `ui_error.wav` | 0.25 s | 22.05 | Acción no válida: dos toques graves y apagados de madera hueca; el segundo, más bajo. | −12.0 | −24.9 | −21.0 |
| `ui_recompensa.wav` | 1.20 s | 44.1 | Recompensa: arpegio de Fa mayor pentatónica que sube (seis notas) y se abre en un acorde con destellos. | −4.0 | −16.8 | −13.1 |
| `ui_jugador_entra.wav` | 0.40 s | 22.05 | Un jugador se conecta: dos notas suaves que suben (La, Re). | −12.0 | −23.6 | −18.6 |
| `ui_jugador_sale.wav` | 0.40 s | 22.05 | Un jugador se va: las mismas notas al revés (Re, La), más apagadas. | −12.0 | −21.1 | −17.4 |
| `ui_invitacion.wav` | 0.50 s | 44.1 | Invitación o aviso social: llamada de tres notas (La, Fa, Do), corta-corta-larga. | −12.0 | −25.5 | −21.5 |
| `ui_sala_creada.wav` | 0.70 s | 44.1 | Sala lista: acorde corto de Fa que se abre de abajo arriba sobre un toque de madera. | −12.0 | −25.2 | −20.7 |
| `ui_prueba.wav` | 1.00 s | 22.05 | Sonido de prueba del menú «Probar sonido»: tres notas claras (Re, La, Re) de kalimba y campana. El 99 % de la energía está entre 500 y 2500 Hz. | −3.0 | −15.3 | −9.7 |
| `punto_control.wav` | 0.90 s | 22.05 | Punto de control: nota larga y cálida (Re) con su quinta y un destello a media nota. | −12.0 | −26.1 | −20.2 |

**Cómo están hechos.**

- Cada efecto tiene capas (ataque, cuerpo y cola), no un tono desnudo: por ejemplo,
  `escudo_alux` es un soplido que sube + un chasquido vítreo al cerrarse la cúpula + parciales
  de barra de vidrio + un tono sostenido que bate + destellos.
- Timbres nuevos, todos sintetizados: campana con parciales altos (`campana_clara`), kalimba
  con chasquido de uña (`lengueta`), madera hueca (`madera`: tres modos de tabla y la cavidad)
  y voz de felino (`voz_ronca` + `formantes`: un tren de pulsos grave e inestable, con
  subarmónico y soplo, filtrado por dos juegos de formantes de garganta grande entre los que
  se mezcla según se abre la boca). El rugido no parte de ninguna grabación de un animal.
- **Frecuencia de muestreo.** A 44100 Hz solo van los 11 efectos con contenido real por
  encima de 11 kHz (destellos, aire, parciales altos de campana): `recoger`, `aliado_revive`,
  `luz_alux`, `escudo_alux`, `apoyo_alux`, `enemigo_purificado`, `ui_mover`, `ui_confirmar`,
  `ui_recompensa`, `ui_invitacion` y `ui_sala_creada`. Medido, ese contenido es discreto
  (entre −28 y −46 dB respecto al total, según el efecto): es aire, no un agudo que pinche.
  Los cálidos o apagados (`ui_prueba`, `punto_control`, `ui_jugador_*`, `escudo_golpe`…) no
  ganaban nada y pesarían el doble. Las variantes de `chispa` y `garras` van a 22050 Hz y
  con el mismo corte que su original para que una ráfaga no cambie de color.
- **Variantes** (`_1`/`_2`/`_3`, `chispa`/`chispa_2`/`chispa_3`, `garras`/`garras_2`/`garras_3`):
  misma receta con otra semilla y otros parámetros (altura, separación, número de granos).
  Entre sí, la correlación de onda máxima es de 0.09 a 0.35 (no son copias) y el color en
  tercios de octava se parece (r de 0.86 a 0.99), salvo `chispa_2` frente a `chispa_3`
  (0.69), que están a cinco semitonos una de otra.
- Cada efecto de esta capa lleva 3 ms de silencio delante: la entrada de 2 ms que evita el
  chasquido inicial no se come así el ataque.
- Sigue valiendo lo de las cinco notas (Re, Fa, Sol, La, Do). `criatura_llamada` y los
  zumbidos oscuros usan tritonos a propósito: es el color del Silencio.

**Niveles por familia** (pico): pasos −20 · interfaz −12, salvo `ui_prueba` (−3) y
`ui_recompensa` (−4) · alux −8 · Balam −5 · enemigos −8 · jefe −3 · avisos de compañeros −6.
Fuera de la lista: `recoger` e `interactuar` a −10 y `dano_fuerte` a −5 (uno más que `dano`).
Tres excepciones deliberadas a la regla de familia:

- `chispa_2` y `chispa_3` van a −7 y `garras_2` y `garras_3` a −6, como sus originales, para
  que al alternarlas no salte el volumen.
- `jefe_respira` va a −10, no a −3: es un soplo continuo, con poca diferencia entre pico y
  RMS, y a −3 una respiración dormida sonaría más fuerte que los golpes del jefe (su tramo
  más denso quedaría en torno a −10 dBFS, como `jefe_choque`). Se cambia en una cifra de
  `EFECTOS_031` si en el juego queda corta.

**Uso.**

- `audio.gd` ya alterna las variantes y manda al bus UI lo que empieza por `ui_` más
  `objetivo`, `sin_energia`, `aliado_caido`, `aliado_revive` y `punto_control`; el manifiesto
  usa ese mismo reparto.
- `enemigo_paso` y los pasos se repiten mucho: conviene dejarles la variación de tono por
  defecto de `Audio.play`. `jefe_respira` no es un bucle (3 s, empieza y acaba en cero): se
  relanza cada 3 s o más, sin variación de tono.
- Parejas y encadenados: `ui_abrir`/`ui_cerrar`; `ui_jugador_entra`/`ui_jugador_sale` (las
  mismas dos notas en sentido contrario); `escudo_alux` → `escudo_golpe`; `guardian_ataque`
  ya lleva su impacto (no hace falta sumarle `enemigo_golpe`); `ritual_pulso` da el golpe a
  los 0.88 s, por si hay que sincronizarlo con la imagen.
- `ui_prueba` es el más fuerte de la interfaz a propósito (pico −3, RMS 50 ms de −9.7): es
  para comprobar que se oye.

**Comprobado con mediciones y espectrogramas, no de oído.** Además de `--check`, se generaron
espectrogramas de los 50 (frecuencia logarítmica, escala absoluta, con la envolvente debajo)
y se revisaron por familias junto a los efectos antiguos más parecidos: que cada uno tenga
ataque, cuerpo y cola, que las variantes difieran y que nada quede vacío ni saturado. De esa
revisión salieron varios retoques (el clímax de `jefe_fase` se perdía bajo la trompa y un
crujido suelto le fijaba el pico; `enemigo_aparece` no crecía; las notas de interfaz se
cortaban sin apagarse; el primer chasquido de `criatura_llamada` se lo comía la entrada).
Eso no sustituye a escucharlos: un espectrograma dice que hay un rugido con formantes entre
250 y 2300 Hz, no si convence.

## Niveles

Cada archivo se ajusta según su papel, no todos al mismo pico:

- Ambientes: RMS de −28 dBFS. Música: RMS de −22 dBFS.
- Efectos comunes: pico entre −10 y −4 dBFS (los de movimiento, más bajos; los golpes
  pesados, más altos; los tonales sostenidos, a −8 para que no suenen más fuertes que
  los golpes).
- Avisos largos (`santuario_abre`, `emboscada`, `victoria`): pico de −3 a −3.5 dBFS.
  `derrota` se queda en −8 a propósito, para que no castigue.
- Pasos e interfaz: pico de −12 a −15 dBFS (los pasos por superficie de la capa 0.3.1, a −20).
- Jefe: los golpes grandes (`jefe_losa`, `jefe_choque`) a −3 y su pisada a −8; avisos y
  movimiento entre −7 y −4; los tonales de jade y cristal entre −10 y −5; `jefe_despierta`
  y `liberacion` a −3, como los avisos largos. Las de cinemática, de −11 a −3 según el plano
  (el juego las baja otros 6 dB). Las tres músicas, a RMS −22 como las demás.

- Capa 0.3.1: por familias (ver su sección).

Ningún archivo pasa de −1 dBFS ni tiene componente continua. Casi todo lleva un
pasa-bajos entre 4.5 y 7.5 kHz para que no resulte áspero (los once efectos a 44.1 kHz,
entre 12 y 14 kHz).

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

**La capa 0.3.1 ocupa 1.577 MB en bruto, dentro de su presupuesto de 2.5 MB** (39 efectos a
22050 Hz, 22.5 s y 0.993 MB; 11 a 44100 Hz, 6.6 s y 0.584 MB). Este presupuesto es firme:
si se supera, `--check` lo cuenta como error. Los 119 archivos suman 10.287 MB en bruto.

## Manifiesto de procedencia

`manifiesto_efectos.json` es una lista con una entrada por archivo de `game/assets/audio/`
generado por `gen_audio.py` (los 69 anteriores y los 50 de la 0.3.1): `id`, `archivo`, `tipo`
(«efecto», «música provisional» o «ambiente provisional»), `bus` (SFX, UI, Cinematics, Music
o Ambience), `duracion_s`, `hz`, `bytes`, `origen` (la función que lo genera), `licencia` y
`semilla` (la pareja que recibe `numpy.random.default_rng`: la semilla base y el CRC-32 del
nombre). Duración, frecuencia y tamaño se leen de los archivos; se reescribe con
`--check --manifiesto`. Los archivos de `game/web/static/audio` (música, ambientes y
cinemáticas del mezclador de la página) no salen de este generador y no están aquí.

## Qué mide la comprobación

`--check` lee los WAV del disco e imprime, por archivo: duración, frecuencia de muestreo,
pico, RMS, RMS máximo en ventanas de 50 ms, componente continua, reparto de energía por
bandas (<200 Hz, 200 Hz–2 kHz, 2–6 kHz, >6 kHz), el nivel de la banda de 2 a 5 kHz en su
tramo más fuerte («n2-5k») y los primeros caracteres de su SHA-256. En los bucles
compara el salto entre la última muestra y la primera con los saltos normales entre
muestras vecinas. Avisa (y devuelve un código de error) si un archivo falta, no dura lo
esperado, pasa de −1 dBFS, está casi en silencio, tiene continua, concentra la energía
por encima de 6 kHz, no empieza o acaba en cero, tiene silencio sobrante o salta en la
costura; también si su frecuencia de muestreo no es la de la tabla o su pico se aparta más
de 0.15 dB del pedido. A los efectos de la capa 0.3.1 les exige además que la banda de 2 a
5 kHz no pase de −17 dBFS en su tramo más fuerte (`chispa` y `garras`, que viven ahí, miden
−19.0 y −19.6; el más alto de los nuevos es `chispa_2`, con −18.6), que tengan cuerpo (RMS
de 50 ms a menos de 22 dB del pico), que `ui_mover` no pase de 0.06 s y que `ui_prueba`
tenga al menos el 80 % de su energía entre 500 y 2500 Hz. El tamaño se da en total y por
capas; el exceso de la primera capa y del jefe se avisa pero no cuenta como error, y el de
la capa 0.3.1 sí.
