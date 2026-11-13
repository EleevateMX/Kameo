# Candidatos de ajuste de timbre y mezcla (carpeta de revisión)

Carpeta para **elegir de oído**. Para cinco frentes del audio de la Alpha 0.3.1 trae el sonido
actual como referencia (`<frente>__actual.mp3`) y dos o tres candidatos con enfoques distintos
(`<frente>__A_<idea>.mp3`, `__B_…`, `__C_…`), más una propuesta de mezcla.

- **Nada de esto está en el juego.** No se ha tocado `game/`, ni los generadores
  (`gen_audio.py`, `gen_ambiente.py`, `gen_cine.py`, `_dsp_estereo.py`), ni sus manifiestos. Los
  candidatos no se declaran en ningún manifiesto porque no viajan con el juego.
- **Ningún candidato está validado de oído.** Nadie los ha escuchado, tampoco quien los hizo. Se
  han comprobado con mediciones y mirando espectrogramas junto al sonido actual. Las
  recomendaciones de abajo son **por medición**: dicen qué candidato cumple mejor lo que se
  pidió en números, no cuál suena mejor. Para eso está la hoja de escucha.
- **Todo es síntesis propia con numpy**, con semillas fijas: ni grabaciones, ni muestras de
  terceros, ni bibliotecas de sonido, y ningún sonido imita el de una obra concreta. Las
  vocales de la voz de Chiich Yaxché usan frecuencias de formantes típicas de una voz de mujer
  (son datos acústicos generales, no una voz grabada). Las «especies» de ave son inventadas.

## Qué hay y cómo se regenera

| Qué | Archivos |
| --- | --- |
| Generador | `gen_candidatos.py` (lanzador y medidas), `comun.py` (utilidades), `f1_balam.py`, `f2_chiich.py`, `f3_aves.py`, `f4_graves.py`, `f5_jefe.py` (un frente por archivo) |
| Medidas de cada MP3 | `medidas.json` (lo escribe el generador; las tablas de este documento salen de ahí con `--tablas`) |
| Audio | 53 MP3 (`libmp3lame -q:a 4`): 16 referencias y 37 candidatos (incluidas las versiones en contexto) |

```bash
.tools/blender-venv/bin/python art/audio/candidatos/gen_candidatos.py                 # todo (unos 70 s, un solo proceso)
.tools/blender-venv/bin/python art/audio/candidatos/gen_candidatos.py --solo balam    # balam, chiich, aves, graves o jefe
.tools/blender-venv/bin/python art/audio/candidatos/gen_candidatos.py --medir         # solo vuelve a medir los MP3
.tools/blender-venv/bin/python art/audio/candidatos/gen_candidatos.py --espectros DIR # espectrogramas comparativos (actual | A | B | C)
.tools/blender-venv/bin/python art/audio/candidatos/gen_candidatos.py --tablas        # las tablas de este documento
```

- Tiempos medidos (con la máquina ocupada en otras pruebas): Balam 2–4 s, Chiich 10–13 s, aves 22–24 s, graves 27–28 s, jefe 5–9 s.
- Dos ejecuciones seguidas dieron los mismos bytes en los 53 MP3 (numpy 2.5.4, ffmpeg 6.1.1).
- Devuelve un código distinto de cero si algún MP3 pasa de −1 dBFS o tiene componente continua.
- Los WAV sin pérdidas de cada candidato quedan en la carpeta temporal del sistema
  (`alux_audio/candidatos/`, o la que diga `ALUX_AUDIO_TMP`). Si se elige uno, lo correcto es
  llevar su función al generador que toque (`gen_audio.py`, `gen_ambiente.py` o `gen_cine.py`)
  y regenerar desde ahí; el MP3 de esta carpeta es solo para escuchar.

## Cómo leer las tablas

Todo se mide sobre el MP3 decodificado.

- **Pico** y **RMS**, en dBFS. **RMS 50 ms**: el tramo de 50 ms más fuerte (la «pegada»).
- **LUFS-M** (o «LUFS-M máx»): sonoridad momentánea máxima, la ventana de 400 ms más fuerte con
  la ponderación de oído de la norma BS.1770. Es la medida con la que **se han igualado los
  efectos cortos**: cada candidato tiene el mismo LUFS-M que el sonido actual (± 0.1), para que
  la comparación de oído sea justa. **LUFS**: sonoridad integrada de todo el archivo, para lo
  que dura más de 3 s; los bucles van a −28 LUFS y la pista de la cinemática a −18, como en el
  juego.
- **Íd. > 200 Hz**: la misma sonoridad después de quitar todo lo que hay por debajo de 200 Hz.
  Es una aproximación de **lo que queda en el altavoz de un portátil o de un móvil**. Cuanto
  más se parece al LUFS-M, menos depende el sonido de los graves.
- **Bandas (%)**: reparto de la energía. Las bandas cambian según el frente (las que se pidieron).
- **Máximo en (s)** y **A −20 dB (s)**: cuándo llega el máximo de la envolvente y cuánto
  tiempo pasa el sonido a menos de 20 dB de ese máximo (su «largo» útil). **Centro (Hz)**:
  centro de gravedad del espectro.
- **Tramas periódicas (%)** (solo Balam): en qué parte del sonido la onda se repite con
  claridad de un ciclo al siguiente. Un tren de pulsos iguales —el «zumbido»— da cerca del
  100 %; una voz ronca, bastante menos; un soplo, casi nada. Mide regularidad, no calidad.
- **Costura** e **I·D** (solo bucles): la misma prueba de `gen_ambiente.py --check` (lo que
  suena tras el final del bucle se parece a lo que suena tras el principio; exige más de 0.98)
  y la correlación entre canales (1 = mono; más baja = más abierto). En las filas `__actual`
  pone «(juego)»: su costura la comprueba `gen_ambiente.py --check` (1.0000 en los tres) y su
  correlación entre canales es 0.50 (aves), 0.65 (cenote) y 0.80 (ruinas). En los siete bucles
  candidatos, además, el salto en el empalme queda muy por debajo del salto típico entre muestras.

Formato: los efectos (Balam y jefe) van en mono a 22.05 kHz, como los del juego, y con el
mismo acabado (3 ms de silencio delante, entrada de 2 ms, fundido final). Los ambientes y la
cinemática, en estéreo a 44.1 kHz. Las referencias `__actual` de los efectos son el WAV del
juego pasado a MP3; las de ambientes y cinemática, una copia del MP3 del juego.

---

## 1. Rugido de Balam (`balam_rugido`, `balam_grunido`, `balam_especial`)

**Problema.** El rugido actual es un diente de sierra (pulsos idénticos de 82–116 Hz) con la
amplitud cerrada a ritmo fijo (27–29 veces por segundo) y dos juegos de formantes estáticos que
se mezclan. Medido: el 80 % de sus tramas son periódicas, el 72 % de la energía está en
150–600 Hz y solo el 4 % en 1–3 kHz. Eso es lo que puede sonar a zumbido y no a animal, y lo
que lo deja sin presencia en altavoces pequeños.

**Qué cambia en todos los candidatos.** Otra síntesis: los pulsos de la garganta se generan
uno a uno, cada uno con su periodo y su fuerza (jitter y shimmer), con subarmónicos que entran
y salen (un pulso de cada dos, o de cada tres, más débil y retrasado); cada pulso excita un
grano amortiguado por formante, y el tracto —largo, de felino grande— se mueve de pulso en
pulso (la boca se abre y se cierra, y lengua y mandíbula no se quedan quietas); el aire es
ruido que sale a ráfagas con cada pulso y pasa por los mismos formantes. El corte de agudos
sube de 4–4.5 kHz a 6 kHz.

