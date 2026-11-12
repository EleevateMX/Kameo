# Beta privada (ALUX Closed Alpha 0.1): despliegue en Render

Guía para publicar ALUX en una URL HTTPS pública, con acceso sólo para testers invitados, y para
operarla: comprobar que está sana, ver registros y métricas, publicar versiones, volver atrás y
respaldar los datos.

> **Estado.** Todo lo de esta guía está implementado y probado en local con la misma imagen y la
> misma disposición que usa Render (`scripts/test-beta-image.sh`): migraciones, acceso sólo con
> invitación, HTTPS/WSS a través de dos proxies, las dos pruebas con navegadores reales, métricas
> y persistencia tras reiniciar. **Desplegada en <https://alux-beta.onrender.com>** desde el 12 de
> noviembre de 2026; lo comprobado contra el servicio real está en [RELEASES.md](RELEASES.md).
> Falta la prueba con testers reales (cuatro a la vez, Edge, audio a oído, FPS con tarjeta gráfica).

![Portada de la beta: sólo se entra con un código de invitación personal](img/beta-portada.jpg)

## Qué se despliega

Render expone un único puerto HTTP por servicio y pone el HTTPS por delante. Por eso la beta va en
**un solo contenedor** con un proxy interno que reparte el tráfico; nada más queda expuesto.

```
Internet ──HTTPS/WSS──► Render (certificado TLS) ──HTTP──► contenedor alux-beta, puerto $PORT
                                                              │ Caddy (proxy interno)
                         /ws ───────────────────────────────► │ servidor de juego Godot   127.0.0.1:9080
                         /api/v1/* ─────────────────────────► │ API                       127.0.0.1:4000
                         /game/* (estáticos comprimidos) ───► │ archivos del juego exportado
                         lo demás ──────────────────────────► │ portal Next.js            127.0.0.1:3000
                                                              ▼
                                            PostgreSQL de Render (red privada, sin acceso externo)
```

| Pieza | Archivo |
| --- | --- |
| Imagen única | `infra/render/Dockerfile` |
| Proxy interno | `infra/render/Caddyfile` |
| Arranque (valida, migra, levanta y vigila) | `infra/render/start.sh` |
| Blueprint de Render | `render.yaml` |

El despliegue con varios contenedores y Caddy con Let's Encrypt (`infra/docker/`) sigue sirviendo
para un servidor propio; ver [despliegue.md](despliegue.md).

## 1. Costo y recursos que se crean

El Blueprint crea **dos** recursos y ninguno más. No toca otros proyectos de la cuenta.

| Recurso | Nombre | Plan | Región | Costo estimado |
| --- | --- | --- | --- | --- |
| Servicio web (Docker) | `alux-beta` | `0.5c-512mb` (antes *Starter*): 0.5 CPU, 512 MB | Ohio | US$7 al mes |
| PostgreSQL 16 | `alux-beta-db` | `0.1c-256mb` (antes *Basic-256mb*), 1 GB de disco | Ohio | US$6 al mes + US$0.30 por el GB de disco |
| **Total** | | | | **US$13.30 al mes**, cobro recurrente mientras existan |

Precios de <https://render.com/pricing>, consultados el 12 de noviembre de 2026.

- Render cobra por el tiempo que el recurso existe (prorrateado): borrarlos al terminar la beta
  detiene el cargo. El espacio de trabajo *Hobby* cuesta US$0; el *Pro* añade US$25 al mes (no
  hace falta para esta beta).
- **Si la pantalla del Blueprint muestra otra cifra, otro plan u otro recurso, no confirmes.**
  Render enseña el precio exacto antes de crear nada.
- **Posibles cargos adicionales:**
  - *Ancho de banda:* *Hobby* incluye 5 GB de salida al mes; el excedente cuesta US$0.15 por GB.
    Una partida de cuatro jugadores gasta alrededor de 0.4 GB por hora y cada primera carga del
    cliente unos 8 MB: los 5 GB dan para unas 11 horas de partida de cuatro al mes.
  - *Minutos de construcción:* *Hobby* incluye 500 al mes; cada despliegue gasta entre 10 y 15.
- Ohio es la región de Render más cercana a Yucatán junto con Virginia.

**Alternativa sin costo (sólo para una prueba de humo):** cambia en `render.yaml` los dos `plan` a
`free`. Limitaciones: el servicio se duerme tras 15 minutos sin tráfico y tarda cerca de un minuto
en despertar, tiene 0.1 CPU (puede no sostener el servidor de juego con cuatro jugadores) y la base
de datos gratuita **caduca a los 30 días** y no tiene respaldos. No sirve como "PostgreSQL
persistente".

