# Referencias visuales de los personajes

Hojas de personaje (turnaround) del alux, de Balam, de Chiich Yaxché y de Nojoch Tuunich,
para mantener la continuidad al generar cinemáticas con Kling u otra herramienta de vídeo. Salen de
los mismos modelos del juego (`art/blender/build_*.py`), renderizados con Blender
(`bpy`, Cycles en CPU); aquí no hay nada dibujado ni generado por IA.

| Archivo | Qué es |
| --- | --- |
| `<personaje>_frente.png` | De frente. 1024×1024. |
| `<personaje>_tres_cuartos.png` | Tres cuartos delantero (cámara girada 40° hacia la izquierda del personaje). |
| `<personaje>_lado.png` | Perfil: se ve el costado **izquierdo** del personaje, que mira hacia la izquierda de la imagen. |
| `<personaje>_espalda.png` | Por detrás. |
| `<personaje>_hoja.png` | Las cuatro vistas en fila (frente, tres cuartos, lado, espalda), 1920×1080, a la misma escala y con el suelo a la misma altura. |
| `balam_accion.png` | Balam en el vuelo del galope (`Run`, cuadro 4 de 12), cámara girada 60°. |
| `nojoch_liberado_hoja.png` | La hoja de Nojoch Tuunich en estado «liberado» (ver su ficha). |

`<personaje>` es `alux`, `balam`, `yaxche` o `nojoch`. Ninguna imagen lleva textos, rótulos ni
marcas: los generadores de vídeo copian lo que ven escrito.

## Cómo regenerarlas

Desde la raíz del repo (el entorno es el de `art/README.md`; hace falta Pillow):

```bash
.tools/blender-venv/bin/python art/blender/render_referencias.py
```

Hace 13 renders y 3 hojas (32 muestras, 2 hilos): del orden de un cuarto de hora. Con argumentos:
`render_referencias.py [alux|balam|yaxche|todos] [carpeta] [resolución] [muestras]`;
por ejemplo, `... render_referencias.py yaxche` rehace solo las de la abuela y
`... render_referencias.py todos /tmp/prueba 384 16` hace una prueba rápida en otra carpeta.

Las de Nojoch Tuunich salen de su propio script, porque llevan estados de material y
expresión: `.tools/blender-venv/bin/python art/blender/render_nojoch.py referencias`
(8 renders y 2 hojas, 24 muestras: unos 6 minutos).

## Cómo están hechas

- **Pose:** el primer cuadro de `Idle` (reposo). El alux lleva el tocado con el que
  empieza el juego: sombrero de palma sobre el cabello.
- **Cámara:** lente de 60 mm, horizontal y a la altura del pecho (alux 0.75 m, Balam
  0.62 m, Yaxché 0.68 m), girando alrededor del personaje a distancia fija (3.02 m,
  4.48 m y 3.33 m). El encuadre es idéntico en todas las vistas de un mismo personaje.
- **Luz:** como la de los retratos del HUD (cielo blanco y un sol suave), neutra para no
  teñir los colores. Las luces giran con la cámara: todas las vistas se iluminan igual.
- **Fondo:** gris `#d2d2d2` uniforme, sin suelo; solo una sombra de contacto suave.
- **Color:** color de vértice plano con la oclusión horneada del modelo, sin texturas.
  Los ojos y el jade son emisivos, por eso se ven más luminosos que su código hex.
- **Un retoque, solo en estas imágenes** (ni el script de construcción ni el `.glb`
  cambian; está explicado en `render_referencias.py`): el cabello del alux ya no
  atraviesa la cinta del sombrero de palma. En el juego sí la atraviesa.
- Los hilos finos que rodean las prendas ya no se retocan: existen como color en los
  modelos desde la corrección de `add_loft_painted`, y estas hojas coinciden con ellos
  píxel a píxel.

## Tamaño relativo

Medidas de los modelos (1 unidad = 1 m), en el primer cuadro de `Idle`.

