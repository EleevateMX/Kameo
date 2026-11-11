# Arte 3D de ALUX

Personajes originales del juego, generados por código con Blender (módulo `bpy`),
sin texturas: solo materiales PBR de color plano. Todo es reproducible: los `.glb`
salen idénticos, byte a byte, cada vez que se ejecutan los scripts.

| Archivo | Qué es |
| --- | --- |
| `blender/build_alux.py` | Genera `game/assets/characters/alux.glb` (el alux y sus cuatro tocados). |
| `blender/build_balam.py` | Genera `game/assets/characters/balam.glb` (Balam, el jaguar). |
| `blender/kameo_common.py` | Utilidades: mallas, esqueleto, horneado de animaciones, exportación, renders. |
| `blender/render_previews.py` | Renders de vista previa (Cycles en CPU) en `previews/`. |
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
.tools/blender-venv/bin/python art/blender/render_previews.py alux     # opcional
.tools/blender-venv/bin/python art/blender/render_previews.py balam    # opcional

# comprobar en Godot
.tools/godot --headless --path game --import
.tools/godot --headless --path game --script "$PWD/art/godot/check_characters.gd"
xvfb-run -a .tools/godot --rendering-driver opengl3 --path game --resolution 480x480 \
    --script "$PWD/art/godot/render_check.gd" -- /tmp/capturas
```

Para cambiar una forma, un color o una animación se edita el script y se vuelve a
ejecutar. Las animaciones son funciones de tiempo o listas de poses clave al final
de cada `build_*.py`; los ángulos van en grados sobre los ejes del modelo.

## Contrato con el juego

- 1 unidad = 1 metro. Origen en los pies. En Godot el personaje mira a **+Z**.
- Cada `.glb` se importa como `Node3D > Armature > Skeleton3D > mallas`, con un
  `AnimationPlayer` en la raíz. Todas las mallas van con piel (skin) sobre el esqueleto.
- Las animaciones cíclicas cierran exactas, pero Godot las importa sin bucle: hay que
  poner `loop_mode = Animation.LOOP_LINEAR` por código en las marcadas como ciclo.
- Todas las animaciones llevan pista en los mismos huesos, así que cambiar de una a
  otra no deja restos de la pose anterior.
- Los materiales se localizan por nombre de superficie
  (`mesh.surface_get_material(i).resource_name`), no por índice.

### `alux.glb` — 7 548 triángulos, 434 KB, 25 huesos

Mide 1.30 m hasta la coronilla (1.47 m con sombrero, 1.60 m con penacho).

| Nodo (MeshInstance3D) | Uso | Materiales |
| --- | --- | --- |
| `Alux` | cuerpo, siempre visible | `Skin`, `Tunic`, `TunicTrim`, `Eye`, `Sash`, `EyePupil`, `White`, `Hair`, `Blush`, `Dark`, `Sandal`, `Pink`, `Red`, `Yellow`, `Leaf` |
| `Hat_Palma` | sombrero de palma | `Straw`, `StrawDark`, `HatBand`, `Jade` |
| `Hat_Penacho` | penacho de plumas | `Gold`, `Jade`, `FeatherGreen`, `FeatherRed`, `FeatherBlue`, `Yellow` |
| `Hat_Flor` | flor de mayo (se muestra junto con `Hair`) | `White`, `Yellow`, `Leaf` |
| `Hair` | cabello oscuro | `Hair` |

`Tunic` es el color del jugador (se exporta en `#2ec4a6`). `TunicTrim` es la base
crema del bordado (jubón, ruedo y puños); las flores usan `Pink`, `Red`, `Yellow` y
`Leaf`. `Eye` es jade emisivo (energía 1.2). `Hair` cabe debajo de los dos sombreros;
con el penacho queda mejor mostrarlo (sin él la cabeza se ve calva por detrás).

