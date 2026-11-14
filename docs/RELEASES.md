# Versiones de ALUX

Qué lleva cada versión, qué se comprobó y cuál está publicada. Plan de las siguientes:
[ROADMAP.md](ROADMAP.md).

| Versión | Estado | Contenido |
| --- | --- | --- |
| Closed Alpha 0.1 | Publicada el 12 nov 2026; **sustituida por la 0.2**. Commit `12fadbe`: es el punto de rollback | Claro de los Aluxes jugable de 1 a 4, combate, emboscada, victoria y derrota, audio provisional, acceso por invitación |
| Closed Alpha 0.2 | Publicada el 12 nov 2026; **sustituida por la 0.2.1**. Commit `c28e32c`: es el punto de rollback | Introducción «El llamado», Chiich Yaxché con modelo propio y diálogo, primer objetivo narrativo, cinemáticas locales y compartidas con voto, progreso del capítulo en el perfil |

| Closed Alpha 0.2.1 | Publicada el 12 nov 2026; **sustituida por la 0.3**. Commit `94bb9c8`: es el punto de rollback | La 0.2 más las cinemáticas híbridas, «El sello cede» producida con Kling y los modelos de los personajes corregidos |

| Closed Alpha 0.3 | Publicada el 12 nov 2026; **sustituida por la 0.3.1**. Commit `93007a0`: es el punto de rollback | Jefe Nojoch Tuunich completo (tres fases, modelo definitivo, cinemáticas de despertar y liberación con Kling), Pluma de Jade y pista del Cenote |

| Closed Alpha 0.3.1 | Publicada el 13 nov 2026 (commit `cdf1543`): **es el punto de rollback de la 0.4** | La 0.3 con el audio arreglado (no sonaba nada), mezclador propio, música original, ambientes por zona, bandas sonoras de las cinemáticas, 50 efectos nuevos y prueba de sonido en el menú |

| Closed Alpha 0.4 | Publicada el 13 nov 2026 (commit `b27e4c1`): **es el punto de rollback de la 0.4.1** | Pantalla completa al pulsar JUGAR, personalizador 3D del alux, plaza social de Mérida (prototipo) con portal al Claro, primeros sonidos elegidos de oído |

| **Closed Alpha 0.4.1** | **Publicada** el 13 nov 2026 en <https://alux-beta.onrender.com> (commit `7e8fc5b`). Rollback: `b27e4c1` (0.4) | Pulido de la 0.4: plaza más ligera y viva, portal como menú del juego, guía de la pelea con Nojoch y su salida del santuario de un salto |

| Closed Alpha 0.5 | **Candidata, sin publicar** (rama de trabajo). Pendiente del visto bueno del dueño | Progresión RPG (nivel 1–10, Semillas de Jade, Puesto de Saberes, amuletos y gachapón), el santuario se abre al despertar Nojoch, plaza de Mérida rehecha y primera ruta del mundo abierto: el Camino a Motul |

## Publicación en la rama `beta`

La rama `beta` es lo único que Render despliega. Cada entrada dice qué commit lleva el código de
esa versión, qué se comprobó antes de publicarla y cómo volver a ella.

Para saber qué hay desplegado en este momento: `npm run beta:check -- <URL>` muestra el commit que
informa el servicio, y `--commit <hash>` exige que sea uno concreto.

## ALUX Closed Alpha 0.5 — Los Caminos del Mayab (candidata, sin publicar)

Nada de esto está en `beta`. Rollback cuando se publique: `7e8fc5b` (0.4.1).

| Qué | Dónde | Comprobado | Sin comprobar |
| --- | --- | --- | --- |
| Progresión RPG: nivel 1–10, XP `100+20(n−1)²`, Semillas de Jade, inventario, un amuleto equipado, Chispa I y Garras I, gachapón con garantía; todo en la API, idempotente | [RPG.md](RPG.md) | API 20 pruebas (memoria y PostgreSQL real); protocolo; equilibrio en niveles 1, 5 y 10; ciclo completo en navegador: jugar el Claro → subir de nivel → comprar un amuleto → equiparlo → +2 % de vida en la sala | Cifras con partidas reales |
| El santuario se abre al despertar Nojoch: los muros se hunden en 3,6 s, colisiones autoritativas, se cierran al dormirse | [BOSS.md](BOSS.md) | Simulación (550 885 comprobaciones), protocolo con 1, 2 y 4 jugadores, navegador | Fluidez con GPU; «El despertar» como vídeo |
| Plaza de Mérida rehecha: ciudad modular, mercado, vegetación, luz de atardecer, vendedores | [OPEN_WORLD.md](OPEN_WORLD.md) §13 | 91 llamadas de dibujo en alta y 75 en mínima en la llegada (antes 90 y 74); servidor de zonas | FPS con GPU; rótulos y nombres provisionales |
| Mundo abierto: el Camino a Motul (222 m al ENE), zonas seguras, 10 criaturas hostiles, descubrimientos, la misión de la cordelera, mapa con Izamal y Valladolid «próximamente» | [OPEN_WORLD.md](OPEN_WORLD.md) §14 | Servidor de zonas 11 de 11; navegador: plaza → arco → camino → misión → milpa → purificar → cartel de Motul → mapa → vuelta, con recompensas pagadas por la API real; carga con 32 aluxes: 11 % de un núcleo | Misión a medias no sobrevive a un reinicio del servidor; varios navegadores a la vez en el camino |

**Verificada sobre el commit exacto `76aa754` (14 nov 2026, copia limpia, una prueba cada vez, todo a
la primera):** API 20 (memoria) · catálogos 3 · equilibrio RPG 3 · simulación sin violaciones ·
servidor de mazmorras 17 · servidor de zonas 11 · audio 11 · vídeo 7 · flujo 15 + ciclo de
progresión · jefe completo 7 · cuatro navegadores 10 · pantalla completa 7 · personalizador 6 ·
plaza 5 · muros del santuario 6 · camino a Motul 9. Imagen de despliegue: la migración `rpg` se
aplica al arrancar (sólo crea tablas), 43 comprobaciones, 255 MB como máximo de 512 con 16 aluxes en
la plaza y una partida del jefe a la vez (360 MB contando los binarios cargados), 11 % de un núcleo,
persistencia tras reiniciar. Revisión previa superada; `beta` avanzaría de `7e8fc5b` sin reescribir
historia. Mismo servicio y mismo plan de Render: sin costos nuevos.

## ALUX Closed Alpha 0.4.1 — Pulido de lo publicado

Respuesta a la primera prueba del dueño en su ordenador. **Publicada el 13 nov 2026** con su visto
bueno: en `beta` está el commit `7e8fc5b`, el mismo sobre el que se hicieron todas las pruebas.
Rollback: en Render → `alux-beta` → Events → el despliegue de `b27e4c1` → Rollback.

**Antes de publicar, sobre `7e8fc5b` (copia limpia):** imagen de despliegue 25 comprobaciones más el
personalizador (6 de 6) y el camino completo (4 de 4) con navegadores contra la imagen; 247 MB como
máximo de 512 con 16 aluxes en la plaza y una partida del jefe a la vez (358 MB contando los binarios
cargados), 17 % de un núcleo; regresión completa a la primera (los trece bloques de abajo).

**En producción, tras desplegar (unos 4 minutos):** `beta:check` 13 de 13 con la versión `7e8fc5b` y
el perfil conservado; camino completo en navegador portal → personalizador → plaza → sala del Claro;
audio 8 de 8 y «El llamado» con su banda sonora; «El sello cede» como vídeo, omitida y con respaldo
del motor; jefe por protocolo con las tres fases (salto incluido: cae en x = 15,5) en 83 s.
**Sin comprobar:** FPS con tarjeta gráfica real, registros y memoria del servicio en Render, dos
personas a la vez en la plaza de producción, Firefox y Safari.