| Personaje | Altura | En cabezas | Ancho | Largo |
| --- | --- | --- | --- | --- |
| Alux | 1.30 m a la coronilla; 1.46 m con el sombrero | 2.7 (la cabeza mide 0.48 m) | 1.04 m de punta a punta de las orejas; 0.57 m la cabeza | — |
| Balam | 0.81 m a la cruz; 1.07 m a la punta de las orejas | 2.5 a la cruz (cabeza de 0.32 m de alto) | 0.57 m | 1.70 m de la nariz a la grupa (unas 4 cabezas de 0.43 m de largo); 2.24 m con la cola |
| Chiich Yaxché | 1.27 m a la coronilla; 1.63 m el bastón con su botón | 2.6 (la misma cabeza del alux) | 1.05 m de oreja a oreja | — |

- El juego agranda a la abuela ×1.15 (lo dice `art/README.md`): en escena mide 1.46 m
  y su bastón 1.87 m: ella queda a la altura del alux con sombrero, y el bastón
  los sobrepasa a los dos.
- La cruz de Balam llega al hombro del alux (0.80 m) y la punta de sus orejas a los
  ojos del alux. De la nariz a la grupa es 1.3 veces más largo que alto es el alux.
- Balam es la forma de jaguar del alux (se transforma en él): un mismo jugador es
  alux o Balam, nunca los dos a la vez. Comparten los ojos de jade, el amuleto y el
  color del jugador (huipil del alux, collar de Balam).

Izquierda y derecha son siempre **las del personaje**.

---

## Alux

Espíritu guardián maya: pequeño, cabezón, de ojos enormes. Modelo: `build_alux.py`.

**Proporciones.** 2.7 cabezas de alto. Cabeza redonda y grande, más ancha que los
hombros; cuello casi inexistente; tronco corto y recto; brazos y piernas cortos y
rollizos; manos de pulgar y tres dedos; pies de cuatro dedos.

**Ropa y accesorios.**

- Sombrero de palma de ala ancha y copa cónica redondeada, a franjas, con cinta roja,
  una cuenta de jade al frente de la cinta y una pluma roja de punta amarilla metida
  en la cinta por el lado izquierdo. Va algo caído hacia atrás.
- Cabello corto, casi negro, con flequillo en picos bajo el ala.
- Huipil recto hasta medio muslo, de manga corta con puño crema ribeteado de rojo.
  Es del color del jugador; el de referencia es el verde jade `#2ec4a6`.
- Jubón: cuello cuadrado color crema sobre los hombros, bordado con flores rosas,
  rojas y amarillas, estrellitas amarillas y hojas verdes, con un hilo rojo en el borde.
- Cenefa crema en el ruedo con 18 flores (rosa, amarilla, roja, alternadas) y hojas
  verdes entre dos hilos rojos; debajo asoma un fustán de encaje blanco con ondas.
- Faja tejida roja con una franja amarilla y rombos (granate y verde jade apagado),
  anudada en el costado izquierdo, hacia atrás, con dos puntas de flecos amarillos.
- Amuleto: disco de jade con aro dorado sobre el pecho, colgado de un cordón marrón,
  con dos cuentas rojas.
- Sabucán (morral de henequén) cruzado: la correa baja del hombro izquierdo a la
  cadera derecha, y el morral cuelga por detrás de esa cadera, con una franja roja,
  otra verde, un botón dorado y flecos.
- Pulsera de cuentas de jade y oro en la muñeca izquierda; de hilo rojo y oro en la
  derecha. Arete de aro dorado con una cuenta de jade en la oreja izquierda.
- Huaraches de cuero marrón con suela oscura.

**Paleta** (de `PAL` y `make_materials` en `build_alux.py`).

