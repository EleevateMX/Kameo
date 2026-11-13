#!/usr/bin/env python3
"""Frente 4: graves en `amb_cenote` y `amb_ruinas`.

En los dos bucles actuales el 73 % de la energía está por debajo de 200 Hz (aire de 55–380 Hz
y resonancias de 73–200 Hz): en un portátil o un móvil casi no suenan y, junto a la selva y el
viento, emborronan los graves. Los candidatos llevan el peso a 200–1200 Hz sin quitar la
sensación de espacio (sala larga, estéreo abierto), de dos maneras:

  A «armónicos»: el mismo diseño y las mismas notas, pero cada resonancia grave suena sobre
                 todo por sus armónicos 2.º a 4.º; el aire sube de banda; las gotas y las
                 piedras ganan cuerpo medio. Se recorta el subgrave.
  B «espacio»  : casi sin zumbido grave. El espacio lo cuentan los sucesos con sala larga:
                 en el cenote, agua que lame y gorgotea, más gotas con «plop» y el aire en la
                 boca del pozo; en las ruinas, soplos anchos por los huecos de la piedra, tres
                 piedrecillas distintas y un asiento lejano.

Mismos bucles que los actuales (32.00 s y 28.21 s) y misma convención.
"""

from __future__ import annotations

import shutil

import numpy as np

from comun import (
    AQUI, AUDIO_MP3, SR, bucle_candidato, env_perc, fase_de, filtrar, gen, glis, lento, modos, n_, pan, poner,
    rafaga, reverb, rms, ruido, ruido_barrido, ruido_st, t_, tirones, campana_env,
)

CORTES = (0, 200, 1200, 1e9)


def _respira(n, g, lo=0.03, hi=0.18, base=0.5, exp=1.3):
    return np.clip(base + (1.0 - base) * lento(n, g, lo, hi), 0.05, 1.8) ** exp


def gota(g, f, plop=0.7):
    """Gota en agua quieta con cuerpo: el «plic» que sube de tono y el «plop» de la cavidad que deja."""
    n = n_(0.24)
    t = t_(n)
    y = np.sin(fase_de(f * (1.0 - 0.38 * np.exp(-t / 0.011)))) * env_perc(n, 0.024, 0.001)
    fc = g.uniform(330.0, 620.0)
    y += plop * np.sin(fase_de(fc * (1.0 + 0.25 * np.exp(-t / 0.02)))) * env_perc(n, 0.045, 0.003)
    k = n_(0.004)
    y[:k] += 0.2 * ruido(k, g, 1500, 6000) * np.exp(-t[:k] / 0.001)
    return y


def _gotas(n, g, hueco, plop, t60, graves):
    """Gotas repartidas por el bucle, con dos ecos de pared y sala larga."""
    seg = n / SR
    seco = np.zeros((2, n))
    tt = g.uniform(0.5, 2.0)
    while tt < seg - 0.5:
        f = 700.0 * (2300.0 / 700.0) ** g.uniform()
        amp = g.uniform(0.35, 1.0)
        p = g.uniform(-0.8, 0.8)
        x = gota(g, f, plop)
        poner(seco, x, tt, amp, p, circular=True)
        if g.uniform() < 0.3:  # gota doble
            poner(seco, gota(g, f * g.uniform(0.85, 1.2), plop), tt + g.uniform(0.12, 0.3), 0.6 * amp, p, circular=True)
        lejos = filtrar(x, 200, 2500)
        poner(seco, lejos, tt + g.uniform(0.19, 0.24), 0.30 * amp, -p, circular=True)  # ecos de pared
        poner(seco, lejos, tt + g.uniform(0.43, 0.5), 0.14 * amp, 0.5 * p, circular=True)
        tt += g.uniform(*hueco)
    return reverb(seco, g, t60=t60, mezcla=0.9, circular=True, agudos=4200, graves=graves, retardo=0.03, cola_agudos=0.8)


