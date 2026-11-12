# Versiones de ALUX

Qué lleva cada versión, qué se comprobó y cuál está publicada. Plan de las siguientes:
[ROADMAP.md](ROADMAP.md).

| Versión | Estado | Contenido |
| --- | --- | --- |
| Closed Alpha 0.1 | **Publicada** en <https://alux-beta.onrender.com> | Claro de los Aluxes jugable de 1 a 4, combate, emboscada, victoria y derrota, audio provisional, acceso por invitación |
| Alpha 0.2 (incremento 1) | En la rama de trabajo, **sin publicar** | Introducción «El llamado», Chiich Yaxché con diálogo, primer objetivo narrativo, reproductor de cinemáticas |

## Publicación en la rama `beta`

La rama `beta` es lo único que Render despliega. Cada entrada dice qué commit lleva el código de
esa versión, qué se comprobó antes de publicarla y cómo volver a ella.

Para saber qué hay desplegado en este momento: `npm run beta:check -- <URL>` muestra el commit que
informa el servicio, y `--commit <hash>` exige que sea uno concreto.

## Alpha 0.2 — La abuela del claro (en desarrollo, sin publicar)

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
| Cuatro navegadores | RESULTADO_E2E |

![La introducción y el diálogo en un navegador real](img/alpha02-navegador.jpg)

**Sin comprobar:** con tarjeta gráfica, con personas, y contra el servicio desplegado (no está publicada).
**Provisional:** el modelo de Chiich Yaxché.

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
