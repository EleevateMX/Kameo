#!/usr/bin/env python3
"""Audio provisional de ALUX, sintetizado por código.

Genera todos los `.wav` de `game/assets/audio/` (mono, 22050 Hz, 16 bits PCM) solo con
numpy y el módulo `wave` de la biblioteca estándar. No usa grabaciones ni muestras de
nadie: todo sale de senos, ruido filtrado y envolventes, con semillas fijas, así que el
resultado es original, libre de licencias y reproducible byte a byte.

Uso:
    python art/audio/gen_audio.py              # genera todo y lo comprueba
    python art/audio/gen_audio.py --check      # solo comprueba lo que hay en disco
    python art/audio/gen_audio.py --compacto   # variante corta (≤ 2.2 MB), ver README
    python art/audio/gen_audio.py --salida DIR # escribe en otra carpeta
"""

from __future__ import annotations

import argparse
import hashlib
import sys
import wave
import zlib
from pathlib import Path

import numpy as np

SR = 22050  # frecuencia de muestreo
SEMILLA = 20261111  # semilla base; cada sonido deriva la suya de su nombre
DOS_PI = 2.0 * np.pi
RAIZ = Path(__file__).resolve().parents[2]
SALIDA = RAIZ / "game" / "assets" / "audio"
LIMITE_BYTES = 2.2e6  # presupuesto pedido para el total (2.2 MB)


# --------------------------------------------------------------------------------------
# Utilidades básicas
# --------------------------------------------------------------------------------------

def gen(nombre: str) -> np.random.Generator:
    """Generador aleatorio propio de cada sonido (independiente del orden de ejecución)."""
    return np.random.default_rng([SEMILLA, zlib.crc32(nombre.encode("utf-8"))])


def n_(seg: float) -> int:
    """Segundos → número de muestras."""
    return int(round(seg * SR))


def t_(n: int) -> np.ndarray:
    """Eje de tiempo en segundos para n muestras."""
    return np.arange(n) / SR


def midi(m: float) -> float:
    """Nota MIDI → Hz (La4 = 69 = 440 Hz)."""
    return 440.0 * 2.0 ** ((m - 69) / 12.0)


def db(x: float) -> float:
    return 20.0 * np.log10(max(float(x), 1e-12))


def rms(x: np.ndarray) -> float:
    return float(np.sqrt(np.mean(np.square(x)))) if len(x) else 0.0


def rampa(n: int, seg: float) -> np.ndarray:
    """Entrada suave (medio coseno) de `seg` segundos; después vale 1."""
    m = max(1, min(n, n_(seg)))
    e = np.ones(n)
    e[:m] = 0.5 - 0.5 * np.cos(np.pi * np.arange(m) / m)
    return e


def salida(n: int, seg: float) -> np.ndarray:
    """Salida suave (medio coseno) en los últimos `seg` segundos; acaba en 0 exacto."""
    m = max(2, min(n, n_(seg)))
    e = np.ones(n)
    e[n - m:] = 0.5 + 0.5 * np.cos(np.pi * np.arange(m) / (m - 1))
    return e


def env_perc(n: int, tau: float, ataque: float = 0.0015) -> np.ndarray:
    """Envolvente percusiva: ataque corto y caída exponencial con constante `tau`.

    Los últimos milisegundos bajan a cero para que el corte no deje un chasquido.
    """
    return rampa(n, ataque) * np.exp(-t_(n) / tau) * salida(n, min(0.004, n / SR / 4))


def env_asr(n: int, ataque: float, rel: float) -> np.ndarray:
    """Ataque, sostén y relajación (para colchones y flautas)."""
    return rampa(n, ataque) * salida(n, rel)


def _respuesta(f: np.ndarray, lo, hi, orden: int, color: float = 0.0) -> np.ndarray:
    """Módulo de un filtro tipo Butterworth (fase cero) con inclinación opcional.

    color = 1 da ruido rosa (-3 dB/octava); color = 2, ruido marrón (-6 dB/octava).
    """
    h = np.ones_like(f)
    fs = np.maximum(f, 1e-9)
    if color:
        h *= (np.maximum(f, 25.0) / 1000.0) ** (-0.5 * color)
    if lo:
        h *= 1.0 / np.sqrt(1.0 + (lo / fs) ** (2 * orden))
    if hi:
        h *= 1.0 / np.sqrt(1.0 + (f / hi) ** (2 * orden))
    return h


def filtrar(x, lo=None, hi=None, orden=2, circular=False):
    """Filtra en el dominio de la frecuencia.

    Con `circular=True` la señal se trata como periódica (lo que necesitan los bucles);
    si no, se rellena con ceros para que la cola no se enrolle sobre el principio.
    """
    n = len(x)
    m = 0 if circular else 1024
    if m:
        x = np.concatenate([np.zeros(m), x, np.zeros(m)])
    nn = len(x)
    h = _respuesta(np.fft.rfftfreq(nn, 1.0 / SR), lo, hi, orden)
    y = np.fft.irfft(np.fft.rfft(x) * h, nn)
    return y if circular else y[m:m + n]


def ruido(n, g, lo=None, hi=None, orden=2, color=0.0):
    """Ruido limitado en banda, con RMS 1. Es periódico en n, así que sirve para bucles."""
    esp = np.fft.rfft(g.standard_normal(n))
    h = _respuesta(np.fft.rfftfreq(n, 1.0 / SR), lo, hi, orden, color)
    h[0] = 0.0
    y = np.fft.irfft(esp * h, n)
    return y / (rms(y) + 1e-12)


def lento(n, g, lo, hi):
    """Modulador aleatorio lento (ruido de muy baja frecuencia, RMS 1)."""
    return ruido(n, g, lo, hi, orden=2)


def rafaga(seg, g, lo, hi, tau, ataque=0.001, color=0.0, orden=2):
    """Golpe de ruido filtrado con caída exponencial."""
    n = n_(seg)
    return ruido(n, g, lo, hi, orden, color) * env_perc(n, tau, ataque)


def ruido_barrido(n, g, fc, ancho=0.6, color=1.0, f_min=120.0, f_max=9000.0, bandas=14):
    """Ruido cuya banda se desplaza con el tiempo (soplidos, estelas).

    Se reparte un mismo ruido en bandas fijas (logarítmicas) y cada una se pondera con
    una campana centrada en `fc(t)`; `ancho` es la desviación en octavas.
    """
    f = np.fft.rfftfreq(n, 1.0 / SR)
    esp = np.fft.rfft(g.standard_normal(n))
    if color:
        esp = esp * (np.maximum(f, 25.0) / 1000.0) ** (-0.5 * color)
    lf = np.log2(np.maximum(f, 1.0))
    centros = np.linspace(np.log2(f_min), np.log2(f_max), bandas)
    paso = centros[1] - centros[0]
    lfc = np.log2(np.broadcast_to(np.asarray(fc, dtype=float), (n,)))
    y = np.zeros(n)
    for c in centros:
        banda = np.fft.irfft(esp * np.exp(-0.5 * ((lf - c) / (0.7 * paso)) ** 2), n)
        y += banda * np.exp(-0.5 * ((lfc - c) / ancho) ** 2)
    return y / (rms(y) + 1e-12)


def fase_de(f) -> np.ndarray:
    """Fase acumulada de una frecuencia variable (array en Hz)."""
    return DOS_PI * np.cumsum(f) / SR


def glis(f0, f1, seg):
    """Seno con barrido exponencial de f0 a f1."""
    n = n_(seg)
    u = np.arange(n) / n
    return np.sin(fase_de(f0 * (f1 / f0) ** u))


def poner(buf, x, t0, gan=1.0, circular=False):
    """Suma `x` en `buf` a partir del segundo t0. Con `circular`, la cola da la vuelta."""
    n = len(buf)
    i0 = int(round(t0 * SR))
    if circular:
        np.add.at(buf, (i0 + np.arange(len(x))) % n, gan * x)
    else:
        a, b = max(i0, 0), min(i0 + len(x), n)
        if b > a:
            buf[a:b] += gan * x[a - i0:b - i0]


def saturar(y, k=2.2):
    """Saturación suave de los picos (da peso a los golpes sin recortarlos en seco)."""
    return np.tanh(k * y / (np.max(np.abs(y)) + 1e-12)) / np.tanh(k)


def reverb(x, g, t60=0.8, mezcla=0.2, circular=False, agudos=3500.0, retardo=0.012):
    """Reverberación barata: convolución con ruido que decae exponencialmente.

    En modo circular la cola se enrolla (bucles). Si no, devuelve la señal alargada con
    la cola; quien llama recorta a la duración final.
    """
    m = n_(t60 * 1.1)
    ri = g.standard_normal(m) * np.exp(-6.9 * t_(m) / t60)
    ri = filtrar(ri, 180.0, agudos, orden=2) * rampa(m, 0.004)
    ri /= np.sqrt(np.sum(ri ** 2)) + 1e-12
    d = n_(retardo)
    if circular:
        n = len(x)
        ri_n = np.zeros(n)
        np.add.at(ri_n, (d + np.arange(m)) % n, ri)
        return x + mezcla * np.fft.irfft(np.fft.rfft(x) * np.fft.rfft(ri_n), n)
    n = len(x) + m + d
    seco = np.concatenate([x, np.zeros(m + d)])
    ri_n = np.zeros(n)
    ri_n[d:d + m] = ri
    return seco + mezcla * np.fft.irfft(np.fft.rfft(seco) * np.fft.rfft(ri_n), n)


