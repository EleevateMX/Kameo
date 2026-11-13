# Assets de audio: procedencia y licencias

Generado por `python3 art/audio/manifiesto.py` a partir de los manifiestos de los generadores
(`art/audio/manifiesto_*.json`). No editar a mano.

## Resumen

- **140 archivos** de audio viajan con el juego (17.6 MB en disco), todos **síntesis propia**:
  salen de los scripts de `art/audio/` (numpy: osciladores, ruido filtrado, envolventes,
  reverberación), con semillas fijas. No hay grabaciones, muestras ni bibliotecas de terceros.
- **Licencia:** original del proyecto ALUX. No hay atribuciones que cumplir ni licencias que renovar.
- **Motion Array: no se usa nada.** Su licencia estándar excluye expresamente apps, software y
  videojuegos (haría falta su plan Business, que se contrata aparte). Si algún día se quiere usar
  material suyo, antes hay que tener esa licencia por escrito y anotar aquí cada archivo con ella.
  Lo mismo para cualquier otra biblioteca: sin licencia que permita distribuirlo dentro de un
  videojuego, no entra.
- **Primera escucha (13 nov 2026).** El dueño del proyecto eligió de oído ocho sonidos entre los
  candidatos de `art/audio/candidatos/`: `balam_rugido`, `balam_grunido`, `balam_especial`,
  `jefe_embestida`, `jefe_choque`, `jefe_cae`, `jefe_despierta` y la voz de Chiich Yaxché de
  `cine_llamado_fx`; y escuchó y dejó como estaban `jefe_paso`, `jefe_losa`, `jefe_barrido`,
  `amb_aves`, `amb_cenote` y `amb_ruinas`. **El resto sigue sin escuchar**: se ha comprobado con
  mediciones (niveles, espectro, costuras de bucle, tiempos), no de oído: ver [AUDIO.md](AUDIO.md).
- Cualquier audio nuevo tiene que declararse en su manifiesto: `manifiesto.py --check` falla si
  hay un archivo sin declarar o con una licencia que no sea la del proyecto.

## Música

10 archivos, 7.78 MB.

| Archivo | Bus | Duración | Tamaño | Origen |
| --- | --- | --- | --- | --- |
| `mus_claro.mp3` | Music | 58.60 s | 933 KB | art/audio/gen_musica.py, función mus_claro() |
| `mus_emboscada.mp3` | Music | 39.40 s | 726 KB | art/audio/gen_musica.py, función mus_emboscada() |
| `mus_exploracion.mp3` | Music | 58.60 s | 938 KB | art/audio/gen_musica.py, función mus_exploracion() |
| `mus_jefe.mp3` | Music | 57.00 s | 875 KB | art/audio/gen_musica.py, función mus_jefe() |
| `mus_jefe_furia.mp3` | Music | 45.80 s | 789 KB | art/audio/gen_musica.py, función mus_jefe_furia() |
| `mus_liberacion.mp3` | Music | 52.20 s | 832 KB | art/audio/gen_musica.py, función mus_liberacion() |
| `mus_lobby.mp3` | Music | 58.60 s | 920 KB | art/audio/gen_musica.py, función mus_lobby() |
| `mus_peligro.mp3` | Music | 39.40 s | 532 KB | art/audio/gen_musica.py, función mus_peligro() |
| `mus_recuerdo.mp3` | Music | 58.60 s | 912 KB | art/audio/gen_musica.py, función mus_recuerdo() |
| `mus_victoria.mp3` | Music | 10.50 s | 138 KB | art/audio/gen_musica.py, función mus_victoria() |

## Ambientes

10 archivos, 2.74 MB.

| Archivo | Bus | Duración | Tamaño | Origen |
| --- | --- | --- | --- | --- |
| `amb_agua.mp3` | Ambience | 24.51 s | 307 KB | art/audio/gen_ambiente.py, función amb_agua |
| `amb_aves.mp3` | Ambience | 28.43 s | 160 KB | art/audio/gen_ambiente.py, función amb_aves |
| `amb_brasero.mp3` | Ambience | 11.03 s | 121 KB | art/audio/gen_ambiente.py, función amb_brasero |
| `amb_cenote.mp3` | Ambience | 33.00 s | 284 KB | art/audio/gen_ambiente.py, función amb_cenote |
| `amb_energia.mp3` | Ambience | 23.57 s | 222 KB | art/audio/gen_ambiente.py, función amb_energia |
| `amb_insectos.mp3` | Ambience | 26.08 s | 279 KB | art/audio/gen_ambiente.py, función amb_insectos |
| `amb_ruinas.mp3` | Ambience | 29.21 s | 241 KB | art/audio/gen_ambiente.py, función amb_ruinas |
| `amb_selva.mp3` | Ambience | 31.09 s | 377 KB | art/audio/gen_ambiente.py, función amb_selva |
| `amb_tormenta.mp3` | Ambience | 27.75 s | 407 KB | art/audio/gen_ambiente.py, función amb_tormenta |
| `amb_viento.mp3` | Ambience | 32.35 s | 282 KB | art/audio/gen_ambiente.py, función amb_viento |

