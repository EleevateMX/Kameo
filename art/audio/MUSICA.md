# Música de ALUX (Alpha 0.3.1)

Diez piezas de música terminadas como archivos (no se genera audio en tiempo de ejecución):
nueve bucles y una fanfarria. **Toda es sintetizada por código** con numpy en
`art/audio/gen_musica.py` (senos, ruido filtrado y envolventes), sin grabaciones ni muestras
de terceros. Es original del proyecto y no tiene licencias que cumplir.

**Nadie la ha escuchado todavía**, ni quien la escribió ni quien la encargó. Todo lo que se
afirma aquí sobre cómo suena sale de mediciones y de mirar espectrogramas, no del oído. Lo
que eso deja sin comprobar está en [«Qué no se ha podido comprobar»](#qué-no-se-ha-podido-comprobar).

- Archivos: `game/web/static/audio/mus_*.mp3`, MP3 estéreo a 44.1 kHz, VBR
  (`ffmpeg -c:a libmp3lame -q:a 5`, unos 130 kbps de media).
- Manifiesto del reproductor: `game/web/static/audio/musica.json` (lo carga
  `game/web/static/alux-audio.js` junto con `ambiente.json` y `cine.json`).
- Procedencia: `art/audio/manifiesto_musica.json`.
- Total: 7.78 MB (presupuesto, 9 MB; ningún archivo pasa de 0.97 MB, con límite de 1.1 MB).

La música provisional anterior (`mus_*.wav` mono a 22 kHz, de `gen_audio.py`) no se toca:
sigue en `game/assets/audio/`. `gen_musica.py` es autónomo y no importa `gen_audio.py`.

## Cómo regenerarla

Hace falta Python con numpy (sirve el entorno de Blender del proyecto; no usa `bpy` ni
scipy) y `ffmpeg` con `libmp3lame`.

```bash
.tools/blender-venv/bin/python art/audio/gen_musica.py                    # genera todo y lo comprueba
.tools/blender-venv/bin/python art/audio/gen_musica.py --solo mus_claro   # solo algunas piezas (ids separados por comas)
.tools/blender-venv/bin/python art/audio/gen_musica.py --check            # solo mide y valida lo que hay en disco
.tools/blender-venv/bin/python art/audio/gen_musica.py --espectros        # además, una hoja de espectrograma por pieza
.tools/blender-venv/bin/python art/audio/gen_musica.py --detalle          # nivel de cada instrumento en la mezcla
.tools/blender-venv/bin/python art/audio/gen_musica.py --tmp DIR          # carpeta de WAV intermedios y espectrogramas
```

Generarlo todo tarda unos 3 min 20 s en una máquina de 4 núcleos, en un solo proceso.
Los WAV intermedios (24 bits) y los espectrogramas van a una carpeta temporal fuera del
repositorio (`$TMPDIR/alux_musica` si no se da `--tmp`) y no se versionan.

Las semillas son fijas: cada pieza y cada nota derivan la suya de su nombre y de sus
parámetros (semilla base 20261112), así que el resultado no depende del orden en que se
genere. Se ha regenerado todo dos veces y los diez MP3 y los dos manifiestos salen
idénticos byte a byte (mismo `sha256`), con numpy 2.5.4 y ffmpeg 6.1.1. Con otras versiones
podría cambiar algún bit.

`--check` devuelve código de salida 1 si algo se sale de rango y 0 si todo está bien. Se
probó con archivos estropeados a propósito (ver «Qué mide `--check`»).

Para cambiar una pieza se edita su función (`mus_claro()`, `mus_jefe()`…): las notas están en
tablas al principio de cada sección y los niveles de mezcla en las llamadas a `p.bus(...)`.

## Convención de bucle

El reproductor usa Web Audio con `loopStart`/`loopEnd`, y el MP3 añade un retardo de
codificación que no todos los decodificadores recortan. Para que el bucle sea continuo
aunque el contenido se desplace unas decenas de milisegundos, cada archivo de bucle es:

```
[ pre = últimos 0.5 s del cuerpo ][ cuerpo del bucle, L segundos ][ post = primeros 0.5 s del cuerpo ]
```

y el manifiesto declara `"loop": [0.5, 0.5 + L]`. El cuerpo es circular de verdad: se
compone sobre un búfer en el que las notas que cruzan el final dan la vuelta, y el eco, la
reverb (convolución circular), los filtros y el limitador se aplican también de forma
periódica. `mus_victoria` no tiene bucle (`"loop": null`).

## Un solo mundo: tonalidad, tempo y temas

- **Tonalidad.** Todo vive en **Re menor pentatónica** (Re Fa Sol La Do) y en su relativo,
  **Fa mayor pentatónica**, que tiene las mismas notas. Los temas del jefe usan Re menor
  natural (aparecen Mi y Si bemol) y el lobby y el recuerdo, Fa mayor (la misma escala).
  Por eso un fundido cruzado de 1–2 s entre dos piezas cualesquiera no junta notas ajenas.
- **Tempo.** Todos los tempos son parientes de 75 pulsos por minuto: 75 (claro, exploración,
  latido de peligro, recuerdo, liberación y la negra con puntillo del lobby), 150 (emboscada
  y furia, el doble) y 120 a medio tiempo, es decir, 60 sentidos (jefe).
- **La llamada del alux** (leitmotiv del juego): `La Do Re | Sol La`, larga-corta-larga y
  corta-larga. Sale de la frase de flauta del `capas_claro` original. Como sus cinco notas
  están en las dos pentatónicas, suena melancólica sobre Re menor y luminosa sobre Fa mayor
  sin cambiar una nota. Aparece en las diez piezas (en `mus_peligro`, solo sus dos primeras
  notas; en `mus_lobby`, en el puente).
- **El motivo del guardián** (Nojoch Tuunich): seis notas, corta-corta-larga dos veces,
  grados 5-1-3 | 2-1-5. En menor (`La Re Fa | Mi Re La`) en `mus_jefe` y `mus_jefe_furia`; en
  mayor (`Do Fa La | Sol Fa Do`) en `mus_recuerdo`, `mus_liberacion` y `mus_victoria`. Es el de
  `capas_jefe` y `capas_recuerdo`.
- **La figura de kalimba del claro** (corcheas 1, 3, 4, 6 y 7 del compás) es la de
  `capas_claro`; vuelve en mayor en `mus_liberacion`. El ostinato de dos notas de
  `capas_emboscada` vuelve en `mus_emboscada` y en `mus_jefe_furia`.

Los dos temas y todas las melodías son propios. No se ha copiado ni imitado ninguna banda
sonora ni ninguna pieza tradicional; la paleta es «inspirada en» lo mesoamericano, no una
reconstrucción.

## Las piezas

Duración = cuerpo del bucle (el archivo dura 1 s más por los márgenes). Los tiempos de las
secciones se cuentan desde el inicio del cuerpo (en el archivo, 0.5 s más tarde).

| id | Bucle | Tempo y compás | Tonalidad | Instrumentos | Estructura |
| --- | --- | --- | --- | --- | --- |
| `mus_claro` | 57.6 s | 75 BPM, 4/4, 18 compases | Re menor pentatónica | Kalimba con eco cruzado, flauta de barro, ocarina, marimba grave, coro de aire y colchón, bajo, tambor grave y de mano, teponaztli, sonaja, palo de lluvia | **A** 0–12.8 s: figura de kalimba y la llamada del alux en la flauta · **A'** 12.8–25.6: respuesta, entra el tambor completo · **B** 25.6–38.4: marimba en 3+3+2 y sonaja · **C** 38.4–51.2: la llamada a dúo (flauta y ocarina a la octava), teponaztli · **puente** 51.2–57.6: se vacía, «Sol La» en la ocarina y palo de lluvia |
| `mus_exploracion` | 57.6 s | 75 BPM, 6/4, 12 compases | Re menor pentatónica (con un Si bemol add9) | Coro de aire y colchón anchos, ocarina con eco, «gotas» de kalimba, flauta grave, bajo sostenido, tambor grave suelto, teponaztli, campanas de jade, sonaja, palo de lluvia, viento | Seis acordes de 9.6 s: Re m7 · Sol sus · Fa add9 · Do sus2 · Si♭ add9 · La 7sus4. La ocarina toca la llamada al doble de lenta (3–16 s) y luego fragmentos con silencios largos |
| `mus_peligro` | 38.4 s | 75 BPM, 12 compases | Re (dron), con Mi♭ y La♭ | Dron grave que bate, tambor como latido («lub-dub»), sonajas sueltas y dos cascabeles que se aceleran, teponaztli, caracol lejano, ocarina grave, voces en segunda menor | Sin melodía cantable. Compases 1–4: latido cada dos pulsos · 5–10: en cada pulso, creciendo; tritono y voces · 11–12: afloja. De la llamada solo quedan sus dos primeras notas (La, Do), graves, cayendo de tono y sin resolver (26–32 s) |
| `mus_emboscada` | 38.4 s | 150 BPM, 4/4, 24 compases | Re menor | Tambores graves (tom y fondo), palmada de parche, teponaztli, sonaja en semicorcheas, dron que late, ostinato de kalimba (doblado por marimba), trompas de caracol, flauta de barro, ocarina | Seis secciones de 6.4 s: **1** arranque (tambores y dron) · **2** palmadas, teponaztli y trompa · **3** la llamada en la flauta · **4** subida sobre Si♭ y Do, trompas a octavas · **5** clímax: la llamada una cuarta arriba, flauta y ocarina · **6** respiro y redoble de vuelta |
| `mus_jefe` | 56.0 s | 120 BPM a medio tiempo, 4/4, 28 compases | Re menor | Percusión de piedra (bombo de roca, choque de losas, gravilla), tambor de fondo, dron que late, trompas de caracol, kalimba grave, flauta de barro, ocarina, coro, teponaztli | Siete secciones de 8 s: **A** el motivo y un eco que no termina · **B** variante sobre Si♭ · **C** lamento (notas largas, flauta que cae) · **A2** el motivo; la flauta lo olvida a la mitad y la trompa solo repite la primera mitad · **D** la llamada del alux, lejos, y la piedra contesta · **A3** el motivo entero a octavas · **E** cierre y redoble |
| `mus_jefe_furia` | 44.8 s | 150 BPM, 4/4, 28 compases | Re menor | Lo mismo, más ostinato de kalimba, teponaztli continuo, gravilla en semicorcheas, rellenos de tambor, trompas a octavas y coro abierto | La misma forma y las mismas melodías que `mus_jefe`, a 150 BPM (secciones de 6.4 s) y con el pulso de percusión doblado; aquí el motivo sí se completa cada vez |
| `mus_recuerdo` | 57.6 s | 75 BPM, 4/4, 18 compases | Fa mayor | Kalimba con eco, flauta de barro, ocarina, campanas de jade, arpegio de kalimba a contratiempo, coro, colchón, bajo, tambor grave como pulso ritual, tambor de mano, sonaja, teponaztli, palo de lluvia | **A** 0–12.8 s: el motivo en mayor y su respuesta · **A'** 12.8–25.6: con campanas · **B** 25.6–38.4: la llamada del alux en la flauta y su espejo (hacia abajo) sobre Si♭ · **A''** 38.4–51.2: el motivo lo canta la flauta, con todo · **coda** 51.2–57.6 |
| `mus_liberacion` | 51.2 s | 75 BPM, 4/4, 16 compases | Fa mayor pentatónica | Flauta de barro, ocarina, trompa suave, kalimba (la figura del claro, en mayor), campanas de jade, coro, colchón, bajo, tambor grave cada dos compases, sonaja, palo de lluvia | **A** 0–12.8 s: el motivo del guardián al doble de lento en la flauta · **B** 12.8–25.6: la llamada en la ocarina y respuesta que resuelve en Fa · **A'** 25.6–38.4: el motivo en la trompa, con destellos de kalimba · **C** 38.4–51.2: descenso sereno |
| `mus_victoria` | 10.5 s, sin bucle | pulso libre (≈120) | Fa mayor | Trompas, kalimba, marimba, flauta, ocarina, coro, bajo, campanas, tambores, sonajas | 0–2.4 s: el motivo del guardián en mayor como toque de trompas · 2.5–4.6: la llamada del alux sobre Si♭ y Do · 4.6: acorde final de Fa, que se apaga con la reverb hasta el segundo 10 |
| `mus_lobby` | 57.6 s | 6/8, negra con puntillo a 75, 36 compases | Fa mayor | Marimba (a terceras en la última vuelta), cuerda pulsada, flauta de barro, ocarina, bajo, coro, sonaja, tambor y tambor de mano, teponaztli, una campana lejana | **A** 0–12.8 s: melodía en la marimba · **A'** 12.8–25.6: con flauta, cierra en Fa · **B** 25.6–38.4: canta la flauta · **A''** 38.4–51.2: todos · **puente** 51.2–57.6: la llamada del alux en la ocarina. Un compás de cada ocho va en tres pulsos (2+2+2) en lugar de dos (3+3) |

Notas:

- La melodía del lobby es propia; su célula (larga-corta-larga) es el ritmo de la llamada
  del alux llevado al 6/8. La cuerda pulsada no está en la paleta mesoamericana del resto:
  se añadió solo aquí porque el lugar es una plaza de ciudad. Si no encaja, basta quitar el
  bus `cuerda` de `mus_lobby()`.
- En `mus_jefe` el guardián «no recuerda»: el motivo se rompe (eco incompleto en A, flauta
  que se queda colgada en A2). En `mus_jefe_furia` se completa siempre.

## Instrumentos

Todos se sintetizan en `gen_musica.py`. Ninguno es un tono puro desnudo: llevan parciales,
ruido en el ataque, vibrato o deriva de afinación, y cada nota se toca con el tiempo y el
volumen algo sueltos y con variantes que alternan.

| Función | Qué es |
| --- | --- |
| `kalimba`, `marimba` | Lengüeta y tecla de madera: parciales inarmónicos que se apagan antes que el fundamental, y el toque |
| `flauta`, `ocarina` | Flauta de barro: tono con armónicos débiles, vibrato que tarda en entrar, entrada desde abajo, soplo y aire agudo |
| `coro`, `colchon`, `viento` | Colchones estéreo: voces con formantes de vocal (u, o, a) desafinadas y con aliento; onda casi triangular; ruido que respira |
| `huehuetl`, `tambor_mano` | Tambor grave de parche (fundamental que cae, modos de membrana, la mano) y su versión aguda |
| `teponaztli` | Tambor de hendidura de dos lengüetas: madera hueca |
| `sonaja`, `palo_lluvia` | Semillas: ruido agudo con grano irregular; cascada de granos que recorre el panorama |
| `caracol`, `trompa` | Caracol: armónicos que se abren con la envolvente |
| `cuerda` | Cuerda pulsada por síntesis aditiva (solo en el lobby) |
| `campana` | Campanita de jade, parciales inarmónicos |
| `golpe_roca`, `choque_losas`, `grava` | Percusión de piedra del jefe |
| `bajo`, `pulso_dron`, `dron_peligro` | Graves: nota suave, dron que late y dron continuo con batidos |

Los tambores están afinados con notas de la escala (Re, Fa, Sol, La, Do).

## Mezcla y masterizado

Como nadie puede escuchar, el equilibrio no se fija a ojo sino midiendo:

- Cada instrumento va a un bus estéreo con su posición en el panorama y su envío a la
  reverb. El nivel de cada bus se **mide y se lleva a un objetivo**: los tonales por
  sonoridad con puerta (LUFS «cuando suenan»), la percusión por su golpe más fuerte (ventana
  de 50 ms). `--detalle` imprime la tabla.
- Reverb estéreo por convolución con dos colas de ruido que comparten una parte (ancha,
  pero la suma a mono no se cancela); los agudos decaen antes.
- Masterizado: paso alto a 35 Hz (orden 3), paso bajo a 16 kHz, se quita la continua, un
  estante suave de agudos (+1.5 a +3 dB; los instrumentos sintetizados son oscuros),
  sonoridad al objetivo (ITU-R BS.1770, implementada en numpy) y limitador con anticipación
  de 3 ms. Después se codifica, se mide el MP3 con `ffmpeg ebur128` y, si hiciera falta, se
  corrige y se vuelve a codificar (no hizo falta: una pasada por pieza).

## Mediciones finales

Salida de `gen_musica.py --check` (todo medido sobre el **MP3 decodificado** con ffmpeg):

| id | Archivo (s) | Bytes | LUFS | Pico real (dBFS) | Correlación L/R (global / mínima en 3 s) | Energía en la escala | Costura: corr. 50 ms / pre-post / salto÷p99.9 |
| --- | ---: | ---: | ---: | ---: | --- | ---: | --- |
| `mus_claro` | 58.60 | 955 379 | −20.0 | −7.3 | 0.74 / 0.62 | 99 % | 1.0000 / 1.0000 / 0.21 |
| `mus_exploracion` | 58.60 | 960 808 | −20.0 | −7.7 | 0.67 / 0.49 | 100 % | 1.0000 / 1.0000 / 0.18 |
| `mus_peligro` | 39.40 | 544 330 | −20.0 | −5.2 | 0.73 / 0.56 | 91 % | 1.0000 / 1.0000 / 0.06 |
| `mus_emboscada` | 39.40 | 743 753 | −18.0 | −4.2 | 0.84 / 0.75 | 95 % | 1.0000 / 1.0000 / 0.13 |
| `mus_jefe` | 57.00 | 896 166 | −18.0 | −4.5 | 0.74 / 0.58 | 97 % | 0.9982 / 0.9962 / 0.49 |
| `mus_jefe_furia` | 45.80 | 807 461 | −18.0 | −5.9 | 0.76 / 0.56 | 95 % | 1.0000 / 1.0000 / 0.26 |
| `mus_recuerdo` | 58.60 | 933 393 | −20.0 | −7.0 | 0.62 / 0.37 | 98 % | 1.0000 / 1.0000 / 0.25 |
| `mus_liberacion` | 52.20 | 852 281 | −20.0 | −8.0 | 0.60 / 0.52 | 99 % | 1.0000 / 1.0000 / 0.64 |
| `mus_victoria` | 10.50 | 141 818 | −18.0 | −3.0 | 0.72 / 0.58 | 98 % | sin bucle; el último segundo queda a −93 dBFS |
| `mus_lobby` | 58.60 | 942 405 | −20.0 | −6.6 | 0.74 / 0.57 | 99 % | 1.0000 / 1.0000 / 0.19 |

Total: 7 777 794 bytes = 7.78 MB.

Reparto de la energía por bandas, en dB respecto al total de cada pieza:

| id | <35 Hz | 35–150 | 150–600 | 600–2k | 2–5 kHz | 5–10 kHz | >10 kHz |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| `mus_claro` | −46.1 | −10.1 | −1.1 | −9.3 | −20.7 | −27.4 | −33.2 |
| `mus_exploracion` | −45.9 | −10.3 | −1.7 | −6.6 | −17.9 | −25.5 | −32.3 |
| `mus_peligro` | −38.3 | −2.4 | −4.1 | −15.5 | −26.4 | −27.2 | −32.3 |
| `mus_emboscada` | −37.1 | −4.6 | −2.9 | −9.6 | −17.6 | −20.9 | −25.8 |
| `mus_jefe` | −38.6 | −7.9 | −1.8 | −8.1 | −18.3 | −27.3 | −36.1 |
| `mus_jefe_furia` | −37.2 | −7.2 | −3.6 | −4.7 | −16.6 | −24.8 | −34.0 |
| `mus_recuerdo` | −45.6 | −9.4 | −3.1 | −4.2 | −17.3 | −26.0 | −32.4 |
| `mus_liberacion` | −47.6 | −11.4 | −3.8 | −3.1 | −17.2 | −26.0 | −32.5 |
| `mus_victoria` | −43.4 | −7.7 | −3.7 | −4.2 | −16.2 | −26.0 | −32.4 |
| `mus_lobby` | −46.7 | −8.4 | −2.5 | −5.5 | −20.1 | −25.0 | −30.8 |

Otras medidas, hechas una vez a mano y no incluidas en `--check`:

- **Suma a mono:** pierde entre 0.4 y 1.0 dB respecto al estéreo según la pieza (no hay
  cancelaciones).
- **Pulso:** la autocorrelación de los ataques da el periodo esperado en claro, recuerdo,
  liberación y lobby (75 por minuto), jefe (120), y emboscada y furia (0.8 s, dos pulsos a
  150). En exploración y peligro, que casi no tienen percusión regular, no sale un pulso
  claro; es lo que se buscaba.

## Qué mide `--check`

Sobre cada MP3 decodificado con ffmpeg, y falla (código de salida 1) si:

- el formato no es MP3 estéreo a 44.1 kHz, o la duración, los bytes, la sonoridad o el pico
  no coinciden con `musica.json`, o `manifiesto_musica.json` no coincide con `musica.json`;
- la **sonoridad integrada** (`ffmpeg ebur128`) se sale de −19…−17 LUFS (emboscada, jefe,
  furia, victoria) o de −21…−19 (claro, exploración, peligro, recuerdo, liberación, lobby);
- el **pico real** pasa de −1.5 dBFS (el de `ebur128` y uno propio con sobremuestreo ×4), hay
  recorte o hay continua (> 0.001);
- la **correlación entre canales** global baja de 0.05 o la de alguna ventana de 3 s es
  negativa; o la pieza es casi mono (correlación > 0.97 o diferencia L−R por debajo de −30 dB);
- el **espectro** se sale de sus límites: menos de 35 Hz por encima de −22 dB; 35–150 Hz
  fuera de −20…−1.5 dB; 2–5 kHz fuera de −40…−9 dB; 5–10 kHz por encima de −14 dB; más de
  10 kHz fuera de −62…−22 dB (respecto a la energía total);
- menos del 85 % de la **energía tonal** (180–2000 Hz, a menos de 35 cents de un semitono)
  cae en notas de la escala declarada (75 % en `mus_peligro`): detecta errores de
  transposición;
- en los bucles: algún segundo queda 24 dB por debajo de la media (**hueco**); los puntos de
  bucle no cuadran con la duración; la ventana de 50 ms después de `loop[1]` no se
  correlaciona más de 0.98 con la de después de `loop[0]` (ni los 0.45 s de antes y de
  después); o **saltar de `loop[1]` a `loop[0]`** da un escalón entre muestras mayor que el
  percentil 99.9 de los que ya hay en el material. Esto último se prueba con el salto
  desplazado 0, 529, 1105, 2257 y −1105 muestras, que son los desfases típicos de un
  decodificador de MP3 que no recorta el retardo;
- en la fanfarria: no dura entre 8 y 12 s, no empieza o no acaba en silencio, o no termina
  con una cola que se apaga;
- un archivo pasa de 1.1 MB o el total de 9 MB.

Para saber si la comprobación detecta fallos de verdad se le dio una copia estropeada a
propósito y dio dieciocho fallos, al menos uno por cada defecto: una pieza subida 14 dB
(sonoridad, pico y recorte), una con un canal invertido (correlación −0.62), una pasada a
mono, una subida un semitono (38 % de energía en la escala, duración), y dos con el punto
de bucle mal declarado, por 0.3 s y por 11 ms (correlación de costura 0.60 y −0.49, escalón).

Los umbrales del espectro se pusieron después de ver las mediciones, con margen, para
vigilar regresiones; no son una norma externa.

## Espectrogramas

`--espectros` deja una hoja por pieza (`ffmpeg showspectrumpic`, frecuencia logarítmica, 90
dB de rango). Se revisaron las diez y, tras verlas, se corrigió lo siguiente:

- en `mus_exploracion` el grave tenía huecos de 3–4 s entre acordes: el bajo ahora se
  sostiene todo el acorde;
- todas quedaban oscuras por encima de 5 kHz: se añadió el estante de agudos, se abrió la
  reverb de los temas tranquilos y se subieron sonajas y gravilla;
- en `mus_peligro` el dron cargaba demasiado en el fundamental (35–150 Hz al borde del
  límite): se repartió hacia sus armónicos;
- en `mus_victoria` el grave del acorde final se cortaba antes que el resto: ahora se apaga
  con él;
- los tambores no estaban afinados con la escala (uno caía en Si): se afinaron.

En todas se ven las secciones y las entradas de instrumentos. Queda una cosa a la vista que
no se ha tocado: la bruma de agudos (3–15 kHz, a unos −65 dBFS) aparece y desaparece con las
notas de flauta y ocarina, porque es su soplo. Debería sonar a respiración, pero no se ha
oído.

## Qué no se ha podido comprobar

Con honestidad, todo lo que depende del oído:

- **Si suena bien.** Si las melodías emocionan, si el claro es «cálido» o el jefe «triste»,
  son intenciones de composición, no hechos medidos.
- **El timbre.** Son instrumentos sintetizados con pocos parciales. Lo más probable es que
  suenen limpios pero sencillos, a sintetizador más que a instrumento grabado; la flauta y
  la ocarina, sobre todo, son casi senoidales.
- **El equilibrio de la mezcla.** Los niveles se fijaron por medida con valores razonables,
  pero nadie ha confirmado que la melodía se oiga sobre el acompañamiento ni que los
  tambores no tapen o no se pierdan.
- **El espectro sigue siendo oscuro.** En `mus_claro` el 78 % de la energía está entre 150 y
  600 Hz (es el registro de la figura original de kalimba), y por encima de 10 kHz todas
  quedan entre −26 y −36 dB. Se prefirió quedarse corto de agudos a arriesgar estridencia.
- **Altavoces pequeños.** El latido de `mus_peligro` (49–55 Hz) y los fondos de tambor de los
  combates pueden no oírse en un portátil o un móvil; quedarían el dron y el ruido del parche.
- **El bucle en navegadores reales.** La costura se comprobó decodificando con ffmpeg y
  simulando desfases de decodificador, no reproduciendo en Chrome, Firefox o Safari con
  `loopStart`/`loopEnd`.
- **Los fundidos entre piezas.** Comparten notas y tempos emparentados, pero no se ha
  renderizado ni medido ningún fundido cruzado. El paso de `mus_jefe` (120) a
  `mus_jefe_furia` (150) no va a tempo: se fía al fundido.
- **El nivel dentro del juego.** No se ha medido la música junto a los efectos y los
  ambientes; los −20 y −18 LUFS son el encargo, no un ajuste hecho en contexto.
- **La originalidad** está garantizada por construcción (los temas salen de los motivos del
  propio proyecto y no se ha partido de ninguna obra), pero no se ha pasado ningún
  comparador de melodías: con células pentatónicas tan cortas, un parecido casual con algo
  existente no se puede descartar del todo.
- **La regularidad.** Sonajas y redobles llevan tiempos y volúmenes humanizados, pero a
  150 BPM pueden sonar mecánicos; el redoble de marimba de las notas largas del lobby es lo
  más dudoso.
- **Rangos supuestos.** El encargo no fija sonoridad para `mus_peligro` ni `mus_victoria`: se
  puso la primera con los temas tranquilos (−20) y la segunda con los de combate (−18).

Detalles menores: `mus_jefe` es el único bucle cuya duración (56 s) no es un múltiplo
entero de tramas de MP3, y por eso su costura se correlaciona 0.998 en lugar de 1.0000
(pasa el umbral de 0.98 con margen). Los cuatro archivos de 58.6 s pesan 0.93–0.96 MB, a un
13 % del límite de 1.1 MB: si se alargan, hay que vigilarlo.

## Procedencia y licencia

`art/audio/manifiesto_musica.json` lista cada archivo con su duración, sus bytes, la función
que lo genera y su semilla. Todo es síntesis propia de `art/audio/gen_musica.py`: original
del proyecto ALUX, sin material de terceros.