| Parte | Hex |
| --- | --- |
| Piel / sombra / luz | `#a9714b` / `#8c563a` / `#bd8a62` |
| Rubor (cachetes, nariz, interior de las orejas) | `#c96a55` |
| Iris de jade (emisivo) | `#59ffe0` |
| Aro del iris / pupila / brillos | `#0c5a4f` / `#052a26` / `#fffaf0` |
| Cejas, pestañas y cabello / reflejo del cabello | `#211712` / `#3d2a20` |
| Boca | `#3a1c16` |
| Huipil (color del jugador) | `#2ec4a6` |
| Jubón y cenefa (crema) / encaje | `#f8efdc` / `#ffffff` |
| Hilo rojo | `#c23b2e` |
| Flores: rosa / roja / amarilla; hojas | `#ff5fa2` / `#e23a30` / `#ffc233`; `#3fa34d` |
| Faja / rombos | `#c93545` / `#8a2032` y `#2a9c78` |
| Jade (amuleto, pulsera, arete, cuenta del sombrero; emisivo suave) | `#3ddba8` |
| Oro | `#e8b53a` |
| Cordón del amuleto | `#5b3a22` |
| Henequén (sabucán) / sombra | `#d9c28c` / `#b0915a` |
| Huaraches / suela | `#7d4c27` / `#4a2c17` |
| Sombrero: palma clara / palma oscura / cinta | `#dcb968` / `#b98d43` / `#b3372e` |
| Pluma: roja con la punta amarilla | `#d83a2e` → `#ffc233` |

**Rasgos que no deben cambiar.**

- Ojos: dos discos enormes de jade turquesa que brillan, con aro oscuro, pupila
  grande y dos brillos blancos (uno grande arriba, uno pequeño abajo). Sin blanco del ojo.
- Orejas largas y puntiagudas que salen horizontales a los lados, con la punta algo caída.
- Cejas cortas y gruesas, nariz de botón, sonrisa pequeña y cachetes con rubor.
- Sombrero de palma a franjas con cinta roja, cuenta de jade y pluma roja a la izquierda.
- Huipil verde jade, jubón crema bordado, faja roja y amarilla con el nudo a la
  izquierda, amuleto de jade en el pecho, sabucán en la cadera derecha.
- Piel morena cálida, sin vello ni marcas; pies descalzos dentro de los huaraches.
- No es un duende ni un goblin: nada de piel verde, colmillos ni garras.

**Descripción para prompt.**

> Stylized low-poly 3D fantasy character, flat vertex colours, no textures: a small Maya forest spirit with an oversized round head, warm brown skin, huge glowing jade-turquoise eyes, long horizontal pointed ears, striped palm-straw hat with red band and red feather, teal huipil tunic with cream flower-embroidered yoke and hem, red-and-yellow woven sash, jade amulet, leather sandals.

Otros tocados del modelo, que no salen en estas hojas: penacho de plumas (`Hat_Penacho`:
cinta dorada y roja, plumas `#16a877`, `#35d6c0`, `#d83a2e`, `#ffc233`, `#2a8fdc`),
flor de mayo en la sien izquierda (`Hat_Flor`: `#fff7ec` con corazón `#ffc233`) y el
cabello solo (`Hair`).

---

## Balam, el jaguar

La forma de jaguar del alux: heroico y estilizado, no realista. Modelo: `build_balam.py`.

**Proporciones.** 1.70 m de la nariz a la grupa y 0.81 m a la cruz; con la cola,
2.24 m. Pecho profundo y ancho, hombros y ancas muy marcados, lomo recto, patas
gruesas y cortas con garras grandes. Cabeza ancha (0.46 m) de ceño fruncido, con
hocico corto y cuadrado, nariz grande y orejas pequeñas y angulosas.

**Pelaje, collar y adornos.**

- Pelaje naranja dorado, más tostado en el lomo, con el vientre, el pecho, el hocico,
  la barbilla, la cara interior de las patas y los dedos color crema.
- Rosetas angulosas (polígonos) casi negras con el centro tostado en el tronco, el
  cuello, los hombros y las ancas; manchas macizas pequeñas en la cabeza, las patas
  y la cola. Una hilera de manchas alargadas a lo largo del lomo.
- Antifaz oscuro alrededor de cada ojo, línea oscura del labio y puntos en el
  nacimiento de los bigotes (no tiene bigotes).
- Nariz grande casi negra. Dos colmillos de marfil que asoman hacia abajo y dos más
  pequeños hacia arriba. Mechones crema en los carrillos.