# --------------------------------------------------------------------------------------
# Instrumentos
# --------------------------------------------------------------------------------------

def kalimba(f, seg, g, brillo=1.0):
    """Lengüeta tipo kalimba/marimba: seno + 4.º armónico con caída rápida y un toque."""
    tau = 0.55 * (261.6 / f) ** 0.5
    n = n_(min(seg, 5.0 * tau))
    t = t_(n)
    y = np.sin(DOS_PI * f * t) * np.exp(-t / tau)
    if 4 * f < 9000:
        y += 0.40 * brillo * np.sin(DOS_PI * 4 * f * t) * np.exp(-t / (0.28 * tau))
    if 6.3 * f < 9000:
        y += 0.07 * brillo * np.sin(DOS_PI * 6.3 * f * t) * np.exp(-t / (0.10 * tau))
    k = min(n, n_(0.02))
    y[:k] += 0.22 * brillo * ruido(k, g, 700, 3500) * np.exp(-t[:k] / 0.004)
    return y * rampa(n, 0.0015) * salida(n, 0.02)


def flauta(f, seg, g, vib=0.005, aire=0.08, ataque=0.07, rel=0.12, cae=0.0):
    """Ocarina/flauta de barro: seno casi puro, vibrato leve y soplo.

    `cae` baja el tono al final (en semitonos) para frases que «suspiran».
    """
    n = n_(seg)
    t = t_(n)
    u = np.arange(n) / n
    v = vib * np.sin(DOS_PI * 5.3 * t) * np.clip((t - 0.15) / 0.35, 0.0, 1.0)
    ff = f * (1.0 + v) * 2.0 ** (-cae * u ** 2 / 12.0)
    w = fase_de(ff)
    y = np.sin(w) + 0.22 * np.sin(2 * w) + 0.07 * np.sin(3 * w)
    soplo = ruido(n, g, 1.5 * f, min(6.0 * f, 6500.0)) * (1.0 + 2.0 * np.exp(-t / 0.05))
    return (y + aire * soplo) * env_asr(n, ataque, rel)


def colchon(f, seg, ataque, rel):
    """Colchón cálido: tres voces desafinadas de onda casi triangular, de entrada lenta."""
    n = n_(seg)
    t = t_(n)
    y = np.zeros(n)
    for desaf, fase in ((-0.004, 0.0), (0.0, 2.1), (0.004, 4.2)):
        w = DOS_PI * f * (1.0 + desaf) * t + fase
        y += np.sin(w) + np.sin(3 * w) / 9.0 + np.sin(5 * w) / 25.0
    return y / 3.0 * env_asr(n, ataque, rel)


def bajo(f, seg, tau=1.2):
    """Nota grave suave (seno con dos armónicos débiles)."""
    n = n_(seg)
    t = t_(n)
    w = DOS_PI * f * t
    y = np.sin(w) + 0.35 * np.sin(2 * w) + 0.10 * np.sin(3 * w)
    return y * rampa(n, 0.04) * np.exp(-t / tau) * salida(n, min(0.3, seg / 2))


def tambor(f0, seg, g, tau=0.12, barrido=0.6, t_barr=0.025, piel=0.3,
           banda=(300.0, 2500.0), tau_piel=0.012):
    """Tambor de mano: seno que baja de tono + ruido del golpe en el parche."""
    n = n_(seg)
    t = t_(n)
    w = fase_de(f0 * (1.0 + barrido * np.exp(-t / t_barr)))
    y = np.sin(w) * np.exp(-t / tau)
    y += piel * ruido(n, g, banda[0], banda[1], color=1.0) * np.exp(-t / tau_piel)
    return y * rampa(n, 0.001) * salida(n, min(0.03, seg / 3))


# Parciales de barra/campana: (razón de frecuencia, amplitud, factor de duración)
PARC_CAMPANA = ((1.0, 1.0, 1.0), (2.0, 0.45, 0.7), (3.01, 0.25, 0.5),
                (4.2, 0.16, 0.35), (5.43, 0.09, 0.25))


def campana(f, seg, tau=0.35, ataque=0.003, parciales=PARC_CAMPANA):
    """Campanita: parciales algo inarmónicos; los agudos se apagan antes."""
    n = n_(seg)
    t = t_(n)
    y = np.zeros(n)
    for razon, amp, kt in parciales:
        if f * razon < 9000:
            y += amp * np.sin(DOS_PI * f * razon * t + razon) * np.exp(-t / (tau * kt))
    return y * rampa(n, ataque) * salida(n, min(0.05, seg / 3))


def modos(lista, seg):
    """Resonancias de piedra/madera: senos amortiguados (frecuencia, amplitud, tau)."""
    n = n_(seg)
    t = t_(n)
    y = np.zeros(n)
    for f, amp, tau in lista:
        y += amp * np.sin(DOS_PI * f * t) * np.exp(-t / tau)
    return y * rampa(n, 0.001) * salida(n, 0.01)


def cuerno(f, seg, g):
    """Caracol/cuerno grave: armónicos que se abren con la envolvente y entrada desde abajo."""
    n = n_(seg)
    t = t_(n)
    entrada = 2.0 ** (-0.7 * np.exp(-t / 0.045) / 12.0)
    vib = 1.0 + 0.007 * np.sin(DOS_PI * 5.6 * t) * np.clip((t - 0.35) / 0.4, 0.0, 1.0)
    w = fase_de(f * entrada * vib)
    env = rampa(n, 0.07) * (0.8 + 0.2 * np.clip(t / 0.5, 0.0, 1.0)) * salida(n, 0.45)
    y = np.zeros(n)
    for k in range(1, 14):
        if k * f > 4500:
            break
        y += np.sin(k * w + 0.3 * k) / k ** 1.0 * env ** (1.0 + 0.3 * (k - 1))
    y += 0.05 * ruido(n, g, 300, 2500, color=1.0) * env
    return y


# --------------------------------------------------------------------------------------
# Bucles de ambiente
# --------------------------------------------------------------------------------------

def _silbo(f0, f1, seg, curva=1.0):
    """Silbido de ave: barrido senoidal con envolvente de campana."""
    n = n_(seg)
    u = np.arange(n) / n
    w = fase_de(f0 * (f1 / f0) ** (u ** curva))
    return (np.sin(w) + 0.12 * np.sin(2 * w)) * np.sin(np.pi * u) ** 1.5


def _canto(tipo, tono=1.0):
    """Cantos de ave inventados (ninguno imita una especie o grabación concreta)."""
    y = np.zeros(n_(1.3))
    if tipo == "trino":
        for i, a in enumerate((0.7, 1.0, 0.9, 0.6)):
            poner(y, _silbo(2900 * tono, 3600 * tono, 0.05), 0.085 * i, a)
    elif tipo == "descenso":
        poner(y, _silbo(2500 * tono, 1750 * tono, 0.32, 0.8), 0.0, 1.0)
        poner(y, _silbo(2100 * tono, 1600 * tono, 0.25, 0.8), 0.42, 0.7)
    elif tipo == "gorjeo":
        n = n_(0.45)
        t = t_(n)
        u = np.arange(n) / n
        w = fase_de(2250 * tono + 260 * np.sin(DOS_PI * 22 * t))
        poner(y, np.sin(w) * np.sin(np.pi * u) ** 1.2, 0.0, 0.9)
    elif tipo == "dos_notas":
        poner(y, _silbo(1650 * tono, 1690 * tono, 0.14), 0.0, 0.9)
        poner(y, _silbo(2090 * tono, 2040 * tono, 0.22), 0.20, 1.0)
    elif tipo == "arrullo":
        for i, a in enumerate((0.8, 1.0, 0.7)):
            poner(y, _silbo(560 * tono, 500 * tono, 0.28), 0.36 * i, a)
    elif tipo == "pio":
        poner(y, _silbo(3300 * tono, 4100 * tono, 0.07), 0.0, 1.0)
        poner(y, _silbo(4100 * tono, 3300 * tono, 0.07), 0.09, 0.8)
    return y


