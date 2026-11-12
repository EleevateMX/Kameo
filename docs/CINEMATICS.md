# Cinemáticas de ALUX

Dirección cinematográfica oficial: qué es una cinemática narrativa, cómo se produce con Kling, cómo
se reproduce en una partida cooperativa sin romperla y en qué estado está cada una.

## Política

1. **Toda cinemática narrativa lleva un componente producido con Kling.** Son narrativas: la
   introducción del juego, la presentación de personajes importantes, el vínculo con cada espíritu
   (transformaciones), las revelaciones de la historia, la presentación de jefes, la apertura y el
   final de cada capítulo y todo lo relacionado con Kukulkán.
2. **No llevan Kling** el combate, el movimiento, los diálogos interactivos ni los eventos menores:
   funcionan mejor en tiempo real. Una escena interactiva no se sustituye por un vídeo.
3. **Ninguna escena depende de que un vídeo cargue.** Cada plano de vídeo tiene debajo el mismo plano
   hecho con el motor; si el vídeo falta, falla o se atasca, se ve ese y la partida sigue.
4. **El servidor manda.** Empieza la escena, pausa la sala, cuenta los votos, la termina y reanuda.
   El progreso y las recompensas nunca dependen del reloj de un vídeo.
5. **Kling no rediseña.** Personajes y lugares salen de los modelos del juego: cada plano parte de un
   cuadro hecho con el propio juego y de las hojas de personaje. Nada fotorrealista ni con aspecto de
   otro motor: fantasía 3D estilizada, formas expresivas, luz de cine, elementos de Yucatán.
6. **El alux del jugador no sale con una cara fija.** Cada quien elige color y sombrero, así que en
   vídeo sólo aparece de forma que no lo contradiga (encuadres de ambiente, sombras, punto de vista,
   espíritus); cuando hace falta verlo, ese tramo se hace con el motor y su aspecto real.
7. **Los créditos se aprueban por cinemática**, con presupuesto máximo. Dentro del límite aprobado
   se generan las tomas necesarias sin pedir permiso una a una.

## Cómo está hecho (sistema híbrido Godot + vídeo)

**Lo que se comprobó del motor:** Godot 4.5 en el navegador sólo reproduce Ogg Theora, decodificado
por software en el hilo del juego; no reproduce MP4 ni WebM. Por eso los vídeos los reproduce el
navegador en un `<video>` colocado encima del lienzo, y el juego lo dirige por un puente.

| Pieza | Archivo | Qué hace |
| --- | --- | --- |
| Guiones | `game/scripts/shared/story_def.gd` (`CUTSCENES`) | Planos: duración, cámara, texto, sonido y, si lo hay, `video` |
| Reproductor | `game/scripts/client/cinematics/cutscene.gd` | Mueve la cámara plano a plano; si el plano tiene vídeo listo lo pone encima y vigila que avance |
| Puente (juego) | `game/scripts/client/cinematics/video_bridge.gd` | Órdenes y consultas al navegador; fuera de la web responde «no hay vídeo» |
| Puente (navegador) | `game/web/static/cine-video.js` | Manifiesto, precarga, `<video>` sobre el juego, subtítulos, registro de fallos |
| Vídeos y manifiesto | `game/web/static/video/` | `manifest.json` y los archivos; se copian al portal al compilar |
| Transiciones e interfaz | `game/scripts/client/hud.gd` | Fundido a negro, franjas, subtítulos, aviso de omitir |
| Fases en la sala | `game/scripts/server/game_server.gd` | Preparación, inicio compartido, votos, fin y reanudación |

Un plano con vídeo sólo añade un campo; el resto es el plano del motor que sirve de respaldo:

```gdscript
{"dur": 3.5, "from": [Vector3(15.5, 3.2, 4.0), Vector3(26, 3.2, 0)], "to": [Vector3(17.5, 2.6, 2.2), Vector3(27, 3.8, 0)],
	"text": "Cada alux en su altar, y el sello cede…", "sound": "santuario_abre", "video": "sello_1"}
```

Y el vídeo se declara en `game/web/static/video/manifest.json` (hoy está vacío: no hay ninguno aprobado):

```json
{ "v": 1, "clips": { "sello_1": { "src": { "mp4": "sello_1.mp4", "webm": "sello_1.webm" }, "dur": 3.5, "audio": false, "v": "a1" } } }
```

