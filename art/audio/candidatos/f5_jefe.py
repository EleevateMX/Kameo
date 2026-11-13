#!/usr/bin/env python3
"""Frente 5: golpes y movimientos de Nojoch Tuunich.

Los efectos actuales ponen el peso en un barrido de seno que baja hasta 30–45 Hz y en ruido
de 45–300 Hz: en un portátil o un móvil eso no suena, y lo que queda (el golpe de ruido medio)
es parecido en la pisada y en la losa. Aquí el peso se cuenta con tres capas que sí se oyen en
un altavoz pequeño:

  - ataque de roca: chasquido de 1–4.5 kHz (ráfaga de pocos milisegundos y modos cortos de piedra);
  - cuerpo: modos amortiguados de 100–300 Hz (no un barrido hacia el subgrave) y golpe de
    ruido en la misma banda;
  - cola: cascotes, polvo y, en los golpes grandes, la losa o la columna que siguen sonando.

Y cada movimiento tiene su perfil: la pisada es un solo golpe compacto y apagado; la losa, un
chasquido brillante con rebote, placa que resuena y cola larga; el barrido no tiene golpe (un
arco de roce que sube y baja); la embestida son zancadas que se aceleran sobre un arrastre que
crece y acaba en su punto más fuerte.

Dos candidatos por sonido:
  A «seco»  : sin sala ni subgrave, colas cortas, más chasquido. Misma duración que el actual.
  B «grande»: cuerpo más largo, algo de subgrave debajo, más cascotes y sala; dura algo más.
"""

from __future__ import annotations

import numpy as np

import _dsp_estereo as D
from comun import (
    SR, env_perc, fase_de, glis, modos, n_, poner, rafaga, rampa, reverb, ruido, ruido_barrido, salida,
    saturar, t_, tirones,
)

CORTES = (0, 100, 300, 1000, 4000, 1e9)


def chasq(g, lo=1000.0, hi=4500.0, tau=0.006, f_modos=(1300.0, 2100.0, 3300.0), gan_modos=0.6):
    """Chasquido de roca: ráfaga de ruido de 1–4.5 kHz y tres modos cortos de piedra."""
    y = np.zeros(n_(0.10))
    poner(y, rafaga(0.07, g, lo, hi, tau=tau, ataque=0.0004), 0.0, 1.0)
    lista = tuple((f * g.uniform(0.93, 1.07), a, t) for f, a, t in zip(f_modos, (1.0, 0.7, 0.4), (0.012, 0.008, 0.005)))
    poner(y, modos(lista, 0.08), 0.0, gan_modos)
    return y


def cuerpo(g, f=(118.0, 176.0, 243.0), tau=0.09, cae=0.06, gan_ruido=1.0):
    """Cuerpo del golpe en 100–300 Hz: tres modos amortiguados que ceden un poco de tono y un
    golpe de ruido en la misma banda, que dura lo mismo (así no suena a tambor afinado). No
    baja al subgrave."""
    n = n_(7.0 * tau)
    t = t_(n)
    y = np.zeros(n)
    for i, fi in enumerate(f):
        w = fase_de(fi * (1.0 + cae * np.exp(-t / 0.03)))
        y += (1.0, 0.8, 0.6)[i] * np.sin(w + 0.9 * i) * np.exp(-t / (0.6 * tau * (1.0 - 0.2 * i)))
    y += gan_ruido * ruido(n, g, 90.0, 340.0, color=1.0) * np.exp(-t / tau)
    return y * rampa(n, 0.002) * salida(n, 0.01)


def medio(g, seg=0.2, tau=0.03, lo=250.0, hi=1200.0):
    """El «toc» medio del golpe (ruido de 250–1200 Hz)."""
    return rafaga(seg, g, lo, hi, tau=tau, color=1.0)


def sub(f0, f1, seg, tau):
    """Subgrave que cede (solo en los candidatos «grandes», y bajo)."""
    return glis(f0, f1, seg) * env_perc(n_(seg), tau, 0.004)


def polvo(y, g, t0, seg, tau, gan=0.12):
    poner(y, ruido(n_(seg), g, 900.0, 4000.0, color=1.0) * env_perc(n_(seg), tau, 0.06), t0, gan)


def sala(y, g, t60, mezcla):
    return reverb(y, g, t60=t60, mezcla=mezcla, agudos=4500.0, graves=120.0)