def amb_selva(seg):
    """Selva de día: viento y hojas, insectos y aves dispersas."""
    g = gen("amb_selva")
    n = n_(seg)
    t = t_(n)

    def ciclo(k, fase=0.0):  # ondas lentas con ciclos enteros por bucle → costura exacta
        return np.sin(DOS_PI * k * t / seg + fase)

    # Viento y hojas (ruido rosa pasa-bajos con ráfagas lentas)
    viento = ruido(n, g, 100, 800, color=1.0)
    viento *= 1.0 + 0.30 * ciclo(1, 0.7) + 0.18 * ciclo(3, 2.1) + 0.08 * ciclo(7, 4.0)
    hojas = ruido(n, g, 1200, 4500, color=1.0)
    rafagas = np.clip(0.5 + 0.35 * ciclo(2, 1.0) + 0.25 * ciclo(5, 3.3), 0.0, None) ** 2
    hojas *= rafagas * np.clip(1.0 + 0.5 * lento(n, g, 0.3, 6.0), 0.2, None)
    cama = viento + 0.28 * hojas

    # Insectos: bandas estrechas y agudas con trémolo
    f_trem1 = round(17.0 * seg) / seg
    f_trem2 = round(9.5 * seg) / seg
    ins1 = ruido(n, g, 5200, 6400, orden=6)
    ins1 *= (0.55 + 0.45 * np.sin(DOS_PI * f_trem1 * t)) * (0.6 + 0.4 * ciclo(1, 3.0))
    ins2 = ruido(n, g, 3300, 3900, orden=6)
    ins2 *= (0.5 + 0.5 * np.sin(DOS_PI * f_trem2 * t)) ** 2 * np.clip(ciclo(2, 0.4), 0.0, 1.0)
    insectos = 0.14 * ins1 + 0.09 * ins2

    # Aves: (posición en el bucle 0..1, canto, tono, cercanía 0..1)
    aves = np.zeros(n)
    agenda = ((0.06, "trino", 1.00, 0.80), (0.21, "dos_notas", 1.00, 0.60),
              (0.33, "pio", 1.00, 0.50), (0.47, "descenso", 1.00, 0.90),
              (0.62, "arrullo", 1.00, 0.70), (0.71, "gorjeo", 1.00, 0.60),
              (0.86, "trino", 0.88, 0.45), (0.93, "pio", 1.12, 0.35))
    if seg < 8.0:  # bucle corto: menos cantos para que sigan siendo dispersos
        agenda = tuple(a for a in agenda if a[0] not in (0.33, 0.86))
    for pos, tipo, tono, cerca in agenda:
        canto = filtrar(_canto(tipo, tono), 300, 3000 + 4000 * cerca)
        t0 = pos * seg + g.uniform(-0.05, 0.05)
        poner(aves, canto, t0, cerca, circular=True)
        poner(aves, canto, t0 + 0.11, 0.22 * cerca, circular=True)  # eco del follaje
        poner(aves, canto, t0 + 0.23, 0.10 * cerca, circular=True)
    aves = reverb(aves, g, t60=1.2, mezcla=0.35, circular=True)

    return cama + insectos + 1.5 * aves


def amb_brasero(seg):
    """Fuego del brasero: retumbo grave, rugido medio y chasquidos."""
    g = gen("amb_brasero")
    n = n_(seg)
    retumbo = ruido(n, g, 50, 220, color=2.0) * np.clip(1.0 + 0.45 * lento(n, g, 0.4, 5.0), 0.2, None)
    rugido = ruido(n, g, 150, 1400, color=1.5) * np.clip(1.0 + 0.6 * lento(n, g, 2.0, 14.0), 0.1, None)
    siseo = ruido(n, g, 2000, 5500, color=1.0) * np.clip(0.6 + 0.5 * lento(n, g, 1.0, 9.0), 0.0, None)
    y = 0.6 * retumbo + 0.9 * rugido + 0.10 * siseo

    chasq = np.zeros(n)
    for _ in range(int(round(11 * seg))):
        t0 = g.uniform(0.0, seg)
        amp = min(0.8, 0.25 * float(np.exp(g.normal(0.0, 0.7))))
        d = g.uniform(0.004, 0.02)
        fc = g.uniform(1200.0, 5000.0)
        poner(chasq, rafaga(d, g, 0.6 * fc, 1.5 * fc, tau=d / 4.0, ataque=0.0005), t0, amp, circular=True)
        if amp > 0.5:  # las chispas fuertes llevan un «toc» de leña
            poner(chasq, np.sin(DOS_PI * fc / 6.0 * t_(n_(0.03))) * env_perc(n_(0.03), 0.008),
                  t0, 0.6 * amp, circular=True)
    return y + 1.9 * chasq


# --------------------------------------------------------------------------------------
# Música
# --------------------------------------------------------------------------------------
# Todo en Re menor pentatónica (Re Fa Sol La Do); los momentos luminosos usan su
# relativo, Fa mayor pentatónica, que tiene las mismas notas.

# Acordes del claro: colchón, bajo y motivo de kalimba (corchea, nota MIDI, intensidad)
_AC = {
    "re": dict(pad=(50, 57, 65), bajo=38, motivo=((0, 62, 1.0), (2, 65, 0.7), (3, 69, 0.8), (5, 74, 0.9), (6, 69, 0.6))),
    "fa": dict(pad=(53, 57, 60), bajo=41, motivo=((0, 60, 1.0), (2, 65, 0.7), (3, 69, 0.8), (5, 72, 0.9), (6, 69, 0.6))),
    "sol": dict(pad=(55, 60, 62), bajo=43, motivo=((0, 62, 1.0), (2, 67, 0.7), (3, 72, 0.8), (5, 74, 0.9), (6, 67, 0.6))),
    "re2": dict(pad=(50, 57, 65), bajo=38, motivo=((0, 62, 1.0), (2, 69, 0.7), (3, 65, 0.8), (5, 69, 0.8), (7, 72, 0.6))),
    "do": dict(pad=(48, 55, 62), bajo=36, motivo=((0, 60, 1.0), (2, 67, 0.7), (3, 74, 0.8), (5, 72, 0.9), (6, 67, 0.6))),
    "la": dict(pad=(57, 62, 67), bajo=33, motivo=((0, 57, 1.0), (2, 62, 0.7), (3, 67, 0.8), (5, 69, 0.8), (7, 72, 0.6))),
}
_PROG_CLARO = {6: ("re", "fa", "sol", "re2", "do", "la"), 4: ("re", "fa", "sol", "la")}
# Flauta: (negra de inicio, nota MIDI, duración en negras)
_FLAUTA_CLARO = {6: ((5, 69, 2.5), (8, 72, 1.5), (10, 74, 2.5), (17, 67, 2.0), (20, 69, 3.0)),
                 4: ((5, 69, 2.5), (8, 72, 1.5), (10, 74, 2.0), (13, 67, 2.5))}


def capas_claro(compases):
    """Capas de la música de exploración (75 BPM, 4/4); todas dan la vuelta al bucle."""
    g = gen("mus_claro")
    negra = 60.0 / 75.0
    comp = 4 * negra
    n = n_(compases * comp)
    c = {k: np.zeros(n) for k in ("colchon", "bajo", "kalimba", "brillo", "flauta", "tambor")}
    for i, nombre in enumerate(_PROG_CLARO[compases]):
        ac = _AC[nombre]
        t0 = i * comp
        for m in ac["pad"]:
            poner(c["colchon"], colchon(midi(m), comp + 1.6, 1.1, 1.5), t0 - 0.4, circular=True)
        poner(c["bajo"], bajo(midi(ac["bajo"] + 12), comp * 0.95), t0, circular=True)
        for corchea, m, vel in ac["motivo"]:
            tt = t0 + corchea * negra / 2 + g.uniform(-0.005, 0.005)
            poner(c["kalimba"], kalimba(midi(m), 1.8, g), tt, vel * g.uniform(0.9, 1.0), circular=True)
            if corchea in (0, 5):  # brillo: la misma nota una octava arriba, muy suave
                poner(c["brillo"], kalimba(midi(m + 12), 1.2, g), tt, 0.6 if corchea else 0.4, circular=True)
        # Tambor de mano muy suave: grave en 1 y 3, toque agudo en 2 y 4
        for tiempo, vel in ((0, 1.0), (2, 0.6)):
            poner(c["tambor"], tambor(95, 0.4, g, tau=0.14, barrido=0.5, piel=0.15, banda=(200, 1200)),
                  t0 + tiempo * negra, vel, circular=True)
        for tiempo, vel in ((1, 0.35), (3, 0.35)) + (((3.5, 0.22),) if i % 2 else ()):
            poner(c["tambor"], tambor(210, 0.15, g, tau=0.04, barrido=0.3, piel=0.3,
                                      banda=(500, 2500), tau_piel=0.01),
                  t0 + tiempo * negra, vel, circular=True)
    for inicio, m, largo in _FLAUTA_CLARO[compases]:
        poner(c["flauta"], flauta(midi(m), largo * negra, g, ataque=0.09, rel=0.25),
              inicio * negra, circular=True)
    # Eco de corchea con puntillo en la kalimba (desplazamiento circular)
    for k in ("kalimba", "brillo"):
        c[k] = c[k] + 0.28 * np.roll(c[k], n_(0.75 * negra)) + 0.12 * np.roll(c[k], n_(1.5 * negra))
    return c, g


def mus_claro(compases):
    c, g = capas_claro(compases)
    y = (0.30 * c["colchon"] + 0.35 * c["bajo"] + 0.90 * c["kalimba"] + 0.40 * c["brillo"]
         + 0.50 * c["flauta"] + 0.55 * c["tambor"])
    return reverb(y, g, t60=1.6, mezcla=0.28, circular=True)