Añadir o cambiar un vídeo es dejar los archivos y su entrada en el manifiesto; no hay que tocar el
juego. `v` es la versión: va en la dirección, así el navegador puede guardar el archivo un año.

### En el navegador

| Tema | Cómo se resuelve |
| --- | --- |
| Formatos | MP4 (H.264) y WebM (VP9). Se descarga sólo el que el navegador reproduce. Objetivo: 720p, ~1.5 Mbps. |
| Precarga | Al entrar a la partida, con prioridad baja y de uno en uno. El archivo se baja entero antes de usarse: no hay cortes por red a mitad. |
| Caché | Vídeos con versión en la dirección y caché de un año; el manifiesto se revalida en cada visita. |
| Sonido | Por defecto en silencio (suena el audio del juego, con los volúmenes del jugador). Un vídeo marcado `audio` suena sólo si el usuario ya interactuó con la página; si el navegador lo bloquea, se reproduce mudo. |
| Subtítulos | Los mismos textos del guion, dibujados por la página sobre el vídeo (no van quemados). |
| Rendimiento | Mientras el vídeo tapa el juego, el mundo 3D no se dibuja. |
| Fallos | Sin manifiesto, archivo ausente, formato no soportado, descarga lenta, error al decodificar, bloqueo de reproducción y vídeo atascado: en todos se ve la escena del motor. Cada fallo queda en el registro del navegador y en las métricas de la sesión (`cine` en `/api/v1/telemetry`). |
| Seguridad | Sólo archivos del mismo sitio declarados en el manifiesto; el juego pasa identificadores y textos, nunca código ni HTML. |

### En la sala (compartidas)

```
PREPARING ──(todos listos o 5 s)──▶ PLAYING ──(duración o mayoría)──▶ RESUMING ──(1 s)──▶ partida
```

| Fase | Servidor | Cliente |
| --- | --- | --- |
| **PREPARING** | Pausa la sala y avisa (`cine_prep`). Espera a que cada conectado conteste `cine_ready`, como mucho 5 s. | Oculta la interfaz, funde a negro, comprueba si tiene los vídeos y contesta (con vídeo o sin él). |
| **PLAYING** | Orden de inicio para todos a la vez (`cine`). Cuenta la duración y los votos. | Reproduce vídeo o motor, según lo que tenga. Enter vota omitir. |
| **RESUMING** | `cine_end`; la sala sigue en pausa 1 s más: nadie recibe daño en la transición. | Corte a negro, la cámara vuelve detrás del personaje, fundido de entrada, interfaz de juego. |

| Regla | Detalle |
| --- | --- |
| El vídeo no viaja por el WebSocket | Cada navegador lo descarga por HTTP; el servidor sólo manda órdenes. |
| Nadie bloquea a nadie | Quien no contesta (descarga colgada, versión vieja) retrasa el inicio como mucho 5 s. Quien se desconecta deja de contar al instante. |
| Omitir | Mayoría de los conectados (1 de 1, 2 de 2, 2 de 3, 3 de 4). Sólo durante la reproducción. Un jugador solo omite al instante. |
| Reconexión | Quien vuelve o entra a mitad recibe la fase y el punto por el que va (`at`) y se engancha ahí; si ya terminó, entra directo a la partida. |
| Sin duplicados | Una vez por sala. Otra ronda o una reconexión no la repiten ni repiten sus consecuencias. |
| Diferencias entre clientes | Cada uno puede ir unas décimas adelantado o atrasado. El final lo marca el servidor para todos; el último plano se corta si un cliente iba tarde. |
| Sólo en puntos seguros | Nunca en mitad de un combate. |

Las **locales** (la introducción) no pasan por el servidor: cada jugador la ve y la omite en su
pantalla, y usan el mismo reproductor y los mismos vídeos.

### Integración con el juego

- **Entrada:** fundido a negro desde la cámara de juego (0.45 s) durante la preparación.
- **Salida:** corte a negro, la cámara vuelve a su sitio sin que se vea el salto y fundido de entrada
  (0.55 s), todo dentro del segundo de reanudación.