| Candidato | Qué es |
| --- | --- |
| **A «glotal»** | Rugido vocal. Altura 78 → 128 → 60 Hz, la boca se abre y se cierra, poca irregularidad (jitter del 3 %), aire moderado y tres golpes de garganta al cerrar. El más parecido en carácter al actual, con voz |
| **B «rugoso»** | Fiera ronca. Arranca en pulsos sueltos de garganta (30 Hz), sube a 96 Hz y se hunde hasta 24 Hz; jitter del 9 %, subarmónicos fuertes e irregulares, mucho aire turbulento y boca «enseñando los dientes» (más 1.5–3 kHz) |
| **C «bufido»** | Solo para el rugido. Casi todo aire: un soplo que aletea de forma irregular (28–40 veces por segundo) por la boca abierta, sobre un fondo de pulsos graves, y cinco golpes de garganta al cerrar |

En `balam_especial` solo cambia el rugido corto del principio: la onda de choque (a los
0.38 s) se ha vuelto a generar con la misma receta que la actual.

| Archivo | s | Pico (dBFS) | RMS | RMS 50 ms | LUFS-M | íd. > 200 Hz | Máximo en (s) | A −20 dB (s) | < 150 Hz (%) | 150–600 Hz (%) | 600–1000 Hz (%) | 1000–3000 Hz (%) | > 3000 Hz (%) | Tramas periódicas (%) | Bytes |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| `balam_rugido__actual.mp3` | 1.00 | −5.0 | −17.2 | −12.9 | −15.5 | −16.2 | 0.32 | 0.84 | 13 | 72 | 11 | 4 | 0 | 80 | 9358 |
| `balam_rugido__A_glotal.mp3` | 1.00 | −4.9 | −17.5 | −13.8 | −15.5 | −16.3 | 0.34 | 0.83 | 19 | 54 | 12 | 15 | 0 | 59 | 9621 |
| `balam_rugido__B_rugoso.mp3` | 1.00 | −3.4 | −17.7 | −13.1 | −15.5 | −16.1 | 0.52 | 0.82 | 18 | 49 | 7 | 25 | 1 | 20 | 10794 |
| `balam_rugido__C_bufido.mp3` | 1.00 | −4.8 | −18.3 | −13.9 | −15.5 | −15.7 | 0.34 | 0.75 | 6 | 51 | 6 | 36 | 2 | 0 | 9250 |

| Archivo | s | Pico (dBFS) | RMS | RMS 50 ms | LUFS-M | íd. > 200 Hz | Máximo en (s) | A −20 dB (s) | < 150 Hz (%) | 150–600 Hz (%) | 600–1000 Hz (%) | 1000–3000 Hz (%) | > 3000 Hz (%) | Tramas periódicas (%) | Bytes |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| `balam_grunido__actual.mp3` | 0.45 | −5.0 | −17.4 | −12.8 | −18.1 | −19.6 | 0.13 | 0.38 | 23 | 71 | 5 | 2 | 0 | 56 | 4168 |
| `balam_grunido__A_glotal.mp3` | 0.45 | −4.5 | −17.8 | −12.9 | −18.1 | −19.0 | 0.10 | 0.35 | 16 | 72 | 8 | 4 | 0 | 39 | 4403 |
| `balam_grunido__B_rugoso.mp3` | 0.45 | −1.6 | −17.8 | −12.6 | −18.1 | −19.1 | 0.02 | 0.29 | 20 | 63 | 8 | 8 | 0 | 22 | 4744 |

| Archivo | s | Pico (dBFS) | RMS | RMS 50 ms | LUFS-M | íd. > 200 Hz | Máximo en (s) | A −20 dB (s) | < 150 Hz (%) | 150–600 Hz (%) | 600–1000 Hz (%) | 1000–3000 Hz (%) | > 3000 Hz (%) | Tramas periódicas (%) | Bytes |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| `balam_especial__actual.mp3` | 0.90 | −4.1 | −15.9 | −10.7 | −14.2 | −15.5 | 0.40 | 0.74 | 31 | 50 | 9 | 9 | 1 | 36 | 7761 |
| `balam_especial__A_glotal.mp3` | 0.90 | −4.1 | −16.0 | −10.5 | −14.2 | −15.4 | 0.40 | 0.73 | 31 | 42 | 11 | 15 | 1 | 18 | 7788 |
| `balam_especial__B_rugoso.mp3` | 0.90 | −2.0 | −16.6 | −10.7 | −14.2 | −15.3 | 0.39 | 0.70 | 31 | 38 | 8 | 21 | 2 | 3 | 8207 |

**Lo que dicen las medidas.** Los tres rugidos suenan igual de fuerte que el actual (−15.5
LUFS-M). El cuerpo de 150–600 Hz sigue siendo la banda principal (49–54 %) y la presencia de
1–3 kHz pasa del 4 % al 15 % (A), 25 % (B) y 36 % (C). La regularidad baja del 80 % de tramas
periódicas al 59 % (A), 20 % (B) y 0 % (C). En el espectrograma, el actual es una mancha fija
en torno a 300 Hz; en A se ve el primer formante subir y bajar con la boca y la altura
dibujar un arco; en B y C se ven los pulsos sueltos del arranque y del cierre.

**Recomendación por medición: B «rugoso»** para los tres sonidos. Es el que más se aleja de lo
que se anotó como problema (20 % de tramas periódicas frente a 80 %) sin perder el cuerpo
(49 %) y con seis veces más presencia. **A** es la opción prudente si B resulta demasiado
sucio: conserva más cuerpo (54 %) y sigue siendo bastante regular. **C** no es un rugido sino
un bufido: puede servir para otro momento (un aviso, un golpe recibido), no para sustituirlo.
Pegas medidas de B: su gruñido corto tiene el pico a −1.6 dBFS (los pulsos sueltos del final
tienen mucha cresta) y hubo que domarlo con el limitador.

---

## 2. Voz de Chiich Yaxché (plano 4 de «El llamado»)

**Problema.** La «voz de árbol» actual son pulsos de crujido (30–56 por segundo) que excitan
dos resonancias de madera, con la curva de volumen de una frase. No tiene altura de voz ni
vocales: en el espectrograma es una banda fija en torno a 580 Hz que se enciende y se apaga.
Por eso puede sonar a puerta que chirría.

**Qué cambia en todos los candidatos.** Una voz anciana sugerida, sin palabras: pulsos
glotales a altura de voz, con el temblor irregular de unos 5 Hz y la ronquera de una voz
vieja; formantes de vocales abiertas (a, o, e) que se mueven de sílaba en sílaba, con un
murmullo nasal entre las sílabas ligadas; aire por el mismo tracto; y la **misma entonación y
los mismos tiempos** que la actual: una llamada de cinco sílabas que acaba hacia arriba
(14.80–16.50 s) y un refunfuño de siete sílabas que cae y acaba con la voz rota
(16.90–18.56 s). Alrededor, el aire del tronco hueco y dos crujidos de tronco en los mismos
sitios que hoy, más graves y apagados.

| Candidato | Qué es |
| --- | --- |
| **A «murmullo»** | Voz de anciana que tararea con la boca entreabierta (base de 172 Hz; la frase se mueve entre unos 110 y 270 Hz). Poca madera: algo de resonancia de tronco y crujidos discretos |
| **B «tronco»** | Voz más grave (124 Hz) que suena dentro del árbol: cada pulso de la voz golpea además tres modos de madera hueca (208, 395 y 760 Hz), la cavidad del tronco resuena más y los crujidos van más altos. Es la que más conserva la idea original de «voz de madera» |
| **C «susurro»** | Voz de aire: un susurro con las mismas vocales y la misma frase, con un hilo de voz (150 Hz) por debajo |

Archivos: `chiich_voz__*.mp3` es **la frase suelta** (5 s, con su sala; todas con la misma
ganancia, la que deja la actual en −20 LUFS) y `cine_llamado_fx__*.mp3` es **la pista de
efectos completa** de la cinemática (20.5 s, −18 LUFS) con cada voz en su sitio. La voz
actual suelta se ha obtenido restando a la pista actual la misma pista generada sin voz
(`gen_cine.fx_llamado()` importado sin tocarlo); el resto de la pista es idéntico en todos los
candidatos antes del acabado. Para oírla con la música hay que reproducir a la vez
`game/web/static/audio/cine_llamado_mus.mp3`.

