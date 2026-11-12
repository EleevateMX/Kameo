# Cinemáticas de Nojoch Tuunich — registro de producción con Kling

Producidas el 12 de noviembre de 2026, con el modelo definitivo del guardián y las tres fases del
combate ya implementadas y verificadas (pruebas con bots y en navegador).

| | «El despertar» | «La liberación» | Conjunto |
| --- | --- | --- | --- |
| Máximo autorizado | 450 | 350 | 800 |
| Suma de lo que declaró cada generación | 280 | 228 | 508 |
| **Saldo: antes 2 375 · después 1 887** | | | **488 consumidos** |

La diferencia de 20 entre la suma y el saldo: dos vídeos (n.º 6 y n.º 19) se aceptaron sin que la
respuesta dijera su coste; se han contado a 32 como los demás, pero el saldo dice que uno de los
dos costó menos. Vale el saldo: **488 créditos**, dentro de los dos máximos.

Precios (iguales que en «El sello cede»): 20 créditos por cuadro a 2K con `gemini-3-pro-image` y
8 por segundo de vídeo a 1080p sin audio con `kling-video-v3_0` (32 por plano de 4 s).

## Cómo se hizo

1. **Cuadros clave del juego** (`../despertar_*.jpg`, `../liberacion_*.jpg`): salen del propio guion
   de las cinemáticas (`scripts/preview.sh … kf_despertar_1a …`), con el modelo definitivo, a 1080p.
2. **Cuadros enriquecidos** (`cuadros/`): imagen a imagen, con el cuadro del juego y una referencia.
   La primera referencia fue el patio enriquecido de «El sello cede», para que el patio sea el
   mismo; después, los propios cuadros aprobados del guardián, para que sea el mismo en todos.
3. **Vídeo** (`originales/`): imagen a vídeo, 4 s, 1080p, un solo plano, sin audio. Con último
   cuadro sólo donde el final importa: el plano 4 del despertar (termina donde empieza el combate)
   y el plano 3 de la liberación (termina como queda el juego).
4. **Para el juego** (`game/web/static/video/`): `scripts/encode-cine.py <original> <id> 4.0` →
   720p, MP4 (H.264) y WebM (VP9), y su entrada en el manifiesto.

El sonido no es de Kling: cada plano lleva un sonido propio que pone el juego (`cine_patio_silencio`,
`cine_grietas`, `cine_ojos`, `cine_en_pie`, `cine_silencio_se_va`, `cine_pluma`), igual con vídeo
que con el respaldo del motor, y por los buses de volumen de siempre.

## Generaciones

### «El despertar de Nojoch Tuunich»

| N.º | Tipo | Para | Entrada | Créd. | Resultado |
| --- | --- | --- | --- | --- | --- |
| 1 | Imagen | Plano 4, final | `despertar_4b` (contrapicado) + patio de «El sello cede» | 20 | **Aprobada, con cambio de plan.** Diseño del guardián y patio, bien; pero el modelo lo colocó en la vista ancha desde el portal, no en el contrapicado. Esa vista es la «cámara del combate» del storyboard, así que el plano 4 se rehízo ancho (también en el motor) y este cuadro es su final y la referencia de todos los demás |
| 2 | Imagen | Plano 1, inicio | n.º 1 + `despertar_1a` como pose | 20 | **Aprobada.** Misma cámara y patio; sentado, dormido, ojos cerrados, cubierto de musgo y raíces |
| 3 | Imagen | Plano 3, inicio | `despertar_3a` + n.º 1 | 20 | **Aprobada.** Primer plano fiel al modelo: cejas caídas, boca triste, cuencas apagadas, grietas magenta |
| 4 | Imagen | Plano 4, inicio | n.º 2 + n.º 1 | 20 | **Aprobada.** El mismo cuadro del dormido, ya despierto: ojos magenta, cabeza alzada, polvo cayendo |
| 5 | Imagen | Plano 2, inicio | `despertar_2a` + n.º 1 | 20 | **Descartada.** Encuadre y diseño correctos, pero otro estilo: texturas más realistas y el cristal verde pálido |
| 6 | Vídeo | Plano 1 | n.º 2 | 32* | **Aprobada (en el juego).** El patio en silencio, el cristal late, la cámara se acerca; la estatua no se mueve |
| 7 | Vídeo | Plano 3 | n.º 3 | 32 | **Descartada.** Al abrir los ojos le salen pupila y blanco: no es el modelo |
| 8 | Vídeo | Plano 4 | n.º 4 → n.º 1 | 32 | **Aprobada (en el juego).** Se empuja con los puños y se yergue entre polvo; termina en pie tras el pedestal, de cara al portal |
| 9 | Imagen | Plano 2, inicio | `despertar_2a` + n.º 2 | 20 | **Aprobada.** Mismo estilo que el resto: musgo, raíces, cristal de jade luminoso |
| 10 | Vídeo | Plano 3 | n.º 3, prompt corregido | 32 | **Aprobada (en el juego).** Tiembla, cae polvo y las cuencas se llenan de luz magenta, sin pupilas. Sigue triste |
| 11 | Vídeo | Plano 2 | n.º 9 | 32 | **Aprobada (en el juego).** Las grietas magenta se extienden por el pecho y los brazos; una raíz se rompe; sigue dormido |
| | | | **Total** | **280** | 6 imágenes (120) y 5 vídeos (160); 2 descartes (52) |

