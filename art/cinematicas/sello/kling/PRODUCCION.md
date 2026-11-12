# «El sello cede» — registro de producción con Kling

Producida el 12 de noviembre de 2026 con un presupuesto autorizado de **500 créditos**.
**Usados: 284.** Saldo antes: 2 659 · saldo después: 2 375 (consultado en Kling).

Dos tratamientos de los mismos tres planos (3 + 4 + 3 = 10 s):

- **A, fiel al videojuego:** parte de los cuadros del juego tal cual.
- **B, fantasía cinematográfica enriquecida:** parte de esos mismos cuadros pasados por imagen a
  imagen para enriquecer luz, materiales y atmósfera sin tocar la arquitectura. **Es el que está en
  el juego.**

## Precios medidos

| Qué | Modelo | Precio |
| --- | --- | --- |
| Cuadro clave enriquecido, 2K, 16:9 | `gemini-3-pro-image` (imagen a imagen) | **20 créditos** |
| Vídeo 1080p sin audio, con o sin último cuadro | `kling-video-v3_0` | **8 créditos por segundo** (24 por 3 s, 32 por 4 s) |

El precio sale en la respuesta de cada generación (`creditsConsumed`) y coincide con la diferencia de saldo.

## Generaciones

| N.º | Tipo | Plano | Trat. | Entrada | Créditos | Resultado |
| --- | --- | --- | --- | --- | --- | --- |
| 1 | Imagen | 2 (inicio) | B | `plano_2a.jpg` | 20 | **Descartada.** Conserva la arquitectura al milímetro, pero el aspecto apenas cambia: sigue viéndose plana. |
| 2 | Vídeo 4 s | 2 | A | `plano_2a.jpg` → `plano_2b.jpg` | 32 | **Aprobada.** La cúpula se agrieta y estalla, los barrotes se deshacen y termina en el cuadro exacto del juego con el santuario abierto. |
| 3 | Imagen | 2 (inicio) | B | `plano_2a.jpg`, prompt reforzado | 20 | **Aprobada.** Misma arquitectura; luz de atardecer, piedra con musgo y grietas, barrotes con resplandor, partículas. Referencia de estilo de las demás. |
| 4 | Imagen | 2 (final) | B | `plano_2b.jpg` + n.º 3 como estilo | 20 | **Aprobada.** Santuario abierto, sin barrotes ni cúpula, cristal al fondo. |
| 5 | Imagen | 1 (inicio) | B | `plano_1a.jpg` + n.º 3 como estilo | 20 | **Aprobada.** |
| 6 | Imagen | 3 (inicio) | B | `plano_3a.jpg` + n.º 3 como estilo | 20 | **Aprobada.** |
| 7 | Vídeo 4 s | 2 | B | n.º 3 → n.º 4 | 32 | **Aprobada (en el juego).** Fracturas luminosas recorren la cúpula, estalla en partículas, el sol tallado se enciende y el portal queda abierto. |
| 8 | Vídeo 3 s | 1 | B | n.º 5 | 24 | **Aprobada (en el juego).** Los glifos del altar pasan a jade, la energía sube hacia el santuario y la rejilla de la cúpula se intensifica. |
| 9 | Vídeo 3 s | 3 | B | n.º 6 | 24 | **Aprobada (en el juego).** La cámara entra, el cristal emite anillos de jade, vetas y niebla magenta invaden el patio y el cielo se vuelve violeta. Sin criaturas. |
| 10 | Vídeo 3 s | 1 | A | `plano_1a.jpg` → `plano_1b.jpg` | 24 | **Aprobada.** |
| 11 | Vídeo 3 s | 3 | A | `plano_3a.jpg` → `plano_3b.jpg` | 24 | **Descartada.** Obligada a terminar en el cuadro limpio del juego, la corrupción aparece y desaparece. |
| 12 | Vídeo 3 s | 3 | A | `plano_3a.jpg` (sin último cuadro) | 24 | **Aprobada.** La corrupción crece hasta el corte. |
| | | | | **Total** | **284** | 5 imágenes (100) y 7 vídeos (184); 2 descartes (44) |