| Archivo | s | Pico (dBFS) | RMS | LUFS | LUFS-M máx | íd. > 200 Hz | < 150 Hz (%) | 150–400 Hz (%) | 400–1000 Hz (%) | 1000–3000 Hz (%) | > 3000 Hz (%) | Centro (Hz) | Bytes |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| `chiich_voz__actual.mp3` | 5.00 | −1.7 | −23.4 | −20.0 | −15.3 | −15.3 | 2 | 51 | 36 | 10 | 0 | 541 | 69577 |
| `chiich_voz__A_murmullo.mp3` | 5.00 | −5.6 | −23.3 | −20.0 | −14.6 | −14.7 | 1 | 23 | 69 | 8 | 0 | 568 | 64391 |
| `chiich_voz__B_tronco.mp3` | 5.00 | −6.5 | −23.2 | −20.0 | −16.1 | −16.4 | 4 | 35 | 56 | 5 | 0 | 519 | 66196 |
| `chiich_voz__C_susurro.mp3` | 5.00 | −3.6 | −23.6 | −20.0 | −14.8 | −14.9 | 0 | 15 | 68 | 16 | 0 | 751 | 67493 |

| Archivo | s | Pico (dBFS) | RMS | LUFS | LUFS-M máx | íd. > 200 Hz | < 150 Hz (%) | 150–400 Hz (%) | 400–1000 Hz (%) | 1000–3000 Hz (%) | > 3000 Hz (%) | Centro (Hz) | Bytes |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| `cine_llamado_fx__actual.mp3` | 20.50 | −3.5 | −20.3 | −18.0 | −13.7 | −13.8 | 30 | 30 | 32 | 7 | 1 | 478 | 289470 |
| `cine_llamado_fx__A_murmullo.mp3` | 20.50 | −3.3 | −20.3 | −18.0 | −12.1 | −12.3 | 28 | 25 | 39 | 7 | 1 | 488 | 346999 |
| `cine_llamado_fx__B_tronco.mp3` | 20.50 | −3.8 | −20.3 | −18.0 | −13.4 | −13.7 | 29 | 28 | 37 | 6 | 1 | 476 | 346818 |
| `cine_llamado_fx__C_susurro.mp3` | 20.50 | −3.6 | −20.3 | −18.0 | −13.3 | −13.4 | 29 | 24 | 38 | 8 | 1 | 505 | 348021 |

Los cuatro hitos de tiempo que `gen_cine.py --check` exige a esta pista se cumplen en los
tres candidatos (el zumbido del sello sigue siendo del plano 3, la voz está en el plano 4, las
gotas en el 2 y el toc-toc de madera en 18.3–18.7 s). Márgenes: el sello queda sobre el plano
4 en +8.1 dB (actual), +6.5 (A), +6.3 (B) y +8.9 (C), con mínimo +6; la voz queda sobre el
plano 3 en +8.2, +9.0, +9.0 y +8.4 dB.

**Lo que dicen las medidas.** Con la misma sonoridad integrada, la energía pasa de 150–400 Hz
(51 % en la actual) a 400–1000 Hz (56–69 %), que es donde viven los primeros formantes de las
vocales abiertas. En el espectrograma del plano 4, A y B enseñan pilas de armónicos que suben
y bajan con la frase (la llamada sube; el refunfuño cae); la actual, dos bandas horizontales
quietas; C, manchas de vocal sin armónicos.

**Recomendación por medición: A «murmullo».** Es la que tiene con más claridad lo que le
falta a la actual —altura de voz que dibuja la frase y vocales— y deja holgura en los hitos.
**B** es la alternativa si A suena demasiado a persona y poco a árbol; su pega medida es que
mete energía de voz en 60–250 Hz, la banda del sello, y pasa ese hito por 0.3 dB. **C** es la
más segura contra el «sonido de sintetizador» (es ruido filtrado), pero la entonación apenas
la lleva el hilo de voz. Aviso para A: su sílaba acentuada es ahora el momento más fuerte de
toda la pista (−12.1 LUFS-M frente a −13.7); si sobresale, se baja la voz 1.5 dB dentro de la pista.

---

## 3. Aves ambientales (`amb_aves`)

**Problema.** El bucle actual tiene doce cantos de diez tipos (los píos y la carraca salen dos
veces cada uno), hechos con barridos de seno limpio y envolvente de campana. De cerca pueden
sonar a sintetizador y las figuras repetidas se acaban reconociendo.

**Qué cambia en todos los candidatos.**

- **La nota.** La altura ya no es un barrido limpio: lleva un bamboleo aleatorio y, donde hay
  vibrato, su ritmo y su hondura derivan. Tiene segundo y tercer armónico que cambian a lo
  largo de la nota, soplo alrededor del tono, un «chif» de ruido en el ataque, una envolvente
  asimétrica con aleteo y una resonancia de pico que hace variar el volumen según por dónde
  pasa la altura.
- **El repertorio.** Dieciocho «especies» inventadas (caída, dos notas, trino, gorjeo,
  arrullo, eco, ululo, píos, carraca, flauteo, silbo que sube, zumbón, chasquidos, silbo
  largo, burbujeo, graznido, tamborileo de pico en un tronco, pregunta). En cada bucle cada
  una sale **como mucho una vez**, con su tono, ritmo e intervalos al azar: no hay ninguna
  figura repetida dentro del bucle.
- **La distancia.** Cuanto más lejos, menos agudos, menos sonido directo y más sala; el
  follaje deja cuatro copias tardías, apagadas y repartidas alrededor de cada canto.
- El reparto es circular (el último hueco da la vuelta al bucle) y dos cantos seguidos no
  salen del mismo lado.

| Candidato | Cantos | Qué es |
| --- | --- | --- |
| **A «lejanas»** | 9, uno cada 3 s más o menos | Todas lejos (filtro de agudos entre 1.8 y 3.6 kHz), sala de 2.1 s. Sin las dos especies más ásperas. Cantan: caída, dos notas, burbujeo, píos, silbo que sube, tamborileo, zumbón, pregunta, ululo |
| **B «timbre»** | 11, uno cada 2.5 s | A media distancia, como hoy, con todo el detalle de la nota nueva: es la prueba de si el timbre basta. Cantan: silbo que sube, eco, trino, gorjeo, graznido, arrullo, zumbón, carraca, pregunta, caída, chasquidos |
| **C «bandada»** | 5, uno cada 5.5 s | Un coro lejano de cientos de píos en oleadas (en el actual existe, pero casi no se oye) y solo cinco solistas, lejos y a media voz: silbo largo, píos, trino, ululo, pregunta |

Mismo bucle que el actual (27.43 s, 1050 cuadros MP3, medio segundo repetido a cada lado, −28
LUFS, pico por debajo de −6 dBFS). `amb_aves_en_selva__*.mp3` son **30 s de cada bucle sobre
`amb_selva`** con los niveles relativos del juego fuera de combate (selva 0.75, aves 0.5); las
cuatro mezclas van subidas 9 dB por igual para oírlas sin tocar el volumen.

| Archivo | s | Pico (dBFS) | RMS | LUFS | LUFS-M máx | íd. > 200 Hz | < 200 Hz (%) | 200–1000 Hz (%) | 1000–4000 Hz (%) | 4000–8000 Hz (%) | > 8000 Hz (%) | Costura | I·D | Bytes |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| `amb_aves__actual.mp3` | 28.43 | −12.9 | −36.1 | −28.4 | −21.2 | −21.2 | 0 | 11 | 87 | 2 | 0 | (juego) |  | 163601 |
| `amb_aves__A_lejanas.mp3` | 28.43 | −11.9 | −36.2 | −28.5 | −21.9 | −21.9 | 0 | 4 | 95 | 0 | 0 | 1.0000 | 0.31 | 281075 |
| `amb_aves__B_timbre.mp3` | 28.43 | −12.6 | −36.1 | −28.3 | −21.4 | −21.4 | 0 | 18 | 82 | 1 | 0 | 0.9987 | 0.32 | 292293 |
| `amb_aves__C_bandada.mp3` | 28.43 | −11.2 | −34.3 | −28.3 | −19.6 | −19.6 | 0 | 0 | 96 | 4 | 0 | 0.9992 | 0.19 | 316547 |