def paso(g, grande):
    """Pisada: un solo golpe compacto y apagado, con poca grava."""
    y = np.zeros(n_(0.7))
    poner(y, cuerpo(g, (125.0, 190.0, 265.0), tau=0.10 if grande else 0.06), 0.0, 1.0)
    poner(y, medio(g, 0.15, 0.025, 250.0, 1100.0), 0.0, 1.1)
    poner(y, chasq(g, 1200.0, 3500.0, tau=0.004), 0.0, 0.65 if grande else 0.9)
    D.escombros(y, g, 0.06, 0.45 if grande else 0.30, 8 if grande else 5, lo=700.0, hi=2600.0, gan=0.22)
    if grande:
        poner(y, sub(70.0, 42.0, 0.3, 0.09), 0.0, 0.35)
        y = sala(y, g, 0.6, 0.15)
    return saturar(y, 1.5)


def losa(g, grande):
    """Golpe de losa: chasquido brillante, placa que resuena, rebote y cola larga de escombros."""
    y = np.zeros(n_(1.7))
    k = 1.6 if grande else 1.0
    poner(y, chasq(g, 800.0, 5000.0, tau=0.012, f_modos=(1100.0, 1900.0, 3100.0)), 0.0, 1.25)
    poner(y, modos(((310.0, 1.0, 0.07 * k), (455.0, 0.8, 0.09 * k), (690.0, 0.6, 0.06 * k), (1040.0, 0.4, 0.04 * k)), 0.7), 0.0, 1.0)
    poner(y, cuerpo(g, (105.0, 150.0, 215.0), tau=0.26 if grande else 0.16), 0.0, 1.0)
    poner(y, medio(g, 0.4, 0.08, 200.0, 900.0), 0.0, 0.9)
    poner(y, cuerpo(g, (112.0, 160.0, 228.0), tau=0.08), 0.11, 0.45)  # la losa rebota
    poner(y, chasq(g, 900.0, 4000.0, tau=0.008), 0.11, 0.40)
    D.escombros(y, g, 0.10, 1.5 if grande else 1.0, 38 if grande else 26, lo=450.0, hi=2800.0, gan=0.8, graves=0.3)
    polvo(y, g, 0.05, 1.0, 0.40 if grande else 0.22)
    if grande:
        poner(y, sub(62.0, 34.0, 0.9, 0.30), 0.0, 0.45)
        y = sala(y, g, 1.1, 0.22)
    return saturar(y, 3.0)


def barrido(g, grande):
    """Barrido: no hay golpe. Un arco de roce de piedra que sube y baja, con aire y masa debajo."""
    seg = 1.15 if grande else 0.88
    n = n_(seg)
    u = np.arange(n) / n
    arco = np.sin(np.pi * u ** 0.8)
    roce = ruido_barrido(n, g, 300.0 * (1100.0 / 300.0) ** arco, ancho=0.6, color=1.0, f_min=150.0, f_max=5000.0)
    roce *= tirones(n, g, 14.0, 55.0, 1.3)
    aire = ruido_barrido(n, g, 500.0 * (2200.0 / 500.0) ** arco, ancho=0.9, color=1.5)
    masa = ruido(n, g, 110.0, 300.0, color=1.0) * (0.6 + 0.4 * tirones(n, g, 5.0, 16.0, 1.0))
    w = fase_de(130.0 * 2.0 ** (0.4 * arco))
    y = (roce + 0.25 * aire + 0.8 * masa + 0.35 * (np.sin(w) + 0.5 * np.sin(2 * w))) * arco ** (1.5 if grande else 2.0)
    poner(y, D.crujidos(0.8 * seg, g, 14, banda=(1500.0, 4000.0)) * arco[:n_(0.8 * seg)], 0.05, 0.12)
    if grande:
        y += 0.5 * ruido(n, g, 55.0, 130.0, color=2.0) * arco ** 1.5
        y = sala(y, g, 0.9, 0.20)
    return saturar(y, 1.6)