# Emboscada: por compás, nota grave del dron y las dos notas del ostinato de kalimba
_VAR_EMB = {0: (38, (74, 77)), 1: (41, (77, 79)), 2: (36, (72, 74))}
_PROG_EMB = {6: (0, 0, 0, 0, 1, 2), 4: (0, 0, 1, 2)}


def capas_emboscada(compases):
    """Capas de la música de combate (150 BPM, 4/4, rejilla de semicorcheas)."""
    g = gen("mus_emboscada")
    semi = 0.1
    comp = 1.6
    n = n_(compases * comp)
    c = {k: np.zeros(n) for k in ("tom", "palmada", "sonaja", "dron", "kalimba")}
    prog = _PROG_EMB[compases]
    for i, var in enumerate(prog):
        t0 = i * comp
        raiz, notas = _VAR_EMB[var]
        ultimo = i == len(prog) - 1
        for s, vel in ((0, 1.0), (3, 0.7), (6, 0.8), (8, 0.95), (11, 0.7), (14, 0.8)):
            poner(c["tom"], tambor(105, 0.30, g, tau=0.075, barrido=0.8, piel=0.5, banda=(250, 2200)),
                  t0 + s * semi, vel, circular=True)
        if ultimo:  # redoble de cierre que empuja a la vuelta
            palmadas = ((4, 0.9), (10, 0.5), (12, 0.9), (13, 0.6), (14, 0.75), (15, 0.9))
        else:
            palmadas = ((4, 0.9), (12, 0.9)) + (((15, 0.5),) if i % 2 else ())
        for s, vel in palmadas:
            poner(c["palmada"], tambor(250, 0.16, g, tau=0.045, barrido=0.4, piel=0.9,
                                       banda=(900, 4500), tau_piel=0.02),
                  t0 + s * semi, vel, circular=True)
        for s in range(16):
            vel = 0.9 if s % 4 == 2 else (0.55 if s % 2 == 0 else 0.3)
            poner(c["sonaja"], rafaga(0.06, g, 3000, 6000, tau=0.016, ataque=0.004),
                  t0 + s * semi, vel, circular=True)
        # Dron grave que late en corcheas (cada pulso arranca en fase 0 y se apaga)
        m = n_(0.2)
        tp = t_(m)
        w = DOS_PI * midi(raiz) * tp
        pulso = (0.7 * np.sin(w) + 0.8 * np.sin(2 * w) + 0.5 * np.sin(3 * w)
                 + 0.25 * np.sin(4 * w) + 0.12 * np.sin(5 * w))
        pulso *= rampa(m, 0.004) * (0.35 + 0.65 * np.exp(-tp / 0.06)) * salida(m, 0.008)
        for k in range(8):
            poner(c["dron"], pulso, t0 + 0.2 * k, 1.0 if k % 2 == 0 else 0.75, circular=True)
        for s, cual, vel in ((0, 0, 1.0), (3, 0, 0.75), (6, 1, 0.9), (10, 0, 0.8), (12, 1, 0.9)):
            poner(c["kalimba"], kalimba(midi(notas[cual]), 0.5, g), t0 + s * semi, vel, circular=True)
    return c, g


def mus_emboscada(compases):
    c, g = capas_emboscada(compases)
    y = (0.75 * c["tom"] + 0.80 * c["palmada"] + 0.35 * c["sonaja"]
         + 0.32 * c["dron"] + 0.30 * c["kalimba"])
    y = reverb(y, g, t60=0.5, mezcla=0.12, circular=True)
    # Saturación suave de los picos de tambor (sin memoria, no afecta a la costura)
    y = y / rms(y)
    return 5.0 * np.tanh(y / 5.0)


# --------------------------------------------------------------------------------------
# Efectos sueltos
# --------------------------------------------------------------------------------------

def paso(k):
    """Paso suave sobre piedra y tierra (tres variantes)."""
    g = gen(f"paso_{k + 1}")
    y = np.zeros(n_(0.12))
    f0 = (105.0, 125.0, 92.0)[k]
    banda = ((350, 2200), (500, 2800), (280, 1800))[k]
    poner(y, glis(1.5 * f0, 0.7 * f0, 0.11) * env_perc(n_(0.11), 0.030), 0.0, 0.9)
    poner(y, rafaga(0.10, g, banda[0], banda[1], tau=(0.024, 0.018, 0.030)[k], color=1.0), 0.0, 0.8)
    poner(y, rafaga(0.07, g, 900, 3500, tau=0.015, color=1.0), (0.035, 0.028, 0.045)[k], 0.40)
    return y


def salto():
    """Salto: soplido que sube."""
    g = gen("salto")
    n = n_(0.2)
    u = np.arange(n) / n
    y = ruido_barrido(n, g, 400.0 * (3400.0 / 400.0) ** u, ancho=0.7) * np.sin(np.pi * u ** 0.8) ** 1.3
    poner(y, glis(220, 520, 0.17) * np.sin(np.pi * np.arange(n_(0.17)) / n_(0.17)) ** 1.5, 0.0, 0.35)
    return y


def aterrizar():
    """Aterrizaje: golpe sordo con algo de polvo."""
    g = gen("aterrizar")
    y = np.zeros(n_(0.2))
    poner(y, glis(135, 55, 0.18) * env_perc(n_(0.18), 0.045), 0.0, 1.0)
    poner(y, rafaga(0.12, g, 150, 900, tau=0.020, color=1.0), 0.0, 0.7)
    poner(y, rafaga(0.18, g, 1500, 4000, tau=0.035, ataque=0.008, color=1.0), 0.005, 0.12)
    return y


def chapoteo():
    """Chapoteo: impacto, rocío y gotas."""
    g = gen("chapoteo")
    y = np.zeros(n_(0.5))
    poner(y, rafaga(0.25, g, 120, 500, tau=0.05, color=1.0), 0.0, 0.9)
    poner(y, rafaga(0.20, g, 500, 4000, tau=0.03, ataque=0.003, color=1.0), 0.0, 1.0)
    n = n_(0.45)
    rocio = ruido(n, g, 1800, 6000, color=1.0) * env_perc(n, 0.13, 0.03)
    rocio *= np.clip(1.0 + 0.8 * lento(n, g, 12, 45), 0.0, None)
    poner(y, rocio, 0.02, 0.6)
    for _ in range(7):
        t0 = g.uniform(0.07, 0.40)
        f0 = g.uniform(500.0, 1100.0)
        d = g.uniform(0.02, 0.045)
        gota = glis(f0, f0 * g.uniform(1.6, 2.3), d) * env_perc(n_(d), d / 3.0, 0.002)
        poner(y, gota, t0, g.uniform(0.15, 0.4) * (1.0 - t0))
    return y


def _destellos(y, g, t_ini, t_fin, cuantos, f_lo, f_hi, gan, tau=0.008):
    """Granos senoidales agudos y breves repartidos en el tiempo (chispas)."""
    for i in range(cuantos):
        t0 = t_ini + (t_fin - t_ini) * (i + g.uniform(0.0, 0.8)) / cuantos
        n = n_(5.0 * tau)
        grano = np.sin(DOS_PI * g.uniform(f_lo, f_hi) * t_(n)) * env_perc(n, tau, 0.001)
        poner(y, grano, t0, gan * (1.0 - 0.6 * i / cuantos))


def chispa():
    """Chispa de jade: gorjeo ascendente, vítreo, con destellos."""
    g = gen("chispa")
    y = np.zeros(n_(0.3))
    n = n_(0.14)
    u = np.arange(n) / n
    w = fase_de(850.0 * (3400.0 / 850.0) ** (u ** 0.8))
    poner(y, (np.sin(w) + 0.3 * np.sin(2 * w)) * rampa(n, 0.004) * np.exp(-t_(n) / 0.07) * salida(n, 0.03), 0.0, 1.0)
    for f, amp, tau, t0 in ((2350, 0.50, 0.070, 0.030), (3520, 0.35, 0.055, 0.045),
                            (4700, 0.25, 0.045, 0.060), (5900, 0.12, 0.035, 0.070)):
        m = n_(5.0 * tau)
        poner(y, np.sin(DOS_PI * f * t_(m)) * env_perc(m, tau, 0.002), t0, amp)
    _destellos(y, g, 0.07, 0.26, 7, 3000, 6500, 0.30)
    poner(y, rafaga(0.05, g, 3000, 7000, tau=0.010), 0.0, 0.25)
    return y


def chispa_impacto():
    """Impacto de la chispa: estallido vítreo corto."""
    g = gen("chispa_impacto")
    y = np.zeros(n_(0.3))
    poner(y, rafaga(0.08, g, 2000, 6500, tau=0.014), 0.0, 0.9)
    poner(y, modos(((1800, 0.6, 0.08), (2950, 0.45, 0.065), (4300, 0.3, 0.05), (5700, 0.15, 0.04)), 0.28), 0.0, 1.0)
    poner(y, glis(260, 180, 0.12) * env_perc(n_(0.12), 0.03), 0.0, 0.5)
    _destellos(y, g, 0.04, 0.24, 6, 2500, 6000, 0.25)
    return y