| Qué | Cambio | Comprobado | Sin comprobar |
| --- | --- | --- | --- |
| Rendimiento de la plaza | Geometría fundida en 11 mallas, sin luces puntuales, una sombra corta, calidad propia de la plaza y regulador de resolución ([perf_governor.gd](../game/scripts/client/perf_governor.gd)). De 235 llamadas de dibujo a 74–90 con un alux | Llamadas y primitivas en navegador; la prueba de dos navegadores pasó de 608 s a 103 s en la misma máquina | **FPS con tarjeta gráfica real**: aquí se dibuja por software. F3 en la plaza y en la mazmorra da FPS, llamadas, escala del 3D, lienzo y GPU |
| Rendimiento de la mazmorra | El mismo regulador: en alta y baja el 3D se mueve entre suelo y techo y se acota en pantallas de alta densidad (el lienzo se dibujaba a `devicePixelRatio` completo) | Regresión completa | Lo mismo: falta medir en un navegador real |
| Portal como menú del juego | Pantalla de título, menú principal con teclado, pantalla de carga hasta que el motor arranca; menú → mundo sin recargar la página | Selectores de las pruebas conservados; flujo, cuatro navegadores, pantalla completa y personalizador en verde | Firefox y Safari |
| Plaza más viva | Composición nueva; guía, tablón de misiones y puesto de saberes con F (muestra el progreso real; las mejoras, «próximamente»: sin compras, moneda ni cambios de base de datos); banderines, luciérnagas, aves y palomas | Servidor de zonas 7 de 7; plaza con dos navegadores 5 de 5 | Nombres y textos de los personajes son provisionales; la tienda necesita decisiones de diseño |
| Salida de Nojoch del santuario | Ya no camina: aviso con círculo donde cae, salto en arco sin colisiones y caída con empujón sin daño. Andando se atascaba hasta 5 s en 7 de 121 posiciones de salida simuladas, incluida la de reposo | Protocolo con 1, 2 y 4 jugadores (un aviso, un salto, una caída, duración fija); en navegador se vieron los estados y 7,9 m de altura | No hay captura con el guardián en el aire (el navegador de pruebas dibuja a 1–2 FPS) |
| Claridad de la pelea | Guía de la fase con pasos numerados y el activo resaltado, balizas sobre el objetivo del paso, «Sin efecto» en cada golpe inútil y qué hacer en su lugar | La prueba del jefe en navegador exige la guía en las tres fases y balizas en la fase 2 | Que un jugador nuevo la entienda: eso sólo lo dice una persona jugando |

**Regresión de la rama con todo integrado (13 nov 2026, una prueba cada vez, a la primera):** API 12 ·
catálogos 3 · simulación sin violaciones · servidor de mazmorras 17 · servidor de zonas 7 · audio 11 ·
vídeo 7 · flujo 15 · jefe completo 7 · cuatro navegadores 10 · pantalla completa 7 · personalizador 6 ·
plaza 5.

**No cambia:** base de datos, API, protocolo de zonas y servicios de Render. El protocolo de la
mazmorra añade dos estados del jefe al final de la lista (`leap_w`, `leap`) y tres eventos; cliente
y servidor se despliegan juntos. Rollback de la 0.4.1: `b27e4c1` (0.4).

## ALUX Closed Alpha 0.4 — El mundo empieza en una plaza

**Publicada el 13 nov 2026.** En `beta` está el commit `b27e4c1`: une la historia de `beta`
(`cdf1543`) con la candidata verificada `7c7ac6c` **sin cambiar ni un archivo de ésta** (mismo árbol
de Git, `75e0ed9`). Todo lo que sigue se comprobó sobre `7c7ac6c`.

**Rollback:** en Render → `alux-beta` → Events → el despliegue de `cdf1543` → Rollback (no
reconstruye). La 0.3.1 funciona con la base de datos de la 0.4: la migración sólo añade una columna
y amplía un límite; un tocado nuevo se vería como el pelo de siempre. Para cerrar sólo la plaza sin
volver atrás: variable `ALUX_ZONE=off` en el panel.

| Incremento | Estado | Documento |
| --- | --- | --- |
| Pantalla completa al pulsar JUGAR (Fullscreen API, preferencia guardada, botón discreto, Esc) | 7 comprobaciones en Chromium. Firefox y Safari sin probar | [FULLSCREEN.md](FULLSCREEN.md) |
| Personalizador 3D con el modelo real: 12 colores, 10 secundarios, 5 tonos de piel, 4 vestimentas, 7 tocados, 5 accesorios, 5 amuletos; cámara orbital; guardado y réplica | 6 comprobaciones en navegador y reglas en la API | [PERSONALIZADOR.md](PERSONALIZADOR.md) |
| Plaza social de Mérida (prototipo): servidor de zonas aparte, movimiento autoritativo, visibilidad por proximidad, portal al Claro | 7 pruebas con bots, 5 con dos navegadores, carga con 8 a 64 simulados. **Sin medir con navegadores reales.** Sin grupos, personaje de bienvenida ni vuelta desde la misión | [OPEN_WORLD.md](OPEN_WORLD.md) §9 y §13 |
| Sonido: los elegidos de oído (Balam, voz de Chiich Yaxché, golpes de Nojoch) y su mezcla | Aprobados provisionalmente para la beta. La mezcla no se ha oído dentro del juego | [AUDIO.md](AUDIO.md) |

**La imagen de Render, con el servidor de zonas** (`scripts/test-beta-image.sh`, contenedor limitado
a 512 MB como el plan actual):

| Qué | Resultado |
| --- | --- |
| Procesos | Proxy, portal, API, servidor de mazmorras y servidor de zonas; si uno cae, el contenedor se reinicia entero |
| Rutas | `wss://DOMINIO/ws` (mazmorras) y `wss://DOMINIO/zone` (plaza), por el proxy de siempre. Sin servicios ni variables nuevas en Render |
| Memoria en reposo | 236–304 MB según la pasada |
| Memoria con 16 aluxes en la plaza y una partida completa del jefe a la vez | Máximo 242 MB de 512; ningún reinicio por memoria |
| CPU en esa misma carga | 14 % de un núcleo de media (el plan da medio núcleo). Medido en esta máquina, no en Render |
| Plaza bajo esa carga | 16 de 16 conectados, 4,3 KB/s cada uno |
| `beta:check` contra la imagen | 13 de 13, con los dos pasos nuevos de la plaza; repetido tras reiniciar aplicación y base de datos |
| Costo | El mismo servicio y el mismo plan (`0.5c-512mb`) y la misma base de datos. Nada nuevo que contratar |

**Regresión sobre el commit exacto `7c7ac6c`** (copia limpia, una prueba cada vez): API 12 de 12 ·
catálogos 3 · simulación sin violaciones · servidor de mazmorras 17 · servidor de zonas 7 · audio 11 ·
flujo de playtest 15 · jefe completo 7 · pantalla completa 7 · personalizador 6, a la primera.
Tres necesitaron repetirse, y se cuenta por qué:

- **Cuatro navegadores (10 de 10 a la segunda):** «demasiadas reconexiones», el fallo conocido de
  cuatro juegos dibujando por software a la vez.
- **Vídeo de las cinemáticas (7 de 7 a la tercera):** dos fallos de tiempos distintos (2,6 s de
  preparación con límite de 2,5; un plano que el muestreo no llegó a ver).
- **Plaza (5 de 5 tras reordenar la prueba):** fallaba siempre en la copia limpia. Instrumentada:
  con el segundo navegador dibujando la plaza por software, el motor de la sala tardaba 297 s en
  arrancar (5,6 s cuando está solo; límite de la prueba, 300 s). La prueba cierra ahora ese
  navegador después de comprobar que ve irse al primero. No es un defecto del juego, pero **no se
  ha medido en ordenadores reales con dos pestañas abiertas**.

