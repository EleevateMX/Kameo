# Playtest: guía de la sesión y resultados


Una sesión de 20–30 minutos para 1 a 4 personas (10–15 hasta la emboscada; el resto, el guardián). Esta guía sirve a quien organiza la prueba y
a quien juega por primera vez.

| Bienvenida | Emboscada |
| --- | --- |
| ![Bienvenida con el objetivo y los controles](img/playtest-bienvenida.jpg) | ![Emboscada: aviso de ataque, aturdido y purificable](img/playtest-combate.jpg) |

| Victoria | Derrota |
| --- | --- |
| ![Panel de victoria](img/playtest-victoria.jpg) | ![Panel de derrota](img/playtest-derrota.jpg) |

| Esperando al grupo | Menú | Reconectando |
| --- | --- | --- |
| ![Esperando en el altar](img/playtest-esperando.jpg) | ![Menú con ajustes](img/playtest-menu.jpg) | ![Aviso de reconexión](img/playtest-reconectando.jpg) |

Estas siete imágenes salen de la vista previa del juego (escena preparada, calidad alta). La hoja de
abajo son capturas de una sesión real en el navegador, tomadas por la prueba automática
`npm run test:flow` en calidad mínima (el entorno de pruebas no tiene tarjeta gráfica): portal,
bienvenida, exploración, menú, controles, emboscada, victoria, nueva ronda, derrota, reintento y
vuelta al portal.

![Sesión real paso a paso](img/playtest-flujo.jpg)

## Cómo entrar

1. Abre el portal y entra (con Discord, o con la entrada de prueba si no está configurado).
2. Pulsa **Crear sala privada** y comparte el código, o **Partida pública**.
3. Pulsa **Entrar al claro**. La primera carga tarda unos segundos (el motor queda en caché).