def esquiva():
    """Esquiva: soplido de aire que pasa."""
    g = gen("esquiva")
    n = n_(0.25)
    u = np.arange(n) / n
    fc = 500.0 * 4.0 ** np.sin(np.pi * u)
    return ruido_barrido(n, g, fc, ancho=0.9) * np.sin(np.pi * u ** 0.6) ** 2


def garras():
    """Zarpazo rápido: tres tajos de aire seguidos."""
    g = gen("garras")
    y = np.zeros(n_(0.25))
    for t0, fa, fb, gan in ((0.0, 4200, 1300, 0.85), (0.05, 4800, 1500, 1.0), (0.10, 3800, 1200, 0.9)):
        n = n_(0.11)
        u = np.arange(n) / n
        tajo = ruido_barrido(n, g, fa * (fb / fa) ** u, ancho=0.45, color=1.5)
        poner(y, tajo * env_perc(n, 0.028, 0.004), t0, gan)
    poner(y, rafaga(0.2, g, 200, 900, tau=0.05, ataque=0.01, color=1.0), 0.0, 0.5)
    return y


def zarpazo_carga():
    """Carga del zarpazo: retumbo y quejido que suben."""
    g = gen("zarpazo_carga")
    n = n_(0.8)
    u = np.arange(n) / n
    trem = 0.6 + 0.4 * np.sin(fase_de(7.0 + 22.0 * u ** 1.5))
    retumbo = ruido(n, g, 50, 320, color=1.5)
    w = fase_de(150.0 * 4.2 ** (u ** 1.3))
    quejido = np.sin(w) + 0.35 * np.sin(2 * w) + 0.15 * np.sin(3 * w)
    aire = ruido_barrido(n, g, 400.0 * 8.0 ** u, ancho=0.7)
    y = 0.9 * retumbo * trem + 0.5 * quejido * np.sqrt(trem) + 0.3 * aire * u
    return y * (0.25 + 0.75 * u ** 1.3)


def zarpazo():
    """Zarpazo cargado: golpe grave y chasquido."""
    g = gen("zarpazo")
    y = np.zeros(n_(0.5))
    poner(y, glis(150, 50, 0.45) * env_perc(n_(0.45), 0.12, 0.002), 0.0, 1.0)
    poner(y, rafaga(0.08, g, 1500, 6500, tau=0.011), 0.0, 1.4)
    poner(y, rafaga(0.30, g, 180, 1300, tau=0.055, color=1.0), 0.0, 1.1)
    poner(y, rafaga(0.50, g, 40, 220, tau=0.16, ataque=0.02, color=2.0), 0.0, 0.5)
    return saturar(y)


def salto_jaguar():
    """Salto ofensivo del jaguar: gruñido grave (FM) y soplido."""
    g = gen("salto_jaguar")
    y = np.zeros(n_(0.5))
    n = n_(0.42)
    t = t_(n)
    u = np.arange(n) / n
    fc = 115.0 * 0.72 ** u
    w = fase_de(fc) + 2.6 * (1.0 - 0.3 * u) * np.sin(fase_de(0.5 * fc))
    aspereza = 1.0 + 0.55 * np.sin(DOS_PI * 29.0 * t + 0.4 * np.sin(DOS_PI * 7.0 * t))
    ronco = (np.sin(w) + 0.25 * ruido(n, g, 150, 900, color=1.0)) * aspereza
    ronco = filtrar(ronco, 70, 1500)
    poner(y, ronco * rampa(n, 0.03) * np.exp(-np.clip(t - 0.12, 0.0, None) / 0.12) * salida(n, 0.05), 0.0, 1.0)
    m = n_(0.38)
    v = np.arange(m) / m
    poner(y, ruido_barrido(m, g, 450.0 * (2400.0 / 450.0) ** v, ancho=0.7) * np.sin(np.pi * v ** 0.7) ** 1.5, 0.10, 0.45)
    return y


def salto_impacto():
    """Impacto del salto contra el suelo."""
    g = gen("salto_impacto")
    y = np.zeros(n_(0.4))
    poner(y, glis(135, 55, 0.35) * env_perc(n_(0.35), 0.09), 0.0, 1.0)
    poner(y, rafaga(0.25, g, 250, 2800, tau=0.045, color=1.0), 0.0, 1.0)
    poner(y, rafaga(0.38, g, 900, 4000, tau=0.11, ataque=0.03, color=1.0), 0.02, 0.2)
    for _ in range(6):
        t0 = g.uniform(0.06, 0.30)
        poner(y, rafaga(0.02, g, 1200, 5000, tau=0.004), t0, g.uniform(0.1, 0.3) * (1.0 - t0 / 0.4))
    return saturar(y)


def golpe():
    """Un enemigo recibe un golpe: chasquido con pegada."""
    g = gen("golpe")
    y = np.zeros(n_(0.15))
    poner(y, glis(260, 115, 0.12) * env_perc(n_(0.12), 0.028), 0.0, 1.0)
    poner(y, rafaga(0.06, g, 700, 4500, tau=0.009), 0.0, 0.9)
    poner(y, rafaga(0.10, g, 250, 1200, tau=0.022, color=1.0), 0.0, 0.5)
    return y


def dano():
    """El jugador recibe daño: golpe sordo y tono que cae."""
    g = gen("dano")
    y = np.zeros(n_(0.3))
    poner(y, glis(160, 68, 0.2) * env_perc(n_(0.2), 0.045), 0.0, 1.0)
    poner(y, rafaga(0.12, g, 200, 1100, tau=0.025, color=1.0), 0.0, 0.6)
    n = n_(0.27)
    u = np.arange(n) / n
    w = fase_de(430.0 * (290.0 / 430.0) ** u)
    tono = np.sin(w) + 0.25 * np.sin(2 * w) + np.sin(3 * w) / 9.0
    poner(y, tono * env_perc(n, 0.10, 0.008) * salida(n, 0.03), 0.02, 0.7)
    return y


def caida():
    """El jugador cae: tres notas tristes que bajan (La, Fa, Re)."""
    g = gen("caida")
    y = np.zeros(n_(0.9))
    for t0, m, d, cae in ((0.0, 69, 0.30, 0.0), (0.22, 65, 0.30, 0.0), (0.44, 62, 0.46, 0.6)):
        poner(y, flauta(midi(m), d, g, vib=0.004, ataque=0.03, rel=0.12, cae=cae), t0, 0.6)
        poner(y, kalimba(midi(m), 0.45, g), t0, 0.7)
    return reverb(y, g, t60=0.7, mezcla=0.2)


def reaparecer():
    """Reaparición: escala de campanitas que sube con brillo."""
    g = gen("reaparecer")
    y = np.zeros(n_(0.9))
    for i, m in enumerate((62, 65, 69, 72, 74, 77, 81, 86)):
        poner(y, campana(midi(m), 0.4, tau=0.12), 0.068 * i, 0.35 + 0.07 * i)
    n = n_(0.8)
    u = np.arange(n) / n
    aire = ruido_barrido(n, g, 1200.0 * 4.5 ** u, ancho=0.5)
    aire *= u ** 1.5 * (1.0 - u) ** 0.4 * (0.7 + 0.3 * np.sin(DOS_PI * 14.0 * t_(n)))
    poner(y, aire, 0.0, 0.9)
    m = n_(0.7)
    poner(y, glis(293.7, 587.3, 0.7) * np.sin(np.pi * np.arange(m) / m), 0.0, 0.3)
    return reverb(y, g, t60=0.6, mezcla=0.2)


def curar():
    """Curación: arpegio cálido que sube, con brillo."""
    g = gen("curar")
    y = np.zeros(n_(0.8))
    for i, m in enumerate((62, 65, 69, 74, 77)):
        t0 = 0.10 * i
        poner(y, kalimba(midi(m), 0.6, g), t0, 0.7)
        n = n_(0.55)
        poner(y, np.sin(DOS_PI * midi(m) * t_(n)) * rampa(n, 0.03) * np.exp(-t_(n) / 0.28) * salida(n, 0.05), t0, 0.35)
    for _ in range(10):
        m = (86, 89, 91, 93, 96, 98)[int(g.integers(0, 6))]
        poner(y, campana(midi(m), 0.2, tau=0.05), g.uniform(0.25, 0.66), 0.28)
    return reverb(y, g, t60=0.7, mezcla=0.22)


def purificar():
    """Purificación: acorde de campanas que florece (Fa mayor)."""
    g = gen("purificar")
    y = np.zeros(n_(1.0))
    for i, (m, gan) in enumerate(((65, 0.8), (72, 0.7), (77, 0.6), (81, 0.45))):
        poner(y, campana(midi(m), 0.95, tau=0.40, ataque=0.02), 0.05 * i, gan)
    n = n_(0.95)
    u = np.arange(n) / n
    crece = np.sin(np.pi * u ** 0.6) ** 1.5
    for m in (53, 60, 65, 69):
        poner(y, np.sin(DOS_PI * midi(m) * t_(n) + m) * crece, 0.0, 0.16)
    poner(y, campana(midi(84), 0.6, tau=0.25, ataque=0.01), 0.25, 0.35)
    poner(y, campana(midi(89), 0.5, tau=0.18, ataque=0.01), 0.33, 0.22)
    return reverb(y, g, t60=1.0, mezcla=0.25)