- Orejas con el dorso oscuro y una mancha clara, y el interior crema rosado.
- Collar tejido ancho en la base del cuello, del color del jugador (`#2ec4a6`) en
  damero de dos tonos, con ribetes dorados, seis cuentas doradas y, al frente, un
  amuleto de jade con aro dorado flanqueado por dos colmillos.
- Un glifo de jade que brilla en cada hombro: un aro con un punto en el centro y
  tres rayitas encima.
- Ajorcas de jade con bordes dorados en las dos patas **delanteras**, sobre la garra.
- Garras de marfil solo en las patas delanteras (cuatro por pata).
- Cola larga, gruesa, con manchas, dos anillos oscuros y la punta oscura.

**Paleta** (de `PAL` y `make_materials` en `build_balam.py`).

| Parte | Hex |
| --- | --- |
| Pelaje / lomo y centro de las rosetas / crema | `#eb9a2c` / `#c26f18` / `#fbe9c2` |
| Rosetas, manchas, antifaz, anillos de la cola | `#2a1a11` |
| Nariz / rosa de la nariz y las orejas | `#2b1a16` / `#d98a7a` |
| Interior de la boca | `#8a2f33` |
| Colmillos y garras | `#fff6e0` |
| Ojos de jade (emisivo) | `#59ffe0` |
| Collar (color del jugador) | `#2ec4a6` |
| Jade (amuleto, glifos, ajorcas; emisivo suave) | `#3ddba8` |
| Oro (ribetes, cuentas, aro del amuleto) | `#e8b53a` |

**Rasgos que no deben cambiar.**

- Ojos pequeños y rasgados de jade turquesa que brillan, con pupila vertical, bajo un
  ceño marcado: los mismos ojos de jade del alux.
- Rosetas poligonales oscuras con centro tostado sobre naranja dorado; vientre crema.
- Collar verde jade con cuentas doradas y amuleto de jade; glifo de jade en cada
  hombro; ajorcas de jade solo en las patas delanteras.
- Cola con dos anillos y punta oscura.
- Complexión maciza, de cabeza ancha y hocico corto: no es un guepardo esbelto ni
  un jaguar fotorrealista, y no tiene pelo suelto, melena ni bigotes.

**Descripción para prompt.**

> Stylized low-poly 3D fantasy jaguar, flat vertex colours, no textures: golden-orange big cat with cream belly and muzzle, dark angular rosettes, small fierce glowing jade eyes, broad head with dark nose and two fangs, teal woven collar with gold beads and jade amulet, jade glyph on each shoulder, jade anklets on front legs, long ringed tail with dark tip.

---

## Chiich Yaxché, la abuela

«La abuela del claro»: la más vieja de los aluxes, guardiana de la gran ceiba. No
se recolorea nunca. Modelo: `build_yaxche.py`.

**Proporciones.** 2.6 cabezas de alto. La misma cabeza, ojos y orejas del alux, sobre
un cuerpo de abuela: espalda encorvada (la cabeza va adelantada), panza redonda,
piernas cortas ocultas por el vestido, que llega a los tobillos. Se apoya en un
bastón más alto que ella, que sujeta con la mano derecha y descansa en el suelo.

**Ropa y accesorios.**

- Cabello de plata peinado hacia atrás, recogido en un moño bajo en la nuca con una
  cinta magenta de dos puntas; un mechón suelto cae por delante de cada oreja.
- Flor de mayo (plumeria) blanca de corazón amarillo, con dos hojas verdes, junto a
  la oreja izquierda. Un arete dorado pequeño en cada oreja.
- Cejas canosas y pobladas, caídas hacia fuera; párpados pesados; dos arrugas en la
  frente, surcos de la sonrisa, ojeras suaves; media sonrisa ladeada.
- Vestido blanco largo de una pieza. En el canesú, tres flores (magenta al centro,
  amarilla y turquesa) entre un hilo magenta y otro turquesa. Cerca del ruedo, una
  cenefa de 14 flores grandes (magenta, amarilla, turquesa, alternadas) con hojas
  verdes, bajo un hilo magenta; ruedo turquesa y fustán de encaje con una raya turquesa.