| Archivo | s | Pico (dBFS) | RMS | LUFS | LUFS-M máx | íd. > 200 Hz | < 200 Hz (%) | 200–1000 Hz (%) | 1000–4000 Hz (%) | 4000–8000 Hz (%) | > 8000 Hz (%) | Centro (Hz) | Bytes |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| `amb_aves_en_selva__actual.mp3` | 30.00 | −6.8 | −24.0 | −21.0 | −16.9 | −17.7 | 26 | 51 | 19 | 4 | 0 | 864 | 455834 |
| `amb_aves_en_selva__A_lejanas.mp3` | 30.00 | −4.2 | −23.9 | −20.9 | −14.7 | −15.2 | 26 | 49 | 21 | 4 | 0 | 872 | 456507 |
| `amb_aves_en_selva__B_timbre.mp3` | 30.00 | −6.9 | −23.9 | −20.9 | −16.3 | −16.4 | 26 | 51 | 19 | 4 | 0 | 890 | 458883 |
| `amb_aves_en_selva__C_bandada.mp3` | 30.00 | −5.4 | −23.5 | −20.3 | −15.2 | −15.5 | 23 | 45 | 28 | 4 | 0 | 1024 | 467626 |

**Lo que dicen las medidas.** Los tres cumplen la convención de bucle (costura 0.9987 o más) y
el nivel. A es el que menos sobresale (momento más fuerte a −21.9 LUFS-M frente a −21.2 del
actual, y 0 % de energía por encima de 4 kHz); B queda como el actual en nivel y reparto; C
suena de forma más continua (RMS 1.8 dB más alto con la misma sonoridad integrada, momento
más fuerte 1.6 dB por encima) y es el más abierto en estéreo (0.19). En la mezcla de 30 s con
la selva, el momento más fuerte de A queda 2.2 dB por encima del de la mezcla actual (−14.7
frente a −16.9 LUFS-M) aunque su bucle suelto es más flojo: lo más probable es que un canto
coincida ahí con una racha de la selva, cosa que en el juego cambia a cada vuelta porque los
dos bucles duran distinto. Conviene escuchar ese punto.

**Recomendación por medición: A «lejanas».** Ataca los dos problemas anotados a la vez
—ninguna especie repetida y distancia— y es el candidato que menos cambia el papel de la capa
en la mezcla. **B** solo conviene si de oído la nota nueva ya no delata el sintetizador de
cerca. **C** cambia el carácter (de sucesos sueltos a un lecho): si gusta, hay que bajar la
capa (ver mezcla). Límite que no se puede medir: un bucle de 27 s se repite igual; sin
figuras repetidas dentro tarda más en aprenderse, pero se aprende.

---

## 4. Graves en cenotes y ruinas (`amb_cenote`, `amb_ruinas`)

**Problema.** En los dos bucles el 73 % de la energía está por debajo de 200 Hz. En un
portátil o un móvil apenas se oyen (al quitar lo de debajo de 200 Hz, el cenote pierde casi
6 dB de su momento más fuerte) y, junto a la selva y el viento, emborronan los graves.

| Candidato | Qué es |
| --- | --- |
| **A «armónicos»** | El mismo diseño y las mismas notas. **Cenote:** las resonancias de Re y La (73, 110, 147 y 196 Hz) suenan sobre todo por sus armónicos 2.º a 4.º; el aire sube de 70–380 a 130–900 Hz; el agua, de 160–520 a 250–950 Hz; cada gota lleva debajo el «plop» de la cavidad (330–620 Hz); pasa-altos de 60 Hz. **Ruinas:** las cinco resonancias con el peso desplazado de 92–138 a 207–466 Hz y dos más arriba (622 y 932 Hz); aire de 110–700 Hz; casi el doble de soplo medio; las piedrecillas llevan el «toc» de la losa (480–860 Hz) y hay un roce de arenilla por bucle; pasa-altos de 55 Hz |
| **B «espacio»** | Casi sin zumbido grave: el espacio lo cuentan los sucesos y su sala. **Cenote:** aire en la boca del pozo (una banda ancha de 250–1400 Hz que se desplaza despacio, sin silbar), agua que lame y once gorgoteos contra la pared, unas veinte gotas con «plop» y sala de 4.2 s; pasa-altos de 90 Hz. **Ruinas:** soplos anchos por tres huecos (330, 520 y 780 Hz) con sala de 2.2 s, tres piedrecillas distintas (una que rebota, un toque suelto y un reguero) y un asiento de bloque lejano; pasa-altos de 80 Hz |

Mismos bucles que los actuales (32.00 s y 28.21 s) y misma convención.

| Archivo | s | Pico (dBFS) | RMS | LUFS | LUFS-M máx | íd. > 200 Hz | < 200 Hz (%) | 200–1200 Hz (%) | > 1200 Hz (%) | Costura | I·D | Bytes |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| `amb_cenote__actual.mp3` | 33.00 | −11.4 | −29.4 | −28.1 | −23.5 | −29.3 | 73 | 26 | 0 | (juego) |  | 290891 |
| `amb_cenote__A_armonicos.mp3` | 33.00 | −14.9 | −30.3 | −28.0 | −25.2 | −25.8 | 21 | 76 | 3 | 1.0000 | 0.69 | 428246 |
| `amb_cenote__B_espacio.mp3` | 33.00 | −12.9 | −30.4 | −28.0 | −23.5 | −23.8 | 4 | 89 | 7 | 1.0000 | 0.33 | 457951 |

| Archivo | s | Pico (dBFS) | RMS | LUFS | LUFS-M máx | íd. > 200 Hz | < 200 Hz (%) | 200–1200 Hz (%) | > 1200 Hz (%) | Costura | I·D | Bytes |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| `amb_ruinas__actual.mp3` | 29.21 | −14.9 | −29.5 | −28.1 | −23.6 | −26.3 | 73 | 27 | 0 | (juego) |  | 246576 |
| `amb_ruinas__A_armonicos.mp3` | 29.21 | −15.3 | −30.2 | −28.1 | −24.1 | −24.6 | 25 | 73 | 2 | 1.0000 | 0.85 | 361127 |
| `amb_ruinas__B_espacio.mp3` | 29.21 | −10.5 | −30.6 | −28.1 | −21.6 | −21.7 | 3 | 92 | 4 | 1.0000 | 0.48 | 368505 |

**Energía por bandas (lo pedido), en %:**

| Archivo | < 200 Hz | 200–1200 Hz | > 1200 Hz |
| --- | --- | --- | --- |
| `amb_cenote__actual.mp3` | 73.1 | 26.4 | 0.5 |
| `amb_cenote__A_armonicos.mp3` | 20.9 | 76.3 | 2.8 |
| `amb_cenote__B_espacio.mp3` | 4.0 | 89.3 | 6.7 |
| `amb_ruinas__actual.mp3` | 73.0 | 26.7 | 0.3 |
| `amb_ruinas__A_armonicos.mp3` | 25.4 | 73.1 | 1.5 |
| `amb_ruinas__B_espacio.mp3` | 3.4 | 92.2 | 4.4 |

