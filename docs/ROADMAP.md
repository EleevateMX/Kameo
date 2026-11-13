# Hoja de ruta de ALUX

De un prototipo jugable a una aventura cooperativa por capítulos. Este documento manda sobre el
orden del trabajo: cada entrega es una versión que se puede jugar, probar con cuatro jugadores y
deshacer. Historia: [STORY_BIBLE.md](STORY_BIBLE.md) · Mecánicas: [GAME_DESIGN.md](GAME_DESIGN.md) ·
Arte: [ART_BIBLE.md](ART_BIBLE.md) · Cinemáticas: [CINEMATICS.md](CINEMATICS.md) ·
Pruebas: [PLAYTEST.md](PLAYTEST.md) · Versiones: [RELEASES.md](RELEASES.md).

## Dónde estamos

| Área | Estado real |
| --- | --- |
| Versión candidata | **Closed Alpha 0.4.1**, en la rama de trabajo, sin publicar: pulido de la 0.4 (plaza más ligera y viva, portal como menú, pelea de Nojoch más clara y su salida de un salto). Espera el visto bueno del dueño. Ver [RELEASES.md](RELEASES.md). |
| Versión publicada | **Closed Alpha 0.4** (13 nov 2026, commit `b27e4c1`): pantalla completa ([FULLSCREEN.md](FULLSCREEN.md)), personalizador 3D ([PERSONALIZADOR.md](PERSONALIZADOR.md)), plaza social de Mérida con portal al Claro ([OPEN_WORLD.md](OPEN_WORLD.md)), primeros sonidos elegidos de oído. **Desarrollo detenido hasta la evaluación del dueño del proyecto.** Siguiente prioridad acordada: volver del Claro a la plaza conservando identidad, grupo, apariencia y progreso. |
| Multijugador | Servidor autoritativo, 4 jugadores, reconexión, salas. Verificado con bots, navegadores y contra el servicio desplegado (un jugador). **Cuatro personas reales a la vez: sin probar.** |
| Combate y formas | Alux y Balam, dos enemigos, emboscada, derrota y otra ronda. Datos modulares (`combat_def.gd`). Equilibrio sin probar con personas. |
| Historia | Introducción, un personaje con diálogo, primer objetivo narrativo, **jefe con tres fases y cierre del capítulo** con la Pluma de Jade y la pista del Cenote (candidata 0.3). Falta «El vínculo de Balam». |
| Cinemáticas | Sistema híbrido y **tres producidas con Kling**: «El sello cede» (publicada; 284 créditos), «El despertar» y «La liberación» de Nojoch Tuunich (candidata 0.3; 488 créditos de 800). Quedan 1 887 créditos. |
| Escenario | Un solo mapa, definido en un único archivo compartido (`world_def.gd`). **No hay soporte para varias zonas.** |
| Arte | Alux, Balam, Chiich Yaxché y **Nojoch Tuunich (modelo definitivo)** modelados. Enemigos comunes con modelos provisionales. |
| Audio | 140 archivos de síntesis propia viajan con el juego (10 músicas, 10 ambientes, 8 pistas de cinemática y 112 efectos), sonando en el navegador desde la 0.3.1. **Sólo se han escuchado los sonidos de la primera hoja de escucha** ([AUDIO.md](AUDIO.md)); el resto está comprobado con mediciones, no de oído. |
| Rendimiento | Medido sólo con render por software. **Sin datos de tarjeta gráfica**; las métricas de cada sesión real ya se registran. |
| Acceso y datos | Invitaciones individuales, PostgreSQL en Render, migraciones automáticas. Discord real pendiente de credenciales. |
| Infraestructura | Un contenedor de 512 MB (unos 300 MB con cuatro jugadores). Aviso de pago pendiente en la cuenta de Render. |

Lo que falta por validar, con detalle: [pendientes.md](pendientes.md).

## Reglas de producción

1. **Ciclos pequeños.** Cada ciclo termina en algo jugable y probado; nada de mejoras sueltas.
2. **Se reutiliza lo que funciona.** Los sistemas actuales se integran en la historia; no se reescriben.
3. **El servidor decide** todo lo que afecta al progreso o al estado compartido, también en la historia
   y las cinemáticas.
4. **Pruebas por ciclo:** API, simulación, protocolo con bots, flujo en navegador, cuatro navegadores
   y medición de rendimiento. Si algo no se pudo probar, se dice.
5. **Commits separados** por bloque y versión candidata documentada en [RELEASES.md](RELEASES.md).
6. **Nada llega a `beta` sin tu visto bueno.** La rama de trabajo no se despliega sola.
7. **Piden autorización previa:** decisiones narrativas abiertas, créditos de Kling y servicios de pago.
8. **Kling es obligatorio en las cinemáticas narrativas**, con presupuesto aprobado por escena y
   siempre con la versión del motor debajo ([CINEMATICS.md](CINEMATICS.md)).