## Bandas sonoras de las cinemáticas

8 archivos, 1.75 MB.

| Archivo | Bus | Duración | Tamaño | Origen |
| --- | --- | --- | --- | --- |
| `cine_despertar_fx.mp3` | Cinematics | 17.50 s | 254 KB | art/audio/gen_cine.py, función fx_despertar |
| `cine_despertar_mus.mp3` | Music | 17.50 s | 210 KB | art/audio/gen_cine.py, función mus_despertar |
| `cine_liberacion_fx.mp3` | Cinematics | 13.50 s | 186 KB | art/audio/gen_cine.py, función fx_liberacion |
| `cine_liberacion_mus.mp3` | Music | 13.50 s | 165 KB | art/audio/gen_cine.py, función mus_liberacion |
| `cine_llamado_fx.mp3` | Cinematics | 20.50 s | 282 KB | art/audio/gen_cine.py, función fx_llamado |
| `cine_llamado_mus.mp3` | Music | 20.50 s | 280 KB | art/audio/gen_cine.py, función mus_llamado |
| `cine_sello_fx.mp3` | Cinematics | 11.50 s | 179 KB | art/audio/gen_cine.py, función fx_sello |
| `cine_sello_mus.mp3` | Music | 11.50 s | 154 KB | art/audio/gen_cine.py, función mus_sello |

## Efectos e interfaz (dentro de la descarga del juego)

112 archivos, 5.29 MB.