**Lo que dicen las medidas.** A deja entre un quinto y un cuarto de la energía por debajo de
200 Hz y lleva tres cuartos a 200–1200 Hz; B la lleva casi toda. Con la misma sonoridad (−28
LUFS), lo que queda en un altavoz pequeño sube 3.5 dB (cenote A), 5.5 dB (cenote B), 1.7 dB
(ruinas A) y 4.6 dB (ruinas B) en el momento más fuerte. La apertura estéreo de A es la del
actual (0.69 y 0.85 frente a 0.65 y 0.80 del juego); B es más abierto (0.33 y 0.48). Las
costuras miden 1.0000.

**Recomendación por medición: A «armónicos»** en los dos. Cumple lo pedido (el peso pasa a
200–1200 Hz y se recorta el subgrave) conservando el carácter, las notas y la apertura del
actual, y sin añadir sucesos nuevos que delaten el bucle. **B** es la opción si en altavoces
pequeños A sigue quedando corto; a cambio, sus sucesos sobresalen más (en ruinas B el momento
más fuerte está 2 dB por encima del actual) y añade figuras reconocibles (gorgoteos, reguero,
asiento) una vez por bucle. Al mover el peso a los medios, estas capas pasan a compartir banda
con la selva, el viento y el agua: ver la propuesta de volumen en la mezcla.

---

## 5. Golpes y movimientos de Nojoch Tuunich

**Problema.** Los efectos actuales ponen el peso en un barrido de seno que baja a 30–45 Hz y
en ruido de 45–300 Hz: la pisada tiene el 56 % de su energía por debajo de 100 Hz; la losa,
el 41 %; la caída, el 51 %. En un altavoz pequeño ese peso desaparece (la pisada pierde 4 dB
de sonoridad al quitar lo de debajo de 200 Hz) y lo que queda —el golpe de ruido medio— es
parecido en la pisada y en la losa.

**Qué cambia en todos los candidatos.** El peso se cuenta con tres capas que sí se oyen en
cualquier altavoz: **ataque** de roca (chasquido de 1–4.5 kHz: una ráfaga de pocos
milisegundos y tres modos cortos de piedra), **cuerpo** en 100–300 Hz (tres modos amortiguados
y un golpe de ruido en la misma banda, en vez del barrido hacia el subgrave) y **cola** de
escombro y polvo. Y cada movimiento tiene su perfil:

| Sonido | Perfil |
| --- | --- |
| `jefe_paso` | Un solo golpe compacto y apagado: cuerpo de 125–265 Hz, «toc» medio, chasquido corto y cinco piedras. Corto (0.14 s a menos de 20 dB del máximo) |
| `jefe_losa` | Chasquido brillante, una placa de piedra que resuena (310, 455, 690 y 1040 Hz), rebote a 0.11 s y cola larga de escombros (hasta 1.0 s) |
| `jefe_barrido` | **Sin golpe**: un arco de roce de piedra a tirones cuya banda sube y baja (300 → 1100 → 300 Hz), con aire y masa de 110–300 Hz. El máximo llega a los 0.26 s, no al principio |
| `jefe_embestida` | Zancadas con chasquido que se aceleran (de 4 a 11 por segundo) sobre un arrastre que sube de 250 a 1100 Hz. Acaba en su punto más fuerte (máximo a 1.16 s de 1.4) para enlazar con el choque |
| `jefe_choque` | Golpe, la columna que se parte en tres chasquidos seguidos, cuatro trozos que caen y escombros |
| `jefe_cae` | Dos golpes de rodilla (0 y 0.24 s) con chasquido, quejido de roca una octava por encima del actual (168 → 92 Hz, para que se oiga) y escombros |
| `jefe_despierta` | Grietas que se agolpan, rugido de roca una octava por encima del actual (112–184 Hz) y el bloque que encaja, con cuerpo medio |

| Candidato | Qué es |
| --- | --- |
| **A «seco»** | Más seco y legible: sin sala (salvo un mínimo en `jefe_despierta`), sin subgrave, colas cortas, más chasquido. Misma duración que el actual |
| **B «grande»** | Más grande y con cola: cuerpo más largo, algo de subgrave debajo, más cascotes y sala (0.6 a 1.3 s). Dura más que el actual: paso 0.65 s, losa 1.6 s, barrido 1.25 s, choque 1.8 s, cae 1.9 s, despierta 3.9 s (la embestida no cambia: tiene que acabar en seco) |

| Archivo | s | Pico (dBFS) | RMS | RMS 50 ms | LUFS-M | íd. > 200 Hz | Máximo en (s) | A −20 dB (s) | < 100 Hz (%) | 100–300 Hz (%) | 300–1000 Hz (%) | 1000–4000 Hz (%) | > 4000 Hz (%) | Centro (Hz) | Bytes |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| `jefe_paso__actual.mp3` | 0.50 | −8.0 | −24.0 | −15.6 | −24.7 | −28.7 | 0.02 | 0.20 | 56 | 26 | 12 | 5 | 0 | 250 | 3699 |
| `jefe_paso__A_seco.mp3` | 0.50 | −8.3 | −24.8 | −15.7 | −24.7 | −27.3 | 0.01 | 0.14 | 6 | 64 | 22 | 8 | 0 | 384 | 4118 |
| `jefe_paso__B_grande.mp3` | 0.65 | −8.7 | −25.8 | −16.7 | −24.7 | −27.3 | 0.00 | 0.24 | 4 | 70 | 21 | 6 | 0 | 329 | 4609 |

| Archivo | s | Pico (dBFS) | RMS | RMS 50 ms | LUFS-M | íd. > 200 Hz | Máximo en (s) | A −20 dB (s) | < 100 Hz (%) | 100–300 Hz (%) | 300–1000 Hz (%) | 1000–4000 Hz (%) | > 4000 Hz (%) | Centro (Hz) | Bytes |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| `jefe_losa__actual.mp3` | 1.20 | −2.9 | −17.7 | −8.9 | −14.8 | −18.2 | 0.01 | 0.65 | 41 | 34 | 12 | 11 | 2 | 492 | 11021 |
| `jefe_losa__A_seco.mp3` | 1.20 | −2.5 | −18.8 | −8.5 | −14.8 | −16.6 | 0.01 | 0.51 | 7 | 48 | 30 | 12 | 2 | 609 | 11835 |
| `jefe_losa__B_grande.mp3` | 1.60 | −6.4 | −19.5 | −11.2 | −14.8 | −16.9 | 0.06 | 0.80 | 9 | 50 | 31 | 9 | 1 | 476 | 14066 |

| Archivo | s | Pico (dBFS) | RMS | RMS 50 ms | LUFS-M | íd. > 200 Hz | Máximo en (s) | A −20 dB (s) | < 100 Hz (%) | 100–300 Hz (%) | 300–1000 Hz (%) | 1000–4000 Hz (%) | > 4000 Hz (%) | Centro (Hz) | Bytes |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| `jefe_barrido__actual.mp3` | 0.90 | −6.0 | −19.9 | −15.4 | −17.7 | −18.4 | 0.30 | 0.75 | 8 | 22 | 59 | 11 | 0 | 579 | 9826 |
| `jefe_barrido__A_seco.mp3` | 0.90 | −5.5 | −20.1 | −14.6 | −17.7 | −18.7 | 0.26 | 0.67 | 7 | 29 | 38 | 25 | 0 | 683 | 7343 |
| `jefe_barrido__B_grande.mp3` | 1.25 | −6.0 | −20.3 | −15.2 | −17.7 | −18.7 | 0.38 | 0.98 | 12 | 28 | 35 | 25 | 0 | 637 | 9915 |

