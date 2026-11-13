# Arte 3D de ALUX

Personajes originales del juego, generados por código con Blender (módulo `bpy`),
sin texturas: el color va en los vértices, con oclusión ambiental horneada. Todo es
reproducible: los `.glb` salen idénticos, byte a byte, cada vez que se ejecutan los scripts.

| Archivo | Qué es |
| --- | --- |
| `blender/build_alux.py` | Genera `game/assets/characters/alux.glb`: el alux y las piezas del personalizador (tocados, vestimenta, accesorios y amuletos), cada una en su malla. |
| `blender/build_balam.py` | Genera `game/assets/characters/balam.glb` (Balam, el jaguar). |
| `blender/build_yaxche.py` | Genera `game/assets/characters/yaxche.glb` (Chiich Yaxché, la abuela del claro, con su bastón). Reutiliza las medidas de la cabeza de `build_alux.py`. |
| `blender/alux_common.py` | Utilidades: mallas, dibujos recortados en la superficie, oclusión, esqueleto, cinemática inversa, horneado de animaciones, exportación, renders. |
| `blender/render_previews.py` | Renders de vista previa en `previews/` y retratos (HUD y diálogos) en `game/assets/ui/`. |
| `blender/render_referencias.py` | Hojas de personaje (turnaround) en `referencias/`, para las cinemáticas. |
| `blender/build_nojoch.py` | Genera `propuestas/nojoch/nojoch.glb` (Nojoch Tuunich, el jefe). Su ficha, con medidas, materiales, estados y animaciones, es `propuestas/nojoch/README.md`. |
| `blender/render_nojoch.py` | Imágenes del jefe en `propuestas/nojoch/` y sus hojas de `referencias/`; también sus medidas. |
| `blender/videos_nojoch.py` | Vídeos de las animaciones del jefe, dibujados con Godot (`propuestas/nojoch/animaciones/`). |
| `godot/check_nojoch.gd`, `godot/render_nojoch.gd` | Comprobación sin ventana del `.glb` del jefe y capturas o cuadros de animación con el renderer de Godot y la luz del juego. |
| `blender/hojas_alux_opciones.py` | Hojas de opciones del personalizador en `propuestas/alux_personalizacion/`, dibujadas con Godot (no usa Blender). La ficha de las piezas es `propuestas/alux_personalizacion/README.md`. |
| `godot/render_alux_opciones.gd` | El alux con cualquier combinación de piezas y colores, con el renderer de Godot y la luz del juego: enciende las mallas y tiñe los materiales como `avatar.gd`. |
| `godot/check_characters.gd` | Comprobación sin ventana de lo que Godot importa. Para el alux comprueba además el contrato del personalizador (nodos, materiales, esqueleto y animaciones) y sale con código 1 si algo falla. |
| `godot/render_check.gd` | Capturas con el renderer real de Godot (bajo `xvfb`). |
| `previews/` | Renders de referencia. `*_hoja.png` es la hoja de contacto; `godot_validacion.png` y `yaxche_godot_hoja.png` son capturas hechas con Godot. |
| `referencias/` | Hojas de personaje sobre fondo neutro (frente, tres cuartos, lado, espalda) y su ficha (`referencias/README.md`): proporciones, paleta, rasgos fijos y descripción para prompt. |

## Cómo regenerar

Blender no hace falta: basta el módulo `bpy` (rueda de PyPI, Python 3.13).