**Alternativa de base de datos:** un proyecto de Supabase. Quita el bloque `databases` y la
referencia `fromDatabase` de `render.yaml` y define `DATABASE_URL` a mano en el panel (cadena de
conexión de Supabase). Las migraciones se aplican igual.

## 2. Preparar la rama `beta` y las invitaciones

El servicio sólo despliega lo que llega a la rama **`beta`**. El trabajo diario sigue en otras
ramas y no se publica solo. Antes de publicar, la revisión previa confirma que es seguro:

```bash
npm run beta:preflight
```

Comprueba que `render.yaml` crea exactamente los dos recursos de la tabla, que no hay secretos en
los archivos ni en el historial de Git, que la imagen no trae accesos de prueba abiertos, que las
invitaciones se validan bien y que ninguna migración borra o altera datos. Al final dice qué
commit se publicaría. Después:

```bash
git push origin claude/tender-johnson-c2gk0s:beta
```

Qué commit corresponde a cada versión publicada: [RELEASES.md](RELEASES.md).

Genera una invitación por tester (ejemplo para cuatro personas, válidas 14 días):

```bash
npm run beta:invites -- --testers "Ana,Luis,Marta,Paco" --days 14
```

El programa imprime dos cosas y no guarda nada en disco:

- **Un código por persona** (`ALUX-XXXXX-XXXXX-XXXXX-XXXXX`). Es su credencial: envíaselo sólo a
  ella, por un canal privado.
- **El valor de `BETA_INVITES`**: una lista de huellas SHA-256 con fecha de vencimiento. Es lo
  único que conoce el servidor; con él no se puede reconstruir ningún código.

## 3. Crear los servicios en Render

1. En <https://dashboard.render.com> → **New → Blueprint** → conecta el repositorio
   `EleevateMX/Kameo` y elige la rama `beta`.
2. Render lee `render.yaml` y muestra los dos recursos con su precio. Revísalo.
3. Te pedirá un solo valor: **`BETA_INVITES`**. Pega el que generaste en el paso 2.
4. **Apply**. La primera construcción tarda unos 10–15 minutos (descarga Godot, exporta el juego
   y compila el portal). El resto de secretos los genera Render.
5. Cuando termine, la URL aparece en el servicio: `https://alux-beta-xxxx.onrender.com`.

No hace falta definir la URL: el contenedor la toma de `RENDER_EXTERNAL_URL` y de ella deriva el
punto de conexión del juego, **`wss://<la misma URL>/ws`**.

## 4. Variables de entorno

Ningún secreto está en Git. Viven en el panel de Render (**Environment**).

| Variable | Quién la pone | Para qué |
| --- | --- | --- |
| `DATABASE_URL` | Render (de `alux-beta-db`, URL interna) | Conexión a PostgreSQL por la red privada. |
| `SESSION_SECRET` | Render (aleatorio) | Firma de las sesiones del portal. |
| `GAME_TICKET_SECRET` | Render (aleatorio) | Firma de los tickets de un solo uso para entrar al juego. |
| `SERVICE_KEY` | Render (aleatorio) | Clave interna entre portal, servidor de juego y API. |
| `BETA_ACCESS` | `render.yaml` (`invite`) | Activa el acceso por invitación. Cualquier otro valor lo apaga. |
| `BETA_INVITES` | Tú, en el panel | Huellas y vencimiento de cada invitación. |
| `PORT`, `RENDER_EXTERNAL_URL` | Render | Puerto público y URL del servicio. |
| `BASE_URL` | Opcional | Sólo con dominio propio: `https://tu-dominio`. |
| `DISCORD_CLIENT_ID`, `DISCORD_CLIENT_SECRET` | Opcional, más adelante | Activan Discord y **apagan** las invitaciones. |
| `ALLOW_DESTRUCTIVE_MIGRATIONS` | Sólo en un despliegue concreto | Permite una migración que borra datos (tras un respaldo). |

En esta imagen la "entrada de prueba" sin restricciones está siempre desactivada.

## 5. Migraciones

Se aplican solas en cada arranque, antes de abrir el puerto (`apps/api/src/migrate.ts`):

- La tabla `schema_migrations` lleva qué versión está aplicada y la huella de su archivo.
- Cada migración va en una transacción: entra completa o no entra. Si falla, el contenedor **no
  arranca** y Render conserva la versión anterior en servicio.
- Un candado de PostgreSQL evita que dos arranques migren a la vez.
- Se niega a ejecutar `DROP TABLE`, `DROP COLUMN`, `TRUNCATE` o `DELETE` salvo que definas
  `ALLOW_DESTRUCTIVE_MIGRATIONS=1` para ese despliegue, después de un respaldo (sección 9).