- **Alineación:** el primer cuadro de cada plano de Kling es una captura del juego con la cámara
  exacta del plano; cuando el modelo lo permite, también el último. Así el vídeo empieza y termina
  en el mismo encuadre que el plano del motor que tiene debajo.
- **Sin teletransportes:** un vídeo no cambia de sitio a un personaje ni altera el mundo sin que la
  historia lo explique; lo que cambie (el sello abierto) tiene que estar ya cambiado en el juego.

## Proceso con Kling

| Paso | Qué se hace | Con qué |
| --- | --- | --- |
| 1 | Imágenes de los modelos actuales | `art/referencias/` (se regeneran con `art/blender/render_referencias.py`) |
| 2 | Hojas de personaje: frente, tres cuartos, lado y espalda | `art/referencias/*_hoja.png` |
| 3 | Ficha de ropa, accesorios, proporciones, colores y rasgos fijos | `art/referencias/README.md` |
| 4 | Cuadros clave del escenario con la cámara de cada plano | `PREVIEW_SIZE=1920x1080 scripts/preview.sh <carpeta> kf_sello_1a …` → `art/cinematicas/<escena>/` |
| 5 | Storyboard | Este documento |
| 6 | Movimientos de cámara | Los `from`/`to` del guion: son los mismos del plano del motor |
| 7 | Prompts por plano | Este documento |
| 8 | **Presupuesto aprobado** → generar y evaluar tomas | Kling |
| 9 | Corregir inconsistencias (repetir, recortar, descartar) | Kling + montaje |
| 10 | Convertir a MP4 y WebM 720p, añadir al manifiesto, probar | `ffmpeg`, `npm run test:cine`, `npm run test:cine-coop` |

**Hojas de personaje** (sin textos: Kling copia lo que lee):

![Hoja de Chiich Yaxché](../art/referencias/yaxche_hoja.png)

Las hojas muestran el diseño tal como lo describen los scripts de construcción. Dos detalles se
corrigieron sólo en el render y **no coinciden con los modelos del juego**: los hilos finos de las
prendas (en el juego quedan como ranuras) y el cabello del alux bajo el sombrero. Están anotados en
[pendientes.md](pendientes.md).

### Lo medido y lo que no

| Dato | Valor | Origen |
| --- | --- | --- |
| Saldo | **2 659 créditos** | Consultado el 12 nov 2026 |
| `kling-video-v3_0_turbo`, 1080p, 5 s, primer cuadro | **50 créditos** | Una toma de prueba |
| Cualquier otro modelo, duración o resolución | **Sin medir** | — |
| Peso para web | 0.85 MB por 5 s a 720p y 1.5 Mbps | Conversión de la toma de prueba |

Modelos disponibles que importan: `v3_0_turbo` (sólo primer cuadro, 3–15 s), `v3_0` y `v4_0` (primer
y último cuadro: permiten terminar en la cámara exacta del juego) y los `omni` (varias imágenes de
referencia: sirven para planos con personaje). Las estimaciones de abajo suponen el precio medido
(10 créditos por segundo) y se corrigen con la primera toma real de cada modelo.

![Cuatro cuadros de la toma de prueba](img/kling-prueba-vinculo.jpg)

La toma de prueba mantuvo el aspecto del juego (personajes y plaza). **No sirve como metraje final**:
muestra a un alux con un aspecto fijo (regla 6) y la cabeza de Balam aún se va a retocar. Queda como
referencia de movimiento.

## Presupuestos (pendientes de tu aprobación)