| Archivo | Bus | Duración | Tamaño | Origen |
| --- | --- | --- | --- | --- |
| `aliado_caido.wav` | UI | 0.80 s | 34 KB | art/audio/gen_audio.py, función aliado_caido |
| `aliado_revive.wav` | UI | 0.80 s | 69 KB | art/audio/gen_audio.py, función aliado_revive |
| `altar_off.wav` | SFX | 0.25 s | 11 KB | art/audio/gen_audio.py, función altar_off |
| `altar_on.wav` | SFX | 0.40 s | 17 KB | art/audio/gen_audio.py, función altar_on |
| `ancla_activa.wav` | SFX | 0.60 s | 26 KB | art/audio/gen_audio.py, función ancla_activa |
| `apoyo_alux.wav` | SFX | 0.80 s | 69 KB | art/audio/gen_audio.py, función apoyo_alux |
| `aterrizar.wav` | SFX | 0.20 s | 9 KB | art/audio/gen_audio.py, función aterrizar |
| `balam_especial.wav` | SFX | 0.90 s | 39 KB | art/audio/gen_audio.py, función balam_especial |
| `balam_golpe.wav` | SFX | 0.35 s | 15 KB | art/audio/gen_audio.py, función balam_golpe |
| `balam_grunido.wav` | SFX | 0.45 s | 19 KB | art/audio/gen_audio.py, función balam_grunido |
| `balam_rugido.wav` | SFX | 1.00 s | 43 KB | art/audio/gen_audio.py, función balam_rugido |
| `cadenas_jade.wav` | SFX | 1.20 s | 52 KB | art/audio/gen_audio.py, función cadenas_jade |
| `caida.wav` | SFX | 0.90 s | 39 KB | art/audio/gen_audio.py, función caida |
| `chapoteo.wav` | SFX | 0.50 s | 22 KB | art/audio/gen_audio.py, función chapoteo |
| `chispa.wav` | SFX | 0.30 s | 13 KB | art/audio/gen_audio.py, función chispa |
| `chispa_2.wav` | SFX | 0.30 s | 13 KB | art/audio/gen_audio.py, función chispa_variante(0) |
| `chispa_3.wav` | SFX | 0.30 s | 13 KB | art/audio/gen_audio.py, función chispa_variante(1) |
| `chispa_impacto.wav` | SFX | 0.30 s | 13 KB | art/audio/gen_audio.py, función chispa_impacto |
| `cine_cenote.wav` | Cinematics | 4.00 s | 172 KB | art/audio/gen_audio.py, función cine_cenote |
| `cine_en_pie.wav` | Cinematics | 4.00 s | 172 KB | art/audio/gen_audio.py, función cine_en_pie |
| `cine_grietas.wav` | Cinematics | 4.00 s | 172 KB | art/audio/gen_audio.py, función cine_grietas |
| `cine_ojos.wav` | Cinematics | 4.00 s | 172 KB | art/audio/gen_audio.py, función cine_ojos |
| `cine_patio_silencio.wav` | Cinematics | 4.00 s | 172 KB | art/audio/gen_audio.py, función cine_patio_silencio |
| `cine_pluma.wav` | Cinematics | 4.00 s | 172 KB | art/audio/gen_audio.py, función cine_pluma |
| `cine_silencio_se_va.wav` | Cinematics | 4.00 s | 172 KB | art/audio/gen_audio.py, función cine_silencio_se_va |
| `corazon_expuesto.wav` | SFX | 1.00 s | 43 KB | art/audio/gen_audio.py, función corazon_expuesto |
| `corazon_golpe.wav` | SFX | 0.40 s | 17 KB | art/audio/gen_audio.py, función corazon_golpe |
| `corazon_libre.wav` | SFX | 1.60 s | 69 KB | art/audio/gen_audio.py, función corazon_libre |
| `criatura_ataque.wav` | SFX | 0.25 s | 11 KB | art/audio/gen_audio.py, función criatura_ataque |
| `criatura_llamada.wav` | SFX | 0.60 s | 26 KB | art/audio/gen_audio.py, función criatura_llamada |
| `curar.wav` | SFX | 0.80 s | 34 KB | art/audio/gen_audio.py, función curar |
| `dano.wav` | SFX | 0.30 s | 13 KB | art/audio/gen_audio.py, función dano |
| `dano_fuerte.wav` | SFX | 0.55 s | 24 KB | art/audio/gen_audio.py, función dano_fuerte |
| `derrota.wav` | SFX | 2.60 s | 112 KB | art/audio/gen_audio.py, función derrota |
| `emboscada.wav` | SFX | 1.60 s | 69 KB | art/audio/gen_audio.py, función emboscada |
| `enemigo_aparece.wav` | SFX | 0.80 s | 34 KB | art/audio/gen_audio.py, función enemigo_aparece |
| `enemigo_aviso.wav` | SFX | 0.35 s | 15 KB | art/audio/gen_audio.py, función enemigo_aviso |
| `enemigo_dano.wav` | SFX | 0.20 s | 9 KB | art/audio/gen_audio.py, función enemigo_dano |
| `enemigo_golpe.wav` | SFX | 0.40 s | 17 KB | art/audio/gen_audio.py, función enemigo_golpe |
| `enemigo_muere.wav` | SFX | 0.50 s | 22 KB | art/audio/gen_audio.py, función enemigo_muere |
| `enemigo_paso.wav` | SFX | 0.25 s | 11 KB | art/audio/gen_audio.py, función enemigo_paso |
| `enemigo_purificado.wav` | SFX | 0.70 s | 60 KB | art/audio/gen_audio.py, función enemigo_purificado |
| `escudo_alux.wav` | SFX | 0.70 s | 60 KB | art/audio/gen_audio.py, función escudo_alux |
| `escudo_golpe.wav` | SFX | 0.40 s | 17 KB | art/audio/gen_audio.py, función escudo_golpe |
| `esquiva.wav` | SFX | 0.25 s | 11 KB | art/audio/gen_audio.py, función esquiva |
| `garras.wav` | SFX | 0.25 s | 11 KB | art/audio/gen_audio.py, función garras |
| `garras_2.wav` | SFX | 0.25 s | 11 KB | art/audio/gen_audio.py, función garras_variante(0) |
| `garras_3.wav` | SFX | 0.25 s | 11 KB | art/audio/gen_audio.py, función garras_variante(1) |
| `glifo_restaurado.wav` | SFX | 1.20 s | 52 KB | art/audio/gen_audio.py, función glifo_restaurado |
| `golpe.wav` | SFX | 0.15 s | 7 KB | art/audio/gen_audio.py, función golpe |
| `guardian_ataque.wav` | SFX | 0.50 s | 22 KB | art/audio/gen_audio.py, función guardian_ataque |
| `guardian_llamada.wav` | SFX | 0.90 s | 39 KB | art/audio/gen_audio.py, función guardian_llamada |
| `interactuar.wav` | SFX | 0.30 s | 13 KB | art/audio/gen_audio.py, función interactuar |
| `jefe_aturdido.wav` | SFX | 1.50 s | 65 KB | art/audio/gen_audio.py, función jefe_aturdido |
| `jefe_aviso.wav` | SFX | 0.80 s | 34 KB | art/audio/gen_audio.py, función jefe_aviso |
| `jefe_barrido.wav` | SFX | 0.90 s | 39 KB | art/audio/gen_audio.py, función jefe_barrido |
| `jefe_cae.wav` | SFX | 1.90 s | 82 KB | art/audio/gen_audio.py, función jefe_cae |
| `jefe_choque.wav` | SFX | 1.80 s | 78 KB | art/audio/gen_audio.py, función jefe_choque |
| `jefe_despierta.wav` | SFX | 3.90 s | 168 KB | art/audio/gen_audio.py, función jefe_despierta |
| `jefe_embestida.wav` | SFX | 1.40 s | 60 KB | art/audio/gen_audio.py, función jefe_embestida |
| `jefe_fase.wav` | SFX | 1.80 s | 78 KB | art/audio/gen_audio.py, función jefe_fase |
| `jefe_llamada.wav` | SFX | 1.50 s | 65 KB | art/audio/gen_audio.py, función jefe_llamada |
| `jefe_losa.wav` | SFX | 1.20 s | 52 KB | art/audio/gen_audio.py, función jefe_losa |
| `jefe_paso.wav` | SFX | 0.50 s | 22 KB | art/audio/gen_audio.py, función jefe_paso |
| `jefe_respira.wav` | SFX | 3.00 s | 129 KB | art/audio/gen_audio.py, función jefe_respira |
| `liberacion.wav` | SFX | 4.00 s | 172 KB | art/audio/gen_audio.py, función liberacion |
| `lluvia_piedra.wav` | SFX | 4.00 s | 172 KB | art/audio/gen_audio.py, función lluvia_piedra |
| `luz_alux.wav` | SFX | 0.60 s | 52 KB | art/audio/gen_audio.py, función luz_alux |
| `objetivo.wav` | UI | 0.50 s | 22 KB | art/audio/gen_audio.py, función objetivo |
| `paso_1.wav` | SFX | 0.12 s | 5 KB | art/audio/gen_audio.py, función paso(0) |
| `paso_2.wav` | SFX | 0.12 s | 5 KB | art/audio/gen_audio.py, función paso(1) |
| `paso_3.wav` | SFX | 0.12 s | 5 KB | art/audio/gen_audio.py, función paso(2) |
| `paso_agua_1.wav` | SFX | 0.30 s | 13 KB | art/audio/gen_audio.py, función paso_agua(0) |
| `paso_agua_2.wav` | SFX | 0.30 s | 13 KB | art/audio/gen_audio.py, función paso_agua(1) |
| `paso_hierba_1.wav` | SFX | 0.18 s | 8 KB | art/audio/gen_audio.py, función paso_hierba(0) |
| `paso_hierba_2.wav` | SFX | 0.18 s | 8 KB | art/audio/gen_audio.py, función paso_hierba(1) |
| `paso_hierba_3.wav` | SFX | 0.18 s | 8 KB | art/audio/gen_audio.py, función paso_hierba(2) |
| `paso_piedra_1.wav` | SFX | 0.08 s | 3 KB | art/audio/gen_audio.py, función paso_piedra(0) |
| `paso_piedra_2.wav` | SFX | 0.08 s | 3 KB | art/audio/gen_audio.py, función paso_piedra(1) |
| `paso_piedra_3.wav` | SFX | 0.08 s | 3 KB | art/audio/gen_audio.py, función paso_piedra(2) |
| `pilar_rompe.wav` | SFX | 1.00 s | 43 KB | art/audio/gen_audio.py, función pilar_rompe |
| `pilar_sube.wav` | SFX | 1.00 s | 43 KB | art/audio/gen_audio.py, función pilar_sube |
| `pluma_jade.wav` | SFX | 2.50 s | 108 KB | art/audio/gen_audio.py, función pluma_jade |
| `punto_control.wav` | UI | 0.90 s | 39 KB | art/audio/gen_audio.py, función punto_control |
| `purificar.wav` | SFX | 1.00 s | 43 KB | art/audio/gen_audio.py, función purificar |
| `reaparecer.wav` | SFX | 0.90 s | 39 KB | art/audio/gen_audio.py, función reaparecer |
| `recoger.wav` | SFX | 0.35 s | 30 KB | art/audio/gen_audio.py, función recoger |
| `ritual_pulso.wav` | SFX | 1.20 s | 52 KB | art/audio/gen_audio.py, función ritual_pulso |
| `ritual_toque.wav` | SFX | 2.00 s | 86 KB | art/audio/gen_audio.py, función ritual_toque |
| `salto.wav` | SFX | 0.20 s | 9 KB | art/audio/gen_audio.py, función salto |
| `salto_impacto.wav` | SFX | 0.40 s | 17 KB | art/audio/gen_audio.py, función salto_impacto |
| `salto_jaguar.wav` | SFX | 0.50 s | 22 KB | art/audio/gen_audio.py, función salto_jaguar |
| `santuario_abre.wav` | SFX | 2.20 s | 95 KB | art/audio/gen_audio.py, función santuario_abre |
| `silencio_grieta.wav` | SFX | 0.80 s | 34 KB | art/audio/gen_audio.py, función silencio_grieta |
| `sin_energia.wav` | UI | 0.15 s | 7 KB | art/audio/gen_audio.py, función sin_energia |
| `transformar.wav` | SFX | 0.70 s | 30 KB | art/audio/gen_audio.py, función transformar |
| `ui_abrir.wav` | UI | 0.20 s | 9 KB | art/audio/gen_audio.py, función ui_abrir |
| `ui_cancelar.wav` | UI | 0.20 s | 9 KB | art/audio/gen_audio.py, función ui_cancelar |
| `ui_cerrar.wav` | UI | 0.20 s | 9 KB | art/audio/gen_audio.py, función ui_cerrar |
| `ui_click.wav` | UI | 0.06 s | 3 KB | art/audio/gen_audio.py, función ui_click |
| `ui_confirmar.wav` | UI | 0.22 s | 19 KB | art/audio/gen_audio.py, función ui_confirmar |
| `ui_error.wav` | UI | 0.25 s | 11 KB | art/audio/gen_audio.py, función ui_error |
| `ui_invitacion.wav` | UI | 0.50 s | 43 KB | art/audio/gen_audio.py, función ui_invitacion |
| `ui_jugador_entra.wav` | UI | 0.40 s | 17 KB | art/audio/gen_audio.py, función ui_jugador(True) |
| `ui_jugador_sale.wav` | UI | 0.40 s | 17 KB | art/audio/gen_audio.py, función ui_jugador(False) |
| `ui_mover.wav` | UI | 0.05 s | 4 KB | art/audio/gen_audio.py, función ui_mover |
| `ui_prueba.wav` | UI | 1.00 s | 43 KB | art/audio/gen_audio.py, función ui_prueba |
| `ui_recompensa.wav` | UI | 1.20 s | 103 KB | art/audio/gen_audio.py, función ui_recompensa |
| `ui_sala_creada.wav` | UI | 0.70 s | 60 KB | art/audio/gen_audio.py, función ui_sala_creada |
| `victoria.wav` | SFX | 3.20 s | 138 KB | art/audio/gen_audio.py, función victoria |
| `zarpazo.wav` | SFX | 0.50 s | 22 KB | art/audio/gen_audio.py, función zarpazo |
| `zarpazo_carga.wav` | SFX | 0.80 s | 34 KB | art/audio/gen_audio.py, función zarpazo_carga |