| Archivo | s | Pico (dBFS) | RMS | RMS 50 ms | LUFS-M | íd. > 200 Hz | Máximo en (s) | A −20 dB (s) | < 100 Hz (%) | 100–300 Hz (%) | 300–1000 Hz (%) | 1000–4000 Hz (%) | > 4000 Hz (%) | Centro (Hz) | Bytes |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| `jefe_embestida__actual.mp3` | 1.40 | −5.0 | −22.6 | −17.1 | −21.1 | −22.3 | 1.06 | 1.11 | 25 | 23 | 46 | 6 | 0 | 400 | 11009 |
| `jefe_embestida__A_seco.mp3` | 1.40 | −6.3 | −23.4 | −16.9 | −21.1 | −22.4 | 1.16 | 1.12 | 7 | 35 | 46 | 12 | 0 | 510 | 13469 |
| `jefe_embestida__B_grande.mp3` | 1.40 | −5.0 | −23.3 | −17.3 | −21.1 | −23.1 | 1.32 | 1.24 | 18 | 39 | 37 | 6 | 0 | 382 | 12266 |

| Archivo | s | Pico (dBFS) | RMS | RMS 50 ms | LUFS-M | íd. > 200 Hz | Máximo en (s) | A −20 dB (s) | < 100 Hz (%) | 100–300 Hz (%) | 300–1000 Hz (%) | 1000–4000 Hz (%) | > 4000 Hz (%) | Centro (Hz) | Bytes |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| `jefe_choque__actual.mp3` | 1.30 | −2.8 | −19.0 | −10.2 | −14.9 | −16.9 | 0.00 | 0.75 | 14 | 46 | 14 | 20 | 5 | 853 | 13030 |
| `jefe_choque__A_seco.mp3` | 1.30 | −2.7 | −18.9 | −9.2 | −14.8 | −16.5 | 0.01 | 0.65 | 4 | 55 | 20 | 16 | 4 | 771 | 12119 |
| `jefe_choque__B_grande.mp3` | 1.80 | −5.2 | −19.9 | −10.6 | −14.8 | −16.6 | 0.01 | 1.02 | 14 | 52 | 17 | 13 | 4 | 673 | 15785 |

| Archivo | s | Pico (dBFS) | RMS | RMS 50 ms | LUFS-M | íd. > 200 Hz | Máximo en (s) | A −20 dB (s) | < 100 Hz (%) | 100–300 Hz (%) | 300–1000 Hz (%) | 1000–4000 Hz (%) | > 4000 Hz (%) | Centro (Hz) | Bytes |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| `jefe_cae__actual.mp3` | 1.40 | −2.7 | −15.9 | −8.9 | −13.3 | −17.2 | 0.29 | 0.94 | 51 | 31 | 11 | 6 | 1 | 320 | 12713 |
| `jefe_cae__A_seco.mp3` | 1.40 | −3.1 | −16.9 | −8.9 | −13.3 | −15.3 | 0.25 | 0.93 | 9 | 61 | 21 | 7 | 1 | 443 | 13083 |
| `jefe_cae__B_grande.mp3` | 1.90 | −5.6 | −17.6 | −10.0 | −13.3 | −15.7 | 0.03 | 1.07 | 10 | 63 | 21 | 6 | 1 | 368 | 16616 |

| Archivo | s | Pico (dBFS) | RMS | LUFS | LUFS-M máx | íd. > 200 Hz | < 100 Hz (%) | 100–300 Hz (%) | 300–1000 Hz (%) | 1000–4000 Hz (%) | > 4000 Hz (%) | Centro (Hz) | Bytes |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| `jefe_despierta__actual.mp3` | 3.50 | −3.0 | −22.5 | −22.7 | −19.0 | −22.3 | 14 | 56 | 19 | 9 | 2 | 490 | 30942 |
| `jefe_despierta__A_seco.mp3` | 3.50 | −6.1 | −22.4 | −22.4 | −19.0 | −20.1 | 8 | 50 | 29 | 11 | 2 | 593 | 32748 |
| `jefe_despierta__B_grande.mp3` | 3.90 | −7.6 | −23.5 | −23.2 | −19.0 | −20.0 | 11 | 48 | 30 | 9 | 2 | 537 | 32004 |

**Lo que dicen las medidas.** Con la misma sonoridad que el actual, la energía por debajo de
100 Hz baja del 56 % al 6 % en la pisada, del 41 % al 7 % en la losa y del 51 % al 9 % en la
caída (A), y lo que queda en un altavoz pequeño sube 1.4 dB (paso), 1.6 dB (losa), 1.9 dB
(cae) y 2.2 dB (despierta). ¿Se distinguen entre sí los cuatro movimientos? En los candidatos
A, por números: la pisada dura 0.14 s y tiene el 8 % en 1–4 kHz; la losa dura 0.51 s, con el
30 % en 300–1000 Hz (la placa) y el 12 % en 1–4 kHz; el barrido no tiene ataque (máximo a
0.26 s) y es el más brillante (25 % en 1–4 kHz); la embestida es la única que crece (máximo a
1.16 s). En el espectrograma se ven las zancadas sueltas de la embestida, las líneas de la
placa en la losa y el arco sin golpe del barrido. Pega de B: los picos bajan 3–4 dB a igual
sonoridad (la losa pasa de −2.5 a −6.4 dBFS), que es justo lo que conviene al limitador del
juego (ver mezcla), pero en la embestida B vuelve a meter graves (18 % por debajo de 100 Hz).

**Recomendación por medición:**

- `jefe_paso`, `jefe_barrido` y `jefe_embestida`: **A «seco»**. Se repiten o avisan: tienen
  que leerse rápido, y la cola de B se pisaría con el paso siguiente.
- `jefe_losa`, `jefe_choque`, `jefe_cae` y `jefe_despierta`: **B «grande»**. Son los golpes
  raros y grandes; B conserva el reparto por bandas de A, añade la cola y, con picos 3–4 dB
  más bajos a igual sonoridad, entra en el limitador del juego sin que este aplaste el golpe.
- Duda abierta: el cuerpo de los golpes son modos de 100–300 Hz; se acortaron para que no
  suenen a tambor afinado, pero solo el oído dirá si suenan a piedra. Y en `jefe_despierta` el
  rugido de roca, al subir una octava, se ve en el espectrograma como una banda estrecha en
  200–300 Hz durante dos segundos: puede sonar más a zumbido que a roca.

---

## Mezcla: niveles actuales y propuesta

Cómo se ha calculado el nivel «a la salida»: sonoridad del archivo + ajuste con que lo lanza
el juego + volumen por defecto de los buses (efectos 0.9 × general 0.9 = −1.8 dB; ambiente
0.8 × 0.9 = −2.9 dB; música 0.7 × 0.9 = −4.0 dB), para el jugador que está junto a la fuente.
Referencias: la música de combate (`mus_jefe`, −18 LUFS) sale a unos **−22 LUFS**, y la del
claro (−20 LUFS), a −24. Sobre toda la salida hay un **limitador a −8 dBFS** (razón 16:1): lo
que pasa de ahí no suena más fuerte; solo aplasta el golpe y hace bombear el ambiente y la
música.

