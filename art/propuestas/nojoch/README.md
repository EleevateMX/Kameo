# Nojoch Tuunich, el Guardián Dormido — propuesta de modelo

**Propuesta para aprobar.** Una copia de este `.glb` está en `game/assets/characters/nojoch.glb`
como modelo provisional, para poder programar y probar el combate en la rama de trabajo; no se
harán cinemáticas con él hasta que se apruebe. El
diseño que sigue es el de [docs/BOSS.md](../../../docs/BOSS.md). Como los demás
personajes, está hecho por código con Blender local (módulo `bpy`): mallas, color de
vértice con oclusión horneada, un esqueleto y las animaciones dentro del mismo `.glb`.
No hay texturas, ni nada dibujado o generado con herramientas de imagen o vídeo.

Diseño original: un coloso de sillares de caliza con las juntas a la vista, cabeza ancha
sin cuello, crestería escalonada, pectoral con cuatro glifos de jade y un espaldar que
guarda el corazón de cristal. Los glifos son signos abstractos inventados para esto
(una espiral cuadrada, una escalera, un marco con un rombo y dos cabrios sobre tres
cuentas): no son escritura maya ni copian ningún glifo real.

## Archivos

| Archivo | Qué es | Tamaño |
| --- | --- | --- |
| `nojoch.glb` | El modelo con sus 11 animaciones | 1 166 892 bytes (1.17 MB) |
| `nojoch_hoja.png` | 1920×1080: frente, tres cuartos, lado y espalda, de pie (`Idle`, cuadro 0). Fondo gris, sin textos | 801 KB |
| `nojoch_sentado.png` | 1440×1080: dormido (`Sleep`), tres cuartos | 840 KB |
| `nojoch_escala.png` | 1920×1080: de pie entre un alux y Balam, a escala real (sus modelos se construyen con `build_alux.py` y `build_balam.py`) | 713 KB |
| `nojoch_poses.png` | 1920×1080: cuadros clave de `Slam` (1.50 s), `Sweep` (1.00 s), `Kneel` (final) y `Remember` (final) | 964 KB |
| `nojoch_recuerda.png` | 1920×1080: `Remember` por delante y por detrás con las vetas apagadas y glifos, ojos y corazón encendidos | 843 KB |
| `nojoch_godot.png` | Hoja de ocho capturas hechas con el renderer de Godot (Compatibility), con la luz del juego. Las dos últimas ya cambian los materiales por nombre. **Es anterior al último ajuste de color** (ver «Qué está flojo») | 663 KB |

Scripts (fuera de esta carpeta): `art/blender/build_nojoch.py` (el modelo),
`art/blender/render_nojoch.py` (estas imágenes y las medidas),
`art/godot/check_nojoch.gd` (comprobación sin ventana) y `art/godot/render_nojoch.gd`
(capturas con Godot).

## Medidas

1 unidad = 1 metro, origen entre los pies, mira a **+Z** en Godot (a −Y en Blender).
Medidas tomadas sobre la malla ya deformada con `render_nojoch.py medidas`.

| | |
| --- | --- |
| De pie | **5.00 m** en reposo (4.97 m en el primer cuadro de `Idle`, que ya lo deja algo cargado de hombros); 4.46 m de mano a mano; 1.87 m de fondo |
| Sentado (`Sleep`) | **3.40 m** de alto, 4.37 m de ancho. Queda de 1.58 m por delante a 1.53 m por detrás del origen |
| Cabeza y crestería | 1.70 m (cara 0.88 m + crestería 0.82 m); 1.94 m de orejera a orejera; la crestería mide 2.06 m de ancho |
| Tronco | Cinturón a 1.7–1.9 m; hombros a 3.10 m; lo alto de los hombros a 3.76 m; 4.16 m de hombro a hombro |
| Brazos | 2.86 m del hombro a la punta de los dedos (llegan a 0.24 m del suelo). Mano de 0.84 m de ancho y 0.90 m de largo: tres dedos y pulgar |
| Piernas | Cadera a 1.40 m, rodilla a 0.82 m; pies de 0.68 × 1.08 m |
| Glifos | Fila centrada a 2.91 m (reposo); cada uno 0.38 × 0.49 m, a 0.48 m entre centros. `Glyph1` es el de la izquierda de quien lo mira de frente |
| Corazón | Cristal de 0.74 m. Centro a 3.56 m de pie (de 3.19 a 3.93 m); **3.19 m de rodillas** al final de `Kneel` (de 2.82 a 3.56 m) y 3.04 m al final de `Remember` |
| Frente a los demás | Alux 1.30 m (1.46 m con sombrero); Balam 0.81 m a la cruz. El coloso mide casi cuatro alux |

