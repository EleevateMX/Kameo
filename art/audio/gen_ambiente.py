#!/usr/bin/env python3
"""Bucles de ambiente de ALUX (Alpha 0.3.1), sintetizados por código.

Genera los diez `amb_*.mp3` (estéreo, 44.1 kHz, LAME `-q:a 6`) y `ambiente.json` en
`game/web/static/audio/`. No usa grabaciones ni muestras de nadie: todo sale de senos,
ruido filtrado y envolventes con semillas fijas (ver `_dsp_estereo.py`).

Cada archivo de bucle se escribe así (lo aprovecha el reproductor con `loopStart`/`loopEnd`):

    [ pre = últimos 0.5 s del cuerpo ][ cuerpo circular, L segundos ][ post = primeros 0.5 s ]

y el manifiesto declara "loop": [0.5, 0.5 + L]. El cuerpo mide un número entero de cuadros
MP3 (1152 muestras): así el codificador trata igual el arranque del cuerpo y su repetición
en el `post`, y el salto del bucle cae entre dos formas de onda prácticamente idénticas.

Uso:
    python art/audio/gen_ambiente.py                 # genera todo, escribe el manifiesto y comprueba
    python art/audio/gen_ambiente.py --check         # solo comprueba lo que hay en disco
    python art/audio/gen_ambiente.py --solo amb_agua,amb_aves   # regenera solo esos
    python art/audio/gen_ambiente.py --espectros DIR # además, espectrogramas PNG en DIR
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parent))
from _dsp_estereo import (  # noqa: E402
    CUADRO_MP3, DOS_PI, LICENCIA, PARC_CRISTAL, SALIDA, SEMILLA, SR,
    actualizar_manifiesto, campana, carpeta_tmp, codificar_mp3, convolucionar, db, env_perc,
    escribir_json, escribir_wav, espectrograma, fase_de, filtrar, gen, glis, lento, lin, limitar,
    lufs, medir, midi, modos, n_, pan, poner, rafaga, reverb, rms, ruido, ruido_barrido, ruido_st,
    semilla_de, t_, trenes,
)

MARGEN = 0.5  # segundos de `pre` y de `post`
CALIDAD = 6  # LAME -q:a
LUFS_MIN, LUFS_MAX, LUFS_OBJ = -30.0, -26.0, -28.0
PICO_MAX = -6.0  # dBFS, medido sobre el MP3 decodificado
TECHO = -8.0  # techo del limitador antes de codificar (el MP3 sube algo los picos)
BYTES_MAX = 450_000
TOTAL_MAX = 3_500_000
CORR_BUCLE = 0.98


# --------------------------------------------------------------------------------------
# Cantos de ave (inventados: ninguno imita una especie ni una grabación concreta)
# --------------------------------------------------------------------------------------

def _silbo(f0, f1, seg, curva=1.0, arm=0.12):
    """Silbido: barrido senoidal con envolvente de campana."""
    n = n_(seg)
    u = np.arange(n) / n
    w = fase_de(f0 * (f1 / f0) ** (u ** curva))
    return (np.sin(w) + arm * np.sin(2 * w)) * np.sin(np.pi * u) ** 1.5


TIPOS_CANTO = ("caida", "dos_notas", "trino", "gorjeo", "arrullo", "eco", "ululo", "pios",
               "carraca", "flauteo")


def _canto(tipo, g, tono=1.0, vel=1.0):
    """Un canto (mono). `tono` multiplica las frecuencias y `vel` la rapidez."""
    y = np.zeros(n_(3.0))

    def d(s):
        return s / vel

    if tipo == "caida":  # dos silbos que caen
        poner(y, _silbo(2500 * tono, 1700 * tono, d(0.32), 0.8), 0.0, 1.0)
        poner(y, _silbo(2150 * tono, 1550 * tono, d(0.26), 0.8), d(0.42), 0.7)
    elif tipo == "dos_notas":  # grave-aguda
        poner(y, _silbo(1650 * tono, 1700 * tono, d(0.15)), 0.0, 0.9)
        poner(y, _silbo(2120 * tono, 2050 * tono, d(0.24)), d(0.21), 1.0)
    elif tipo == "trino":  # notas rápidas que se aprietan
        k = int(g.integers(5, 10))
        for i in range(k):
            a = 0.5 + 0.5 * np.sin(np.pi * (i + 0.5) / k)
            poner(y, _silbo(2800 * tono, 3500 * tono, d(0.05)), d(0.085) * i * (1.0 - 0.02 * i), a)
    elif tipo == "gorjeo":  # nota que tiembla
        n = n_(d(0.5))
        t = t_(n)
        u = np.arange(n) / n
        w = fase_de(2300 * tono * (1.0 - 0.1 * u) + 280 * np.sin(DOS_PI * 21 * vel * t))
        poner(y, np.sin(w) * np.sin(np.pi * u) ** 1.2, 0.0, 0.9)
    elif tipo == "arrullo":  # paloma: notas graves y redondas
        k = int(g.integers(3, 5))
        for i in range(k):
            poner(y, _silbo(560 * tono, 495 * tono, d(0.3), arm=0.25), d(0.38) * i, (0.8, 1.0, 0.75, 0.55)[i])
    elif tipo == "eco":  # una nota clara que se repite cada vez más lejos
        f = 1350 * tono
        for i in range(4):
            poner(y, _silbo(f, 0.94 * f, d(0.22), 0.6), d(0.34) * i, 0.6 ** i)
    elif tipo == "ululo":  # sube y baja despacio
        for j, (dur, gan) in enumerate(((0.55, 1.0), (0.42, 0.6))):
            n = n_(d(dur))
            u = np.arange(n) / n
            w = fase_de(tono * (950 + 520 * np.sin(np.pi * u) ** 1.3))
            poner(y, (np.sin(w) + 0.2 * np.sin(2 * w)) * np.sin(np.pi * u) ** 1.2, d(0.72) * j, gan)
    elif tipo == "pios":  # píos agudos que bajan en escalera
        k = int(g.integers(3, 6))
        for i in range(k):
            f = 3900 * tono * 0.93 ** i
            poner(y, _silbo(f, 1.18 * f, d(0.06)), d(0.13) * i, 1.0 - 0.12 * i)
    elif tipo == "carraca":  # llamada seca, de ruido que vibra
        n = n_(d(0.45))
        t = t_(n)
        u = np.arange(n) / n
        port = ruido(n, g, 1700 * tono, 3000 * tono, orden=8)
        poner(y, port * (0.5 + 0.5 * np.sin(DOS_PI * 27 * vel * t)) ** 2 * np.sin(np.pi * u) ** 0.8, 0.0, 0.7)
    elif tipo == "flauteo":  # tres notas sueltas
        for i, f in enumerate(tono * np.array([1800.0, 2400.0, 2020.0])):
            poner(y, _silbo(f, f * g.uniform(0.96, 1.04), d(0.2)), d(0.26) * i, (0.9, 1.0, 0.8)[i])
    fin = int(np.nonzero(y)[0][-1]) + 1
    return y[:fin] / np.max(np.abs(y)) * (0.55 if tipo == "carraca" else 1.0)


# --------------------------------------------------------------------------------------
# Los diez ambientes. Cada función recibe el número de muestras del cuerpo y devuelve
# el cuerpo circular en estéreo, sin normalizar.
# --------------------------------------------------------------------------------------

def amb_selva(n):
    """Base de selva de día: aire grave, hojas en cuatro copas y zumbido lejano de insectos."""
    g = gen("amb_selva")
    seg = n / SR
    t = t_(n)
    aire = ruido_st(n, g, 110, 700, color=1.0, ancho=0.5)
    aire = aire * np.clip(1.0 + 0.30 * lento(n, g, 0.03, 0.2), 0.35, None)
    hojas = np.zeros((2, n))
    for p, lo, hi in ((-0.85, 1500, 5200), (-0.3, 1900, 6500), (0.3, 1300, 4600), (0.85, 2200, 7000)):
        racha = np.clip(0.42 + 0.5 * lento(n, g, 0.035, 0.3), 0.03, None) ** 2
        temblor = np.clip(1.0 + 0.4 * lento(n, g, 1.5, 8.0), 0.2, None)
        hojas += pan(ruido(n, g, lo, hi, color=1.0) * racha * temblor, p)
    zum = np.zeros((2, n))
    for fc, bw, f_trem, p in ((3100, 380, 13.0, -0.5), (5900, 600, 21.0, 0.45), (4300, 300, 9.0, 0.1)):
        ft = round(f_trem * seg) / seg
        port = ruido(n, g, fc - bw / 2, fc + bw / 2, orden=6)
        port *= 0.7 + 0.3 * np.sin(DOS_PI * ft * t + 0.8 * lento(n, g, 0.05, 0.4))
        port *= np.clip(0.6 + 0.4 * lento(n, g, 0.03, 0.15), 0.1, None)
        zum += pan(port, p)
    return aire + 0.36 * hojas + 0.07 * zum


def amb_aves(n):
    """Aves de selva: cantos variados repartidos en el estéreo, con distancia, y un lecho lejano."""
    g = gen("amb_aves")
    seg = n / SR
    seco = np.zeros((2, n))
    envio = np.zeros((2, n))
    orden = list(g.permutation(TIPOS_CANTO))
    tt = g.uniform(0.4, 1.4)
    i = 0
    while tt < seg - 1.0:
        if i and i % len(TIPOS_CANTO) == 0:  # otra vuelta, en otro orden
            ultimo = orden[-1]
            orden = list(g.permutation(TIPOS_CANTO))
            if orden[0] == ultimo:
                orden.append(orden.pop(0))
        tipo = orden[i % len(TIPOS_CANTO)]
        cerca = g.uniform(0.2, 0.95)
        p = g.uniform(-0.9, 0.9)
        c = _canto(tipo, g, tono=g.uniform(0.84, 1.2), vel=g.uniform(0.85, 1.2))
        c = filtrar(c, 350, 2200 + 6000 * cerca)
        nivel = 0.3 + 0.7 * cerca
        poner(seco, c, tt, nivel, p, circular=True)
        poner(seco, c, tt + g.uniform(0.08, 0.13), 0.2 * nivel, 0.6 * p, circular=True)  # eco del follaje
        poner(envio, c, tt, nivel * (0.5 + 0.9 * (1.0 - cerca)), p, circular=True)
        tt += g.uniform(1.1, 3.4)
        i += 1
    # Lecho: bandada lejana, cientos de píos mínimos que solo se oyen como sala
    lecho = np.zeros((2, n))
    dens = np.clip(0.5 + 0.5 * lento(n, g, 0.03, 0.2), 0.05, 1.0)
    for _ in range(int(10 * seg)):
        t0 = g.uniform(0.0, seg)
        f0 = 1800 * (5200 / 1800) ** g.uniform()
        x = _silbo(f0, f0 * g.uniform(0.75, 1.35), g.uniform(0.03, 0.08))
        poner(lecho, x, t0, g.uniform(0.2, 1.0) * dens[int(t0 * SR) % n], g.uniform(-1.0, 1.0), circular=True)
    lecho = filtrar(lecho, 900, 4200, circular=True)
    lecho = reverb(lecho, g, t60=2.2, mezcla=1.0, circular=True, agudos=4200, seco=0.15)
    cola = reverb(envio, g, t60=1.9, mezcla=1.0, circular=True, agudos=4500, seco=0.0)
    return seco + 0.55 * cola + 0.010 * lecho / rms(lecho)


def amb_insectos(n):
    """Chicharras (ruido agudo en bandas, con trémolo, en oleadas) y grillos (chirridos tonales)."""
    g = gen("amb_insectos")
    seg = n / SR
    t = t_(n)
    y = np.zeros((2, n))
    for fc, bw, p in ((4300, 500, -0.7), (5300, 650, 0.6), (6200, 700, -0.2), (7100, 800, 0.3)):
        port = ruido(n, g, fc - bw / 2, fc + bw / 2, orden=6)
        pulsos = round(g.uniform(34.0, 58.0) * seg) / seg
        trem = (0.5 + 0.5 * np.sin(DOS_PI * pulsos * t + 1.2 * lento(n, g, 0.05, 0.6))) ** 1.5
        ola = np.clip(0.15 + 0.75 * lento(n, g, 0.03, 0.14), 0.0, None) ** 1.6  # sube y baja
        y += pan(port * (0.25 + 0.75 * trem) * (0.10 + ola), p)
    y /= rms(y)
    grillos = np.zeros((2, n))
    for i in range(5):
        f = g.uniform(3700.0, 5200.0)
        p = g.uniform(-0.9, 0.9)
        periodo = g.uniform(0.45, 0.9)
        m = n_(0.011)
        pulso = np.sin(DOS_PI * f * t_(m)) * np.sin(np.pi * np.arange(m) / m) ** 2
        chirrido = np.zeros(n_(0.06))
        for j in range(3 if i % 2 == 0 else 2):
            poner(chirrido, pulso, 0.017 * j, 1.0 - 0.1 * j)
        activo = np.clip(0.3 + 0.9 * lento(n, g, 0.03, 0.12), 0.0, 1.0) ** 2
        for k in range(int(seg / periodo)):
            t0 = k * periodo + g.uniform(-0.03, 0.03)
            a = activo[int(t0 * SR) % n]
            if a > 0.05:
                poner(grillos, chirrido, t0, a * g.uniform(0.8, 1.0), p, circular=True)
    grillos = reverb(grillos, g, t60=0.7, mezcla=0.25, circular=True, agudos=7000)
    return y + 2.2 * grillos


def amb_viento(n):
    """Viento entre árboles y ruinas: ráfagas lentas de ruido que cambia de color, sin silbidos."""
    g = gen("amb_viento")
    fuerza = np.clip(0.48 + 0.42 * lento(n, g, 0.03, 0.2), 0.04, None)
    des = n_(0.7)  # la ráfaga llega antes a un lado que al otro
    y = np.zeros((2, n))
    centro = ruido_barrido(n, g, 230.0 * 2.0 ** (1.3 * np.clip(fuerza, 0.0, 1.4)), ancho=1.0, color=1.6,
                           f_min=80.0, f_max=3200.0, bandas=12) * fuerza ** 1.4
    for c, fz in enumerate((np.roll(fuerza, -des), np.roll(fuerza, des))):
        lado = ruido_barrido(n, g, 260.0 * 2.0 ** (1.3 * np.clip(fz, 0.0, 1.4)), ancho=0.9, color=1.6,
                             f_min=80.0, f_max=3200.0, bandas=12) * fz ** 1.4
        y[c] = 0.8 * centro + 0.6 * lado
    for fc, p in ((236.0, -0.4), (352.0, 0.5)):  # huecos de las ruinas: resuenan con las ráfagas fuertes
        hueco = ruido(n, g, 0.96 * fc, 1.04 * fc, orden=4) * np.clip(fuerza - 0.45, 0.0, None) ** 1.5
        y += pan(0.45 * hueco * np.clip(1.0 + 0.3 * lento(n, g, 0.5, 3.0), 0.3, None), p)
    hojas = ruido_st(n, g, 1800, 5500, color=1.2, ancho=0.6) * fuerza ** 2.2
    y += 0.10 * hojas * np.clip(1.0 + 0.35 * lento(n, g, 1.0, 6.0), 0.2, None)
    y += 0.22 * ruido_st(n, g, 40, 140, color=2.0, ancho=0.3) * (0.5 + 0.5 * fuerza)
    return y


def amb_agua(n):
    """Arroyo cercano: murmullo por bandas, gorgoteo grave y burbujas sueltas."""
    g = gen("amb_agua")
    seg = n / SR
    y = np.zeros((2, n))
    bordes = np.geomspace(350.0, 7500.0, 8)
    for lo, hi in zip(bordes[:-1], bordes[1:]):
        mod = np.clip(1.0 + 0.7 * lento(n, g, 2.0, 16.0), 0.05, None)
        mod *= np.clip(1.0 + 0.25 * lento(n, g, 0.05, 0.5), 0.4, None)
        y += ruido_st(n, g, lo, hi, orden=3, ancho=0.6) * mod * (1000.0 / np.sqrt(lo * hi)) ** 0.45
    y /= rms(y)
    gor = ruido_st(n, g, 110, 420, color=1.0, ancho=0.4)
    gor = gor * np.clip(0.2 + 0.8 * lento(n, g, 0.8, 5.0), 0.0, None) ** 1.5
    bur = np.zeros((2, n))
    for _ in range(int(26 * seg)):
        f0 = 420.0 * (2600.0 / 420.0) ** g.uniform()
        d = g.uniform(0.012, 0.05) * (900.0 / f0) ** 0.3
        x = glis(f0, f0 * g.uniform(1.2, 1.8), d) * env_perc(n_(d), d / 3.0, 0.002)
        poner(bur, x, g.uniform(0.0, seg), min(1.5, 0.35 * float(np.exp(g.normal(0.0, 0.6)))),
              g.uniform(-0.9, 0.9), circular=True)
    return y + 0.35 * gor + 0.45 * bur / rms(bur)


def _gota(g, f):
    """Gota en agua quieta: «plic» que sube de tono y se apaga enseguida."""
    n = n_(0.11)
    t = t_(n)
    w = fase_de(f * (1.0 - 0.38 * np.exp(-t / 0.011)))
    y = np.sin(w) * env_perc(n, 0.024, 0.001)
    k = n_(0.004)
    y[:k] += 0.2 * ruido(k, g, 1500, 6000) * np.exp(-t[:k] / 0.001)
    return y


def amb_cenote(n):
    """Interior de cenote: aire de caverna, resonancia grave, agua profunda y gotas con eco largo."""
    g = gen("amb_cenote")
    seg = n / SR
    aire = ruido_st(n, g, 70, 380, color=1.5, ancho=0.5)
    aire = aire * np.clip(1.0 + 0.3 * lento(n, g, 0.03, 0.2), 0.4, None)
    res = np.zeros((2, n))
    for fc, p, gan in ((73.4, -0.3, 1.0), (110.0, 0.35, 0.7), (146.8, 0.0, 0.45), (196.0, -0.5, 0.25)):
        r = ruido(n, g, 0.985 * fc, 1.015 * fc, orden=4)
        res += pan(gan * r * np.clip(0.5 + 0.5 * lento(n, g, 0.03, 0.18), 0.05, None) ** 1.3, p)
    agua = ruido_st(n, g, 160, 520, orden=4, color=1.5, ancho=0.6)
    agua = agua * np.clip(0.55 + 0.45 * lento(n, g, 0.08, 0.4), 0.1, None) ** 1.3
    seco = np.zeros((2, n))
    tt = g.uniform(0.5, 2.0)
    while tt < seg - 0.5:
        f = 700.0 * (2300.0 / 700.0) ** g.uniform()
        amp = g.uniform(0.35, 1.0)
        p = g.uniform(-0.8, 0.8)
        gota = _gota(g, f)
        poner(seco, gota, tt, amp, p, circular=True)
        if g.uniform() < 0.3:  # gota doble
            poner(seco, _gota(g, f * g.uniform(0.85, 1.2)), tt + g.uniform(0.12, 0.3), 0.6 * amp, p, circular=True)
        lejos = filtrar(gota, 200, 2500)
        poner(seco, lejos, tt + g.uniform(0.19, 0.24), 0.30 * amp, -p, circular=True)  # ecos de pared
        poner(seco, lejos, tt + g.uniform(0.43, 0.5), 0.14 * amp, 0.5 * p, circular=True)
        tt += g.uniform(1.2, 3.6)
    gotas = reverb(seco, g, t60=3.6, mezcla=0.9, circular=True, agudos=4200, graves=150, retardo=0.03,
                   cola_agudos=0.8)
    return 0.50 * aire + 0.45 * res + 0.22 * agua + 1.1 * gotas


def amb_ruinas(n):
    """Patio de piedra antiguo: tono de aire grave, resonancia hueca y dos piedrecillas por bucle."""
    g = gen("amb_ruinas")
    seg = n / SR
    aire = ruido_st(n, g, 55, 240, color=1.5, ancho=0.4)
    aire = aire * np.clip(1.0 + 0.35 * lento(n, g, 0.03, 0.16), 0.3, None)
    hueco = np.zeros((2, n))
    for fc, bw, p, gan in ((92.0, 0.05, -0.45, 0.8), (138.0, 0.045, 0.4, 1.0), (207.0, 0.04, 0.1, 0.9),
                           (311.0, 0.04, -0.2, 0.6), (466.0, 0.035, 0.3, 0.3)):
        r = ruido(n, g, fc * (1.0 - bw), fc * (1.0 + bw), orden=4)
        hueco += pan(gan * r * np.clip(0.45 + 0.55 * lento(n, g, 0.03, 0.2), 0.03, None) ** 1.4, p)
    soplo = ruido_st(n, g, 500, 2400, color=1.5, ancho=0.7)
    soplo = soplo * np.clip(0.3 + 0.6 * lento(n, g, 0.04, 0.3), 0.0, None) ** 2
    piedras = np.zeros((2, n))
    for pos, golpes, p in ((0.24, int(g.integers(4, 7)), g.uniform(-0.7, -0.2)), (0.69, 2, g.uniform(0.2, 0.7))):
        tt = (pos + g.uniform(-0.04, 0.04)) * seg
        paso = g.uniform(0.13, 0.2)
        for i in range(golpes):  # una piedrecilla que rebota y se queda quieta
            f1 = g.uniform(1400.0, 2600.0)
            x = rafaga(0.02, g, 1800, 6000, tau=0.002, ataque=0.0003)
            poner(x, modos(((f1, 1.0, 0.007), (1.7 * f1, 0.6, 0.005), (2.9 * f1, 0.3, 0.003)), 0.019), 0.0, 0.8)
            poner(piedras, x, tt, 0.7 ** i * g.uniform(0.8, 1.0), p + 0.05 * i, circular=True)
            tt += paso * 0.72 ** i
    piedras = reverb(piedras, g, t60=1.7, mezcla=0.6, circular=True, agudos=4500, retardo=0.02)
    return 0.6 * aire + 0.75 * hueco + 0.12 * soplo + 0.6 * piedras


def amb_tormenta(n):
    """Tormenta tropical: lluvia sobre hojas (siseo, gotas, goterones) y dos truenos lejanos."""
    g = gen("amb_tormenta")
    seg = n / SR
    inten = np.clip(0.8 + 0.25 * lento(n, g, 0.03, 0.14), 0.4, 1.4)
    base = ruido_st(n, g, 700, 9000, color=0.6, ancho=0.5) * inten
    gotas = np.zeros((2, n))
    for lo, hi, tau, por_seg, gan in ((1500, 4500, 0.003, 90, 1.0), (3000, 8000, 0.002, 120, 0.7),
                                      (500, 1500, 0.007, 14, 1.2)):
        for _ in range(5):  # cinco granos distintos por tamaño: ningún color fijo se repite
            nucleo = rafaga(8 * tau, g, lo, hi, tau=tau * g.uniform(0.7, 1.4), ataque=0.0004)
            comun = convolucionar(trenes(n, g, por_seg / 5.0, 0.7, dens=inten / 1.4), nucleo)
            for c in range(2):
                gotas[c] += gan * (0.7 * comun
                                   + convolucionar(trenes(n, g, por_seg / 5.0, 0.7, dens=inten / 1.4), nucleo))
    gotas /= rms(gotas)
    goterones = np.zeros((2, n))
    for _ in range(int(2.5 * seg)):  # gotas gordas sobre hojas grandes
        f = g.uniform(280.0, 800.0)
        x = modos(((f, 1.0, 0.02), (2.3 * f, 0.4, 0.01)), 0.1)
        x[:n_(0.006)] += 0.5 * ruido(n_(0.006), g, 1000, 4000) * np.exp(-t_(n_(0.006)) / 0.0015)
        poner(goterones, x, g.uniform(0.0, seg), g.uniform(0.3, 1.0), g.uniform(-0.9, 0.9), circular=True)
    grave = ruido_st(n, g, 45, 260, color=1.8, ancho=0.4)
    grave = grave * np.clip(1.0 + 0.3 * lento(n, g, 0.05, 0.3), 0.3, None)
    truenos = np.zeros((2, n))
    for pos, gan, p, dur, f_hi in ((0.21, 1.0, -0.35, 6.5, 170.0), (0.68, 0.5, 0.4, 5.0, 120.0)):
        m = n_(dur)
        tt = t_(m)
        env = np.zeros(m)
        for j in range(5):  # varios retumbos encadenados
            t0 = 0.0 if j == 0 else g.uniform(0.0, 0.35 * dur)
            dt = np.clip(tt - t0, 0.0, None)
            env += g.uniform(0.4, 1.0) * np.exp(-dt / g.uniform(0.5, 1.4)) * (1.0 - np.exp(-dt / 0.07)) * (tt >= t0)
        env *= np.where(tt > dur - 1.5, 0.5 + 0.5 * np.cos(np.pi * np.clip((tt - (dur - 1.5)) / 1.5, 0.0, 1.0)), 1.0)
        x = ruido(m, g, 28, f_hi, color=2.0) * env * np.clip(1.0 + 0.5 * lento(m, g, 1.5, 7.0), 0.2, None)
        x += 0.25 * ruido(m, g, 150, 600, color=2.0) * np.exp(-tt / 0.6) * (1.0 - np.exp(-tt / 0.08))
        poner(truenos, x, (pos + g.uniform(-0.03, 0.03)) * seg, gan, p, circular=True)
    truenos = reverb(truenos, g, t60=3.0, mezcla=0.6, circular=True, agudos=700, graves=30, retardo=0.04)
    return 0.55 * base + 0.6 * gotas + 0.22 * goterones / rms(goterones) + 0.35 * grave + 0.95 * truenos


def amb_energia(n):
    """Energía mística: zumbido armónico sobre Re que late despacio y destellos vítreos suaves."""
    g = gen("amb_energia")
    seg = n / SR
    t = t_(n)
    f0 = midi(50)  # Re3
    pulso = round(0.45 * seg) / seg
    hondo = np.clip(0.4 + 0.12 * lento(n, g, 0.04, 0.2), 0.2, 0.6)  # el latido no es siempre igual de hondo
    late = (1.0 - hondo) + hondo * (0.5 + 0.5 * np.sin(DOS_PI * pulso * t - np.pi / 2
                                                     + 0.5 * lento(n, g, 0.04, 0.2))) ** 1.6
    y = np.zeros((2, n))
    for razon, amp, p in ((0.5, 0.2, 0.0), (1.0, 0.8, -0.25), (1.5, 0.7, 0.3), (2.0, 0.7, -0.4),
                          (3.0, 0.4, 0.45), (4.0, 0.25, -0.15), (6.0, 0.1, 0.2)):
        f = round(f0 * razon * seg) / seg  # ciclos enteros por bucle → costura exacta
        bat = round(g.uniform(0.12, 0.4) * seg) / seg  # batido lento entre dos voces
        x = np.sin(DOS_PI * f * t + g.uniform(0, DOS_PI)) + 0.8 * np.sin(DOS_PI * (f + bat) * t + g.uniform(0, DOS_PI))
        mov = 0.35 * np.sin(DOS_PI * round(g.uniform(0.04, 0.1) * seg) / seg * t + g.uniform(0, DOS_PI))
        y += pan(amp * x, p + mov)
    y *= late
    y /= rms(y)
    halo = ruido_st(n, g, 2200, 5200, orden=3, ancho=0.7) * late ** 3
    halo = halo * np.clip(1.0 + 0.3 * lento(n, g, 0.5, 4.0), 0.3, None)
    des = np.zeros((2, n))
    notas = (74, 77, 79, 81, 84, 86, 89, 91)  # Re menor pentatónica, de Re5 a Sol6
    tt = g.uniform(0.3, 1.2)
    previa = None
    while tt < seg - 0.2:
        m = int(g.choice([x for x in notas if x != previa]))
        previa = m
        x = campana(midi(m), 1.6, tau=g.uniform(0.25, 0.5), ataque=0.006, parciales=PARC_CRISTAL)
        poner(des, x, tt, g.uniform(0.25, 1.0), g.uniform(-0.8, 0.8), circular=True)
        tt += g.uniform(0.7, 2.2)
    des = reverb(des, g, t60=2.4, mezcla=0.7, circular=True, agudos=6000)
    return y + 0.03 * halo + 0.36 * des


def amb_brasero(n):
    """Fuego de brasero: retumbo grave, rugido medio y crepitar. Casi todo va al centro (mono)."""
    g = gen("amb_brasero")
    seg = n / SR
    retumbo = ruido(n, g, 50, 220, color=2.0) * np.clip(1.0 + 0.45 * lento(n, g, 0.4, 5.0), 0.2, None)
    rugido = ruido(n, g, 150, 1400, color=1.5) * np.clip(1.0 + 0.55 * lento(n, g, 2.0, 14.0), 0.1, None)
    lado = ruido(n, g, 300, 2500, color=1.5) * np.clip(1.0 + 0.5 * lento(n, g, 2.0, 12.0), 0.1, None)
    siseo = ruido(n, g, 2000, 6500, color=1.0) * np.clip(0.6 + 0.5 * lento(n, g, 1.0, 9.0), 0.0, None)
    centro = 0.6 * retumbo + 0.9 * rugido + 0.10 * siseo
    y = np.stack([centro + 0.25 * lado, centro - 0.25 * lado])
    chasq = np.zeros((2, n))
    for _ in range(int(round(9 * seg))):
        t0 = g.uniform(0.0, seg)
        amp = min(0.7, 0.25 * float(np.exp(g.normal(0.0, 0.6))))
        d = g.uniform(0.004, 0.02)
        fc = g.uniform(1200.0, 5500.0)
        p = g.uniform(-0.3, 0.3)
        poner(chasq, rafaga(d, g, 0.6 * fc, 1.5 * fc, tau=d / 4.0, ataque=0.0005), t0, amp, p, circular=True)
        if amp > 0.45:  # las chispas fuertes llevan un «toc» de leña
            poner(chasq, np.sin(DOS_PI * fc / 6.0 * t_(n_(0.03))) * env_perc(n_(0.03), 0.008), t0, 0.6 * amp, p,
                  circular=True)
    return y + 1.9 * chasq


# --------------------------------------------------------------------------------------
# Tabla de bucles
# --------------------------------------------------------------------------------------
# (id, función, cuadros MP3 del cuerpo, pasa-altos Hz, pasa-bajos Hz, qué es, capas)
BUCLES = (
    ("amb_selva", amb_selva, 1152, 45.0, 9000.0,
     "Base de selva de día, sin cantos protagonistas. Suena siempre de fondo.",
     "aire grave (70–600 Hz); hojas en cuatro copas (1.3–7 kHz) con rachas independientes; "
     "zumbido lejano de insectos en tres bandas estrechas (3.1, 4.3 y 5.9 kHz) con trémolo"),
    ("amb_aves", amb_aves, 1050, 250.0, 8500.0,
     "Aves de selva: cantos variados repartidos en el estéreo, con distancia.",
     "unos doce cantos de diez tipos inventados (silbos, trinos, gorjeo, arrullo, llamada en eco, "
     "ululo, píos, carraca, flauteo), cada uno con tono, rapidez, distancia y lado al azar; eco de "
     "follaje y sala; lecho muy tenue de bandada lejana"),
    ("amb_insectos", amb_insectos, 960, 1500.0, 9500.0,
     "Chicharras y grillos: texturas agudas con trémolo, que suben y bajan.",
     "cuatro chicharras (ruido en banda de 4.3 a 7.1 kHz, trémolo de 34–58 pulsos/s, oleadas "
     "lentas); cinco grillos (chirridos tonales de 3.7–5.2 kHz que entran y salen)"),
    ("amb_viento", amb_viento, 1200, 40.0, 7000.0,
     "Viento entre árboles y ruinas: ráfagas lentas, sin silbido.",
     "ruido de banda móvil (230–800 Hz según la fuerza de la ráfaga) en centro y lados, con la "
     "ráfaga cruzando de un lado a otro; dos resonancias huecas (236 y 352 Hz) en las ráfagas "
     "fuertes; hojas altas; fondo grave"),
    ("amb_agua", amb_agua, 900, 90.0, 9000.0,
     "Arroyo / agua corriente cercana.",
     "murmullo en siete bandas (350 Hz–7.5 kHz) que borbotean por separado; gorgoteo grave "
     "(110–420 Hz); unas 600 burbujas (silbidos ascendentes de 12–50 ms)"),
    ("amb_cenote", amb_cenote, 1225, 40.0, 7000.0,
     "Interior de cenote: gotas con eco largo, agua profunda, resonancia de caverna.",
     "aire de caverna (50–320 Hz); resonancias graves sobre Re y La (73, 110, 147 y 196 Hz); agua "
     "profunda que lame despacio; unas trece gotas con dos ecos de pared y sala de 3.6 s"),
    ("amb_ruinas", amb_ruinas, 1080, 30.0, 6000.0,
     "Patio de piedra antiguo: tono de aire grave, resonancia hueca, alguna piedrecilla.",
     "aire grave (32–170 Hz); cuatro resonancias huecas (92, 138, 207 y 311 Hz) que respiran; "
     "soplo medio muy tenue; dos piedrecillas por bucle (una que rebota y otra que apenas cae)"),
    ("amb_tormenta", amb_tormenta, 1024, 35.0, 9000.0,
     "Tormenta tropical: lluvia sobre hojas y truenos lejanos poco frecuentes.",
     "siseo de lluvia (0.7–9.5 kHz); miles de gotas en tres tamaños; goterones sobre hojas grandes; "
     "rumor grave; dos truenos lejanos distintos por bucle (uno más presente, otro muy lejos)"),
    ("amb_energia", amb_energia, 864, 55.0, 8000.0,
     "Energía mística (sello, cristal, altares): zumbido armónico que late, destellos vítreos.",
     "siete parciales sobre Re3 (dos voces cada uno, que baten) con latido de ~0.45 Hz y "
     "panorámica lenta; halo agudo que late; destellos de cristal en Re menor pentatónica con sala"),
    ("amb_brasero", amb_brasero, 384, 45.0, 8500.0,
     "Fuego de brasero: crepitar y rugido suave. Se usa posicional: funciona en mono.",
     "retumbo (50–220 Hz) y rugido (150–1400 Hz) al centro; rugido lateral tenue; siseo; unos 90 "
     "chasquidos con panorámica estrecha"),
)
IDS = [b[0] for b in BUCLES]


def acabar_bucle(x, graves, agudos, lufs_obj=LUFS_OBJ, techo_db=TECHO):
    """Filtra de forma circular, quita la continua, ajusta la sonoridad y limita los picos."""
    x = filtrar(x, graves, None, orden=2, circular=True)
    x = filtrar(x, None, agudos, orden=4, circular=True)
    x = x - np.mean(x, axis=-1, keepdims=True)
    for _ in range(3):
        x = x * lin(lufs_obj - lufs(x))
        x = limitar(x, lin(techo_db), circular=True)
    return x


def con_margenes(cuerpo):
    """[pre][cuerpo][post]: medio segundo del final delante y medio del principio detrás."""
    h = n_(MARGEN)
    return np.concatenate([cuerpo[:, -h:], cuerpo, cuerpo[:, :h]], axis=-1)


def generar(ids, tmp: Path, dir_esp: Path | None) -> None:
    SALIDA.mkdir(parents=True, exist_ok=True)
    ruta_json = SALIDA / "ambiente.json"
    pistas = {}
    if ruta_json.exists():
        pistas = json.loads(ruta_json.read_text(encoding="utf-8")).get("tracks", {})
    for nombre, fn, cuadros, graves, agudos, _que, _capas in BUCLES:
        if nombre not in ids:
            continue
        n = cuadros * CUADRO_MP3
        cuerpo = acabar_bucle(fn(n), graves, agudos)
        wav, mp3 = tmp / f"{nombre}.wav", SALIDA / f"{nombre}.mp3"
        for _ in range(4):  # el MP3 cambia algo la sonoridad y los picos: se corrige midiendo el resultado
            escribir_wav(wav, con_margenes(cuerpo))
            codificar_mp3(wav, mp3, CALIDAD)
            m = medir(mp3)
            falta = LUFS_OBJ - m["lufs"]
            sobra = m["peak_db"] - (PICO_MAX - 0.8)
            if abs(falta) <= 0.25 and sobra <= 0.0:
                break
            cuerpo = cuerpo * lin(falta)
            if sobra > 0.0:
                cuerpo = limitar(cuerpo, lin(TECHO - sobra), circular=True)
        largo = n / SR
        pistas[nombre] = {
            "file": mp3.name, "bus": "Ambience",
            "loop": [MARGEN, round(MARGEN + largo, 6)],
            "seconds": round(m["seconds"], 3), "bytes": m["bytes"],
            "lufs": round(m["lufs"], 1), "peak_db": round(m["peak_db"], 1),
        }
        print(f"  {nombre}: {m['seconds']:.2f} s, {m['bytes']} bytes, {m['lufs']:.1f} LUFS, pico {m['peak_db']:.1f} dBFS")
        if dir_esp is not None:
            dir_esp.mkdir(parents=True, exist_ok=True)
            espectrograma(mp3, dir_esp / f"{nombre}.png")
    escribir_json(ruta_json, {"version": 1, "tracks": {k: pistas[k] for k in IDS if k in pistas}})
    actualizar_manifiesto("ambiente", [
        {"id": nombre, "archivo": f"game/web/static/audio/{nombre}.mp3", "tipo": "ambiente", "bus": "Ambience",
         "duracion_s": pistas[nombre]["seconds"], "bytes": pistas[nombre]["bytes"],
         "origen": f"síntesis propia: art/audio/gen_ambiente.py, función {fn.__name__}",
         "licencia": LICENCIA, "semilla": semilla_de(nombre)}
        for nombre, fn, *_ in BUCLES if nombre in pistas])


def comprobar() -> int:
    """Mide los MP3 en disco y devuelve el número de fallos."""
    ruta_json = SALIDA / "ambiente.json"
    if not ruta_json.exists():
        print("FALTA ambiente.json")
        return 1
    pistas = json.loads(ruta_json.read_text(encoding="utf-8")).get("tracks", {})
    fallos_tot = 0
    total = 0
    print(f"{'archivo':<14}{'seg':>7}{'bucle':>7}{'bytes':>8}{'LUFS':>7}{'pico':>7}{'I·D':>6}{'DC':>9}"
          f"{'corr':>8}{'salto':>9}{'típico':>9}  <200 -1k -4k -8k >8k  resultado")
    for nombre in IDS:
        mp3 = SALIDA / f"{nombre}.mp3"
        if not mp3.exists() or nombre not in pistas:
            print(f"{nombre:<14} FALTA")
            fallos_tot += 1
            continue
        p = pistas[nombre]
        m = medir(mp3)
        x = m["x"]
        total += m["bytes"]
        fallos = []
        ini, fin = p["loop"]
        largo = fin - ini
        corto = nombre == "amb_brasero"
        if not ((8.0 <= largo <= 12.0) if corto else (20.0 <= largo <= 32.0)):
            fallos.append(f"bucle de {largo:.1f} s")
        if abs(ini - MARGEN) > 1e-9 or abs(m["seconds"] - (largo + 2 * MARGEN)) > 0.03:
            fallos.append("duración≠pre+bucle+post")
        if abs(round(largo * SR) % CUADRO_MP3) != 0:
            fallos.append("bucle no alineado a cuadros")
        if m["bytes"] > BYTES_MAX:
            fallos.append(f">{BYTES_MAX // 1000} KB")
        if not LUFS_MIN <= m["lufs"] <= LUFS_MAX:
            fallos.append("LUFS fuera de rango")
        if m["peak_db"] > PICO_MAX:
            fallos.append(f"pico>{PICO_MAX:.0f} dBFS")
        if m["dc"] > 5e-4:
            fallos.append("continua")
        if m["corr"] < (0.6 if corto else 0.0):
            fallos.append("mal en mono")
        if m["bandas"][4] > 20.0:
            fallos.append("mucho >8 kHz")
        # Costura: lo que suena tras loop[1] debe ser lo mismo que tras loop[0], también si el
        # decodificador no recorta el retardo del codificador (se prueba con varios desfases).
        v = n_(0.05)
        corr_min = 1.0
        salto_max = 0.0
        dif = np.abs(np.diff(x, axis=-1))
        tipico = float(np.percentile(dif, 99.9))
        for des in (0, 529, 1105, 2257):
            i0, i1 = int(round(ini * SR)) + des, int(round(fin * SR)) + des
            a, b = x[:, i0:i0 + v].ravel(), x[:, i1:i1 + v].ravel()
            if len(b) < 2 * v:
                corr_min = 0.0
                continue
            corr_min = min(corr_min, float(np.corrcoef(a, b)[0, 1]))
            salto_max = max(salto_max, float(np.max(np.abs(x[:, i0] - x[:, i1 - 1]))))
        if corr_min <= CORR_BUCLE:
            fallos.append(f"costura corr {corr_min:.3f}")
        if salto_max > tipico:
            fallos.append("escalón en la costura")
        if (p["file"] != mp3.name or p["bus"] != "Ambience" or p["bytes"] != m["bytes"]
                or abs(p["seconds"] - m["seconds"]) > 0.01 or abs(p["lufs"] - m["lufs"]) > 0.15
                or abs(p["peak_db"] - m["peak_db"]) > 0.15):
            fallos.append("manifiesto desfasado")
        fallos_tot += len(fallos)
        b = m["bandas"]
        print(f"{nombre:<14}{m['seconds']:>7.2f}{largo:>7.2f}{m['bytes']:>8}{m['lufs']:>7.1f}{m['peak_db']:>7.1f}"
              f"{m['corr']:>6.2f}{m['dc']:>9.5f}{corr_min:>8.4f}{salto_max:>9.5f}{tipico:>9.5f}"
              f"  {b[0]:>4.0f}{b[1]:>4.0f}{b[2]:>4.0f}{b[3]:>4.0f}{b[4]:>4.0f}  {', '.join(fallos) if fallos else 'ok'}")
    print(f"\nTotal ambientes: {total} bytes = {total / 1e6:.3f} MB (límite {TOTAL_MAX / 1e6:.1f} MB)")
    if total > TOTAL_MAX:
        print("FALLO: se supera el presupuesto total")
        fallos_tot += 1
    extra = set(pistas) - set(IDS)
    if extra:
        print(f"FALLO: pistas de más en el manifiesto: {sorted(extra)}")
        fallos_tot += 1
    print("RESULTADO:", "ok" if not fallos_tot else f"{fallos_tot} fallo(s)")
    return fallos_tot


def main() -> int:
    ap = argparse.ArgumentParser(description="Genera y comprueba los bucles de ambiente de ALUX.")
    ap.add_argument("--check", action="store_true", help="solo comprobar los archivos existentes")
    ap.add_argument("--solo", default="", help="ids separados por comas (por defecto, todos)")
    ap.add_argument("--espectros", type=Path, default=None, help="carpeta donde dejar espectrogramas PNG")
    a = ap.parse_args()
    if not a.check:
        ids = [s for s in a.solo.split(",") if s] or IDS
        desconocidos = set(ids) - set(IDS)
        if desconocidos:
            print(f"ids desconocidos: {sorted(desconocidos)}")
            return 2
        print(f"Generando {len(ids)} bucle(s) (semilla base {SEMILLA})…")
        generar(ids, carpeta_tmp(), a.espectros)
    return 1 if comprobar() else 0


if __name__ == "__main__":
    sys.exit(main())
