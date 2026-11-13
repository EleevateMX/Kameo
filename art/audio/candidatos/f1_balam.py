#!/usr/bin/env python3
"""Frente 1: voz de Balam (rugido, gruñido y rugido del ataque especial).

El rugido del juego es un diente de sierra con la amplitud cerrada a ritmo fijo, filtrado por
dos juegos de formantes estáticos que se mezclan. Aquí la síntesis es otra: pulsos glotales
uno a uno (cada uno con su periodo y su fuerza), que excitan granos formánticos; el tracto
(largo, de felino grande) se mueve de pulso en pulso; y el aire es ruido a ráfagas glotales
pasado por los mismos formantes. Nada parte de una grabación.

Candidatos:
  A «glotal»  : rugido vocal. Altura 78 → 128 → 60 Hz, la boca se abre y se cierra, poca
                irregularidad, aire moderado y cierre gutural corto.
  B «rugoso»  : fiera ronca. Más grave (30 → 96 → 24 Hz), arranca y acaba en pulsos sueltos
                (garganta), subarmónicos fuertes e irregulares y mucho aire turbulento.
  C «bufido»  : casi todo aire: soplo que aletea por la boca abierta sobre un fondo de pulsos
                graves, y un cierre de garganta de cinco golpes. (Solo para el rugido.)
"""

from __future__ import annotations

import numpy as np

from comun import (
    DOS_PI, SR, env_pulsos, filtro_variable, glis, env_perc, granos, lento,
    mezclar_formantes, n_, poner, pulsos, rafaga, rampa, reverb, rms, ruido, ruido_barrido, salida,
    saturar, t_,
)

# Tracto de un felino grande (unos 27 cm): más grave que una voz humana. (Hz, ancho, ganancia)
CERRADO = ((150.0, 90.0, 0.55), (250.0, 70.0, 1.00), (720.0, 100.0, 0.45), (1380.0, 150.0, 0.20),
           (2100.0, 220.0, 0.12), (2850.0, 300.0, 0.06))
ABIERTO = ((165.0, 100.0, 0.55), (540.0, 120.0, 1.00), (1080.0, 170.0, 0.62), (1780.0, 230.0, 0.42),
           (2500.0, 300.0, 0.28), (3250.0, 380.0, 0.11))
# Enseñando los dientes: menos primer formante y más 1.5–3 kHz (lo que se oye en altavoz pequeño)
FAUCES = ((160.0, 100.0, 0.50), (430.0, 130.0, 0.95), (1150.0, 180.0, 0.60), (1900.0, 230.0, 0.58),
          (2650.0, 300.0, 0.44), (3300.0, 380.0, 0.16))
CORTES = (0, 150, 600, 1000, 3000, 1e9)


def voz_felina(g, n, f0, abre, forma_abierta=ABIERTO, escala=1.0, jitter=0.03, shimmer=0.2, sub=0.2,
               retardo=0.04, triple=0.0, aire=0.3, ataque=0.0007, deriva=0.04, vaiven=0.04):
    """Voz de felino (RMS 1): pulsos irregulares → granos formánticos + aire a ráfagas glotales.

    `f0` y `abre` (0..1) son arrays de n muestras; `sub`, `retardo` y `triple` pueden serlo.
    """
    f0 = f0 * (1.0 + deriva * lento(n, g, 1.5, 9.0))
    tp, amp = pulsos(n, g, f0, jitter, shimmer, sub, retardo, triple)
    tc = np.linspace(0.0, n / SR, 240)
    # el tracto no se queda quieto: lengua y mandíbula mueven un poco todos los formantes
    mueve = escala * (1.0 + vaiven * np.interp(tc, t_(n), lento(n, g, 2.0, 11.0)))
    tr = mezclar_formantes(tc, np.interp(tc, t_(n), abre), CERRADO, forma_abierta, mueve)
    voz = granos(n, tp, amp, tr, ataque=ataque)
    voz /= rms(voz) + 1e-12
    # Aire: ruido que sale a ráfagas con cada pulso y pasa por el mismo tracto, más ancho
    soplo = ruido(n, g, 250, 8000, color=0.7) * (0.3 + env_pulsos(n, tp, amp, 0.25 / np.mean(f0)))
    soplo = filtro_variable(soplo, lambda t, f: tr.ganancia(t, f, ancho=1.8) * (f / (f + 500.0)))
    soplo /= rms(soplo) + 1e-12
    y = voz + aire * soplo * (0.35 + 0.65 * abre)
    return y / (rms(y) + 1e-12)


def _cierre_gutural(g, n_golpes, t0, sep0, sep1, escala=1.0):
    """Golpes de garganta que se van espaciando: pulsos sueltos por el tracto casi cerrado."""
    seps = sep0 * (sep1 / sep0) ** (np.arange(n_golpes) / max(n_golpes - 1, 1))
    tp = t0 + np.concatenate([[0.0], np.cumsum(seps[:-1])]) + g.uniform(-0.004, 0.004, n_golpes)
    amp = (1.0 - 0.6 * np.arange(n_golpes) / n_golpes) * g.uniform(0.8, 1.0, n_golpes)
    n = n_(tp[-1] + 0.12)
    tc = np.linspace(0.0, n / SR, 8)
    tr = mezclar_formantes(tc, np.full(8, 0.25), CERRADO, ABIERTO, escala)
    return granos(n, tp, amp, tr, ataque=0.0012)