### «La liberación de Nojoch Tuunich»

| N.º | Tipo | Para | Entrada | Créd. | Resultado |
| --- | --- | --- | --- | --- | --- |
| 12 | Imagen | Plano 2, inicio | `liberacion_2a` + n.º 3 | 20 | **Aprobada.** Fiel al modelo: ojos de jade, sonrisa serena, glifos encendidos, mano abierta |
| 13 | Vídeo | Plano 2 | n.º 12 | 32 | **Descartada.** A mitad levanta un puño cerrado con el ceño bajo: no es serenidad |
| 14 | Imagen | Plano 1, inicio | `liberacion_1a` + n.º 12 | 20 | **Aprobada.** De rodillas en la explanada, cara triste, grietas magenta aún encendidas |
| 15 | Imagen | Plano 3, final | `liberacion_3b` + n.º 12 | 20 | **Aprobada.** Manos abiertas y, flotando ante él, una pluma de quetzal de jade con raquis dorado |
| 16 | Vídeo | Plano 1 | n.º 14 | 32 | **Aprobada (en el juego).** Las grietas se apagan, las motas magenta se desprenden y se disuelven; la cámara gira |
| 17 | Imagen | Plano 3, inicio | n.º 15 (edición) | 20 | **Aprobada.** El mismo cuadro sin la pluma: sólo una luz de jade entre sus manos |
| 18 | Vídeo | Plano 2 | n.º 12, prompt corregido | 32 | **Aprobada (en el juego).** Alza la cabeza, sonríe y ofrece la mano abierta, palma arriba |
| 19 | Vídeo | Plano 3 | n.º 17 → n.º 15 | 32* | **Aprobada (en el juego).** La luz se despliega en pluma, sube y flota hacia la cámara. No aparece ningún alux |
| | | | **Total** | **228** | 5 imágenes (100) y 4 vídeos (128); 1 descarte (32) |

\* La respuesta no informó del coste; contado como los demás (ver arriba).

## Revisión de cada toma

Hoja de ocho cuadros de cada vídeo y cuadros sueltos a tamaño completo. Se comprobó en todas:

- que el guardián es el del juego (crestería de losas, cuatro paneles de glifos, hombros de bloque,
  rótulas, ojos de losa de luz sin pupilas) y que no cambia a lo largo del plano;
- que la expresión es la que toca: triste y confusa al despertar, **nunca enfadado**; serena al final;
- que el patio es el de «El sello cede» y la explanada, la del juego;
- que no aparecen jugadores, criaturas, textos ni marcas de agua;
- que el despertar termina con él en pie tras el pedestal (donde empieza el combate) y la liberación,
  con la pluma flotando ante él (como queda el juego).

Lo que no es perfecto: en los planos anchos del patio la cara del guardián es una interpretación
más blanda que en el primer plano (está lejos y no se nota en movimiento); la luz de la liberación
es de día claro, menos dramática que el atardecer del despertar; y en «El sello cede», publicada
antes, el patio se ve **sin** el coloso.

## Archivos

| Carpeta | Contenido |
| --- | --- |
| `../despertar_*.jpg`, `../liberacion_*.jpg` | Cuadros clave del juego (1920 × 1080), primer y último de cada plano |
| `cuadros/` | Los nueve cuadros enriquecidos aprobados (2752 × 1536, JPEG) y el descartado por estilo |
| `originales/` | Las siete tomas aprobadas tal como salieron de Kling (1080p, H.264, 24 cuadros/s) |
| `web/` | Las dos secuencias montadas a 720p (`el_despertar.mp4`, `la_liberacion.mp4`) y las dos tomas descartadas, reducidas |
| `game/web/static/video/` | Lo que carga el juego: `despertar_1…4` y `liberacion_1…3` en MP4 y WebM, y el manifiesto |

