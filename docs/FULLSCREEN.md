# Pantalla completa

Primer incremento de la Alpha 0.4. Prueba: `npm run test:fullscreen`
([tests/e2e/fullscreen.ts](../tests/e2e/fullscreen.ts)).

## Cómo funciona

- **Se pide con la Fullscreen API dentro del clic del jugador.** El botón **JUGAR** del portal llama
  a `requestFullscreen()` en el mismo clic. Una página no puede pulsar F11 por nadie, y no se
  intenta simular.
- **El juego se abre dentro de la misma página** (`/play/CÓDIGO` muestra `/game/index.html` en un
  marco a pantalla entera). Si se cambiara de página, el navegador quitaría la pantalla completa
  antes de que el juego cargara. La página del juego sigue funcionando abierta directamente.
- **Si el navegador la niega o no la tiene, se entra igual, en ventana.** Nada espera a que se
  conceda.
- **La preferencia se guarda** en el navegador (`alux_fullscreen`): la casilla «Pantalla completa al
  jugar» del portal, y el botón del juego, la cambian.
- **Botón discreto** en la esquina inferior izquierda del juego, y otro en el menú («Pantalla
  completa: sí/no»). Con la partida en marcha el ratón está capturado: Esc lo suelta (abre el menú)
  y entonces se puede pulsar.
- **Esc.** En Chrome y Edge, estando en pantalla completa, Esc llega al juego y abre su menú
  (bloqueo de teclado); mantenerla pulsada sale de pantalla completa. Donde no existe ese bloqueo,
  Esc sale de pantalla completa como siempre. En los dos casos la partida sigue, y **no se vuelve a
  meter al jugador** en pantalla completa sin que lo pida.
- **Quien abre el juego directamente** (enlace antiguo, recarga) entra en pantalla completa con su
  primer clic o tecla si así lo prefiere, una sola vez.
- El audio y la captura del ratón funcionan igual dentro del marco (mismo origen).

## Comprobado

En Chromium (el mismo motor que Chrome y Edge), automatizado:

1. JUGAR deja la página en pantalla completa, el juego carga dentro del portal y la conserva.
2. El audio suena con el juego dentro del portal.
3. El botón del juego sale a ventana y vuelve; la preferencia se guarda.
4. Salir «como con Esc» (lo hace el navegador): la partida continúa y no se vuelve a entrar sola.
5. Con la preferencia desactivada, JUGAR entra en ventana.
6. Si el navegador niega la petición, se entra igual, en ventana.
7. Abriendo el juego directamente, el primer clic la pide, una sola vez.

## Sin comprobar y límites conocidos

| Navegador | Estado |
| --- | --- |
| Chrome y Edge de escritorio | Mismo motor que la prueba; **sin probar a mano**. El bloqueo de Esc sólo existe aquí |
| Firefox | **Sin probar.** Tiene Fullscreen API; no tiene bloqueo de teclado: Esc sale de pantalla completa (la partida sigue en ventana) |
| Safari de escritorio | **Sin probar.** Tiene Fullscreen API (con prefijo en versiones antiguas, que el juego contempla); sin bloqueo de teclado; puede mostrar un aviso propio al entrar |
| Safari en iPhone | No ofrece pantalla completa para páginas (sólo para vídeo): la casilla y el botón no aparecen y se juega en ventana. El juego, además, no tiene controles táctiles |
| Safari en iPad y Chrome en Android | **Sin probar**; sin controles táctiles el juego no es jugable ahí |

La tecla mantenida para salir (Chrome/Edge) y el aviso «Pulsa Esc para salir» los pone el navegador
y no se pueden quitar ni traducir.
