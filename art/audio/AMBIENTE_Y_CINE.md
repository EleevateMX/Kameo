# Ambientes del mundo y banda sonora de las cinemáticas (Alpha 0.3.1)

Diez bucles de ambiente y ocho pistas de cinemática (efectos y música de las cuatro escenas),
en MP3 estéreo a 44.1 kHz, en `game/web/static/audio/`. **Todo es síntesis propia**: sale de
`gen_ambiente.py`, `gen_cine.py` y su módulo común `_dsp_estereo.py` (senos, ruido filtrado por
FFT, envolventes y convolución, con numpy). No hay grabaciones, muestras ni voces de nadie, y
ningún sonido imita el de una obra concreta. Las semillas son fijas.

**Nadie lo ha escuchado.** Se ha comprobado con mediciones y revisando espectrogramas, no de
oído. Lo que eso deja sin comprobar está en «Lo que no se ha podido comprobar».

Sustituye a las versiones provisionales (mono, 22 kHz) de `gen_audio.py`: `amb_selva`,
`amb_brasero` y los `cine_*` por plano. `gen_audio.py` no se ha tocado.

## Cómo regenerar

Hace falta Python con numpy (sirve el entorno de Blender del proyecto; no usa `bpy`) y `ffmpeg`
con `libmp3lame`.

```bash
.tools/blender-venv/bin/python art/audio/gen_ambiente.py            # genera, escribe ambiente.json y comprueba
.tools/blender-venv/bin/python art/audio/gen_cine.py                # genera, escribe cine.json y comprueba
.tools/blender-venv/bin/python art/audio/gen_ambiente.py --check    # solo mide lo que hay en disco
.tools/blender-venv/bin/python art/audio/gen_cine.py --check
.tools/blender-venv/bin/python art/audio/gen_ambiente.py --solo amb_agua,amb_aves
.tools/blender-venv/bin/python art/audio/gen_cine.py --solo sello --espectros /tmp/espectros
```

- Tardan unos 50 s (ambientes) y 20 s (cinemáticas), en un solo proceso.
- Los WAV intermedios (24 bits) van a la carpeta temporal del sistema (`alux_audio/`) o a la que
  diga la variable `ALUX_AUDIO_TMP`. No se versionan.
- `--check` devuelve un código distinto de cero si algo se sale de rango.
- Dos ejecuciones seguidas dan los mismos bytes en los 18 MP3 y los tres JSON (comprobado con
  numpy 2.5.4 y ffmpeg 6.1.1; con otra versión de LAME los MP3 cambiarán algo).
- Cada sonido deriva su semilla de su nombre (`[20261112, crc32(nombre)]`): cambiar uno no
  cambia los demás.
- Los dos scripts actualizan `manifiesto_ambiente_cine.json` (procedencia de cada archivo).

## Convención de bucle

Cada archivo de ambiente se escribe así:

```
[ pre = últimos 0.5 s del cuerpo ][ cuerpo circular, L segundos ][ post = primeros 0.5 s del cuerpo ]
```

y `ambiente.json` declara `"loop": [0.5, 0.5 + L]`. El cuerpo es circular de verdad: el ruido y
los moduladores son periódicos en L, las colas de sala se enrollan y los eventos que cruzan el
final se suman al principio.

**El cuerpo mide un número entero de cuadros MP3 (1152 muestras).** Por eso L no es un número
redondo de segundos (30.093 s, 27.429 s…). Se midió la diferencia: con un bucle de ruido de
30.000 s, lo que el decodificador entrega tras `loop[1]` se parece a lo que entrega tras
`loop[0]` con correlación 0.81; con el cuerpo alineado a cuadros, 1.0000, porque el codificador
ve la misma señal en la misma posición del cuadro. Si se cambia la duración de un bucle, hay que
mantenerla en múltiplos de 1152 muestras (la tabla `BUCLES` la da en cuadros).

## Ambientes

Sonoridad objetivo −28 LUFS (rango pedido −30…−26), pico ≤ −6 dBFS, LAME `-q:a 6`, bus `Ambience`.