def cenote_a(n, g):
    aire = ruido_st(n, g, 130, 900, color=1.2, ancho=0.5) * np.clip(1.0 + 0.3 * lento(n, g, 0.03, 0.2), 0.4, None)
    res = np.zeros((2, n))
    # Las notas de siempre (Re y La), pero cada una suena sobre todo por sus armónicos 2.º a 4.º
    for fc, p, gan in ((73.4, -0.3, 1.0), (110.0, 0.35, 0.7), (146.8, 0.0, 0.45), (196.0, -0.5, 0.25)):
        for k, gk in ((1, 0.25), (2, 0.7), (3, 1.0), (4, 0.7), (6, 0.3)):
            f = fc * k
            if f > 900.0:
                continue
            r = ruido(n, g, 0.985 * f, 1.015 * f, orden=4)
            res += pan(gan * gk * r * _respira(n, g), float(np.clip(p + 0.15 * (k - 2), -0.9, 0.9)))
    agua = ruido_st(n, g, 250, 950, orden=4, color=1.2, ancho=0.6) * _respira(n, g, 0.08, 0.4, 0.55)
    gotas = _gotas(n, g, (1.2, 3.6), plop=0.7, t60=3.6, graves=200.0)
    return 0.45 * aire + 0.50 * res / rms(res) + 0.30 * agua + 1.1 * gotas / rms(gotas) * 0.19


def cenote_b(n, g):
    seg = n / SR
    aire = ruido_st(n, g, 200, 1100, color=1.0, ancho=0.6) * np.clip(1.0 + 0.3 * lento(n, g, 0.03, 0.2), 0.4, None)
    # el aire en la boca del pozo: una banda ancha que se desplaza despacio (no silba)
    boca = np.zeros((2, n))
    for c, des in enumerate((0.0, 0.3)):
        fc = 520.0 * 2.0 ** (0.5 * np.clip(lento(n, g, 0.03, 0.12), -1.5, 1.5) + des)
        boca[c] = ruido_barrido(n, g, fc, ancho=0.35, color=1.0, f_min=250.0, f_max=1400.0, bandas=8)
    boca *= np.clip(_respira(n, g, 0.03, 0.15, 0.4, 1.5), None, 1.6)
    res = np.zeros((2, n))
    for f, p, gan in ((146.8, -0.3, 0.6), (220.0, 0.35, 1.0), (293.7, 0.0, 0.8)):
        res += pan(gan * ruido(n, g, 0.985 * f, 1.015 * f, orden=4) * _respira(n, g), p)
    agua = ruido_st(n, g, 300, 1400, orden=3, color=1.2, ancho=0.7) * _respira(n, g, 0.08, 0.4, 0.5, 1.6)
    glug = np.zeros((2, n))
    for _ in range(11):  # el agua gorgotea contra la pared de vez en cuando
        f = g.uniform(280.0, 520.0)
        d = g.uniform(0.06, 0.10)
        x = glis(f, f * g.uniform(1.25, 1.6), d) * env_perc(n_(d), d / 3.0, 0.004)
        t0 = g.uniform(0.0, seg)
        for j in range(int(g.integers(1, 4))):
            poner(glug, x, t0 + 0.11 * j * g.uniform(0.8, 1.2), g.uniform(0.4, 1.0) * 0.8 ** j, g.uniform(-0.7, 0.7), circular=True)
    glug = reverb(glug, g, t60=3.0, mezcla=0.8, circular=True, agudos=3000, graves=220, retardo=0.03)
    gotas = _gotas(n, g, (0.9, 2.5), plop=0.9, t60=4.2, graves=220.0)
    return (0.30 * aire + 0.30 * boca / rms(boca) + 0.16 * res / rms(res) + 0.32 * agua
            + 0.20 * glug / rms(glug) + 0.30 * gotas / rms(gotas))


