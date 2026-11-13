#!/usr/bin/env python3
"""Banda sonora de las cuatro cinemáticas de ALUX (Alpha 0.3.1), sintetizada por código.

Por cada cinemática de `game/scripts/shared/story_def.gd` (`CUTSCENES`) genera dos pistas
sin bucle, de la duración de la cinemática más 1.5 s de cola, en `game/web/static/audio/`:

    cine_<id>_fx.mp3    efectos y ambiente de los planos (bus Cinematics)
    cine_<id>_mus.mp3   música / tono emocional (bus Music), más baja que los efectos

y el manifiesto `cine.json`. Una sola banda sonora sirve para el vídeo y para el respaldo
del motor: los dos corren sobre la misma línea de tiempo y el sonido lo pone el juego.

Todo es síntesis propia con numpy (ver `_dsp_estereo.py`): sin grabaciones, sin muestras y
sin voces. Música en Re menor pentatónica con instrumentos sintetizados de inspiración
mesoamericana (flauta de barro, tambor de tronco, sonaja, caracol, kalimba, madera hueca).

Uso:
    python art/audio/gen_cine.py                  # genera todo, escribe el manifiesto y comprueba
    python art/audio/gen_cine.py --check          # solo comprueba lo que hay en disco
    python art/audio/gen_cine.py --solo sello     # regenera solo esa cinemática
    python art/audio/gen_cine.py --espectros DIR  # además, espectrogramas PNG en DIR
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path

import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parent))
from _dsp_estereo import (  # noqa: E402
    DOS_PI, LICENCIA, MOTIVO_MAYOR, MOTIVO_MENOR, PARC_CRISTAL, RAIZ, RITMO_MOTIVO, SALIDA, SEMILLA, SR,
    actualizar_manifiesto, campana, campana_env, carpeta_tmp, chasquido, codificar_mp3, colchon_st,
    convolucionar, crujidos, cuerno, db, destellos, env_perc, escombros, escribir_json, escribir_wav,
    espectrograma, fase_de, filtrar, flauta, gemido, gen, glis, impacto_piedra, kalimba, lento, lin,
    limitar, lufs, madera, medir, midi, modos, n_, pan, poner, rafaga, rampa, reverb, rms, ruido,
    ruido_barrido, ruido_st, salida, saturar, semilla_de, sonaja, t_, tambor, tambor_grave, tirones,
    trompa, zumbido,
)
from _voz_granular import Tracto, env_pulsos, filtro_variable, granos, pulsos, suavizar  # noqa: E402

COLA = 1.5  # segundos de cola tras el final de la cinemática
CALIDAD = 5  # LAME -q:a
FX_LUFS = (-20.0, -16.0, -18.0)  # mínimo, máximo, objetivo
MUS_LUFS = (-24.0, -20.0, -22.0)
FX_PICO_MAX = -2.0  # dBFS sobre el MP3 decodificado
SUMA_PICO_MAX = -1.0  # dBFS de efectos + música sumados
FX_TECHO = -4.2  # techos del limitador antes de codificar
MUS_TECHO = -9.0
TOTAL_MAX = 2_200_000
STORY_DEF = RAIZ / "game" / "scripts" / "shared" / "story_def.gd"

# Duración de los planos de cada cinemática. `--check` comprueba que coinciden con story_def.gd.
PLANOS = {
    "sello": (3.0, 4.0, 3.0),
    "despertar": (4.0, 4.0, 4.0, 4.0),
    "liberacion": (4.0, 4.0, 4.0),
    "llamado": (5.0, 4.5, 5.0, 4.5),
}
TITULOS = {
    "sello": "El sello cede",
    "despertar": "El despertar de Nojoch Tuunich",
    "liberacion": "La liberación de Nojoch Tuunich",
    "llamado": "El llamado",
}


def total(cine: str) -> float:
    return float(sum(PLANOS[cine]))


def inicios(cine: str) -> list:
    return [float(x) for x in np.concatenate([[0.0], np.cumsum(PLANOS[cine])[:-1]])]


def lienzo(cine: str) -> np.ndarray:
    return np.zeros((2, n_(total(cine) + COLA)))


def sala(x, g, **kw):
    """Reverberación recortada a la duración de la entrada."""
    return reverb(x, g, **kw)[..., :x.shape[-1]]


# --------------------------------------------------------------------------------------
# Piezas de efectos compartidas
# --------------------------------------------------------------------------------------

def arrastre(seg, g, lo=60.0, hi=1100.0, ritmo=(4.0, 18.0), temblor=7.5):
    """Roca enorme que se arrastra: roce a tirones y temblor grave (mono, RMS ~0.3)."""
    k = n_(seg)
    t = t_(k)
    y = ruido(k, g, lo, hi, color=1.1) * tirones(k, g, *ritmo)
    y += 0.7 * ruido(k, g, 30, 110, color=2.0) * (0.55 + 0.45 * np.sin(DOS_PI * temblor * t))
    return 0.3 * y / rms(y)


def latido(g, m=69, cristal=0.6):
    """Latido doble: dos pulsos sordos con un anillo vítreo (el Silencio dentro de la piedra)."""
    y = np.zeros(n_(0.95))
    for t0, gan in ((0.0, 1.0), (0.17, 0.7)):
        poner(y, glis(96, 58, 0.14) * env_perc(n_(0.14), 0.04, 0.004), t0, 0.9 * gan)
        poner(y, campana(midi(m), 0.7, tau=0.17, ataque=0.004, parciales=PARC_CRISTAL), t0, cristal * gan)
    return y


def polvo(seg, g, lo=1800.0, hi=6000.0, tau=0.35):
    """Polvo y arenilla que cae tras un golpe (estéreo)."""
    k = n_(seg)
    return ruido_st(k, g, lo, hi, color=1.0, ancho=0.7) * env_perc(k, tau, 0.05) * tirones(k, g, 3.0, 14.0, 1.0)


def silbo(f0, f1, seg, curva=1.0):
    """Silbido de ave inventado: barrido senoidal con envolvente de campana."""
    k = n_(seg)
    u = np.arange(k) / k
    w = fase_de(f0 * (f1 / f0) ** (u ** curva))
    return (np.sin(w) + 0.12 * np.sin(2 * w)) * np.sin(np.pi * u) ** 1.5


def gota(g, f):
    """Gota en agua quieta: «plic» que sube de tono y se apaga enseguida."""
    k = n_(0.11)
    t = t_(k)
    y = np.sin(fase_de(f * (1.0 - 0.38 * np.exp(-t / 0.011)))) * env_perc(k, 0.024, 0.001)
    j = n_(0.004)
    y[:j] += 0.2 * ruido(j, g, 1500, 6000) * np.exp(-t[:j] / 0.001)
    return y


# --- Voz de Chiich Yaxché, la abuela árbol (plano 4 de «El llamado») ---------------------
# Elegida de oído por el dueño del proyecto el 13 de noviembre de 2026 (candidato A
# «murmullo» de `art/audio/candidatos/`, escuchado dentro de la escena). Es una voz anciana
# sugerida, sin palabras: pulsos glotales a altura de voz, con el temblor y la ronquera de
# una voz vieja; formantes de vocales abiertas que se mueven de sílaba en sílaba; y la
# entonación de dos frases, una llamada que sube y un refunfuño que cae. Sustituye a la voz
# de crujidos de la Alpha 0.3.1, que podía sonar a puerta. No parte de ninguna voz grabada:
# las vocales usan frecuencias de formantes típicas de una voz de mujer.

# Vocales (Hz, ancho, ganancia de cada formante) y murmullo nasal entre sílabas
VOCALES = {
    "a": ((800.0, 80.0, 1.00), (1150.0, 90.0, 0.60), (2800.0, 120.0, 0.16), (3500.0, 130.0, 0.06), (4950.0, 140.0, 0.010)),
    "o": ((450.0, 70.0, 1.00), (800.0, 80.0, 0.38), (2830.0, 100.0, 0.14), (3500.0, 130.0, 0.04), (4950.0, 135.0, 0.005)),
    "e": ((420.0, 60.0, 1.00), (1650.0, 80.0, 0.22), (2700.0, 120.0, 0.11), (3300.0, 150.0, 0.05), (4950.0, 200.0, 0.005)),
    "u": ((340.0, 50.0, 1.00), (720.0, 60.0, 0.26), (2530.0, 170.0, 0.04), (3500.0, 180.0, 0.012), (4950.0, 200.0, 0.002)),
    "m": ((270.0, 60.0, 0.70), (1050.0, 150.0, 0.08), (2300.0, 200.0, 0.03), (3300.0, 250.0, 0.010), (4950.0, 300.0, 0.001)),
}
# Sílabas: (inicio, duración, tono inicial y final en semitonos sobre la base, vocal inicial y final, fuerza)
# «¡Despierta, alux!»: tres sílabas con la segunda acentuada, pausa, y dos más con la última hacia arriba
FRASE_LLAMADA = ((0.00, 0.22, 0.0, 1.0, "e", "e", 0.80), (0.24, 0.36, 4.0, 3.0, "a", "a", 1.25), (0.62, 0.26, 1.5, -1.0, "o", "o", 0.80),
                 (1.02, 0.18, 0.0, 2.0, "a", "a", 0.85), (1.22, 0.50, 3.0, 8.0, "o", "a", 1.30))
# «La selva te necesita…»: siete sílabas más bajas y más rápidas, que caen y acaban con la voz rota
FRASE_REFUNFUNO = ((0.00, 0.16, 2.0, 2.0, "a", "a", 0.70), (0.18, 0.22, 3.0, 2.0, "o", "o", 0.90), (0.42, 0.16, 1.0, 1.0, "e", "e", 0.70),
                   (0.62, 0.16, 1.0, 0.0, "o", "o", 0.70), (0.80, 0.16, 0.0, 0.0, "a", "a", 0.70), (0.98, 0.24, 0.0, -2.0, "o", "o", 0.90),
                   (1.24, 0.44, -3.0, -8.0, "o", "u", 0.80))
FRASES_VOZ = ((0.30, FRASE_LLAMADA), (2.40, FRASE_REFUNFUNO))  # inicio de cada frase desde el principio del plano
SEMILLA_VOZ = "candidatos-2026-11:chiich_voz__A_murmullo"  # la del candidato que se escuchó
# Sonoridad de la voz dentro de la pista antes del acabado: la misma que tenía la voz anterior
VOZ_LUFS = -16.317061691049965


def guion_voz(n):
    """Curvas de las dos frases a lo largo del plano: tono (semitonos), fuerza, ronquera y tracto."""
    t = t_(n)
    tono = np.zeros(n)
    fuerza = np.zeros(n)
    ronca = np.zeros(n)
    claves = []  # (instante, formantes)
    for t0, frase in FRASES_VOZ:
        for i, (ini, dur, s0, s1, v0, v1, f) in enumerate(frase):
            a, b = t0 + ini, t0 + ini + dur
            dentro = (t >= a) & (t < b)
            u = (t[dentro] - a) / dur
            tono[dentro] = s0 + (s1 - s0) * u ** 1.3
            # la sílaba entra en 45 ms y sale en 70; entre sílabas ligadas queda un murmullo nasal
            fuerza[dentro] = f ** 0.7 * np.clip(u * dur / 0.045, 0.0, 1.0) ** 0.8 * np.clip((1.0 - u) * dur / 0.07, 0.0, 1.0) ** 0.8
            claves += [(a - 0.01, VOCALES["m"]), (a + 0.06, VOCALES[v0]), (b - 0.07, VOCALES[v1]), (b + 0.01, VOCALES["m"])]
            if i == len(frase) - 1 and s1 < s0:  # la frase que cae acaba con la voz rota
                ronca[dentro] = np.clip((u - 0.35) / 0.4, 0.0, 1.0)
        # el tono se mantiene en los huecos para que la voz no salte al volver
        fin = t0 + frase[-1][0] + frase[-1][1]
        hueco = (t >= t0) & (t < fin) & (fuerza <= 0.0)
        tono[hueco] = np.interp(t[hueco], t[(t >= t0) & (t < fin) & (fuerza > 0.0)], tono[(t >= t0) & (t < fin) & (fuerza > 0.0)])
    tono = suavizar(tono, 0.05)
    murmullo = suavizar((fuerza > 0).astype(float), 0.16)
    fuerza = np.clip(suavizar(fuerza, 0.02), 0.0, None)
    fuerza = np.maximum(fuerza, 0.16 * murmullo * (murmullo > 0.55))  # las sílabas ligadas no se cortan
    claves.sort(key=lambda c: c[0])
    return tono, fuerza, ronca, np.array([c[0] for c in claves]), np.array([c[1] for c in claves])


def voz_anciana(g, n, base, escala, aire, temblor=0.022, ataque=0.0009, pecho=0.55):
    """Las dos frases sin palabras (mono) y su envolvente.

    `base` es la altura de la voz (Hz) y `escala` multiplica los formantes. `pecho` es la
    ganancia de un formante grave fijo, justo encima de la altura de la voz: da el calor de
    la fundamental, que los formantes de las vocales solos dejan flaca.
    """
    t = t_(n)
    tono, fuerza, ronca, tc, m = guion_voz(n)
    grave = np.tile([[1.12 * base / escala, 110.0, pecho]], (len(tc), 1, 1))
    m = np.concatenate([grave, m], axis=1)
    tr = Tracto(tc, m[:, :, 0] * escala, m[:, :, 1], m[:, :, 2])
    # voz vieja: temblor de unos 5 Hz que no es regular, y altura que deriva
    tiembla = np.sin(DOS_PI * np.cumsum(5.2 * (1.0 + 0.12 * lento(n, g, 0.5, 2.5))) / SR)
    f0 = base * 2.0 ** (tono / 12.0) * (1.0 + temblor * tiembla * (0.6 + 0.4 * lento(n, g, 0.3, 1.5))) \
        * (1.0 + 0.012 * lento(n, g, 1.0, 6.0)) * (1.0 - 0.10 * ronca)
    tp, amp = pulsos(n, g, f0, jitter=0.018 + 0.05 * ronca, shimmer=0.12, sub=0.10 + 0.75 * ronca, retardo=0.06)
    env_p = np.interp(tp, t, fuerza * (1.0 + 0.08 * tiembla))
    vivo = env_p > 1e-3
    tp, amp = tp[vivo], amp[vivo] * env_p[vivo]
    voz = granos(n, tp, amp, tr, ataque=ataque)
    voz /= rms(voz[fuerza > 0.3]) + 1e-12
    # aire de la voz: ruido a ráfagas glotales por el mismo tracto
    soplo = ruido(n, g, 300, 9000, color=0.6) * (0.5 * fuerza + env_pulsos(n, tp, amp, 0.0015))
    soplo = filtro_variable(soplo, lambda tt, f: tr.ganancia(tt, f, ancho=1.6) * (f / (f + 900.0)))
    soplo /= rms(soplo[fuerza > 0.3]) + 1e-12
    return voz + aire * soplo, fuerza


def crujido_tronco(g, seg, f, ritmo=(9.0, 17.0)):
    """El tronco cruje al moverse: pega y resbala lento, grave y apagado (sin tono que suba: no es una puerta)."""
    k = n_(seg)
    u = np.arange(k) / k
    tp, amp = pulsos(k, g, ritmo[0] + (ritmo[1] - ritmo[0]) * np.sin(np.pi * u), jitter=0.3, shimmer=0.5)
    tr = Tracto(np.array([0.0, seg]), np.tile([f, 2.71 * f, 5.15 * f], (2, 1)), np.tile([14.0, 30.0, 60.0], (2, 1)),
                np.tile([1.0, 0.45, 0.15], (2, 1)))
    y = granos(k, tp, amp * np.interp(tp, t_(k), np.sin(np.pi * u) ** 0.8), tr, ataque=0.0015)
    return filtrar(y, 80, 1600) / (np.max(np.abs(y)) + 1e-12)


def en_tronco(x, mezcla):
    """La voz dentro de un tronco hueco: se le suma su paso por las resonancias de la cavidad."""
    ri = modos(((132.0, 0.45, 0.050), (287.0, 1.0, 0.035), (455.0, 0.7, 0.025), (910.0, 0.3, 0.012)), 0.25)
    hueco = convolucionar(x, ri, circular=False)
    return x + mezcla * hueco * (rms(x) / (rms(hueco) + 1e-12))


def voz_chiich():
    """La voz de Chiich Yaxché para el plano 4 de «El llamado» (estéreo, 5 s desde el inicio del plano).

    Voz de anciana que tararea con la boca entreabierta (base de 172 Hz), algo a la izquierda,
    con el aire del tronco hueco y dos crujidos de tronco; lleva su sala corta y la sala de la
    pista, y sale con la sonoridad `VOZ_LUFS`. Tiene su propio generador aleatorio (el del
    candidato que se eligió de oído), aparte del de la pista.
    """
    g = gen(SEMILLA_VOZ)
    n = n_(4.4)
    mono, fuerza = voz_anciana(g, n, base=172.0, escala=0.95, aire=0.28)
    mono = en_tronco(mono, 0.15)
    cuerpo = rms(mono[fuerza > 0.3])
    y = pan(mono, -0.15)
    y = y + 0.10 * cuerpo * ruido_st(n, g, 150, 1100, color=1.2, ancho=0.6) * np.clip(suavizar(fuerza, 0.35), 0.0, None)
    for t0, f in ((0.05, 150.0), (2.10, 120.0)):  # el tronco cruje al moverse
        poner(y, crujido_tronco(g, 0.5, f), t0, 0.35 * cuerpo, 0.3)
    v = reverb(filtrar(y, 110.0, 6000.0), g, t60=0.9, mezcla=0.18, agudos=4500.0)[:, :n_(4.7)]
    v = reverb(v, g, t60=1.5, mezcla=0.2, agudos=6000.0)  # la misma sala que el resto de la pista
    k = n_(5.0)
    v = np.concatenate([v, np.zeros((2, max(0, k - v.shape[-1])))], axis=-1)[:, :k]
    v = v * rampa(k, 0.01) * salida(k, 0.3)
    return v * lin(VOZ_LUFS - lufs(v))


def _gastar_voz_anterior(g):
    """Gasta del generador de la pista los mismos números que gastaba la voz anterior.

    La voz de crujidos de la Alpha 0.3.1 se sintetizaba con el generador de la pista, entre
    las hojas del plano 4 y el toc-toc de madera. Al quitarla, el toc-toc, las chispas del
    final y la sala de toda la pista saldrían con otros números: aquí se piden los mismos
    (por sílaba: cinco uniformes y dos tandas de ruido; después los dos crujidos de tronco y
    las cuatro respuestas de su sala), para que el resto de la pista sea, muestra a muestra,
    el que se midió y se escuchó con la voz nueva.
    """
    for dur in (0.22, 0.36, 0.24, 0.18, 0.48, 0.16, 0.22, 0.16, 0.16, 0.16, 0.24, 0.42):
        for _ in range(4):
            g.uniform()
        g.standard_normal(n_(dur))
        g.standard_normal(n_(dur))
        g.uniform()
    for _ in range(2):  # los dos crujidos de tronco
        g.uniform()
        g.uniform()
        g.standard_normal(n_(0.5))
        g.standard_normal(n_(0.5))
    for _ in range(4):  # la sala de la voz (0.9 s): dos respuestas por canal
        g.standard_normal(n_(0.9 * 1.1))


def notas(y, g, inst, lista, gan=1.0, p=0.0):
    """Coloca notas: lista de (inicio, midi, duración, intensidad). `inst(f, dur)` da la nota."""
    for ini, m, dur, vel in lista:
        poner(y, inst(midi(m), dur), ini, gan * vel, p)


# --------------------------------------------------------------------------------------
# «El sello cede» (3 + 4 + 3 s)
# --------------------------------------------------------------------------------------

def fx_sello():
    g = gen("cine_sello_fx")
    y = lienzo("sello")
    # --- Plano 1 (0–3 s): los altares resuenan y la energía de jade converge en el portal
    for t0, m, p in ((0.10, 62, -0.8), (0.55, 65, 0.8), (1.00, 69, -0.4), (1.45, 72, 0.4)):
        seg = 3.25 - t0
        k = n_(seg)
        tt = t_(k)
        f = midi(m)
        x = np.sin(DOS_PI * f * tt) + 0.6 * np.sin(DOS_PI * 1.006 * f * tt + 1.0) + 0.25 * np.sin(DOS_PI * 2.76 * f * tt)
        poner(y, x * rampa(k, 0.25) * (0.5 + 0.5 * tt / seg) * salida(k, 0.3), t0, 0.15, p)
        poner(y, campana(2 * f, 1.2, tau=0.4, ataque=0.004), t0, 0.26, p)  # el altar se enciende
        poner(y, rafaga(0.25, g, 150, 900, tau=0.05, color=1.0), t0, 0.22, p)
    for j in range(7):  # estelas que van de los lados al centro, cada vez más seguidas
        t0 = 0.45 + 2.0 * (j / 7.0) ** 0.8
        dur = min(0.95, 3.02 - t0)
        k = n_(dur)
        u = np.arange(k) / k
        x = ruido_barrido(k, g, 700.0 * (3800.0 / 700.0) ** u, ancho=0.45, color=0.5, f_min=400.0, f_max=7000.0,
                          bandas=10) * campana_env(k, 1.2) * (0.5 + 0.5 * u)
        poner(y, pan(x, (-0.9 if j % 2 == 0 else 0.9) * (1.0 - u) ** 0.7), t0, 0.12 * (0.6 + 0.08 * j))
    for _ in range(46):  # chispas de jade que se aprietan hacia el final del plano
        t0 = 3.0 - 2.6 * g.uniform() ** 1.8
        f = 2500.0 * (7500.0 / 2500.0) ** g.uniform()
        x = np.sin(DOS_PI * f * t_(n_(0.07))) * env_perc(n_(0.07), 0.012, 0.001)
        poner(y, x, t0, 0.10 * g.uniform(0.3, 1.0), g.uniform(-0.9, 0.9) * (3.0 - t0) / 2.6)
    k = n_(3.0)
    u = np.arange(k) / k
    y[:, :k] += 0.14 * ruido_st(k, g, 40, 120, color=2.0, ancho=0.3) * u ** 2
    # --- Plano 2 (3–7 s): el sello resiste, se parte, estalla y el portal se abre con peso
    k = n_(1.95)
    u = np.arange(k) / k
    z = zumbido(k, g, midi(38) * 2.0 ** (7.0 * u ** 1.5 / 12.0), trem=(6.0, 16.0), brillo=0.8)
    poner(y, pan(z * (0.15 + 0.85 * u ** 1.8) * rampa(k, 0.05) * salida(k, 0.03), 0.3 * np.sin(DOS_PI * 1.3 * u)),
          3.0, 0.42)
    poner(y, crujidos(1.9, g, 70, crece=1.2, ancho=0.8), 3.0, 0.5)
    for t0, gan, p in ((3.9, 0.5, -0.5), (4.4, 0.7, 0.5), (4.75, 0.9, -0.2)):
        poner(y, chasquido(g, gan, grave=g.uniform(120.0, 170.0)), t0, 0.7, p)
    poner(y, chasquido(g, 1.3, 120.0), 4.95, 0.9, 0.0)  # la grieta que parte el sello
    poner(y, saturar(impacto_piedra(g, 0.5, 130, 50, tau=0.10, brillo=1.3)), 4.95, 0.75, 0.0)
    estallido = np.zeros((2, n_(1.6)))  # estallido vítreo en 5.05 s
    poner(estallido, ruido_st(n_(0.4), g, 2500, 9000, color=0.5, ancho=0.8) * env_perc(n_(0.4), 0.06, 0.001), 0.0, 0.5)
    for _ in range(26):
        f = 1800.0 * (6500.0 / 1800.0) ** g.uniform()
        poner(estallido, campana(f, 0.9, tau=g.uniform(0.05, 0.25), ataque=0.001, parciales=PARC_CRISTAL),
              g.uniform(0.0, 0.05), g.uniform(0.2, 0.6), g.uniform(-0.9, 0.9))
    for _ in range(30):  # esquirlas que caen
        f = 2500.0 * (7500.0 / 2500.0) ** g.uniform()
        t0 = 0.08 + 1.2 * g.uniform() ** 1.5
        poner(estallido, campana(f, 0.25, tau=0.04, ataque=0.001, parciales=PARC_CRISTAL), t0,
              0.22 * (1.0 - 0.7 * t0 / 1.3) * g.uniform(0.4, 1.0), g.uniform(-0.9, 0.9))
    poner(y, estallido, 5.05, 0.55)
    k = n_(1.45)  # la losa del portal se arrastra (5.30–6.75 s) y encaja
    u = np.arange(k) / k
    poner(y, pan(arrastre(1.45, g, ritmo=(5.0, 22.0)) * campana_env(k, 0.6), -0.3 + 0.5 * u), 5.30, 1.5)
    poner(y, gemido(k, g, 70.0 * (48.0 / 70.0) ** u, ronco=1.8) * campana_env(k, 1.0), 5.30, 0.22, 0.1)
    poner(y, saturar(impacto_piedra(g, 0.9, 105, 36, tau=0.22, brillo=0.7)), 6.72, 0.95, 0.1)
    poner(y, glis(58, 30, 0.8) * env_perc(n_(0.8), 0.28, 0.004), 6.72, 0.5, 0.0)
    escombros(y, g, 6.80, 7.25, 12, gan=0.2, graves=0.2)
    poner(y, polvo(0.7, g, tau=0.2), 6.75, 0.05)
    # --- Plano 3 (7–10 s): silencio inquietante, algo se mueve, aviso de los Olvidados
    k = n_(3.3)
    tt = t_(k)
    aire = ruido_st(k, g, 60, 420, color=1.8, ancho=0.6) * rampa(k, 0.5) * salida(k, 0.4)
    fino = np.sin(DOS_PI * 1174.7 * tt) + np.sin(DOS_PI * 1178.1 * tt + 0.6)
    poner(y, 0.03 * aire + pan(0.006 * fino * rampa(k, 0.8) * salida(k, 0.3), 0.0), 7.0)
    for t0, p, dur in ((7.85, 0.55, 0.38), (8.55, -0.6, 0.30)):  # algo se arrastra a un lado y a otro
        j = n_(dur)
        x = ruido(j, g, 300, 2600, color=1.0) * tirones(j, g, 18.0, 60.0) * campana_env(j, 0.8)
        poner(y, x, t0, 0.065, p)
        poner(y, rafaga(0.03, g, 1500, 5000, tau=0.004), t0 + dur, 0.08, p)
    j = n_(0.9)
    v = np.arange(j) / j
    poner(y, gemido(j, g, 62.0 * (54.0 / 62.0) ** v, ronco=1.5) * campana_env(j, 1.0), 8.25, 0.07, -0.2)
    j = n_(1.0)  # 9.0–10.0 s: el aviso crece y se corta
    v = np.arange(j) / j
    aviso = 0.5 * gemido(j, g, 82.0 * (112.0 / 82.0) ** (v ** 2), ronco=2.6, tope=1700.0) * v ** 1.5
    aviso += 0.4 * zumbido(j, g, midi(50) * 2.0 ** (3.0 * v / 12.0), trem=(9.0, 18.0), brillo=1.0) * v ** 2
    poner(y, pan(aviso * salida(j, 0.02), 0.25 * np.sin(DOS_PI * 2.0 * v)), 9.0, 0.55)
    t0, paso, i = 9.0, 0.13, 0
    while t0 < 9.95:  # castañeteo de piedra que se acelera
        f1 = g.uniform(900.0, 1700.0)
        x = rafaga(0.03, g, 1200, 5000, tau=0.004, ataque=0.0004)
        poner(x, modos(((f1, 1.0, 0.008), (2.3 * f1, 0.5, 0.005)), 0.028), 0.0, 0.8)
        poner(y, x, t0, 0.10 + 0.22 * (t0 - 9.0), 0.6 if i % 2 else -0.6)
        t0 += paso
        paso = max(0.035, paso * 0.86)
        i += 1
    y = sala(y, g, t60=1.6, mezcla=0.22, agudos=5500.0)
    poner(y, saturar(impacto_piedra(g, 0.3, 120, 60, tau=0.05, brillo=1.2)), 9.97, 0.6, 0.0)  # corte seco
    return y


def mus_sello():
    g = gen("cine_sello_mus")
    y = lienzo("sello")
    # Plano 1: expectación. Colchón de Re, ocarina que sube La–Do–Re, tambor que se aprieta
    for m, gan in ((38, 0.5), (50, 0.6), (57, 0.45)):
        poner(y, colchon_st(midi(m), 3.4, 1.0, 0.6), 0.0, 0.16 * gan)
    notas(y, g, lambda f, d: flauta(f, d, g), ((0.35, 69, 0.75, 0.8), (1.05, 72, 0.75, 0.9), (1.75, 74, 1.3, 1.0)),
          0.30, -0.2)
    for t0, gan in ((0.04, 0.5), (1.0, 0.6), (2.0, 0.7), (2.5, 0.75), (2.75, 0.8)):
        poner(y, tambor_grave(g), t0, 0.5 * gan, 0.1)
    poner(y, sonaja(1.2, g, crece=1.5), 1.8, 0.10, 0.4)
    # Plano 2: tensión. Redoble que se cierra, caracol que crece, golpe en el estallido (5.05 s)
    t0, paso = 3.0, 0.42
    while t0 < 4.93:
        poner(y, tambor_grave(g, f0=66.0, seg=0.7, tau=0.2), t0, 0.28 + 0.25 * (t0 - 3.0) / 1.9, -0.1)
        t0 += paso
        paso = max(0.085, paso * 0.83)
    k = n_(1.6)
    poner(y, cuerno(midi(38), 1.6, g, ataque=0.5, rel=0.08) * (np.arange(k) / k) ** 1.3, 3.35, 0.34, 0.15)
    poner(y, tambor_grave(g, f0=58.0, seg=1.4, tau=0.4), 5.05, 0.9, 0.0)
    poner(y, tambor(140.0, 0.4, g, tau=0.1), 5.05, 0.4, -0.3)
    poner(y, cuerno(midi(50), 1.9, g), 5.08, 0.30, -0.25)
    poner(y, cuerno(midi(57), 1.8, g), 5.14, 0.20, 0.3)
    notas(y, g, lambda f, d: kalimba(f, d, g), [(5.25 + 0.22 * i, m, 1.2, 0.9 - 0.06 * i)
                                               for i, m in enumerate((74, 72, 69, 67, 65, 62))], 0.30, 0.25)
    poner(y, tambor_grave(g, f0=55.0, seg=1.2, tau=0.35), 6.72, 0.6, 0.0)
    # Plano 3: casi silencio. Re con tritono muy bajo, kalimba suelta, latido que se acelera
    for m, gan in ((50, 0.5), (56, 0.28), (38, 0.5)):
        poner(y, colchon_st(midi(m), 3.2, 1.2, 0.25), 6.9, 0.10 * gan)
    notas(y, g, lambda f, d: kalimba(f, d, g, brillo=0.6), ((7.4, 69, 1.5, 0.7), (8.1, 65, 1.5, 0.6),
                                                           (8.7, 62, 1.5, 0.55)), 0.22, -0.3)
    for t0, gan in ((8.0, 0.35), (8.8, 0.45), (9.3, 0.55), (9.6, 0.65), (9.8, 0.75)):
        poner(y, tambor_grave(g, f0=60.0, seg=0.8, tau=0.22), t0, 0.5 * gan, 0.0)
    poner(y, sonaja(1.0, g, crece=2.0), 8.97, 0.16, 0.35)
    poner(y, tambor_grave(g, f0=56.0, seg=1.3, tau=0.3), 9.97, 0.7, 0.0)  # golpe final: empieza la emboscada
    poner(y, tambor(150.0, 0.3, g, tau=0.07), 9.97, 0.35, 0.3)
    return sala(y, g, t60=1.4, mezcla=0.2, agudos=5000.0)


# --------------------------------------------------------------------------------------
# «El despertar de Nojoch Tuunich» (4 × 4 s)
# --------------------------------------------------------------------------------------

def fx_despertar():
    g = gen("cine_despertar_fx")
    y = lienzo("despertar")
    # --- Plano 1 (0–4 s): patio en silencio, aire grave, respiración lenta de piedra a lo lejos
    k = n_(4.3)
    poner(y, ruido_st(k, g, 45, 260, color=1.8, ancho=0.5) * rampa(k, 0.6) * salida(k, 0.5), 0.0, 0.035)
    lejos = np.zeros((2, n_(4.2)))
    for t0, dur, f_a, f_b, gan in ((0.45, 1.5, 170.0, 430.0, 0.8), (2.15, 1.75, 430.0, 150.0, 1.0)):  # inspira, espira
        j = n_(dur)
        v = np.arange(j) / j
        x = ruido_barrido(j, g, f_a * (f_b / f_a) ** v, ancho=0.7, color=1.5, f_min=90.0, f_max=1400.0, bandas=8)
        poner(lejos, x * campana_env(j, 0.9), t0, 0.5 * gan, 0.15)
    j = n_(1.75)
    poner(lejos, gemido(j, g, 47.0, ronco=1.2, tope=400.0) * campana_env(j, 1.2), 2.15, 0.22, 0.15)
    poner(y, sala(filtrar(lejos, 60, 1100), g, t60=2.2, mezcla=0.7, agudos=1500.0), 0.0, 0.055)
    # --- Plano 2 (4–8 s): grietas, el Silencio se cuela como un zumbido, latido magenta
    poner(y, crujidos(3.7, g, 110, crece=0.8, ancho=0.8), 4.0, 0.55)
    for t0, gan, p in ((4.25, 0.35, -0.5), (5.1, 0.5, 0.4), (5.9, 0.65, -0.3), (6.6, 0.8, 0.5), (7.2, 0.9, -0.1),
                       (7.65, 1.0, 0.2)):
        poner(y, chasquido(g, gan, grave=g.uniform(120.0, 170.0)), t0, 0.6, p)
        poner(y, polvo(0.6, g, tau=0.2), t0 + 0.03, 0.05 * gan)
        escombros(y, g, t0 + 0.05, t0 + 0.5, 5, lo=900, hi=3200, gan=0.16 * gan)
    k = n_(4.0)
    u = np.arange(k) / k
    z = zumbido(k, g, midi(50) * 2.0 ** (-2.0 * (1.0 - u) / 12.0), trem=(3.0, 8.0), brillo=0.5)
    poner(y, pan(z * u ** 1.7 * salida(k, 0.04), 0.5 * np.sin(DOS_PI * 0.35 * u * 4.0)), 4.0, 0.26)
    for t0, gan in ((5.0, 0.35), (6.0, 0.5), (7.0, 0.65), (7.6, 0.8)):
        poner(y, latido(g), t0, 0.45 * gan, 0.0)
    y[:, n_(4.0):n_(4.0) + k] += 0.1 * ruido_st(k, g, 40, 160, color=2.0, ancho=0.3) * u ** 1.5 * salida(k, 0.05)
    # --- Plano 3 (8–12 s): silencio breve, golpe tonal seco (9.0 s) y gemido grave de piedra
    k = n_(4.0)
    poner(y, ruido_st(k, g, 60, 500, color=1.8, ancho=0.5) * rampa(k, 0.3) * salida(k, 0.3), 8.0, 0.02)
    j = n_(2.4)
    v = np.arange(j) / j
    poner(y, gemido(j, g, 52.0 + 30.0 * np.sin(np.pi * v) ** 1.5) * np.sin(np.pi * v) ** 1.1, 9.5, 0.20, -0.1)
    poner(y, arrastre(2.4, g, hi=900.0) * np.sin(np.pi * v) ** 1.5, 9.5, 0.22, 0.2)
    j = n_(2.9)  # los ojos quedan encendidos: tono fino que bate
    tt = t_(j)
    ojos = np.sin(DOS_PI * 932.3 * tt) + np.sin(DOS_PI * 936.0 * tt + 0.4) + 0.5 * np.sin(DOS_PI * 1318.5 * tt)
    poner(y, ojos * env_perc(j, 1.4, 0.01), 9.02, 0.035, 0.0)
    escombros(y, g, 10.4, 11.9, 7, gan=0.10, graves=0.1)
    # --- Plano 4 (12–16 s): se pone en pie (arrastre de roca enorme, polvo) y pisada final en 15.0 s
    k = n_(2.8)
    u = np.arange(k) / k
    sube = (0.25 + 0.75 * u ** 1.2) * salida(k, 0.12)
    poner(y, pan(arrastre(2.8, g) * sube, -0.25 + 0.4 * u), 12.0, 1.0)
    j = n_(2.4)
    v = np.arange(j) / j
    poner(y, gemido(j, g, 50.0 * (96.0 / 50.0) ** v) * rampa(j, 0.3) * (0.4 + 0.6 * v) * salida(j, 0.15), 12.3, 0.20,
          0.1)
    poner(y, crujidos(2.7, g, 40, banda=(400.0, 2200.0), crece=0.6, ancho=0.8), 12.1, 0.36)
    escombros(y, g, 12.5, 14.8, 20, gan=0.14, graves=0.3)
    poner(y, polvo(2.6, g, tau=1.5), 12.2, 0.03)
    y = sala(y, g, t60=1.5, mezcla=0.22, agudos=5500.0)
    # Golpes secos (sin sala delante, con su propia cola): los ojos y la pisada
    ojo = saturar(impacto_piedra(g, 0.32, 98, 49, tau=0.06, brillo=1.2))
    j = len(ojo)
    ojo += 0.8 * (np.sin(DOS_PI * midi(38) * t_(j)) + 0.6 * np.sin(DOS_PI * midi(50) * t_(j))) * env_perc(j, 0.11, 0.003)
    ojo[:n_(0.25)] += 0.35 * campana(midi(74), 0.25, tau=0.06, parciales=PARC_CRISTAL)
    poner(y, ojo, 9.0, 0.85, 0.0)
    pisada = np.zeros((2, n_(2.5)))
    poner(pisada, saturar(impacto_piedra(g, 1.1, 125, 32, tau=0.28, brillo=1.0), 2.8), 0.0, 1.0, 0.0)
    poner(pisada, glis(62, 28, 1.0) * env_perc(n_(1.0), 0.34, 0.004), 0.0, 0.7, 0.0)
    escombros(pisada, g, 0.08, 1.4, 26, gan=0.36, graves=0.3)
    poner(pisada, polvo(1.9, g, tau=0.6), 0.1, 0.07)
    poner(y, saturar(reverb(pisada, g, t60=1.8, mezcla=0.3, agudos=5000.0), 3.0), 15.0, 2.3)
    return y


def mus_despertar():
    g = gen("cine_despertar_mus")
    y = lienzo("despertar")
    # Plano 1: casi nada. Re muy grave y una nota de ocarina que suspira, lejos
    for m, gan in ((38, 0.6), (45, 0.4)):
        poner(y, colchon_st(midi(m), 4.3, 1.8, 0.5), 0.0, 0.16 * gan)
    poner(y, flauta(midi(57), 1.7, g, vib=0.004, aire=0.14, ataque=0.25, rel=0.6, cae=1.0), 1.5, 0.22, -0.3)
    # Plano 2: pulso de tambor con los latidos, Re + Mi bemol que crece, sonaja trémula
    for t0, gan in ((4.0, 0.3), (5.0, 0.4), (6.0, 0.5), (7.0, 0.62), (7.6, 0.72)):
        poner(y, tambor_grave(g, f0=58.0, seg=0.9, tau=0.26), t0 + 0.02, 0.8 * gan, 0.0)
    k = n_(4.0)
    u = np.arange(k) / k
    for m, gan in ((50, 0.6), (51, 0.45), (38, 0.6)):
        poner(y, colchon_st(midi(m), 4.0, 2.5, 0.04) * u ** 1.2, 4.0, 0.25 * gan)
    poner(y, sonaja(2.0, g, granos=22.0, crece=1.6) * salida(n_(2.0), 0.03), 6.0, 0.10, 0.4)
    # Plano 3: corte a silencio; golpe con el del plano (9.0 s); después, colchón grave que crece
    poner(y, tambor_grave(g, f0=52.0, seg=1.4, tau=0.36), 9.0, 0.85, 0.0)
    poner(y, cuerno(midi(38), 0.55, g, ataque=0.02, rel=0.3), 9.0, 0.32, 0.0)
    for m, gan in ((38, 0.6), (45, 0.45), (48, 0.3)):
        poner(y, colchon_st(midi(m), 2.9, 1.6, 0.5), 9.5, 0.13 * gan)
    # Plano 4: tambores que se aprietan, caracol que crece y, en la pisada, el tema del guardián
    for t0, gan in ((12.0, 0.4), (12.75, 0.45), (13.5, 0.52), (14.0, 0.58), (14.4, 0.66), (14.7, 0.74), (14.86, 0.8)):
        poner(y, tambor_grave(g, f0=60.0, seg=0.8, tau=0.22), t0, 0.55 * gan, -0.1 if t0 < 14.0 else 0.1)
    k = n_(2.75)
    poner(y, cuerno(midi(38), 2.75, g, ataque=0.8, rel=0.1) * (0.3 + 0.7 * (np.arange(k) / k) ** 1.5), 12.2, 0.26, 0.2)
    # (en 15.0 s no hay tambor: el golpe es la pisada de la pista de efectos; aquí entra la trompa)
    pulso = 0.32  # La–Re–Fa: corta, corta, larga (primera mitad del motivo, en trompa grave)
    for (ini, dur), m in list(zip(RITMO_MOTIVO, MOTIVO_MENOR))[:3]:
        larga = dur == 2
        seg = 1.75 if larga else pulso * 1.08
        poner(y, trompa(midi(m - 12), seg, g, ataque=0.05, rel=0.9 if larga else 0.1), 15.0 + ini * pulso,
              0.48 if larga else 0.40, -0.1)
        poner(y, trompa(midi(m - 24), seg, g, ataque=0.06, rel=0.9 if larga else 0.1), 15.0 + ini * pulso, 0.22, 0.15)
    poner(y, tambor_grave(g, f0=54.0, seg=1.3, tau=0.34), 15.0 + 2 * pulso, 0.5, 0.0)
    for m, gan in ((38, 0.6), (50, 0.5), (57, 0.4), (65, 0.3)):
        poner(y, colchon_st(midi(m), 2.4, 0.5, 1.2), 15.05, 0.12 * gan)
    return sala(y, g, t60=1.6, mezcla=0.2, agudos=4500.0)


# --------------------------------------------------------------------------------------
# «La liberación de Nojoch Tuunich» (3 × 4 s)
# --------------------------------------------------------------------------------------

def fx_liberacion():
    g = gen("cine_liberacion_fx")
    y = lienzo("liberacion")
    # --- Plano 1 (0–4 s): el zumbido se deshace en motas; las grietas se apagan una a una
    k = n_(3.3)
    u = np.arange(k) / k
    z = zumbido(k, g, midi(50) * 2.0 ** (-3.0 * u / 12.0), trem=(8.0, 2.5))
    z *= np.clip(1.0 + 1.2 * lento(k, g, 8.0, 30.0) - 2.6 * u, 0.0, 1.0)  # se rompe en granos
    poner(y, pan(z * rampa(k, 0.03) * (1.0 - u) ** 0.8, 0.4 * np.sin(DOS_PI * 0.4 * u * 3.3)), 0.0, 0.5)
    for _ in range(80):  # motas: cada vez más agudas y más abiertas
        v = g.uniform() ** 0.7
        f = 2200.0 * 2.0 ** (1.6 * v) * g.uniform(0.85, 1.2)
        x = np.sin(DOS_PI * f * t_(n_(0.09))) * env_perc(n_(0.09), 0.016, 0.002)
        poner(y, x, 0.25 + 3.7 * v, 0.07 * g.uniform(0.3, 1.0), g.uniform(-1.0, 1.0) * (0.3 + 0.7 * v))
    campanillas = (81, 84, 86, 89, 93)  # La Do Re Fa La
    for i, (t0, p) in enumerate(((0.45, -0.6), (1.15, 0.5), (1.85, -0.3), (2.55, 0.35), (3.25, 0.0))):
        w = i / 4.0  # de crujido a campanilla
        poner(y, chasquido(g, 1.0, grave=g.uniform(120.0, 160.0)), t0, 0.6 * (1.0 - w) ** 1.2, p)
        poner(y, crujidos(0.3, g, 8), t0, 0.35 * (1.0 - w), p)
        poner(y, campana(midi(campanillas[i]), 1.5, tau=0.5, ataque=0.004), t0, 0.5 * (0.2 + 0.8 * w), p)
    # --- Plano 2 (4–8 s): aire limpio, la voz de piedra en calma, la selva vuelve a oírse
    k = n_(4.6)
    poner(y, ruido_st(k, g, 700, 5000, color=1.3, ancho=0.7) * campana_env(k, 0.8)
          * np.clip(1.0 + 0.3 * lento(k, g, 0.3, 2.0), 0.3, None), 3.7, 0.035)
    j = n_(2.6)
    v = np.arange(j) / j
    voz = gemido(j, g, 98.0 * (82.0 / 98.0) ** v + 6.0 * np.sin(np.pi * v), ronco=0.9, tope=800.0)
    poner(y, voz * campana_env(j, 0.8), 4.9, 0.14, 0.0)
    poner(y, np.sin(DOS_PI * 147.0 * t_(j) + 0.3) * campana_env(j, 1.5), 4.9, 0.05, 0.0)
    ave = np.zeros(n_(0.8))
    poner(ave, silbo(1700, 1750, 0.15), 0.0, 0.9)
    poner(ave, silbo(2150, 2080, 0.24), 0.21, 1.0)
    poner(y, sala(pan(filtrar(ave, 400, 3500), 0.6), g, t60=1.8, mezcla=0.8, agudos=3500.0), 6.9, 0.07)
    # --- Plano 3 (8–12 s): la Pluma de Jade: destello vítreo, brillo que flota, cola larga
    for m, gan, p in ((86, 1.0, 0.0), (93, 0.7, -0.4), (98, 0.5, 0.4)):
        poner(y, campana(midi(m), 1.8, tau=0.55, ataque=0.003, parciales=PARC_CRISTAL), 8.15, 0.34 * gan, p)
    j = n_(0.6)
    v = np.arange(j) / j
    x = ruido_barrido(j, g, 2000.0 * (7000.0 / 2000.0) ** v, ancho=0.5, color=0.5, f_min=1200.0, f_max=9000.0,
                      bandas=10) * campana_env(j, 1.5)
    poner(y, pan(x, 0.0), 7.95, 0.16)
    for _ in range(50):
        v = g.uniform() ** 1.6
        f = 3000.0 * (7500.0 / 3000.0) ** g.uniform()
        x = np.sin(DOS_PI * f * t_(n_(0.08))) * env_perc(n_(0.08), 0.014, 0.001)
        poner(y, x, 8.2 + 3.4 * v, 0.07 * g.uniform(0.3, 1.0) * (1.0 - 0.6 * v), g.uniform(-0.9, 0.9))
    j = n_(3.2)  # el aire de la pluma, que flota hacia el grupo
    v = np.arange(j) / j
    x = ruido_barrido(j, g, 900.0 + 1600.0 * np.sin(np.pi * v) ** 1.2, ancho=0.6, color=1.0, f_min=500.0,
                      f_max=5000.0, bandas=10) * campana_env(j, 1.0)
    poner(y, pan(x, -0.5 + 0.7 * v), 8.3, 0.07)
    poner(y, campana(midi(93), 1.6, tau=0.6, ataque=0.006), 11.0, 0.14, 0.2)
    return sala(y, g, t60=2.0, mezcla=0.28, agudos=6500.0)


def mus_liberacion():
    g = gen("cine_liberacion_mus")
    y = lienzo("liberacion")
    # Plano 1: el Re menor se disuelve
    for m, gan in ((38, 0.5), (50, 0.6), (57, 0.5)):
        poner(y, colchon_st(midi(m), 4.2, 0.4, 3.0), 0.0, 0.15 * gan)
    notas(y, g, lambda f, d: kalimba(f, d, g, brillo=0.7), ((0.8, 62, 1.6, 0.7), (2.2, 65, 1.6, 0.7)), 0.22, 0.3)
    poner(y, flauta(midi(72), 1.2, g, ataque=0.3, rel=0.4), 3.1, 0.14, -0.2)
    # Plano 2: Fa mayor (el relativo): tono cálido y una frase de flauta de barro que sube
    for m, gan in ((41, 0.6), (48, 0.6), (53, 0.7), (57, 0.6), (60, 0.35)):
        poner(y, colchon_st(midi(m), 5.6, 1.4, 1.4), 3.6, 0.15 * gan)
    notas(y, g, lambda f, d: flauta(f, d, g, ataque=0.12, rel=0.25), ((4.4, 69, 1.25, 0.85), (5.6, 72, 1.05, 0.9),
                                                                    (6.6, 77, 1.7, 1.0)), 0.30, -0.15)
    # Plano 3: arpegio luminoso y el motivo del guardián en mayor; cola larga y esperanzada
    poner(y, tambor_grave(g, f0=65.0, seg=1.0, tau=0.3, gan_piel=0.2), 8.3, 0.3, 0.0)
    for i, m in enumerate((65, 69, 72, 74, 77, 81, 84)):
        t0 = 8.3 + 0.17 * i
        p = -0.6 + 0.2 * i
        poner(y, kalimba(midi(m), 1.6, g), t0, 0.34, p)
        poner(y, campana(midi(m), 1.6, tau=0.5, ataque=0.004), t0, 0.14, p)
    pulso = 0.3
    for (ini, dur), m in zip(RITMO_MOTIVO, MOTIVO_MAYOR):
        t0 = 9.75 + ini * pulso
        ultima = ini == RITMO_MOTIVO[-1][0]
        poner(y, kalimba(midi(m), max(0.6, 2.5 * dur * pulso), g), t0, 0.36 * (1.0 if dur == 2 else 0.8), 0.2)
        poner(y, campana(midi(m), 2.0 if ultima else max(0.4, 1.6 * dur * pulso), tau=0.7 if ultima else 0.12 + 0.1 * dur,
                         ataque=0.004), t0, 0.17, 0.2)
    for m, gan in ((41, 0.6), (53, 0.7), (60, 0.6), (65, 0.5), (69, 0.4)):
        poner(y, colchon_st(midi(m), 5.3, 1.2, 2.6), 8.1, 0.15 * gan)
    poner(y, flauta(midi(84), 2.2, g, vib=0.004, aire=0.1, ataque=0.5, rel=1.3), 11.2, 0.13, -0.3)
    return sala(y, g, t60=2.2, mezcla=0.26, agudos=6000.0)


# --------------------------------------------------------------------------------------
# «El llamado» (5 + 4.5 + 5 + 4.5 s)
# --------------------------------------------------------------------------------------

def fx_llamado():
    g = gen("cine_llamado_fx")
    y = lienzo("llamado")
    # --- Plano 1 (0–5 s): la selva desde arriba, callada: solo viento, y un ave sola sin respuesta
    k = n_(5.6)
    u = np.arange(k) / k
    tt = t_(k)  # dos ráfagas lentas (periodos de 5.2 y 2.3 s), no un vaivén rápido
    fuerza = 0.65 + 0.25 * np.sin(DOS_PI * tt / 5.2 + g.uniform(0, DOS_PI)) + 0.12 * np.sin(DOS_PI * tt / 2.3 + g.uniform(0, DOS_PI))
    fuerza = fuerza * rampa(k, 0.8) * salida(k, 1.2)
    for c in range(2):
        v = ruido_barrido(k, g, 300.0 * 2.0 ** (1.1 * np.clip(fuerza, 0.0, 1.3)), ancho=0.9, color=1.5, f_min=90.0,
                          f_max=3000.0, bandas=10)
        y[c, :k] += 0.20 * v * fuerza ** 1.3
    y[:, :k] += 0.045 * ruido_st(k, g, 1800, 6000, color=1.0, ancho=0.7) * fuerza ** 2 * tirones(k, g, 1.0, 6.0, 1.0)
    ave = np.zeros(n_(1.2))
    for i in range(3):  # una llamada en eco… que nadie contesta
        poner(ave, silbo(1380, 1300, 0.22, 0.6), 0.34 * i, 0.6 ** i)
    poner(y, sala(pan(filtrar(ave, 400, 3200), -0.5), g, t60=2.0, mezcla=0.9, agudos=3200.0), 1.5, 0.10)
    # --- Plano 2 (5–9.5 s): el cenote oscuro: aire de caverna, agua quieta, tres gotas con eco
    k = n_(5.0)
    env = rampa(k, 0.7) * salida(k, 0.8)
    poner(y, ruido_st(k, g, 60, 350, color=1.7, ancho=0.5) * env, 4.8, 0.07)
    poner(y, ruido_st(k, g, 160, 520, orden=4, color=1.5, ancho=0.6) * env
          * np.clip(0.5 + 0.5 * lento(k, g, 0.2, 0.7), 0.05, None) ** 1.3, 4.8, 0.05)
    tt = t_(k)
    oscuro = np.sin(DOS_PI * 55.0 * tt) + 0.7 * np.sin(DOS_PI * 55.6 * tt + 1.0) + 0.3 * np.sin(DOS_PI * 110.4 * tt)
    poner(y, oscuro * env, 4.8, 0.03, 0.0)
    gotas = np.zeros((2, n_(8.5)))
    for t0, f, p, gan in ((0.75, 880.0, -0.4, 0.9), (2.15, 660.0, 0.45, 1.0), (3.55, 990.0, 0.1, 0.8)):
        x = gota(g, f)
        poner(gotas, x, t0, gan, p)
        poner(gotas, filtrar(x, 200, 2500), t0 + 0.22, 0.3 * gan, -p)
        poner(gotas, filtrar(x, 200, 2000), t0 + 0.47, 0.14 * gan, 0.5 * p)
    poner(y, reverb(gotas, g, t60=3.2, mezcla=0.9, agudos=3800.0, graves=150.0, retardo=0.03, cola_agudos=0.8)
          [:, :n_(8.5)], 5.0, 0.62)
    # --- Plano 3 (9.5–14.5 s): el santuario sellado: el zumbido del sello y tres pulsos
    k = n_(5.1)
    u = np.arange(k) / k
    z = zumbido(k, g, midi(38) * (1.0 + 0.02 * np.sin(DOS_PI * 0.3 * u * 5.1)), trem=(2.5, 4.5), brillo=0.5)
    poner(y, pan(z * campana_env(k, 0.6), 0.35 * np.sin(DOS_PI * 0.2 * u * 5.1)), 9.45, 0.17)
    poner(y, ruido_st(k, g, 40, 130, color=2.0, ancho=0.3) * campana_env(k, 0.8), 9.45, 0.10)
    for t0, gan in ((10.6, 0.6), (12.2, 0.8), (13.6, 1.0)):
        poner(y, latido(g, m=74, cristal=0.35), t0, 0.5 * gan, 0.0)
        poner(y, campana(midi(80), 0.9, tau=0.22, ataque=0.004, parciales=PARC_CRISTAL), t0, 0.12 * gan, 0.4)  # tritono
        destellos(y, g, t0, t0 + 0.5, 6, 2500.0, 6000.0, 0.05 * gan)
    j = n_(0.5)
    poner(y, ruido(j, g, 250, 2000, color=1.0) * tirones(j, g, 12.0, 40.0) * campana_env(j, 0.8), 11.4, 0.07, -0.5)
    # --- Plano 4 (14.5–19 s): hojas, la voz de Chiich Yaxché (se suma al final) y la llamada
    k = n_(5.6)
    hojas = ruido_st(k, g, 1500, 6500, color=1.0, ancho=0.7) * rampa(k, 0.6) * salida(k, 1.5)
    poner(y, hojas * np.clip(0.4 + 0.5 * lento(k, g, 0.3, 2.0), 0.05, None) ** 1.5 * tirones(k, g, 1.5, 8.0, 1.0),
          14.3, 0.05)
    poner(y, ruido_st(k, g, 120, 700, color=1.3, ancho=0.5) * rampa(k, 0.6) * salida(k, 1.5), 14.3, 0.045)
    _gastar_voz_anterior(g)  # la voz ya no sale de este generador: ver `voz_chiich`
    for t0, f, gan in ((18.35, 294.0, 0.8), (18.58, 392.0, 1.0)):  # toc-toc de madera hueca: despierta
        poner(y, madera(g, f=f), t0, 0.8 * gan, 0.1)
    for i, m in enumerate((86, 89, 93)):  # y algo se enciende
        poner(y, campana(midi(m), 1.6, tau=0.5, ataque=0.004), 18.72 + 0.09 * i, 0.16, -0.2 + 0.25 * i)
    destellos(y, g, 18.7, 19.6, 14, 3000.0, 7000.0, 0.05)
    y = sala(y, g, t60=1.5, mezcla=0.2, agudos=6000.0)
    # La voz de Chiich Yaxché, elegida de oído: primera frase 14.80–16.50 s, segunda 16.90–18.56 s
    poner(y, voz_chiich(), 14.5)
    return y


def mus_llamado():
    g = gen("cine_llamado_mus")
    y = lienzo("llamado")

    def kal(f, d):
        return kalimba(f, d, g)

    def fla(f, d):
        return flauta(f, d, g, ataque=0.12, rel=0.25)

    # Plano 1: tono de cuento. Kalimba que abre, colchón de Re y ocarina que baja (la selva no canta)
    for m, gan in ((50, 0.6), (57, 0.5), (38, 0.4)):
        poner(y, colchon_st(midi(m), 5.4, 1.2, 1.2), 0.0, 0.15 * gan)
    notas(y, g, kal, ((0.30, 62, 1.6, 0.8), (0.75, 69, 1.6, 0.85), (1.20, 74, 2.0, 1.0), (2.10, 72, 1.6, 0.8),
                      (2.55, 69, 1.6, 0.75), (3.40, 65, 1.6, 0.7), (3.85, 67, 1.6, 0.7), (4.30, 69, 1.8, 0.75)), 0.34, 0.25)
    notas(y, g, fla, ((2.0, 69, 1.2, 0.9), (3.25, 67, 0.85, 0.85), (4.15, 65, 1.15, 0.8)), 0.24, -0.25)
    # Plano 2: más oscuro. Re grave con Fa, kalimba baja y una flauta grave que suspira
    for m, gan in ((38, 0.6), (53, 0.4), (45, 0.4)):
        poner(y, colchon_st(midi(m), 4.9, 1.2, 1.2), 4.9, 0.15 * gan)
    notas(y, g, lambda f, d: kalimba(f, d, g, brillo=0.6), ((5.4, 62, 1.8, 0.7), (6.2, 65, 1.8, 0.65), (7.0, 62, 1.8, 0.6),
                                                           (7.9, 60, 2.0, 0.6)), 0.30, 0.2)
    poner(y, flauta(midi(62), 2.5, g, vib=0.004, aire=0.12, ataque=0.3, rel=0.8, cae=2.0), 6.5, 0.2, -0.3)
    # Plano 3: el sello. Tambor grave lento, Re–La–Do que crece, sonaja trémula, caracol muy bajo
    for t0, gan in ((9.6, 0.5), (10.9, 0.55), (12.2, 0.62), (13.3, 0.7), (14.0, 0.75)):
        poner(y, tambor_grave(g, f0=58.0, seg=1.2, tau=0.32), t0, 0.5 * gan, 0.0)
    k = n_(5.0)
    u = np.arange(k) / k
    for m, gan in ((38, 0.6), (45, 0.5), (48, 0.4)):
        poner(y, colchon_st(midi(m), 5.0, 2.0, 0.6) * (0.4 + 0.6 * u), 9.5, 0.15 * gan)
    poner(y, sonaja(1.9, g, granos=20.0, crece=1.2), 12.5, 0.08, 0.4)
    j = n_(3.3)
    poner(y, cuerno(midi(38), 3.3, g, ataque=1.2, rel=0.6) * (0.4 + 0.6 * (np.arange(j) / j)), 11.0, 0.17, 0.2)
    # Plano 4: calidez. Fa–La–Do sobre Re, flauta que sube, arpegio de kalimba y tambor de mano
    for m, gan in ((50, 0.5), (53, 0.6), (57, 0.6), (60, 0.5)):
        poner(y, colchon_st(midi(m), 5.6, 0.9, 2.2), 14.4, 0.15 * gan)
    notas(y, g, fla, ((15.0, 69, 0.75, 0.85), (15.75, 72, 0.75, 0.9), (16.5, 74, 0.95, 0.95), (17.5, 77, 1.9, 1.0)),
          0.28, -0.2)
    notas(y, g, kal, [(16.0 + 0.3 * i, m, 1.6, 0.75) for i, m in enumerate((62, 65, 69, 72, 74))] +
          [(18.9, 74, 2.0, 0.8), (18.9, 69, 2.0, 0.6)], 0.32, 0.3)
    for t0, f, gan in ((17.0, 110.0, 0.7), (17.4, 147.0, 0.5), (17.8, 110.0, 0.6), (18.2, 147.0, 0.5),
                       (18.6, 110.0, 0.7)):
        poner(y, tambor(f, 0.5, g, tau=0.14), t0, 0.22 * gan, -0.1)
    return sala(y, g, t60=1.8, mezcla=0.24, agudos=5500.0)


# --------------------------------------------------------------------------------------
# Tabla de pistas y guion (lo que el juego enseña en cada plano y lo que suena)
# --------------------------------------------------------------------------------------

CINES = {
    "sello": (fx_sello, mus_sello),
    "despertar": (fx_despertar, mus_despertar),
    "liberacion": (fx_liberacion, mus_liberacion),
    "llamado": (fx_llamado, mus_llamado),
}
IDS = list(CINES)


def pistas_de(cine: str):
    """(id de pista, función, es música)."""
    fx, mus = CINES[cine]
    return ((f"cine_{cine}_fx", fx, False), (f"cine_{cine}_mus", mus, True))


def _tramo_db(x, a, b, lo=None, hi=None):
    """RMS en dB del tramo [a, b] s (suma de canales), opcionalmente en una banda."""
    s = x[:, n_(a):n_(b)]
    if lo or hi:
        s = filtrar(s, lo, hi, orden=4)
    return db(rms(s))


def _pico_en(x, a, b):
    """Segundo en el que cae el máximo absoluto dentro de [a, b]."""
    s = np.max(np.abs(x[:, n_(a):n_(b)]), axis=0)
    return a + float(np.argmax(s)) / SR


def _mas_fuerte(x, ventana):
    """Segundo en el que empieza la ventana con más energía de toda la pista."""
    v = n_(ventana)
    ac = np.concatenate([[0.0], np.cumsum(np.sum(x ** 2, axis=0))])
    return float(np.argmax(ac[v:] - ac[:-v])) / SR


# Hitos: comprobaciones de que cada evento cae en su plano. (cinemática, pista, qué, prueba)
HITOS = (
    ("sello", "fx", "el estallido vítreo (agudos) está en 5.0–5.5 s, no antes",
     lambda x: _tramo_db(x, 5.0, 5.5, 3000) > _tramo_db(x, 3.0, 4.9, 3000) + 6.0),
    ("sello", "fx", "el pico del plano 2 cae entre 4.9 y 7.0 s (grieta, estallido o tope de la losa)",
     lambda x: 4.9 <= _pico_en(x, 3.0, 7.0) <= 7.0),
    ("sello", "fx", "plano 3: calma en 7.2–7.8 s, al menos 10 dB por debajo del plano 2",
     lambda x: _tramo_db(x, 7.2, 7.8) < _tramo_db(x, 4.9, 6.9) - 10.0),
    ("sello", "fx", "el aviso crece: 9.5–10.0 s supera en 8 dB a 7.2–7.8 s",
     lambda x: _tramo_db(x, 9.5, 10.0) > _tramo_db(x, 7.2, 7.8) + 8.0),
    ("sello", "mus", "termina con tensión: el último segundo no es el más flojo",
     lambda x: _tramo_db(x, 9.0, 10.1) > _tramo_db(x, 7.2, 8.0) + 3.0),
    ("despertar", "fx", "plano 1 en calma: 20 dB o más por debajo de la pisada",
     lambda x: _tramo_db(x, 0.3, 3.8) < _tramo_db(x, 15.0, 15.6) - 20.0),
    ("despertar", "fx", "las grietas crecen: 6.5–8.0 s supera a 4.0–5.0 s",
     lambda x: _tramo_db(x, 6.5, 8.0) > _tramo_db(x, 4.0, 5.0) + 3.0),
    ("despertar", "fx", "silencio breve en 8.15–8.95 s: 15 dB por debajo del final del plano 2",
     lambda x: _tramo_db(x, 8.15, 8.95) < _tramo_db(x, 7.0, 8.0) - 15.0),
    ("despertar", "fx", "el golpe seco de los ojos cae en 9.0 s (±0.06)",
     lambda x: abs(_pico_en(x, 8.1, 9.6) - 9.0) <= 0.06),
    ("despertar", "fx", "la pisada final (15.0 s) es el tramo de 0.4 s con más energía de toda la pista",
     lambda x: 14.9 <= _mas_fuerte(x, 0.4) <= 15.15),
    ("despertar", "mus", "el tema (trompa) entra en 15.0 s: 15.0–16.5 s supera en 6 dB a 12.0–14.0 s en 80–400 Hz",
     lambda x: _tramo_db(x, 15.0, 16.5, 80, 400) > _tramo_db(x, 12.0, 14.0, 80, 400) + 6.0),
    ("liberacion", "fx", "el zumbido grave se va: 2.8–4.0 s queda 8 dB por debajo de 0–1.2 s en 50–600 Hz",
     lambda x: _tramo_db(x, 2.8, 4.0, 50, 600) < _tramo_db(x, 0.0, 1.2, 50, 600) - 8.0),
    ("liberacion", "fx", "la voz de piedra (50–300 Hz) está en el plano 2: 5.2–7.2 s supera a 3.0–4.0 s",
     lambda x: _tramo_db(x, 5.2, 7.2, 50, 300) > _tramo_db(x, 3.0, 4.0, 50, 300) + 6.0),
    ("liberacion", "fx", "el destello de la pluma (agudos) cae en 8.0–8.6 s",
     lambda x: _tramo_db(x, 8.0, 8.6, 3000) > _tramo_db(x, 6.5, 7.8, 3000) + 6.0),
    ("liberacion", "mus", "el arpegio empieza en el plano 3: el pico de 7.5–9.6 s cae después de 8.28 s",
     lambda x: _pico_en(x, 7.5, 9.6) >= 8.28),
    ("liberacion", "mus", "cola larga: aún suena entre 12.0 y 13.0 s",
     lambda x: _tramo_db(x, 12.0, 13.0) > -50.0),
    ("llamado", "fx", "las gotas del cenote (600–2500 Hz) están en el plano 2",
     lambda x: _tramo_db(x, 5.6, 9.3, 600, 2500) > _tramo_db(x, 10.0, 14.0, 600, 2500) + 3.0),
    ("llamado", "fx", "el zumbido del sello (60–250 Hz) está en el plano 3",
     lambda x: _tramo_db(x, 10.0, 14.0, 60, 250) > _tramo_db(x, 15.0, 18.0, 60, 250) + 6.0),
    ("llamado", "fx", "la voz de árbol (200–1500 Hz) está en el plano 4",
     lambda x: _tramo_db(x, 14.8, 18.2, 200, 1500) > _tramo_db(x, 10.0, 14.0, 200, 1500) + 6.0),
    ("llamado", "fx", "la llamada de madera cae en 18.3–18.7 s",
     lambda x: 18.3 <= _pico_en(x, 18.25, 19.0) <= 18.7),
)


# --------------------------------------------------------------------------------------
# Acabado, escritura y comprobación
# --------------------------------------------------------------------------------------

def acabar(x, seg, lufs_obj, techo_db, agudos):
    """Recorta a la duración, filtra, funde los extremos, ajusta la sonoridad y limita."""
    n = n_(seg)
    x = np.concatenate([x, np.zeros((2, max(0, n - x.shape[-1])))], axis=-1)[:, :n]
    x = filtrar(x, 30.0, None, orden=2)
    x = filtrar(x, None, agudos, orden=4)
    ventana = rampa(n, 0.004) * salida(n, 0.5)
    ventana[0] = 0.0
    x = x * ventana
    x = x - ventana * (np.sum(x, axis=-1, keepdims=True) / np.sum(ventana))  # sin continua y con extremos en cero
    for _ in range(4):
        x = x * lin(lufs_obj - lufs(x))
        x = limitar(x, lin(techo_db))
    return x


def codificar(nombre, x, tmp, lufs_obj, pico_max):
    """Escribe el WAV intermedio y el MP3; corrige nivel y pico midiendo el MP3. Devuelve (x, medida)."""
    wav, mp3 = tmp / f"{nombre}.wav", SALIDA / f"{nombre}.mp3"
    for _ in range(5):
        escribir_wav(wav, x)
        codificar_mp3(wav, mp3, CALIDAD)
        m = medir(mp3)
        falta = lufs_obj - m["lufs"]
        sobra = m["peak_db"] - pico_max
        if abs(falta) <= 0.3 and sobra <= 0.0:
            break
        x = x * lin(falta)
        techo = db(np.max(np.abs(x))) - max(sobra, 0.0) - (0.2 if sobra > 0 else 0.0)
        x = limitar(x, lin(min(techo, pico_max - 0.6)))
    return x, m


def planos_de_story_def() -> dict:
    """Lee de story_def.gd la duración de los planos de cada cinemática."""
    planos, actual, dentro = {}, None, False
    for linea in STORY_DEF.read_text(encoding="utf-8").splitlines():
        if linea.startswith("const CUTSCENES"):
            dentro = True
            continue
        if not dentro:
            continue
        if linea.startswith("}"):
            break
        m = re.match(r'^\t"(\w+)": \{', linea)
        if m:
            actual = m.group(1)
            planos[actual] = []
        m = re.search(r'\{"dur": ([\d.]+)', linea)
        if m and actual:
            planos[actual].append(float(m.group(1)))
    return planos


def generar(ids, tmp: Path, dir_esp: Path | None) -> None:
    SALIDA.mkdir(parents=True, exist_ok=True)
    ruta_json = SALIDA / "cine.json"
    previo = json.loads(ruta_json.read_text(encoding="utf-8")) if ruta_json.exists() else {}
    pistas = previo.get("tracks", {})
    for cine in ids:
        seg = total(cine) + COLA
        (id_fx, fn_fx, _), (id_mus, fn_mus, _) = pistas_de(cine)
        fx = acabar(fn_fx(), seg, FX_LUFS[2], FX_TECHO, 14000.0)
        crudo_mus = fn_mus()
        techo_mus = MUS_TECHO
        for _ in range(4):
            mus = acabar(crudo_mus, seg, MUS_LUFS[2], techo_mus, 12000.0)
            fx, m_fx = codificar(id_fx, fx, tmp, FX_LUFS[2], FX_PICO_MAX - 0.6)
            mus, m_mus = codificar(id_mus, mus, tmp, MUS_LUFS[2], techo_mus + 1.5)
            n = min(m_fx["x"].shape[-1], m_mus["x"].shape[-1])
            suma = db(np.max(np.abs(m_fx["x"][:, :n] + m_mus["x"][:, :n])))
            if suma <= SUMA_PICO_MAX - 0.3:
                break
            techo_mus -= max(1.0, suma - (SUMA_PICO_MAX - 0.3) + 0.5)  # la música cede sitio a los efectos
        for nombre, m, bus in ((id_fx, m_fx, "Cinematics"), (id_mus, m_mus, "Music")):
            pistas[nombre] = {"file": f"{nombre}.mp3", "bus": bus, "loop": None, "seconds": round(m["seconds"], 3),
                              "bytes": m["bytes"], "lufs": round(m["lufs"], 1), "peak_db": round(m["peak_db"], 1)}
            print(f"  {nombre}: {m['seconds']:.2f} s, {m['bytes']} bytes, {m['lufs']:.1f} LUFS, pico {m['peak_db']:.1f} dBFS")
            if dir_esp is not None:
                dir_esp.mkdir(parents=True, exist_ok=True)
                espectrograma(SALIDA / f"{nombre}.mp3", dir_esp / f"{nombre}.png")
        print(f"  {cine}: efectos + música, pico de la suma {suma:.1f} dBFS")
    orden = [p[0] for c in IDS for p in pistas_de(c)]
    escribir_json(ruta_json, {
        "version": 1,
        "tracks": {k: pistas[k] for k in orden if k in pistas},
        "cutscenes": {c: {"fx": f"cine_{c}_fx", "mus": f"cine_{c}_mus", "seconds": total(c), "shots": inicios(c)}
                      for c in IDS if f"cine_{c}_fx" in pistas and f"cine_{c}_mus" in pistas},
    })
    actualizar_manifiesto("cinemática", [
        {"id": nombre, "archivo": f"game/web/static/audio/{nombre}.mp3", "tipo": "cinemática",
         "bus": pistas[nombre]["bus"], "duracion_s": pistas[nombre]["seconds"], "bytes": pistas[nombre]["bytes"],
         "origen": f"síntesis propia: art/audio/gen_cine.py, función {fn.__name__}",
         "licencia": LICENCIA, "semilla": semilla_de(nombre)}
        for c in IDS for nombre, fn, _ in pistas_de(c) if nombre in pistas])


def comprobar() -> int:
    """Mide los MP3 en disco y devuelve el número de fallos."""
    ruta_json = SALIDA / "cine.json"
    if not ruta_json.exists():
        print("FALTA cine.json")
        return 1
    datos = json.loads(ruta_json.read_text(encoding="utf-8"))
    pistas, escenas = datos.get("tracks", {}), datos.get("cutscenes", {})
    fallos_tot = 0
    reales = planos_de_story_def()
    for cine in IDS:
        if [round(v, 3) for v in reales.get(cine, [])] != [round(v, 3) for v in PLANOS[cine]]:
            print(f"FALLO: los planos de «{cine}» en story_def.gd son {reales.get(cine)}, aquí {PLANOS[cine]}")
            fallos_tot += 1
    total_bytes = 0
    print(f"{'archivo':<22}{'seg':>7}{'bytes':>8}{'LUFS':>7}{'pico':>7}{'I·D':>6}{'DC':>9}  <200 -1k -4k -8k >8k  resultado")
    for cine in IDS:
        dec = {}
        for nombre, _fn, es_mus in pistas_de(cine):
            mp3 = SALIDA / f"{nombre}.mp3"
            if not mp3.exists() or nombre not in pistas:
                print(f"{nombre:<22} FALTA")
                fallos_tot += 1
                continue
            p = pistas[nombre]
            m = medir(mp3)
            x = m["x"]
            dec["mus" if es_mus else "fx"] = (x, m)
            total_bytes += m["bytes"]
            fallos = []
            rango = MUS_LUFS if es_mus else FX_LUFS
            if abs(m["seconds"] - (total(cine) + COLA)) > 0.03:
                fallos.append(f"duración≠{total(cine) + COLA:.1f}")
            if not rango[0] <= m["lufs"] <= rango[1]:
                fallos.append("LUFS fuera de rango")
            if m["peak_db"] > FX_PICO_MAX:
                fallos.append(f"pico>{FX_PICO_MAX:.0f} dBFS")
            if m["dc"] > 5e-4:
                fallos.append("continua")
            if m["corr"] < 0.0:
                fallos.append("mal en mono")
            if m["bandas"][4] > 20.0:
                fallos.append("mucho >8 kHz")
            borde = n_(0.02)
            if db(np.max(np.abs(x[:, :n_(0.001)]))) > -40.0 or db(np.max(np.abs(x[:, -borde:]))) > -50.0:
                fallos.append("extremos≠silencio")
            if (p["file"] != mp3.name or p["bus"] != ("Music" if es_mus else "Cinematics") or p["loop"] is not None
                    or p["bytes"] != m["bytes"] or abs(p["seconds"] - m["seconds"]) > 0.01
                    or abs(p["lufs"] - m["lufs"]) > 0.15 or abs(p["peak_db"] - m["peak_db"]) > 0.15):
                fallos.append("manifiesto desfasado")
            fallos_tot += len(fallos)
            b = m["bandas"]
            print(f"{nombre:<22}{m['seconds']:>7.2f}{m['bytes']:>8}{m['lufs']:>7.1f}{m['peak_db']:>7.1f}{m['corr']:>6.2f}"
                  f"{m['dc']:>9.5f}  {b[0]:>4.0f}{b[1]:>4.0f}{b[2]:>4.0f}{b[3]:>4.0f}{b[4]:>4.0f}  "
                  f"{', '.join(fallos) if fallos else 'ok'}")
        if len(dec) == 2:
            (fx, m_fx), (mus, m_mus) = dec["fx"], dec["mus"]
            n = min(fx.shape[-1], mus.shape[-1])
            suma = db(np.max(np.abs(fx[:, :n] + mus[:, :n])))
            notas_ = []
            if suma > SUMA_PICO_MAX:
                notas_.append(f"la suma pasa de {SUMA_PICO_MAX:.0f} dBFS")
            if m_mus["lufs"] >= m_fx["lufs"]:
                notas_.append("la música no va por debajo de los efectos")
            e = escenas.get(cine, {})
            if (e.get("fx") != f"cine_{cine}_fx" or e.get("mus") != f"cine_{cine}_mus"
                    or abs(e.get("seconds", -1) - total(cine)) > 1e-6 or e.get("shots") != inicios(cine)):
                notas_.append("entrada «cutscenes» incorrecta")
            for c, pista, que, prueba in HITOS:
                if c == cine and not prueba(dec[pista][0]):
                    notas_.append(f"hito ({pista}): {que}")
            fallos_tot += len(notas_)
            hitos = sum(1 for h in HITOS if h[0] == cine)
            print(f"  → {cine}: suma de efectos y música, pico {suma:.1f} dBFS; música {m_fx['lufs'] - m_mus['lufs']:.1f} LU "
                  f"por debajo; {hitos} hitos de tiempo: {'; '.join(notas_) if notas_ else 'ok'}")
    print(f"\nTotal cinemáticas: {total_bytes} bytes = {total_bytes / 1e6:.3f} MB (límite {TOTAL_MAX / 1e6:.1f} MB)")
    if total_bytes > TOTAL_MAX:
        print("FALLO: se supera el presupuesto total")
        fallos_tot += 1
    print("RESULTADO:", "ok" if not fallos_tot else f"{fallos_tot} fallo(s)")
    return fallos_tot


def main() -> int:
    ap = argparse.ArgumentParser(description="Genera y comprueba la banda sonora de las cinemáticas de ALUX.")
    ap.add_argument("--check", action="store_true", help="solo comprobar los archivos existentes")
    ap.add_argument("--solo", default="", help="cinemáticas separadas por comas (por defecto, todas)")
    ap.add_argument("--espectros", type=Path, default=None, help="carpeta donde dejar espectrogramas PNG")
    a = ap.parse_args()
    if not a.check:
        ids = [s for s in a.solo.split(",") if s] or IDS
        desconocidos = set(ids) - set(IDS)
        if desconocidos:
            print(f"cinemáticas desconocidas: {sorted(desconocidos)}")
            return 2
        print(f"Generando {len(ids)} cinemática(s) (semilla base {SEMILLA})…")
        generar(ids, carpeta_tmp(), a.espectros)
    return 1 if comprobar() else 0


if __name__ == "__main__":
    sys.exit(main())