| Archivo | Bucle (s) | Archivo (s) | Bytes | LUFS | Pico (dBFS) | Qué es y capas |
| --- | --- | --- | --- | --- | --- | --- |
| `amb_selva.mp3` | 30.09 | 31.09 | 385 681 | −28.0 | −13.3 | Base de selva de día, sin cantos protagonistas. Aire (110–700 Hz); hojas en cuatro copas (1.3–7 kHz) con rachas independientes; zumbido lejano de insectos en tres bandas estrechas (3.1, 4.3 y 5.9 kHz) con trémolo |
| `amb_aves.mp3` | 27.43 | 28.43 | 163 601 | −28.0 | −12.9 | Doce cantos de diez tipos inventados (caída, dos notas, trino, gorjeo, arrullo, llamada en eco, ululo, píos, carraca, flauteo), cada uno con tono, rapidez, distancia y lado al azar; eco de follaje y sala; lecho muy tenue de bandada lejana |
| `amb_insectos.mp3` | 25.08 | 26.08 | 285 810 | −28.1 | −11.6 | Cuatro chicharras (ruido en banda de 4.3 a 7.1 kHz, trémolo de 34–58 pulsos/s, oleadas lentas); cinco grillos (chirridos tonales de 3.7–5.2 kHz que entran y salen) |
| `amb_viento.mp3` | 31.35 | 32.35 | 288 613 | −27.8 | −10.5 | Ruido de banda móvil (230–800 Hz según la fuerza de la ráfaga) en centro y lados, con la ráfaga cruzando de un lado a otro; dos resonancias huecas (236 y 352 Hz) solo en las ráfagas fuertes; hojas altas; fondo grave. Sin silbido |
| `amb_agua.mp3` | 23.51 | 24.51 | 313 879 | −28.0 | −13.9 | Arroyo cercano: murmullo en siete bandas (350 Hz–7.5 kHz) que borbotean por separado; gorgoteo grave; unas 600 burbujas (silbidos ascendentes de 12–50 ms) |
| `amb_cenote.mp3` | 32.00 | 33.00 | 290 891 | −28.0 | −11.4 | Aire de caverna; resonancias graves sobre Re y La (73, 110, 147 y 196 Hz); agua profunda que lame despacio; unas quince gotas (algunas dobles) con dos ecos de pared y sala de 3.6 s |
| `amb_ruinas.mp3` | 28.21 | 29.21 | 246 576 | −28.1 | −14.9 | Aire grave; cinco resonancias huecas (92–466 Hz) que respiran; soplo medio tenue; dos piedrecillas por bucle (una que rebota y otra que apenas cae) |
| `amb_tormenta.mp3` | 26.75 | 27.75 | 416 841 | −27.8 | −8.0 | Siseo de lluvia (0.7–9 kHz); miles de gotas en tres tamaños (quince granos distintos); goterones sobre hojas grandes; rumor grave; dos truenos lejanos distintos por bucle (uno más presente, otro muy lejos) |
| `amb_energia.mp3` | 22.57 | 23.57 | 227 150 | −28.0 | −19.0 | Siete parciales sobre Re3 (dos voces cada uno, que baten) con un latido de ~0.45 Hz y panorámica lenta; halo agudo que late; destellos de cristal en Re menor pentatónica, con sala |
| `amb_brasero.mp3` | 10.03 | 11.03 | 123 550 | −27.9 | −13.1 | Retumbo (50–220 Hz) y rugido (150–1400 Hz) al centro; rugido lateral tenue; siseo; unos 90 chasquidos con panorámica estrecha. Correlación entre canales 0.89: funciona en mono |

Total: 2 742 592 bytes (2.74 MB; límite 3.5 MB). El mayor, `amb_tormenta`, pesa 417 KB (límite 450 KB).

Cómo se reparten en el espectro (energía por bandas, en %, medida sobre el MP3):

