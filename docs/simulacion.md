# Simulación de movimiento: garantías y cómo se prueban

ALUX no usa el motor de física de Godot para los jugadores. El movimiento lo resuelve una
simulación propia (`game/scripts/shared/sim.gd`) que ejecutan **el servidor** (autoridad) y
**el cliente** (predicción de su propio personaje) con exactamente el mismo código.

## Cómo funciona

- Cada mensaje `in` del cliente avanza **un tick** de 1/30 s. No hay "delta" enviado por el cliente.
- El mundo sólido es una lista de cajas, cilindros y una función de altura (`world_def.gd`),
  idéntica en ambos lados.
- El desplazamiento horizontal se aplica en **sub-pasos de 0.25 m como máximo**. Tras cada sub-paso
  se resuelven las colisiones en hasta 4 pasadas y, si el cuerpo sigue solapando algo, **el paso se
  descarta**: nunca se acepta una posición inválida.
- Temporizadores (enfriamientos, esquiva, carga) en **ticks enteros** y energía en pasos de 0.5:
  viajan por la red sin redondeo, así que cliente y servidor coinciden exactamente en cuándo se
  puede usar cada habilidad.
- Velocidad horizontal con tope absoluto (`MAX_HSPEED`), incluidos esquiva, salto ofensivo y empujones.

## Qué impide cada trampa

| Intento | Por qué no funciona |
| --- | --- |
| Atravesar muros o la puerta | Sub-pasos + rechazo de posiciones inválidas. El más rápido (esquiva, 0.6 m/tick) nunca cruza un muro de 1 m ni la puerta de 0.7 m. |
| Entrar al santuario saltando el muro | Mientras está cerrado, un sello sólido cubre todo el interior hasta 40 m de altura. |
| Ir más rápido | El servidor calcula la velocidad a partir de la forma; el vector de entrada se recorta a longitud 1. |
| Mandar más entradas por segundo | Presupuesto de 1 entrada por tick de servidor (ráfaga 8, cola 12). El exceso se descarta. |
| Saltarse enfriamientos o energía | Viven en el estado del servidor; el cliente sólo manda "botón pulsado". |
| Explotar diferencias entre clientes | No hay nada que explotar: el resultado es el del servidor. Una diferencia sólo provoca una corrección visual en ese cliente. |
| Valores absurdos (NaN, 1e9) | El servidor sanea cada campo antes de simular. |

## Pruebas

```bash
scripts/test-sim.sh
```

`game/tests/sim_fuzz.gd` ejecuta la simulación real sin ventana y comprueba **en cada tick**:

1. **Paseantes aleatorios** (240 × 900 ticks) por todo el claro, con todas las habilidades, cambios
   de forma y empujones: nunca dentro de una caja o cilindro, nunca fuera del claro, nunca bajo el
   suelo, energía y enfriamientos en rango.
2. **Asalto al santuario cerrado** (280 atacantes × 700 ticks) desde todos los lados y desde la ladera
   de detrás, esquivando, saltando y recibiendo empujones hacia dentro: ninguno entra.
3. **Obstáculos y borde**: empuje continuo contra árboles, columnas y el límite del claro.
4. **Velocidad sostenida**: 6 s en línea recta machacando todos los botones; la distancia no supera
   la cota teórica (carrera + esquivas o saltos limitados por su enfriamiento).
5. **Determinismo**: mismas entradas → estado final idéntico bit a bit.
6. **Predicción**: un cliente que parte del estado redondeado de la red y repite las mismas entradas
   no se separa del servidor más de 2 cm, y sus temporizadores y energía coinciden exactamente.

Último resultado: **427 840 comprobaciones, 0 violaciones**; separación máxima entre predicción y
servidor, 1.2 mm.

Esta prueba encontró y permitió corregir tres fallos reales antes de llegar a los jugadores:

- un rincón entre dos cajas muy juntas donde el cuerpo quedaba 5 cm dentro de una de ellas;
- el santuario se podía saltar desde la ladera con Balam, evitando el acertijo;
- el redondeo de red podía hacer que el cliente activara una esquiva un tick antes que el servidor.

`tests/protocol.test.ts` cubre lo mismo desde fuera, contra el servidor real: ráfagas de entradas,
vectores enormes, mensajes inventados y la puerta cerrada.

## Límites conocidos

- Los enemigos usan las mismas colisiones pero no tienen búsqueda de caminos: rodean obstáculos con
  una maniobra simple y pueden quedarse atascados detrás de muros largos.
- No hay compensación de latencia para los golpes cuerpo a cuerpo: el servidor usa su posición actual
  de enemigos y jugador. Con latencias altas el jugador notará que debe acercarse un poco más.
- La regla de diseño "no dejar huecos más estrechos que el cuerpo (0.8 m) entre dos sólidos" se
  respeta a mano; conviene automatizarla cuando haya más escenarios.