def transformar():
    """Transformación: remolino de aire y acorde brillante."""
    g = gen("transformar")
    y = np.zeros(n_(0.7))
    n = n_(0.5)
    u = np.arange(n) / n
    giro = DOS_PI * (1.5 * u + 3.5 * u ** 2)  # el remolino se acelera
    fc = 700.0 * 3.5 ** u * 2.0 ** (0.6 * np.sin(giro))
    remolino = ruido_barrido(n, g, fc, ancho=0.5) * rampa(n, 0.02) * (0.3 + 0.7 * u) * salida(n, 0.12)
    poner(y, remolino, 0.0, 0.8)
    poner(y, glis(180, 720, 0.4) * np.sin(np.pi * np.arange(n_(0.4)) / n_(0.4)) ** 1.5, 0.0, 0.3)
    for i, m in enumerate((77, 81, 84)):
        poner(y, campana(midi(m), 0.36, tau=0.13), 0.33 + 0.012 * i, 0.5)
        poner(y, kalimba(midi(m - 12), 0.36, g), 0.33 + 0.012 * i, 0.4)
    _destellos(y, g, 0.36, 0.62, 6, 2800, 6000, 0.12)
    return reverb(y, g, t60=0.5, mezcla=0.18)


def enemigo_aviso():
    """Aviso de ataque enemigo: dos tonos tensos que suben (tritono)."""
    y = np.zeros(n_(0.35))
    for t0, fa, fb, d, gan in ((0.0, 360.0, 372.0, 0.17, 0.75), (0.15, 505.0, 530.0, 0.20, 1.0)):
        n = n_(d)
        w = fase_de(fa * (fb / fa) ** (np.arange(n) / n))
        tono = np.sin(w) + 0.20 * np.sin(3 * w) + 0.08 * np.sin(5 * w)
        tono *= (0.75 + 0.25 * np.sin(DOS_PI * 28.0 * t_(n))) * env_asr(n, 0.006, 0.03)
        poner(y, tono, t0, gan)
    n = n_(0.33)
    poner(y, glis(90, 120, 0.33) * np.sin(np.pi * np.arange(n) / n), 0.0, 0.35)
    return y


def enemigo_golpe():
    """Golpe del guardián de piedra: porrazo pesado con escombros."""
    g = gen("enemigo_golpe")
    y = np.zeros(n_(0.4))
    poner(y, glis(115, 46, 0.38) * env_perc(n_(0.38), 0.10), 0.0, 1.0)
    poner(y, rafaga(0.12, g, 250, 1800, tau=0.022, color=1.0), 0.0, 1.0)
    poner(y, modos(((305, 0.5, 0.045), (468, 0.4, 0.035), (742, 0.3, 0.025), (1130, 0.15, 0.018)), 0.2), 0.0, 1.5)
    poner(y, rafaga(0.38, g, 60, 400, tau=0.12, ataque=0.03, color=2.0), 0.0, 0.4)
    for _ in range(9):
        t0 = g.uniform(0.07, 0.36)
        lo = g.uniform(700.0, 2000.0)
        poner(y, rafaga(0.03, g, lo, 2.5 * lo, tau=g.uniform(0.004, 0.009)), t0,
              g.uniform(0.12, 0.35) * (1.0 - t0 / 0.45))
    return saturar(y)


def enemigo_muere():
    """Enemigo derrotado: se desmorona y se disuelve."""
    g = gen("enemigo_muere")
    y = np.zeros(n_(0.5))
    for t0 in np.sort(0.46 * g.uniform(0.0, 1.0, 45) ** 1.6):
        fc = g.uniform(500.0, 3500.0) * (1.0 - 0.6 * t0 / 0.5)
        d = g.uniform(0.012, 0.04)
        poner(y, rafaga(d, g, 0.6 * fc, 1.6 * fc, tau=d / 4.0), t0,
              g.uniform(0.2, 0.6) * (1.0 - t0 / 0.52) ** 0.7)
    n = n_(0.48)
    t = t_(n)
    w = fase_de(520.0 * (150.0 / 520.0) ** (np.arange(n) / n))
    poner(y, np.sin(w) * (0.6 + 0.4 * np.sin(DOS_PI * 19.0 * t)) * env_perc(n, 0.2, 0.01), 0.0, 0.4)
    poner(y, ruido(n, g, 2500, 6000, color=1.0) * env_perc(n, 0.12, 0.02), 0.0, 0.15)
    poner(y, glis(120, 60, 0.3) * env_perc(n_(0.3), 0.08), 0.0, 0.5)
    return y


def altar_on():
    """Altar activado: piedra que resuena y tono de campana (Re)."""
    g = gen("altar_on")
    y = np.zeros(n_(0.4))
    poner(y, rafaga(0.08, g, 250, 1600, tau=0.014, color=1.0), 0.0, 0.8)
    poner(y, modos(((196, 0.6, 0.07), (331, 0.4, 0.05), (547, 0.25, 0.035)), 0.3), 0.0, 1.0)
    poner(y, campana(midi(74), 0.385, tau=0.16), 0.012, 0.8)
    poner(y, campana(midi(81), 0.36, tau=0.12), 0.03, 0.3)
    return reverb(y, g, t60=0.4, mezcla=0.15)


def altar_off():
    """Altar liberado: más grave y apagado."""
    g = gen("altar_off")
    y = np.zeros(n_(0.25))
    poner(y, rafaga(0.07, g, 150, 900, tau=0.016, color=1.0), 0.0, 0.8)
    poner(y, modos(((147, 0.6, 0.06), (233, 0.4, 0.045)), 0.22), 0.0, 1.0)
    n = n_(0.22)
    w = fase_de(294.0 * (262.0 / 294.0) ** (np.arange(n) / n))
    poner(y, (np.sin(w) + 0.2 * np.sin(2 * w)) * env_perc(n, 0.07, 0.004), 0.01, 0.7)
    return y


def santuario_abre():
    """Se disuelve el sello del santuario: piedra que roza y acorde que crece."""
    g = gen("santuario_abre")
    n = n_(2.2)
    t = t_(n)
    y = np.zeros(n)
    # Piedra: ruido grave con «tirones» irregulares (pega y resbala)
    env_p = rampa(n, 0.08) * np.clip(1.0 - (t - 0.2) / 1.5, 0.0, 1.0) ** 0.8
    tirones = np.clip(0.55 + 0.6 * lento(n, g, 6, 32), 0.0, None) ** 1.5
    y += 0.55 * ruido(n, g, 90, 900, color=1.5) * tirones * env_p
    y += 0.25 * ruido(n, g, 45, 150, color=2.0) * env_p
    poner(y, tambor(70, 0.4, g, tau=0.12, barrido=0.7, piel=0.5, banda=(200, 1500), tau_piel=0.03), 1.55, 0.8)
    # Acorde que crece (Re menor) y florece en Fa mayor
    for i, m in enumerate((50, 57, 62, 65, 69)):
        poner(y, colchon(midi(m), 1.9 - 0.08 * i, 1.2, 0.7), 0.25 + 0.08 * i, 0.40)
    m_ = n_(1.4)
    u = np.arange(m_) / m_
    poner(y, ruido_barrido(m_, g, 1500.0 * (5000.0 / 1500.0) ** u, ancho=0.5) * u ** 2 * salida(m_, 0.15), 0.2, 0.25)
    for i, m in enumerate((74, 77, 81, 84)):
        poner(y, kalimba(midi(m), 0.8, g), 1.0 + 0.1 * i, 0.50 + 0.06 * i)
    for i, (m, gan) in enumerate(((77, 1.0), (81, 0.85), (84, 0.75), (89, 0.4))):
        poner(y, campana(midi(m), 0.75, tau=0.35, ataque=0.008), 1.45 + 0.04 * i, gan)
    return reverb(y, g, t60=1.2, mezcla=0.25)


def emboscada():
    """Emboscada: toque grave de caracol y golpe de tambor."""
    g = gen("emboscada")
    y = np.zeros(n_(1.6))
    f = midi(50)  # Re3
    poner(y, cuerno(f, 1.5, g), 0.03, 1.0)
    poner(y, cuerno(f * 1.006, 1.5, g), 0.03, 0.6)
    poner(y, cuerno(f / 2.0, 1.5, g), 0.03, 0.25)
    poner(y, tambor(62, 0.7, g, tau=0.20, barrido=1.0, piel=0.5, banda=(200, 2000), tau_piel=0.03), 0.0, 1.3)
    poner(y, tambor(62, 0.5, g, tau=0.16, barrido=0.8, piel=0.4, banda=(200, 2000), tau_piel=0.03), 0.5, 0.7)
    return reverb(filtrar(y, None, 3000), g, t60=0.9, mezcla=0.2)