def embestida(g, grande):
    """Embestida: zancadas que se aceleran (de 4 a 11 por segundo) sobre un arrastre que crece.
    Acaba en su punto más fuerte, para enlazar con el choque."""
    seg = 1.4
    n = n_(seg)
    u = np.arange(n) / n
    y = np.zeros(n + n_(0.3))
    fase = np.cumsum(4.0 + 7.5 * u ** 1.2) / SR + 0.6
    for i in np.nonzero(np.diff(np.floor(fase)) > 0)[0]:
        ts = i / SR
        k = g.uniform(0.92, 1.08)
        gan = 0.22 + 0.78 * (ts / seg) ** 1.2
        poner(y, cuerpo(g, (120.0 * k, 180.0 * k, 250.0 * k), tau=0.06 if grande else 0.04), ts, gan)
        poner(y, medio(g, 0.08, 0.02, 300.0, 1200.0), ts, 0.5 * gan)
        poner(y, chasq(g, 1200.0, 4000.0, tau=0.004), ts, 0.38 * gan)
    arrastre = ruido_barrido(n, g, 250.0 * (1100.0 / 250.0) ** u, ancho=0.8, color=1.3, f_min=120.0, f_max=4000.0)
    y[:n] += 0.7 * arrastre * tirones(n, g, 10.0, 45.0, 1.6) * (0.2 + 0.8 * u ** 1.3)
    if grande:
        y[:n] += 0.5 * ruido(n, g, 55.0, 160.0, color=2.0) * (0.2 + 0.8 * u ** 1.3)
        y = sala(y, g, 0.7, 0.15)
    return y[:n]


def choque(g, grande):
    """Choque contra una columna: golpe, la columna que se parte en tres chasquidos y cae a trozos."""
    y = np.zeros(n_(1.9))
    poner(y, cuerpo(g, (135.0, 200.0, 280.0), tau=0.20 if grande else 0.12), 0.0, 0.95)
    poner(y, medio(g, 0.3, 0.05, 250.0, 1500.0), 0.0, 0.8)
    for t0, gan in ((0.0, 1.0), (0.018, 0.7), (0.045, 0.55)):  # la columna se parte
        poner(y, chasq(g, 900.0, 6000.0, tau=0.014, f_modos=(1500.0, 2500.0, 3900.0)), t0, gan)
    poner(y, modos(((520.0, 0.5, 0.07), (835.0, 0.4, 0.05), (1310.0, 0.3, 0.035), (2140.0, 0.15, 0.02)), 0.3), 0.004, 0.8)
    for t0, f0, gan in ((0.30, 120.0, 0.55), (0.52, 98.0, 0.45), (0.78, 140.0, 0.30), (0.96, 110.0, 0.18)):  # trozos
        tt = t0 + g.uniform(-0.02, 0.02)
        poner(y, cuerpo(g, (1.2 * f0, 1.8 * f0, 2.5 * f0), tau=0.05), tt, gan)
        poner(y, chasq(g, 1000.0, 3500.0, tau=0.005), tt, 0.35 * gan)
    D.escombros(y, g, 0.06, 1.7 if grande else 1.2, 46 if grande else 34, lo=500.0, hi=3200.0, gan=0.85, graves=0.2)
    polvo(y, g, 0.05, 1.1, 0.45 if grande else 0.30)
    if grande:
        poner(y, sub(66.0, 36.0, 0.8, 0.26), 0.0, 0.4)
        y = sala(y, g, 1.1, 0.20)
    return saturar(y, 2.6)


def cae(g, grande):
    """Cae de rodillas: dos golpes (una rodilla y la otra), quejido de roca que se hunde y escombros."""
    y = np.zeros(n_(2.0))
    for t0, k, gan in ((0.0, 1.0, 1.0), (0.24, 0.9, 0.85)):
        poner(y, cuerpo(g, (112.0 * k, 165.0 * k, 230.0 * k), tau=0.24 if grande else 0.15), t0, 0.95 * gan)
        poner(y, medio(g, 0.4, 0.08, 200.0, 900.0), t0, 0.95 * gan)
        poner(y, chasq(g, 900.0, 4500.0, tau=0.010), t0, 1.0 * gan)
    m = n_(0.9)
    v = np.arange(m) / m  # el quejido va una octava por encima del actual (84→46 Hz) para que se oiga
    poner(y, D.gemido(m, g, 168.0 * (92.0 / 168.0) ** (v ** 0.7)) * rampa(m, 0.05) * (1.0 - v) ** 0.8, 0.30, 0.34)
    D.escombros(y, g, 0.08, 1.8 if grande else 1.3, 42 if grande else 30, lo=450.0, hi=2600.0, gan=0.75, graves=0.3)
    polvo(y, g, 0.05, 1.2, 0.5 if grande else 0.35)
    if grande:
        poner(y, sub(58.0, 30.0, 0.8, 0.28), 0.0, 0.45)
        poner(y, sub(52.0, 29.0, 0.7, 0.25), 0.24, 0.38)
        y = sala(y, g, 1.2, 0.22)
    return saturar(y, 3.0)