Contra la imagen definitiva, con navegadores reales por HTTPS/WSS a través de dos proxies: plaza con
dos jugadores 5 de 5, personalizador 6 de 6 y el camino completo 4 de 4. Memoria contando también
los binarios cargados (PSS): 331 MB en reposo, 350 MB tras esas pruebas, de 512.

**En producción, tras desplegar (`b27e4c1`, 13 nov 2026):**

| Qué | Resultado |
| --- | --- |
| Despliegue | Render construyó y cambió el tráfico en unos 4 minutos; `/healthz` informa `b27e4c1` |
| `beta:check` con invitación | 13 de 13: HTTPS, base de datos, nada abierto sin sesión, descarga (12,2 MB), 28 pistas de audio, `wss://…/ws` y `wss://…/zone`, sala con reconexión, plaza (10 estados/s, aforo 32). El perfil conserva Sello del Claro y Pluma de Jade |
| Camino completo en navegador (`e2e/beta-plaza.ts`) | Portal → personalizador 3D (guardado) → plaza de Mérida con ese aspecto, andando y con música → portal → sala del Claro con el aspecto y con sonido |
| Audio en la salida del navegador | Normal 8 de 8 (ambiente −27,7 dBFS, chispa −9,6 dBFS de pico), bloqueo simulado 2 de 2, «El llamado» con su banda sonora y omisión |
| Cinemáticas | «El sello cede» como vídeo con banda sonora, omisión a los 2,4 s y respaldo del motor |
| Jefe por protocolo | Tres fases y liberación en 82 s, pista del Cenote anotada |

**No comprobado:** registros, memoria y reinicios reales del servicio (sólo se ven en el panel de
Render); dos personas viéndose en la plaza de producción (sólo hay una invitación de verificación;
comprobado contra la imagen); navegadores con tarjeta gráfica, Firefox y Safari; personas reales.

**Qué cambia respecto a la 0.3.1 fuera del cliente:** una migración sólo aditiva (columna `look` y
límite del tocado más amplio; la 0.3.1 sigue funcionando con la base nueva), el ticket de sala
lleva el aspecto, endpoints nuevos de la API para la plaza, y un proceso nuevo (servidor de zonas)
que la imagen de Render **todavía no arranca**. El servidor de mazmorras sólo cambia en que acepta
el aspecto del ticket y lo relee de la API cuando el jugador se cambia.

## ALUX Closed Alpha 0.3.1 — El claro vuelve a oírse

| | |
| --- | --- |
| **Estado** | **Publicada** el 13 nov 2026. Candidata `4f47832`, aprobada ese día |
| **Commit publicado en `beta`** | **`cdf1543`**: el siguiente a la candidata; sólo añade el registro y el nombre de la versión en el juego. Es el que informa `/healthz` |
| **Código de la versión** | `963630b`; la candidata `4f47832` le añade el registro, la documentación y el paso de audio de `beta:check` (el juego no cambia). No incluye nada de la Alpha 0.4 |
| **Rollback** | Publicar en `beta` el commit `93007a0` (0.3). Sin migraciones ni cambios de infraestructura: los datos sirven en los dos sentidos |
| **Qué cambia respecto a la 0.3** | Cliente del juego (audio), archivos de sonido, pruebas y documentación; en la API, sólo campos nuevos en la telemetría de sesión. **Sin cambios** en el servidor de juego, el protocolo, `render.yaml`, la imagen ni la base de datos |

### El defecto que corrige

Un jugador entró a la 0.3 y no oyó nada. Era cierto y venía desde la 0.1: en la exportación web el
bus maestro del motor quedaba desconectado de la salida del navegador porque los buses se creaban
en ejecución. Las pruebas no lo veían porque sólo comprobaban que el juego «reproducía». Causa,
evidencia y corrección: [AUDIO.md](AUDIO.md).

### Novedades

| Novedad | Detalle |
| --- | --- |
| El juego suena | Buses definidos en `default_bus_layout.tres`. Medido en la salida del navegador: de silencio absoluto a ambiente y música a unos −27 dBFS con picos de −6 dBFS en las habilidades |
| Mezclador propio | `alux-audio.js`: bucles sin corte, fundidos de música, capas de ambiente, atenuación de la música bajo los golpes grandes y en las cinemáticas, limitador y medidor de la salida. Buses: Master, Music, Ambience, SFX, UI, Cinematics y Voice |
| Activación y diagnóstico | El audio arranca con el primer gesto; aviso en pantalla si el navegador lo bloquea o si el volumen está a cero; **Menú → Probar sonido** mide la señal y lo dice; la telemetría guarda si la sesión llegó a sonar |
| Música original | Diez piezas en estéreo: claro, exploración, peligro, emboscada, las tres fases de Nojoch Tuunich, liberación, victoria y el primer tema del lobby |
| Paisaje sonoro | Diez capas de ambiente que cambian con la zona: selva, aves, insectos, viento, agua y cenote, ruinas y energía del santuario, brasero |
| Cinemáticas con sonido | «El llamado», «El sello cede», «El despertar» y «La liberación» tienen banda sonora propia (efectos y música por separado), la misma con vídeo o con el motor; al omitir se funde |
| Banco de efectos | 50 efectos nuevos: pasos por material, variantes de chispa y garras, Balam, criaturas, guardián, interfaz y avisos de compañeros |
| Ajustes | Volúmenes de interfaz y cinemáticas; el menú cabe en pantallas bajas |
| Playtest | Métricas del combate por jugador y hoja de observación ([PLAYTEST.md](PLAYTEST.md)) |

Todo el audio es síntesis propia; no se usa material de terceros ([ASSETS_AUDIO.md](ASSETS_AUDIO.md)).

### Comprobado (en local, sobre una copia limpia de `963630b`)

| Comprobación | Resultado |
| --- | --- |
| API | 11 de 11 |
| Simulación compartida | 427 840 comprobaciones, sin violaciones |
| Servidor con bots | 17 de 17 |
| **Audio en navegador** (`npm run test:audio`, midiendo y grabando la salida real) | 11 de 11: suena al entrar, la habilidad se oye por encima sin recortar, «Probar sonido» confirma señal, silenciado es silencio absoluto con aviso, música a cero deja el ambiente, pestaña oculta calla y vuelve, bucles exactos sin reinicios, bloqueo de autoplay (simulado) con aviso y arranque al primer clic, banda sonora de la introducción y su omisión |
| Cinemáticas en vídeo (`npm run test:cine`) | Pasa (7 comprobaciones) |
| Combate completo en navegador (`npm run test:boss`) | Pasa a la segunda: cada fase suena con su música y las dos cinemáticas de Kling llevan su banda sonora. La primera vez falló donde ya había fallado alguna vez antes de esta versión: la jugadora del navegador, a 1–2 FPS por software, no llegó andando hasta el guardián en la fase 3 |
| Flujo de playtest (`npm run test:flow`) | 15 pasos, con el audio medido |
| Cuatro navegadores (`npm run test:e2e`) | 10 de 10 (sincronía del combate, reconexión, quinto jugador rechazado, identidad tras recargar) |
| Manifiesto de audio (`python3 art/audio/manifiesto.py --check`) | 147 archivos declarados, ninguno sin declarar |
| Revisión previa de publicación (`npm run beta:preflight`) | Superada sobre `963630b`: sin secretos, migraciones sin cambios, vídeos completos |
| Archivos de audio servidos (`npm run beta:check`, paso nuevo «Audio del juego») | En local: mezclador y 28 pistas con su tamaño y tipo `audio/mpeg`. Contra producción dice, como debe, que la 0.3 no trae mezclador |

### Peso

Descarga inicial: 10,58 MB con Brotli (11,25 MB en la 0.3: la música y los ambientes ya no van
dentro del juego). Audio bajo demanda: 2,8 MB al entrar y hasta 12,3 MB si se oye todo. Detalle y
memoria en [AUDIO.md](AUDIO.md).

### Antes de publicar (13 nov 2026, sobre el commit exacto `cdf1543` en una copia limpia)

