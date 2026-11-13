# Audio de ALUX

Cómo suena el juego en el navegador, por qué no sonaba hasta la Alpha 0.3 y cómo se comprueba que
suena **midiendo la salida**, no contando llamadas a `play()`.

- Banco de sonidos, música y cinemáticas: [art/audio/](../art/audio/README.md) (cómo se generan) y
  [ASSETS_AUDIO.md](ASSETS_AUDIO.md) (procedencia y licencias de cada archivo).
- Prueba: `npm run test:audio` ([tests/e2e/audio-probe.ts](../tests/e2e/audio-probe.ts)).

## El defecto: el juego no sonaba (Alpha 0.1 a 0.3)

**Síntoma.** Un jugador entró a la Alpha 0.3 publicada y no oyó nada. Las pruebas automáticas daban
el audio por bueno porque sólo miraban que el juego hubiera cargado los sonidos y que el
`AudioContext` del navegador estuviera en marcha.

**Diagnóstico.** La sonda engancha todo lo que se conecta a la salida de audio del navegador, lo
mide y lo graba. Contra la 0.3 (en local y en `alux-beta.onrender.com`): contexto «running», el
juego «reproduciendo» música y efectos, 18 fuentes arrancadas con datos válidos… y en la salida,
**silencio absoluto** (−∞ dB). El volcado del grafo de Web Audio mostró por qué: el bus maestro del
motor no estaba conectado a la salida; a la salida sólo llegaba el nodo de audio en flujo del motor,
que no se usa.

**Causa.** `audio.gd` creaba los buses `Music`, `SFX` y `Ambience` al arrancar con
`AudioServer.add_bus()`. En la exportación web sin hilos, Godot 4.5 reproduce los sonidos como
«muestras» sobre un mezclador propio escrito en JavaScript, y ese mezclador tiene un error al
añadir buses en ejecución: `Bus.addAt()` crea el bus y lo recoloca con `Bus.move(desde, hasta)`,
que hace `splice(hasta - 1, …)`; cuando «hasta» es −1 (añadir al final), eso es `splice(-2, …)` y el
bus nuevo acaba **en la posición 0**. El grafo volcado lo confirma: el maestro deja de ser el bus 0
y, al reasignar los envíos, se desconecta de la salida y acaba enviando a un bus que no va a
ninguna parte. No es autoplay, ni volumen, ni formato: el grafo
quedaba cortado desde el primer cuadro, en todos los navegadores.

**Descartado con evidencia:** bloqueo de autoplay (el contexto estaba en marcha), volúmenes y
silencios (ganancias correctas en el grafo), archivos (las fuentes arrancaban con datos, pico
0,2–0,4), compresión QOA (las muestras se decodifican bien), el envoltorio del `AudioContext` de la
página (sólo guardaba una referencia), ajustes guardados (la sonda los borra antes de entrar).

**Corrección.** Los buses se definen en [`game/default_bus_layout.tres`](../game/default_bus_layout.tres)
y ya no se crea ninguno en ejecución (el motor los monta bien cuando vienen de la disposición).
Medido con la misma sonda: de −∞ dB a ambiente y música a unos −25 dBFS, con picos de −6 dBFS al
usar la chispa de jade.

| | Antes (0.3) | Después |
| --- | --- | --- |
| Grabación de la salida del navegador (27 s) | −∞ dB RMS, −∞ dB de pico | −28 dB RMS, −8,7 dB de pico |
| Maestro del motor → salida | desconectado | conectado |

## Cómo está montado

Dos caminos, según lo que el motor hace bien en web:

| Qué | Quién lo reproduce | Por qué |
| --- | --- | --- |
| Efectos (bus `SFX`) e interfaz (bus `UI`) | El motor, como muestras de Web Audio, desde `res://assets/audio/*.wav` | Cortos, con respuesta inmediata, variación de tono y atenuación por distancia |
| Música, ambientes y bandas sonoras de las cinemáticas | [`alux-audio.js`](../game/web/static/alux-audio.js), el mezclador de la página, desde `game/web/static/audio/*.mp3` | El motor en web reinicia los bucles al terminar (hueco audible), no aplica efectos de bus a las muestras y obligaría a meter la música en la descarga inicial |

El mezclador usa **el mismo `AudioContext` que el motor** (lo captura al crearse), así que hay un solo
permiso del navegador y una sola cadena de salida:

```
motor (SFX, UI) ───────────────────────────┐
música ──► atenuación ──► bus Music ──┐     │
ambientes ► atenuación ──► bus Ambience ┼► maestro ┴► pestaña visible ► limitador ► salida
cinemáticas (efectos) ──► bus Cinematics ┘                                    └► medidor
cinemáticas (música) ───► bus Music
```

- **Buses:** `Master`, `Music`, `Ambience`, `SFX`, `UI`, `Cinematics` y `Voice` (reservado: el juego
  no tiene voces todavía). Volúmenes por defecto: general 0,9 · música 0,7 · ambiente 0,8 ·
  efectos 0,9 · interfaz 0,8 · cinemáticas 0,9. Se guardan en el navegador con el resto de ajustes.
- **Limitador:** un compresor de Web Audio (umbral −8 dB, razón 16:1, ataque 2 ms) sobre toda la
  salida, también sobre lo que manda el motor. El compresor del navegador añade por su cuenta una
  ganancia de compensación; se mide al arrancar con un tono de prueba fuera de línea y se deshace,
  para que sólo actúe cuando hay picos.
- **Bucles sin corte:** cada bucle lleva medio segundo de material repetido a cada lado y se
  reproduce con `loopStart`/`loopEnd` de Web Audio. Así el bucle es exacto aunque el decodificador de
  MP3 desplace el contenido unos milisegundos.
- **Música:** una pista a la vez con fundido cruzado; se cargan bajo demanda y sólo se guardan en
  memoria las dos últimas (un minuto de música decodificada ocupa unos 21 MB). Los ambientes se
  guardan a 22 kHz, la mitad, y la capa que deja de sonar se suelta; la banda sonora de una
  cinemática se suelta al terminar. Qué suena lo decide `_refresh_music()`: claro, exploración (lejos del
  centro), tensión (criaturas persiguiendo cerca), emboscada, las tres fases del guardián,
  liberación; con respaldo si falta una pista.
- **Ambientes:** capas simultáneas cuyo volumen depende de dónde está el jugador (selva, aves,
  insectos, viento; agua y cenote junto al cenote; ruinas y energía en el santuario y la pirámide;
  el brasero según la distancia). Lo calcula `_update_soundscape()` unas veces por segundo.
- **Atenuación de la música (ducking):** baja unos decibelios bajo los golpes grandes del guardián
  y calla durante las cinemáticas.
- **Distancia:** los efectos del mundo pierden volumen entre 5 y 38 m del jugador.
- **Variantes:** los efectos con archivos numerados (`chispa`, `chispa_2`, `chispa_3`; `paso_piedra_1…3`)
  alternan sin repetir dos veces seguidas la misma. Los pasos suenan a lo que se pisa.
- **Pestaña oculta:** el juego calla y vuelve a sonar al regresar.

Nada de esto usa funciones que la exportación web no tenga: no hay efectos de bus del motor ni
audio generado en tiempo de ejecución (salvo las tres notas de respaldo de «Probar sonido»).

## Activación y diagnóstico

- El audio arranca con el primer gesto. Quien llega desde el portal ya ha hecho clic en el mismo
  sitio y Chrome y Edge lo dejan sonar al cargar; si el navegador lo bloquea (Firefox y Safari
  suelen exigir un gesto en la propia página), cualquier clic, toque o tecla lo reanuda.
- **Aviso en pantalla** mientras está bloqueado: «🔇 Toca aquí o pulsa una tecla para activar el
  sonido». Con el volumen general a cero: «🔇 Sonido silenciado en Ajustes».
- **Menú → Probar sonido:** suena un aviso y, casi un segundo después, el juego lee el medidor de la
  salida y lo dice: «Prueba correcta: sale sonido (pico −7 dB)», «Audio bloqueado por el
  navegador…», «Volumen general a cero…» o «No llegó señal a la salida…».
- **Métricas de sesión:** cada sesión guarda el pico máximo medido en la salida, cuánto tardó en
  activarse el audio y los errores de carga. `npm run beta:metrics` lo resume en la columna «sonó».
  No se guarda nada más del jugador.
- **Registro en la página:** `ALUX_SND.log` y `ALUX_SND.state()` (contexto, nivel, pistas, errores),
  para depurar desde la consola del navegador.

## Cinemáticas

Cada cinemática tiene **una sola banda sonora**, en dos pistas (efectos en `Cinematics`, música en
`Music`), que el juego arranca en el segundo de la escena que toque. Es la misma se vea como vídeo de
Kling o con el motor: los vídeos no llevan audio, así que no hay nada que duplicar. Si un jugador
se engancha tarde o la descarga se retrasa, entra donde va la escena. Al omitir se funde en un
cuarto de segundo; si termina sola, se deja sonar la cola. Mientras dura, la música de fondo calla
y los ambientes bajan. Sin banda sonora (o fuera del navegador) cada plano dispara su efecto, como
antes; nunca las dos cosas.