def _piedra(g, cuerpo=0.9):
    """Un toque de piedrecilla: chasquido, modos agudos cortos y, debajo, el «toc» de la losa."""
    f1 = g.uniform(1400.0, 2600.0)
    x = np.zeros(n_(0.12))
    poner(x, rafaga(0.02, g, 1800, 6000, tau=0.002, ataque=0.0003), 0.0, 1.0)
    poner(x, modos(((f1, 1.0, 0.007), (1.7 * f1, 0.6, 0.005), (2.9 * f1, 0.3, 0.003)), 0.019), 0.0, 0.8)
    fb = g.uniform(480.0, 860.0)
    poner(x, modos(((fb, 1.0, 0.022), (1.52 * fb, 0.5, 0.014)), 0.11), 0.0, cuerpo)
    return x


def _rebote(piedras, g, tt, golpes, p, cuerpo):
    paso = g.uniform(0.13, 0.2)
    for i in range(golpes):
        poner(piedras, _piedra(g, cuerpo), tt, 0.7 ** i * g.uniform(0.8, 1.0), p + 0.05 * i, circular=True)
        tt += paso * 0.72 ** i


def ruinas_a(n, g):
    seg = n / SR
    aire = ruido_st(n, g, 110, 700, color=1.3, ancho=0.4) * np.clip(1.0 + 0.35 * lento(n, g, 0.03, 0.16), 0.3, None)
    hueco = np.zeros((2, n))
    # las mismas cinco resonancias y dos más arriba, con el peso desplazado de 92–138 a 207–466 Hz
    for fc, bw, p, gan in ((92.0, 0.05, -0.45, 0.25), (138.0, 0.045, 0.4, 0.5), (207.0, 0.04, 0.1, 1.0),
                           (311.0, 0.04, -0.2, 1.0), (466.0, 0.035, 0.3, 0.8), (622.0, 0.035, -0.35, 0.5),
                           (932.0, 0.03, 0.2, 0.25)):
        r = ruido(n, g, fc * (1.0 - bw), fc * (1.0 + bw), orden=4)
        hueco += pan(gan * r * _respira(n, g, 0.03, 0.2, 0.45, 1.4), p)
    soplo = ruido_st(n, g, 500, 2400, color=1.5, ancho=0.7) * np.clip(0.3 + 0.6 * lento(n, g, 0.04, 0.3), 0.0, None) ** 2
    piedras = np.zeros((2, n))
    _rebote(piedras, g, (0.24 + g.uniform(-0.04, 0.04)) * seg, int(g.integers(4, 7)), g.uniform(-0.7, -0.2), 0.9)
    _rebote(piedras, g, (0.69 + g.uniform(-0.04, 0.04)) * seg, 2, g.uniform(0.2, 0.7), 0.9)
    m = n_(0.7)  # arenilla que resbala, una vez por bucle
    poner(piedras, ruido(m, g, 700, 3000, color=1.0) * tirones(m, g, 8.0, 30.0, 2.0) * campana_env(m, 1.5), 0.47 * seg, 0.10,
          g.uniform(-0.3, 0.3), circular=True)
    piedras = reverb(piedras, g, t60=1.7, mezcla=0.6, circular=True, agudos=4500, graves=200, retardo=0.02)
    return 0.45 * aire + 0.75 * hueco / rms(hueco) * 0.9 + 0.22 * soplo + 0.6 * piedras