- Rebozo lila pálido: esclavina sobre los hombros, abierta en V por delante, con una
  franja más oscura en el borde, y dos puntas largas que cuelgan por delante hasta
  la cenefa de flores, cada una con una raya magenta y flecos.
- Collar de ocho cuentas de jade con una gota de jade al centro.
- Dos pulseras finas de oro en el antebrazo izquierdo; pulsera de hilo magenta y
  amarillo en la muñeca derecha. Sandalias sencillas de cuero marrón.
- Bastón de madera de ceiba, nudoso, con espinas cónicas, que arriba se dobla hacia
  delante en un cayado corto. Sobre la empuñadura lleva cuatro hilos enrollados
  (magenta, amarillo, turquesa, magenta). Del cayado brota un retoño verde con dos
  hojas que sostiene un botón de jade que brilla, rodeado por tres luciérnagas de jade.

**Paleta** (de `PAL` y `make_materials` en `build_yaxche.py`).

| Parte | Hex |
| --- | --- |
| Piel / sombra y arrugas / luz | `#a9714b` / `#8c563a` / `#bd8a62` |
| Rubor | `#c96a55` |
| Iris de jade (emisivo) | `#59ffe0` |
| Aro del iris / pupila / brillos | `#0c5a4f` / `#052a26` / `#fffaf0` |
| Línea del párpado / boca | `#4a2e25` / `#3a1c16` |
| Cabello de plata / mechas / reflejo | `#dedad3` / `#8a8785` / `#f6f4f0` |
| Cejas | `#c9c4bc` |
| Vestido / sombra del vestido / encaje | `#f0eadf` / `#cbc2b2` / `#f7f4ee` |
| Bordado: magenta / amarillo / turquesa / hoja | `#e0368c` / `#ffc233` / `#1fb8b0` / `#3fa34d` |
| Rebozo / borde / raya | `#b9a2df` / `#9379c2` / `#644093` |
| Flor de mayo / corazón | `#fff7ec` / `#ffc233` |
| Jade (collar, botón, luciérnagas; emisivo suave) | `#3ddba8` |
| Oro (pulseras, aretes) | `#e8b53a` |
| Sandalias / suela | `#7d4c27` / `#4a2c17` |
| Bastón: madera / veta oscura / veta clara / espinas | `#a08a68` / `#6c573e` / `#c0ad8b` / `#574330` |
| Retoño / hojas oscuras | `#5cb84c` / `#2f8a3c` |

El modelo define además un naranja de bordado (`#f0822e`) que no usa ninguna pieza.

**Rasgos que no deben cambiar.**

- Los mismos ojos enormes de jade turquesa que el alux, pero con el párpado de
  arriba caído (mirada amable y cansada), y las mismas orejas largas, más caídas.
- Cabello de plata con moño bajo y cinta magenta; flor de mayo blanca en la oreja izquierda.
- Vestido blanco con flores magenta, amarillas y turquesa; rebozo lila con dos
  puntas de flecos por delante; collar de cuentas de jade.
- Bastón de ceiba con espinas, siempre en la mano derecha, más alto que ella, con
  el retoño verde y el botón de jade que brilla en la punta, y sus tres luciérnagas.
- Encorvada y panzona, de la misma estatura que el alux: no es una anciana humana
  alta ni una bruja; nada de verrugas, nariz ganchuda ni sombrero.

**Descripción para prompt.**

> Stylized low-poly 3D fantasy character, flat vertex colours, no textures: small hunched elder Maya forest spirit, oversized round head, wrinkled brown skin, big glowing jade eyes, long pointed ears, low silver hair bun, white plumeria by her left ear, long white flower-embroidered dress, pale lilac shawl, jade bead necklace, tall thorny wooden staff topped by a glowing jade bud.

---

## Nojoch Tuunich, el Guardián Dormido

El primer jefe: un coloso de sillares de caliza que duerme sentado en el patio del
santuario y que no es un enemigo, sino alguien que olvidó a quién cuida. Modelo:
`build_nojoch.py`; diseño en `docs/BOSS.md`; medidas, materiales y animaciones en
`art/propuestas/nojoch/README.md`.