Revisión de cada toma: hoja de ocho cuadros y cuadros sueltos a tamaño completo. Se comprobó que no
cambia la arquitectura, que no aparecen personajes, criaturas, textos ni marcas de agua, y que el
plano 2 termina con el santuario abierto, como queda en el juego.

## Archivos

| Carpeta | Contenido |
| --- | --- |
| `originales/` | Las seis tomas aprobadas tal como salieron de Kling (1080p, H.264, 24 cuadros/s) |
| `cuadros/` | Los cuatro cuadros clave enriquecidos (2752 × 1536; guardados en JPEG de alta calidad) |
| `web/` | Las dos secuencias montadas a 720p para verlas de corrido |
| `../plano_*.jpg` | Los cuadros clave del juego de los que parte todo |
| `game/web/static/video/` | Lo que carga el juego: `sello_1/2/3` en MP4 (H.264) y WebM (VP9), 720p, y su manifiesto |

Peso de lo que descarga un jugador: 2.63 MB en MP4 o 2.03 MB en WebM (sólo uno de los dos).

Conversión para web (por plano; `-t` es la duración del plano en el guion):

```bash
ffmpeg -i originales/B_plano2.mp4 -t 4.0 -an -vf "scale=1280:720:force_original_aspect_ratio=increase,crop=1280:720,fps=24,format=yuv420p" \
  -c:v libx264 -profile:v main -level 3.1 -preset slow -crf 23 -maxrate 2600k -bufsize 5200k -movflags +faststart sello_2.mp4
```

```bash
ffmpeg -i originales/B_plano2.mp4 -t 4.0 -an -vf "scale=1280:720:force_original_aspect_ratio=increase,crop=1280:720,fps=24,format=yuv420p" \
  -c:v libvpx-vp9 -crf 34 -b:v 0 -deadline good -cpu-used 2 -row-mt 1 sello_2.webm
```

## Prompts

### Imagen a imagen (tratamiento B)

**N.º 3, cuadro de referencia (plano 2, sellado):**

> Transform this flat low-poly game screenshot into a spectacular frame from a high-end stylized 3D animated fantasy adventure film, while keeping the SAME scene: same camera angle and composition, same sanctuary layout and silhouette, same gate with the golden sun emblem above it, same cyan glyph panels on the pillars, same vertical magenta energy bars sealing the gate, same translucent pink magic dome with its grid of energy lines, same jungle setting. Upgrade everything else: dramatic golden-hour cinematic lighting with the sun low behind the jungle, strong volumetric god rays and drifting mist between the trees, deep soft shadows and ambient occlusion, warm rim light on the stone edges. The stone becomes weathered carved limestone with rich surface detail, cracks, moss and small hanging vines. The jungle becomes lush, dense and layered with detailed tropical leaves and ferns. The magenta bars and the pink dome glow intensely with bloom and cast pink light onto the stone and the ground; the dome's energy lines shimmer; the cyan glyphs and the golden sun emblem emit soft light. Floating jade and gold magic particles and fireflies in the air, atmospheric depth haze. Rich materials, cinematic colour grading, stylized (not photorealistic), no characters, no creatures, no text, no logos, no new buildings.

**N.º 4, 5 y 6** (con el n.º 3 como segunda imagen): empiezan todos igual y cambian la descripción del encuadre.

> Image 1 is a flat low-poly game screenshot to transform. Image 2 is the STYLE REFERENCE: the same sanctuary already rendered as a high-end stylized 3D animated fantasy film frame. Transform image 1 so it matches the rendering of image 2 exactly: same dramatic golden-hour lighting […] Keep the SAME camera angle, composition and layout as image 1 […]

- N.º 4: *IMPORTANT: in this frame the sanctuary is OPEN: there are NO magenta bars in the gate and NO pink dome; through the open gate you see the inner courtyard with a glowing jade crystal floating above a stone pedestal.*
- N.º 5: *the round stone altar plate with carved glyphs on the ground in the foreground, the stone marker pillar with its magenta band and pennant, the sealed sanctuary behind it […] and the large translucent pink magic dome.*
- N.º 6: *we look through the open stone gate into the walled inner courtyard; in the centre stands the low octagonal stone pedestal with a glowing turquoise basin and, floating above it, the diamond-shaped jade crystal.*