| Capa | < 200 Hz | 200 Hz–1 kHz | 1–4 kHz | 4–8 kHz | > 8 kHz |
| --- | --- | --- | --- | --- | --- |
| `amb_selva` | 30 | 56 | 10 | 4 | 0 |
| `amb_aves` | 0 | 11 | 87 | 2 | 0 |
| `amb_insectos` | 0 | 0 | 6 | 89 | 4 |
| `amb_viento` | 11 | 76 | 12 | 0 | 0 |
| `amb_agua` | 2 | 57 | 35 | 5 | 0 |
| `amb_cenote` | 73 | 26 | 1 | 0 | 0 |
| `amb_ruinas` | 73 | 27 | 0 | 0 | 0 |
| `amb_tormenta` | 65 | 7 | 17 | 9 | 1 |
| `amb_energia` | 36 | 63 | 0 | 0 | 0 |
| `amb_brasero` | 39 | 52 | 9 | 0 | 0 |

Selva (graves y medios), aves (1–4 kHz) e insectos (4–8 kHz) casi no se pisan. Cenote y ruinas
viven en los graves y dejan libre todo lo demás. Los bucles tienen duraciones distintas a
propósito: sonando varios a la vez, la combinación tarda mucho en repetirse.

Eventos sueltos (lo que más delata un bucle): los dos truenos de la tormenta, las dos
piedrecillas de las ruinas, las gotas del cenote y los cantos de ave. Están una sola vez por
bucle cada uno, con variaciones, y a nivel discreto.

## Cinemáticas

Dos pistas por cinemática, sin bucle, de la duración exacta de la escena más 1.5 s de cola. El
segundo 0 del archivo es el segundo 0 de la cinemática. Efectos a −18 LUFS (rango −20…−16) con
pico ≤ −2 dBFS; música a −22 LUFS (rango −24…−20), unas 4 LU por debajo; la suma de las dos no
pasa de −1 dBFS. LAME `-q:a 5`.

| Archivo | Bus | Duración (s) | Bytes | LUFS | Pico (dBFS) | Pico de la suma fx+mus |
| --- | --- | --- | --- | --- | --- | --- |
| `cine_sello_fx.mp3` | Cinematics | 11.50 | 183 199 | −17.9 | −3.8 | −1.9 |
| `cine_sello_mus.mp3` | Music | 11.50 | 157 682 | −21.9 | −9.0 | |
| `cine_despertar_fx.mp3` | Cinematics | 17.50 | 260 377 | −18.0 | −3.4 | −1.4 |
| `cine_despertar_mus.mp3` | Music | 17.50 | 214 653 | −22.1 | −11.8 | |
| `cine_liberacion_fx.mp3` | Cinematics | 13.50 | 190 439 | −18.0 | −4.3 | −3.0 |
| `cine_liberacion_mus.mp3` | Music | 13.50 | 169 153 | −21.9 | −8.9 | |
| `cine_llamado_fx.mp3` | Cinematics | 20.50 | 289 470 | −17.9 | −3.5 | −2.3 |
| `cine_llamado_mus.mp3` | Music | 20.50 | 286 979 | −21.9 | −10.1 | |

Total: 1 751 952 bytes (1.75 MB; límite 2.2 MB).

`cine.json` lleva además, por cinemática, sus dos pistas, la duración y el segundo en que
empieza cada plano (`shots`). Las duraciones de los planos están en `PLANOS` (`gen_cine.py`) y
`--check` las compara con `game/scripts/shared/story_def.gd`: si alguien cambia un plano, falla.

Música: Re menor pentatónica (Re Fa Sol La Do) como centro, con instrumentos sintetizados de
inspiración mesoamericana: flauta de barro/ocarina, tambor grande de tronco, tambor de mano,
sonaja de semillas, caracol y trompa, kalimba, madera hueca. Hay tres notas de fuera de la
escala, puestas a propósito como tensión: Mi♭ (despertar, plano 2) y Sol♯, el tritono del
Silencio (sello, plano 3; pulsos del sello en «El llamado»). El motivo del guardián es el mismo
de la música de combate (`gen_audio.py`): La–Re–Fa en menor al ponerse en pie y Do–Fa–La |
Sol–Fa–Do en mayor al entregar la pluma.