## Versiones

Las fechas no se fijan: cada versión sale cuando cumple sus criterios.

### Alpha 0.2 — La abuela del claro

| | |
| --- | --- |
| **Objetivo** | Que el Claro deje de ser un mapa con un acertijo y empiece a contar una historia. |
| **Alcance** | Introducción dentro del motor, Chiich Yaxché con diálogo, primer objetivo narrativo, sistema de cinemáticas reutilizable. |
| **Dependencias** | Ninguna externa. |
| **Entrega** | Candidata a beta al cerrar el segundo incremento. |

| Incremento | Contenido | Estado |
| --- | --- | --- |
| 1 | Reproductor de cinemáticas (locales), introducción «El llamado», Chiich Yaxché (modelo provisional) con diálogos según el momento de la historia, objetivo «Habla con Chiich Yaxché», marca en la brújula, progreso anotado por el servidor. | **Hecho y probado** |
| 2 | Cinemáticas compartidas con voto de mayoría y sala en pausa, con la primera («El sello cede», al abrir el santuario); progreso del capítulo guardado en el perfil; modelo propio de Chiich Yaxché (Blender). | **Hecho y probado** (detalle en [RELEASES.md](RELEASES.md)) |
| 3 | Correcciones que salgan de la primera sesión con testers (audio, equilibrio, rendimiento). | Pendiente: aún no ha habido sesión |

**Criterios de aceptación:** un jugador nuevo ve la introducción, habla con la abuela y sabe qué
hacer sin ayuda externa; con cuatro jugadores cada quien puede leer el diálogo a su ritmo sin detener
a los demás; ninguna prueba anterior se rompe.

### Alpha 0.3 — El Guardián Dormido

| | |
| --- | --- |
| **Objetivo** | Primer jefe cooperativo: un combate que no se gana sin repartirse papeles. |
| **Alcance** | Nojoch Tuunich con tres fases (diseño en [GAME_DESIGN.md](GAME_DESIGN.md)), su presentación como cinemática compartida, modelos propios de los dos enemigos actuales. |
| **Incremento 1 (hecho)** | Sistema cinematográfico híbrido. |
| **Incremento 2 (hecho)** | «El sello cede» producida con Kling e integrada, con sus dos tratamientos. |
| **Incremento 3 (hecho)** | El santuario conserva las consecuencias de «El sello cede»: enredaderas, grietas, glifos que se asientan, restos magenta que se apagan y magia residual. |
| **Incremento 4 (hecho)** | Nojoch Tuunich completo: modelo definitivo, tres fases, punto de control por fase, liberación, Pluma de Jade y pista del Cenote; pruebas con bots para 1, 2 y 4 jugadores y combate completo en navegador. |
| **Incremento 5 (hecho)** | «El despertar» y «La liberación» producidas con Kling e integradas. |
| **Siguiente** | Tu visto bueno para publicar la candidata. Después: probarla con personas y ajustar ritmo y dificultad; modelos propios de los dos enemigos comunes. |
| **Dependencias** | Cinemáticas compartidas (0.2, incremento 2). Datos de rendimiento con tarjeta gráfica para decidir cuántos efectos caben. |
| **Implementación** | El jefe reutiliza la IA de enemigos, los avisos de ataque, los altares de presión, la purificación y la derrota con reintento. |
| **Pruebas** | Bots: victoria con 1, 2 y 4 jugadores; derrota y reintento; nadie puede saltarse fases desde el cliente. Navegador: flujo completo hasta vencer. |
| **Aceptación** | Con cuatro jugadores hace falta coordinarse; con uno es posible. La escena de presentación no deja a nadie atascado. |

### Alpha 0.4 — La Pluma de Jade (cierre del Capítulo I)

| | |
| --- | --- |
| **Objetivo** | Que el capítulo tenga final: recompensa, revelación y camino al siguiente. |
| **Alcance** | (La Pluma de Jade y la cinemática final se adelantaron a la 0.3.) «El vínculo de Balam» como vídeo de Kling con versión del motor; modelos propios de los enemigos; ajustes tras jugar el jefe con personas; la pluma en el aspecto del alux; rehacer el plano 3 de «El sello cede» con el coloso en el patio. |
| **Dependencias** | Tu aprobación de guiones, storyboards y créditos de Kling. Modelos definitivos (para que los vídeos no queden viejos). |
| **Aceptación** | El capítulo se juega de principio a fin en 20–30 minutos y deja claro adónde se va después. |

### Alpha 0.5 — Primera zona del Cenote