| | **C. El sello cede** | **A. El llamado de Chiich Yaxché** | **B. El vínculo de Balam** | **D. Despertar de Nojoch Tuunich** |
| --- | --- | --- | --- | --- |
| Duración | 10 s | 13 s | 20–24 s | 15–20 s |
| Planos (generaciones por pasada) | 3 | 3 | 4 | 4 |
| Modelo | `v3_0` con primer y último cuadro; si sale a más del doble del precio medido, `v3_0_turbo` | `v3_0`; el plano de la abuela con un `omni` y su hoja de personaje | `v3_0` y `omni` con la hoja de Balam | Por decidir con el modelo del jefe |
| Costo estimado por generación | 40–50 | 50 | 50–60 | 50 |
| Repeticiones previstas | hasta 2 por plano | hasta 2; 3 en el plano con personaje | hasta 2 por plano | hasta 2 por plano |
| Estimado por pasada | 120–150 | 150 | 240 | 200 |
| **Presupuesto máximo** | **500** | **550** | **750** | **700** |
| Referencias | 6 cuadros clave del juego (`art/cinematicas/sello/`) | Hoja de Yaxché, cuadros de la gran ceiba y del brasero | Hoja de Balam, cuadros de la plaza de noche | Modelo del jefe (no existe) |
| Resultado | 3 vídeos 1080p → 720p web (~2 MB), integrados con respaldo del motor | Sustituye el final de la introducción y enlaza con el diálogo | Escena del vínculo + transición con el motor al Balam jugable | Presentación compartida del jefe, terminando en la cámara de combate |
| Bloqueos | **Ninguno** | Storyboard y cuadros clave por hacer | Cabeza de Balam, luz de noche, storyboard por adaptar a la regla 6 | Modelo y mecánica del jefe sin aprobar |

El presupuesto de C incluye una variante del plano 2 con los cuadros clave «enriquecidos» (materiales
y luz más ricos, hechos con imagen a imagen) para que compares con evidencia qué aspecto prefieres
antes de producir las demás.

**Los cuatro máximos suman 2 500 créditos de 2 659.** No recomiendo aprobarlos juntos: con C se mide
el precio real de los modelos y cuántas repeticiones hacen falta, y con eso se ajustan los otros tres.

## Estado de cada cinemática

| Id | Título | Clase | Dónde ocurre | Estado |
| --- | --- | --- | --- | --- |
| `llamado` | El llamado | Local | Al entrar por primera vez; se repite desde el menú | Versión del motor hecha (4 planos, 19 s). Componente Kling: cinemática A, sin presupuesto aprobado |
| `sello` | El sello cede | Compartida | La primera vez que el grupo abre el santuario | Versión del motor hecha (2 planos, 7 s) y **lista para vídeo**: storyboard, cuadros clave y prompts preparados. Falta aprobar el presupuesto |
| `vinculo_balam` | El vínculo de Balam | Compartida o local, por decidir | Tras hablar con Chiich Yaxché | Storyboard aprobado, por adaptar a la regla 6; una toma de prueba; producción en 0.4 |
| `guardian_despierta` | Despertar de Nojoch Tuunich | Compartida | Al entrar al patio del santuario | Bloqueada hasta aprobar modelo y mecánica del jefe (0.3) |
| `pluma_de_jade` | La Pluma de Jade | Compartida | Al vencer al jefe | Planeada (0.4) |

## «El llamado» (hecha)

| Plano | Duración | Cámara | Texto |
| --- | --- | --- | --- |
| 1 | 5.0 s | Vista alta del claro, avanzando despacio | *Capítulo I · El Claro de los Aluxes* — «La selva del Mayab lleva tres noches sin cantar.» |
| 2 | 4.5 s | Orilla del cenote, bajando hacia el agua | «El agua del cenote amaneció oscura, y nadie se atreve a beberla.» |
| 3 | 5.0 s | Hacia el santuario sellado | «El santuario de los guardianes se cerró por dentro. Un sello que no es de este claro lo cubre.» |
| 4 | 4.5 s | Se acerca a Chiich Yaxché | **Chiich Yaxché:** «¡Despierta, alux! La selva te necesita… y yo ya me cansé de gritar.» |

Sólo se muestra sola la primera vez en cada navegador; después se puede repetir desde el menú.

## C. «El sello cede»: storyboard definitivo (pendiente de aprobar)

**Qué cuenta:** el grupo acaba de coordinarse por primera vez; el santuario responde, se abre… y lo
que guardaba ya no los reconoce. **Duración:** 10 s en tres planos (hoy son 7 s en dos; las reglas del
servidor no cambian, sólo la duración del guion). **Sin personajes:** los jugadores están sobre los
altares con su propio aspecto, así que ningún plano los muestra, ni a los enemigos de cuerpo entero
(sus modelos son provisionales y cambiarán en la 0.3).

![Cuadros clave: primer y último cuadro de cada plano, sacados del juego](img/storyboard-sello.jpg)