Peso de lo que descarga un jugador (sólo un formato): despertar 2.00 MB en MP4 o 1.08 MB en WebM;
liberación 1.72 MB o 1.09 MB. Con «El sello cede», 6.35 MB en MP4 o 4.20 MB en WebM en total.

## Prompts

En todos los vídeos: `duration 4`, `resolution 1080p`, `imageCount 1`, `prefer_multi_shots false`,
`enable_audio false`. En todas las imágenes: `aspect_ratio 16:9`, `img_resolution 2k`.

### Imágenes

**N.º 1 (referencia del guardián):**

> Image 1 is a flat low-poly game screenshot to transform. Image 2 is the STYLE REFERENCE: the same sanctuary courtyard already rendered as a high-end stylized 3D animated fantasy film frame. Transform image 1 so it matches the rendering of image 2 exactly: same warm golden-hour lighting with soft volumetric god rays through the jungle canopy, same weathered mossy carved limestone walls with cracks and small hanging vines, same worn stone floor, same floating jade crystal above its octagonal stone pedestal, same lush layered jungle behind the walls, a few drifting motes of light. Keep the SAME camera angle, composition and layout as image 1. THE MAIN SUBJECT is the stone colossus standing behind the pedestal: keep his design EXACTLY as in image 1, same proportions, same silhouette, same standing pose with arms hanging at his sides. He is a five-metre guardian built from stacked carved limestone blocks, with a wide stepped stone headdress of stacked slabs, heavy block shoulders, a horizontal row of four square carved glyph panels across the chest (dark, unlit), big blocky forearms and fists, short thick legs. His face keeps the same sad, confused expression: drooping stone brows, downturned mouth, two glowing magenta eyes. Thin jagged glowing magenta cracks of corrupting energy run across his chest, arms and legs exactly where they are in image 1. Render him as warm cream and sand coloured weathered limestone with chiselled edges, fine carved relief, small patches of moss and a few dry roots on the shoulders, soft ambient occlusion between the blocks and warm rim light. Stylized 3D animated film look, not photorealistic. Do not add or remove any element. No other characters, no people, no animals, no text, no logos, no watermark.

**N.º 2 y 4 (ediciones del cuadro anterior):** *Edit image 1. Keep EVERYTHING exactly as it is in
image 1: same camera, same framing, same courtyard… Change ONLY…* — en la 2, que esté dormido,
sentado como en la imagen 2 (pose del juego), ojos cerrados y grietas casi invisibles; en la 4, que
acabe de despertar: cabeza alzada, ojos magenta como en la imagen 2, grietas encendidas, musgo
caído, todavía sentado y apoyado en los puños.

**N.º 3, 9, 12, 14 y 15 (cuadro del juego + referencia):** *Re-render image 1… The output MUST keep
exactly the framing and composition of image 1: [descripción del encuadre]. Do NOT change the
camera… Image 2 is ONLY a reference for rendering style, materials, lighting and for the character's
design: do NOT copy the camera, the framing or the composition of image 2…* seguido del estado del
guardián en ese cuadro. Lo que hizo falta decir expresamente:

- N.º 3: *his EYES ARE STILL DARK: two deep dark eye sockets with no glow at all.*
- N.º 9 (tras descartar la 5): *match its rendering style EXACTLY: the same simple stylized low-poly
  look with faceted low-poly trees and flat clean surfaces (not painterly, not realistic)… and the
  same crystal: a bright glowing cyan-jade diamond.*
- N.º 12: *the colossus is FREED and at peace. His eyes glow soft JADE cyan (not magenta). His
  expression is SERENE… The four glyph panels on his chest are LIT… There is NO magenta energy
  anywhere: the cracks on his body are dark, healed scars.*
- N.º 15: *a single long, elegant quetzal tail feather made of luminous jade and turquoise light,
  with a thin golden central shaft and fine soft barbs on both sides… It is a feather, not a blade,
  not a leaf and not a crystal.*

**N.º 17:** *Edit this image. Keep EVERYTHING exactly as it is… Change ONLY this: REMOVE the large
jade feather completely… In its place, low between his two open hands in front of his waist, there
is only a small, soft ball of jade light… No feather anywhere in the image.*

### Vídeos

**N.º 6, plano 1 del despertar:**