- Si alguien edita una migración ya aplicada, el arranque se detiene: se crea una nueva.

| Migración | Contenido | Estado |
| --- | --- | --- |
| `20261111000000_init` | Esquema inicial (jugadores, personajes, salas, recompensas…), RLS activado. | Probada en PostgreSQL 16 |
| `20261112000000_beta` | Jugadores con invitación (`provider = 'beta'`) y tabla `session_metrics`. Sólo añade. | Probada en PostgreSQL 16 |

Estado en la base de datos desplegada: se ve en los registros del arranque
(`[migraciones] aplicada …`) o con `DATABASE_URL=… npm run migrate -- --status`.

## 6. Comprobar que está sana

```bash
npm run beta:check -- https://alux-beta-xxxx.onrender.com
```

Comprueba desde fuera: portal por HTTPS, API y base de datos (`/healthz`), que no haya entrada
anónima ni rutas internas, la descarga del juego y que `wss://…/ws` abra y rechace tickets falsos.

```bash
npm run beta:check -- https://alux-beta-xxxx.onrender.com --code ALUX-XXXXX-XXXXX-XXXXX-XXXXX
```

Con el código de un tester (usa uno tuyo, de organizador) entra como él y recorre el camino
completo: sesión, guardado, sala, ticket, cuatro segundos de partida por WebSocket seguro (estados
por segundo y latencia) y registro de métricas. Sale con error si algo falla.

Añade `--commit <hash>` para exigir que lo desplegado sea exactamente ese commit (el servicio lo
informa en `/healthz`), y `--mark Nombre` antes de un reinicio y `--expect Nombre` después para
comprobar que los datos persisten.

**Registros:** en Render, servicio `alux-beta` → **Logs**. Cada línea lleva el proceso que la
escribe:

| Prefijo | Qué es |
| --- | --- |
| `[inicio]` | Arranque: URL pública, invitaciones cargadas, avisos de configuración. |
| `[migraciones]` | Qué migración se aplicó. |
| `[api]` | API; las líneas `[metrics]` son los informes de rendimiento de cada sesión. |
| `[juego]` | Servidor de juego: salas, santuario abierto, emboscadas ganadas o perdidas. |
| `[portal]` | Portal; `[auth] Tester «id» inició sesión`. |
| `[proxy]` | Proxy interno. |

Render reinicia el contenedor si `/healthz` deja de responder o si cualquiera de los procesos
termina.

## 7. Invitar a cuatro testers

1. Genera los códigos (paso 2) y pon `BETA_INVITES` en el panel. Para añadir gente después sin
   invalidar a los anteriores: `npm run beta:invites -- --testers "Sofía" --keep "<valor actual>"`.
2. Crea la sala tú o deja que la cree el primero que entre.
3. Envía a cada persona, **por separado**, un mensaje como este:

   > Te invito a probar ALUX (beta privada).
   > 1. Abre https://alux-beta-xxxx.onrender.com en Chrome o Edge, en una computadora.
   > 2. Entra con tu código personal: `ALUX-…` (no lo compartas; vence el DD/MM).
   > 3. Pulsa «Unirme» y escribe el código de sala que te pase, o usa el enlace de invitación.
   > La partida dura unos 10–15 minutos. Se juega con teclado y ratón; Esc abre el menú.

4. Para **retirar** a alguien, borra su entrada de `BETA_INVITES` y guarda: Render reinicia el
   servicio y su sesión deja de valer. Las invitaciones vencen solas el día indicado.

Cada invitación es una identidad: si dos personas usan el mismo código, comparten alux y la
segunda desconecta a la primera.

## 8. Pruebas reales y métricas

Lo que sólo se puede validar con personas, en sus computadoras:

| Qué validar | Cómo |
| --- | --- |
| Acceso desde una computadora externa | Cada tester entra con su código desde su casa. |
| Carga en Chrome y en Edge | Al menos una persona en cada navegador; anotar el tiempo de la primera carga. |
| Cuatro jugadores desde conexiones distintas | Todos en la misma sala; ver los cuatro en el panel de grupo. |
| Movimiento y transformación sincronizados | Que cada quien diga lo que ve hacer a los demás (correr, 2 = Balam). |
| Altares, combate y emboscada | Ronda completa: cuatro altares, emboscada, purificar con F. |
| Victoria, derrota y reinicio | Una ronda ganada, «Jugar otra ronda» (votan los cuatro) y una perdida a propósito. |
| Reconexión tras cortar Internet | Un tester apaga el wifi 10 s: debe ver «Reconectando…» y volver al mismo lugar. |
| Persistencia | Tras la victoria, reinicia el servicio en Render (*Manual Deploy → Restart*): el sello sigue en el portal. |
| Audio y controles | Preguntar a cada tester si oyó ambiente, música y efectos, y si algún control falló. |
| FPS, latencia, memoria, carga | Se registran solos (abajo). F3 los muestra en pantalla. |

