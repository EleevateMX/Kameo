# Pendientes y validaciones que faltan

Estado tras el primer incremento de la Alpha 0.2. El plan por versiones está en
[ROADMAP.md](ROADMAP.md); aquí va lo que falta por hacer o por validar. Nada de lo que aparece aquí
como pendiente debe darse por hecho.

## Lo primero que falta para la beta con personas

- **Primera sesión con testers reales.** La Closed Alpha 0.1 está publicada en
  <https://alux-beta.onrender.com> y comprobada desde fuera con un jugador; falta jugarla con cuatro
  personas a la vez. Las invitaciones ya están generadas.
- **Aviso de pago en Render.** Seguía activo en la última captura; puede suspender el servicio.
- **Nadie ha escuchado el audio.** Está generado por código y sólo se ha medido (niveles, espectro,
  bucles sin corte). Hay que oírlo en el juego y ajustar la mezcla o sustituir lo que suene mal.
- **Nadie ha jugado la build con GPU ni por Internet.** Todo se ha probado con render por software
  (2–8 FPS), con bots y en una sola máquina. Las métricas de cada sesión real quedarán registradas.
- **Equilibrio sin probar con personas**: daño, vida, energía, duración de la emboscada y dificultad
  para uno o dos jugadores.
- **Edge sin probar**: las pruebas automáticas usan Chromium.

## Integraciones que dependen de credenciales o infraestructura

| Tema | Estado | Qué falta exactamente |
| --- | --- | --- |
| **Discord OAuth2 real** | **Pendiente** | No hay aplicación de Discord. El flujo está implementado y probado con credenciales ficticias (redirección, `state`, cancelación, respuesta manipulada), pero el canje del código con Discord y la lectura del perfil no se han ejecutado nunca contra Discord. Hace falta `DISCORD_CLIENT_ID` y `DISCORD_CLIENT_SECRET` y repetir la prueba con cuatro cuentas reales. |
| **Supabase alojado** | **Pendiente** | El proyecto ALUX **no llegó a crearse**: Supabase pidió una confirmación de costo que no se respondió a tiempo. No se tocó ningún otro proyecto. Además, el entorno de desarrollo no tiene salida TCP hacia PostgreSQL, así que la conexión API ↔ Supabase habrá que probarla desde el servidor real. |
| Esquema y RLS | Validado sólo en local | La migración se aplica limpia en PostgreSQL 16 (local y en contenedor) y las pruebas de la API pasan contra él. RLS está activado sin políticas en las 10 tablas. Falta aplicarla en Supabase, pasar sus *advisors* de seguridad y comprobar con la clave pública (`anon`) que no se puede leer ni escribir nada. |
| **Beta en Render** | Preparada, **sin desplegar** | Imagen única, Blueprint, acceso por invitación, migraciones automáticas, métricas, comprobación, rollback y respaldo: hechos y probados en local con `scripts/test-beta-image.sh` (HTTPS/WSS a través de dos proxies, 512 MB, reinicio con persistencia, cuatro navegadores). Falta crear los servicios (cuenta y costo), comprobar la conexión por la red privada de Render y medir con testers reales. |
| **Docker + HTTPS/WSS** | Probado en local | `scripts/test-deploy.sh` construye las tres imágenes y verifica portal por HTTPS, rutas internas cerradas, sesión con cookie `Secure`, guardado en PostgreSQL, ticket y entrada al juego por `wss://` a través de Caddy. Falta: un VPS real, un dominio con certificado de Let's Encrypt (aquí se usó el certificado interno de Caddy para `localhost`) y Supabase como base de datos. |
| **Rendimiento con GPU** | **Pendiente** | No había GPU. Todo lo medido en navegador es render por software (1.5–8 FPS), no representativo; ahí la escena nueva cuesta un 40 % más que la anterior. Las herramientas están listas (F3 en el juego, `E2E_GPU=1 npm run test:e2e`, `docs/rendimiento.md`). |
| Latencia por Internet | **Pendiente** | Sólo se ha jugado con cliente y servidor en la misma máquina. |
| Respaldo antes de migraciones destructivas | No aplica todavía | La única migración crea tablas en un proyecto vacío. Cuando haya datos, el procedimiento será: `pg_dump` (o respaldo de Supabase), revisar el alcance del cambio y sólo entonces aplicar. |

