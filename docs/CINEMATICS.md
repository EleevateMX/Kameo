# Cinemáticas de ALUX

Cómo se hacen, cómo se reproducen en una partida cooperativa y en qué estado está cada una.
Las cinemáticas son parte del juego: cuentan lo que el jugador acaba de provocar o lo que está a
punto de hacer, y siempre devuelven el control en el mismo sitio.

## Tres clases

| Clase | Qué es | Quién la controla | Para qué | Estado |
| --- | --- | --- | --- | --- |
| **Local dentro del motor** | La cámara del juego recorre el escenario real, con subtítulos. | Cada jugador en su pantalla. No detiene a nadie más. | Introducciones al entrar, recordatorios, repetir una escena desde el menú. | **Hecho** |
| **Compartida dentro del motor** | Igual, pero todos la ven a la vez. | El servidor la empieza y la termina. | Momentos que cambian la partida: llega el jefe, se abre un camino. | **Hecho** |
| **Vídeo prerenderizado** | Un vídeo hecho con Kling, con subtítulos del juego encima. | Local o compartida, según el momento. | Lo que el navegador no puede dibujar: vínculos con los espíritus, finales de capítulo. | Diseñado (0.4) |

## Reproductor dentro del motor (hecho)

| Pieza | Archivo |
| --- | --- |
| Guiones (planos, textos, sonidos) | `game/scripts/shared/story_def.gd`, tabla `CUTSCENES` |
| Reproductor | `game/scripts/client/cinematics/cutscene.gd` |
| Franjas, subtítulos, rótulo y aviso de omitir | `game/scripts/client/hud.gd` (modo cine) |
| Enganche con la partida | `game/scripts/client/game_client.gd` |

Un guion es una lista de planos. Cada plano dice cuánto dura, de dónde a dónde va la cámara (posición
y punto al que mira), el subtítulo, quién habla, un rótulo opcional y un sonido opcional:

```gdscript
{"dur": 4.5, "from": [Vector3(0.4, 2.4, 3.6), Vector3(-5.2, 1.25, 1.2)], "to": [Vector3(-2.4, 1.6, 2.5), Vector3(-5.2, 1.15, 1.2)],
	"who": "yaxche", "text": "¡Despierta, alux! La selva te necesita…", "sound": "objetivo"}
```

Mientras suena: la interfaz de juego se oculta, entran las franjas, el personaje se queda quieto
(se sigue enviando entrada vacía al servidor, así la conexión no se corta) y la cámara de juego se
detiene. Al terminar u omitir, la cámara y los controles vuelven solos donde estaban. La cámara nunca
baja del terreno. Funciona igual en los tres niveles de calidad y no carga nada nuevo.

**Lo que todavía no hace** (está previsto y no implementado): animar personajes con `AnimationPlayer`
dentro del plano, fundidos entre planos y efectos propios por plano. Hoy un plano mueve la cámara,
pone texto y lanza un sonido.

## Reglas en cooperativo

Implementadas y probadas con bots y en navegador. El servidor guarda la cinemática en curso, los
segundos que le quedan y los votos; los clientes los reciben en el estado del mundo (así, quien se
reconecta sabe que la sala está en pausa) y en dos eventos: `cine` al empezar y `cine_end` al terminar.

| Regla | Local | Compartida |
| --- | --- | --- |
| Quién la empieza | El cliente | El servidor (evento con el tick en que empieza) |
| ¿Detiene la partida? | No. Sólo deja quieto a quien la ve. | Sí, para todos: enemigos en pausa y jugadores sin recibir daño mientras dura. |
| Omitir | Al instante, Enter o Esc. | Es un **voto** (Enter o Esc). Se omite cuando vota la mayoría de los conectados: 1 de 1, 2 de 2, 2 de 3, 3 de 4. En pantalla: «Enter · votar para omitir (1/3)». |
| Quién decide que terminó | El cliente | El servidor: al acabar su duración o al cumplirse el voto. Un cliente no puede terminarla por su cuenta. |
| Alguien entra a mitad | Ve la suya | No la ve: entra directo a la partida cuando termine. |
| Alguien se desconecta | — | Deja de contar para el voto. |
| Volver al juego | Cámara y controles donde estaban | Igual, y todos a la vez; los enemigos tardan unos 3 s en reaccionar. |
| Cuántas veces | La introducción, una por navegador | Una por sala: al jugar otra ronda no se repite. |

Nunca se usa una cinemática compartida en mitad de un combate normal: sólo en puntos seguros.

## Vídeo en el navegador (diseño)

- **Reproducción:** una capa `<video>` de la página, por encima del juego, controlada por el juego.
  Godot en navegador no reproduce bien vídeo propio; el navegador sí.
- **Formato:** MP4 H.264 a 720p y unos 1.5 Mbps (compatible con todo), con WebM como alternativa.
  Objetivo: menos de 5 MB por cada 20 s.
- **Carga diferida:** el vídeo no viaja con el juego; se pide cuando se acerca su momento.
- **Subtítulos:** los dibuja el juego (mismos textos que el guion), no van quemados en el vídeo.
- **Audio:** el del vídeo va apagado; suena el del juego, para respetar los volúmenes del jugador.
- **Si falla** (no carga, el navegador lo bloquea, conexión lenta): se reproduce la versión dentro
  del motor de la misma escena, o se salta con un rótulo. La partida nunca se queda esperando.