| Plano | Duración | Qué pasa | Cámara (la misma del plano del motor) | Primer → último cuadro | Subtítulo |
| --- | --- | --- | --- | --- | --- |
| 1. Los altares responden | 3.0 s | Los glifos del altar se encienden en jade; la luz corre por el suelo hasta el santuario y sube por sus glifos. La cúpula del sello ondula. | Baja, avanza hacia el portal | `plano_1a` → `plano_1b` | «Cada alux en su altar…» |
| 2. El sello cede | 3.5 s | La luz llega al sol tallado, que se enciende en oro. Los barrotes magenta parpadean, se quiebran y se hunden; la cúpula se deshace en motas. Una ola dorada sale del portal y deja ver el patio. | Avanza hacia el portal | `plano_2a` (sellado) → `plano_2b` (abierto) | «…y el sello cede.» |
| 3. Los Olvidados despiertan | 3.5 s | Silencio. Vetas magenta trepan por la piedra, el anillo del suelo late, se levantan polvo y piedras, se junta una niebla oscura. En la sombra del portal se encienden pares de ojos. | Desciende hacia el anillo | `plano_3a` → `plano_3b` | «Pero quienes lo cuidaban ya no recuerdan a quién. ¡Los Olvidados despiertan!» |

Termina en negro y la partida vuelve con la cámara de cada jugador, justo antes de la emboscada.

**Prompts** (en inglés; imagen a vídeo, con el cuadro clave como primer cuadro y, si el modelo lo
admite, el último):

| Plano | Prompt |
| --- | --- |
| 1 | *The carved glyphs on the round stone altar in the foreground ignite with jade-green light. The light races as thin glowing lines across the ground toward the sealed stone sanctuary and climbs its carved glyph panels one by one. The translucent pink dome over the sanctuary ripples. Low camera slowly pushes forward toward the gate. Small floating jade motes, soft cinematic light.* |
| 2 | *The jade light reaches the sun glyph above the gate, which flares gold. The magenta energy bars sealing the gate flicker, crack and sink into the ground, while the translucent pink dome breaks into drifting motes and dissolves. A wave of warm golden light bursts outward from the gate, revealing the inner courtyard and a jade crystal floating above a stone pedestal. Camera pushes slowly toward the open gate.* |
| 3 | *Silence falls. Thin magenta veins of corruption creep across the stone pillars and the ground, and the magenta ring on the grass pulses brighter. Dust lifts, small stones tremble and rise, dark magenta mist gathers inside the ring. In the shadow of the gate, pairs of magenta eyes light up. Camera lowers slowly toward the ring. Ominous, no creatures fully visible.* |

En los tres: *Stylized low-poly 3D animation, flat colours, clean shapes, same architecture, colours
and layout as the first frame. No characters, no people, no animals, no text, no logos.*
Negativo: *photorealistic, realistic textures, film grain, new buildings, camera shake, humans, text, watermark.*

**Al aprobarse:** se generan las tomas dentro del presupuesto, se eligen contigo, se convierten, se
añaden al manifiesto, el guion pasa a tres planos de 10 s (con el plano 1 nuevo también en la versión
del motor) y se repiten `npm run test:cine` y `npm run test:cine-coop`.

## A. «El llamado de Chiich Yaxché» (guion; sin presupuesto aprobado)

13 s en tres planos, como cierre de la introducción y entrada al diálogo que ya existe.

| Plano | Duración | Qué pasa | Notas |
| --- | --- | --- | --- |
| 1 | 4 s | La ceiba ancestral late: una luz extraña sube por el tronco y las hojas se quedan quietas. | La gran ceiba ya existe junto al cenote; faltan sus cuadros clave. |
| 2 | 4 s | Chiich Yaxché levanta la cabeza; el brote de jade de su bastón parpadea y se oscurece un instante. | Plano con personaje: su hoja como referencia y primer cuadro del juego. |
| 3 | 5 s | Sobre las copas avanza una sombra magenta hacia el santuario. Ella se vuelve hacia la cámara. | Termina en el encuadre donde empieza el diálogo: «¡Por fin despiertas…!». |

Es local (cada jugador la ve al entrar), así que el vídeo tiene que estar precargado antes de
empezar: la introducción esperará su descarga unos segundos y, si no llega, usará el motor.

## B. «El vínculo de Balam» (storyboard aprobado el 12 nov 2026; producción en 0.4)