## Pruebas

`npm run test:audio` abre el juego en un navegador con el audio encendido y **mide lo que llega a
la salida** (y lo graba en `tests/e2e/screenshots/audio/*.webm` para poder escucharlo):

| Escenario | Qué exige |
| --- | --- |
| `normal` | Tras el primer clic: contexto en marcha, ambiente y música audibles (más de −60 dBFS), sin errores de carga, el medidor del juego coincide con la salida. La chispa de jade se oye por encima y no recorta. «Probar sonido» confirma señal. Volumen general a cero: silencio absoluto, aviso en pantalla y en el menú; al subirlo, vuelve. Música a cero: queda el ambiente. Pestaña oculta: silencio; al volver, suena. Los bucles largos arrancan una sola vez con bucle de Web Audio |
| `bloqueado` | Con el audio bloqueado: contexto suspendido, silencio y aviso en pantalla; tras el primer clic, contexto en marcha, ambiente audible y aviso retirado. *El bloqueo es simulado* (el contexto nace suspendido y `resume()` no hace nada hasta un clic de verdad): bajo automatización Chromium concede siempre el gesto |
| `cine` | La introducción suena con su banda sonora; al omitirla para en menos de un segundo, vuelve la música del claro y no se arrancó más de una pista de efectos y una de música |

Además, el flujo de playtest y la prueba del jefe comprueban con el medidor que la música y el
ambiente suenan y que la música cambia con cada fase.

**Lo que estas pruebas no pueden decir:** si suena *bien*. Miden que hay señal, a qué nivel y que no
recorta. La única escucha humana es la de los sonidos de «Primera escucha humana»; ver también
«Validación pendiente».

## Contenido (Alpha 0.3.1)

Todo es síntesis propia, renderizada a archivos; no hay audio generado en tiempo de ejecución.
Procedencia de cada archivo: [ASSETS_AUDIO.md](ASSETS_AUDIO.md).

| Grupo | Archivos | Dónde | Detalle |
| --- | --- | --- | --- |
| Música | 10 piezas en estéreo (7,8 MB): claro, exploración, peligro, emboscada, las tres fases del guardián, liberación, victoria y el primer tema del lobby | `game/web/static/audio/mus_*.mp3` | [art/audio/MUSICA.md](../art/audio/MUSICA.md) |
| Ambientes | 10 capas en bucle (2,7 MB): selva, aves, insectos, viento, agua, cenote, ruinas, tormenta, energía y brasero | `game/web/static/audio/amb_*.mp3` | [art/audio/AMBIENTE_Y_CINE.md](../art/audio/AMBIENTE_Y_CINE.md) |
| Cinemáticas | 4 bandas sonoras en dos pistas cada una (1,8 MB): «El llamado», «El sello cede», «El despertar», «La liberación» | `game/web/static/audio/cine_*.mp3` | mismo documento, con el guion plano a plano |
| Efectos e interfaz | 112 efectos (50 nuevos en esta versión; 7 son los efectos por plano de respaldo de las cinemáticas): personaje, alux, Balam, enemigos, Nojoch Tuunich e interfaz | `game/assets/audio/*.wav` | [art/audio/README.md](../art/audio/README.md) |

**Qué suena ya en el juego y qué está en el banco esperando su momento:**

- Conectados: todo lo de arriba salvo lo que sigue.
- `amb_tormenta`: no hay clima en el Claro; queda para las regiones nuevas.
- `mus_lobby`: para el lobby social (Alpha 0.4).
- `luz_alux`, `escudo_alux`, `escudo_golpe`, `apoyo_alux`, `recoger`: el alux todavía no tiene esas
  habilidades ni objetos que recoger.
- `enemigo_paso`, `ui_error`, `ui_cancelar`, `ui_invitacion`, `ui_sala_creada`: sin evento en el
  juego (las invitaciones y la creación de sala ocurren en el portal, que no tiene sonido).

## Peso y memoria

| | Alpha 0.3 | Alpha 0.3.1 |
| --- | --- | --- |
| Descarga inicial del juego (motor, datos y código, con Brotli) | 11,25 MB | 10,58 MB |
| Paquete de datos del juego (`index.pck`) | 3,95 MB | 3,29 MB (la música y los ambientes ya no van dentro) |
| Audio pedido al entrar, en segundo plano | — | 2,8 MB (música del claro, cinco capas de ambiente e introducción) |
| Audio total si se oye todo en una sesión | — | 12,3 MB |
| Audio decodificado en memoria | — | unos 20 MB por música (dos como mucho) y 5 MB por capa de ambiente |

