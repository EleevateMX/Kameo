# Pendientes y validaciones que faltan

Estado tras la Fase 3 y la mejora de dirección artística. Nada de lo que aparece aquí como pendiente
debe darse por hecho.

## Integraciones que dependen de credenciales o infraestructura

| Tema | Estado | Qué falta exactamente |
| --- | --- | --- |
| **Discord OAuth2 real** | **Pendiente** | No hay aplicación de Discord. El flujo está implementado y probado con credenciales ficticias (redirección, `state`, cancelación, respuesta manipulada), pero el canje del código con Discord y la lectura del perfil no se han ejecutado nunca contra Discord. Hace falta `DISCORD_CLIENT_ID` y `DISCORD_CLIENT_SECRET` y repetir la prueba con cuatro cuentas reales. |
| **Supabase alojado** | **Pendiente** | El proyecto ALUX **no llegó a crearse**: Supabase pidió una confirmación de costo que no se respondió a tiempo. No se tocó ningún otro proyecto. Además, el entorno de desarrollo no tiene salida TCP hacia PostgreSQL, así que la conexión API ↔ Supabase habrá que probarla desde el servidor real. |
| Esquema y RLS | Validado sólo en local | La migración se aplica limpia en PostgreSQL 16 (local y en contenedor) y las pruebas de la API pasan contra él. RLS está activado sin políticas en las 10 tablas. Falta aplicarla en Supabase, pasar sus *advisors* de seguridad y comprobar con la clave pública (`anon`) que no se puede leer ni escribir nada. |
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

- **Arte** (detalle en [direccion-artistica.md](direccion-artistica.md))
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
  - Sin sonido y sin música.
  - Cinemática de introducción: aplazada hasta tener modelos definitivos (decisión del proyecto).
- **Combate**
  - Sin jefe final ni más tipos de enemigo.
  - Los enemigos no tienen búsqueda de caminos: rodean obstáculos con una maniobra simple.
  - Sin compensación de latencia en los golpes cuerpo a cuerpo.
  - El equilibrio (daños, vida, energía) no se ha probado con personas.
  - "Interactuar" se limita al brasero y a purificar criaturas; no hay más objetos.
- **Controles**: sólo teclado y ratón. Sin mando ni controles táctiles (no se puede jugar en móvil).
- **Contenido**: un solo escenario. Faltan misiones, el resto del capítulo 1 y las demás transformaciones.

## Técnica

- Al reconectarse, un cliente no recibe los eventos de combate del hueco (números de daño, efectos); su
  estado sí es correcto porque viene completo del servidor.
- En equipos sin GPU, recargar la página con varios juegos abiertos tarda minutos (compilación de shaders).
- El emparejador vive dentro de la API; un solo proceso de juego aloja hasta 64 salas.
- Sin telemetría, panel de administración ni límites por IP (sólo por jugador y por conexión).
- La regla "no dejar huecos de menos de 0.8 m entre sólidos" se cumple a mano.

## Orden sugerido

1. Confirmar la creación del proyecto de Supabase y dar las credenciales de Discord.
2. Desplegar en un VPS con dominio y repetir `tests/deploy-check.ts` y la prueba de 4 navegadores con GPU.
3. Modelar los enemigos con el mismo método que los personajes; revisar animaciones con GPU; sonido.
4. Jefe del capítulo 1 y la siguiente transformación (Guardián del Cenote).
