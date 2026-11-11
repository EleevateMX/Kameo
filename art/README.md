# Arte 3D de ALUX

Personajes originales del juego, generados por código con Blender (módulo `bpy`),
sin texturas: el color va en los vértices, con oclusión ambiental horneada. Todo es
reproducible: los `.glb` salen idénticos, byte a byte, cada vez que se ejecutan los scripts.

| Archivo | Qué es |
| --- | --- |
| `blender/build_alux.py` | Genera `game/assets/characters/alux.glb` (el alux y sus cuatro tocados). |
| `blender/build_balam.py` | Genera `game/assets/characters/balam.glb` (Balam, el jaguar). |
| `blender/alux_common.py` | Utilidades: mallas, dibujos recortados en la superficie, oclusión, esqueleto, cinemática inversa, horneado de animaciones, exportación, renders. |
| `blender/render_previews.py` | Renders de vista previa en `previews/` y retratos del HUD en `game/assets/ui/`. |
| `godot/check_characters.gd` | Comprobación sin ventana de lo que Godot importa. |
| `godot/render_check.gd` | Capturas con el renderer real de Godot (bajo `xvfb`). |
| `previews/` | Renders de referencia. `*_hoja.png` es la hoja de contacto; `godot_validacion.png` son capturas hechas con Godot. |

## Cómo regenerar

Blender no hace falta: basta el módulo `bpy` (rueda de PyPI, Python 3.13).

```bash
python3 -m venv .tools/blender-venv
.tools/blender-venv/bin/pip install bpy numpy Pillow      # bpy 5.3.0

.tools/blender-venv/bin/python art/blender/build_alux.py
.tools/blender-venv/bin/python art/blender/build_balam.py
.tools/blender-venv/bin/python art/blender/render_previews.py alux        # opcional
.tools/blender-venv/bin/python art/blender/render_previews.py balam       # opcional
.tools/blender-venv/bin/python art/blender/render_previews.py portraits   # retratos del HUD

# comprobar en Godot
.tools/godot --headless --path game --import
.tools/godot --headless --path game --script "$PWD/art/godot/check_characters.gd"
xvfb-run -a .tools/godot --rendering-driver opengl3 --path game --resolution 480x480 \
    --script "$PWD/art/godot/render_check.gd" -- /tmp/capturas
```

Los renders usan Cycles en CPU con 2 hilos. Para cambiar una forma, un color o una
animación se edita el script y se vuelve a ejecutar. Las animaciones están al final de
cada `build_*.py`: son funciones de tiempo o listas de poses clave, con los ángulos en
grados sobre los ejes del modelo; los pies y las garras se plantan con cinemática
inversa (canales `IK_*`).

## Contrato con el juego

- 1 unidad = 1 metro. Origen en los pies. En Godot el personaje mira a **+Z**.
- Cada `.glb` se importa como `Node3D > Armature > Skeleton3D > mallas`, con un
  `AnimationPlayer` en la raíz. Todas las mallas van con piel (skin) sobre el esqueleto.
- **Color de vértice.** Godot activa solo `vertex_color_use_as_albedo` en todos los
  materiales al importar; no hay que tocar nada. Los colores van codificados en sRGB
  porque así los muestra el renderer Compatibility (`vertex_color_is_srgb` queda en
  `false`, y así debe seguir). Si el juego sustituye un material por otro propio y
  quiere conservar la oclusión horneada, el nuevo debe llevar
  `vertex_color_use_as_albedo = true`.
- Los materiales se localizan por nombre de superficie
  (`mesh.surface_get_material(i).resource_name`), no por índice. Son de una sola cara.
- Las animaciones cíclicas cierran exactas, pero Godot las importa sin bucle.
- Todas las animaciones llevan pista en los mismos huesos, así que cambiar de una a
  otra no deja restos de la pose anterior. Ninguna desplaza la raíz.

### `alux.glb` — 9 454 triángulos, 632 KB, 33 huesos

Mide 1.30 m hasta la coronilla (1.47 m con sombrero, 1.61 m con penacho).

| Nodo (MeshInstance3D) | Uso | Triángulos | Materiales |
| --- | --- | --- | --- |
| `Alux` | cuerpo, siempre visible | 7 012 | `Body`, `Tunic`, `Eye`, `Jade` |
| `Hat_Palma` | sombrero de palma con pluma | 656 | `Headwear`, `Jade` |
| `Hat_Penacho` | penacho de plumas | 976 | `Headwear`, `Jade` |
| `Hat_Flor` | flor de mayo (con `Hair`) | 504 | `Headwear` |
| `Hair` | cabello oscuro; va bien con los tres tocados | 306 | `Headwear` |

- `Body`: blanco, todo el color está en los vértices (piel, bordados, faja, huaraches…).
- `Tunic`: color del jugador (se exporta en `#2ec4a6`); sus vértices solo llevan
  sombra y costuras, en gris.