```bash
python3 -m venv .tools/blender-venv
.tools/blender-venv/bin/pip install bpy numpy Pillow      # bpy 5.3.0

.tools/blender-venv/bin/python art/blender/build_alux.py
.tools/blender-venv/bin/python art/blender/build_balam.py
.tools/blender-venv/bin/python art/blender/build_yaxche.py
.tools/blender-venv/bin/python art/blender/render_previews.py alux        # opcional
.tools/blender-venv/bin/python art/blender/render_previews.py balam       # opcional
.tools/blender-venv/bin/python art/blender/render_previews.py yaxche      # opcional
.tools/blender-venv/bin/python art/blender/render_previews.py portraits   # los tres retratos
.tools/blender-venv/bin/python art/blender/render_previews.py portraits yaxche   # solo el suyo
.tools/blender-venv/bin/python art/blender/render_referencias.py          # hojas de personaje (todas)
.tools/blender-venv/bin/python art/blender/render_referencias.py balam    # solo las de un personaje
.tools/blender-venv/bin/python art/blender/hojas_alux_opciones.py        # hojas del personalizador (con Godot)

# comprobar en Godot
.tools/godot --headless --path game --import
.tools/godot --headless --path game --script "$PWD/art/godot/check_characters.gd"   # alux: «CONTRATO ALUX: OK»
xvfb-run -a .tools/godot --rendering-driver opengl3 --path game --resolution 480x480 \
    --script "$PWD/art/godot/render_check.gd" -- /tmp/capturas          # todas las tomas
xvfb-run -a .tools/godot --rendering-driver opengl3 --path game --resolution 480x480 \
    --script "$PWD/art/godot/render_check.gd" -- /tmp/capturas yaxche   # solo las de un personaje
```

Los renders usan Cycles en CPU con 2 hilos. Para cambiar una forma, un color o una
animación se edita el script y se vuelve a ejecutar. Las animaciones están al final de
cada `build_*.py`: son funciones de tiempo o listas de poses clave, con los ángulos en
grados sobre los ejes del modelo; los pies y las garras se plantan con cinemática
inversa (canales `IK_*`).

Los bordados y las manchas se recortan en la propia malla (`add_loft_painted`). Una
franja puede dar la vuelta entera a la prenda a cualquier altura (`band()` en
`build_alux.py`): sus bordes reciben un vértice por columna de la malla, así que el
hilo existe como superficie de color. Si al generar aparece el aviso «… sin malla»,
algún dibujo ha dejado un hueco por el que se vería el interior.

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
- **Materiales que el juego tiñe.** El renderer Compatibility multiplica el albedo del
  material por el color de vértice tal como están guardados (en sRGB). Un material
  teñible lleva el color en el albedo y, en los vértices, solo el matiz (sombra,
  cenefas, rubor) como factor; el juego cambia `albedo_color` y nada más. En Blender,
  `make_material(..., tint=True)` y `MeshBuilder.vdiv` se encargan de dividir.
- Las animaciones cíclicas cierran exactas, pero Godot las importa sin bucle.
- Todas las animaciones llevan pista en los mismos huesos, así que cambiar de una a
  otra no deja restos de la pose anterior. Ninguna desplaza la raíz.

### `alux.glb` — 12 721 triángulos, 823 KB, 33 huesos

Mide 1.30 m hasta la coronilla (1.47 m con sombrero, 1.61 m con penacho). Lleva el cuerpo,
el cabello y las piezas del personalizador, cada una en su malla; el juego enciende
una por familia buscándola por nombre (`find_children(prefijo + "*")` da esa malla y
ninguna otra). **Todas llegan visibles**: quien instancie el modelo apaga las que no
toquen. La ficha completa (huesos de cada pieza, combinaciones, problemas conocidos y
hojas de opciones) está en `propuestas/alux_personalizacion/README.md`.