def rugido_a(g, seg=0.98):
    n = n_(seg)
    u = np.arange(n) / n
    f0 = 78.0 + 50.0 * np.sin(np.pi * np.clip(u / 0.72, 0.0, 1.0)) ** 1.1 - 18.0 * u ** 2.5  # 78 → 128 → 60 Hz
    abre = np.sin(np.pi * u ** 0.75) ** 0.8
    sub = 0.12 + 0.55 * np.clip((u - 0.62) / 0.3, 0.0, 1.0) + 0.3 * np.exp(-u / 0.05)
    y = voz_felina(g, n, f0, abre, sub=sub, retardo=0.05, aire=0.32, jitter=0.03, shimmer=0.18)
    env = rampa(n, 0.045) * (0.30 + 0.70 * abre ** 1.3) * salida(n, 0.22)
    y = y * env
    alie = ruido_barrido(n, g, 600.0 * (2000.0 / 600.0) ** abre, ancho=0.9, color=1.3)  # aliento que sale
    y += 0.10 * alie * env * abre
    poner(y, rafaga(0.05, g, 400, 3000, tau=0.010, color=1.0), 0.0, 0.16)  # arranque
    poner(y, _cierre_gutural(g, 3, 0.80, 0.045, 0.06), 0.0, 0.10)
    return saturar(y, 1.4)


def rugido_b(g, seg=0.98):
    n = n_(seg)
    u = np.arange(n) / n
    # arranca en pulsos de garganta (30 Hz), sube a 96 y se hunde otra vez hasta 24 Hz
    f0 = 30.0 + 66.0 * np.clip(u / 0.16, 0.0, 1.0) ** 1.5 - 72.0 * np.clip((u - 0.55) / 0.45, 0.0, 1.0) ** 1.3
    abre = np.clip(np.sin(np.pi * u ** 0.8), 0.0, 1.0) ** 0.7
    caos = np.clip(0.45 + 0.45 * lento(n, g, 3.0, 14.0), 0.0, 0.9)  # el subarmónico entra y sale
    tri = np.clip(0.25 + 0.5 * lento(n, g, 2.0, 10.0), 0.0, 0.8)
    y = voz_felina(g, n, f0, abre, forma_abierta=FAUCES, escala=0.94, jitter=0.09, shimmer=0.4, sub=caos,
                   retardo=0.10, triple=tri, aire=0.55, ataque=0.0006, deriva=0.07)
    env = rampa(n, 0.03) * (0.42 + 0.58 * abre ** 1.2) * salida(n, 0.16)
    return saturar(y * env, 2.6)


def rugido_c(g, seg=0.98):
    n = n_(seg)
    t = t_(n)
    u = np.arange(n) / n
    abre = np.clip(np.sin(np.pi * u ** 0.6), 0.0, 1.0) ** 0.6
    tc = np.linspace(0.0, seg, 240)
    tr = mezclar_formantes(tc, np.interp(tc, t, abre), CERRADO, FAUCES,
                           1.0 + 0.07 * np.interp(tc, t, lento(n, g, 2.0, 11.0)))
    # el soplo aletea de forma irregular (28–40 veces por segundo): eso lo hace bufido y no siseo
    aleteo = 0.5 + 0.5 * np.sin(DOS_PI * np.cumsum(34.0 * (1.0 + 0.18 * lento(n, g, 2.0, 9.0))) / SR)
    soplo = ruido(n, g, 200, 8500, color=0.8) * (0.35 + 0.65 * aleteo ** 2)
    soplo = filtro_variable(soplo, lambda tt, f: tr.ganancia(tt, f, ancho=1.5) * (f / (f + 350.0)))
    soplo /= rms(soplo)
    f0 = 44.0 + 22.0 * np.sin(np.pi * u) - 10.0 * u
    fondo = voz_felina(g, n, f0, 0.6 * abre, jitter=0.12, shimmer=0.4, sub=0.5, retardo=0.12, aire=0.1)
    env = rampa(n, 0.06) * (0.25 + 0.75 * abre ** 1.4) * salida(n, 0.30)
    y = (soplo + 0.75 * fondo) * env * (1.0 - 0.75 * np.clip((u - 0.70) / 0.12, 0.0, 1.0))
    poner(y, _cierre_gutural(g, 5, 0.70, 0.038, 0.062), 0.0, 0.42)
    return saturar(y, 1.5)


def grunido_a(g, seg=0.44):
    n = n_(seg)
    t = t_(n)
    u = np.arange(n) / n
    abre = 0.50 * np.sin(np.pi * u ** 0.6)
    f0 = 96.0 * (60.0 / 96.0) ** u
    sub = 0.25 + 0.5 * u
    y = voz_felina(g, n, f0, abre, sub=sub, retardo=0.06, aire=0.22, jitter=0.04, shimmer=0.22)
    env = rampa(n, 0.03) * np.exp(-np.clip(t - 0.14, 0.0, None) / 0.20) * salida(n, 0.10)
    y = y * env
    poner(y, rafaga(0.05, g, 300, 2200, tau=0.010, color=1.0), 0.0, 0.14)
    return saturar(y, 1.4)