def ruinas_b(n, g):
    seg = n / SR
    aire = ruido_st(n, g, 200, 900, color=1.2, ancho=0.5) * np.clip(1.0 + 0.35 * lento(n, g, 0.03, 0.16), 0.3, None)
    soplos = np.zeros((2, n))
    for fc, p in ((330.0, -0.6), (520.0, 0.5), (780.0, -0.1)):  # aire por tres huecos: bandas anchas, cada una a su aire
        racha = np.clip(0.3 + 0.5 * lento(n, g, 0.03, 0.15), 0.0, 1.2) ** 1.5  # acotada: ninguna ráfaga se dispara
        soplos += pan(ruido(n, g, 0.82 * fc, 1.22 * fc, orden=3) * racha * np.clip(1.0 + 0.3 * lento(n, g, 0.6, 4.0), 0.3, None), p)
    soplos = reverb(soplos, g, t60=2.2, mezcla=0.5, circular=True, agudos=3000, graves=220, retardo=0.02)
    hueco = np.zeros((2, n))
    for fc, p in ((207.0, 0.2), (311.0, -0.3)):
        hueco += pan(ruido(n, g, 0.96 * fc, 1.04 * fc, orden=4) * _respira(n, g, 0.03, 0.2, 0.45, 1.4), p)
    piedras = np.zeros((2, n))
    _rebote(piedras, g, (0.20 + g.uniform(-0.03, 0.03)) * seg, int(g.integers(4, 7)), g.uniform(-0.7, -0.2), 1.1)
    poner(piedras, _piedra(g, 1.3), (0.52 + g.uniform(-0.03, 0.03)) * seg, 0.8, g.uniform(0.3, 0.7), circular=True)  # un solo toque
    tt = (0.80 + g.uniform(-0.03, 0.03)) * seg  # un reguero de piedrecillas
    for i in range(7):
        poner(piedras, _piedra(g, 0.7), tt, g.uniform(0.2, 0.5), -0.1 + g.uniform(-0.2, 0.2), circular=True)
        tt += g.uniform(0.05, 0.16)
    asiento = np.zeros((2, n))  # lejos, un bloque que se asienta: golpe sordo con cuerpo medio
    poner(asiento, modos(((170.0, 1.0, 0.12), (240.0, 0.8, 0.10), (330.0, 0.5, 0.07)), 0.7), 0.38 * seg, 1.0, -0.2, circular=True)
    piedras = reverb(piedras, g, t60=2.0, mezcla=0.7, circular=True, agudos=4500, graves=220, retardo=0.02)
    asiento = reverb(asiento, g, t60=2.6, mezcla=1.2, circular=True, agudos=1500, graves=120, retardo=0.05)
    return (0.25 * aire + 0.55 * soplos / rms(soplos) + 0.14 * hueco / rms(hueco) + 0.40 * piedras
            + 0.05 * asiento / np.max(np.abs(asiento)))


# (frente, cuadros MP3 del cuerpo, pasa-bajos, ((sufijo, función, pasa-altos, descripción), …))
BUCLES = (
    ("amb_cenote", 1225, 7000.0, (
        ("A_armonicos", cenote_a, 60.0, "mismo diseño; las resonancias de Re y La suenan por sus armónicos 2.º–4.º; gotas con «plop»"),
        ("B_espacio", cenote_b, 90.0, "casi sin zumbido: aire en la boca del pozo, agua que lame y gorgotea, más gotas y sala de 4.2 s"),
    )),
    ("amb_ruinas", 1080, 6000.0, (
        ("A_armonicos", ruinas_a, 55.0, "mismas resonancias con el peso en 207–466 Hz y dos más arriba; piedras con cuerpo y arenilla"),
        ("B_espacio", ruinas_b, 80.0, "soplos anchos por tres huecos con sala, tres piedrecillas distintas y un asiento lejano"),
    )),
)


def generar() -> dict:
    grupos = {}
    for frente, cuadros, agudos, candidatos in BUCLES:
        shutil.copyfile(AUDIO_MP3 / f"{frente}.mp3", AQUI / f"{frente}__actual.mp3")
        nombres, extra = [f"{frente}__actual"], {}
        for sufijo, fn, graves, _ in candidatos:
            nombre = f"{frente}__{sufijo}"
            extra[nombre] = bucle_candidato(nombre, fn(cuadros * 1152, gen(nombre)), graves, agudos)
            print(f"  {nombre}: costura corr {extra[nombre]['costura_corr']:.4f}, I·D {extra[nombre]['corr_canales']:.2f}")
            nombres.append(nombre)
        grupos[frente] = {"archivos": nombres, "canales": 2, "cortes": list(CORTES), "extra": extra}
    return grupos
