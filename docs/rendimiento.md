# Rendimiento: cómo medirlo

## Dentro del juego

Pulsa **F3** para ver, actualizado cada segundo:

- **FPS** del navegador.
- **ping**: ida y vuelta al servidor de juego (mensaje `ping`/`pong` cada 2 s).
- **estados/s**: estados del servidor recibidos (lo normal son 15).
- **dibujados**: llamadas de dibujo del cuadro.
- **memoria**: memoria del motor y, en Chrome/Edge, la del montón de JavaScript.

Con `?debug=1` en la dirección, los mismos datos quedan en `window.__aluxState.perf`.

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
| Navegador **sin GPU** (render por software, entorno de pruebas), un jugador a 640×360 | 2.4 FPS en calidad alta, 7.6 FPS en calidad baja. No es representativo de un jugador real. Con y sin los modelos de Blender el resultado es el mismo. |
| Navegador **con GPU** | **Pendiente.** No había GPU disponible en el entorno donde se desarrolló. |
| Latencia real por Internet | **Pendiente.** Sólo se ha probado en la misma máquina (ping < 5 ms). |

## Presupuesto pensado para navegador

- Personajes: ≤ 8 000 triángulos cada uno, sin texturas (materiales de color plano).
- Escenario: terreno de ~33 000 triángulos, árboles y arbustos con instanciado (3 llamadas de dibujo).
- Efectos: mallas pequeñas sin iluminación; se precalientan al cargar para evitar tirones.
- Red: ~15 estados/s de unos 2 KB con 4 jugadores y una emboscada completa.
- Descarga: motor de 9 MB comprimido (una vez, luego en caché) + ~1 MB de juego.

El juego baja solo a calidad baja si durante 8 s no llega a 20 FPS (`?q=high` lo impide y `?q=low`
la fuerza desde el principio). Si en una GPU modesta no se alcanzan 60 FPS, las primeras palancas son:
calidad baja (sin sombras ni resplandor, 60 % de resolución interna), reducir `directional_shadow/size` en `project.godot` y
bajar el número de luces puntuales del escenario.