Las cuatro vistas y `nojoch_hoja.png` lo muestran en estado **«olvido»**, como aparece al
despertar: ojos magenta, vetas del Silencio encendidas, glifos del pecho apagados y cara
triste. `nojoch_liberado_hoja.png` es la misma hoja en estado **«liberado»**: sin vetas
(quedan como cicatrices), ojos, glifos y corazón de jade encendidos y cara serena. La
cámara está a 2.50 m de altura y a 10.34 m. A diferencia de los otros personajes, el
color no es el hex del modelo, sino el que da la luz del juego (ver «Paleta»).

**Proporciones.** 5.0 m de pie (casi cuatro alux) y 3.4 m sentado; 4.2 m de hombro a
hombro. Tres cabezas de alto: la cabeza con su crestería mide 1.70 m y es tan ancha como
el pecho, sin cuello. Tronco ancho y corto; brazos larguísimos y gruesos (2.86 m: las
manos llegan a un palmo del suelo) con manos enormes de tres dedos y pulgar; piernas muy
cortas (cadera a 1.40 m) con pies de más de un metro.

**Piezas.**

- Todo él son sillares de caliza encajados, con las aristas matadas y las juntas a la
  vista; algún desportillado. Sin ropa.
- Cabeza: caja ancha con orejeras cuadradas de disco tallado y pendientes; nariz en cuña;
  dos cejas de piedra separadas, caídas hacia fuera (la izquierda algo más alta); ojos
  almendrados hundidos que brillan; boca tallada como una ranura oscura con labio, de
  comisuras bajas, sobre un morro más claro; mandíbula en losa.
- Crestería: banda con cinco tachones y, encima, cornisas y pilares calados cada vez más
  estrechos, con una placa escalonada al frente; le falta un pilar a su izquierda.
- Pecho: una placa (pectoral) con cuatro glifos abstractos en fila —una espiral cuadrada,
  una escalera con una cuenta, un marco con un rombo y dos cabrios sobre tres cuentas—,
  cornisa encima y tres colgantes debajo. No son escritura.
- Espalda: un marco de piedra (espaldar) que sube por detrás de la cabeza y guarda un
  cristal de jade de seis caras, el corazón; debajo, una losa tallada con marco, tres
  cabrios en la espina y dos cuadros con rombo.
- Cinturón de tachones con un disco al frente y un faldón tallado.
- Articulaciones: rótulas de piedra más oscura en hombros, muñecas, caderas y tobillos;
  tambores con tapa en codos y rodillas; rodilleras con disco.
- Antebrazos con brazal de tres cabrios y muñequera de tacos; grebas con cabrios y
  ajorcas de tacos en los tobillos; rombo tallado en cada muslo.
- Muy poco musgo seco en lo alto de hombros y crestería y tres raíces finas (una baja
  por el hombro izquierdo).
- Vetas del Silencio: grietas finas de luz magenta, en zigzag, por hombros, antebrazos,
  pecho, espalda y cabeza. Solo mientras está olvidado.

**Paleta** (de `HEX` en `build_nojoch.py`). La primera columna es el código del modelo; la
piedra se ve más clara en el juego y en estas hojas, entre crema `#ecd2a0` al sol y arena
`#b08d62` a la sombra.

| Parte | Hex |
| --- | --- |
| Caliza: media / arena / crema / oscura | `#ba8f6b` / `#aa805e` / `#d0a781` / `#8e6a50` |
| Placas talladas (pectoral, banda, ajorcas, losa de la espalda) | `#c99565` |
| Juntas, cuencas y boca | `#4f3d30` |
| Desportillados / pátina de tierra | `#dfbf9c` / `#7d6248` |
| Musgo seco / oscuro / claro | `#737544` / `#565a36` / `#8d8a52` |
| Raíces / sombra | `#6a4c33` / `#45301f` |
| Glifos apagados | `#5a564b` |
| Jade: corazón y ojos / luz de los ojos / luz del corazón y de los glifos | `#2ec4a6` / `#59ffe0` / `#3fe8c4` |
| Silencio: luz de las vetas y de los ojos / filo / borde | `#fa3399` / `#ffc4e6` / `#b01c66` |
| Vetas apagadas (cicatrices) | `#8a7460` |