| Animación | Duración | Tipo | Notas |
| --- | --- | --- | --- |
| `Idle` | 2.0 s | ciclo | respira, mira a los lados, parpadea, mueve una oreja |
| `Run` | 0.6 s | ciclo | |
| `Jump` | 0.4 s | una vez | despegue y pose de subida; se queda en el último cuadro |
| `Fall` | 0.6 s | ciclo | |
| `Swim` | 1.2 s | ciclo | **ya incluye** el cuerpo inclinado ~60° hacia delante |
| `Cast` | 0.4 s | una vez | lanza con la mano derecha; el brazo queda extendido hacia 0.18 s |
| `Dodge` | 0.3 s | una vez | voltereta hacia delante, sin desplazamiento |
| `Interact` | 0.6 s | una vez | |
| `Hit` | 0.3 s | una vez | |
| `Death` | 0.9 s | una vez | cae de espaldas (hacia −Z, unos 0.4–1.0 m); se queda en el último cuadro |

### `balam.glb` — 7 740 triángulos, 468 KB, 29 huesos

Mide 1.66 m de la nariz a la grupa (2.17 m con la cola) y 0.80 m a la cruz.
Un solo nodo de malla, `Balam`, con los materiales `Fur`, `FurLight`, `Spots`, `Eye`,
`Collar`, `Gold`, `Mouth` y `Fang`. `Collar` es el color del jugador (`#2ec4a6`);
`Eye` es el mismo jade emisivo del alux.

| Animación | Duración | Tipo | Notas |
| --- | --- | --- | --- |
| `Idle` | 2.4 s | ciclo | |
| `Run` | 0.467 s | ciclo | galope |
| `Jump` | 0.4 s | una vez | se queda en el último cuadro |
| `Fall` | 0.6 s | ciclo | |
| `Swim` | 0.9 s | ciclo | |
| `Claw` | 0.333 s | una vez | zarpazo con la pata delantera derecha; impacto hacia 0.16 s |
| `Charge` | 0.5 s | ciclo | agazapado, tiembla y azota la cola |
| `ChargeRelease` | 0.467 s | una vez | parte de la pose de `Charge`; golpe con las dos patas hacia 0.2 s |
| `Pounce` | 0.5 s | una vez | salto estirado con las patas al frente; termina aterrizando |
| `Hit` | 0.3 s | una vez | |
| `Death` | 1.0 s | una vez | cae sobre su costado derecho; se queda en el último cuadro |

Ninguna animación desplaza la raíz: el juego mueve al personaje.

## Qué es provisional

Es arte hecho por código: sirve y se lee bien a la distancia de juego, pero no
sustituye a un modelado a mano. Lo más flojo, por si un artista lo retoma:

- **Mallas hechas de piezas que se cruzan.** El cuerpo no es una sola superficie:
  hombros, ancas, mangas y cabeza son volúmenes superpuestos. De cerca se ven las
  uniones, y en Balam algunas rosetas quedan cortadas donde el hombro o el anca
  entran en el tronco. Convendría una malla continua con buena topología.
- **Deformación sencilla.** Codos, rodillas y lomo se doblan con pesos lineales, sin
  corrección de volumen. La falda del huipil sigue a los muslos de forma aproximada y
  las mangas atraviesan el jubón cuando el alux levanta los brazos.
- **Animación sin cinemática inversa.** Los pies resbalan algo en `Run`, y en `Death`
  o `Dodge` alguna parte puede hundirse un par de centímetros en el suelo. La boca
  del alux no se anima (el hueso `Mouth` existe pero no se usa) y las manos son
  manoplas sin dedos.
- **Cara de Balam.** Se lee como jaguar, pero las orejas redondas y los ojos grandes
  le dan aire de cachorro. Falta carácter en cráneo, hocico y garras.
- **Bordado y rosetas como geometría.** Son polígonos planos pegados a la superficie
  (a 4 mm). Una textura o colores por vértice darían más detalle con menos triángulos.
- **Muchos materiales.** El cuerpo del alux tiene 15 superficies y Balam 8, es decir,
  otras tantas llamadas de dibujo por personaje. Si pesa en navegador, lo primero es
  fundir los colores decorativos en uno solo con colores por vértice.