## Verificado en esta fase

- **Cuatro jugadores simultáneos**: con bots contra el servidor real (acertijo + emboscada completa) y con
  cuatro navegadores (movimiento, transformación, combate y reconexión).
- **Servidor autoritativo**: tickets, velocidad, teletransporte, formas, daño, enfriamientos, energía y
  recompensas no se pueden falsear desde el cliente (`tests/protocol.test.ts`).
- **Simulación propia**: 427 840 comprobaciones sin violaciones con el escenario nuevo (`docs/simulacion.md`).
- **Despliegue en contenedores** en una sola máquina.

## Juego

- **Arte** (detalle en [ART_BIBLE.md](ART_BIBLE.md))
  - **Enemigos: siguen hechos con primitivas** (sólo se recolorearon). Es lo que más desentona ahora.
  - Alux y Balam: segunda pasada hecha (rostro, manos, ropa, rosetas, animaciones nuevas). Quedan:
    cabeza de Balam (nariz pesada, perfil algo de oso), uniones visibles de cerca en las articulaciones,
    mangas del alux que atraviesan el canesú al levantar los brazos, y una boca que sólo abre y cierra.
  - Las animaciones se han revisado en cuadros fijos; **falta verlas en movimiento con GPU** (ritmo,
    transiciones y que el pie no patine al correr, que está calculado pero no observado).
  - Escenario: hecho por código con color por vértice. Faltan variedad de ruinas, fauna ambiental y
    un ciclo de luz. Sin texturas por decisión de rendimiento.
  - En el render por software de las pruebas, las sombras se ven tenues; falta confirmarlas con GPU.
  - HUD: sin minimapa (hay brújula), sin opciones dentro del juego para cambiar la calidad (hoy va por
    dirección `?q=` o automática) y sin adaptación a pantallas pequeñas o táctiles.
  - Audio provisional sintetizado (38 archivos): suficiente para probar, no definitivo. Sin voces,
    sin sonido posicional real (sólo se atenúa por distancia) y sin música adaptativa.
  - Cinemática de introducción: aplazada hasta tener modelos definitivos (decisión del proyecto).
- **Historia (Alpha 0.2)**
  - Hecho: introducción dentro del motor, Chiich Yaxché con modelo propio y diálogo, primer objetivo
    narrativo, cinemáticas compartidas con voto de mayoría («El sello cede») y progreso del capítulo
    guardado en el perfil.
  - Sin probar con personas: si el voto para omitir se entiende y si la pausa de la sala molesta.
  - El perfil guarda que se escuchó el llamado, pero una sala nueva empieza la historia desde el
    principio: todavía no se salta lo ya visto por todo el grupo.
  - El rebozo de la abuela es rígido: en los gestos amplios se nota.
  - Los planos del motor sólo mueven la cámara, ponen texto y lanzan un sonido; todavía no animan
    personajes. Hay fundido al entrar y al salir de las compartidas, no entre planos.
  - Los diálogos son lineales, sin voces, y sólo en español.
  - Nombres de espíritus y antagonista: aprobados como nombres de trabajo; falta la revisión de un
    hablante de maya yucateco.
  - Kling: storyboard de «El vínculo de Balam» aprobado y una toma de prueba hecha (50 créditos por
    5 s). Presupuestos por escena en [CINEMATICS.md](CINEMATICS.md), **todos sin aprobar**.