- **Omitir:** mismas reglas que arriba.

## Proceso con Kling

Ningún vídeo se genera sin tu aprobación previa de guion, storyboard y créditos.

| Paso | Qué se hace | Quién aprueba |
| --- | --- | --- |
| 1 | Guion: qué pasa y qué dice cada quien | Tú |
| 2 | Storyboard: planos, duración, movimiento de cámara | Tú |
| 3 | Decidir motor o vídeo | Dirección técnica |
| 4 | Reunir referencias **aprobadas** del alux, de Balam y del lugar | Tú (las referencias) |
| 5 | Preparar los primeros cuadros con el propio juego, para que el lugar sea el mismo | — |
| 6 | Escribir los prompts con continuidad entre planos | — |
| 7 | **Autorizar créditos** | Tú |
| 8 | Generar, elegir tomas, montar | Tú (la toma final) |
| 9 | Convertir para web, subtítulos y audio del juego | — |
| 10 | Probar en navegador, con el respaldo dentro del motor | — |

**Consistencia de personajes.** No se inventa un alux nuevo en cada vídeo. Las referencias salen de
los modelos del juego: las hojas de `art/previews/` y capturas del propio escenario. En Kling se
registran como sujetos reutilizables (uno para el alux, uno para Balam) y cada plano parte de un
primer cuadro hecho con el juego.

**Costo medido (12 nov 2026).** Con tu autorización se hizo una sola toma de prueba: 5 s a 1080p con
el modelo `kling-video-v3_0_turbo`, partiendo de un cuadro del propio juego. **Costó 50 créditos**;
quedan 2 659.

![Cuatro cuadros de la toma de prueba](img/kling-prueba-vinculo.jpg)

| Qué se vio | Resultado |
| --- | --- |
| Fidelidad a los personajes | Balam y el alux se mantienen iguales al modelo del juego (rosetas, ajorcas, penacho, vestido). |
| Fidelidad al lugar | La plaza, los pilares y la pirámide del juego se conservan; la cámara gira alrededor. |
| Acción pedida | El jaguar camina hacia el alux y baja la cabeza. El alux apenas reacciona. |
| Peso para web | El original son 9 MB (1080p). Convertido a 720p y 1.5 Mbps queda en 0.85 MB por 5 s: unos 4 MB para los 24 s. |

**Presupuesto de «El vínculo de Balam»** con este modelo: 24 s son unos 240 créditos por pasada.
Contando dos o tres tomas por plano para elegir, entre 500 y 750 créditos. Otros modelos (4.0, omni)
pueden costar distinto: no se han medido.

## Estado de cada cinemática

| Id | Título | Clase | Dónde ocurre | Estado |
| --- | --- | --- | --- | --- |
| `llamado` | El llamado | Local, motor | Al entrar por primera vez; se repite desde el menú | **Hecha** (4 planos, 19 s) |
| `sello` | El sello cede | Compartida, motor | La primera vez que el grupo abre el santuario | **Hecha** (2 planos, 7 s) |
| `vinculo_balam` | El vínculo de Balam | Vídeo (Kling) + respaldo en motor | Tras hablar con Chiich Yaxché | **Storyboard aprobado**; una toma de prueba hecha; producción en 0.4 |
| `guardian_despierta` | El Guardián Dormido despierta | Compartida, motor | Al entrar al patio del santuario | Planeada (0.3) |
| `pluma_de_jade` | La Pluma de Jade | Vídeo (Kling) + respaldo en motor | Al vencer al jefe | Planeada (0.4) |

## «El llamado» (hecha)

| Plano | Duración | Cámara | Texto |
| --- | --- | --- | --- |
| 1 | 5.0 s | Vista alta del claro, avanzando despacio | *Capítulo I · El Claro de los Aluxes* — «La selva del Mayab lleva tres noches sin cantar.» |
| 2 | 4.5 s | Orilla del cenote, bajando hacia el agua | «El agua del cenote amaneció oscura, y nadie se atreve a beberla.» |
| 3 | 5.0 s | Hacia el santuario sellado | «El santuario de los guardianes se cerró por dentro. Un sello que no es de este claro lo cubre.» |
| 4 | 4.5 s | Se acerca a Chiich Yaxché | **Chiich Yaxché:** «¡Despierta, alux! La selva te necesita… y yo ya me cansé de gritar.» |

Sólo se muestra sola la primera vez en cada navegador; después se puede repetir desde el menú.

## «El sello cede» (hecha)

| Plano | Duración | Cámara | Texto |
| --- | --- | --- | --- |
| 1 | 3.5 s | Hacia el portal del santuario, acercándose | «Cada alux en su altar, y el sello cede…» |
| 2 | 3.5 s | Sobre el lugar de la emboscada, bajando | «…pero quienes lo cuidaban ya no recuerdan a quién. ¡Los Olvidados despiertan!» |

Mientras dura, nadie se mueve, nadie ataca y nadie recibe daño.

## Storyboard: «El vínculo de Balam» (aprobado el 12 nov 2026; producción en 0.4)

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
4. Tu autorización de los créditos de producción (500–750 estimados). La toma de prueba ya está hecha.
5. El reproductor de vídeo del navegador (Alpha 0.4).

**Respaldo dentro del motor:** la misma escena en tres planos con los modelos del juego y el efecto
de transformación que ya existe. Se hará primero, así la escena existe aunque el vídeo no cargue.