def grunido_b(g, seg=0.44):
    n = n_(seg)
    t = t_(n)
    u = np.arange(n) / n
    abre = 0.60 * np.sin(np.pi * u ** 0.55)
    f0 = 62.0 * (26.0 / 62.0) ** (u ** 0.8)  # cae hasta pulsos sueltos
    y = voz_felina(g, n, f0, abre, forma_abierta=FAUCES, escala=0.94, jitter=0.10, shimmer=0.4, sub=0.55,
                   retardo=0.10, triple=0.4, aire=0.45, deriva=0.06)
    env = rampa(n, 0.02) * np.exp(-np.clip(t - 0.16, 0.0, None) / 0.22) * salida(n, 0.08)
    return saturar(y * env, 2.6)


def _onda_choque(y, g, tq):
    """La onda de choque del ataque especial: misma receta que `balam_especial` de gen_audio.py."""
    poner(y, glis(125, 34, 0.50) * env_perc(n_(0.50), 0.15, 0.002), tq, 1.2)
    poner(y, rafaga(0.10, g, 600, 5500, tau=0.014, ataque=0.0005), tq, 0.9)
    poner(y, rafaga(0.35, g, 150, 1300, tau=0.07, color=1.0), tq, 1.0)
    m = n_(0.48)
    v = np.arange(m) / m
    anillo = ruido_barrido(m, g, 2600.0 * (260.0 / 2600.0) ** (v ** 0.6), ancho=0.8, color=1.0, f_min=100.0)
    poner(y, anillo * env_perc(m, 0.17, 0.010), tq + 0.01, 0.7)
    poner(y, rafaga(0.50, g, 35, 160, tau=0.20, ataque=0.02, color=2.0), tq, 0.6)


def _especial(g, rugido_corto):
    y = np.zeros(n_(0.9))
    poner(y, rugido_corto, 0.0, 0.8)  # el rugido corto, al nivel del original frente a la onda
    _onda_choque(y, g, 0.38)
    y = reverb(y, g, t60=0.5, mezcla=0.10, agudos=3500.0, graves=60.0)[:n_(0.9)]
    return saturar(y, 2.0)


def especial_a(g):
    n = n_(0.46)
    u = np.arange(n) / n
    abre = np.sin(np.pi * u ** 0.5) ** 0.7
    f0 = 98.0 + 34.0 * np.sin(np.pi * u) - 12.0 * u
    r = voz_felina(g, n, f0, abre, sub=0.2 + 0.3 * u, retardo=0.05, aire=0.32)
    return _especial(g, r * rampa(n, 0.03) * (0.6 + 0.4 * abre) * salida(n, 0.12))


def especial_b(g):
    n = n_(0.46)
    u = np.arange(n) / n
    abre = np.sin(np.pi * u ** 0.5) ** 0.7
    f0 = 36.0 + 60.0 * np.clip(u / 0.25, 0.0, 1.0) ** 1.4 - 30.0 * np.clip((u - 0.6) / 0.4, 0.0, 1.0)
    r = voz_felina(g, n, f0, abre, forma_abierta=FAUCES, escala=0.94, jitter=0.09, shimmer=0.4,
                   sub=np.clip(0.45 + 0.4 * lento(n, g, 3.0, 14.0), 0.0, 0.9), retardo=0.10, triple=0.35,
                   aire=0.55, deriva=0.07)
    return _especial(g, r * rampa(n, 0.025) * (0.6 + 0.4 * abre) * salida(n, 0.12))


# (frente, duración, corte de agudos, fundido final, [(sufijo, función, descripción)])
# El corte de agudos sube de 4.0–4.5 kHz (actual) a 6 kHz: la presencia de 1–3 kHz necesita aire encima.
SONIDOS = (
    ("balam_rugido", 1.00, 6000.0, 0.20, (
        ("A_glotal", rugido_a, "rugido vocal: pulsos glotales y tracto que se abre, 78→128→60 Hz"),
        ("B_rugoso", rugido_b, "fiera ronca: pulsos de garganta, subarmónicos irregulares y aire turbulento"),
        ("C_bufido", rugido_c, "bufido: soplo que aletea por la boca abierta y cierre de garganta"),
    )),
    ("balam_grunido", 0.45, 6000.0, 0.08, (
        ("A_glotal", grunido_a, "gruñido vocal corto, boca casi cerrada, 96→60 Hz"),
        ("B_rugoso", grunido_b, "gruñido de garganta: cae hasta pulsos sueltos, con aire"),
    )),
    ("balam_especial", 0.90, 6000.0, 0.20, (
        ("A_glotal", especial_a, "rugido corto vocal + la misma onda de choque"),
        ("B_rugoso", especial_b, "rugido corto ronco + la misma onda de choque"),
    )),
)