## Malla y esqueleto

- **8 765 triángulos** (tope: 14 000) y 15 226 vértices, en un solo nodo de malla,
  `Nojoch`, con piel sobre un solo esqueleto. Sin texturas: `COLOR_0` con el color y la
  oclusión horneada.
- **26 huesos**: `Root`, `Hips`, `Spine`, `Chest`, `Head`, `Jaw` (mandíbula), `Lids`
  (párpados de piedra: bajan con una traslación), `HeartBone` (el cristal; se anima su
  escala para el latido y sirve para colgarle partículas o una luz) y, a cada lado
  (`_L`, `_R`), `UpperArm`, `Forearm`, `Hand`, `Fingers`, `FingerTips`, `Thumb`,
  `Thigh`, `Shin`, `Foot`.
- Cada sillar va pegado a un solo hueso (no hay piel que se doble) y las articulaciones
  son tambores de piedra. Casi todas las caras son planas y llevan vértices propios: por
  eso hay tantos vértices para tan pocos triángulos.
- Árbol al cargar: `Node3D > Armature > Skeleton3D > Nojoch`, con `AnimationPlayer` en
  la raíz, igual que los otros personajes.

## Materiales

Se localizan por nombre de superficie, como en los demás `.glb`. Son de una sola cara.

| Material | Triángulos | Cómo se exporta | Para qué sirve |
| --- | --- | --- | --- |
| `Body` | 7 525 | Blanco; todo el color va en los vértices | Caliza, placas talladas, musgo y raíces |
| `Eye` | 32 | Jade `#2ec4a6`, emisión `#59ffe0` × 1.2 | Los ojos, al fondo de las cuencas. En `Sleep` los tapan los párpados |
| `Glyph1` … `Glyph4` | 70, 50, 50, 70 | Jade `#2ec4a6` **sin emisión** (apagados) | Los cuatro glifos del pecho, uno por material, para encenderlos de uno en uno |
| `Heart` | 96 | Jade `#2ec4a6`, emisión `#3fe8c4` × 1.0 | El corazón de cristal del espaldar |
| `Silence` | 872 | Magenta `#fa3399`, emisión × 1.8 (Godot lo lee como × 1.72) | Las vetas de corrupción de brazos, pecho, espalda y cabeza |

Cómo cambiarlos desde el juego (es lo que hace `art/godot/render_nojoch.gd` en sus dos
últimas capturas, con un material duplicado por superficie):

- **Encender un glifo:** `emission_enabled = true`, `emission = Color("#3fe8c4")`,
  `emission_energy_multiplier ≈ 1.8`.
- **Apagar las vetas:** `emission_enabled = false` y `albedo_color = Color("#4d423b")`;
  quedan como cicatrices oscuras en la piedra. Son relieve, no una máscara: no se pueden
  borrar, solo apagar.
- Si se sustituye un material por otro propio hay que conservar
  `vertex_color_use_as_albedo = true`.

### Propuesta de estados por fase

No hace falta tocar el modelo ni volver a renderizar: son solo valores de material (y
la animación). Solo están comprobados en imagen el estado de exportación (olvido) y el
de recuerdo; el resto es una propuesta de partida para afinar en el juego.

| Estado | `Silence` | `Glyph1`…`4` | `Heart` | `Eye` | Animación |
| --- | --- | --- | --- | --- | --- |
| **Dormido** (estatua) | Apagado: sin emisión, albedo `#4d423b` | Apagados | Emisión × 0.3; un latido a × 1.5 cuando entra el grupo | Da igual: párpados cerrados (mejor emisión 0) | `Sleep` |
| **Olvido** (fase 1) | Magenta × 1.8: **es como se exporta** | Apagados; cada purificación enciende uno (`#3fe8c4` × 1.8). Al despertar pueden parpadear en magenta | × 1.0 | Jade × 1.2 | `Awaken`, `Idle`, `Walk`, `Slam`, `Sweep`, `Summon` |
| **Furia** (fase 2) | Más viva y latiendo: × 2.5–3.2; baja un escalón cada vez que se suelta el corazón (3.0 → 2.3 → 1.6) | Los encendidos se quedan, algo más bajos (× 1.0) | × 1.0; × 3.0 latiendo mientras está expuesto (encadenado, `Kneel`) | Magenta `#fa3399` × 1.6: el cambio más visible de la fase | Además `Charge`, `Stunned`, `Kneel` |
| **Recuerdo** (fase 3) | Se apaga a medida que avanza el toque: de × 1.6 a 0 | Los cuatro encendidos × 1.8 | × 2.4 | Vuelve al jade × 1.6 | `Kneel` → `Remember` |
| **Liberado** | Apagado, albedo `#4d423b` | Encendidos, fijos (× 1.2–1.8) | × 2.4 con latido lento | Jade × 1.6 | Último cuadro de `Remember` |