> A quiet walled courtyard of an ancient jungle sanctuary at golden hour. At the back, behind the stone pedestal, a colossal statue made of stacked limestone blocks sits asleep, covered in moss and dry roots, completely motionless, eyes closed. The diamond-shaped jade crystal floating above the pedestal bobs gently and pulses once with soft light. Dust motes and tiny jade fireflies drift through the god rays, the hanging vines and jungle leaves stir very slightly. Very slow, steady camera push-in toward the statue. The statue does not move at all and does not change. Stylized 3D animated fantasy film, same lighting and design as the first frame. No other characters, no people, no animals, no text, no logos.

**N.º 11, plano 2:**

> Side view of a colossal statue made of stacked limestone blocks, sitting asleep on the courtyard floor, covered in moss and dry roots, eyes closed. Thin jagged cracks of glowing magenta energy slowly appear and spread across his chest, shoulder, arm and legs, like lightning creeping through the stone, growing brighter and pulsing. A little dust and a few dry leaves fall from him, and one or two of the dry roots on his shoulders snap. The statue stays seated and asleep with his eyes closed: he does not stand up, does not open his eyes and does not move his limbs. The four carved glyph panels on his chest stay dark. The glowing jade crystal in the foreground bobs gently. Very slow camera move, rising slightly toward his chest and head. […]

**N.º 10, plano 3** (la n.º 7 era igual sin la parte de los ojos):

> Extreme close-up of the face of a colossal guardian made of stacked limestone blocks. At first he is asleep: his two eye sockets are dark, empty rectangular hollows. The stone trembles, a little dust and small pebbles fall from his slab headdress, and the thin magenta cracks on his face and chest pulse brighter. Then a magenta glow ignites inside the two eye sockets and grows until each socket is completely filled with a flat, solid slab of bright magenta light. The eyes are only glowing magenta light: no pupils, no irises, no white eyeballs, no eyelashes, no cartoon eyes. He slowly lifts his head a little toward the camera. His expression stays sad and confused the whole time: drooping stone brows, downturned mouth; he never looks angry and never roars. Very slow camera push-in. […]

**N.º 8, plano 4:**

> The colossal guardian made of stacked limestone blocks, sitting behind the pedestal with his eyes glowing magenta, pushes against the floor with both stone fists and slowly rises to his full height, five metres tall. His stone blocks grind against each other, dust and small pebbles pour from his shoulders and headdress, moss and dry roots fall off him, the courtyard trembles slightly. He ends standing upright behind the pedestal, arms hanging at his sides, looking at the camera with a sad, confused expression; he never looks angry and never roars. The camera stays almost still, with a very slight push-in. […]

**N.º 16, plano 1 de la liberación:**

> A colossal guardian made of stacked limestone blocks crouches on his knees in a jungle clearing, tired, head slightly bowed. The thin magenta cracks of corrupting energy on his chest, arms and legs flicker, weaken and go out one by one, from his head down to his feet, leaving only dark healed scars in the stone. As each crack fades, small motes of magenta light detach from his body, rise into the air and dissolve. His sad expression slowly relaxes and he raises his head a little. His eyes and the four glyph panels on his chest keep glowing soft jade cyan the whole time. By the end there is no magenta left on him. He stays on his knees and does not stand up. Very slow camera orbit to the right with a slight push-in. […]

**N.º 18, plano 2** (la n.º 13 no prohibía el puño ni fijaba las cejas):

> Close shot of a colossal guardian made of stacked limestone blocks who has just been freed and is completely at peace. Very little movement, calm and gentle. He slowly lifts his head a little and looks toward the camera with a serene, kind smile; his stone brows are relaxed and level, never lowered, never frowning. His eyes glow soft jade cyan and the four carved glyph panels on his chest glow jade, pulsing slowly like a calm heartbeat. His big stone hand at the lower right stays OPEN the whole time, fingers extended, and slowly turns palm up toward the camera as a gentle offering. He never closes his hand, never makes a fist, never raises his arm, never waves and never points. […] The eyes are only flat glowing jade light: no pupils, no white eyeballs. There is no magenta anywhere. Very slow camera push-in. […]

**N.º 19, plano 3:**

> A serene colossal guardian made of stacked limestone blocks holds his two open stone hands out to the sides in an offering gesture. Between his hands, the small ball of jade light swells, rises slowly in front of his chest and unfurls into a single long, elegant quetzal feather made of luminous jade and turquoise light, with a thin golden shaft and fine soft barbs. The feather floats upright in the air in front of him, turning very slightly, shedding tiny motes of jade light, and drifts gently toward the camera. The guardian watches it with a calm, kind smile and does not move his arms; his hands stay open. […] Very slow camera pull back. […]

Todos los vídeos terminan con: *Stylized 3D animated fantasy film, [luz], same look as the first
frame. No other characters, no people, no text, no logos.*