| Sonido | Pico (dBFS) | RMS | LUFS-M | íd. > 200 Hz | Ajuste en el juego (dB) | LUFS-M a la salida | Cuándo |
| --- | --- | --- | --- | --- | --- | --- | --- |
| `balam_rugido` | −5.0 | −17.2 | −15.5 | −16.2 | — | — | sin evento en el juego |
| `balam_grunido` | −5.0 | −17.4 | −18.1 | −19.6 | −3 | −22.9 | al transformarse (−9 los de otros jugadores) |
| `balam_especial` | −5.0 | −15.9 | −14.2 | −15.5 | −2 | −18.0 | zarpazo a plena carga (−8 los de otros) |
| `zarpazo` | −4.0 | −19.5 | −19.5 | −22.1 | +3 | −18.3 | suena a la vez que `balam_especial` (−5 los de otros) |
| `transformar` | −6.0 | −21.5 | −18.7 | −18.7 | 0 | −20.5 | suena a la vez que `balam_grunido` |
| `jefe_paso` | −8.0 | −24.0 | −24.7 | −28.7 | −2 | −28.5 | cada paso (+2 al cambiar de sitio, +3 al arrancar la embestida) |
| `jefe_aviso` | −6.9 | −22.9 | −20.9 | −21.6 | −1 | −23.7 | antes de la losa (−3 barrido, +1 embestida) |
| `jefe_losa` | −3.0 | −17.7 | −14.8 | −18.2 | 0 | −16.6 | golpe de losa; la música baja 5 dB |
| `jefe_barrido` | −6.0 | −19.9 | −17.7 | −18.4 | 0 | −19.5 | barrido y al soltarse las cadenas |
| `jefe_embestida` | −5.0 | −22.6 | −21.1 | −22.3 | 0 | −22.9 | anuncio de la embestida, con `jefe_aviso` a +1 |
| `jefe_choque` | −3.0 | −19.0 | −14.9 | −16.9 | +2 | −14.7 | choque; la música baja 8 dB |
| `jefe_aturdido` | −6.3 | −21.7 | −20.3 | −23.6 | 0 | −22.1 | a la vez que `jefe_choque` |
| `pilar_rompe` | −3.0 | −16.3 | −13.0 | −14.1 | 0 | −14.8 | a la vez que `jefe_choque` (−2 cuando cae una columna sola) |
| `jefe_cae` | −2.9 | −15.9 | −13.3 | −17.2 | 0 | −15.1 | liberación; la música baja 10 dB |
| `liberacion` | −2.9 | −18.8 | −13.1 | −13.2 | 0 | −14.9 | a la vez que `jefe_cae` (sin posición) |
| `jefe_despierta` | −2.9 | −22.5 | −19.0 | −22.3 | +2 | −18.8 | despertar; la música baja 7 dB |

| Capa de ambiente | Pico (dBFS) | LUFS | LUFS-M máx | íd. > 200 Hz | Volumen de la capa | LUFS a la salida | Cuándo |
| --- | --- | --- | --- | --- | --- | --- | --- |
| `amb_selva` | −13.3 | −28.1 | −23.4 | −24.2 | 0.75 (−2.5 dB) | −33.5 | base (×0.4 en las ruinas) |
| `amb_aves` | −12.9 | −28.4 | −21.2 | −21.2 | 0.50 (−6.0 dB) | −37.3 | 0.2 en combate; ×0.2 en las ruinas |
| `amb_insectos` | −11.6 | −28.1 | −22.5 | −22.5 | 0.30 (−10.5 dB) | −41.5 |  |
| `amb_viento` | −10.5 | −28.0 | −20.5 | −20.6 | 0.20 (−14.0 dB) | −44.9 | hasta 0.5 en la pirámide; +0.2 en combate |
| `amb_agua` | −13.9 | −28.2 | −26.3 | −26.4 | 0.60 (−4.4 dB) | −35.5 | junto al cenote |
| `amb_cenote` | −11.4 | −28.1 | −23.5 | −29.3 | 0.45 (−6.9 dB) | −37.9 | junto al cenote |
| `amb_ruinas` | −14.9 | −28.1 | −23.6 | −26.3 | 0.70 (−3.1 dB) | −34.1 | en el santuario (0.4 en la pirámide) |

### Propuesta de ajuste (dB sobre lo que hoy pone el juego)

| Sonido | Hoy | Propuesta | Por qué (qué tapa a qué) |
| --- | --- | --- | --- |
| `balam_rugido` | sin evento | 0 propio, −6 ajeno, cuando se conecte | **No lo lanza ningún script del juego** (solo suenan `balam_grunido` y `balam_especial`). A 0 dB saldría a −17.3 LUFS-M: unos 5 dB sobre la música de combate y algo menos de 1 dB por debajo de la losa |
| `balam_grunido` | −3 propio, −9 ajeno | **−1 y −7** (con el actual, 0 y −6) | Suena a la vez que `transformar` (0 dB; −20.5 a la salida, todo por encima de 200 Hz). El gruñido sale 2.4 dB por debajo y con el 94 % de su energía por debajo de 600 Hz: el acorde lo tapa. Con el candidato (más 1–3 kHz) bastan 2 dB |
| `balam_especial` | −2 propio, −8 ajeno | igual | Ya es el más fuerte de Balam (−18.0) |
| `zarpazo` cuando suena con `balam_especial` | +3 | **0** | Los dos salen igual de fuertes (−18.3 y −18.0) y a la vez; el pico del zarpazo llega solo a −2.8 dBFS y la suma entra de lleno en el limitador. El especial ya lleva su onda de choque |
| `jefe_paso` al andar | −2 | **+1** con el candidato (+3 con el actual) | Sale a −28.5 LUFS-M, 6.5 dB **por debajo** de la música de combate, y en un altavoz pequeño a −32.5: no se oye, y es lo que avisa de que el coloso se acerca. A +1 sigue 9 dB por debajo de la losa |
| `jefe_paso` al cambiar de sitio y al arrancar la embestida | +2 y +3 | +4 y +5 (misma subida) | Mantener la escala entre los tres usos |
| `jefe_aviso` | −1, −3, +1 | igual | — |
| `jefe_embestida` | 0 | **+3**, y bajar la música 3 dB durante 1.2 s | Sale a −22.9 LUFS-M: por debajo de la música (no hay atenuación en ese momento) y 1.2 dB por debajo de `jefe_aviso` (+1), que suena a la vez en la misma banda (300–2400 Hz). Es el anuncio del ataque más peligroso |
| `jefe_barrido` | 0 | igual | −19.5: 2.5 dB sobre la música y 3 por debajo de la losa |
| `jefe_losa` | 0 | **0 con B «grande»; −2 con el actual o con A** | El pico del actual llega a −4.8 dBFS a la salida, 3 dB por encima del umbral del limitador. B tiene la misma sonoridad con el pico en −8.2: no lo toca |
| `jefe_choque` | +2 | **0** | Ver la fila siguiente |
| `pilar_rompe` cuando suena con `jefe_choque` | 0 | **−6** (o quitarlo) | En el choque suenan tres efectos grandes a la vez: `jefe_choque` (+2), `pilar_rompe` (0) y `jefe_aturdido` (0). Los dos primeros salen igual de fuertes (−14.7 y −14.8 LUFS-M), con picos de −2.8 y −4.8 dBFS: la suma roza 0 dBFS y el limitador la baja unos 7 dB. Además `jefe_choque` ya lleva dentro la columna que se parte y cae |
| `jefe_aturdido` | 0 | igual | Queda 7 dB por debajo del choque |
| `jefe_cae` | 0 | **−3** | Suena a la vez que `liberacion` (−14.9 a la salida) y sale igual de fuerte (−15.1), con el pico de los dos en −4.7 dBFS. `liberacion` es lo que cuenta el momento (el zumbido que se resuelve en acorde); la caída es el acompañamiento |
| `jefe_despierta` | +2 | **+2 con B «grande»; 0 con el actual o con A** | El actual llega con el pico a −2.7 dBFS (son los chasquidos de las grietas). B tiene la misma sonoridad con el pico en −7.4 |
| `amb_aves` | 0.5 (0.2 en combate) | igual con A o B; **0.4 con C «bandada»** | C suena de forma continua (RMS 1.8 dB más alto) y tiene un 4 % de energía en 4–8 kHz, la banda de `amb_insectos` (0.3) |
| `amb_cenote` | 0.45 | igual con A; **0.35 con B «espacio»** | B lleva el 89 % de la energía a 200–1200 Hz, donde está `amb_agua` (0.6, que suena en el mismo sitio), y en altavoz pequeño ya sube 5.5 dB por sí solo |
| `amb_ruinas` | 0.7 (0.4 en la pirámide) | **0.6 con A; 0.5 con B** | Es la capa más alta de la zona. Con el 73 % por debajo de 200 Hz no competía con nadie en los medios; al subir a 200–1200 Hz comparte banda con `amb_selva` (56 % en 200–1000 Hz) y `amb_viento` (76 %) |
| Voz de Chiich en `cine_llamado_fx` | — | **−1.5 dB dentro de la pista si se elige A** | Su sílaba acentuada pasa a ser el momento más fuerte de la pista (−12.1 LUFS-M frente a −13.7). La flauta y la kalimba de `cine_llamado_mus` en ese plano (La4–Fa5, 440–700 Hz) caen en la banda de las vocales; van 4 LU por debajo y en el juego otros 2 dB más bajas: no debería tapar, pero hay que oírlo |