| Comprobación | Resultado |
| --- | --- |
| Imagen Docker definitiva (`scripts/test-beta-image.sh`) | Construida y verificada: migraciones, invitación, HTTPS y WSS a través de dos proxies, descarga del juego (9,1 MB con Brotli), **mezclador y 28 pistas de audio servidas**, partida, reconexión, métricas, persistencia tras reiniciar los contenedores y límite de intentos. 270 MB de memoria de 512 |
| Buses de Godot | `default_bus_layout.tres` con Master, Music, Ambience, SFX, UI, Cinematics y Voice; ninguna llamada a `AudioServer.add_bus()` en el código |
| Archivos de audio | 119 efectos y 28 pistas del mezclador con sus 3 manifiestos; `manifiesto.py --check` sin archivos sin declarar |
| Regresión | API 11 de 11 · simulación sin violaciones · servidor 17 de 17 · audio en navegador 11 de 11 · flujo de playtest 15 pasos · jefe completo 7 pasos (a la primera) · vídeo 7 comprobaciones · cuatro navegadores 10 de 10. Las pruebas de vídeo y de cuatro navegadores fallaron mientras otro proceso mío cargaba la máquina (tiempos de preparación y reconexiones) y pasaron al repetirlas con la máquina en calma |
| Sin duplicar audio en las cinemáticas | Con banda sonora, el efecto por plano no se dispara; la prueba de audio comprueba que la escena arranca como mucho una pista de efectos y una de música |
| `beta:preflight` | Superada. `beta` avanzó de `93007a0` a `cdf1543` sin reescribir historia; nada de la Alpha 0.4 |

### Comprobado en el servicio real (13 nov 2026, `cdf1543` en `beta`)

| Comprobación contra <https://alux-beta.onrender.com> | Resultado |
| --- | --- |
| `npm run beta:check` con invitación y `--commit cdf1543` | 11 de 11: HTTPS, versión desplegada `cdf15431ea0e`, nada abierto sin sesión, descarga (12,0 MB transferidos), **audio: mezclador y 28 pistas**, `wss://`, sesión, guardado (el perfil conserva el Sello del Claro y la Pluma de Jade de la 0.3), partida a 15 estados/s y 34 ms, reconexión y métricas |
| **Audio en navegador real, midiendo la salida** (`tests/e2e/audio-probe.ts`) | 11 de 11. Al entrar: ambiente y música a −28,5 dBFS de media. Chispa de jade: pico de −6,4 dBFS, sin recortar. «Probar sonido» confirma señal. Volumen general a cero: silencio absoluto y aviso. Música a cero: queda el ambiente. Pestaña oculta: silencio; al volver, suena. Bucles exactos. Audio bloqueado (simulado): silencio y aviso hasta el primer clic. Introducción con su banda sonora (−23,4 dBFS) y omisión |
| Cinemáticas (`tests/e2e/beta-cine.ts`: ver, omitir, sin vídeo) | Los 10 vídeos se descargan; «El sello cede» se ve como vídeo con su banda sonora (−14 dBFS) y sin restos al terminar; Enter la omite a los 2,5 s y la banda sonora para; con las descargas de vídeo cortadas se ve con el motor **con la misma banda sonora, una sola vez** |
| Sesión completa por protocolo (`npm run beta:boss -w @alux/tests`) | Emboscada, las tres fases (una derrota en la fase 3, retomada desde su punto de control), liberación, Pluma de Jade (ya la tenía: no se duplica), pista del Cenote. 47 ms de latencia media (máx. 96), 14,9 estados/s, sin cortes |

### Sin comprobar

- **Registros, memoria y reinicios del servicio:** sólo se ven en el panel de Render. Desde aquí
  consta que respondió sin cortes durante todas las pruebas (unos 25 minutos) y que la misma imagen
  usa 270 MB de 512 recién arrancada.
- **Calidad artística del audio: no está aprobada.** Los efectos y la música sintéticos quedan
  aceptados provisionalmente para pruebas; falta la evaluación de personas.
- «El despertar» y «La liberación» como vídeo con su banda sonora se comprobaron en local, no
  contra producción (allí la sesión completa fue por protocolo).
- **Nadie ha escuchado esta versión.** Las pruebas miden que hay señal, su nivel y que no recorta;
  no dicen si suena bien. Las grabaciones de la salida del navegador quedan para oírlas.
- Chrome, Edge, Firefox y Safari reales, con tarjeta gráfica y con cuatro personas.

## ALUX Closed Alpha 0.3 — El Guardián Dormido

| | |
| --- | --- |
| **Código de la versión** | `44f99b77dafb` (rama candidata `release/alpha-0.3-rc1`), aprobado para publicar el 12 nov 2026 |
| **Commit publicado en `beta`** | El siguiente a ese: añade este registro y el nombre de la versión en el juego y en el portal. Es el que informa `/healthz` |
| **Rollback** | Publicar en `beta` el commit `94bb9c8` (0.2.1). Sin migraciones: los datos sirven en los dos sentidos |
| **Qué cambia respecto a la 0.2.1** | Sólo juego, arte, pruebas y documentación (171 archivos). **Sin cambios** en infraestructura, `render.yaml`, migraciones ni dependencias |

Aprobada para pruebas con jugadores reales: el combate del jefe, sus dos cinemáticas y la Pluma de
Jade **no los ha jugado todavía ninguna persona**. Diseño completo del jefe: [BOSS.md](BOSS.md).

Créditos de Kling de esta versión: las generaciones declararon 508 (280 + 228) y el saldo bajó 488
(2 375 → 1 887). La diferencia de 20 está en dos vídeos cuya respuesta no informó del coste y se
contaron a 32; uno costó menos. Vale el saldo. Registro: `art/cinematicas/jefe/kling/PRODUCCION.md`.

| Novedad | Detalle |
| --- | --- |
| Nojoch Tuunich, combate completo | Tres fases cooperativas decididas por el servidor. **Olvido** (patio): purificar criaturas junto a él enciende los glifos del pecho. **Furia** (explanada): columnas que despierta el alux, lluvia de piedra, embestida que se corta contra una columna, anclas, cadenas de jade y corazón expuesto a las garras de Balam. **Recuerdo**: glifos de memoria y contacto de todos a la vez |
| Transición de fase | El guardián cruza el portal andando; nadie se teletransporta. Punto de control en cada fase: una derrota retoma la fase alcanzada |
| Modelo definitivo | Caliza cálida, rostro con tres expresiones (triste, dolor contenido, serena), grietas que cambian con el Silencio, glifos que se encienden; animaciones revisadas en movimiento. 11 006 triángulos, 30 huesos |
| Pluma de Jade | Objeto ancestral persistente: sale en la liberación, la entrega el servidor una vez por jugador, aparece en el perfil y abre la pista del Cenote hablando con el guardián liberado. No desbloquea transformaciones |
| Cinemáticas del jefe | «El despertar» (16 s) y «La liberación» (12 s), compartidas, con voto para omitir, versión del motor de respaldo y vídeos de Kling |
| Presentación | Escenario del combate (anclas, columnas, cadenas, lluvia, carril de embestida, glifos, haces de contacto), barra con segunda barra, objetivos y pistas por momento, 31 sonidos, música por fase, sacudida de cámara regulable (en cero si el sistema pide menos movimiento) |
| Secuelas de «El sello cede» | El santuario conserva lo que mostró el vídeo: enredaderas, grietas y marcas que se asientan |
| Otros | Enter en un panel de victoria sigue la aventura (otra ronda se pide con su botón); al liberar al guardián, las criaturas corrompidas cercanas también recuerdan |

![Las fases 2 y 3 y el guardián liberado, en el juego](img/jefe-fases.jpg)