### «El sello cede» (`sello`, 10 s: 3 + 4 + 3)

| Plano | Tiempo | Efectos (`cine_sello_fx`) | Música (`cine_sello_mus`) |
| --- | --- | --- | --- |
| 1. Los altares | 0.0–3.0 | Cuatro altares entran uno a uno, cada uno en su lado: 0.10 (Re4, izq.), 0.55 (Fa4, der.), 1.00 (La4), 1.45 (Do5): tono de piedra que crece, campanilla al encenderse y golpe sordo. Siete estelas de ruido ascendente que van de los lados al centro, cada vez más seguidas (0.45–3.0). 46 chispas de jade que se aprietan hacia 3.0. Grave que crece | Colchón de Re. Ocarina que sube: La4 (0.35), Do5 (1.05), Re5 (1.75–3.05). Tambor grave en 0.04, 1.0, 2.0, 2.5, 2.75. Sonaja que crece (1.8–3.0) |
| 2. El sello se rompe | 3.0–7.0 | 3.0–4.95: zumbido que sube siete semitonos con trémolo cada vez más rápido, crujidos que se agolpan, chasquidos en 3.9, 4.4 y 4.75. **4.95**: grieta grande y porrazo. **5.05**: estallido vítreo (ruido de 2.5–9 kHz, 26 parciales de cristal, esquirlas hasta 6.3). 5.30–6.75: la losa se arrastra (roce a tirones, gemido 70→48 Hz). **6.72**: la losa encaja (impacto y subgrave), cascotes hasta 7.25 | Redoble de tambor que se cierra (3.0–4.9), caracol en Re2 que crece (3.35–4.95). **5.05**: golpe de tambor grande, caracoles en Re3 y La3 (hasta 7.0), kalimba que baja Re5 Do5 La4 Sol4 Fa4 Re4 desde 5.25. Tambor en 6.72 |
| 3. Algo despierta | 7.0–10.0 | Aire interior muy bajo y un tono fino que bate (1175/1178 Hz). Algo se arrastra en 7.85 (der.) y 8.55 (izq.); gruñido lejano en 8.25. **9.0–10.0**: el aviso de los Olvidados crece (gemido 82→112 Hz, zumbido que sube, castañeteo de piedra que se acelera). **9.97**: golpe seco y corte; cola de sala hasta 11.5 | Re con su tritono (Sol♯), muy bajo. Kalimba suelta: La4 (7.4), Fa4 (8.1), Re4 (8.7). Latido de tambor que se acelera: 8.0, 8.8, 9.3, 9.6, 9.8. Sonaja que crece (8.97–9.97). **9.97**: golpe final, sin resolver: después empieza la emboscada |

### «El despertar de Nojoch Tuunich» (`despertar`, 16 s: 4 × 4)

| Plano | Tiempo | Efectos (`cine_despertar_fx`) | Música (`cine_despertar_mus`) |
| --- | --- | --- | --- |
| 1. El patio en silencio | 0.0–4.0 | Aire grave muy bajo. Respiración lenta de piedra, lejos: inspira 0.45–1.95, espira 2.15–3.9 con un gemido de 47 Hz debajo (apagada a 1.1 kHz, con mucha sala) | Re2 y La2 casi inaudibles; una nota de ocarina grave (La3, 1.5–3.2) que cae un semitono |
| 2. Las grietas | 4.0–8.0 | 110 crujidos que se agolpan; chasquidos gordos en 4.25, 5.1, 5.9, 6.6, 7.2 y 7.65, con polvo y cascotes. El Silencio se cuela: zumbido que entra desde cero y crece, balanceándose entre los lados. Latido magenta (doble, con anillo de cristal) en 5.0, 6.0, 7.0 y 7.6, cada vez más fuerte | Tambor grave con los latidos (4.02, 5.02, 6.02, 7.02, 7.62). Colchón de Re con Mi♭ que crece. Sonaja trémula (6.0–8.0) |
| 3. Los ojos | 8.0–12.0 | **8.0**: todo se corta. Silencio breve (8.0–9.0; el --check exige 15 dB menos que el final del plano 2). **9.0**: golpe tonal seco, sin sala (porrazo corto, Re2 + Re3 y un destello de cristal). Queda un tono fino que bate (932/936 Hz): los ojos encendidos. 9.5–11.9: gemido grave de piedra (52→82→52 Hz) con roce; cascotes sueltos | Silencio desde 8.0. **9.0**: tambor y caracol corto en Re2. Colchón grave (Re2 La2 Do3) que crece de 9.5 a 12.4 |
| 4. En pie | 12.0–16.0 | 12.0–14.8: arrastre de roca enorme que crece (roce a tirones, temblor de 7.5 Hz), gemido que sube 50→96 Hz, crujidos, cascotes y polvo. Un hueco de 0.2 s. **15.0**: pisada final (impacto 125→32 Hz, subgrave, 26 cascotes, polvo): es el tramo con más energía de la pista. Cola hasta 17.5 | Tambores que se aprietan (12.0, 12.75, 13.5, 14.0, 14.4, 14.7, 14.86) y caracol en Re2 que crece. **15.0**: entra su tema en trompa grave, La2 (15.00) – Re3 (15.32) – Fa3 (15.64–17.4), doblada una octava abajo; tambor en 15.64; colchón de Re menor. En 15.0 la música no lleva tambor: el golpe es la pisada |