(Brotli de calidad 9 en las dos columnas, medido sobre los mismos archivos de cada compilación.)
El juego no espera al audio para empezar: cada pista entra con un fundido cuando termina de cargar.

## Primera escucha humana (13 nov 2026)

El dueño del proyecto comparó de oído cinco grupos de sonidos de la 0.3.1 con candidatos de ajuste
([art/audio/candidatos/](../art/audio/candidatos/LEEME.md)). Es la única evaluación humana que hay,
y cubre **sólo estos sonidos**:

| Sonido | Elegido | Qué pasa en la Alpha 0.4 |
| --- | --- | --- |
| Rugido de Balam | C · bufido | Se adopta. Además se conecta: suena cuando Balam salta (antes no sonaba en ningún sitio) |
| Gruñido al transformarse | B · rugoso | Se adopta, 2 dB más alto (el acorde de la transformación lo tapaba) |
| Zarpazo a plena carga | B · rugoso | Se adopta |
| Voz de Chiich Yaxché | En la escena, A · murmullo (suelta gustó más B · tronco) | Se adopta A en «El llamado», que es donde suena |
| Aves del claro | En el juego, el actual (suelto gustó más B · timbre) | No cambia |
| Cenote y ruinas | El actual | No cambian |
| Paso, losa y barrido de Nojoch | El actual | No cambian de timbre |
| Embestida, choque, caída y despertar de Nojoch | B · grande | Se adoptan |

Ajustes de mezcla que acompañan (propuestos **por medición**, no de oído, y sólo en la 0.4): el paso
del coloso sube 5 dB y su embestida 3 dB con la música bajando un momento, para que se le oiga
venir; la losa baja 2 dB y el choque contra la columna 2 dB (rozaban el limitador); la columna rota
baja 6 dB dentro del choque; la caída baja 3 dB porque suena a la vez que la liberación.

**Nivel de los elegidos.** Los candidatos se escucharon igualados en sonoridad con el sonido al que
sustituyen. En el juego los archivos conservan el pico de su familia (Balam −5 dBFS, Nojoch −3), y a
igual pico los elegidos no suenan igual de fuertes que los anteriores, así que el juego los lanza
compensados para que se oigan como se eligieron: gruñido +3,5 dB, zarpazo a plena carga +3 dB,
choque −3 dB, caída −3 dB y despertar −5 dB (bufido y embestida no cambian). Sin esa compensación
el despertar y el choque entrarían más fuerte en el limitador. Es un cálculo sobre la sonoridad
momentánea máxima, no una escucha: queda por confirmar de oído dentro del juego.

Todo lo demás —la música, el resto de efectos, los otros ambientes y las otras tres bandas sonoras—
sigue aprobado **sólo provisionalmente para pruebas**.

## Validación pendiente

- **Escucha humana completa.** Salvo los sonidos de la tabla anterior, ninguna persona ha evaluado esta versión. Las grabaciones de la salida del
  navegador que deja `npm run test:audio` permiten oír exactamente lo que salió en la prueba, pero
  eso es una escucha de la grabación, no una validación. Falta que alguien juegue con altavoces y
  con auriculares y diga si la mezcla, los timbres y los bucles convencen. Los propios generadores
  señalan sus puntos débiles (rugido de Balam, voz de árbol de «El llamado», cantos de ave, exceso
  de graves en cenote y ruinas, instrumentos de pocos parciales): ver sus documentos.
- **Chrome, Edge, Firefox y Safari reales, con tarjeta gráfica.** Las pruebas usan Chromium con
  render por software. En Firefox y Safari el audio debería necesitar un clic en el juego (se ve el
  aviso); no se ha comprobado en ellos, ni la costura de los bucles con sus decodificadores de MP3.
- **Bloqueo de autoplay real.** El escenario `bloqueado` simula la política del navegador.
- **Cuatro jugadores oyéndose.** La prueba de cuatro navegadores comprueba la partida, no la mezcla
  de cuatro personas a la vez.
- **Pantalla completa y reconexión con audio:** la reconexión conserva el contexto y la música
  (misma página); la pantalla completa llega con la Alpha 0.4.
- **Móvil:** el juego no tiene controles táctiles; el audio no se ha probado ahí.