def victoria():
    """Victoria: frase pentatónica que sube (kalimba y flauta) y acorde final de Fa."""
    g = gen("victoria")
    y = np.zeros(n_(3.2))
    for t0, m, vel in ((0.00, 72, 0.80), (0.15, 74, 0.80), (0.30, 77, 0.90),
                       (0.52, 79, 0.85), (0.67, 81, 0.95), (0.90, 84, 1.00)):
        poner(y, kalimba(midi(m), 0.7, g), t0, 1.25 * vel)
    poner(y, flauta(midi(79), 0.16, g, ataque=0.02, rel=0.04), 0.52, 0.35)
    poner(y, flauta(midi(81), 0.24, g, ataque=0.02, rel=0.05), 0.67, 0.40)
    poner(y, flauta(midi(84), 1.9, g, ataque=0.04, rel=1.0, vib=0.006), 0.90, 0.38)
    ta = 1.25  # acorde final
    for i, m in enumerate((65, 69, 72, 77, 81)):
        poner(y, kalimba(midi(m), 1.8, g), ta + 0.028 * i, 0.7)
    for m in (53, 60, 65, 69):
        poner(y, colchon(midi(m), 1.95, 0.15, 1.0), ta, 0.20)
    poner(y, bajo(midi(41), 1.9, tau=0.9), ta, 0.35)
    for m, gan in ((77, 0.30), (84, 0.25), (89, 0.15)):
        poner(y, campana(midi(m), 1.5, tau=0.5), ta + 0.01, gan)
    poner(y, tambor(90, 0.5, g, tau=0.16, barrido=0.6, piel=0.3), ta, 0.6)
    return reverb(y, g, t60=1.3, mezcla=0.25)


def derrota():
    """Derrota: frase lenta que baja, suave, sin castigar."""
    g = gen("derrota")
    y = np.zeros(n_(2.6))
    frase = ((0.00, 74, 0.55), (0.45, 72, 0.55), (0.90, 69, 0.55), (1.35, 65, 0.55), (1.80, 62, 0.80))
    for i, (t0, m, d) in enumerate(frase):
        poner(y, flauta(midi(m), d, g, ataque=0.06, rel=0.2 if i < 4 else 0.6, cae=0.5 if i == 4 else 0.0), t0, 0.6)
        poner(y, kalimba(midi(m - 12), 0.9, g, brillo=0.5), t0, 0.35)
    for m in (50, 57, 65):
        poner(y, colchon(midi(m), 1.3, 0.5, 0.75), 1.3, 0.28)
    return reverb(y, g, t60=1.2, mezcla=0.3)


def ui_click():
    """Clic de interfaz: toque seco de madera."""
    g = gen("ui_click")
    y = np.zeros(n_(0.06))
    poner(y, modos(((820, 1.0, 0.011), (1730, 0.5, 0.006)), 0.058), 0.0, 1.0)
    poner(y, rafaga(0.02, g, 1500, 4500, tau=0.002, ataque=0.0005), 0.0, 0.3)
    return y


def ui_abrir():
    """Abrir menú: pequeña ola suave."""
    g = gen("ui_abrir")
    n = n_(0.2)
    u = np.arange(n) / n
    env = np.sin(np.pi * u ** 0.6) ** 2
    y = (glis(520, 600, 0.2) + 0.6 * glis(780, 900, 0.2)) * env
    return y + 0.25 * ruido_barrido(n, g, 700.0 * 3.5 ** u, ancho=0.7) * env


def sin_energia():
    """Sin energía: doble pitido apagado."""
    y = np.zeros(n_(0.15))
    for t0, f, d, gan in ((0.0, 233.0, 0.055, 1.0), (0.08, 196.0, 0.065, 0.9)):
        n = n_(d)
        w = DOS_PI * f * t_(n)
        poner(y, (np.sin(w) + 0.3 * np.sin(2 * w) + np.sin(3 * w) / 9.0) * env_asr(n, 0.004, 0.02), t0, gan)
    return y


def objetivo():
    """Objetivo actualizado: dos notas de campanita (La, Re)."""
    g = gen("objetivo")
    y = np.zeros(n_(0.5))
    poner(y, campana(midi(81), 0.40, tau=0.16), 0.0, 0.8)
    poner(y, campana(midi(86), 0.36, tau=0.20), 0.13, 1.0)
    return reverb(y, g, t60=0.5, mezcla=0.15)


# --------------------------------------------------------------------------------------
# Catálogo
# --------------------------------------------------------------------------------------
# Bucles: (nombre, función(arg), arg normal, arg compacto, RMS objetivo en dBFS, corte agudo, descripción)
BUCLES = (
    ("amb_selva", amb_selva, 10.0, 6.5, -28.0, 7000.0, "Selva de día: viento, hojas, insectos y aves dispersas"),
    ("amb_brasero", amb_brasero, 4.0, 2.4, -28.0, 6500.0, "Fuego del brasero: retumbo grave y chasquidos"),
    ("mus_claro", mus_claro, 6, 4, -22.0, 7000.0, "Música de exploración, Re menor pentatónica, 75 BPM"),
    ("mus_emboscada", mus_emboscada, 6, 4, -22.0, 7000.0, "Música de emboscada, tambores y ostinato, 150 BPM"),
)

# Efectos: (nombre, función, duración, pico en dBFS, corte agudo, fundido final, descripción)
EFECTOS = (
    ("paso_1", lambda: paso(0), 0.12, -14.0, 4500.0, 0.03, "Paso suave sobre piedra/tierra (variante 1)"),
    ("paso_2", lambda: paso(1), 0.12, -14.0, 4500.0, 0.03, "Paso (variante 2, algo más seco)"),
    ("paso_3", lambda: paso(2), 0.12, -14.0, 4500.0, 0.03, "Paso (variante 3, más grave)"),
    ("salto", salto, 0.20, -10.0, 7000.0, 0.03, "Salto: soplido que sube"),
    ("aterrizar", aterrizar, 0.20, -9.0, 5000.0, 0.04, "Aterrizaje: golpe sordo con polvo"),
    ("chapoteo", chapoteo, 0.50, -7.0, 7000.0, 0.10, "Chapoteo en el agua"),
    ("chispa", chispa, 0.30, -7.0, 7500.0, 0.05, "Chispa de jade: gorjeo vítreo ascendente con destellos"),
    ("chispa_impacto", chispa_impacto, 0.30, -6.0, 7500.0, 0.05, "Impacto de la chispa: estallido vítreo"),
    ("esquiva", esquiva, 0.25, -9.0, 6500.0, 0.03, "Esquiva: soplido de aire"),
    ("garras", garras, 0.25, -6.0, 7500.0, 0.04, "Garras: tres tajos rápidos"),
    ("zarpazo_carga", zarpazo_carga, 0.80, -8.0, 6500.0, 0.03, "Carga del zarpazo: retumbo y quejido que suben"),
    ("zarpazo", zarpazo, 0.50, -4.0, 7000.0, 0.10, "Zarpazo cargado: golpe grave y chasquido"),
    ("salto_jaguar", salto_jaguar, 0.50, -6.0, 6500.0, 0.06, "Salto ofensivo: gruñido grave y soplido"),
    ("salto_impacto", salto_impacto, 0.40, -5.0, 6500.0, 0.08, "Impacto del salto contra el suelo"),
    ("golpe", golpe, 0.15, -6.0, 7000.0, 0.03, "Un enemigo recibe un golpe"),
    ("dano", dano, 0.30, -6.0, 5000.0, 0.05, "El jugador recibe daño: golpe sordo y tono que cae"),
    ("caida", caida, 0.90, -7.0, 6500.0, 0.15, "El jugador cae: tres notas tristes que bajan"),
    ("reaparecer", reaparecer, 0.90, -8.0, 7000.0, 0.15, "Reaparición: campanitas que suben con brillo"),
    ("curar", curar, 0.80, -8.0, 7000.0, 0.15, "Curación: arpegio cálido ascendente"),
    ("purificar", purificar, 1.00, -8.0, 7000.0, 0.20, "Purificación: acorde de campanas que florece"),
    ("transformar", transformar, 0.70, -6.0, 7000.0, 0.12, "Transformación: remolino y acorde brillante"),
    ("enemigo_aviso", enemigo_aviso, 0.35, -8.0, 4000.0, 0.03, "Aviso de ataque enemigo: dos tonos tensos"),
    ("enemigo_golpe", enemigo_golpe, 0.40, -5.0, 6500.0, 0.08, "Golpe del guardián de piedra con escombros"),
    ("enemigo_muere", enemigo_muere, 0.50, -7.0, 7000.0, 0.10, "Enemigo derrotado: se desmorona"),
    ("altar_on", altar_on, 0.40, -7.0, 7000.0, 0.08, "Altar activado: piedra y campana"),
    ("altar_off", altar_off, 0.25, -9.0, 2500.0, 0.05, "Altar liberado: más grave y apagado"),
    ("santuario_abre", santuario_abre, 2.20, -3.0, 7000.0, 0.30, "Se abre el santuario: piedra que roza y acorde que crece"),
    ("emboscada", emboscada, 1.60, -3.5, 5000.0, 0.25, "Emboscada: caracol grave y tambor"),
    ("victoria", victoria, 3.20, -3.0, 7000.0, 0.35, "Victoria: frase ascendente y acorde final"),
    ("derrota", derrota, 2.60, -8.0, 6000.0, 0.45, "Derrota: frase lenta descendente, suave"),
    ("ui_click", ui_click, 0.06, -14.0, 5000.0, 0.015, "Clic de interfaz, madera"),
    ("ui_abrir", ui_abrir, 0.20, -15.0, 5000.0, 0.04, "Abrir menú: ola suave"),
    ("sin_energia", sin_energia, 0.15, -14.0, 1800.0, 0.02, "Sin energía: doble pitido apagado"),
    ("objetivo", objetivo, 0.50, -12.0, 7000.0, 0.12, "Objetivo actualizado: dos notas de campanita"),
)