El primer intento (n.º 1) pedía «clean readable shapes» y «only improve the rendering»: demasiado tímido.

### Imagen a vídeo

Todos con `kling-video-v3_0`, 1080p, `enable_audio=false`, `prefer_multi_shots=false`, una toma.

**Plano 1, B (n.º 8):**

> The carved glyphs on the round stone altar in the foreground blaze with jade-green light. Streams of glowing jade energy rise from the altar and flow along the ground toward the sealed sanctuary. The large translucent pink magic dome covering the sanctuary begins to vibrate and react: its grid of energy lines intensifies and pulses brighter and brighter, ripples run across its surface and thin luminous cracks start to appear on it. The magenta bars in the gate flicker. Slow, smooth low camera push-in toward the sanctuary. Keep the same architecture, altar, jungle and lighting as the first frame; the dome stays in place and does not break yet. Epic stylized 3D animated fantasy film, volumetric light rays, floating magic particles. No characters, no people, no creatures, no text, no logos.

**Plano 2, B (n.º 7):**

> The translucent pink magic dome over the ancient stone sanctuary is struck from within by surging energy: bright glowing fractures race across its surface, then the dome shatters into thousands of luminous particles of ancient jade and gold magic that swirl around the temple columns and drift upward. The vertical magenta energy bars sealing the gate flicker violently, break apart and dissolve into sparks. The golden sun emblem above the gate flares brightly and a powerful wave of warm golden light bursts outward from the opening gate, revealing the inner courtyard and its floating jade crystal. Slow, smooth cinematic camera push-in toward the gate. Keep the same architecture, stone, jungle and lighting as the first frame. Epic stylized 3D animated fantasy film, volumetric light, magic particles. No characters, no people, no creatures, no text, no logos.

**Plano 3, B (n.º 9):**

> Slow, smooth cinematic camera push-in through the stone gate into the quiet inner courtyard, toward the diamond-shaped jade crystal floating above its octagonal stone pedestal. The ancient crystal awakens: it begins to glow brighter and brighter, pulsing, sending rings of jade light across the floor. Then the mood turns ominous: the warm golden light dims toward a dark purple dusk, thin veins of dark magenta corruption creep along the cracks of the walls and the floor toward the pedestal, dark magenta mist rolls in low over the ground from the edges, and the crystal flickers as if threatened. Keep the same courtyard, walls, pedestal and crystal as the first frame. Epic stylized 3D animated fantasy film, volumetric light, floating particles. No characters, no people, no creatures, no monsters, no statues, no text, no logos.

**Tratamiento A (n.º 2, 10 y 12):** la misma acción de cada plano, con este cierre en lugar del de «epic stylized film»:

> Stylized low-poly 3D animation, flat colours, clean shapes, same architecture, colours and layout as the first frame. No characters, no people, no animals, no text, no logos.

En el n.º 12 se añadió: *The corruption stays and intensifies; it does not disappear.*

## Lo aprendido para las siguientes

1. **Enriquecer el cuadro clave antes de animar** es lo que da el salto visual; el vídeo hereda el
   aspecto del primer cuadro. Pedirlo con timidez no sirve: hay que nombrar luz, materiales y
   atmósfera, y repetir qué elementos no se tocan.
2. **Un cuadro enriquecido como referencia de estilo** mantiene iguales los demás.
3. **El último cuadro sirve cuando el estado cambia** (sellado → abierto): garantiza que el vídeo
   termine como el juego. Estorba cuando el plano debe terminar distinto de como empezó sin que
   exista ese cuadro en el juego (la corrupción del plano 3).
4. Tres segundos por plano dan para una acción; la fractura del sello necesitó cuatro.
5. Planos sin personajes ni criaturas salieron bien a la primera en seis de siete vídeos.
