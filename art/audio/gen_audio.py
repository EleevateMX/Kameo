#!/usr/bin/env python3
"""Audio provisional de ALUX, sintetizado por código.

Genera todos los `.wav` de `game/assets/audio/` (mono, 22050 Hz, 16 bits PCM) solo con
numpy y el módulo `wave` de la biblioteca estándar. No usa grabaciones ni muestras de
nadie: todo sale de senos, ruido filtrado y envolventes, con semillas fijas, así que el
resultado es original, libre de licencias y reproducible byte a byte.

Uso:
    python art/audio/gen_audio.py              # genera todo y lo comprueba
    python art/audio/gen_audio.py --check      # solo comprueba lo que hay en disco
    python art/audio/gen_audio.py --compacto   # variante con bucles más cortos, ver README
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
LIMITE_BYTES = 2.2e6  # presupuesto pedido para la primera capa (2.2 MB)
LIMITE_JEFE = 3.0e6  # objetivo para lo añadido con el jefe Nojoch Tuunich (~3 MB)


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
# Jefe Nojoch Tuunich: piezas comunes (piedra, Silencio, cristal y motivo)
# --------------------------------------------------------------------------------------

# Parciales de barra de vidrio: más inarmónicos que la campana de jade (corazón de cristal)
PARC_CRISTAL = ((1.0, 1.0, 1.0), (2.76, 0.40, 0.45), (5.40, 0.20, 0.25), (8.93, 0.07, 0.12))

# Motivo del guardián: seis notas con ritmo corta-corta-larga dos veces (pulso de inicio y
# duración, en pulsos). Grados 5-1-3 | 2-1-5: en Re menor suena en la música del combate
# (la única nota fuera de la pentatónica es el Mi de paso) y en Fa mayor, su relativo, en
# la Pluma de Jade y en `mus_recuerdo`. Es propio; no cita ninguna obra.
_RITMO_MOTIVO = ((0, 1), (1, 1), (2, 2), (4, 1), (5, 1), (6, 2))
_MOTIVO_MENOR = (57, 62, 65, 64, 62, 69)  # La Re Fa | Mi Re La
_MOTIVO_MAYOR = (72, 77, 81, 79, 77, 84)  # Do Fa La | Sol Fa Do


def tirones(n, g, lo=6.0, hi=32.0, dureza=1.5):
    """Envolvente irregular de «pega y resbala»: piedra que roza contra piedra."""
    return np.clip(0.55 + 0.6 * lento(n, g, lo, hi), 0.0, None) ** dureza


def crujidos(seg, g, cuantos, banda=(600.0, 3500.0), crece=0.0):
    """Chasquidos de piedra que se agrieta, repartidos al azar.

    Con `crece` > 0 se agolpan y se refuerzan hacia el final; con `crece` < 0 hacen lo
    contrario (la piedra se asienta).
    """
    y = np.zeros(n_(seg))
    for _ in range(cuantos):
        u = g.uniform(0.0, 1.0) ** (1.0 / (1.0 + crece) if crece >= 0 else 1.0 - crece)
        fc = g.uniform(*banda)
        d = g.uniform(0.008, 0.03)
        amp = g.uniform(0.3, 1.0) * (0.25 + 0.75 * (u if crece >= 0 else 1.0 - u))
        poner(y, rafaga(d, g, 0.6 * fc, 1.7 * fc, tau=d / 4.0, ataque=0.0005), u * (seg - 0.05), amp)
        if g.uniform() < 0.3:  # algunos dejan una resonancia corta de piedra
            m = n_(0.05)
            poner(y, np.sin(DOS_PI * fc / 3.0 * t_(m)) * env_perc(m, 0.012), u * (seg - 0.05), 0.6 * amp)
    return y


def chasquido(g, gan=1.0, grave=150.0):
    """Grieta gorda: chasquido seco, resonancia de bloque y un golpe sordo debajo."""
    y = np.zeros(n_(0.25))
    poner(y, rafaga(0.09, g, 700, 5000, tau=0.012, ataque=0.0005), 0.0, 1.0)
    poner(y, modos(((1.6 * grave, 0.6, 0.05), (2.7 * grave, 0.4, 0.035), (5.1 * grave, 0.25, 0.02)), 0.2), 0.0, 0.9)
    poner(y, glis(grave, 0.5 * grave, 0.2) * env_perc(n_(0.2), 0.05), 0.0, 0.7)
    return gan * y


def impacto_piedra(g, seg=0.6, f0=110.0, f1=42.0, tau=0.14, brillo=1.0):
    """Porrazo de piedra: caída grave, golpe de ruido, resonancias de bloque y chasquido."""
    y = np.zeros(n_(seg))
    d = seg - 0.01
    poner(y, glis(f0, f1, d) * env_perc(n_(d), tau, 0.002), 0.0, 1.0)
    poner(y, rafaga(min(d, 0.3), g, 180, 1800, tau=0.03, color=1.0), 0.0, 1.0)
    poner(y, rafaga(min(d, 0.08), g, 1500, 6000, tau=0.009), 0.0, 0.8 * brillo)
    poner(y, modos(((1.9 * f0, 0.5, 0.06), (3.1 * f0, 0.4, 0.045), (4.7 * f0, 0.3, 0.03),
                    (8.2 * f0, 0.15, 0.02)), min(d, 0.35)), 0.0, 1.2)
    poner(y, rafaga(d, g, 45, 300, tau=1.2 * tau, ataque=0.02, color=2.0), 0.0, 0.5)
    return y


def escombros(y, g, t_ini, t_fin, cuantos, lo=500.0, hi=2500.0, gan=0.35, graves=0.0):
    """Cascotes que caen después de un golpe: chasquidos cada vez más flojos y espaciados.

    `graves` es la proporción de cascotes grandes, que suenan además con un golpe sordo.
    """
    for _ in range(cuantos):
        u = g.uniform(0.0, 1.0) ** 1.5
        t0 = t_ini + (t_fin - t_ini) * u
        fc = g.uniform(lo, hi)
        d = g.uniform(0.015, 0.045)
        amp = gan * g.uniform(0.3, 1.0) * (1.0 - 0.8 * u)
        poner(y, rafaga(d, g, 0.6 * fc, 2.2 * fc, tau=d / 4.0, ataque=0.0005), t0, amp)
        if g.uniform() < graves:
            poner(y, glis(g.uniform(140.0, 260.0), 80.0, 0.09) * env_perc(n_(0.09), 0.022), t0, 1.2 * amp)


def gemido(n, g, f, ronco=2.2):
    """Gemido grave de roca (RMS 1): tono bajo con FM y aspereza, como un gruñido muy lento.

    `f` puede ser un número o un array con la frecuencia en cada muestra.
    """
    t = t_(n)
    fc = np.broadcast_to(np.asarray(f, dtype=float), (n,))
    w = fase_de(fc) + ronco * np.sin(fase_de(0.5 * fc))
    aspereza = 1.0 + 0.5 * np.sin(DOS_PI * 23.0 * t + 0.5 * np.sin(DOS_PI * 5.0 * t))
    y = filtrar((np.sin(w) + 0.3 * ruido(n, g, 120, 700, color=1.0)) * aspereza, 55, 1100)
    return y / (rms(y) + 1e-12)


def zumbido(n, g, f, trem=(5.0, 9.0), hondo=0.5, brillo=0.6):
    """Zumbido oscuro del Silencio (RMS 1).

    Grave hueco con una voz desafinada que bate, un tritono encima y un trémolo cuya
    velocidad va de trem[0] a trem[1] Hz. `f` puede ser un número o un array (Hz);
    `brillo` añade armónicos altos.
    """
    u = np.arange(n) / n
    w = fase_de(np.broadcast_to(np.asarray(f, dtype=float), (n,)))
    y = np.zeros(n)
    for razon, amp in ((1.0, 1.0), (1.008, 0.5), (2.0, 0.40), (3.0, 0.32), (2.0 ** 0.5, 0.45),
                       (2.0 * 2.0 ** 0.5, 0.20), (5.0, 0.12)):
        y += amp * np.sin(razon * w + 1.7 * razon)
    for k in (4, 6, 7, 9):  # armónicos altos: lo hacen audible en altavoces pequeños
        y += brillo * 0.6 / k * np.sin(k * w + k)
    y *= 1.0 - hondo * (0.5 + 0.5 * np.sin(fase_de(trem[0] + (trem[1] - trem[0]) * u)))
    y += 0.10 * ruido(n, g, 150, 1200, color=1.5) * np.clip(1.0 + 0.5 * lento(n, g, 2.0, 9.0), 0.0, None)
    return y / (rms(y) + 1e-12)


def latido_cristal(g, m=69):
    """Latido del corazón de cristal: dos pulsos sordos con un anillo vítreo (La)."""
    y = np.zeros(n_(0.9))
    for t0, gan in ((0.0, 1.0), (0.17, 0.7)):
        poner(y, glis(96, 58, 0.14) * env_perc(n_(0.14), 0.04, 0.004), t0, 0.9 * gan)
        poner(y, campana(midi(m), 0.7, tau=0.17, ataque=0.004, parciales=PARC_CRISTAL), t0, 0.6 * gan)
    return y


def motivo(y, g, notas, t0, pulso, gan=1.0, cola=1.2):
    """Pone el motivo del guardián con kalimba y campana de jade; la última nota resuena."""
    for (inicio, dur), m in zip(_RITMO_MOTIVO, notas):
        tt = t0 + inicio * pulso
        ultima = inicio == _RITMO_MOTIVO[-1][0]
        poner(y, kalimba(midi(m), max(0.5, 2.5 * dur * pulso), g), tt, gan * (1.0 if dur == 2 else 0.8))
        poner(y, campana(midi(m), cola if ultima else max(0.35, 1.6 * dur * pulso),
                         tau=0.45 if ultima else 0.12 + 0.10 * dur, ataque=0.004), tt, 0.5 * gan)


def trompa(f, seg, g, ataque=0.06, rel=0.18):
    """Trompa de caracol para melodías: como `cuerno`, con relajación corta para ligar notas."""
    n = n_(seg)
    t = t_(n)
    entrada = 2.0 ** (-0.5 * np.exp(-t / 0.04) / 12.0)
    vib = 1.0 + 0.006 * np.sin(DOS_PI * 5.2 * t) * np.clip((t - 0.25) / 0.4, 0.0, 1.0)
    w = fase_de(f * entrada * vib)
    env = env_asr(n, ataque, min(rel, seg / 2))
    y = np.zeros(n)
    for k in range(1, 12):
        if k * f > 3500:
            break
        y += np.sin(k * w + 0.3 * k) / k ** 1.2 * env ** (1.0 + 0.25 * (k - 1))
    return y + 0.04 * ruido(n, g, 300, 2500, color=1.0) * env


# --------------------------------------------------------------------------------------
# Jefe Nojoch Tuunich: efectos del combate
# --------------------------------------------------------------------------------------

def jefe_despierta():
    """El coloso despierta: la piedra se resquebraja y ruge una masa de roca que se mueve."""
    g = gen("jefe_despierta")
    seg = 3.5
    n = n_(seg)
    t = t_(n)
    y = np.zeros(n)
    # 1) Grietas: crujidos que se agolpan y cinco chasquidos gordos, casi todos a más
    poner(y, crujidos(1.75, g, 60, crece=0.9), 0.0, 0.85)
    for t0, gan in ((0.0, 0.65), (0.34, 0.5), (0.66, 0.8), (1.08, 1.0), (1.44, 1.3)):
        poner(y, chasquido(g, gan, grave=g.uniform(130.0, 170.0)), t0)
    # 2) Rugido: roce de bloques y un gemido grave que sube y vuelve a bajar
    env_r = np.clip((t - 0.9) / 1.3, 0.0, 1.0) ** 1.6 * np.clip((seg - 0.1 - t) / 1.1, 0.0, 1.0) ** 1.2
    y += 0.50 * ruido(n, g, 70, 1100, color=1.1) * tirones(n, g, 5, 26) * env_r
    y += 0.24 * ruido(n, g, 38, 140, color=2.0) * env_r
    m = n_(2.4)
    u = np.arange(m) / m
    poner(y, gemido(m, g, 56.0 + 36.0 * np.sin(np.pi * u) ** 1.5) * np.sin(np.pi * u) ** 1.2, 0.95, 0.42)
    # 3) El bloque encaja: golpe sordo y cascotes
    poner(y, impacto_piedra(g, 0.7, 96, 40, tau=0.16, brillo=0.5), 2.55, 0.42)
    escombros(y, g, 2.62, 3.4, 16, gan=0.16, graves=0.2)
    return reverb(y, g, t60=1.1, mezcla=0.22)


def jefe_paso():
    """Pisada pesada de piedra (se repite a cada paso del coloso)."""
    g = gen("jefe_paso")
    y = np.zeros(n_(0.5))
    poner(y, impacto_piedra(g, 0.45, 92, 38, tau=0.10, brillo=0.35), 0.0, 1.0)
    poner(y, rafaga(0.22, g, 200, 1200, tau=0.035, color=1.0), 0.0, 0.7)  # cuerpo medio del golpe
    escombros(y, g, 0.08, 0.40, 6, lo=600, hi=2200, gan=0.25)
    return saturar(y, 1.6)


def jefe_aviso():
    """Anticipación de un golpe: la piedra se tensa y cruje cada vez más agudo y más rápido."""
    g = gen("jefe_aviso")
    n = n_(0.8)
    u = np.arange(n) / n
    # el «pega y resbala» va de 16 a 75 tirones por segundo
    pulso = np.clip(np.sin(fase_de(16.0 * (75.0 / 16.0) ** (u ** 1.3))), 0.0, 1.0) ** 3
    crujir = ruido_barrido(n, g, 500.0 * (2400.0 / 500.0) ** u, ancho=0.7) * pulso
    w = fase_de(170.0 * (430.0 / 170.0) ** (u ** 1.2))
    tono = (np.sin(w) + 0.4 * np.sin(2 * w) + 0.2 * np.sin(3 * w)) * (0.35 + 0.65 * pulso)
    y = 1.3 * crujir + 0.75 * tono + 0.40 * ruido(n, g, 50, 220, color=2.0)
    return saturar(y * (0.22 + 0.78 * u ** 1.4), 1.8)


def jefe_losa():
    """Golpe de losa: impacto enorme contra el suelo y cola de escombros."""
    g = gen("jefe_losa")
    y = np.zeros(n_(1.2))
    poner(y, impacto_piedra(g, 1.0, 120, 34, tau=0.24, brillo=1.0), 0.0, 1.0)
    poner(y, glis(62, 30, 0.9) * env_perc(n_(0.9), 0.30, 0.004), 0.0, 0.6)  # subgrave que sacude
    poner(y, rafaga(0.5, g, 150, 700, tau=0.11, color=1.5), 0.0, 0.7)
    escombros(y, g, 0.10, 1.12, 30, lo=450, hi=2600, gan=0.9, graves=0.3)
    poner(y, ruido(n_(1.0), g, 900, 4000, color=1.0) * env_perc(n_(1.0), 0.28, 0.06), 0.05, 0.12)  # polvo
    return saturar(reverb(y, g, t60=0.7, mezcla=0.12))


def jefe_barrido():
    """Barrido: silbido grave de una masa que pasa, con roce de piedra."""
    g = gen("jefe_barrido")
    n = n_(0.9)
    u = np.arange(n) / n
    paso_ = np.sin(np.pi * u ** 0.8)  # 0 → 1 → 0: la masa pasa por delante
    aire = ruido_barrido(n, g, 140.0 * 4.5 ** paso_, ancho=0.8, color=1.5, f_min=70.0, f_max=3000.0)
    w = fase_de(74.0 * 2.0 ** (0.45 * paso_))
    masa = np.sin(w) + 0.4 * np.sin(2 * w)
    roce = ruido(n, g, 700, 3200, color=1.0) * tirones(n, g, 14, 55, 2.0)
    return (aire + 0.55 * masa + 0.32 * roce) * paso_ ** 2


def jefe_llamada():
    """Llamada del Silencio: doble golpe en el suelo y un zumbido oscuro que crece."""
    g = gen("jefe_llamada")
    y = np.zeros(n_(1.5))
    for t0, gan in ((0.0, 0.9), (0.26, 1.0)):
        poner(y, impacto_piedra(g, 0.55, 105, 40, tau=0.13, brillo=0.7), t0, gan)
    escombros(y, g, 0.32, 0.9, 8, gan=0.3)
    m = n_(1.2)
    u = np.arange(m) / m
    z = zumbido(m, g, midi(50) * 2.0 ** (2.0 * u / 12.0), trem=(6.0, 14.0))
    poner(y, z * (0.12 + 0.88 * u ** 1.2) * salida(m, 0.10), 0.29, 0.75)
    return y


def jefe_embestida():
    """Embestida: arrastre de piedra y zancadas que se aceleran (acaba fuerte: enlaza con el choque)."""
    g = gen("jefe_embestida")
    n = n_(1.4)
    u = np.arange(n) / n
    zancada = np.clip(np.sin(fase_de(4.0 + 8.0 * u ** 1.2)), 0.0, 1.0) ** 3  # de 4 a 12 por segundo
    grave = ruido(n, g, 40, 260, color=2.0) * (0.35 + 0.65 * zancada)
    arrastre = ruido_barrido(n, g, 220.0 * (900.0 / 220.0) ** u, ancho=0.9, color=1.5, f_min=90.0, f_max=4000.0)
    arrastre *= tirones(n, g, 10, 45, 1.6)
    w = fase_de(48.0 * 2.0 ** (u ** 1.5))
    empuje = (np.sin(w) + 0.5 * np.sin(2 * w) + 0.25 * np.sin(3 * w)) * (0.5 + 0.5 * zancada)
    return (0.9 * grave + 0.8 * arrastre + 0.5 * empuje) * (0.18 + 0.82 * u ** 1.3)


def jefe_choque():
    """Choque de la embestida contra una columna, que se parte y cae a trozos."""
    g = gen("jefe_choque")
    y = np.zeros(n_(1.3))
    poner(y, impacto_piedra(g, 0.8, 135, 44, tau=0.17, brillo=1.3), 0.0, 1.0)
    poner(y, rafaga(0.16, g, 900, 6000, tau=0.02, ataque=0.0005), 0.0, 0.9)  # la columna se parte
    poner(y, modos(((520, 0.5, 0.07), (835, 0.4, 0.05), (1310, 0.3, 0.035), (2140, 0.15, 0.02)), 0.3), 0.004, 0.8)
    for t0, f0, gan in ((0.30, 120.0, 0.55), (0.52, 98.0, 0.45), (0.78, 140.0, 0.30), (0.96, 110.0, 0.18)):
        poner(y, impacto_piedra(g, 0.3, f0, 0.5 * f0, tau=0.06, brillo=0.4), t0 + g.uniform(-0.02, 0.02), gan)
    escombros(y, g, 0.06, 1.22, 38, lo=500, hi=3200, gan=0.9, graves=0.2)
    poner(y, ruido(n_(1.1), g, 900, 4000, color=1.0) * env_perc(n_(1.1), 0.30, 0.06), 0.05, 0.12)  # polvo
    return saturar(reverb(y, g, t60=0.7, mezcla=0.12))


def jefe_aturdido():
    """Aturdido: la piedra cruje y se asienta, con un gemido grave que se hunde."""
    g = gen("jefe_aturdido")
    n = n_(1.5)
    u = np.arange(n) / n
    y = np.zeros(n)
    y += 0.4 * gemido(n, g, 98.0 * (52.0 / 98.0) ** (u ** 0.8)) * rampa(n, 0.08) * (1.0 - 0.6 * u) * salida(n, 0.4)
    poner(y, crujidos(1.4, g, 24, banda=(500.0, 2600.0), crece=-0.8), 0.0, 0.8)
    poner(y, chasquido(g, 0.7, grave=140.0), 0.0)
    poner(y, impacto_piedra(g, 0.4, 88, 44, tau=0.09, brillo=0.3), 0.92, 0.45)  # termina de asentarse
    return reverb(y, g, t60=0.6, mezcla=0.15)


def pilar_sube():
    """Una columna de piedra emerge del suelo y encaja con un tope."""
    g = gen("pilar_sube")
    n = n_(1.0)
    t = t_(n)
    sube = np.clip(t / 0.78, 0.0, 1.0)
    env = rampa(n, 0.03) * (0.3 + 0.7 * sube ** 1.2) * np.where(t < 0.78, 1.0, np.exp(-(t - 0.78) / 0.05))
    roce = ruido_barrido(n, g, 180.0 * (700.0 / 180.0) ** sube, ancho=0.9, color=1.5, f_min=80.0, f_max=3500.0)
    roce *= tirones(n, g, 12, 50, 1.5)
    w = fase_de(52.0 * (118.0 / 52.0) ** sube)
    tono = np.sin(w) + 0.45 * np.sin(2 * w) + 0.2 * np.sin(3 * w)
    y = (0.9 * roce + 0.6 * ruido(n, g, 45, 200, color=2.0) + 0.45 * tono) * env
    poner(y, impacto_piedra(g, 0.21, 150, 70, tau=0.05, brillo=0.8), 0.78, 1.6)
    escombros(y, g, 0.80, 0.95, 7, gan=0.5)
    return y


def lluvia_piedra():
    """Lluvia de piedra: 44 piedras de tamaños distintos que caen a destiempo (no es un bucle)."""
    g = gen("lluvia_piedra")
    seg = 4.0
    n = n_(seg)
    y = 0.02 * ruido(n, g, 200, 1800, color=1.5) * np.clip(1.0 + 0.5 * lento(n, g, 0.5, 4.0), 0.2, None)  # polvo
    instantes = np.sort(g.uniform(0.0, 3.55, 44))
    instantes[0] = 0.0
    for t0 in instantes:
        tam = float(np.clip(np.exp(g.normal(0.0, 0.55)), 0.35, 2.2))  # tamaño relativo de la piedra
        gan = 0.45 * tam ** 0.8 * g.uniform(0.6, 1.0)
        if tam > 1.25 and t0 > 0.25:  # las grandes se oyen venir
            m = n_(0.22)
            v = np.arange(m) / m
            poner(y, ruido_barrido(m, g, 2600.0 * (700.0 / 2600.0) ** v, ancho=0.45) * v ** 2, t0 - 0.22, 0.10 * tam)
        f0 = 150.0 / tam
        poner(y, impacto_piedra(g, 0.35, f0, 0.45 * f0, tau=0.055 * tam, brillo=0.9 / tam ** 0.5), t0, gan)
        for k in range(int(g.integers(0, 3))):  # rebotes
            poner(y, rafaga(0.03, g, 800, 3500, tau=0.006), t0 + 0.07 * (k + 1) + g.uniform(0.0, 0.03),
                  0.6 * gan / (k + 1))
    return reverb(y, g, t60=0.6, mezcla=0.12)


def ancla_activa():
    """Un alux pisa un ancla: tono de jade limpio (Re) sobre el leve ceder de la losa."""
    g = gen("ancla_activa")
    y = np.zeros(n_(0.6))
    poner(y, campana(midi(74), 0.58, tau=0.22, ataque=0.004), 0.0, 1.0)
    poner(y, campana(midi(81), 0.50, tau=0.16, ataque=0.004), 0.0, 0.3)
    n = n_(0.55)
    poner(y, np.sin(DOS_PI * midi(62) * t_(n)) * env_perc(n, 0.2, 0.01), 0.0, 0.35)
    poner(y, rafaga(0.05, g, 300, 1400, tau=0.01, color=1.0), 0.0, 0.25)
    return reverb(y, g, t60=0.5, mezcla=0.12)


def cadenas_jade():
    """Cadenas de energía que se tensan: eslabones vítreos cada vez más juntos y un tirón final."""
    g = gen("cadenas_jade")
    y = np.zeros(n_(1.2))
    escala = (62, 65, 67, 69, 72, 74, 77, 79, 81, 84, 86, 89, 91, 93, 96, 98)
    for i, m in enumerate(escala):
        t0 = 0.82 * (i / len(escala)) ** 0.75  # los eslabones se aprietan
        gan = (1.0 if i % 2 == 0 else 0.6) * (0.5 + 0.5 * i / len(escala))
        poner(y, campana(midi(m), 0.14, tau=0.035, ataque=0.002), t0, gan)
        poner(y, rafaga(0.02, g, 2500, 6000, tau=0.004), t0, 0.25 * gan)
    n = n_(0.86)
    u = np.arange(n) / n
    w = fase_de(146.8 * 2.0 ** u)  # la tensión sube una octava (Re3 → Re4)
    tension = (np.sin(w) + 0.3 * np.sin(2 * w)) * (0.7 + 0.3 * np.sin(DOS_PI * 22.0 * t_(n)))
    poner(y, tension * u ** 1.5 * salida(n, 0.03), 0.0, 0.55)
    poner(y, ruido_barrido(n, g, 900.0 * (3800.0 / 900.0) ** u, ancho=0.5) * u ** 2 * salida(n, 0.05), 0.0, 0.25)
    for m, gan in ((74, 0.9), (81, 0.7), (86, 0.8), (93, 0.4)):  # tirón: quinta de jade que queda vibrando
        poner(y, campana(midi(m), 0.34, tau=0.16, ataque=0.003), 0.85, gan)
    return reverb(y, g, t60=0.6, mezcla=0.18)


def corazon_expuesto():
    """El corazón de la espalda queda expuesto: latido de cristal y brillo que asciende."""
    g = gen("corazon_expuesto")
    y = np.zeros(n_(1.0))
    poner(y, latido_cristal(g), 0.0, 1.0)
    for i, m in enumerate((74, 77, 81, 86, 89)):
        poner(y, campana(midi(m), 0.5, tau=0.18, ataque=0.004, parciales=PARC_CRISTAL), 0.36 + 0.09 * i, 0.35 + 0.08 * i)
    n = n_(0.6)
    u = np.arange(n) / n
    poner(y, ruido_barrido(n, g, 1500.0 * (5000.0 / 1500.0) ** u, ancho=0.5) * u ** 2 * salida(n, 0.12), 0.34, 0.22)
    _destellos(y, g, 0.55, 0.92, 7, 3000, 6000, 0.15)
    return reverb(y, g, t60=0.7, mezcla=0.2)


def corazon_golpe():
    """Golpe de Balam sobre el corazón de cristal: chasquido y resonancia vítrea (La)."""
    g = gen("corazon_golpe")
    y = np.zeros(n_(0.4))
    poner(y, rafaga(0.05, g, 1800, 6500, tau=0.008), 0.0, 0.8)
    poner(y, glis(240, 120, 0.1) * env_perc(n_(0.1), 0.03), 0.0, 0.6)
    poner(y, campana(midi(81), 0.38, tau=0.11, ataque=0.002, parciales=PARC_CRISTAL), 0.0, 1.0)
    poner(y, campana(midi(86), 0.30, tau=0.08, ataque=0.002, parciales=PARC_CRISTAL), 0.0, 0.35)
    _destellos(y, g, 0.03, 0.28, 5, 3000, 6000, 0.15)
    return reverb(y, g, t60=0.4, mezcla=0.15)


def corazon_libre():
    """El corazón se suelta: el cristal cede y un acorde de Fa mayor asciende."""
    g = gen("corazon_libre")
    y = np.zeros(n_(1.6))
    poner(y, rafaga(0.10, g, 1500, 6500, tau=0.015), 0.0, 0.7)
    poner(y, modos(((1320, 0.5, 0.07), (2210, 0.4, 0.055), (3640, 0.3, 0.04)), 0.3), 0.0, 0.6)
    _destellos(y, g, 0.02, 0.5, 10, 2500, 6000, 0.25)
    for i, m in enumerate((65, 69, 72, 77, 81, 84)):
        t0 = 0.12 + 0.11 * i
        poner(y, campana(midi(m), 1.45 - t0, tau=0.45, ataque=0.006, parciales=PARC_CRISTAL), t0, 0.55 + 0.05 * i)
        poner(y, kalimba(midi(m), 0.8, g), t0, 0.45)
    for m in (53, 60, 65, 69):
        poner(y, colchon(midi(m), 1.35, 0.5, 0.6), 0.15, 0.20)
    n = n_(0.8)
    u = np.arange(n) / n
    poner(y, ruido_barrido(n, g, 1400.0 * (4500.0 / 1400.0) ** u, ancho=0.5) * u ** 1.5 * salida(n, 0.2), 0.1, 0.18)
    poner(y, campana(midi(89), 0.6, tau=0.3, ataque=0.006), 0.90, 0.35)
    return reverb(y, g, t60=1.2, mezcla=0.25)


def glifo_restaurado():
    """Un glifo del pecho se enciende: campana de jade ceremonial, con armónicos y respuesta aguda."""
    g = gen("glifo_restaurado")
    y = np.zeros(n_(1.2))
    poner(y, rafaga(0.05, g, 300, 1500, tau=0.012, color=1.0), 0.0, 0.3)
    poner(y, campana(midi(74), 1.15, tau=0.50, ataque=0.004), 0.0, 1.0)
    poner(y, campana(midi(81), 1.10, tau=0.42, ataque=0.004), 0.015, 0.55)
    poner(y, campana(midi(86), 1.00, tau=0.35, ataque=0.004), 0.03, 0.40)
    n = n_(1.1)
    poner(y, np.sin(DOS_PI * midi(62) * t_(n)) * env_perc(n, 0.45, 0.01), 0.0, 0.35)
    poner(y, campana(midi(93), 0.7, tau=0.30, ataque=0.004), 0.40, 0.28)
    return reverb(y, g, t60=1.1, mezcla=0.28)


def ritual_toque():
    """Canalizar el toque: acorde cálido de Fa sostenido que crece y se abre.

    Entra en 0.15 s y sale en 0.3 s: relanzándolo cada 1.7 s (sin variación de tono) las
    copias se solapan y hacen de fundido cruzado.
    """
    g = gen("ritual_toque")
    n = n_(2.0)
    t = t_(n)
    u = np.arange(n) / n
    y = np.zeros(n)
    for m, gan in ((53, 0.9), (60, 0.8), (65, 1.0), (69, 0.7)):
        w = DOS_PI * midi(m) * t
        voz = np.sin(w) + 0.30 * u * np.sin(2 * w + 0.5) + 0.18 * u ** 2 * np.sin(3 * w + 1.1)
        y += gan * voz * (1.0 + 0.04 * np.sin(DOS_PI * 4.0 * t + m))
    y *= 0.70 + 0.30 * u ** 1.2
    y += 0.12 * ruido_barrido(n, g, 1200.0 * (3500.0 / 1200.0) ** u, ancho=0.5) * u ** 2  # halo
    return y * rampa(n, 0.15)


def silencio_grieta():
    """El Silencio se agrieta: el zumbido oscuro sube, se quiebra y cae en esquirlas."""
    g = gen("silencio_grieta")
    y = np.zeros(n_(0.8))
    m = n_(0.33)
    u = np.arange(m) / m
    z = zumbido(m, g, 110.0 * 2.0 ** (3.0 * u / 12.0), trem=(9.0, 30.0))
    poner(y, z * rampa(m, 0.01) * (0.5 + 0.5 * u) * salida(m, 0.02), 0.0, 0.45)
    tq = 0.30  # instante del quiebre
    poner(y, rafaga(0.12, g, 900, 6500, tau=0.016, ataque=0.0005), tq, 1.2)
    k = n_(0.3)
    v = np.arange(k) / k
    wq = fase_de(1100.0 * (160.0 / 1100.0) ** (v ** 0.6))
    poner(y, (np.sin(wq) + 0.4 * np.sin(1.5 * wq)) * env_perc(k, 0.07, 0.002), tq, 0.8)  # desgarro que cae
    for i in range(9):  # esquirlas: granos que caen de tono
        d = n_(0.06)
        f = g.uniform(500.0, 1900.0) * (1.0 - 0.5 * i / 9)
        grano = np.sin(fase_de(f * 0.6 ** (np.arange(d) / d))) * env_perc(d, 0.015, 0.001)
        poner(y, grano, tq + 0.03 + 0.42 * (i / 9) ** 1.3 + g.uniform(0.0, 0.02), 0.45 * (1.0 - 0.6 * i / 9))
    r = n_(0.45)
    resto = zumbido(r, g, 110.0 * 2.0 ** (-7.0 * np.arange(r) / r / 12.0), trem=(24.0, 7.0))
    poner(y, resto * env_perc(r, 0.13, 0.005), tq + 0.02, 0.30)
    return reverb(y, g, t60=0.5, mezcla=0.15)


def liberacion():
    """El Silencio se disuelve: el zumbido oscuro afloja su tritono, se apaga y florece Fa mayor."""
    g = gen("liberacion")
    n = n_(4.0)
    y = np.zeros(n)
    # Zumbido en Re: el tritono (La bemol) resbala hasta la quinta justa (La) antes de apagarse
    m = n_(2.7)
    tm = t_(m)
    um = np.arange(m) / m
    f = midi(50)
    w = DOS_PI * f * tm
    wt = fase_de(f * 2.0 ** 0.5 * 2.0 ** (np.clip((tm - 0.8) / 1.1, 0.0, 1.0) / 12.0))
    oscuro = (0.6 * np.sin(0.5 * w) + np.sin(w) + 0.7 * np.sin(1.008 * w + 1.0) + 0.40 * np.sin(2 * w + 0.4)
              + 0.30 * np.sin(3 * w + 2.0) + 0.16 * np.sin(4 * w + 0.9) + 0.12 * np.sin(6 * w + 1.5)
              + 0.55 * np.sin(wt) + 0.25 * np.sin(2 * wt + 0.7) + 0.10 * np.sin(4 * wt + 0.2))
    oscuro *= 1.0 - 0.5 * (1.0 - um) * (0.5 + 0.5 * np.sin(fase_de(9.0 - 6.0 * um)))  # el trémolo se calma
    oscuro += 0.25 * ruido(m, g, 150, 1200, color=1.5) * (1.0 - um) ** 2
    oscuro *= rampa(m, 0.02) * (0.5 + 0.5 * np.cos(np.pi * np.clip((tm - 1.0) / 1.7, 0.0, 1.0)))
    poner(y, oscuro, 0.0, 0.50)
    # Acorde luminoso
    for i, mi in enumerate((41, 53, 60, 65, 69, 72)):
        poner(y, colchon(midi(mi), 2.75, 1.1, 0.9), 1.2, 0.26 if i else 0.34)
    for i, (mi, gan) in enumerate(((77, 0.9), (81, 0.8), (84, 0.8), (89, 0.6))):
        t0 = 2.0 + 0.17 * i
        poner(y, campana(midi(mi), 3.95 - t0, tau=0.7, ataque=0.008), t0, gan)
        poner(y, kalimba(midi(mi), 1.2, g), t0, 0.5 * gan)
    k = n_(1.4)
    v = np.arange(k) / k
    poner(y, ruido_barrido(k, g, 1200.0 * (4800.0 / 1200.0) ** v, ancho=0.5) * np.sin(np.pi * v) ** 2, 1.3, 0.16)
    _destellos(y, g, 2.2, 3.5, 14, 2800, 6000, 0.12, tau=0.012)
    return reverb(y, g, t60=1.5, mezcla=0.28)


def pluma_jade():
    """Aparece la Pluma de Jade: el motivo del guardián en Fa mayor, seis notas."""
    g = gen("pluma_jade")
    y = np.zeros(n_(2.5))
    motivo(y, g, _MOTIVO_MAYOR, 0.0, 0.2, cola=1.25)
    for m in (53, 60, 65):
        poner(y, colchon(midi(m), 1.4, 0.4, 0.8), 1.05, 0.14)
    poner(y, flauta(midi(84), 1.1, g, ataque=0.08, rel=0.7, vib=0.006), 1.25, 0.22)
    _destellos(y, g, 1.3, 2.2, 9, 3000, 6000, 0.10, tau=0.012)
    return reverb(y, g, t60=1.3, mezcla=0.25)


# --------------------------------------------------------------------------------------
# Jefe Nojoch Tuunich: sonido de los planos de las dos cinemáticas (4 s cada uno)
# --------------------------------------------------------------------------------------

def cine_patio_silencio():
    """Despertar, plano 1: el patio casi vacío, tenso, y un único latido del cristal."""
    g = gen("cine_patio_silencio")
    n = n_(4.0)
    t = t_(n)
    aire = ruido(n, g, 250, 1400, color=1.5) * np.clip(1.0 + 0.35 * lento(n, g, 0.25, 1.5), 0.3, None)
    f = midi(38)
    grave = np.sin(DOS_PI * f * t) + 0.8 * np.sin(DOS_PI * f * 1.006 * t + 1.0) + 0.5 * np.sin(DOS_PI * 2 * f * t + 2.0)
    # tensión: dos tonos agudos casi iguales que baten despacio, muy flojos
    fino = np.sin(DOS_PI * 1174.7 * t) + np.sin(DOS_PI * 1177.4 * t + 0.6)
    y = (0.050 * aire + 0.050 * grave + 0.009 * fino) * rampa(n, 0.02)
    poner(y, reverb(latido_cristal(g), g, t60=1.4, mezcla=0.35), 2.0, 0.55)
    return y


def cine_grietas():
    """Despertar, plano 2: grietas que crecen, raíces que se parten y polvo que cae."""
    g = gen("cine_grietas")
    n = n_(4.0)
    u = np.arange(n) / n
    y = np.zeros(n)
    poner(y, crujidos(3.6, g, 130, crece=0.8), 0.0, 0.8)
    poner(y, crujidos(1.6, g, 22), 0.0, 0.4)  # los primeros, sueltos, para que el plano no arranque vacío
    for t0, gan in ((0.0, 0.30), (0.9, 0.45), (1.7, 0.60), (2.4, 0.75), (2.95, 0.88), (3.35, 1.0)):
        poner(y, chasquido(g, gan, grave=g.uniform(120.0, 170.0)), t0)
        k = n_(0.6)
        poner(y, ruido(k, g, 1800, 5000, color=1.0) * env_perc(k, 0.2, 0.06), t0 + 0.03, 0.10 * gan)  # polvo
        escombros(y, g, t0 + 0.05, t0 + 0.5, 5, lo=900, hi=3200, gan=0.22 * gan)
    for t0 in (2.62, 3.12):  # raíces que se parten (chasquido leñoso)
        poner(y, modos(((330, 0.7, 0.03), (520, 0.5, 0.025), (880, 0.3, 0.015)), 0.12), t0, 0.5)
        poner(y, rafaga(0.04, g, 800, 3000, tau=0.006), t0, 0.4)
    y += 0.30 * ruido(n, g, 40, 180, color=2.0) * u ** 1.5
    y += 0.05 * ruido(n, g, 1200, 4500, color=1.0) * (0.3 + 0.7 * u) * tirones(n, g, 3, 14)  # arenilla
    return reverb(y, g, t60=0.9, mezcla=0.2)


def cine_ojos():
    """Despertar, plano 3: el jade parpadea, el zumbido magenta sube y los ojos se abren (dos golpes secos)."""
    g = gen("cine_ojos")
    n = n_(4.0)
    t = t_(n)
    sube = np.clip(t / 3.0, 0.0, 1.0)
    z = zumbido(n, g, midi(50) * 2.0 ** (5.0 * sube ** 1.3 / 12.0), trem=(5.0, 13.0))
    z *= np.where(t < 3.0, 0.15 + 0.85 * sube ** 1.6, 0.30 + 0.70 * np.exp(-(t - 3.0) / 0.05))
    y = np.zeros(n)
    poner(y, campana(midi(86), 0.3, tau=0.08), 0.35, 0.40)  # los glifos parpadean en jade…
    poner(y, campana(midi(86), 0.3, tau=0.08), 0.60, 0.50)
    k = n_(0.7)
    v = np.arange(k) / k
    wk = fase_de(1174.7 * (830.6 / 1174.7) ** np.clip(v / 0.5, 0.0, 1.0))
    poner(y, (np.sin(wk) + 0.3 * np.sin(2 * wk)) * env_perc(k, 0.22, 0.004), 0.90, 0.55)  # …y se tiñen
    y = reverb(y + 0.70 * z, g, t60=0.8, mezcla=0.18)[:n]
    for t0, gan in ((3.0, 0.9), (3.38, 1.0)):  # golpes secos, sin reverberación
        poner(y, impacto_piedra(g, 0.26, 92, 50, tau=0.05, brillo=1.2), t0, gan)
    return y


def cine_en_pie():
    """Despertar, plano 4: el coloso se incorpora (arrastre grave y temblor) y remata con un golpe."""
    g = gen("cine_en_pie")
    n = n_(4.0)
    t = t_(n)
    y = np.zeros(n)
    sube = np.clip(t / 2.7, 0.0, 1.0)
    env = (0.2 + 0.8 * sube ** 1.3) * np.where(t < 2.7, 1.0, np.exp(-(t - 2.7) / 0.12))
    y += 0.48 * ruido(n, g, 60, 1100, color=1.1) * tirones(n, g, 4, 18) * env
    y += 0.34 * ruido(n, g, 30, 110, color=2.0) * (0.55 + 0.45 * np.sin(DOS_PI * 7.5 * t)) * env  # temblor
    m = n_(2.4)
    u = np.arange(m) / m
    poner(y, gemido(m, g, 50.0 * (96.0 / 50.0) ** u) * rampa(m, 0.3) * (0.4 + 0.6 * u) * salida(m, 0.15), 0.35, 0.30)
    poner(y, crujidos(2.6, g, 34, banda=(400.0, 2200.0), crece=0.6), 0.1, 0.60)
    poner(y, impacto_piedra(g, 0.95, 125, 34, tau=0.25, brillo=1.0), 3.0, 1.0)
    poner(y, glis(60, 30, 0.9) * env_perc(n_(0.9), 0.30, 0.004), 3.0, 0.6)
    escombros(y, g, 3.08, 3.92, 22, gan=0.40, graves=0.3)
    return reverb(y, g, t60=1.0, mezcla=0.2)


def cine_silencio_se_va():
    """Liberación, plano 1: el zumbido oscuro se apaga y entran cuatro notas de jade, una a una."""
    g = gen("cine_silencio_se_va")
    n = n_(4.0)
    y = np.zeros(n)
    m = n_(2.5)
    u = np.arange(m) / m
    z = zumbido(m, g, midi(50) * 2.0 ** (-3.0 * u / 12.0), trem=(8.0, 2.5))
    poner(y, z * rampa(m, 0.03) * (1.0 - u) ** 1.1, 0.0, 0.55)
    for i, mi in enumerate((72, 77, 81, 84)):  # una por glifo: Do, Fa, La, Do
        t0 = 0.55 + 0.75 * i
        poner(y, campana(midi(mi), 3.95 - t0, tau=0.75, ataque=0.005), t0, 0.75)
        poner(y, kalimba(midi(mi), 1.2, g), t0, 0.5)
        k = n_(1.0)
        poner(y, np.sin(DOS_PI * midi(mi - 12) * t_(k)) * env_perc(k, 0.4, 0.02), t0, 0.2)
    for mi in (53, 60, 65, 69):
        poner(y, colchon(midi(mi), 2.2, 1.3, 0.7), 1.75, 0.15)
    return reverb(y, g, t60=1.4, mezcla=0.28)


def cine_pluma():
    """Liberación, plano 2: brillo y el motivo de la Pluma de Jade, al doble de lento."""
    g = gen("cine_pluma")
    n = n_(4.0)
    y = np.zeros(n)
    poner(y, campana(midi(96), 0.5, tau=0.2, ataque=0.004), 0.0, 0.25)
    k = n_(1.3)
    v = np.arange(k) / k
    poner(y, ruido_barrido(k, g, 1800.0 * (5000.0 / 1800.0) ** v, ancho=0.5) * np.sin(np.pi * v) ** 2, 0.0, 0.14)
    _destellos(y, g, 0.05, 3.3, 20, 3000, 6200, 0.11, tau=0.012)
    for mi in (53, 60, 65, 69):
        poner(y, colchon(midi(mi), 3.9, 0.9, 1.0), 0.0, 0.18)
    motivo(y, g, _MOTIVO_MAYOR, 0.45, 0.4, cola=1.1)
    return reverb(y, g, t60=1.4, mezcla=0.28)


def cine_cenote():
    """Liberación, plano 3: calma, viento suave y un destello lejano de agua."""
    g = gen("cine_cenote")
    n = n_(4.0)
    u = np.arange(n) / n
    viento = ruido(n, g, 120, 900, color=1.5) * np.clip(1.0 + 0.4 * lento(n, g, 0.25, 2.0), 0.3, None)
    hojas = ruido(n, g, 1500, 4000, color=1.0) * np.clip(0.5 + 0.5 * lento(n, g, 0.3, 3.0), 0.0, None)
    y = (0.060 * viento + 0.012 * hojas) * (0.7 + 0.3 * np.sin(np.pi * u)) * rampa(n, 0.02)
    for mi in (53, 60):
        poner(y, colchon(midi(mi), 3.9, 1.5, 1.5), 0.0, 0.035)
    agua = np.zeros(n_(1.2))
    for i in range(6):  # gotas y reflejos
        f0 = g.uniform(700.0, 1400.0)
        d = g.uniform(0.03, 0.05)
        poner(agua, glis(f0, 1.8 * f0, d) * env_perc(n_(d), d / 3.0, 0.002), 0.09 * i + g.uniform(0.0, 0.04),
              0.5 * (1.0 - 0.1 * i))
    poner(agua, campana(midi(93), 0.6, tau=0.25, ataque=0.006), 0.05, 0.5)
    poner(agua, campana(midi(96), 0.5, tau=0.20, ataque=0.006), 0.22, 0.3)
    agua = filtrar(reverb(agua, g, t60=1.8, mezcla=0.6), 400, 4500)  # lejano: apagado y con mucha sala
    poner(y, agua, 2.25, 0.20)
    return y


# --------------------------------------------------------------------------------------
# Jefe Nojoch Tuunich: música
# --------------------------------------------------------------------------------------
# `mus_jefe` y `mus_jefe_furia` comparten tonalidad (Re menor), tempo (120 BPM), armonía y
# la posición del motivo, para poder pasar de una a otra con el fundido de `set_music`.
# Cada sección son cuatro compases: (raíces del dron, notas de la trompa).

_SEC_JEFE = {
    "A": dict(raices=(38, 38, 38, 38), dos=((74, 77),) * 4),
    "B": dict(raices=(34, 34, 38, 38), dos=((74, 77),) * 4),
    "C": dict(raices=(43, 36, 38, 33), dos=((74, 79), (72, 79), (74, 77), (76, 81))),
}
_VARIANTE_MENOR = (62, 65, 69, 67, 65, 74)  # el motivo una cuarta más arriba, sobre Si bemol
_LARGAS_JEFE = ((0, 4, 55), (4, 4, 60), (8, 6, 62), (14, 2, 57))  # (pulso, duración, nota) de la sección C
_FORMA_JEFE = {12: "ABC", 8: "AC"}


def golpe_roca(g):
    """Bombo de piedra: grave largo con golpe mate (pulso de la música del jefe)."""
    y = tambor(76, 0.7, g, tau=0.20, barrido=0.9, t_barr=0.03, piel=0.6, banda=(120.0, 900.0), tau_piel=0.03)
    poner(y, modos(((128, 0.75, 0.10), (197, 0.55, 0.07), (296, 0.30, 0.045)), 0.4), 0.0, 1.0)
    return y


def choque_losas(g):
    """Dos losas que chocan: hace de caja en la música del jefe."""
    y = np.zeros(n_(0.28))
    poner(y, modos(((392, 0.6, 0.05), (611, 0.5, 0.04), (987, 0.35, 0.03), (1570, 0.2, 0.02)), 0.26), 0.0, 1.0)
    poner(y, rafaga(0.12, g, 500, 3500, tau=0.02, color=1.0), 0.0, 0.9)
    return y


def capas_jefe(compases, furia):
    """Capas de la música del jefe (120 BPM, 4/4, rejilla de semicorcheas de 0.125 s)."""
    g = gen("mus_jefe_furia" if furia else "mus_jefe")
    negra = 0.5
    semi = negra / 4
    comp = 4 * negra
    n = n_(compases * comp)
    c = {k: np.zeros(n) for k in ("roca", "losas", "grava", "dron", "trompa", "kalimba")}

    def frase(notas, t0, gan=1.0, octava=0):
        """El motivo en la trompa, doblado por una kalimba grave que marca el ataque."""
        for (inicio, dur), m in zip(_RITMO_MOTIVO, notas):
            tt = t0 + inicio * negra
            poner(c["trompa"], trompa(midi(m + octava), dur * negra * 1.08, g), tt, gan, circular=True)
            poner(c["kalimba"], kalimba(midi(m + octava + 12), 0.9, g, brillo=0.6), tt, 0.8 * gan, circular=True)

    for i, sec in enumerate(_FORMA_JEFE[compases]):
        ts = i * 4 * comp
        for j, raiz in enumerate(_SEC_JEFE[sec]["raices"]):
            t0 = ts + j * comp
            cierre = sec == "C" and j == 3  # último compás: redoble que empuja a la vuelta
            if furia:
                rocas = ((0, 1.0), (3, 0.7), (6, 0.8), (8, 0.95), (11, 0.7), (14, 0.8))
                losas = ((4, 0.9), (10, 0.5), (12, 0.9), (13, 0.6), (14, 0.75), (15, 0.9)) if cierre \
                    else ((4, 0.9), (12, 0.9)) + (((15, 0.5),) if j % 2 else ())
                grava = [(s, 0.9 if s % 4 == 2 else (0.55 if s % 2 == 0 else 0.3)) for s in range(16)]
                pulsos, largo = 8, 0.25
            else:
                rocas = ((0, 0.9), (6, 0.6), (8, 0.7), (10, 0.8), (12, 0.9), (14, 1.0)) if cierre \
                    else ((0, 1.0), (6, 0.55), (10, 0.75))
                losas = ((4, 0.7), (12, 0.9), (15, 0.6)) if cierre else ((8, 0.9),) + (((15, 0.4),) if j % 2 else ())
                grava = [(s, 0.8 if s % 4 == 2 else 0.4) for s in range(0, 16, 2)]
                pulsos, largo = 4, 0.5
            for s, vel in rocas:
                poner(c["roca"], golpe_roca(g), t0 + s * semi, vel, circular=True)
            for s, vel in losas:
                poner(c["losas"], choque_losas(g), t0 + s * semi, vel, circular=True)
            for s, vel in grava:
                poner(c["grava"], rafaga(0.07, g, 1800, 5000, tau=0.018, ataque=0.004, color=1.0),
                      t0 + s * semi, vel, circular=True)
            # Dron grave que late (cada pulso arranca en fase 0 y se apaga)
            m = n_(largo)
            tp = t_(m)
            w = DOS_PI * midi(raiz) * tp
            pulso = (0.7 * np.sin(w) + 0.8 * np.sin(2 * w) + 0.5 * np.sin(3 * w)
                     + 0.25 * np.sin(4 * w) + 0.12 * np.sin(5 * w))
            pulso *= rampa(m, 0.004) * (0.35 + 0.65 * np.exp(-tp / (0.24 * largo + 0.012))) * salida(m, 0.008)
            for k in range(pulsos):
                poner(c["dron"], pulso, t0 + k * largo, 1.0 if k % 2 == 0 else 0.75, circular=True)
            if furia:  # ostinato de dos notas, como en la emboscada
                notas = _SEC_JEFE[sec]["dos"][j]
                for s, cual, vel in ((0, 0, 1.0), (3, 0, 0.75), (6, 1, 0.9), (10, 0, 0.8), (12, 1, 0.9)):
                    poner(c["kalimba"], kalimba(midi(notas[cual]), 0.5, g), t0 + s * semi, 0.7 * vel, circular=True)
        # Melodía de la sección
        if sec == "A":
            frase(_MOTIVO_MENOR, ts)
            if furia:
                frase(_MOTIVO_MENOR, ts + 2 * comp, 0.8, octava=12)
            else:  # eco lejano de la segunda mitad del motivo
                for inicio, m in ((4, 76), (5, 74), (6, 81)):
                    poner(c["kalimba"], kalimba(midi(m), 0.9, g, brillo=0.6), ts + 2 * comp + inicio * negra,
                          0.45, circular=True)
        elif sec == "B":
            frase(_VARIANTE_MENOR, ts)
            frase(_MOTIVO_MENOR, ts + 2 * comp)
            frase(_MOTIVO_MENOR, ts + 2 * comp, 0.45, octava=12)
        else:
            for inicio, dur, m in _LARGAS_JEFE:
                poner(c["trompa"], trompa(midi(m), dur * negra * 1.04, g, ataque=0.12, rel=0.3),
                      ts + inicio * negra, 0.9, circular=True)
                if furia:
                    poner(c["trompa"], trompa(midi(m + 12), dur * negra * 1.04, g, ataque=0.12, rel=0.3),
                          ts + inicio * negra, 0.4, circular=True)
    return c, g


def _acabar_tambores(y):
    """Saturación suave de los picos de tambor (sin memoria, no afecta a la costura)."""
    y = y / rms(y)
    return 5.0 * np.tanh(y / 5.0)


def mus_jefe(compases):
    """Combate contra Nojoch Tuunich: solemne y pesada, a medio tiempo."""
    c, g = capas_jefe(compases, furia=False)
    y = (0.85 * c["roca"] + 1.20 * c["losas"] + 0.30 * c["grava"] + 0.50 * c["dron"]
         + 0.30 * c["trompa"] + 0.36 * c["kalimba"])
    return _acabar_tambores(reverb(y, g, t60=0.9, mezcla=0.18, circular=True))


def mus_jefe_furia(compases):
    """Fase de furia: la misma música con el pulso doblado, sonaja continua y ostinato."""
    c, g = capas_jefe(compases, furia=True)
    y = (0.80 * c["roca"] + 1.20 * c["losas"] + 0.42 * c["grava"] + 0.50 * c["dron"]
         + 0.30 * c["trompa"] + 0.45 * c["kalimba"])
    return _acabar_tambores(reverb(y, g, t60=0.6, mezcla=0.14, circular=True))


# Recuerdo: acordes de Fa mayor pentatónica (colchón, bajo y arpegio de acompañamiento)
_AC_REC = {
    "fa": dict(pad=(53, 57, 60), bajo=41, arp=(65, 69, 72)),
    "re": dict(pad=(50, 57, 65), bajo=38, arp=(62, 65, 69)),
    "do": dict(pad=(48, 55, 62), bajo=36, arp=(60, 62, 67)),
}
_PROG_REC = {8: ("fa", "fa", "re", "do", "fa", "fa", "re", "do"), 4: ("fa", "fa", "re", "do")}
_RESPUESTA_1 = tuple(zip(_RITMO_MOTIVO, (81, 79, 77, 74, 77, 79)))  # La Sol Fa | Re Fa Sol
_RESPUESTA_2 = (((0, 1), 84), ((1, 1), 81), ((2, 2), 77), ((4, 4), 79))  # Do La Fa | Sol (larga)
# Frases: (compás de inicio, notas con su ritmo, con brillo)
_FRASES_REC = {
    8: ((0, tuple(zip(_RITMO_MOTIVO, _MOTIVO_MAYOR)), False), (2, _RESPUESTA_1, False),
        (4, tuple(zip(_RITMO_MOTIVO, _MOTIVO_MAYOR)), True), (6, _RESPUESTA_2, False)),
    4: ((0, tuple(zip(_RITMO_MOTIVO, _MOTIVO_MAYOR)), True), (2, _RESPUESTA_2, False)),
}


def capas_recuerdo(compases):
    """Capas de `mus_recuerdo` (80 BPM, 4/4): el motivo del guardián en Fa mayor."""
    g = gen("mus_recuerdo")
    negra = 60.0 / 80.0
    comp = 4 * negra
    n = n_(compases * comp)
    c = {k: np.zeros(n) for k in ("colchon", "bajo", "arpegio", "kalimba", "brillo", "flauta", "tambor")}
    for i, nombre in enumerate(_PROG_REC[compases]):
        ac = _AC_REC[nombre]
        t0 = i * comp
        for m in ac["pad"]:
            poner(c["colchon"], colchon(midi(m), comp + 1.6, 1.1, 1.5), t0 - 0.4, circular=True)
        poner(c["bajo"], bajo(midi(ac["bajo"] + 12), comp * 0.95), t0, circular=True)
        for k, corchea in enumerate((1, 3, 5, 7)):  # arpegio a contratiempo, muy suave
            poner(c["arpegio"], kalimba(midi(ac["arp"][k % 3]), 1.2, g, brillo=0.5),
                  t0 + corchea * negra / 2 + g.uniform(-0.005, 0.005), 0.8 if k % 2 == 0 else 0.6, circular=True)
        for tiempo, vel in ((0, 1.0), (2, 0.6)):
            poner(c["tambor"], tambor(95, 0.4, g, tau=0.14, barrido=0.5, piel=0.15, banda=(200, 1200)),
                  t0 + tiempo * negra, vel, circular=True)
        poner(c["tambor"], tambor(210, 0.15, g, tau=0.04, barrido=0.3, piel=0.3, banda=(500, 2500), tau_piel=0.01),
              t0 + 3 * negra, 0.3, circular=True)
    for compas, frase, con_brillo in _FRASES_REC[compases]:
        for (inicio, dur), m in frase:
            tt = compas * comp + inicio * negra + g.uniform(-0.005, 0.005)
            poner(c["kalimba"], kalimba(midi(m), 1.8, g), tt, 1.0 if dur >= 2 else 0.85, circular=True)
            if dur >= 2:  # la flauta sostiene las notas largas
                poner(c["flauta"], flauta(midi(m), dur * negra * 0.95, g, ataque=0.09, rel=0.3), tt, 1.0, circular=True)
            if con_brillo:
                poner(c["brillo"], campana(midi(m + 12), 1.2, tau=0.3, ataque=0.004), tt, 0.6, circular=True)
    for k in ("kalimba", "brillo"):  # eco de corchea con puntillo
        c[k] = c[k] + 0.28 * np.roll(c[k], n_(0.75 * negra)) + 0.12 * np.roll(c[k], n_(1.5 * negra))
    return c, g


def mus_recuerdo(compases):
    """El guardián recuerda: calmada y esperanzada, el motivo en modo mayor."""
    c, g = capas_recuerdo(compases)
    y = (0.32 * c["colchon"] + 0.35 * c["bajo"] + 0.30 * c["arpegio"] + 0.95 * c["kalimba"]
         + 0.30 * c["brillo"] + 0.45 * c["flauta"] + 0.40 * c["tambor"])
    return reverb(y, g, t60=1.7, mezcla=0.30, circular=True)


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

# Jefe Nojoch Tuunich (mismo formato de tablas). Los tres bucles son música.
BUCLES_JEFE = (
    ("mus_jefe", mus_jefe, 12, 8, -22.0, 6500.0, "Música del jefe: Re menor, 120 BPM a medio tiempo, percusión de piedra"),
    ("mus_jefe_furia", mus_jefe_furia, 12, 8, -22.0, 7000.0, "Música de la fase de furia: mismo tono y tempo, más densa"),
    ("mus_recuerdo", mus_recuerdo, 8, 4, -22.0, 7000.0, "Música del recuerdo: el motivo en Fa mayor, 80 BPM"),
)

EFECTOS_JEFE = (
    ("jefe_despierta", jefe_despierta, 3.50, -3.0, 6500.0, 0.35, "El coloso despierta: grietas y rugido de roca"),
    ("jefe_paso", jefe_paso, 0.50, -8.0, 4500.0, 0.12, "Pisada pesada de piedra"),
    ("jefe_aviso", jefe_aviso, 0.80, -7.0, 6000.0, 0.04, "Anticipación de un golpe: piedra que se tensa"),
    ("jefe_losa", jefe_losa, 1.20, -3.0, 6500.0, 0.25, "Golpe de losa: impacto enorme y escombros"),
    ("jefe_barrido", jefe_barrido, 0.90, -6.0, 5500.0, 0.08, "Barrido: silbido grave de masa y roce"),
    ("jefe_llamada", jefe_llamada, 1.50, -4.0, 6000.0, 0.12, "Llamada del Silencio: doble golpe y zumbido que crece"),
    ("jefe_embestida", jefe_embestida, 1.40, -5.0, 6000.0, 0.05, "Embestida: arrastre de piedra que se acelera"),
    ("jefe_choque", jefe_choque, 1.30, -3.0, 6500.0, 0.30, "Choque contra una columna que se rompe"),
    ("jefe_aturdido", jefe_aturdido, 1.50, -7.0, 5500.0, 0.35, "Aturdido: la piedra se asienta con un gemido"),
    ("pilar_sube", pilar_sube, 1.00, -5.0, 6000.0, 0.06, "Una columna emerge del suelo"),
    ("lluvia_piedra", lluvia_piedra, 4.00, -5.0, 6500.0, 0.40, "Lluvia de piedra: caídas irregulares"),
    ("ancla_activa", ancla_activa, 0.60, -9.0, 7000.0, 0.12, "Ancla pisada: tono de jade limpio"),
    ("cadenas_jade", cadenas_jade, 1.20, -7.0, 7000.0, 0.15, "Cadenas de energía que se tensan"),
    ("corazon_expuesto", corazon_expuesto, 1.00, -7.0, 7000.0, 0.15, "Corazón expuesto: latido de cristal y brillo"),
    ("corazon_golpe", corazon_golpe, 0.40, -6.0, 7500.0, 0.08, "Golpe sobre el corazón de cristal"),
    ("corazon_libre", corazon_libre, 1.60, -5.0, 7000.0, 0.30, "El corazón se suelta: acorde ascendente"),
    ("glifo_restaurado", glifo_restaurado, 1.20, -9.0, 7000.0, 0.25, "Glifo encendido: campana de jade ceremonial"),
    ("ritual_toque", ritual_toque, 2.00, -10.0, 6000.0, 0.30, "Canalizar el toque: acorde cálido que crece"),
    ("silencio_grieta", silencio_grieta, 0.80, -6.0, 7000.0, 0.15, "El Silencio se agrieta"),
    ("liberacion", liberacion, 4.00, -3.0, 7000.0, 0.60, "El Silencio se disuelve en un acorde mayor"),
    ("pluma_jade", pluma_jade, 2.50, -6.0, 7000.0, 0.50, "Aparece la Pluma de Jade: motivo de seis notas"),
    ("cine_patio_silencio", cine_patio_silencio, 4.00, -8.0, 6000.0, 0.40, "Cinemática: patio en silencio y un latido"),
    ("cine_grietas", cine_grietas, 4.00, -4.0, 6500.0, 0.40, "Cinemática: grietas que crecen y polvo"),
    ("cine_ojos", cine_ojos, 4.00, -3.0, 6500.0, 0.40, "Cinemática: zumbido magenta y dos golpes secos"),
    ("cine_en_pie", cine_en_pie, 4.00, -3.0, 6500.0, 0.40, "Cinemática: el coloso se incorpora"),
    ("cine_silencio_se_va", cine_silencio_se_va, 4.00, -6.0, 7000.0, 0.60, "Cinemática: el zumbido se apaga y entran cuatro notas"),
    ("cine_pluma", cine_pluma, 4.00, -6.0, 7000.0, 0.60, "Cinemática: brillo y motivo de la pluma, lento"),
    ("cine_cenote", cine_cenote, 4.00, -11.0, 6000.0, 0.50, "Cinemática: calma, viento y destello de agua"),
)

NOMBRES_JEFE = frozenset(x[0] for x in BUCLES_JEFE + EFECTOS_JEFE)
BUCLES = BUCLES + BUCLES_JEFE
EFECTOS = EFECTOS + EFECTOS_JEFE

# Segundos por compás de cada música (su argumento en BUCLES es el número de compases)
SEG_COMPAS = {"mus_claro": 4 * 60.0 / 75.0, "mus_emboscada": 4 * 60.0 / 150.0,
              "mus_jefe": 4 * 60.0 / 120.0, "mus_jefe_furia": 4 * 60.0 / 120.0, "mus_recuerdo": 4 * 60.0 / 80.0}


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
        d[nombre] = arg * SEG_COMPAS.get(nombre, 1.0)
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
    total_jefe = 0
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
        if nombre in NOMBRES_JEFE:
            total_jefe += ruta.stat().st_size
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
    print(f"\nTotal: {total} bytes = {total / 1e6:.3f} MB ({total / 2 ** 20:.3f} MiB)")
    print(f"  primera capa: {(total - total_jefe) / 1e6:.3f} MB (presupuesto {LIMITE_BYTES / 1e6:.1f} MB); "
          f"jefe: {total_jefe / 1e6:.3f} MB (objetivo {LIMITE_JEFE / 1e6:.1f} MB)")
    if total - total_jefe > LIMITE_BYTES or total_jefe > LIMITE_JEFE:
        print("AVISO: se supera el presupuesto en bruto (ver README: perfil --compacto o compresión al importar).")
    return avisos_tot


def main() -> int:
    ap = argparse.ArgumentParser(description="Genera y comprueba el audio provisional de ALUX.")
    ap.add_argument("--check", action="store_true", help="solo comprobar los archivos existentes")
    ap.add_argument("--compacto", action="store_true",
                    help="bucles más cortos (música con menos compases, selva 6.5 s, brasero 2.4 s)")
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