### «La liberación de Nojoch Tuunich» (`liberacion`, 12 s: 3 × 4)

| Plano | Tiempo | Efectos (`cine_liberacion_fx`) | Música (`cine_liberacion_mus`) |
| --- | --- | --- | --- |
| 1. El Silencio se va | 0.0–4.0 | El zumbido baja tres semitonos y se rompe en granos hasta apagarse (0–3.3). 80 motas (de 2.2 a 6.7 kHz), cada vez más agudas y más abiertas en el estéreo. Las grietas se apagan una a una en 0.45, 1.15, 1.85, 2.55 y 3.25: la primera es casi todo crujido y la última casi toda campanilla (La5, Do6, Re6, Fa6, La6) | El Re menor se disuelve (colchón que se apaga); kalimba Re4 (0.8) y Fa4 (2.2); flauta Do5 (3.1) que anuncia el cambio |
| 2. La serenidad | 4.0–8.0 | Aire limpio (3.7–8.3). Su voz, de piedra pero en calma: un gemido suave de 98→82 Hz, sin palabras (4.9–7.5). En 6.9, un ave lejana de dos notas: la selva vuelve a oírse | Fa mayor, el relativo: colchón cálido desde 3.6. Flauta de barro que sube: La4 (4.4), Do5 (5.6), Fa5 (6.6–8.3) |
| 3. La Pluma de Jade | 8.0–12.0 | Soplo ascendente (7.95–8.55) y, en **8.15**, destello de cristal (Re6, La6, Re7). 50 chispas que se van espaciando (8.2–11.6). El aire de la pluma, que flota hacia el grupo (8.3–11.5, de la izquierda al centro). Campanilla en 11.0. Cola hasta 13.5 | **8.30**: arpegio luminoso de kalimba y campana, Fa4 La4 Do5 Re5 Fa5 La5 Do6, cada 0.17 s, de izquierda a derecha. **9.75**: el motivo del guardián en mayor (Do5 Fa5 La5, Sol5 Fa5 Do6; última nota en 11.55, que resuena). Colchón de Fa mayor y flauta en Do6 (11.2–13.4): cola larga |

### «El llamado» (`llamado`, 19 s: 5 + 4.5 + 5 + 4.5)