Protocolo: el estado del jefe (`b`) crece de 14 a 24 campos y hay eventos `boss` nuevos; la historia
de la sala gana dos banderas; llegan los avisos `story` `freed` y `clue`. Compatible hacia atrás: un
cliente anterior ignora lo que no conoce. Recompensa nueva en el catálogo (`pluma_de_jade`).
**Sin migraciones de base de datos**: usa las tablas de recompensas y misiones que ya existían.

### Comprobado (en local)

| Comprobación | Resultado |
| --- | --- |
| API | 11 de 11 (nueva: la Pluma de Jade se da una vez por jugador aunque la gane en varias salas, queda en su perfil y no desbloquea formas) |
| Simulación compartida | 427 840 comprobaciones, sin violaciones |
| Servidor con bots | 17 de 17. El combate completo con 1, 2 y 4 jugadores: las tres fases, mensajes inventados ignorados, nadie se teletransporta en la transición, reintento desde la fase 2, una caída de la sala y un jugador lejos que no bloquean el ritual, una sola petición de Pluma de Jade para todos, pista del Cenote única, cada cinemática una vez por sala y el combate empezando donde acaba «El despertar» |
| Navegador, combate completo (`npm run test:boss`) | Una jugadora en un navegador real y tres compañeros: las tres fases, las dos cinemáticas, panel «Capítulo I completado», Pluma de Jade guardada en el perfil y pista del Cenote. La jugadora toca al guardián manteniendo F |
| Navegador, resto | Flujo de playtest (15 pasos, con el despertar y su cinemática), cuatro navegadores (10 pasos: sincronía, reconexión, quinto jugador rechazado) y vídeo (6 casos: vídeos reales, archivo ausente o corrupto, descarga lenta, vídeo atascado y omitir): pasan |
| Vídeos | Los diez clips del guion están en el manifiesto, en MP4 y WebM; las dos cinemáticas del jefe se ven como vídeo en el navegador y, sin vídeo, con el motor |

### Rendimiento medido

| Qué | Medida |
| --- | --- |
| Servidor de juego durante el combate | 107 MB de memoria residente y 4 % de CPU de media (13 % de pico) con **tres salas a la vez** (1, 2 y 4 jugadores) peleando las tres fases. Sin crecimiento durante la prueba |
| Coste del jefe en el motor (calidad alta, con sombras) | El modelo: unas 27 llamadas de dibujo y 33 000 triángulos dibujados más (11 006 por pasada). El escenario del combate: otras 20–25 llamadas en la fase 2 y unas 10 en la 3. La pluma: 30 |
| Escenas completas (calidad alta) | Fase 1: 270 llamadas · fase 2: 295–304 · fase 3: 282 · liberado: 88 |
| Navegador de pruebas (render por software, calidad mínima, cuatro jugadores) | 309 llamadas de dibujo al final del combate; 1–3 FPS, como el resto del juego en este entorno: **no es representativo** de un equipo con tarjeta gráfica |
| Carga del juego en el navegador de pruebas | 8–12 s hasta estar jugando |
| Descarga | Cliente: 9.7 MB con Brotli (8.2 MB en la 0.2; la diferencia son los sonidos y el modelo). Vídeos del jefe: 3.7 MB más en MP4 o 2.2 MB en WebM, en segundo plano |

### Rollback

Volver a la 0.2.1: publicar en `beta` el commit `94bb9c8`. Los datos son compatibles en los dos
sentidos (no hay migraciones); quien ya tenga la Pluma de Jade la conserva en la base de datos
aunque la 0.2.1 no la muestre.

### Comprobado en el servicio real (12 nov 2026, commit `93007a0` en `beta`)

Antes de publicar se repitió la regresión completa en una copia limpia del commit: API 11 de 11,
simulación sin violaciones, servidor 17 de 17, combate completo en navegador, flujo de playtest,
vídeos y cuatro navegadores (este último falló dos veces con la máquina de pruebas saturada
—las páginas se quedaban congeladas más de 15 s y se reconectaban— y pasó a la tercera con la
máquina en calma; el fallo no se reprodujo y no afecta al jefe). `beta:preflight` superado.
`beta` avanzó de `94bb9c8` a `93007a0` sin reescribir historia.

| Comprobación contra <https://alux-beta.onrender.com> | Resultado |
| --- | --- |
| `npm run beta:check` con invitación y `--commit 93007a0` | 10 de 10: HTTPS, versión desplegada `93007a013672`, nada abierto sin sesión, descarga (12.7 MB transferidos), `wss://` que rechaza tickets falsos, sesión con invitación, guardado, partida (15 estados/s, 30 ms), reconexión y métricas |
| Sesión completa por protocolo (`npm run beta:boss -w @alux/tests`) | Una jugadora sola: emboscada a los 9 s, «El sello cede», fase 1 a los 21 s, «El despertar», fase 2 a los 61 s, fase 3 y liberación a los 74 s, «La liberación», **Pluma de Jade guardada en el perfil**, pista del Cenote anotada. 54 ms de latencia media (máx. 66), 14.9 estados/s, sin cortes |
| Cinemáticas en un navegador (`tests/e2e/beta-cine.ts`: ver, omitir, sin vídeo) | Los 10 vídeos se descargan (6.35 MB, caché inmutable de un año); «El sello cede» se ve como vídeo; Enter la omite a los 2 s; con las descargas cortadas se ve con el motor y la partida sigue |
| **Audio** (`tests/e2e/audio-probe.ts`, salida real del navegador) | **No suena nada**: la grabación de la salida es silencio absoluto aunque el juego «reproduce» música y efectos. Es el defecto que comunicó el jugador; causa y corrección en [AUDIO.md](AUDIO.md) (Alpha 0.3.1) |

**Sin comprobar:** el combate con personas (ritmo, dificultad, si las pistas bastan) —**no hay
ninguna prueba con cuatro personas reales**—; con tarjeta gráfica, en Safari o Firefox; «El
despertar» y «La liberación» reproducidas como vídeo desde producción (la sesión completa fue por
protocolo; en navegador se comprobó que los siete clips se descargan y, en local, que se ven). El
uso de memoria y los reinicios del servicio sólo se ven en el panel de Render: desde aquí consta
que respondió sin cortes durante todas las pruebas y que la misma imagen arranca con 272 MB de 512.

## ALUX Closed Alpha 0.2.1

| | |
| --- | --- |
| **Código de la versión** | `e9a51c1bd2b3` (rama candidata `release/alpha-0.2.1-rc1`) |
| **Commit publicado en `beta`** | El siguiente a ese: añade este registro y el nombre de la versión en el juego y en el portal. Es el que informa `/healthz`. |
| **Fecha** | 12 de noviembre de 2026 |
| **Autorizada por** | El dueño del proyecto, el 12 de noviembre de 2026 |
| **Qué añade a la 0.2** | Sistema cinematográfico híbrido (vídeo en el navegador con respaldo del motor, fases de preparación y reanudación, fundidos), «El sello cede» producida con Kling (3 planos, 10 s, 2.6 MB) y los tres personajes con los hilos de sus prendas corregidos. |
| **Qué no lleva** | El jefe Nojoch Tuunich ni las secuelas visibles del sello en el santuario: son de la Alpha 0.3 y siguen en la rama de trabajo. |
| **Base de datos** | Sin cambios: no hay migraciones nuevas. |
| **Recursos** | Los mismos dos; no se crea ninguno. |

**Comprobado sobre el código de la versión antes de publicar:** API (10 de 10), simulación (427 840
comprobaciones sin violaciones), servidor con bots (14 de 14), vídeos reales de Kling en un navegador,
cinco casos de fallo del vídeo, flujo completo en navegador (14 pasos), cuatro navegadores (10 pasos,
con los vídeos presentes) y la revisión previa, que ahora exige que los vídeos del manifiesto sean los
definitivos: 3 declarados y presentes, ninguno de prueba.

