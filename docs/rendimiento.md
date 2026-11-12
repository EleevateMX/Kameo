# Rendimiento: cómo medirlo

## Dentro del juego

Pulsa **F3** para ver, actualizado cada segundo:

- **FPS** del navegador.
- **ping**: ida y vuelta al servidor de juego (mensaje `ping`/`pong` cada 2 s).
- **estados/s**: estados del servidor recibidos (lo normal son 15).
- **dibujados**: llamadas de dibujo del cuadro.
- **memoria**: memoria del motor y, en Chrome/Edge, la del montón de JavaScript.

Con `?debug=1` en la dirección, los mismos datos quedan en `window.__aluxState.perf`, junto con los
triángulos (`tris`) y objetos (`objects`) dibujados en el cuadro.

## Medición automática con GPU

En una computadora con tarjeta gráfica, con ALUX corriendo:

```bash
E2E_GPU=1 E2E_HEADED=1 npm run test:e2e
```

Abre cuatro navegadores visibles usando la GPU (sin `E2E_GPU=1` fuerza render por software) y al
final imprime los FPS de cada uno. `npm run shots -w @alux/tests` hace lo mismo con un navegador a
1280×720 y tres bots, y muestra `rendimiento` al terminar.

## Qué se ha medido hasta ahora

| Entorno | Resultado |
| --- | --- |
| Servidor de juego (Godot sin ventana) durante la prueba de red (varias salas, hasta 4 jugadores y 12 enemigos cada una) | 30 ticks/s; ~100 MB de memoria; ~5 % de un núcleo en una muestra puntual. Falta una prueba de carga con muchas salas. |
| Navegador **sin GPU** (render por software, entorno de pruebas), un jugador a 640×360 | 1.5 FPS en calidad alta, 5.3 en baja y 8.4 en mínima (ver la comparación de abajo). No es representativo de un jugador real. |
| Imagen única de la beta (portal + API + servidor de juego + proxy), contenedor limitado a 512 MB | 200–260 MB recién arrancada; ~300 MB con cuatro navegadores en una sala. Descarga del cliente: 7.8 MB comprimidos (el `.wasm` de 36 MB va en Brotli). Medido en local, no en Render. |
| Alpha 0.2, incremento 1 (introducción, personaje y diálogo), mismo método | Sin diferencia medible en cuadros por segundo frente a la versión anterior medida el mismo día (7.2 en mínima, 5.0 en baja); unas 25–30 llamadas de dibujo más. Una luz propia para el personaje se descartó: en el navegador cada luz extra obliga a redibujar lo que alcanza. |
| Alpha 0.2, incremento 2 (modelo propio de Chiich Yaxché, cinemática compartida), mismo método | 6.7 en mínima y 4.7 en baja: alrededor de un 7 % menos que el incremento 1, por pasar de piezas sueltas a un modelo con esqueleto (8 599 triángulos, 39 huesos). Cerca del margen de error; por confirmar con GPU. |
| Alpha 0.3, incremento 1 (cinemáticas con vídeo), mismo método | En juego, sin cambio: 6.9 en mínima y 4.8 en baja. Durante una escena con vídeo el mundo 3D no se dibuja (el bucle del juego va a 16–19 cuadros/s frente a 5–5.5 con la escena del motor); el vídeo lo decodifica el navegador aparte. |
| Navegador **con GPU** | **Pendiente.** No había GPU disponible en el entorno donde se desarrolló. |
| Latencia real por Internet | **Pendiente.** Sólo se ha probado en la misma máquina (ping < 5 ms). |

## Costo de la mejora visual (antes y después)

Misma medición en los dos casos: un jugador solo en la sala, 640×360, Chromium con render por
software (sin GPU), 15 s contando cuadros reales con `tests/e2e/perf-probe.ts`, nivel de calidad fijado.

| | Antes (Fase 3) | Después (dirección artística) |
| --- | --- | --- |
| **Alta**: cuadros por segundo | 2.5 | 1.5 |
| **Alta**: llamadas de dibujo | 248 | 285–321 |
| **Alta**: triángulos por cuadro | 243 778 | 312 208 |
| **Baja**: cuadros por segundo | 8.4 | 5.3 |
| **Baja**: llamadas de dibujo | 121 | 250 |
| **Baja**: triángulos por cuadro | 95 394 | 165 686 |
| **Mínima** (nivel nuevo): cuadros por segundo | no existía | 8.4 |
| **Mínima**: llamadas de dibujo / triángulos | no existía | 245 / 104 706 |
| Descarga del juego (`index.pck`) | 596 188 bytes | 1 156 100 bytes |
| Personajes: materiales por cuerpo | 15 (alux) y 8 (Balam) | 4 y 4 |
| Personajes: triángulos | 7 548 y 7 740 | 9 454 y 8 956 |

Lectura honesta de la tabla:

- En render por software la escena nueva cuesta **alrededor de un 40 % más** en alta y en baja. El nivel
  **mínimo** nuevo recupera el rendimiento que antes tenía el nivel bajo.
- El aumento de llamadas de dibujo viene del escenario (estelas, pilares, ruinas y flora son más piezas)
  y del HUD dibujado por código. No se ha separado cuánto aporta cada uno.
- Los triángulos en alta se cuentan dos veces cuando hay sombras (pase de sombras + pase de color). El
  terreno ya no proyecta sombra (sólo la recibe), lo que ahorró unos 90 000 triángulos por cuadro.
- **Sigue sin haber medición con GPU.** Estos números sirven para comparar antes y después, no para
  saber cómo irá en la computadora de un jugador.
- Las pruebas automáticas de cuatro navegadores corren en calidad mínima (`&q=min`) porque en este
  entorno sin GPU los otros niveles van demasiado lentos para ellas.

## Presupuesto pensado para navegador

- Personajes: ≤ 9 500 triángulos cada uno, sin texturas, 4 materiales por cuerpo (color y oclusión en los vértices).
- Escenario: terreno de ~33 000 triángulos; árboles, palmas, helechos, flores y hierba con instanciado;
  piedra tallada en mallas fusionadas con color por vértice (un solo material de piedra).
- Agua, llama y sello del santuario: un shader pequeño cada uno, sin texturas.
- Efectos: mallas pequeñas sin iluminación; se precalientan al cargar para evitar tirones.
- Red: ~15 estados/s de unos 2 KB con 4 jugadores y una emboscada completa (la mejora visual no la cambió).
- Descarga: motor de 9 MB comprimido (una vez, luego en caché) + ~1.2 MB de juego.

## Niveles de calidad

| Nivel | Cambios respecto al anterior | Parámetro |
| --- | --- | --- |
| Alta | Sombras, resplandor, suavizado 2×, partículas, flora menuda, selva de fondo. | `?q=high` (no baja sola) |
| Baja | Sin sombras, resplandor, partículas ni flora menuda; 60 % de resolución interna. | `?q=low` |
| Mínima | Además sin cordilleras, pirámide lejana ni nubes; 50 % de resolución interna. | `?q=min` |

Sin parámetro, el juego empieza en alta y baja un nivel cada vez que pasa 8 s por debajo de 20 FPS.
Con `?q=low` empieza en baja y todavía puede bajar a mínima. El nivel sólo afecta a lo que dibuja ese
navegador. Si en una GPU modesta no se alcanzan 60 FPS, las siguientes palancas son reducir
`directional_shadow/size` en `project.godot` y fusionar más piezas estáticas del escenario.