## Bucles provisionales que ya no viajan en la versión web

7 archivos de la primera capa (mono, 22 kHz). Siguen en `game/assets/audio/` para
ejecutar el juego fuera del navegador, pero la exportación web los excluye: los sustituyen la música
y los ambientes de arriba.

| Archivo | Bus | Duración | Tamaño | Origen |
| --- | --- | --- | --- | --- |
| `amb_brasero.wav` | Ambience | 4.00 s | 172 KB | art/audio/gen_audio.py, función amb_brasero |
| `amb_selva.wav` | Ambience | 10.00 s | 431 KB | art/audio/gen_audio.py, función amb_selva |
| `mus_claro.wav` | Music | 19.20 s | 827 KB | art/audio/gen_audio.py, función mus_claro |
| `mus_emboscada.wav` | Music | 9.60 s | 413 KB | art/audio/gen_audio.py, función mus_emboscada |
| `mus_jefe.wav` | Music | 24.00 s | 1034 KB | art/audio/gen_audio.py, función mus_jefe |
| `mus_jefe_furia.wav` | Music | 24.00 s | 1034 KB | art/audio/gen_audio.py, función mus_jefe_furia |
| `mus_recuerdo.wav` | Music | 24.00 s | 1034 KB | art/audio/gen_audio.py, función mus_recuerdo |