**Rasgos que no deben cambiar.**

- Es de sillares, no de roca: bloques tallados y encajados, de caras planas. Caliza
  cálida, crema y arena; nunca gris, verde ni negra, y sin metal.
- Cabeza ancha y sin cuello con la crestería escalonada; no lleva casco, cuernos ni corona.
- Cara de piedra triste, no feroz: cejas caídas hacia fuera, comisuras bajas, sin
  dientes ni colmillos. Liberado, serena: cejas casi rectas y una sonrisa leve.
- Cuatro glifos en el pecho, en fila; cristal de jade en la espalda, dentro de su marco.
- Brazos hasta el suelo con puños enormes de tres dedos y pulgar; piernas cortas.
- Olvidado: ojos y vetas magenta, glifos oscuros. Liberado: ojos, glifos y corazón de
  jade, sin vetas. Nunca las dos luces a la vez, salvo los glifos de jade que se van
  encendiendo durante el combate.
- No lleva armas ni armadura, y no es un robot: nada de tornillos, cables ni humo.

**Descripción para prompt.**

> Stylized low-poly 3D fantasy character, flat vertex colours, no textures: a colossal guardian statue built from stacked warm cream-and-sand limestone blocks, wide flat head with stepped temple-crest headdress, sad drooping stone brows, glowing magenta eyes, four dark carved glyph panels on the chest, huge three-fingered fists, short legs, thin glowing magenta cracks, sparse moss, jade crystal heart on its back.

Para el estado liberado, cambia lo magenta: *calm glowing jade eyes, four glowing jade
glyphs on the chest, a faint serene smile, no magenta cracks (only thin dark scars)*.

---

## Para usarlas con Kling

- Como referencia de personaje, sube la hoja (`*_hoja.png`) o dos o tres vistas
  sueltas; la de tres cuartos es la que más información da en una sola imagen.
- Acompaña siempre la imagen con la «descripción para prompt» y añade la acción y el
  escenario después. Repite el estilo (low-poly, colores planos, sin texturas) en
  cada plano: es lo primero que el generador tiende a perder.
- Los personajes son asimétricos a propósito (pluma, arete, nudo de la faja y morral
  del alux; flor y bastón de la abuela; el pilar que falta en la crestería del coloso,
  a su izquierda). Si un plano sale en espejo, se nota ahí.

## Lo que estas imágenes heredan de los modelos

Son defectos de los modelos, no del render; conviene no pedirle al generador que los
reproduzca.

- **Balam, por detrás:** el arranque de las patas traseras es un tubo abierto que
  asoma a los lados de la grupa como dos «copas» huecas.
- **Balam, cabeza:** el perfil, con la nariz gruesa y el hocico corto, recuerda a un
  oso o a un perro grande (ya está anotado en `art/README.md`).
- **Yaxché, hombros:** la parte alta de los brazos atraviesa el rebozo y se ve como
  un parche de piel en cada hombro. Las puntas del rebozo tienen un par de pliegues
  angulosos, y en la espalda del rebozo hay una sombra horneada con forma de mancha.
- **Alux y Yaxché, de perfil:** la oreja tapa casi toda la cara; para el rostro
  sirven la vista de frente y la de tres cuartos.
- **Alux, por detrás:** el cabello es un casquete liso de borde poligonal, sin mechones.
- **Manos:** pulgar y tres dedos; los dedos son tubos sin articulaciones.
- **Nojoch Tuunich:** los codos y las rodillas son tambores lisos, menos tallados que el
  resto; la crestería se lee de frente como losas apiladas más que como un peine calado;
  de perfil el corazón asoma por detrás de la cabeza. En la hoja de «olvido» las grietas
  de la furia, apagadas, se adivinan de cerca como costuras de la piedra: no hay que
  pedirle al generador que las dibuje.
