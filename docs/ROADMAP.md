# Hoja de ruta de ALUX

De un prototipo jugable a una aventura cooperativa por capítulos. Este documento manda sobre el
orden del trabajo: cada entrega es una versión que se puede jugar, probar con cuatro jugadores y
deshacer. Historia: [STORY_BIBLE.md](STORY_BIBLE.md) · Mecánicas: [GAME_DESIGN.md](GAME_DESIGN.md) ·
Arte: [ART_BIBLE.md](ART_BIBLE.md) · Cinemáticas: [CINEMATICS.md](CINEMATICS.md) ·
Pruebas: [PLAYTEST.md](PLAYTEST.md) · Versiones: [RELEASES.md](RELEASES.md).

## Dónde estamos

| Área | Estado real |
| --- | --- |
| Versión publicada | **Closed Alpha 0.1** en <https://alux-beta.onrender.com> (rama `beta`, commit `12fadbe`). Rollback: [beta.md](beta.md), sección 9. |
| Versión en desarrollo | **Alpha 0.2**, primer incremento hecho en la rama de trabajo. **No publicada.** |
| Multijugador | Servidor autoritativo, 4 jugadores, reconexión, salas. Verificado con bots, navegadores y contra el servicio desplegado (un jugador). **Cuatro personas reales a la vez: sin probar.** |
| Combate y formas | Alux y Balam, dos enemigos, emboscada, derrota y otra ronda. Datos modulares (`combat_def.gd`). Equilibrio sin probar con personas. |
| Historia | Introducción, un personaje con diálogo y primer objetivo narrativo (Alpha 0.2). Sin jefe ni cierre de capítulo. |
| Escenario | Un solo mapa, definido en un único archivo compartido (`world_def.gd`). **No hay soporte para varias zonas.** |
| Arte | Alux y Balam modelados (Blender, por código). Enemigos y Chiich Yaxché con modelos provisionales. |
| Audio | 38 sonidos generados por código. **Nadie los ha escuchado.** |
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
| 2 | Modelo propio de Chiich Yaxché (Blender); cinemáticas compartidas con voto para omitir (lo necesita el jefe); progreso del capítulo guardado en el perfil; correcciones que salgan de la primera sesión con testers (audio, equilibrio, rendimiento). | Pendiente |

**Criterios de aceptación:** un jugador nuevo ve la introducción, habla con la abuela y sabe qué
hacer sin ayuda externa; con cuatro jugadores cada quien puede leer el diálogo a su ritmo sin detener
a los demás; ninguna prueba anterior se rompe.

### Alpha 0.3 — El Guardián Dormido

| | |
| --- | --- |
| **Objetivo** | Primer jefe cooperativo: un combate que no se gana sin repartirse papeles. |
| **Alcance** | Nojoch Tuunich con tres fases (diseño en [GAME_DESIGN.md](GAME_DESIGN.md)), su presentación como cinemática compartida, modelos propios de los dos enemigos actuales. |
| **Dependencias** | Cinemáticas compartidas (0.2, incremento 2). Datos de rendimiento con tarjeta gráfica para decidir cuántos efectos caben. |
| **Implementación** | El jefe reutiliza la IA de enemigos, los avisos de ataque, los altares de presión, la purificación y la derrota con reintento. |
| **Pruebas** | Bots: victoria con 1, 2 y 4 jugadores; derrota y reintento; nadie puede saltarse fases desde el cliente. Navegador: flujo completo hasta vencer. |
| **Aceptación** | Con cuatro jugadores hace falta coordinarse; con uno es posible. La escena de presentación no deja a nadie atascado. |

### Alpha 0.4 — La Pluma de Jade (cierre del Capítulo I)

| | |
| --- | --- |
| **Objetivo** | Que el capítulo tenga final: recompensa, revelación y camino al siguiente. |
| **Alcance** | Pluma de Jade como recompensa persistente; cinemática final; «El vínculo de Balam» y el final como vídeo (Kling) con versión dentro del motor de respaldo; reproductor de vídeo en el navegador. |
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

## Decisiones que necesitan tu aprobación

| Decisión | Opciones | Recomendación |
| --- | --- | --- |
| ¿Balam se desbloquea jugando? | **A.** Sigue disponible desde el inicio y la historia cuenta el vínculo. **B.** Los jugadores nuevos empiezan sin Balam y lo reciben tras la escena del vínculo. | **B** a partir de 0.4, cuando exista la escena; hasta entonces, A. Quien ya lo tiene lo conserva. |
| Nombres de los espíritus (Áayin, Tuunich, Toh) y del antagonista (El que Calla) | Aprobar, cambiar o proponer otros | Aprobar como nombres de trabajo y revisarlos con un hablante de maya. |
| Primera cinemática con Kling | «El vínculo de Balam» (storyboard en [CINEMATICS.md](CINEMATICS.md)) | Producirla en 0.4, no antes: los modelos todavía van a cambiar. |
| Voto para omitir cinemáticas compartidas | Unanimidad, mayoría, o que decida quien creó la sala | Mayoría de los conectados; un jugador solo omite al instante. |