- `Eye`: iris de jade emisivo (energía 1.2). `Jade`: amuleto, pulsera y arete, emisivo suave.
- `Headwear`: blanco con color de vértice, para tocados y cabello.

| Animación | Duración | Tipo | Notas |
| --- | --- | --- | --- |
| `Idle` | 3.0 s | ciclo | respira, cambia el peso, mira de reojo, parpadea, sacude una oreja |
| `Run` | 0.333 s | ciclo | compuesta para **5.2 m/s**; cada pie plantado retrocede exactamente a esa velocidad |
| `Jump` | 0.4 s | una vez | se agacha (0.07 s), despega y queda en pose de subida |
| `Fall` | 0.6 s | ciclo | |
| `Land` | 0.267 s | una vez | aplastamiento máximo a 0.07 s |
| `Swim` | 1.2 s | ciclo | ya incluye el cuerpo inclinado ~60° hacia delante |
| `Cast` | 0.4 s | una vez | mano derecha; brazo extendido (lanzamiento) a **0.10 s** |
| `Dodge` | 0.3 s | una vez | voltereta hacia delante |
| `Interact` | 0.6 s | una vez | |
| `Hit` | 0.3 s | una vez | golpe a 0.045 s, da un paso atrás y vuelve |
| `Death` | 0.9 s | una vez | cae de espaldas (hacia −Z); se queda en el último cuadro |
| `Transform` | 0.5 s | una vez | sale de una bolita, salta con los brazos abiertos (0.10 s) y cae en reposo |

### `balam.glb` — 8 956 triángulos, 656 KB, 30 huesos

Mide 1.70 m de la nariz a la grupa (2.24 m con la cola) y 0.81 m a la cruz. Un solo
nodo de malla, `Balam`, con los materiales `Body` (color de vértice: pelaje y rosetas),
`Collar` (color del jugador, `#2ec4a6`), `Eye` (jade emisivo, 1.2) y `Jade` (amuleto,
glifos de los hombros y ajorcas, emisivo suave).

| Animación | Duración | Tipo | Notas |
| --- | --- | --- | --- |
| `Idle` | 3.0 s | ciclo | |
| `Run` | 0.4 s | ciclo | galope compuesto para **8.4 m/s**; traseras en los cuadros 0–3, delanteras en 6–9 |
| `Jump` | 0.4 s | una vez | se recoge (0.07 s) y salta estirado |
| `Fall` | 0.6 s | ciclo | |
| `Land` | 0.267 s | una vez | |
| `Swim` | 0.9 s | ciclo | |
| `Claw` | 0.333 s | una vez | garra delantera derecha; contacto a **0.10 s** |
| `Charge` | 0.5 s | ciclo | agazapado, tiembla y azota la cola |
| `ChargeRelease` | 0.467 s | una vez | parte de la pose de `Charge`; las dos garras golpean a **0.15 s** |
| `Pounce` | 0.5 s | una vez | estirado en el aire a 0.30 s; acaba cayendo con las garras por delante |
| `PounceLand` | 0.367 s | una vez | sigue a `Pounce`: impacto sobre las delanteras (0.07 s) y luego las traseras |
| `Hit` | 0.3 s | una vez | |
| `Death` | 1.0 s | una vez | cae sobre su costado derecho; se queda en el último cuadro |
| `Transform` | 0.6 s | una vez | brota, se alza rugiendo (0.14–0.28 s), deja caer las garras (0.40 s) y se asienta |

### Retratos del HUD

`game/assets/ui/portrait_alux.png` y `portrait_balam.png`: 256×256, fondo
transparente, unos 11 KB cada uno, con el personaje dentro del círculo inscrito.

## Qué sigue siendo provisional

Es arte hecho por código: se lee bien a la distancia de juego y ya tiene capas y
vida, pero no sustituye a un modelado y una animación hechos a mano.

- **Piezas que se cruzan.** Los cuerpos siguen siendo volúmenes superpuestos, no una
  sola superficie. La oclusión horneada disimula las uniones, pero de cerca se ven, y
  las articulaciones se doblan con pesos lineales.
- **Cabeza de Balam.** Tiene ceño, antifaz y hocico de felino grande, pero la nariz
  es gruesa y el perfil recuerda algo a un oso; le falta el modelado fino de un jaguar.
- **Dibujos poligonales.** Rosetas, manchas y flores son polígonos recortados en la
  malla: limpios y sin parpadeo, pero angulosos de cerca.
- **Oclusión fija.** Está horneada en reposo: no cambia al moverse el personaje.
- **Animación procedimental.** Solo `Run` garantiza el apoyo exacto; en `Dodge`,
  `Death` y `Swim` las piernas van por cinemática directa y puede haber pequeños
  cruces con el suelo o la ropa. Las mangas atraviesan el jubón al levantar los brazos.
- **Expresión.** La boca del alux solo se abre y se estrecha (un hueso); los ojos no giran.