Para jugar en una sola computadora, ver [README](../README.md#probarlo-en-tu-computadora).

## Qué pasa en una partida

| Paso | Qué ve el jugador | Qué tiene que hacer |
| --- | --- | --- |
| 1. Bienvenida | Tarjeta con el objetivo y los controles. | Clic, Enter o cualquier tecla. |
| 2. Explorar | Objetivo arriba: «Pisa un altar…» o «Pisen N altares…». Los altares salen en la brújula. | Caminar hasta un altar y quedarse encima. Con varios jugadores, uno en cada altar. |
| 3. Esperar | «Quédate en el altar (2/4) · esperando al grupo». | No moverse hasta que el grupo complete los altares. |
| 4. Emboscada | Aviso, música de combate y objetivo «Quedan N enemigos». | Vencer o purificar a todos. |
| 5. Resultado | Panel de **Victoria** (resumen y sello) o de **Derrota**. | Enter: entrar al santuario. O reintentar, otra ronda (con su botón) o salir. |
| 6. El guardián despierta (0.3) | Al entrar al patio, la cinemática «El despertar» y la barra de Silencio. | Fase 1: debilitar criaturas y tocarlas con F **junto a él**. Sus golpes no le hacen nada. |
| 7. La explanada (0.3) | El guardián sale andando del santuario. Glifos dorados y discos de jade en el suelo. | Fase 2: un alux despierta una columna (F), el grupo hace que embista contra ella, se pisan las anclas y Balam golpea el corazón. Tres veces. Bajo la lluvia de piedra, junto a una columna. |
| 8. El ritual (0.3) | El guardián se arrodilla. | Fase 3: purificar criaturas junto a él para encender los glifos del suelo; después, todos como alux mantienen F a su lado a la vez. |
| 9. Liberación (0.3) | Cinemática «La liberación» y panel **Capítulo I completado**. | Hablar con el guardián (F): da la pista del Cenote. La Pluma de Jade queda en el perfil. |

- **Victoria**: no queda ningún enemigo. Todos reciben el Sello del Claro (una sola vez por perfil).
- **Derrota**: todo el grupo conectado está caído a la vez. El santuario se sella y, a los 6 s, se
  puede volver a pisar los altares.
- **Otra ronda**: tras la victoria, la piden todos los jugadores (botón del panel o del menú).
- **Derrota contra el guardián**: si cae todo el grupo, se duerme y el combate se retoma desde la
  fase alcanzada; no hay que volver a abrir el santuario ni repetir fases.

![El combate con Nojoch Tuunich, fase a fase](img/jefe-fases.jpg)

## Controles

| Acción | Tecla |
| --- | --- |
| Moverse · saltar | W A S D · Espacio |
| Mirar | Ratón (clic para capturarlo) · Q / E |
| Atacar · habilidad secundaria · especial | Clic · clic derecho · F (o J · K · F) |
| Alux · Balam | 1 · 2 |
| Recentrar la cámara | R |
| Menú (volumen, sensibilidad, calidad, salir) | Esc o P |
| Ayuda de controles | H |
| Calidad gráfica · datos técnicos | F4 · F3 |

Los ajustes del menú se guardan en el navegador.

## Cómo se lee el combate

| Señal | Significa |
| --- | --- |
| **!** naranja sobre un enemigo y marca en el suelo | Va a golpear: aléjate o esquiva (clic derecho). |
| Estrellas amarillas girando | Está aturdido: aprovecha. |
| Anillo de jade en el suelo y **F** sobre la criatura | Ya se puede purificar: acércate como alux y pulsa F (cura al grupo). |
| Barra de vida verde en una criatura | Lo mismo: está lo bastante débil para purificarla. |
| Ranura de habilidad que se sacude en rojo | No se puede usar: falta energía o sigue recargándose. |
| Bordes de la pantalla latiendo en rojo | Te queda poca vida: toca el brasero de la plaza (F como alux). |
| «Has caído · reapareces en N» | Vuelves solo junto al brasero; en la emboscada tarda 8 s. |
| Aviso arriba a la derecha | Conexión lenta o reconectando (el juego sigue visible y vuelve solo). |

Los dos enemigos: el **guardián de piedra** (lento, golpea en área, resiste las chispas) y la
**criatura corrompida** (rápida, embiste, débil a las chispas y purificable).

## Qué observar en la prueba

- ¿Entiende el objetivo sin que nadie se lo explique? ¿Cuánto tarda en encontrar un altar?
- ¿Descubre a Balam y cuándo conviene cada forma?
- ¿Entiende por qué no puede usar una habilidad?
- ¿Purifica alguna criatura? ¿Usa el brasero?
- ¿Se entiende por qué se pierde y qué hacer después?
- ¿El volumen por defecto molesta? ¿Algún sonido cansa?
- ¿Algún momento de confusión con la cámara o el ratón?

Con el guardián (0.3), que nadie ha jugado todavía:

- ¿Entienden que no se le pega, que hay que devolverle la memoria? ¿Cuánto tardan?
- ¿Descubren solos las columnas, la embestida, las anclas y el corazón, o hace falta explicarlo?
- ¿Se reparten papeles? ¿Alguien se queda sin nada que hacer?
- ¿La lluvia de piedra y la embestida se ven venir a tiempo? ¿El daño es justo?
- ¿El contacto final (todos manteniendo F) se entiende? ¿Frustra cuando una criatura lo corta?
- ¿Cuánto dura cada fase? ¿Se hace larga alguna?
- ¿La cara del guardián se lee triste al principio y serena al final?
- ¿Las dos cinemáticas se ven enteras? ¿Alguien quiere omitirlas?
- ¿La sacudida de cámara molesta a alguien?

## Playtest humano del guardián: qué se registra y qué hay que apuntar

Nadie ha jugado todavía el combate de Nojoch Tuunich. Las pruebas automáticas sólo dicen que se
puede terminar; no dicen si se entiende ni si divierte. **El equilibrio no se toca para que pasen
los bots**: se ajustará con lo que salga de esta sesión.

**Lo que el juego registra solo** (desde la Alpha 0.3.1, una fila por jugador y sesión; se consulta
con `npm run beta:metrics`, y con `--json` para el detalle):

| Dato | Dónde sale |
| --- | --- |
| Tiempo en cada fase (segundos de combate en Olvido, Furia y Recuerdo, sin contar cinemáticas) | columna `jefe`: `95+140+60 s` |
| Derrotas del grupo en cada fase | `jefe`: `derrotas 0/2/1` |
| Daño recibido y caídas de ese jugador durante el combate | `jefe`: `daño 180`; `boss.falls` en el detalle |
| Uso de la transformación (porcentaje del combate como Balam) | `jefe`: `Balam 35 %` |
| Acciones denegadas (pulsó algo que no podía hacer: señal de que no entendió el objetivo) | `boss.denied` en el detalle |
| Si liberaron al guardián | `jefe`: `liberado` |
| Errores de sincronización visibles para el jugador (reconexiones) | columna `reconex` |
| FPS medio y percentil 5, latencia media y máxima | `FPS med`, `FPS p5`, `ping ms`, `ping máx` |
| Cinemáticas: vistas como vídeo, con el motor, omitidas y fallos de carga | columna `cine` y `cine.fails` |
| Audio: si llegó a sonar (pico medido en la salida del navegador), errores de carga | columna `sonó` y `audio.errors` |

**Lo que sólo puede apuntar una persona** (una hoja por jugador; quien modera no explica nada salvo
que el grupo se atasque más de tres minutos, y entonces apunta qué tuvo que decir):

| Pregunta | Respuesta |
| --- | --- |
| Navegador, equipo y si jugó con altavoces o auriculares | |
| Al entrar, ¿oyó el ambiente enseguida? ¿Tuvo que tocar algo para que sonara? | |
| ¿Entendió qué había que hacer en cada fase sin ayuda? (1 Olvido · 2 Furia · 3 Recuerdo) | |
| ¿Qué fue lo que más tardó en entender? | |
| ¿Vio venir la losa, el barrido, la lluvia y la embestida? ¿Algún golpe le pareció injusto? | |
| ¿Cuándo se transformó en Balam y para qué? | |
| ¿Notó saltos, compañeros que «se teletransportan» o golpes que no cuentan? | |
| Sonido: ¿se distinguen los avisos del guardián? ¿Algo molesta, satura o tapa a lo demás? ¿La música acompaña cada fase? | |
| Cinemáticas: ¿se vieron y se oyeron enteras? ¿Quiso omitir alguna? ¿El sonido iba con la imagen? | |
| ¿Qué cambiaría primero? | |

Antes de empezar: cada jugador abre el menú (Esc) y pulsa **Probar sonido**; debe decir «Prueba
correcta». Si dice que el audio está bloqueado o que no llega señal, se apunta el navegador y el
mensaje exacto.

## Resultados

| Fecha | Versión | Qué se probó | Resultado |
| --- | --- | --- | --- |
| 12 nov 2026 | Closed Alpha 0.1 (publicada) | Automático contra el servicio real: HTTPS, WSS, invitación, guardado, partida, reconexión, métricas; sesión de un jugador en navegador | Pasa. Detalle en [RELEASES.md](RELEASES.md) |
| 12 nov 2026 | Alpha 0.2, incremento 1 (sin publicar) | Automático en local: API, simulación, 12 pruebas de servidor (incluida la historia), flujo en navegador con introducción y diálogo, cuatro navegadores | Ver [RELEASES.md](RELEASES.md) |
| 12 nov 2026 | Alpha 0.2, incremento 2 (sin publicar) | Automático en local: API, simulación, 13 pruebas de servidor (incluida la cinemática compartida y su voto), flujo completo en navegador, cuatro navegadores, medición de rendimiento | Ver [RELEASES.md](RELEASES.md) |
| 12 nov 2026 | Alpha 0.3, incremento 1 (sin publicar) | Automático en local: API, 14 pruebas de servidor (fases de la cinemática, reconexión), vídeo en navegador (5 casos, con vídeos de prueba), cuatro navegadores con vídeo y con fallos, flujo completo, rendimiento | Ver [RELEASES.md](RELEASES.md) |
| 12 nov 2026 | **Closed Alpha 0.2, publicada** | Antes: regresión completa sobre el commit de la versión en una copia limpia. Después, contra el servicio: 10 comprobaciones externas, sesión completa de un jugador en navegador real y las dos cinemáticas | Pasa. Sin probar: 2–4 jugadores a la vez en el servicio. Ver [RELEASES.md](RELEASES.md) |
| 12 nov 2026 | Alpha 0.3, incremento 2 (sin publicar) | Automático en local: API, simulación, 14 pruebas de servidor, vídeos reales de Kling en navegador, 5 casos de fallo, flujo completo, cuatro navegadores | Pasa, salvo la prueba de cuatro navegadores viendo la escena, inestable sin GPU. Ver [RELEASES.md](RELEASES.md) |
| 12 nov 2026 | **Closed Alpha 0.2.1, publicada** | Antes: regresión completa sobre el commit de la versión. Después, contra el servicio: 10 comprobaciones externas; en navegador real, carga y reproducción del vídeo de Kling, omisión, respaldo del motor, introducción y ciclo completo de un jugador | Pasa. Sin probar: 2–4 jugadores a la vez en el servicio. Ver [RELEASES.md](RELEASES.md) |
| 12 nov 2026 | Alpha 0.3 en desarrollo: jefe, fase 1 | Automático en local: 17 pruebas de servidor, con el jefe para 1, 2 y 4 jugadores | Pasa. Ver [RELEASES.md](RELEASES.md) |
| 12 nov 2026 | **Alpha 0.3 RC1** (sin publicar) | Automático en local: API (11), simulación, 17 pruebas de servidor con el combate completo para 1, 2 y 4 jugadores, combate completo en navegador con las dos cinemáticas de Kling, flujo de playtest, cuatro navegadores, 6 casos de vídeo e imagen de despliegue | Pasa. **Nadie ha jugado el jefe todavía.** Ver [RELEASES.md](RELEASES.md) |
| 12 nov 2026 | **Closed Alpha 0.3, publicada** | Antes: regresión completa en una copia limpia del commit. Después, contra el servicio: 10 comprobaciones externas, sesión completa por protocolo (las tres fases, liberación, Pluma guardada), cinemáticas en navegador (ver, omitir, sin vídeo) y la sonda de audio | Pasa todo salvo el audio: **no sonaba nada** (defecto de la 0.1 en adelante, descubierto por un jugador). Detalle en [RELEASES.md](RELEASES.md) y [AUDIO.md](AUDIO.md) |
| — | Closed Alpha 0.1 | **Primera sesión con testers reales** (cuatro a la vez, Edge, audio a oído, FPS con tarjeta gráfica) | **Pendiente** |

Cuando haya una sesión real, se anota aquí: quiénes, cuánto duró, qué entendieron sin ayuda, qué no,
y las métricas que registró el juego (`npm run beta:metrics`).

## Límites conocidos de esta build

- El audio es provisional: está generado por código, no grabado.
- Los enemigos siguen siendo modelos provisionales.
- Sin mando ni controles táctiles: teclado y ratón.
- El rendimiento con tarjeta gráfica real no está medido (ver [rendimiento.md](rendimiento.md)).
- Un solo escenario; dos encuentros (la emboscada y el guardián).
- El combate con el guardián no lo ha jugado ninguna persona: su ritmo y dificultad son una apuesta.

Lo demás, en [pendientes.md](pendientes.md).
