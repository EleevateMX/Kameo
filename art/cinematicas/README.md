# Cuadros clave de las cinemáticas

Primer y último cuadro de cada plano, sacados del juego con la cámara exacta del guion. Son la
entrada de Kling (imagen a vídeo): así el vídeo empieza y termina en el mismo encuadre que el plano
del motor que tiene debajo. No llevan interfaz, jugadores ni textos.

| Carpeta | Escena | Archivos |
| --- | --- | --- |
| `sello/` | «El sello cede» | `plano_1a/1b` (altar → portal), `plano_2a/2b` (sellado → abierto), `plano_3a/3b` (umbral → cristal del patio) |
| `jefe/` | «El despertar de Nojoch Tuunich» y «La liberación» | `despertar_1…4` y `liberacion_1…3`, con el modelo propuesto (sin producir; guiones en [docs/BOSS.md](../../docs/BOSS.md)) |
| `sello/kling/` | Producción con Kling | Originales, cuadros enriquecidos, secuencias montadas y [registro con prompts y costos](sello/kling/PRODUCCION.md) |

Regenerar (las cámaras están en `KEYFRAMES`, en `game/tools/preview.gd`):

```bash
PREVIEW_SIZE=1920x1080 scripts/preview.sh /tmp/cuadros kf_sello_1a kf_sello_1b kf_sello_2a kf_sello_2b kf_sello_3a kf_sello_3b
```

Storyboard, prompts y presupuesto: [docs/CINEMATICS.md](../../docs/CINEMATICS.md).
Hojas de personaje: [art/referencias/](../referencias/README.md).