Regla general que sale de la tabla: los golpes grandes del jefe ya están en el techo del
limitador, así que **no se gana nada subiéndolos**; lo que da sitio es bajar lo que suena a
la vez (ya se hace con la música) y no apilar tres efectos grandes en el mismo instante. Lo
que sí está corto es lo que avisa: la pisada y la embestida.

---

## Hoja de escucha

Escuchar cada grupo en este orden: `__actual`, A, B, C; primero con auriculares y después con
los altavoces de un portátil o de un móvil. Apuntar un sí o un no, y cuál se prefiere.

**1. Balam**

- ¿El `actual` suena a zumbido o a motor? ¿Y cada candidato?
- ¿Cuál suena a animal? ¿A un animal grande, del tamaño de un jaguar, o a uno pequeño o a una persona gruñendo?
- ¿Se nota que la boca se abre y se cierra?
- En el altavoz del portátil, ¿cuál se sigue oyendo con cuerpo?
- ¿B es fiero o es sucio (ruido, chasquidos sueltos)? ¿El cierre de garganta del final molesta?
- ¿C sirve como rugido, o es otra cosa (un bufido, un aviso)?
- `balam_grunido`: ¿suena a gruñido corto o a eructo o motor? ¿Hace pareja con el rugido elegido?
- `balam_especial`: ¿el rugido corto y la onda de choque parecen un solo gesto?

**2. Chiich Yaxché**

- ¿La `actual` suena a puerta que chirría? ¿Alguno de los candidatos también?
- ¿Se oye a alguien que habla sin palabras? ¿A una anciana? ¿Da miedo, da risa o da confianza?
- ¿Se entiende la intención de las dos frases: primero una llamada (sube), después un refunfuño (cae)?
- ¿Suena a árbol, o solo a persona (A) o solo a madera (B)?
- ¿El temblor de la voz parece de voz vieja o de aparato (un trémolo mecánico)?
- ¿C (susurro) se oye bien o se pierde entre las hojas?
- En `cine_llamado_fx__*` (mejor con `cine_llamado_mus.mp3` sonando a la vez): ¿la voz está al nivel justo, sobresale o se pierde? ¿Encaja con el toc-toc y las campanillas del final?

**3. Aves**

- En cada bucle suelto: ¿algún canto suena a sintetizador, a juguete o a videojuego antiguo? ¿Cuál (apuntar el segundo)?
- ¿Suenan lejos, en una selva, o pegadas a la oreja?
- Dejarlo sonar tres o cuatro vueltas: ¿se reconoce algún canto cuando vuelve? ¿Cuál?
- ¿El tamborileo (A) y el graznido o los chasquidos (B) encajan o distraen?
- ¿C (bandada) suena a coro de aves lejano o a ruido o a grillos?
- En `amb_aves_en_selva__*`: ¿las aves se oyen sobre la selva sin tapar? ¿Alguna pega un susto? ¿Cuál de las cuatro mezclas se dejaría sonando diez minutos?

**4. Cenote y ruinas**

- Con el altavoz del portátil o del móvil: ¿se oye algo del `actual`? ¿Y de A y de B?
- Con auriculares: ¿A y B siguen sonando a espacio grande y hueco, o se han quedado pequeños o finos?
- ¿El cenote sigue pareciendo profundo y húmedo? ¿Las gotas con «plop» suenan a gota o a burbuja de dibujos animados?
- ¿Las ruinas siguen pareciendo piedra antigua y quieta? ¿Los soplos de B suenan a aire entre piedras o a alguien soplando o a un fantasma?
- ¿Alguna resonancia suena a nota de órgano o a pitido que canse?
- Tras tres o cuatro vueltas: ¿se reconoce algún suceso (el gorgoteo, el reguero de piedrecillas, el asiento lejano)?

**5. Nojoch Tuunich**

- A ciegas (que otra persona los lance en desorden): ¿se distingue el paso de la losa? ¿El barrido de la embestida?
- ¿Se entiende el peso con el altavoz del portátil? ¿Cuál pesa más: el `actual`, A o B?
- ¿Suena a piedra, o a tambor, a madera o a metal? (Atención al cuerpo de los golpes y a la placa de la losa.)
- ¿El chasquido del ataque ayuda o pincha? ¿Cansaría oír `jefe_paso` cada medio segundo?
- `jefe_barrido`: ¿se entiende que algo enorme pasa rozando, sin golpe?
- `jefe_embestida` seguida de `jefe_choque` (reproducirlos uno detrás de otro): ¿enlazan? ¿Las zancadas suenan a carrera o a caballo o a tambor?
- `jefe_choque`: ¿se oye la columna partirse y caer a trozos?
- `jefe_cae` y `jefe_despierta`: ¿el quejido y el rugido de roca, una octava más altos, siguen sonando a roca enorme o se han quedado en zumbido?
- B: ¿la cola hace el golpe más grande o lo emborrona?

**Mezcla** (jugando, cuando haya algo conectado)

- ¿Se oye venir al coloso por sus pasos, con música?
- ¿Se oye el anuncio de la embestida a tiempo de apartarse?
- En el choque contra la columna y en la liberación: ¿el golpe suena limpio o «aplastado»? ¿Baja de golpe el ambiente?
- Al transformarse en Balam: ¿se oye el gruñido o solo el acorde?

---

## Lo que no se ha podido hacer o comprobar

- **Escucharlo.** Todo lo de arriba son números y espectrogramas. No sustituyen al oído: un
  espectrograma dice que hay armónicos que suben con la frase, no que suene a abuela.
- **Probarlo en el juego.** No se ha ejecutado Godot ni un navegador. Los candidatos de
  efectos no se han importado (QOA) ni oído con la atenuación por distancia y la variación de
  tono del juego; los bucles no se han probado con Web Audio (la costura se ha medido con el
  decodificador de ffmpeg y desfases simulados, como hace `gen_ambiente.py --check`).
- **La propuesta de mezcla es aritmética**, a partir de la sonoridad de los archivos y de los
  ajustes del código, no una medida de la salida del navegador con todo sonando. El efecto del
  limitador está estimado por los picos, no medido.
- **Variantes.** `jefe_paso` se repite con una sola muestra y la variación de tono del juego;
  no se han hecho variantes numeradas (`jefe_paso_2`…), que ayudarían más que cualquier timbre.
- **Otros sonidos de las mismas familias** no se han tocado: `balam_golpe`, `jefe_aviso`,
  `jefe_llamada`, `jefe_aturdido`, `jefe_fase`, `jefe_respira`, `pilar_rompe`, ni los
  efectos por plano de respaldo de las cinemáticas, que conservan el carácter anterior.
- **La voz actual de Chiich suelta** sale de una resta, no del generador: es exacta para la
  voz con su sala, pero no existe como pista en el juego.
- **Diferencia de brillo.** Los candidatos de Balam y del jefe cortan los agudos en 6–6.5 kHz
  y los actuales en 4–6.5 kHz (el rugido en 4.5 kHz, la pisada en 4.5 kHz). Parte de la
  diferencia que se oiga es ese corte; va incluido a propósito, pero conviene saberlo.
- **Los candidatos «grandes» duran más que los actuales** (hasta medio segundo). El juego
  reproduce el archivo entero, así que no debería importar, pero no se ha comprobado con el
  ritmo real del combate.
- **Peso.** Si se adoptan, los bucles pesarán como los actuales (allí se codifican con
  `-q:a 6`); aquí van con `-q:a 4`, lo pedido para escuchar, y por eso ocupan más.