| Nodo (MeshInstance3D) | Uso | Triángulos | Materiales |
| --- | --- | --- | --- |
| `Alux` | cuerpo, siempre visible | 6 560 | `Skin`, `Body`, `Tunic`, `Trim`, `Eye`, `Jade` |
| `Hair` | cabello oscuro; visible con todos los tocados | 306 | `Headwear` |
| `Hat_Palma` | tocado 0: sombrero de palma con pluma | 656 | `Headwear`, `Jade` |
| `Hat_Penacho` | tocado 1: penacho de plumas | 976 | `Headwear`, `Jade` |
| `Hat_Flor` | tocado 2: flor de mayo | 504 | `Headwear` |
| `Hat_Plumas` | tocado 4: diadema baja de plumas cortas | 352 | `Headwear` |
| `Hat_Panuelo` | tocado 5: pañuelo anudado | 204 | `Trim` |
| `Hat_Hojas` | tocado 6: corona de hojas y florecillas | 308 | `Headwear` |
| `Outfit_Capa` | vestimenta 1: capa corta con broche | 340 | `Trim`, `Body` |
| `Outfit_Faja` | vestimenta 2: faja ancha con flecos y delantal | 268 | `Trim`, `Body` |
| `Outfit_Bordado` | vestimenta 3: pechera y bajo de rombos | 352 | `Trim`, `Body` |
| `Acc_Morral` | accesorio 1: sabucán cruzado | 364 | `Trim`, `Body` |
| `Acc_Sonaja` | accesorio 2: sonaja de jícara al cinto | 177 | `Body` |
| `Acc_Caracol` | accesorio 3: caracol marino a la espalda | 292 | `Body` |
| `Acc_Farol` | accesorio 4: farolito de luciérnagas al cinto | 198 | `Body`, `Firefly` |
| `Amu_Jade` | amuleto 1: colgante de jade | 248 | `Body`, `Jade` |
| `Amu_Concha` | amuleto 2: concha en cordón | 152 | `Body` |
| `Amu_Obsidiana` | amuleto 3: espejo de obsidiana | 204 | `Body`, `Obsidian` |
| `Amu_Semillas` | amuleto 4: collar de semillas rojas | 260 | `Body` |

El tocado 3 es «sin tocado» y el índice 0 de vestimenta, accesorios y amuletos es
«ninguno». El sabucán y el amuleto de jade, que antes iban fijos en el cuerpo, son
ahora `Acc_Morral` y `Amu_Jade`: el alux de siempre es accesorio 1 y amuleto 1 (y así
sale en los renders de `previews/`, `referencias/` y los retratos).

- `Tunic`: color principal del jugador (se exporta en `#2ec4a6`); sus vértices solo
  llevan sombra y costuras, en gris.
- `Trim`: color secundario (se exporta en `#f8efdc`, el crema de siempre): jubón, ruedo
  y puños del huipil, telas de `Outfit_*`, `Hat_Panuelo` y la correa del morral. Vértices
  en blanco y grises. Los bordados de encima siguen en `Body`.
- `Skin`: la piel. Como el rubor y las palmas son más claros que la piel media y un
  vértice no pasa de 1, la piel media va en gris 0.75 y el albedo es el tono de piel
  × 4/3: se exporta en `#e19764`, que da el `#a9714b` de siempre. Para otro tono,
  `albedo_color = tono × 4/3` (y × 1.12 si se aclara como `Body`).
- `Body`: blanco, todo el color está en los vértices (bordados, faja, huaraches, y en
  las piezas: cuero, madera, jícara, conchas, semillas…).
- `Eye`: iris de jade emisivo (energía 1.2). `Jade`: amuleto, pulsera y arete, emisivo suave.
- `Headwear`: blanco con color de vértice, para tocados y cabello.
- `Firefly`: la luz del farol, emisivo suave (0.7). `Obsidian`: el espejo, el único
  material pulido (rugosidad 0.12), con el color y el destello en los vértices.
- El esqueleto no tiene huesos nuevos: lo que cuelga del cinto va pesado a `Bag`, lo
  que cuelga del cuello a `Amulet`, y las puntas de la faja ancha a `SashTail`, que ya
  se balanceaban en todas las animaciones.

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

### `balam.glb` — 9 036 triángulos, 661 KB, 30 huesos

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

### `yaxche.glb` — 8 935 triángulos, 561 KB, 39 huesos

Chiich Yaxché, «la abuela del claro»: la más vieja de los aluxes, guardiana de la gran
ceiba. Es un personaje no jugador: el juego **no** debe recolorearla (por eso no tiene
`Tunic` ni `Collar`). Está modelada a la escala del alux, con la misma cabeza, pero
encorvada, panzona y de piernas cortas: mide 1.27 m hasta la coronilla y su bastón
llega a 1.60 m (el juego la agranda ×1.15).

| Nodo (MeshInstance3D) | Uso | Triángulos | Materiales |
| --- | --- | --- | --- |
| `Yaxche` | cuerpo: cabeza, cabello y moño, flor, vestido, rebozo, collar | 7 981 | `Body`, `Eye`, `Jade` |
| `Staff` | bastón de ceiba con su retoño | 954 | `Body`, `Jade` |