# --------------------------------------------------------------------------------------
# Acabado, escritura y comprobación
# --------------------------------------------------------------------------------------

def acabar_bucle(x, rms_db, agudos):
    """Filtra de forma circular, quita la continua y ajusta el volumen por RMS."""
    x = filtrar(x, 35.0, None, orden=2, circular=True)
    x = filtrar(x, None, agudos, orden=4, circular=True)
    x = x - np.mean(x)
    x = x * (10.0 ** (rms_db / 20.0) / rms(x))
    techo = 10.0 ** (-1.5 / 20.0)
    pico = float(np.max(np.abs(x)))
    return x * (techo / pico) if pico > techo else x


def acabar_efecto(x, seg, pico_db, agudos, fundido):
    """Recorta a la duración, filtra, funde los extremos y ajusta el pico."""
    n = n_(seg)
    x = np.concatenate([x, np.zeros(max(0, n - len(x)))])[:n]
    x = filtrar(x, 30.0, None, orden=2)
    x = filtrar(x, None, agudos, orden=4)
    ventana = rampa(n, 0.002) * salida(n, fundido)
    ventana[0] = 0.0
    x = x * ventana
    x = x - ventana * (np.sum(x) / np.sum(ventana))  # quita la continua sin tocar los extremos
    return x * (10.0 ** (pico_db / 20.0) / float(np.max(np.abs(x))))


def escribir(ruta: Path, x: np.ndarray) -> None:
    datos = np.round(np.clip(x, -1.0, 1.0) * 32767.0).astype("<i2")
    with wave.open(str(ruta), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(datos.tobytes())


def leer(ruta: Path) -> np.ndarray:
    with wave.open(str(ruta), "rb") as w:
        assert (w.getnchannels(), w.getsampwidth(), w.getframerate()) == (1, 2, SR), ruta.name
        return np.frombuffer(w.readframes(w.getnframes()), dtype="<i2").astype(np.float64) / 32768.0


def duraciones(compacto: bool) -> dict:
    """Duración esperada de cada archivo según el perfil."""
    d = {}
    for nombre, _f, normal, corto, *_ in BUCLES:
        arg = corto if compacto else normal
        if nombre == "mus_claro":
            d[nombre] = arg * 4 * 60.0 / 75.0
        elif nombre == "mus_emboscada":
            d[nombre] = arg * 4 * 60.0 / 150.0
        else:
            d[nombre] = float(arg)
    for nombre, _f, seg, *_ in EFECTOS:
        d[nombre] = seg
    return d


def generar(compacto: bool) -> None:
    SALIDA.mkdir(parents=True, exist_ok=True)
    for nombre, fn, normal, corto, rms_db, agudos, _desc in BUCLES:
        escribir(SALIDA / f"{nombre}.wav", acabar_bucle(fn(corto if compacto else normal), rms_db, agudos))
    for nombre, fn, seg, pico_db, agudos, fundido, _desc in EFECTOS:
        escribir(SALIDA / f"{nombre}.wav", acabar_efecto(fn(), seg, pico_db, agudos, fundido))


def comprobar(compacto: bool) -> int:
    """Mide cada archivo y avisa de lo que huela mal. Devuelve el número de avisos."""
    esperada = duraciones(compacto)
    bucles = {b[0] for b in BUCLES}
    total = 0
    avisos_tot = 0
    print(f"{'archivo':<20}{'dur s':>7}{'bucle':>6}{'pico':>7}{'RMS':>7}{'RMS50':>7}{'DC':>9}"
          f"{'<200':>6}{'200-2k':>7}{'2-6k':>6}{'>6k':>5}  {'sha256':<10} avisos")
    for nombre in [b[0] for b in BUCLES] + [e[0] for e in EFECTOS]:
        ruta = SALIDA / f"{nombre}.wav"
        if not ruta.exists():
            print(f"{nombre:<20} FALTA")
            avisos_tot += 1
            continue
        total += ruta.stat().st_size
        x = leer(ruta)
        n = len(x)
        pico = float(np.max(np.abs(x)))
        dc = float(np.mean(x))
        # RMS máximo en ventanas de 50 ms (aproxima la sonoridad del momento más fuerte)
        v = n_(0.05)
        if n >= v:
            ac = np.concatenate([[0.0], np.cumsum(x ** 2)])
            rms50 = float(np.sqrt(np.max(ac[v:] - ac[:-v]) / v))
        else:
            rms50 = rms(x)
        pot = np.abs(np.fft.rfft(x)) ** 2
        f = np.fft.rfftfreq(n, 1.0 / SR)
        tot = float(np.sum(pot)) + 1e-20
        b = [float(np.sum(pot[(f >= a) & (f < c)])) / tot * 100.0
             for a, c in ((0, 200), (200, 2000), (2000, 6000), (6000, 1e9))]
        avisos = []
        if abs(n / SR - esperada[nombre]) > 0.002:
            avisos.append(f"duración≠{esperada[nombre]:.2f}")
        if db(pico) > -1.0:
            avisos.append("pico>-1dB")
        if db(rms(x)) < -45.0:
            avisos.append("casi silencio")
        if abs(dc) > 1e-3:
            avisos.append("continua")
        if b[3] > 25.0:
            avisos.append("mucho >6k")
        dif = np.abs(np.diff(x))
        extra = ""
        if nombre in bucles:
            costura = abs(x[0] - x[-1])
            p50, p99, p999, dmax = (float(np.percentile(dif, q)) for q in (50, 99, 99.9, 100))
            extra = f" costura Δ={costura:.5f} (típico {p50:.5f}, p99 {p99:.5f}, máx {dmax:.5f})"
            if costura > p999:
                avisos.append("salto en la costura")
        else:
            if abs(x[0]) > 2 / 32768 or abs(x[-1]) > 2 / 32768:
                avisos.append("extremos≠0")
            fuerte = np.nonzero(np.abs(x) > pico * 10.0 ** (-50.0 / 20.0))[0]
            cola = (n - 1 - fuerte[-1]) / SR
            if cola > 0.3 * n / SR:
                avisos.append(f"silencio final {cola:.2f}s")
            if fuerte[0] / SR > 0.02:
                avisos.append(f"silencio inicial {fuerte[0] / SR:.3f}s")
        avisos_tot += len(avisos)
        sha = hashlib.sha256(ruta.read_bytes()).hexdigest()[:8]
        print(f"{nombre:<20}{n / SR:>7.3f}{'sí' if nombre in bucles else 'no':>6}{db(pico):>7.1f}"
              f"{db(rms(x)):>7.1f}{db(rms50):>7.1f}{dc:>9.5f}{b[0]:>6.0f}{b[1]:>7.0f}{b[2]:>6.0f}{b[3]:>5.0f}"
              f"  {sha:<10} {', '.join(avisos) if avisos else 'ok'}{extra}")
    print(f"\nTotal: {total} bytes = {total / 1e6:.3f} MB ({total / 2 ** 20:.3f} MiB); "
          f"presupuesto {LIMITE_BYTES / 1e6:.1f} MB")
    if total > LIMITE_BYTES:
        print("AVISO: el total supera el presupuesto (ver README: perfil --compacto o compresión al importar).")
    return avisos_tot


def main() -> int:
    ap = argparse.ArgumentParser(description="Genera y comprueba el audio provisional de ALUX.")
    ap.add_argument("--check", action="store_true", help="solo comprobar los archivos existentes")
    ap.add_argument("--compacto", action="store_true",
                    help="bucles más cortos (música de 4 compases, selva 6.5 s, brasero 2.4 s)")
    ap.add_argument("--salida", type=Path, default=None,
                    help="carpeta de salida (por defecto game/assets/audio)")
    a = ap.parse_args()
    if a.salida is not None:
        global SALIDA
        SALIDA = a.salida.resolve()
    if not a.check:
        generar(a.compacto)
    return 1 if comprobar(a.compacto) else 0


if __name__ == "__main__":
    sys.exit(main())