| | |
| --- | --- |
| **Objetivo** | Salir del claro. |
| **Alcance** | Soporte para varias zonas (hoy el mundo es un único archivo compartido por cliente y servidor), viaje del grupo entre zonas, primera cueva inundada. |
| **Dependencias** | **Trabajo técnico previo obligatorio:** separar la definición del mundo por zona en la simulación compartida, en el servidor y en las pruebas de invariantes. Capítulo I cerrado. |
| **Riesgo** | Es el cambio de arquitectura más grande desde el inicio. Se hará en un ciclo propio, sin contenido nuevo, antes de construir la zona. |

### Alpha 0.6 — El vínculo de Áayin

Transformación acuática: nado rápido, inmersión, habilidades propias y acertijos de agua que la
necesitan. Depende de 0.5 y de aprobar el diseño del espíritu del Capítulo II.

### Alpha 0.7 — Capítulo II completo

Historia, jefe y cierre de Los Secretos del Cenote, con la misma estructura que el Capítulo I.

### Después

| Capítulo | Contenido | Forma nueva |
| --- | --- | --- |
| III. La Ciudad de Piedra | Templos y mecanismos; combates que piden combinar formas | Guardián de Obsidiana |
| IV. Los Vientos del Mayab | Manglares, corrientes de viento, exploración vertical | Ave del Viento |
| V. El Despertar de Kukulkán | Desenlace y forma final, que sólo existe cuando los cuatro actúan juntos | Kukulkán |

## Dependencias que cruzan versiones

| Tema | Por qué importa | Cuándo se necesita |
| --- | --- | --- |
| Sesión con testers reales | Sin ella no hay datos de FPS, latencia, audio ni equilibrio | Antes de cerrar 0.2 |
| Aviso de pago en Render | El servicio puede suspenderse | Ya |
| Revisión de las palabras mayas | Respeto y corrección de nombres | Antes de cerrar el Capítulo I |
| Credenciales de Discord | Sustituir las invitaciones | Antes de abrir la beta a más gente |
| Varias zonas | Bloquea todo el Capítulo II | 0.5 |
| Capacidad del servidor | 512 MB compartidos; un jefe y más salas pueden pedir el plan siguiente (US$25 al mes) | Medir en 0.3 |

## Decisiones tomadas

| Decisión | Resuelto (12 nov 2026) | Efecto |
| --- | --- | --- |
| ¿Balam se desbloquea jugando? | **Sí, a partir de la 0.4**, cuando exista la escena del vínculo. Hasta entonces sigue disponible desde el inicio; quien ya lo tiene lo conserva. | Trabajo previsto en 0.4 |
| Nombres de los espíritus y del antagonista | **Aprobados como nombres de trabajo**: Áayin, Tuunich, Toh y El que Calla. Falta la revisión de un hablante de maya yucateco. | [STORY_BIBLE.md](STORY_BIBLE.md) |
| Primera cinemática con Kling | **«El sello cede»**, autorizada con 500 créditos y producida con 284 (12 nov 2026), en tratamiento enriquecido. «El vínculo de Balam» sigue aprobada en storyboard, para la 0.4. | [CINEMATICS.md](CINEMATICS.md) |
| Publicar la Alpha 0.2 | **Autorizada y publicada** el 12 nov 2026. | [RELEASES.md](RELEASES.md) |
| Publicar la Alpha 0.2.1 | **Autorizada y publicada** el 12 nov 2026, con «El sello cede» de Kling y los modelos corregidos. | [RELEASES.md](RELEASES.md) |
| Concepto de Nojoch Tuunich | **Aprobado** (12 nov 2026): liberarlo del Silencio, tres fases, fase 2 en la explanada, reintento por fases, Pluma de Jade. | [BOSS.md](BOSS.md) |
| Cinemáticas del jefe con Kling | **Autorizadas** (12 nov 2026): despertar hasta 450 créditos y liberación hasta 350, con el modelo definitivo y la mecánica verificados. Producidas: 488 en total. | [art/cinematicas/jefe/kling/PRODUCCION.md](../art/cinematicas/jefe/kling/PRODUCCION.md) |
| Kling en las cinemáticas | **Obligatorio en toda cinemática narrativa** (12 nov 2026), con presupuesto por escena y respaldo del motor. La primera en producirse será «El sello cede». | [CINEMATICS.md](CINEMATICS.md) |
| Voto para omitir cinemáticas compartidas | **Mayoría de los conectados**; un jugador solo omite al instante. | Implementado en 0.2 |

## Decisiones abiertas

| Decisión | Opciones | Recomendación |
| --- | --- | --- |
| Audio con material de terceros | Seguir con síntesis propia · contratar una biblioteca con licencia para videojuegos (Motion Array sólo con su plan Business) · generar efectos con ElevenLabs (consume créditos) | Decidir después de escuchar la 0.3.1: si los timbres sintéticos no convencen, pedir presupuesto para una biblioteca con licencia explícita |
