# Versiones de ALUX

Qué lleva cada versión, qué se comprobó y cuál está publicada. Plan de las siguientes:
[ROADMAP.md](ROADMAP.md).

| Versión | Estado | Contenido |
| --- | --- | --- |
| Closed Alpha 0.1 | **Publicada** en <https://alux-beta.onrender.com> | Claro de los Aluxes jugable de 1 a 4, combate, emboscada, victoria y derrota, audio provisional, acceso por invitación |
| Alpha 0.2 (incrementos 1 y 2) | **Candidata**: rama `release/alpha-0.2-rc1` (commit `ddb1aa9`). **Sin publicar**: `beta` sigue en la 0.1 | Introducción «El llamado», Chiich Yaxché con modelo propio y diálogo, primer objetivo narrativo, cinemáticas locales y compartidas con voto, progreso del capítulo en el perfil |

| Alpha 0.3 (incremento 1) | En la rama de trabajo, **sin publicar** | Sistema cinematográfico híbrido: vídeo en el navegador con respaldo del motor, fases de preparación y reanudación, fundidos, referencias y storyboard de «El sello cede» |

## Publicación en la rama `beta`

La rama `beta` es lo único que Render despliega. Cada entrada dice qué commit lleva el código de
esa versión, qué se comprobó antes de publicarla y cómo volver a ella.

Para saber qué hay desplegado en este momento: `npm run beta:check -- <URL>` muestra el commit que
informa el servicio, y `--commit <hash>` exige que sea uno concreto.

## Alpha 0.3 — incremento 1: cinemáticas híbridas (en desarrollo, sin publicar)

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

## Alpha 0.2 — La abuela del claro (candidata, sin publicar)

**Rama candidata:** `release/alpha-0.2-rc1`, en el commit `ddb1aa9`. Antes de crearla se repitieron
sobre ese commit las pruebas de API, simulación, servidor, flujo y cuatro navegadores, la revisión de
secretos y la prueba de la imagen desplegable (migraciones, acceso sólo con invitación, HTTPS/WSS,
partida, reconexión, métricas y persistencia tras reiniciar). **No está publicada:** publicar es
llevar ese commit a `beta`, y eso espera tu autorización.

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