Guía de la sesión y qué observar: [PLAYTEST.md](PLAYTEST.md).

**Métricas automáticas.** Cada navegador envía un resumen cada minuto y al terminar cada ronda:
calidad gráfica elegida (y si la eligió el juego o el jugador), FPS medio y percentil 5, latencia
media y máxima, tiempo desde abrir la página hasta estar dentro, memoria, reconexiones, victorias
y derrotas, resolución, tarjeta gráfica y si el navegador dejó sonar el audio. No incluye nada
personal más allá del identificador del jugador y el navegador.

- En los registros de Render: líneas `[metrics] {…}`.
- En tabla, con acceso a la base de datos (sección 9 para abrirlo de forma temporal):

  ```bash
  DATABASE_URL="<URL externa>" npm run beta:metrics
  ```

## 9. Publicar, volver atrás y respaldar

**Publicar una versión nueva** (sólo cuando esté probada en la rama de trabajo):

```bash
git push origin claude/tender-johnson-c2gk0s:beta
```

Render construye y, si el contenedor nuevo arranca y `/healthz` responde, cambia el tráfico. Si la
construcción o el arranque fallan (incluida una migración), **la versión anterior sigue en
servicio**. Las partidas en curso se cortan al cambiar de versión: los clientes reconectan solos,
pero las salas empiezan de nuevo (el progreso guardado no se pierde).

**Volver atrás (rollback):**

1. Rápido: en Render → `alux-beta` → **Events** → el despliegue bueno → **Rollback**. Vuelve a esa
   imagen sin reconstruir. Comprueba después si el despliegue automático quedó desactivado.
2. Después, deja la rama coherente con un commit que revierta el cambio y vuelve a activar el
   despliegue automático:

   ```bash
   git revert <commit-malo>
   ```

   ```bash
   git push origin HEAD:beta
   ```

Las migraciones sólo añaden, así que una versión anterior del código funciona con el esquema nuevo.
Si alguna vez una migración quita algo, se hace en dos despliegues (primero el código que deja de
usarlo, después la migración) y con respaldo previo.

**Respaldo de los datos.** La base de datos no acepta conexiones externas. Para respaldar:

1. Render → `alux-beta-db` → **Access Control** → añade tu IP. Copia la **External Database URL**.
2. Ejecuta (necesita `pg_dump` 16):

   ```bash
   DATABASE_URL="<URL externa>" scripts/beta-backup.sh
   ```

   Deja `backups/alux-AAAAMMDD-HHMM.dump` (carpeta fuera de Git).
3. Quita tu IP de la lista de acceso.

Restaurar: `DATABASE_URL="<URL externa>" scripts/beta-backup.sh --restore backups/alux-….dump`
(pide confirmación escrita; reemplaza los datos). Haz un respaldo antes de cada sesión de pruebas
importante y antes de cualquier migración que no sea sólo aditiva. Los planes de pago de Render
ofrecen además recuperación a un punto en el tiempo desde su panel.

## 10. Activar Discord y apagar las invitaciones

1. En la aplicación de Discord añade el *redirect* `https://<tu URL>/auth/discord/callback`.
2. En Render define `DISCORD_CLIENT_ID` y `DISCORD_CLIENT_SECRET`.

Con esas dos variables el acceso por invitación **se desactiva por completo**: desaparece el
formulario, la ruta rechaza todo y las sesiones abiertas con invitación dejan de valer. Después
puedes borrar `BETA_INVITES` y poner `BETA_ACCESS=off`.

## Límites de esta beta

- Una sola instancia: portal, API y servidor de juego comparten 0.5 CPU y 512 MB. En la prueba
  local, con el contenedor limitado a 512 MB, usa unos 200–260 MB recién arrancado y unos 300 MB
  con cuatro jugadores en una sala. El margen es justo: si Render lo reinicia por memoria, sube
  el servicio a `1c-2g`. El uso de CPU con jugadores reales no está medido.
- Las salas viven en memoria: un despliegue o un reinicio las vacía (el progreso no).
- Las invitaciones se administran editando una variable; no hay panel de administración.
- El límite de intentos de código cuenta sólo los fallos (8 por IP cada 10 minutos, en memoria del
  proceso); los códigos tienen 100 bits de azar, así que adivinar uno no es viable.
- Sin dominio propio la URL es `*.onrender.com`.