## Animaciones

30 cuadros por segundo. Todas llevan pista en los mismos huesos (2 de posición, 23 de
giro y 1 de escala), así que cambiar de una a otra no deja restos. Ninguna desplaza la
raíz. Los ciclos cierran exactos, pero Godot los importa sin bucle (hay que activarlo).

| Animación | Duración | Tipo | Notas |
| --- | --- | --- | --- |
| `Sleep` | 4.0 s | ciclo | Sentado en el suelo, rodillas abiertas, brazos caídos por delante, cabeza gacha y párpados cerrados. Respiración mínima. El cuerpo queda unos 0.8 m por detrás del origen, para que al levantarse acabe de pie justo encima |
| `Awaken` | 4.0 s | una vez | Quieto hasta 0.7 s; tiembla entre 0.25 y 1.45 s; a 1.45 s ha alzado la cabeza y abierto los ojos; se empuja con los puños de 2.0 a 2.8 s; en pie a 3.3 s; se sacude el polvo entre 3.15 y 3.95 s. Termina en el primer cuadro de `Idle` |
| `Idle` | 4.0 s | ciclo | De pie; respira, mira despacio a los lados, el corazón late |
| `Walk` | 1.6 s | ciclo | Pasos pesados, compuesta para **1.0 m/s**. Planta el pie izquierdo a 0 s y el derecho a 0.8 s |
| `Slam` | 2.6 s | una vez | Alza el puño derecho hasta **1.2 s**, golpea a **1.45 s** y lo deja en el suelo hasta 1.85 s. El puño cae a unos 3.3 m por delante del origen (z de 2.9 a 3.8 m), algo a su derecha |
| `Sweep` | 2.2 s | una vez | Se carga hasta **0.9 s** y barre con el brazo derecho hasta **1.35 s**, de su derecha a su izquierda: unos 125° a 3 m de radio, con la mano entre 0.4 y 1.7 m de altura |
| `Summon` | 2.6 s | una vez | Los dos puños arriba a 1.0 s; golpean el suelo a **1.30 s** (a 2.5–3.4 m por delante) y se quedan hasta 1.9 s |
| `Charge` | 0.8 s | ciclo | Embestida inclinado unos 42°, puños atrás; compuesta para **2.2 m/s** |
| `Stunned` | 2.4 s | ciclo | Tambaleo en círculo, cabeza colgando, párpados a medio cerrar, mandíbula floja |
| `Kneel` | 2.0 s | una vez | Las rodillas tocan el suelo a **0.95 s**; se queda de rodillas con los puños en el suelo (se sostiene el último cuadro) |
| `Remember` | 3.0 s | una vez | Empieza donde acaba `Kneel`; levanta la cabeza, abre los ojos y tiende las manos abiertas hacia delante (2.5 s); se queda así |

## Paleta

Los hex están en el diccionario `HEX` de `build_nojoch.py`. La caliza parte de los
colores del santuario (`world_builder.gd`: `LIME #dbcca8`, `LIME_DARK #a19680`,
`LIME_WARM #e6c794`), llevada a un gris cálido algo más apagado.