| Plano | Tiempo | Efectos (`cine_llamado_fx`) | Música (`cine_llamado_mus`) |
| --- | --- | --- | --- |
| 1. La selva no canta | 0.0–5.0 | Viento sobre las copas, una sola ráfaga lenta, y hojas. Sin aves, salvo una llamada en eco, lejana (1.5–2.5), que nadie contesta | Tono de cuento: kalimba que abre (Re4 0.30, La4 0.75, Re5 1.20, Do5 2.10, La4 2.55, Fa4 3.40, Sol4 3.85, La4 4.30), colchón de Re, ocarina que baja (La4 2.0, Sol4 3.25, Fa4 4.15) |
| 2. El cenote oscuro | 5.0–9.5 | Aire de caverna, agua quieta y un tono oscuro de 55 Hz. Tres gotas con dos ecos de pared y sala larga: 5.75, 7.15 y 8.55 | Más oscuro: Re grave con Fa; kalimba baja (Re4 5.4, Fa4 6.2, Re4 7.0, Do4 7.9); flauta grave en Re4 (6.5–9.0) que cae dos semitonos |
| 3. El santuario sellado | 9.5–14.5 | El zumbido del sello (Re2, trémolo lento) y un grave debajo. Tres pulsos del sello, cada vez más fuertes: 10.6, 12.2 y 13.6 (latido, cristal en Re5 con su tritono y chispas). Un roce de piedra en 11.4 | Tambor grave lento (9.6, 10.9, 12.2, 13.3, 14.0), colchón Re–La–Do que crece, sonaja trémula (12.5–14.4), caracol muy bajo (11.0–14.3) |
| 4. Chiich Yaxché | 14.5–19.0 | Hojas y aire cálido. El tronco cruje (14.55, 16.6). **La voz de árbol**, hecha de madera que cruje y aire por un tronco hueco, sin palabras: primera frase 14.80–16.50 (tres «sílabas» con la segunda acentuada, pausa, y dos más con la última hacia arriba: una llamada); segunda frase 16.90–18.56 (siete sílabas más bajas, que caen: un refunfuño). **18.35 y 18.58**: toc-toc de madera hueca. 18.72: tres campanillas que suben (Re6 Fa6 La6) y chispas: despierta | Calidez: Fa–La–Do sobre Re. Flauta que sube: La4 (15.0), Do5 (15.75), Re5 (16.5), Fa5 (17.5–19.4). Arpegio de kalimba (Re4 Fa4 La4 Do5 Re5, 16.0–17.2). Tambor de mano (17.0, 17.4, 17.8, 18.2, 18.6). Cierra abierto, en Re5 + La4 (18.9) |

## Mediciones finales

Salida de `--check` (12 nov 2026). «I·D» es la correlación entre canales; «corr» y «salto», la
costura del bucle (ver abajo).