**Imagen desplegable:** verificada en local con los vídeos en el commit `bc353a7`. Entre ese commit y
el de esta versión sólo cambian tres modelos, dos retratos, guiones de arte, documentación y pruebas;
no se pudo repetir la construcción sobre el commit exacto porque el registro de imágenes base limitó
las peticiones desde el entorno de pruebas. Render construye la suya y, si fallara, deja la 0.2 en
servicio.

**Volver a la 0.2:** en Render → `alux-beta` → **Events** → el despliegue del commit `c28e32c` →
**Rollback**; o, desde Git, `git push origin c28e32c42925ae3c27b73b763772c84df8709a04:beta --force-with-lease`.
La base de datos no necesita nada: el esquema es el mismo. Detalle en [beta.md](beta.md), sección 9.

**Comprobado después de desplegar, contra <https://alux-beta.onrender.com>:**

| Comprobación | Resultado |
| --- | --- |
| Versión en servicio | `/healthz` informa `94bb9c888bb041dd0491a924eee45b45f537ff4d`; base de datos respondiendo |
| HTTPS, cabeceras y cierre sin sesión | Pasa |
| WSS | `wss://alux-beta.onrender.com/ws` abre y rechaza tickets falsos |
| Invitación, guardado, métricas | Pasa |
| Partida por WebSocket | 15 estados por segundo, latencia de 30 ms, reconexión tras un corte en el mismo sitio |
| Carga de vídeo | Los tres vídeos se sirven con 200 y caché de un año (`immutable`): 2.63 MB en MP4; el manifiesto, con revalidación |
| Reproducción en navegador real | «El sello cede» pausa la sala y se ve **como vídeo**, los tres planos, durante 8.9 s; la partida sigue con la emboscada y el santuario abierto |
| Omisión | Enter a mitad del vídeo la termina a los 2.5 s y la partida sigue |
| Respaldo | Con las descargas de vídeo cortadas, la escena se ve con el motor (9.3 s), los tres fallos quedan registrados y la partida sigue |
| Introducción | «El llamado» se reproduce al entrar y se omite con Enter |
| Ciclo completo de un jugador | Pasa: carga (17.5 s), audio, menú, altar, emboscada, derrota, reintento y salida |

![La beta publicada reproduciendo el plano 2 de Kling](img/beta-021-sello.jpg)

**Sin comprobar en el servicio:** de dos a cuatro jugadores a la vez (sólo hay una invitación de
comprobación), los registros de Render (no hay acceso desde aquí; el servicio responde y no se
reinició durante las pruebas), Safari, Firefox y cualquier navegador con tarjeta gráfica.

**Etiqueta de versión:** `alpha-0.2.1` (`94bb9c8`) está creada en local y **no se pudo subir**: el
servicio de Git de este entorno sigue rechazando las etiquetas. Para crearla:

```bash
git tag -a alpha-0.2.1 94bb9c888bb041dd0491a924eee45b45f537ff4d -m "ALUX Closed Alpha 0.2.1"
```

```bash
git push origin alpha-0.2.1
```

## Contenido de la 0.2.1 — «El sello cede» con Kling

La primera cinemática producida con Kling, integrada sobre el sistema del incremento 1.
Producción completa: [art/cinematicas/sello/kling/PRODUCCION.md](../art/cinematicas/sello/kling/PRODUCCION.md).

![Los tres planos dentro del juego, con sus subtítulos](img/sello-kling-en-juego.jpg)

| Novedad | Detalle |
| --- | --- |
| «El sello cede» en vídeo | 10 s en tres planos (la barrera reacciona, el sello se rompe, algo despierta), en el tratamiento enriquecido: misma arquitectura del juego con luz, materiales y partículas de cine. 2.6 MB en MP4, 2.0 MB en WebM |
| Dos tratamientos | También se produjo el fiel al juego, para comparar; está guardado y se puede cambiar sustituyendo tres archivos |
| Guion del motor | Mismos tres planos y cámaras, como respaldo. El portal se abre a la vista en el plano 2 y al volver ya está abierto |
| Reloj real | La escena se mide con el reloj y no sumando cuadros: un navegador lento ya no pierde el último plano |
| Decodificación bajo demanda | Los vídeos se descargan al entrar, pero su decodificador se crea justo antes de la escena y se libera al terminar |
| Créditos | 284 de los 500 autorizados; saldo 2 375 |

| Comprobación (en local) | Resultado |
| --- | --- |
| API, simulación, servidor con bots | 10 de 10 · sin violaciones · 14 de 14 |
| Vídeos reales de Kling en un navegador | Pasa: los tres planos se ven como vídeo con sus subtítulos, la escena dura lo que su guion, no hay fallos registrados y se vuelve al juego con el santuario abierto y la emboscada |
| Casos de fallo (vídeos de prueba) | 5 de 5: reproducción, archivo ausente y corrupto, descarga lenta, vídeo atascado, omitir a mitad; al terminar no queda ningún decodificador abierto |
| Flujo completo (un navegador y tres bots) | Pasa, con la escena compartida y su voto |
| Cuatro navegadores (movimiento, combate, reconexión) | Pasa, con los vídeos reales presentes |
| Cuatro navegadores viendo la escena (`test:cine-coop`) | **Inestable en este entorno.** Con el incremento 1 pasó dos veces seguidas; con esta versión, en una ejecución los cuatro llegaron a la escena (vídeo, vídeo, motor, motor) y en tres la prueba se agotó **antes** de la escena, al no conseguir parar a los cuatro personajes sobre sus altares a 1 cuadro por segundo. Hay que repetirla con tarjeta gráfica |
| Imagen desplegable (commit `bc353a7`, en local) | Se construye con los vídeos dentro y pasa sus comprobaciones. Sirve los vídeos con caché de un año y el manifiesto con revalidación; 197 MB de memoria recién arrancada, de 512 |
| Descarga | 2.63 MB más (MP4) por jugador, en segundo plano y con prioridad baja; el juego no espera por ella |

**Un problema encontrado y corregido:** con los tres vídeos reales precargados como elementos de vídeo
vivos, la prueba de cuatro navegadores dejó de pasar (los personajes no llegaban a su destino). Sin
el manifiesto, pasaba. Por eso la decodificación es ahora bajo demanda; con el cambio vuelve a pasar.
Es una medición sin tarjeta gráfica, pero apunta a un costo real en equipos modestos.

**Sin comprobar:** con tarjeta gráfica y con personas; Safari y Firefox; cuatro personas viendo la
escena a la vez; nada de esto en Render (la beta lleva la 0.2, sin estos vídeos).

## Contenido de la 0.2.1 — cinemáticas híbridas

Kling pasa a ser obligatorio en las cinemáticas narrativas ([CINEMATICS.md](CINEMATICS.md)). Este
incremento construye todo lo necesario para reproducir sus vídeos sin arriesgar la partida. **No
incluye ningún vídeo de Kling ni gastó créditos**: el manifiesto de vídeos está vacío y el juego se
ve igual que en la 0.2 hasta que se apruebe el primero.

| Novedad | Detalle |
| --- | --- |
| Vídeo en el navegador | El motor no reproduce MP4 ni WebM en la web, así que los reproduce el navegador sobre el juego, dirigido por un puente (`cine-video.js` + `video_bridge.gd`). Manifiesto, precarga, caché, subtítulos, sonido sólo tras interacción. |
| Respaldo por plano | Cada plano de vídeo tiene debajo el plano del motor. Si el vídeo falta, está roto, no llega a tiempo o se atasca, se ve el del motor sin detener nada. |
| Fases compartidas | `PREPARING → PLAYING → RESUMING`. El servidor pausa la sala, espera a los clientes (5 s como máximo), da la orden de inicio a todos, cuenta votos y deja 1 s de pausa sin daño al volver. |
| Reconexión | Quien vuelve o llega a mitad recibe la fase y el punto por el que va. |
| Transiciones | Fundido a negro al entrar y al salir; la cámara vuelve a su sitio sin que se vea el salto. |
| Métricas | Cada sesión informa de cuántas cinemáticas vio como vídeo o con el motor y qué falló. |
| Referencias para Kling | Hojas de personaje del alux, Balam y Chiich Yaxché (`art/referencias/`) y cuadros clave de «El sello cede» sacados del juego (`art/cinematicas/sello/`). |
| «El sello cede» | Storyboard definitivo de 3 planos y 10 s, prompts y presupuesto, **pendientes de aprobar**. El plano 2 de la versión del motor tenía un árbol delante: corregido. |