| Nombre | Hex | Dónde |
| --- | --- | --- |
| Caliza | `#c4b89e` | Tono medio de los sillares |
| CalizaGris | `#aba089` | Sillares más grises |
| CalizaCrema | `#d9ccab` | Sillares claros, tachones |
| CalizaOscura | `#928873` | Sillares en sombra y tambores |
| CalizaCalida | `#d8c193` | Placas talladas: pectoral, ajorcas, banda, discos |
| Junta | `#584f45` | Fondo de las cuencas, la boca y el espaldar |
| Rotura | `#efe6cc` | Caliza recién partida en los desportillados |
| Verdin | `#7d8a63` | Pátina verdosa cerca del suelo |
| Musgo / MusgoOscuro / MusgoClaro | `#5c8c45` / `#3c6a32` / `#8fb155` | Musgo de hombros, pecho y crestería (`MOSS` del santuario) |
| Raiz / RaizOscura | `#6e5338` / `#47341f` | Raíces |
| Jade | `#2ec4a6` | Glifos, corazón y ojos (albedo) |
| JadeLuz | `#59ffe0` | Emisión de los ojos (la del alux) |
| JadeVivo | `#3fe8c4` | Emisión del corazón y de los glifos encendidos |
| Silencio | `#fa3399` | Vetas (`MAGENTA` del santuario) |
| SilencioApagado | `#4d423b` | Las vetas cuando recuerda |

## Cómo regenerar

Desde la raíz del repo, con el entorno de `art/README.md` (`bpy`, `numpy`, `Pillow`):

```bash
.tools/blender-venv/bin/python art/blender/build_nojoch.py     # el .glb: unos 6 s
.tools/blender-venv/bin/python art/blender/render_nojoch.py    # las cinco imágenes: unos 10 min (Cycles, 2 hilos, 24 muestras)
```

Lo demás es opcional:

```bash
# una sola imagen, o una prueba rápida al 40 % con 8 muestras en otra carpeta
.tools/blender-venv/bin/python art/blender/render_nojoch.py poses
.tools/blender-venv/bin/python art/blender/render_nojoch.py todo /tmp/prueba 8 0.4
# medidas y contactos con el suelo; un cuadro suelto de cualquier animación
.tools/blender-venv/bin/python art/blender/render_nojoch.py medidas
.tools/blender-venv/bin/python art/blender/render_nojoch.py toma Slam 1.2 180 10 /tmp/slam.png 640
# comprobar el .glb con Godot, sin ventana y sin proyecto
.tools/godot --headless --script "$PWD/art/godot/check_nojoch.gd"
# capturas con el renderer de Godot (necesita un proyecto vacío) y su hoja
mkdir -p /tmp/nojoch_godot && touch /tmp/nojoch_godot/project.godot
xvfb-run -a .tools/godot --path /tmp/nojoch_godot --rendering-driver opengl3 --resolution 640x640 \
    --script "$PWD/art/godot/render_nojoch.gd" -- /tmp/nojoch_godot/capturas "$PWD/art/propuestas/nojoch/nojoch.glb"
.tools/blender-venv/bin/python art/blender/render_nojoch.py godot /tmp/nojoch_godot/capturas
```

## Comprobaciones hechas

- **Godot 4.5.1 sin ventana** (`check_nojoch.gd`): carga el `.glb`, encuentra los 8
  materiales, los 26 huesos y las 11 animaciones con su duración, 8 765 triángulos.
  Resultado: correcto.
- **Renderer de Godot** (`nojoch_godot.png`): se ve entero, sin agujeros por caras al
  revés, con el color de vértice y lo emisivo en su sitio; el cambio de materiales por
  nombre funciona.
- **Caras traseras** en Blender (`toma … caras`): se corrigieron las tres que salieron
  (placa del antebrazo derecho, fondo del espaldar y placa de la crestería vista por
  detrás). Quedan astillas mínimas donde una veta dobla una arista.
- **Suelo**: `medidas` recorre todas las animaciones. Lo peor es 7.6 cm de espinilla
  bajo el suelo en la sentadilla de `Summon` y 2–3 cm en `Slam`, `Sweep` y `Awaken`.
- No se usa `add_loft_painted`, así que el defecto de las franjas sin área no aplica.

## Estado de las imágenes

Las cinco imágenes de Blender (`hoja`, `sentado`, `escala`, `poses`, `recuerda`) salen
del `.glb` que se entrega y las he revisado una a una: el coloso se ve entero, bien
encuadrado, sin caras negras ni piezas sueltas, con los glifos y el corazón a la vista.
Solo `nojoch_godot.png` quedó sin rehacer tras el último ajuste de color.

## Qué está flojo

**Del modelo**

- **Pesa 1.17 MB**, casi el doble que el alux o Balam, con menos triángulos: las caras
  planas triplican los vértices, y 28 s de animación a 30 cuadros ocupan lo suyo. Se
  puede bajar compartiendo vértices en las caras que no se ven o exportando a 15 cuadros.