**Qué cuenta:** por qué el alux puede volverse jaguar. Balam no es un poder: es alguien que decide
caminar con él. **Duración:** unos 24 s en cuatro planos. **Formato:** 16:9, 1080p de origen.
**Sin diálogo**; un único texto al final.

| Plano | Duración | Qué se ve | Cámara | Referencias | Primer cuadro |
| --- | --- | --- | --- | --- | --- |
| 1. La noche | 6 s | El claro de noche. El brasero casi apagado. Un alux pequeño, de espaldas, mira la selva. Entre los árboles se encienden dos ojos ámbar. | Avance lento hacia el alux | Alux (hoja de modelo), plaza del juego | Captura del juego: plaza de noche, alux de espaldas |
| 2. El jaguar | 7 s | Balam sale de la maleza: jaguar de rosetas oscuras con ajorcas y glifos de jade que brillan. Rodea al alux despacio. El alux retrocede un paso… y se queda. | Giro alrededor de los dos | Balam (hoja de modelo), alux | Captura del juego: Balam y alux frente a frente |
| 3. La frente | 5 s | Primer plano. El jaguar baja la cabeza y apoya la frente en la del alux. Las rosetas se encienden una a una. | Fija, muy cerca | Retratos de ambos | Montaje de los dos retratos |
| 4. La luz | 6 s | Balam se deshace en motas y plumas de luz de jade que envuelven al alux. Por un instante su sombra es la de un jaguar. Amanece. | Retroceso y subida | Alux, plaza al amanecer | Último cuadro del plano 3 |

**Texto final (subtítulo del juego):** «Balam camina contigo. Llámalo con el 2.»

**Prompts base** (en inglés, que es como mejor responde Kling; se afinan con la toma de prueba):

| Plano | Prompt |
| --- | --- |
| 1 | *Night in a small jungle plaza of pale limestone, a low stone brazier with dying embers. A small clay guardian with large ears, a palm hat and an embroidered tunic stands with his back to the camera, looking into the dark jungle. Two amber eyes light up between the trees. Slow push-in, soft moonlight, fireflies, stylized 3D animation, rounded shapes, saturated colors.* |
| 2 | *A stylized jaguar with dark rosettes, jade anklets and softly glowing jade glyphs on its shoulders steps out of the foliage and slowly circles the small clay guardian. The guardian takes one step back, then holds still. Camera orbits around them, moonlight, gentle jade glow on the stone floor.* |
| 3 | *Extreme close-up: the jaguar lowers its head and rests its forehead against the small guardian's forehead. The rosettes on its fur light up one by one in jade green. Static camera, shallow depth of field, warm and tender mood.* |
| 4 | *The jaguar dissolves into motes and feathers of jade light that swirl around the small guardian. For an instant his shadow on the stone is the shadow of a jaguar. Dawn breaks over the jungle. Camera pulls back and rises.* |

En todos: *same character design as the reference images, no text, no logos, no humans.*

**Qué hace falta antes de producirla**

1. ~~Tu aprobación de este guion y de los cuatro planos.~~ Hecho.
2. Modelos definitivos del alux y de Balam (la cabeza de Balam todavía se va a retocar): si se
   produce antes, habrá que repetirla.
3. Las capturas de primer cuadro, de noche; hoy el juego sólo tiene iluminación de día.
4. Tu autorización del presupuesto (máximo 750). La toma de prueba ya está hecha.
5. ~~El reproductor de vídeo del navegador.~~ Hecho.
6. Adaptar los planos 1, 2 y 4 a la regla 6: el alux del jugador no puede salir con un aspecto fijo.
   Propuesta: verlo sólo como sombra o desde su punto de vista, y hacer con el motor (con su aspecto
   real) el instante en que se vuelve jaguar.

**Respaldo dentro del motor:** la misma escena en tres planos con los modelos del juego y el efecto
de transformación que ya existe. Se hará primero, así la escena existe aunque el vídeo no cargue.

## D. «Despertar de Nojoch Tuunich» (bloqueada)

15–20 s: la piedra se resquebraja, los glifos del pecho se encienden uno a uno, el coloso abre los
ojos y se incorpora; termina en la cámara con la que empieza el combate. **No se produce** hasta que
el modelo y la mecánica del jefe estén aprobados: un vídeo hecho antes habría que repetirlo.