Cambios de protocolo (compatibles: un cliente que no conteste sólo retrasa el inicio 5 s): mensaje
`cine_ready`, evento `cine_prep`, campo `at` en `cine` y un valor más en el estado del mundo.
Sin migraciones.

| Comprobación (en local, con vídeos de prueba generados sin Kling) | Resultado |
| --- | --- |
| API | 10 de 10, con las métricas de cinemáticas |
| Servidor con bots | 14 de 14. Nuevas: preparación, inicio compartido, pausa en las tres fases, voto sólo durante la reproducción, reanudación; quien se va no bloquea, quien vuelve o llega se engancha y nada se duplica |
| Vídeo en un navegador (`npm run test:cine`) | 5 de 5: reproducción con subtítulos y vuelta al juego; archivo ausente y corrupto; descarga que no llega; vídeo atascado a mitad; omitir durante el vídeo |
| Cuatro navegadores en una sala (`npm run test:cine-coop`) | Pasa: dos con vídeo, uno con archivos rotos, uno con la descarga colgada. Todos reciben la orden de inicio, cada uno la ve con lo que tiene y los cuatro siguen jugando |
| Flujo completo y cuatro navegadores de siempre | Pasan |
| Rendimiento en juego (render por software, 640×360) | Sin cambio: 6.9 FPS en mínima y 4.8 en baja (6.7 y 4.7 antes) |
| Durante la escena | Con vídeo el juego no dibuja el mundo: 16–19 cuadros/s de su bucle frente a 5–5.5 con la escena del motor, en el mismo equipo |
| Imagen desplegable (commit `8bc476a`, en local) | Se construye con los archivos nuevos y pasa sus comprobaciones (migraciones, invitaciones, HTTPS/WSS, partida, reconexión, persistencia). Sirve el puente y el manifiesto con revalidación, y los vídeos con caché de un año |
| Descarga | El puente pesa 13 KB. Los vídeos se piden aparte y sólo en un formato; objetivo ~2 MB para los 10 s de «El sello cede» (medido: 0.85 MB por 5 s a 720p) |

![Vídeo de prueba (un patrón generado en local, no es Kling) reproduciéndose sobre el juego, con franjas, subtítulo y aviso de omitir](img/cine-video-prueba.jpg)

**Sin comprobar:** con tarjeta gráfica y con personas; Safari y Firefox (la prueba usa Chromium);
sonido dentro de un vídeo (los de prueba son mudos); el voto con cuatro navegadores a la vez (sin GPU
van a 1–2 cuadros por segundo y la escena acaba antes de que lleguen los votos: está cubierto con
bots); la reconexión a mitad de escena en un navegador (cubierta con bots); nada de esto en Render
(no está publicada).

## ALUX Closed Alpha 0.2

| | |
| --- | --- |
| **Código de la versión** | `ddb1aa9980a6b7074e7cf674d028acab7425fa34` (rama candidata `release/alpha-0.2-rc1`) |
| **Commit publicado en `beta`** | `c28e32c42925ae3c27b73b763772c84df8709a04`: el siguiente a ese; añade este registro y el nombre de la versión en el juego y en el portal. Es el que informa `/healthz`. |
| **Fecha** | 12 de noviembre de 2026 |
| **Autorizada por** | El dueño del proyecto, el 12 de noviembre de 2026 |
| **Base de datos** | Sin cambios: no hay migraciones nuevas respecto a la 0.1. |
| **Recursos** | Los mismos dos de la 0.1; no se crea ninguno. |

**Comprobado sobre el código de la versión, en una copia limpia, antes de publicar:** API (10 de 10),
simulación (427 840 comprobaciones sin violaciones), servidor con bots (13 de 13), flujo completo en
navegador (14 pasos), cuatro navegadores (10 pasos), revisión de secretos y la imagen desplegable
(migraciones, acceso sólo con invitación, HTTPS/WSS, partida, reconexión, métricas y persistencia
tras reiniciar).

**Volver a la 0.1:** en Render → `alux-beta` → **Events** → el despliegue del commit `12fadbe` →
**Rollback**; o, desde Git, `git push origin 12fadbec9be468036f05b551c87282d19fcaca6f:beta --force-with-lease`. La base de datos no necesita nada:
el esquema es el mismo. Detalle en [beta.md](beta.md), sección 9.

**Comprobado después de desplegar, contra <https://alux-beta.onrender.com>:**

| Comprobación | Resultado |
| --- | --- |
| Versión en servicio | `/healthz` informa `c28e32c`; base de datos respondiendo |
| HTTPS, cabeceras y cierre sin sesión | Pasa: sin entrada anónima, rutas internas cerradas, códigos inventados rechazados |
| WSS | `wss://alux-beta.onrender.com/ws` abre y rechaza tickets falsos |
| Invitación | Entra con un código vigente; el perfil se guarda |
| Partida por WebSocket | 15 estados por segundo, latencia de 57 ms, reconexión tras un corte en el mismo sitio |
| Métricas de sesión | Recibidas y guardadas |
| Navegador real, un jugador | Pasa la sesión completa: carga (18 s), audio, menú, altar, emboscada, derrota, reintento y salida |
| Cinemáticas en navegador real | «El llamado» se reproduce al entrar y se omite; «El sello cede» pausa la sala, se ve y la partida sigue con la emboscada |

**Sin comprobar en el servicio:** de dos a cuatro jugadores a la vez (sólo hay una invitación de
comprobación; hacen falta testers o más invitaciones), los registros de Render (no hay acceso desde
aquí) y cualquier navegador con tarjeta gráfica.

**Etiquetas de versión:** `alpha-0.1` (`12fadbe`) y `alpha-0.2` (`c28e32c`) están creadas pero **no se
pudieron subir**: el servicio de Git de este entorno rechazó la subida de etiquetas. Para crearlas:

```bash
git tag -a alpha-0.1 12fadbec9be468036f05b551c87282d19fcaca6f -m "ALUX Closed Alpha 0.1"
```

```bash
git tag -a alpha-0.2 c28e32c42925ae3c27b73b763772c84df8709a04 -m "ALUX Closed Alpha 0.2"
```

```bash
git push origin alpha-0.1 alpha-0.2
```

## Alpha 0.2 — La abuela del claro (contenido)

**Incremento 1.** No toca el protocolo existente: añade un mensaje (`talk`), un evento (`story`) y un
valor al estado del mundo. Un cliente de la 0.1 seguiría funcionando contra este servidor.

| Novedad | Detalle |
| --- | --- |
| Introducción «El llamado» | Cinemática dentro del motor (4 planos, 19 s) la primera vez que se entra; se omite con Enter o Esc y se repite desde el menú. |
| Chiich Yaxché | Personaje junto al brasero. F abre el diálogo; lo que dice cambia según el momento (antes de los altares, en la emboscada, tras una derrota, con el santuario libre). |
| Primer objetivo narrativo | «Habla con Chiich Yaxché», con marca en la brújula. Al terminar de hablar, el servidor lo anota para toda la sala y el objetivo pasa a los altares. No es obligatorio. |
| Reproductor de cinemáticas | Reutilizable: guiones como datos, cámara, subtítulos, rótulos y sonido. Ver [CINEMATICS.md](CINEMATICS.md). |
| Pruebas | `&cine=0` desactiva la introducción en las pruebas que no la necesitan. |