- **Recuerda al gólem de bloques de siempre.** Lo propio de este es la crestería, el
  pectoral de glifos y el espaldar del corazón; de lejos sigue siendo «un robot de
  piedra». Le vendría bien más talla (grecas, relieves) y menos caja lisa, sobre todo
  en la espalda y las piernas.
- **La cara es más adusta que serena.** Los ojos de rabillo caído y los párpados ayudan,
  pero la boca es solo una ranura y la ceja es una losa recta. No tiene más expresión
  que párpados y mandíbula.
- **La crestería** se lee de frente como un sombrero de losas apiladas más que como el
  peine calado de un templo; los huecos entre pilares apenas se ven.
- **El corazón no está literalmente entre los omóplatos**: va en un espaldar que sube
  por detrás de la cabeza, a la altura de los hombros. Lo puse ahí para que quedara a
  unos 3 m estando de rodillas (3.19 m el centro, 2.82 m la punta de abajo), como pide
  el diseño. Si se prefiere más bajo, baja también de rodillas.
- **El bloque del hombro gira con el brazo.** Al alzar los brazos (`Slam`, `Summon`) su
  musgo y sus raíces quedan boca abajo, y al abrirlos se mete en el costado del pecho.
- **Los sillares se cruzan en las articulaciones** cuando se doblan mucho: rodillas y
  caderas en `Sleep` y `Kneel`, codos, y los dedos al cerrar el puño.
- **Las vetas son crestas gruesas** de brillo uniforme, de una sola cara, y flotan un
  par de centímetros al cruzar las juntas. No pueden «crecer» ni retirarse poco a poco.
- **Los glifos apagados siguen siendo jade bastante vivo**; quizá deban oscurecerse más
  cuando no están encendidos (basta bajar el albedo desde el juego).
- **El musgo colgante** son púas pequeñas; las raíces, tubos de cinco lados. De cerca
  se nota. La oclusión está horneada en reposo y no cambia con la pose.
- **Al sol, en Godot, la caliza se quema** casi a blanco con la luz del juego (pasa
  igual con cualquier color claro). Habría que verlo en el patio real antes de decidir
  si se oscurece más.

**De las animaciones**

- **No las he visto en movimiento**: solo cuadros sueltos y medidas. Los tiempos y los
  arcos son un primer intento y pueden resultar rígidos; hay pequeños saltos donde la
  mano pasa de apoyada a libre (`Awaken` a 2.0 y 2.8 s, `Slam` y `Summon` al soltar).
- **`Charge` va despacio** (2.2 m/s): con piernas tan cortas no da para más sin patinar.
  Si la embestida es más rápida, habrá que acelerar la animación o aceptar que patine.
  `Walk` está compuesta para 1.0 m/s.
- **`Sleep`**: las manos cuelgan en el aire por delante de las rodillas, no descansan
  sobre nada, y sentado queda 0.8 m por detrás del origen.
- **`Kneel`**: los pies acaban tendidos con la planta hacia arriba; visto por detrás es
  tosco. En las sentadillas de los golpes la espinilla se hunde unos centímetros.
- **`Sweep`** barre unos 125°, no los 140° del diseño, y la mano pasa entre 0.4 y 1.7 m:
  un alux agachado junto al pie podría quedar por debajo.

**De las imágenes y la comprobación**

- **`nojoch_godot.png` es anterior al último ajuste de color**: muestra la caliza un
  poco más clara que la del `.glb` entregado. La geometría, los huesos y las animaciones
  son los mismos. No se rehízo para no ocupar la máquina.
- **`nojoch_sentado.png` enseña al dormido con las vetas encendidas** (el estado de
  exportación). Según el diseño, dormido parece una estatua: debería verse con las
  vetas apagadas. No hay imagen de ese estado, ni del de furia.
- **La hoja** lleva las cuatro vistas en una fila, así que el coloso sale pequeño (unos
  560 píxeles de alto); el detalle se ve mejor en las otras imágenes.
- No se comprobó que dos construcciones seguidas den el `.glb` idéntico byte a byte
  (los otros personajes sí lo cumplen y el script usa los mismos generadores con
  semilla fija; el tamaño sí coincide).
- No está probado dentro del juego: ni el coste en equipos modestos, ni cómo se ve en
  el patio, ni la cámara de combate.