- **Cinemáticas con vídeo (Alpha 0.3)**
  - Hecho: reproducción en el navegador, respaldo del motor por plano, fases de preparación y
    reanudación, reconexión, métricas, y **«El sello cede» producida con Kling e integrada**.
  - **Sin publicar:** la beta lleva la Alpha 0.2, donde esa escena todavía es la del motor.
  - Sin probar: Safari y Firefox, tarjeta gráfica, sonido dentro de un vídeo, personas.
  - El vídeo deja niebla y vetas magenta en el patio que el juego no tiene; no se nota porque se
    vuelve por fundido a la cámara del jugador, fuera del patio.
  - Las etiquetas de versión `alpha-0.1` y `alpha-0.2` no se pudieron subir desde este entorno
    (el servicio de Git rechazó la subida de etiquetas). Los commits son `12fadbe` y `c28e32c`.
  - Precios de Kling sin medir: planos con personajes, sonido generado, 720p y 4K.
  - La introducción («El llamado») es local y empieza nada más entrar: cuando tenga vídeo habrá
    que esperar su precarga unos segundos antes de empezarla. Sin hacer.
  - Modelos: corregidos los hilos finos de las prendas (alux, Yaxché, cola de Balam), que quedaban
    como ranuras; las hojas de referencia coinciden con los modelos.
  - Modelos: el cabello del alux atraviesa la cinta del sombrero de palma; a Yaxché le asoman los
    hombros por el rebozo; por detrás, las patas traseras de Balam se ven huecas.
  - «El vínculo de Balam»: los planos 1, 2 y 4 muestran al alux con un aspecto fijo; hay que
    adaptarlos (sombra, punto de vista o tramo con el motor).
- **Partida**
  - Hecho: ciclo completo (bienvenida, altares, emboscada, victoria o derrota, otra ronda, salir),
    menú con ajustes y avisos de conexión. Detalle en [PLAYTEST.md](PLAYTEST.md).
  - La derrota exige que todo el grupo conectado esté caído a la vez; con cuatro jugadores será rara.
    Falta decidir con pruebas si hace falta otra condición (tiempo límite, vidas del grupo).
  - Otra ronda necesita el voto de todos: si alguien se queda ausente sin desconectarse, bloquea.
  - Sin pausa real (es multijugador): el menú deja al personaje quieto pero la partida sigue.
  - Los ajustes se guardan en el navegador, no en el perfil.
- **Combate**
  - Sin jefe final ni más tipos de enemigo.
  - Los enemigos no tienen búsqueda de caminos: rodean obstáculos con una maniobra simple.
  - Sin compensación de latencia en los golpes cuerpo a cuerpo.
  - El equilibrio (daños, vida, energía) no se ha probado con personas.
  - "Interactuar" se limita al brasero y a purificar criaturas; no hay más objetos.
- **Controles**: sólo teclado y ratón. Sin mando ni controles táctiles (no se puede jugar en móvil).
  Las teclas no se pueden reasignar. Tras salir del modo ratón con Esc, Chrome tarda cerca de un
  segundo en dejar capturarlo otra vez.
- **Contenido**: un solo escenario. Faltan misiones, el resto del capítulo 1 y las demás transformaciones.

## Técnica

- Al reconectarse, un cliente no recibe los eventos de combate del hueco (números de daño, efectos); su
  estado sí es correcto porque viene completo del servidor.
- En equipos sin GPU, recargar la página con varios juegos abiertos tarda minutos (compilación de shaders).
- El emparejador vive dentro de la API; un solo proceso de juego aloja hasta 64 salas.
- Sin telemetría, panel de administración ni límites por IP (sólo por jugador y por conexión).
- La regla "no dejar huecos de menos de 0.8 m entre sólidos" se cumple a mano.

## Orden sugerido

1. Crear la beta en Render ([beta.md](beta.md)), pasar `npm run beta:check` e invitar a cuatro testers.
2. Con los resultados (métricas, audio, equilibrio), ajustar y dar las credenciales de Discord.
3. Modelar los enemigos con el mismo método que los personajes; revisar animaciones con GPU; sonido.
4. Jefe del capítulo 1 y la siguiente transformación (Guardián del Cenote).