| Comprobación (en local) | Resultado |
| --- | --- |
| API | 10 de 10 |
| Simulación | 427 840 comprobaciones sin violaciones (el mundo compartido no cambió) |
| Servidor con bots | 12 de 12, con la prueba nueva: hablar sólo cuenta estando a su lado y lo sabe toda la sala |
| Flujo en navegador | Pasa: la introducción se reproduce y deja quieto al personaje, se omite, se habla con la abuela, el servidor anota el avance y el resto de la partida sigue igual |
| Cuatro navegadores | Pasa: movimiento, transformación, combate sincronizado, reconexión, sala llena y recarga |
| Rendimiento (render por software, 640×360, un jugador, mismo día y máquina) | Sin diferencia medible: 7.2 FPS en mínima y 5.0 en baja, frente a 7.2 y 4.9 de la versión anterior. Unas 25–30 llamadas de dibujo más (el personaje y la interfaz nueva). |

![La introducción y el diálogo en un navegador real](img/alpha02-navegador.jpg)

**Sin comprobar:** con tarjeta gráfica, con personas, y contra el servicio desplegado (no está publicada).

**Incremento 2.** Amplía el protocolo sin romperlo: un mensaje (`skip`), dos eventos (`cine`,
`cine_end`) y dos valores más al final del estado del mundo. No hay migraciones nuevas.

| Novedad | Detalle |
| --- | --- |
| Cinemáticas compartidas | Las empieza y las termina el servidor. Mientras duran, la sala está en pausa: nadie se mueve ni recibe daño y los enemigos esperan. Cada sala las ve una sola vez. |
| «El sello cede» | La primera (2 planos, 7 s): se reproduce para todo el grupo cuando abre el santuario por primera vez, justo antes de la emboscada. |
| Voto para omitir | Enter vota. Se omite con la mayoría de los conectados (1 de 1, 2 de 2, 2 de 3, 3 de 4); en pantalla se ve cuántos votos van. Quien se desconecta deja de contar. |
| Progreso del capítulo | Al hablar con la abuela, el servidor guarda «El llamado de la abuela» en el perfil de quienes estén conectados (una vez por jugador) y el portal lo muestra junto a los sellos. |
| Chiich Yaxché, modelo propio | Hecho en Blender por código, como el alux y Balam: 8 599 triángulos, 39 huesos, 542 KB. Animaciones de reposo, hablar, regañar y bendecir; el brote de jade del bastón late. Retrato propio en el diálogo. |
| Toma de prueba de Kling | Una toma de 5 s de «El vínculo de Balam» para medir el costo: **50 créditos**. No está en el juego. Ver [CINEMATICS.md](CINEMATICS.md). |

| Comprobación (en local) | Resultado |
| --- | --- |
| API | 10 de 10 |
| Simulación | Sin violaciones (el mundo compartido no cambió) |
| Servidor con bots | 13 de 13, con la prueba nueva: la escena pausa la sala, un voto de cuatro no basta, tres la terminan, y no se repite en la misma sala |
| Flujo en navegador | Pasa completo: introducción, diálogo, escena compartida con voto, victoria, otra ronda, derrota, reintento y salida |
| Cuatro navegadores | Pasa: movimiento, transformación, combate sincronizado, reconexión, sala llena y recarga |
| Rendimiento (mismo método que el incremento 1) | 6.7 FPS en mínima y 4.7 en baja, frente a 7.2 y 5.0 del incremento 1: **una bajada de alrededor del 7 %**, atribuible al modelo nuevo (antes eran piezas sin esqueleto). Está cerca del margen de error de esta medición; hay que confirmarlo con tarjeta gráfica. |

![Chiich Yaxché, el diálogo con su retrato y la escena compartida «El sello cede»](img/alpha02-incremento2.jpg)

**Corregido en las pruebas, no en el juego:** el paso de la derrota en la prueba de flujo dependía de
observar una fase que dura pocos segundos; con el equipo cargado se la perdía. Ahora un testigo dentro
de la página la registra.

**Sin comprobar:** con tarjeta gráfica, con personas (¿se entiende el voto?, ¿molesta la pausa?) y
contra el servicio desplegado.

## ALUX Closed Alpha 0.1

| | |
| --- | --- |
| **Código de la versión** | `3dc3f81d205a26ec840de5984ef10668ff634446` |
| **Commit publicado en `beta`** | El siguiente a ese: sólo añade este registro. Es el que informará `/healthz` (`git rev-parse origin/beta`). |
| **Publicada desde** | `claude/tender-johnson-c2gk0s` |
| **Fecha** | 12 de noviembre de 2026 |
| **Estado en Render** | **Desplegada** el 12 de noviembre de 2026 en <https://alux-beta.onrender.com> (juego: `wss://alux-beta.onrender.com/ws`). El servicio informa el commit `12fadbec9be468036f05b551c87282d19fcaca6f`. |

**Recursos que crea** (y ninguno más): `alux-beta` (Docker, `0.5c-512mb`, Ohio, US$7 al mes) y
`alux-beta-db` (PostgreSQL 16, `0.1c-256mb`, 1 GB, Ohio, US$6 + US$0.30 al mes).

**Migraciones incluidas:** `20261111000000_init` y `20261112000000_beta`. Las dos sólo crean
tablas e índices, activan RLS y amplían una restricción; no borran ni modifican datos.

**Comprobado antes de publicar** (en local; nada de esto se ha ejecutado aún en Render):

| Comprobación | Resultado |
| --- | --- |
| `npm run beta:preflight` (Blueprint, secretos en archivos e historial, accesos de prueba, invitaciones, migraciones) | Supera las 8 revisiones |
| API | 10 de 10; 20 de 20 contra PostgreSQL 16 con el migrador |
| Simulación | 427 840 comprobaciones sin violaciones |
| Servidor de juego con bots | 11 de 11 |
| Imagen única como en Render (`scripts/test-beta-image.sh`): migraciones, acceso sólo con invitación, HTTPS/WSS, partida, métricas, commit informado, persistencia tras reiniciar y bloqueo por códigos inventados | Pasa |
| Flujo completo de la partida en navegador contra esa imagen | Pasa (3 de 4 pasadas del día; la que falló coincidió con la máquina saturada) |
| Cuatro navegadores contra esa imagen | **Inestable en el entorno de pruebas**: pasa 3 de 6 pasadas. Las que fallan lo hacen porque una pestaña, renderizando por software en una máquina de 4 núcleos, se congela más de 15 s y el servidor la desconecta. La misma prueba pasa sin Docker con el mismo código. |
| Respaldo y restauración (`scripts/beta-backup.sh`) | Probado contra PostgreSQL 16: datos estropeados a propósito y recuperados |

**Comprobado contra el servicio desplegado**, desde fuera de Render:

| Comprobación | Resultado |
| --- | --- |
| `npm run beta:check` con una invitación: HTTPS, HSTS, API y base de datos, commit desplegado, rutas internas cerradas, sin entrada anónima, descarga del juego, `wss://`, sesión, guardado, partida por WebSocket (15 estados/s), reconexión con el mismo lugar y posición, latido y métricas | Pasa |
| Sesión de un jugador en un navegador real (`tests/e2e/beta-solo.ts`): portal, carga del cliente Godot, audio del navegador activo, menú, altar, emboscada, derrota, reintentar y salir | Pasa |
| Descarga del cliente | 8.2 MB con Brotli (10.6 MB con gzip) |

![El cliente real jugando contra el servicio desplegado](img/beta-en-render.jpg)

**Sin comprobar todavía:** cuatro jugadores a la vez en el servicio desplegado, persistencia tras un
reinicio del servicio provocado a propósito, Edge, el audio a oído, y FPS y latencia con tarjeta
gráfica desde las conexiones de los testers.

**Volver a esta versión:** en Render, *Rollback* al despliegue de este commit; o, desde Git,
`git push origin <commit publicado>:beta --force-with-lease` (sólo si `beta` avanzó con algo que
hay que retirar; lo normal es `git revert`). Ver [beta.md](beta.md), sección 9.