- `Body`: blanco, todo el color está en los vértices. Los blancos del vestido y del
  cabello van un poco bajos (`#f0eadf`, `#dedad3`) para que no se quemen si el juego
  aclara el material como hace con los aluxes.
- `Eye`: el mismo iris de jade emisivo que el alux (energía 1.2).
- `Jade`: en `Yaxche`, las cuentas del collar; en `Staff`, **solo** el botón del
  retoño y las tres luciérnagas. Para que el botón brille más (en `Bless`), basta
  poner un material propio en esa superficie del nodo `Staff`
  (`set_surface_override_material`), sin tocar el recurso compartido con el collar.
- Esqueleto: los 33 huesos del alux con sus mismos nombres (`SashTail` y `Bag` quedan
  sin malla), más `Index_L` (el dedo que regaña), `ShawlEnd_L`/`ShawlEnd_R` (puntas
  del rebozo), `StaffBone` (el bastón, hijo de `Hand_R`), `Sprout` (retoño y botón,
  hijo de `StaffBone`) y `Fireflies` (luciérnagas, hijo de `StaffBone`, con la cabeza
  en el centro del botón: sirve para colgarle un `BoneAttachment3D` con partículas).
  El hueso no se llama `Staff` porque Godot lo renombraría al chocar con el nodo.
- La pose de reposo ya es la suya: apoyada en el bastón, que sujeta con la mano
  derecha. El bastón sigue a la mano en todas las animaciones y, mientras no se
  levanta a propósito, la contera no se mueve del suelo aunque el cuerpo se meza.

| Animación | Duración | Tipo | Notas |
| --- | --- | --- | --- |
| `Idle` | 3.0 s | ciclo | respira, se mece sobre el bastón, parpadea (0.6 y 1.7 s), sacude la oreja derecha (2.05–2.4 s); las luciérnagas rondan el botón |
| `Talk` | 2.4 s | ciclo | gesticula con la mano izquierda, asiente, abre y cierra la boca; un golpecito de bastón a **1.33 s** |
| `Scold` | 1.2 s | una vez | frunce el ceño y menea el índice (0.16–1.0 s); golpes de bastón a **0.34 s** y **0.80 s** |
| `Bless` | 1.6 s | una vez | alza el bastón, lo sostiene con los ojos entornados entre **0.55 y 1.05 s** (ahí va el brillo del botón, que pone el juego) y lo vuelve a apoyar a 1.42 s |
| `Run`, `Fall` | 3.0 s | ciclo | copias exactas de `Idle`, por si el código del avatar las pide |

`Scold` y `Bless` empiezan y acaban en la pose neutra, muy cerca del arranque de `Idle`.

### Retratos del HUD y de los diálogos

`game/assets/ui/portrait_alux.png`, `portrait_balam.png` y `portrait_yaxche.png`:
256×256, fondo transparente, unos 11–12 KB cada uno (PNG de paleta con
transparencia; Godot los importa como RGBA), con el personaje dentro del círculo
inscrito. El de la abuela está encuadrado un 10 % más abierto que el del alux para
que quepa el botón de jade del bastón.

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
- **Piezas del personalizador.** Son rígidas (sin tela ni física). Con los brazos en
  alto la capa se arruga sobre los hombros y asoman las mangas; lo que cuelga del cinto
  va en la cadera derecha, hacia atrás, y de frente casi no se ve; con la cabeza
  agachada el mentón tapa el amuleto. El detalle, en
  `propuestas/alux_personalizacion/README.md`.
- **Abuela Yaxché.** El rebozo es una esclavina rígida con dos puntas: al levantar un
  brazo (`Scold`, `Bless`) sube con él y se arruga, y el antebrazo derecho roza la
  punta de ese lado. La mano izquierda solo separa el índice; el puño derecho no se
  abre. Al alzarlo en `Bless`, el bastón se desliza unos centímetros dentro del puño.
  El cabello es un casquete liso con mechas pintadas, sin volumen de pelo.