def despierta(g, grande):
    """El coloso despierta: grietas que se agolpan, la roca que ruge al moverse y el bloque que encaja."""
    seg = 3.5
    n = n_(seg)
    t = t_(n)
    y = np.zeros(n + n_(0.6))
    poner(y, D.crujidos(1.75, g, 60, crece=0.9), 0.0, 0.85)
    for t0, gan in ((0.0, 0.65), (0.34, 0.5), (0.66, 0.8), (1.08, 1.0), (1.44, 1.3)):
        poner(y, D.chasquido(g, gan, grave=g.uniform(130.0, 170.0)), t0)
    env = np.clip((t - 0.9) / 1.3, 0.0, 1.0) ** 1.6 * np.clip((seg - 0.1 - t) / 1.1, 0.0, 1.0) ** 1.2
    y[:n] += 0.50 * ruido(n, g, 120.0, 1400.0, color=1.0) * tirones(n, g, 5.0, 26.0) * env
    m = n_(2.4)
    u = np.arange(m) / m  # el rugido de roca, una octava por encima del actual (56–92 Hz)
    poner(y, D.gemido(m, g, 112.0 + 72.0 * np.sin(np.pi * u) ** 1.5, tope=1400.0) * np.sin(np.pi * u) ** 1.2, 0.95, 0.42)
    poner(y, cuerpo(g, (115.0, 170.0, 240.0), tau=0.14), 2.55, 0.5)
    poner(y, chasq(g, 1000.0, 3500.0, tau=0.006), 2.55, 0.25)
    D.escombros(y, g, 2.62, 3.4, 16, gan=0.16, graves=0.2)
    if grande:
        y[:n] += 0.22 * ruido(n, g, 40.0, 140.0, color=2.0) * env
        poner(y, sub(60.0, 34.0, 0.6, 0.18), 2.55, 0.25)
        return saturar(sala(y, g, 1.3, 0.25), 1.8)
    return saturar(sala(y, g, 0.5, 0.10), 1.8)


# (frente, duración, corte de agudos, fundido final, candidatos). El corte de agudos es 6.5 kHz en
# todos (la pisada actual corta en 4.5 kHz y la embestida en 6 kHz): el chasquido lo necesita.
SONIDOS = (
    ("jefe_paso", 0.50, 6500.0, 0.12, (
        ("A_seco", lambda g: paso(g, False), "golpe compacto: cuerpo de 125–265 Hz, chasquido corto, cinco piedras"),
        ("B_grande", lambda g: paso(g, True), "cuerpo más largo, subgrave bajo, más grava y sala corta", 0.65))),
    ("jefe_losa", 1.20, 6500.0, 0.25, (
        ("A_seco", lambda g: losa(g, False), "chasquido brillante, placa que resuena, rebote a 0.11 s y escombros hasta 1.0 s"),
        ("B_grande", lambda g: losa(g, True), "placa y cuerpo más largos, subgrave, 38 cascotes y sala de 1.1 s", 1.60))),
    ("jefe_barrido", 0.90, 6500.0, 0.08, (
        ("A_seco", lambda g: barrido(g, False), "arco de roce a tirones (300→1100→300 Hz), aire y masa de 110–300 Hz; sin golpe"),
        ("B_grande", lambda g: barrido(g, True), "arco más largo y ancho, rumor grave y sala", 1.25))),
    ("jefe_embestida", 1.40, 6500.0, 0.05, (
        ("A_seco", lambda g: embestida(g, False), "zancadas con chasquido que se aceleran sobre un arrastre que sube; acaba fuerte"),
        ("B_grande", lambda g: embestida(g, True), "zancadas con más cuerpo, rumor grave y algo de sala; misma duración"))),
    ("jefe_choque", 1.30, 6500.0, 0.30, (
        ("A_seco", lambda g: choque(g, False), "golpe, la columna se parte en tres chasquidos, cuatro trozos y escombros"),
        ("B_grande", lambda g: choque(g, True), "más cuerpo, subgrave, 46 cascotes y sala de 1.1 s", 1.80))),
    ("jefe_cae", 1.40, 6500.0, 0.30, (
        ("A_seco", lambda g: cae(g, False), "dos golpes de rodilla con chasquido, quejido una octava más alto y escombros"),
        ("B_grande", lambda g: cae(g, True), "golpes más largos con subgrave, más escombros y sala de 1.2 s", 1.90))),
    ("jefe_despierta", 3.50, 6500.0, 0.35, (
        ("A_seco", lambda g: despierta(g, False), "grietas, rugido de roca una octava más alto (112–184 Hz) y asiento con cuerpo medio"),
        ("B_grande", lambda g: despierta(g, True), "lo mismo con el rumor grave del actual debajo y sala de 1.3 s", 3.90))),
)