```
archivo           seg  bucle   bytes   LUFS   pico   I·D       DC    corr    salto   típico  <200 -1k -4k -8k >8k  resultado
amb_selva       31.09  30.09  385681  -28.0  -13.3  0.58  0.00001  1.0000  0.00755  0.03705    30  56  10   4   0  ok
amb_aves        28.43  27.43  163601  -28.0  -12.9  0.50  0.00000  1.0000  0.00131  0.03411     0  11  87   2   0  ok
amb_insectos    26.08  25.08  285810  -28.1  -11.6  0.69  0.00000  1.0000  0.01243  0.09653     0   0   6  89   4  ok
amb_viento      32.35  31.35  288613  -27.8  -10.5  0.65  0.00000  1.0000  0.00017  0.02188    11  76  12   0   0  ok
amb_agua        24.51  23.51  313879  -28.0  -13.9  0.52  0.00000  1.0000  0.00605  0.02833     2  57  35   5   0  ok
amb_cenote      33.00  32.00  290891  -28.0  -11.4  0.65  0.00000  1.0000  0.00233  0.00587    73  26   1   0   0  ok
amb_ruinas      29.21  28.21  246576  -28.1  -14.9  0.80  0.00001  1.0000  0.00128  0.00523    73  27   0   0   0  ok
amb_tormenta    27.75  26.75  416841  -27.8   -8.0  0.45  0.00002  1.0000  0.00535  0.05712    65   7  17   9   1  ok
amb_energia     23.57  22.57  227150  -28.0  -19.0  0.81  0.00001  1.0000  0.00135  0.00526    36  63   0   0   0  ok
amb_brasero     11.03  10.03  123550  -27.9  -13.1  0.89  0.00002  1.0000  0.00326  0.01310    39  52   9   0   0  ok
Total ambientes: 2742592 bytes = 2.743 MB (límite 3.5 MB)
RESULTADO: ok

archivo                   seg   bytes   LUFS   pico   I·D       DC  <200 -1k -4k -8k >8k  resultado
cine_sello_fx           11.50  183199  -17.9   -3.8  0.74  0.00002    44  39  12   4   0  ok
cine_sello_mus          11.50  157682  -21.9   -9.0  0.90  0.00001    63  33   3   0   0  ok
  → sello: suma de efectos y música, pico -1.9 dBFS; música 4.0 LU por debajo; 5 hitos de tiempo: ok
cine_despertar_fx       17.50  260377  -18.0   -3.4  0.86  0.00005    69  20   8   2   0  ok
cine_despertar_mus      17.50  214653  -22.1  -11.8  0.91  0.00002    75  23   1   0   0  ok
  → despertar: suma de efectos y música, pico -1.4 dBFS; música 4.1 LU por debajo; 6 hitos de tiempo: ok
cine_liberacion_fx      13.50  190439  -18.0   -4.3  0.79  0.00002    35  15  47   3   0  ok
cine_liberacion_mus     13.50  169153  -21.9   -8.9  0.69  0.00001     9  81  10   0   0  ok
  → liberacion: suma de efectos y música, pico -3.0 dBFS; música 3.9 LU por debajo; 5 hitos de tiempo: ok
cine_llamado_fx         20.50  289470  -17.9   -3.5  0.50  0.00000    33  59   7   1   0  ok
cine_llamado_mus        20.50  286979  -21.9  -10.1  0.77  0.00000    18  78   4   0   0  ok
  → llamado: suma de efectos y música, pico -2.3 dBFS; música 4.0 LU por debajo; 4 hitos de tiempo: ok
Total cinemáticas: 1751952 bytes = 1.752 MB (límite 2.2 MB)
RESULTADO: ok
```

Qué mide `--check`, siempre sobre el MP3 decodificado con ffmpeg:

- Duración, tamaño (por archivo y total), sonoridad integrada (`ffmpeg ebur128`) y pico de muestra.
- Continua (< 0.0005), correlación entre canales no negativa (≥ 0.6 en el brasero) y no más
  del 20 % de la energía por encima de 8 kHz.
- Que el manifiesto diga lo que hay en disco (bytes, duración, LUFS, pico).
- **Bucles**: la ventana de 50 ms tras `loop[1]` se correlaciona > 0.98 con la de 50 ms tras
  `loop[0]`, y el salto de `loop[1]` a `loop[0]` no supera el percentil 99.9 de los saltos
  normales entre muestras de la propia pista («típico»). Las dos pruebas se repiten con el
  contenido desplazado 529, 1105 y 2257 muestras, por si el decodificador del navegador no
  recorta el retardo del codificador; se informa del peor caso. También que el bucle mida un
  número entero de cuadros MP3.
- **Cinemáticas**: que las duraciones coincidan con `story_def.gd`; que los extremos sean
  silencio; que la suma de efectos y música no pase de −1 dBFS; que la música vaya por debajo;
  y 20 «hitos» de tiempo (tabla `HITOS`) que comprueban que cada evento cae en su plano: por
  ejemplo, que el golpe de los ojos esté en 9.0 s ± 0.06, que haya silencio entre 8.15 y 8.95 s,
  que la pisada de 15.0 s sea el tramo con más energía, que el estallido vítreo esté en 5.0–5.5 s
  o que la voz de árbol esté en el plano 4.

Se probó también al revés: con una copia estropeada a propósito (un bucle mal declarado y una
pista de cinemática retrasada 1 s y subida 6 dB) `--check` dio 4 y 9 fallos.

Revisión de espectrogramas (`ffmpeg showspectrumpic`, uno por archivo, mirados uno a uno).
Lo que se vio y se corrigió:

| Archivo | Lo que se veía | Corrección |
| --- | --- | --- |
| `amb_aves` | Un canto de ruido dominaba el nivel y el resto quedaba tapado por el lecho | Cada canto se normaliza por separado y el lecho baja |
| `amb_cenote` | El agua profunda eran golpes de banda ancha cada 2–4 s (repetición evidente) | Banda más estrecha y vaivén más suave; cola de las gotas más larga en agudos |
| `amb_ruinas`, `amb_cenote`, `amb_selva` | Casi toda la energía por debajo de 200 Hz | Menos subgrave y más medios (en ruinas, del 96 % al 73 %) |
| `amb_tormenta` | Líneas horizontales fijas (el mismo grano repetido) y 478 KB | Quince granos distintos; bucle más corto; truenos más bajos para que el limitador no bombee la lluvia |
| `amb_insectos` | Los grillos no se veían | Suben 8 dB |
| `cine_despertar_fx` | La «respiración lejana» del plano 1 sonaba tan fuerte como la pisada | Baja 18 dB; se reequilibraron los cuatro planos |
| `cine_sello_fx` | Cascotes del plano 2 metidos en el silencio del plano 3 | Acaban en 7.25 s |
| `cine_llamado_fx` | Cuatro ráfagas de viento en 5 s (vaivén rápido); la voz, por debajo del zumbido del sello | Una ráfaga lenta; la voz sube 7.6 dB y el sello baja |
| `cine_liberacion_fx` | La voz de piedra dominaba el plano 2 | Baja a la mitad y sube de 62–74 a 82–98 Hz |

En `amb_energia` se ven franjas cada 2.2 s: es el latido, que es lo pedido (su hondura y su
fase varían despacio para que no sea mecánico).

## Lo que no se ha podido comprobar

- **Nadie lo ha escuchado.** Las mediciones dicen que los niveles, los tiempos, el espectro y
  las costuras están donde deben; no dicen si suena bien. Lo más incierto, por orden:
  1. La **voz de árbol** de «El llamado»: es una idea (pulsos de crujido con dos resonancias y
     la curva de una frase). Puede sonar a puerta que chirría más que a personaje.
  2. Los **cantos de ave**: son silbidos sintéticos. Con distancia y sala deberían pasar por
     aves; de cerca pueden sonar a sintetizador.
  3. La **lluvia** y el **arroyo**: texturas de ruido y granos; lo normal es que suenen más
     «limpios» que una grabación.
  4. Si la música de las cinemáticas emociona o solo acompaña. Es sobria: pocas notas.
- **Graves.** `amb_cenote`, `amb_ruinas`, los truenos y casi toda la música de «El despertar»
  viven por debajo de 200 Hz. En altavoces de portátil o de móvil se oirán mucho menos que en
  auriculares. Varias capas graves a la vez (selva + viento + ruinas) pueden emborronarse.
- **El limitador.** Los golpes de los efectos pasan por un limitador para caber en −18 LUFS con
  pico de −2 dBFS: actúa en menos del 5 % del tiempo de cada pista, con una reducción máxima
  de 3 a 7 dB en el golpe más fuerte. La música de «El despertar» quedó con el techo más bajo
  (−11.8 dBFS) para que la suma con la pisada no pasara de −1 dBFS. No se sabe si se nota.
- **Repetición a los diez minutos.** Los espectrogramas no enseñan franjas periódicas dentro de
  un bucle (salvo el latido de la energía), pero un bucle de 23–32 s se repite, y el oído lo
  acaba aprendiendo. Los eventos más reconocibles son el trueno mayor, la piedrecilla que rebota
  y, en `amb_aves`, los píos y la carraca, que salen dos veces cada uno (con otro tono y otro lado).
- **El navegador.** La costura se ha medido con el decodificador de ffmpeg y con desfases
  simulados, no con Web Audio en un navegador real.
- **La integración.** Estos archivos no están conectados al juego: no se tocó ningún archivo de
  `game/`. Los planos de `story_def.gd` siguen declarando su `sound` por plano (`objetivo`,
  `santuario_abre`, `cine_grietas`…): si el reproductor pone estas bandas sonoras **y** esos
  sonidos, se oirán dobles.
- La reproducibilidad byte a byte solo se ha probado en esta máquina.
