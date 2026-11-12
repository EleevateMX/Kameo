#!/usr/bin/env python3
"""Música de ALUX (Alpha 0.3.1), sintetizada por código y renderizada a archivos.

Genera las diez piezas de `game/web/static/audio/` (MP3 estéreo, 44.1 kHz) solo con numpy
y `ffmpeg` (libmp3lame). No usa grabaciones ni muestras de nadie: todo sale de senos, ruido
filtrado y envolventes, con semillas fijas, así que la música es original del proyecto,
no tiene licencias que cumplir y se puede volver a generar igual.

Es un script autónomo: no importa `gen_audio.py`. Los instrumentos parten de los de aquel
(kalimba, flauta de barro, tambor, campana, cuerno, trompa, colchón, bajo) rehechos a
44.1 kHz y en estéreo, y los motivos de `capas_claro`, `capas_emboscada`, `capas_jefe` y
`capas_recuerdo` se conservan y se desarrollan aquí.

Uso:
    python art/audio/gen_musica.py                    # genera todo, lo codifica y lo comprueba
    python art/audio/gen_musica.py --solo mus_claro   # solo algunas piezas (separadas por comas)
    python art/audio/gen_musica.py --check            # solo mide y valida lo que hay en disco
    python art/audio/gen_musica.py --espectros        # además, una hoja de espectrograma por pieza
    python art/audio/gen_musica.py --tmp DIR          # carpeta de WAV intermedios y espectrogramas
    python art/audio/gen_musica.py --detalle          # imprime el nivel de cada instrumento en la mezcla

Convención de bucle (la aplica el reproductor del juego con `loopStart`/`loopEnd`):

    [ pre = últimos 0.5 s del cuerpo ][ cuerpo, L segundos ][ post = primeros 0.5 s del cuerpo ]

y el manifiesto declara `"loop": [0.5, 0.5 + L]`. El cuerpo es circular de verdad: las colas
de reverb y las notas que cruzan el final se suman al principio.
"""

from __future__ import annotations

import argparse
import json
import re
import subprocess
import sys
import tempfile
import wave
import zlib
from pathlib import Path

import numpy as np

SR = 44100  # frecuencia de muestreo
SEMILLA = 20261112  # semilla base; cada pieza y cada nota derivan la suya de su nombre
DOS_PI = 2.0 * np.pi
RAIZ = Path(__file__).resolve().parents[2]
SALIDA = RAIZ / "game" / "web" / "static" / "audio"
DOC = RAIZ / "art" / "audio"
MARGEN = 0.5  # segundos de «pre» y de «post» alrededor del cuerpo del bucle
LIMITE_ARCHIVO = 1.1e6  # bytes por archivo
LIMITE_TOTAL = 9.0e6  # bytes en total
PICO_MAX = -1.5  # dBFS, pico real medido sobre el MP3 decodificado


# --------------------------------------------------------------------------------------
# Utilidades básicas
# --------------------------------------------------------------------------------------

def gen(nombre: str) -> np.random.Generator:
    """Generador aleatorio propio de cada cosa (independiente del orden de ejecución)."""
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
    return float(np.sqrt(np.mean(np.square(x)))) if x.size else 0.0


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
    """Envolvente percusiva: ataque corto y caída exponencial con constante `tau`."""
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
    """Filtra en el dominio de la frecuencia (último eje; vale para mono y estéreo).

    Con `circular=True` la señal se trata como periódica (lo que necesitan los bucles);
    si no, se rellena con ceros para que la cola no se enrolle sobre el principio.
    """
    n = x.shape[-1]
    m = 0 if circular else 2048
    if m:
        relleno = [(0, 0)] * (x.ndim - 1) + [(m, m)]
        x = np.pad(x, relleno)
    nn = x.shape[-1]
    h = _respuesta(np.fft.rfftfreq(nn, 1.0 / SR), lo, hi, orden)
    y = np.fft.irfft(np.fft.rfft(x, axis=-1) * h, nn, axis=-1)
    return y if circular else y[..., m:m + n]


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


def fase_de(f) -> np.ndarray:
    """Fase acumulada de una frecuencia variable (array en Hz)."""
    return DOS_PI * np.cumsum(f) / SR


def glis(f0, f1, seg):
    """Seno con barrido exponencial de f0 a f1."""
    n = n_(seg)
    u = np.arange(n) / n
    return np.sin(fase_de(f0 * (f1 / f0) ** u))


def panear(x, pan):
    """Mono → estéreo con ley de potencia constante. pan: -1 izquierda, 0 centro, +1 derecha."""
    a = (np.clip(pan, -1.0, 1.0) + 1.0) * np.pi / 4.0
    return np.stack([np.cos(a) * x, np.sin(a) * x])


def sumar(buf, x, i0, circular):
    """Suma `x` en `buf` desde la muestra i0. Con `circular`, lo que se sale da la vuelta."""
    n = buf.shape[-1]
    m = x.shape[-1]
    if circular:
        i0 %= n
        k = 0
        while k < m:
            c = min(m - k, n - i0)
            buf[..., i0:i0 + c] += x[..., k:k + c]
            k += c
            i0 = 0
    else:
        a, b = max(i0, 0), min(i0 + m, n)
        if b > a:
            buf[..., a:b] += x[..., a - i0:b - i0]


def desplazar(x, muestras, circular):
    """Retrasa una señal (último eje). En circular da la vuelta; si no, entra silencio."""
    if circular:
        return np.roll(x, muestras, axis=-1)
    y = np.zeros_like(x)
    if muestras < x.shape[-1]:
        y[..., muestras:] = x[..., :x.shape[-1] - muestras]
    return y


# --------------------------------------------------------------------------------------
# Instrumentos (todos devuelven mono salvo los que dicen «estéreo»)
# --------------------------------------------------------------------------------------
# Cada nota se pide a través de `nota()`, que la guarda en caché y le da un generador
# aleatorio derivado de sus parámetros: así una nota suena igual se pida en el orden que
# se pida, y las variantes (`var`) hacen de «round robin» para que dos golpes seguidos no
# sean idénticos.

_CACHE: dict = {}


def nota(inst, *args, var=0, **kw):
    clave = (inst.__name__, args, tuple(sorted(kw.items())), var)
    if clave not in _CACHE:
        _CACHE[clave] = inst(*args, g=gen(repr(clave)), **kw)
    return _CACHE[clave]


def _afina(m, g, cents=3.0):
    """Frecuencia de la nota con una desafinación mínima (humaniza los unísonos)."""
    return midi(m) * 2.0 ** (g.uniform(-cents, cents) / 1200.0)


def kalimba(m, seg, g, brillo=1.0):
    """Lengüeta tipo kalimba: fundamental, 4.º armónico de caída rápida y el toque del pulgar."""
    f = _afina(m, g)
    tau = 0.55 * (261.6 / f) ** 0.5
    n = n_(min(seg, 5.0 * tau))
    t = t_(n)
    y = np.sin(DOS_PI * f * t) * np.exp(-t / tau)
    y += 0.06 * np.sin(DOS_PI * 2 * f * t + 0.5) * np.exp(-t / (0.5 * tau))
    for razon, amp, kt in ((4.0, 0.40, 0.28), (6.3, 0.07, 0.10), (9.6, 0.03, 0.05)):
        if razon * f < 14000:
            y += amp * brillo * np.sin(DOS_PI * razon * f * t) * np.exp(-t / (kt * tau))
    k = min(n, n_(0.025))
    y[:k] += 0.22 * brillo * ruido(k, g, 800, 6000) * np.exp(-t[:k] / 0.004)
    return y * rampa(n, 0.0015) * salida(n, 0.03)


def marimba(m, seg, g, dureza=1.0):
    """Tecla de madera con resonador: parciales 1 : 4 : 9.9 y el golpe de la baqueta."""
    f = _afina(m, g)
    tau = 0.40 * (220.0 / f) ** 0.6
    n = n_(min(seg, 6.0 * tau) + 0.02)
    t = t_(n)
    y = np.sin(DOS_PI * f * t) * np.exp(-t / tau)
    y += 0.25 * np.sin(DOS_PI * f * t + 0.2) * (1.0 - np.exp(-t / 0.012)) * np.exp(-t / (1.3 * tau))
    y += 0.28 * dureza * np.sin(DOS_PI * 4 * f * t + 0.3) * np.exp(-t / (0.25 * tau))
    if 9.9 * f < 14000:
        y += 0.08 * dureza * np.sin(DOS_PI * 9.9 * f * t) * np.exp(-t / (0.08 * tau))
    k = min(n, n_(0.02))
    y[:k] += 0.30 * ruido(k, g, 300, 3000 * dureza) * np.exp(-t[:k] / 0.003)
    return y * rampa(n, 0.0012) * salida(n, 0.03)


def flauta(m, seg, g, vib=0.005, aire=0.08, ataque=0.07, rel=0.12, cae=0.0, brillo=1.0):
    """Flauta de barro: tono casi puro, vibrato que tarda en entrar, soplo y deriva de afinación.

    `cae` baja el tono al final (en semitonos) para frases que «suspiran»; `brillo` es la
    cantidad de armónicos (con 0.25 queda una ocarina).
    """
    f = midi(m)
    n = n_(seg)
    t = t_(n)
    u = np.arange(n) / n
    v = vib * np.sin(DOS_PI * g.uniform(4.8, 5.8) * t + g.uniform(0, DOS_PI)) * np.clip((t - 0.18) / 0.4, 0.0, 1.0)
    deriva = 0.0015 * lento(n, g, 0.3, 3.0)
    entrada = 2.0 ** (-0.35 * np.exp(-t / 0.03) / 12.0)
    w = fase_de(f * (1.0 + v + deriva) * entrada * 2.0 ** (-cae * u ** 2 / 12.0))
    y = (np.sin(w) + 0.22 * brillo * np.sin(2 * w) + 0.07 * brillo * np.sin(3 * w)
         + 0.025 * brillo * np.sin(4 * w) + 0.012 * brillo * np.sin(5 * w))
    soplo = ruido(n, g, 1.5 * f, min(7.0 * f, 9000.0)) * (1.0 + 2.5 * np.exp(-t / 0.05))
    alto = 0.25 * ruido(n, g, 7000.0, 15000.0, color=1.0)
    env = env_asr(n, ataque, min(rel, seg / 2)) * (1.0 + 0.05 * lento(n, g, 1.5, 7.0))
    return (y + aire * (soplo + alto)) * env


def ocarina(m, seg, g, vib=0.004, aire=0.11, ataque=0.045, rel=0.15, cae=0.0):
    """Ocarina: como la flauta de barro pero más redonda y con más soplo."""
    return flauta(m, seg, g, vib=vib, aire=aire, ataque=ataque, rel=rel, cae=cae, brillo=0.25)


# Formantes de vocal: (frecuencia central, ancho, amplitud)
_VOCALES = {
    "u": ((320.0, 70.0, 1.0), (800.0, 90.0, 0.35), (2400.0, 160.0, 0.05)),
    "o": ((450.0, 80.0, 1.0), (850.0, 100.0, 0.50), (2600.0, 170.0, 0.07)),
    "a": ((700.0, 100.0, 1.0), (1150.0, 110.0, 0.60), (2800.0, 180.0, 0.12)),
}
_REJILLA = np.arange(4097) / 4096.0


def _tabla_vocal(f0, vocal):
    """Un periodo de la onda de una voz: armónicos pesados por los formantes de la vocal."""
    tabla = np.zeros(4097)
    for k in range(1, int(min(4500.0 / f0, 40)) + 1):
        a = sum(amp / (1.0 + ((k * f0 - fc) / bw) ** 2) for fc, bw, amp in _VOCALES[vocal])
        tabla += (a + 0.02) / k ** 0.5 * np.sin(DOS_PI * k * _REJILLA + 0.7 * k * k)
    return tabla / rms(tabla)


def coro(m, seg, g, vocal="o", ataque=1.0, rel=1.4, voces=3, ancho=0.7):
    """Colchón de voces y aire (estéreo): varias voces desafinadas con vibrato propio."""
    f0 = midi(m)
    n = n_(seg)
    t = t_(n)
    tabla = _tabla_vocal(f0, vocal)
    y = np.zeros((2, n))
    for v in range(voces):
        des = (v - (voces - 1) / 2.0) * 0.0035 + g.uniform(-0.001, 0.001)
        vibr = 0.004 * np.sin(DOS_PI * g.uniform(4.6, 5.6) * t + g.uniform(0, DOS_PI))
        fase = np.cumsum(f0 * (1.0 + des + vibr + 0.002 * lento(n, g, 0.2, 2.0))) / SR + g.uniform()
        voz = np.interp(fase % 1.0, _REJILLA, tabla)
        voz += 0.10 * ruido(n, g, 400.0, 3200.0, color=1.0)  # aliento
        voz *= 1.0 + 0.08 * lento(n, g, 0.5, 4.0)
        y += panear(voz, ancho * (2.0 * v / max(voces - 1, 1) - 1.0))
    return y / np.sqrt(voces) * env_asr(n, ataque, min(rel, seg / 2))


def colchon(m, seg, g, ataque=1.1, rel=1.5, ancho=0.6):
    """Colchón cálido (estéreo): tres voces desafinadas de onda casi triangular."""
    f = midi(m)
    n = n_(seg)
    t = t_(n)
    y = np.zeros((2, n))
    for i, desaf in enumerate((-0.004, 0.0, 0.004)):
        w = DOS_PI * f * (1.0 + desaf) * t + g.uniform(0, DOS_PI)
        voz = np.sin(w) + np.sin(3 * w) / 9.0 + np.sin(5 * w) / 25.0
        y += panear(voz, ancho * (i - 1))
    return y / 3.0 * env_asr(n, ataque, min(rel, seg / 2))


def bajo(m, seg, g, tau=1.2):
    """Nota grave suave: seno con armónicos débiles y un toque de madera al empezar."""
    f = midi(m)
    n = n_(seg)
    t = t_(n)
    w = DOS_PI * f * t
    y = np.sin(w) + 0.35 * np.sin(2 * w) + 0.10 * np.sin(3 * w) + 0.04 * np.sin(4 * w)
    k = min(n, n_(0.03))
    y[:k] += 0.15 * ruido(k, g, 150, 900) * np.exp(-t[:k] / 0.006)
    return y * rampa(n, 0.02) * np.exp(-t / tau) * salida(n, min(0.3, seg / 2))


def tambor(f0, seg, g, tau=0.12, barrido=0.6, t_barr=0.025, piel=0.3,
           banda=(300.0, 2500.0), tau_piel=0.012):
    """Tambor sencillo: seno que baja de tono + ruido del golpe en el parche."""
    n = n_(seg)
    t = t_(n)
    w = fase_de(f0 * (1.0 + barrido * np.exp(-t / t_barr)))
    y = np.sin(w) * np.exp(-t / tau)
    y += piel * ruido(n, g, banda[0], banda[1], color=1.0) * np.exp(-t / tau_piel)
    return y * rampa(n, 0.001) * salida(n, min(0.03, seg / 3))


# Modos de una membrana ideal respecto al fundamental: (razón, amplitud, factor de duración)
_MODOS_PARCHE = ((1.59, 0.45, 0.55), (2.14, 0.30, 0.40), (2.30, 0.22, 0.35),
                 (2.65, 0.16, 0.30), (2.92, 0.12, 0.25), (3.60, 0.07, 0.20))


def huehuetl(f0, seg, g, tau=0.30, barrido=0.5, piel=0.35, fuerza=1.0):
    """Tambor grave de parche tipo huéhuetl: fundamental que cae, modos de membrana y la mano."""
    n = n_(seg)
    t = t_(n)
    f0 = f0 * (1.0 + g.uniform(-0.012, 0.012))
    y = np.sin(fase_de(f0 * (1.0 + barrido * np.exp(-t / 0.03)))) * np.exp(-t / tau)
    for razon, amp, kt in _MODOS_PARCHE:
        y += amp * g.uniform(0.7, 1.1) * np.sin(DOS_PI * f0 * razon * t + g.uniform(0, DOS_PI)) * np.exp(-t / (tau * kt))
    y += piel * ruido(n, g, 120.0, 1800.0 * fuerza, color=1.0) * np.exp(-t / 0.018)
    y += 0.10 * piel * fuerza * ruido(n, g, 2000.0, 7000.0) * np.exp(-t / 0.004)
    return y * rampa(n, 0.0012) * salida(n, min(0.05, seg / 3))


def tambor_mano(f0, seg, g, fuerza=1.0):
    """Tambor de mano agudo: golpe corto de dedos en el borde del parche."""
    return huehuetl(f0, seg, g, tau=0.05, barrido=0.3, piel=0.55, fuerza=fuerza)


def teponaztli(m, seg, g, dureza=1.0):
    """Lengüeta de un tambor de hendidura tipo teponaztli: madera hueca golpeada con baqueta."""
    f = midi(m) * (1.0 + g.uniform(-0.004, 0.004))
    n = n_(seg)
    t = t_(n)
    y = np.zeros(n)
    for razon, amp, tau in ((1.0, 1.0, 0.16), (2.76, 0.30, 0.05), (5.40, 0.12, 0.025), (8.93, 0.04, 0.012)):
        y += amp * np.sin(DOS_PI * f * razon * t + razon) * np.exp(-t / tau)
    y += 0.35 * ruido(n, g, 250.0, 1100.0, color=1.0) * np.exp(-t / 0.03)  # el tronco hueco
    y += 0.20 * dureza * ruido(n, g, 1500.0, 6000.0) * np.exp(-t / 0.002)  # la baqueta
    return y * rampa(n, 0.001) * salida(n, min(0.04, seg / 3))


def sonaja(seg, g, lo=3000.0, hi=11000.0, tau=0.03, ataque=0.006):
    """Sonaja de semillas: ruido agudo con grano irregular (las semillas no caen a la vez)."""
    n = n_(seg)
    t = t_(n)
    y = ruido(n, g, lo, hi, orden=3)
    grano = np.clip(0.6 + 0.8 * ruido(n, g, 40.0, 400.0), 0.0, None) ** 1.5
    return y * grano * rampa(n, ataque) * np.exp(-t / tau) * salida(n, seg / 4)


def palo_lluvia(seg, g, densidad=220.0, sentido=1.0):
    """Palo de lluvia (estéreo): cascada de granos que recorre el panorama de un lado a otro."""
    n = n_(seg)
    u = np.arange(n) / n
    perfil = np.sin(np.pi * u) ** 0.7
    cdf = np.cumsum(perfil)
    cuantos = int(densidad * seg)
    pos = np.searchsorted(cdf / cdf[-1], g.uniform(size=cuantos))
    pos = np.minimum(pos, n - 1)
    amp = g.uniform(0.2, 1.0, cuantos) ** 2 * (0.4 + 0.6 * perfil[pos])
    pan = np.clip(sentido * (1.2 * pos / n - 0.6) + g.uniform(-0.3, 0.3, cuantos), -1.0, 1.0)
    ang = (pan + 1.0) * np.pi / 4.0
    cual = g.integers(0, 6, cuantos)
    kn = n_(0.02)
    tk = t_(kn)
    y = np.zeros((2, n + kn))
    nn = n + kn
    for j, fc in enumerate((2200.0, 3100.0, 4300.0, 5900.0, 7700.0, 10000.0)):
        grano = ruido(kn, g, 0.7 * fc, 1.5 * fc) * np.exp(-tk / 0.003) * rampa(kn, 0.0004)
        grano += 0.3 * np.sin(DOS_PI * 0.5 * fc * tk) * np.exp(-tk / 0.002)
        esp = np.fft.rfft(grano, nn)
        sel = cual == j
        for canal, peso in ((0, np.cos(ang)), (1, np.sin(ang))):
            imp = np.zeros(nn)
            np.add.at(imp, pos[sel], amp[sel] * peso[sel])
            y[canal] += np.fft.irfft(np.fft.rfft(imp) * esp, nn)
    return y


# Parciales de barra/campana: (razón de frecuencia, amplitud, factor de duración)
PARC_CAMPANA = ((1.0, 1.0, 1.0), (2.0, 0.45, 0.7), (3.01, 0.25, 0.5),
                (4.2, 0.16, 0.35), (5.43, 0.09, 0.25))


def campana(m, seg, g, tau=0.35, ataque=0.003):
    """Campanita de jade: parciales algo inarmónicos; los agudos se apagan antes."""
    f = _afina(m, g, 4.0)
    n = n_(seg)
    t = t_(n)
    y = np.zeros(n)
    for razon, amp, kt in PARC_CAMPANA:
        if f * razon < 14000:
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


def caracol(m, seg, g, crece=0.5):
    """Caracol grave: armónicos que se abren con la envolvente y entrada desde abajo."""
    f = midi(m)
    n = n_(seg)
    t = t_(n)
    entrada = 2.0 ** (-0.7 * np.exp(-t / 0.045) / 12.0)
    vib = 1.0 + 0.007 * np.sin(DOS_PI * 5.6 * t) * np.clip((t - 0.35) / 0.4, 0.0, 1.0)
    w = fase_de(f * entrada * vib * (1.0 + 0.0012 * lento(n, g, 0.3, 3.0)))
    env = rampa(n, 0.07) * (0.8 + 0.2 * np.clip(t / crece, 0.0, 1.0)) * salida(n, min(0.45, seg / 2))
    y = np.zeros(n)
    for k in range(1, 16):
        if k * f > 5000:
            break
        y += np.sin(k * w + 0.3 * k) / k * env ** (1.0 + 0.3 * (k - 1))
    return y + 0.05 * ruido(n, g, 300, 2500, color=1.0) * env


def trompa(m, seg, g, ataque=0.06, rel=0.18):
    """Trompa de caracol para melodías: como `caracol`, con relajación corta para ligar notas."""
    f = midi(m)
    n = n_(seg)
    t = t_(n)
    entrada = 2.0 ** (-0.5 * np.exp(-t / 0.04) / 12.0)
    vib = 1.0 + 0.006 * np.sin(DOS_PI * g.uniform(4.9, 5.5) * t) * np.clip((t - 0.25) / 0.4, 0.0, 1.0)
    w = fase_de(f * entrada * vib * (1.0 + 0.0012 * lento(n, g, 0.3, 3.0)))
    env = env_asr(n, ataque, min(rel, seg / 2))
    y = np.zeros(n)
    for k in range(1, 14):
        if k * f > 4200:
            break
        y += np.sin(k * w + 0.3 * k) / k ** 1.2 * env ** (1.0 + 0.25 * (k - 1))
    return y + 0.04 * ruido(n, g, 300, 2500, color=1.0) * env


def cuerda(m, seg, g, tau=1.6, brillo=1.0, pos=0.19):
    """Cuerda pulsada (síntesis aditiva): los armónicos altos se apagan antes, leve inarmonía."""
    f = _afina(m, g, 4.0)
    n = n_(seg)
    t = t_(n)
    k = np.arange(1, int(min(11000.0 / f, 36)) + 1)[:, None]
    fk = k * f * np.sqrt(1.0 + 8e-5 * k ** 2)
    amp = np.sin(np.pi * k * pos) / k ** (1.25 - 0.2 * brillo)
    tk = tau * (220.0 / f) ** 0.35 / (1.0 + 0.12 * k ** 1.4)
    fases = g.uniform(0, DOS_PI, k.shape)
    y = np.sum(amp * np.sin(DOS_PI * fk * t + fases) * np.exp(-t / tk), axis=0)
    y += 0.10 * np.sin(DOS_PI * 185.0 * t) * np.exp(-t / 0.06)  # la caja
    q = min(n, n_(0.015))
    y[:q] += 0.08 * ruido(q, g, 1500, 7000) * np.exp(-t[:q] / 0.002)  # la uña
    return y * rampa(n, 0.002) * salida(n, min(0.08, seg / 3))


def golpe_roca(g):
    """Bombo de piedra: grave largo con golpe mate (pulso de la música del jefe)."""
    y = tambor(76, 0.7, g, tau=0.20, barrido=0.9, t_barr=0.03, piel=0.6, banda=(120.0, 900.0), tau_piel=0.03)
    x = modos(((128, 0.75, 0.10), (197, 0.55, 0.07), (296, 0.30, 0.045)), 0.4)
    y[:len(x)] += x
    return y


def choque_losas(g):
    """Dos losas que chocan: hace de caja en la música del jefe."""
    y = np.zeros(n_(0.28))
    x = modos(((392, 0.6, 0.05), (611, 0.5, 0.04), (987, 0.35, 0.03), (1570, 0.2, 0.02)), 0.26)
    y[:len(x)] += x
    x = rafaga(0.12, g, 500, 4500, tau=0.02, color=1.0)
    y[:len(x)] += 0.9 * x
    return y


def grava(g):
    """Gravilla que salta: hace de platillo en la música del jefe."""
    return rafaga(0.07, g, 1800, 7000, tau=0.018, ataque=0.004, color=1.0)


def pulso_dron(m, largo, g):
    """Pulso del dron grave que late: arranca en fase 0 y se apaga."""
    n = n_(largo)
    t = t_(n)
    w = DOS_PI * midi(m) * t
    y = (0.7 * np.sin(w) + 0.8 * np.sin(2 * w) + 0.5 * np.sin(3 * w)
         + 0.25 * np.sin(4 * w) + 0.12 * np.sin(5 * w) + 0.06 * np.sin(6 * w + 0.4))
    return y * rampa(n, 0.004) * (0.35 + 0.65 * np.exp(-t / (0.24 * largo + 0.012))) * salida(n, 0.008)


def dron_peligro(seg, g):
    """Dron grave de la tensión (estéreo, periódico en `seg`).

    Re grave con voces que baten, y por encima un tritono (La bemol) y una segunda menor
    (Mi bemol) que asoman y se van. Todas las frecuencias se redondean a un número entero
    de ciclos por bucle para que la costura sea exacta.
    """
    n = n_(seg)
    t = t_(n)

    def q(f):
        return round(f * seg) / seg

    def ciclo(k, fase=0.0):
        return np.sin(DOS_PI * k * t / seg + fase)

    f0 = midi(38)
    y = np.zeros((2, n))
    parciales = ((0.5, 0.30), (1.0, 1.0), (1.0035, 0.6), (1.5, 0.22), (2.0, 0.45), (2.006, 0.30),
                 (3.0, 0.25), (4.0, 0.14), (5.0, 0.09), (6.0, 0.07), (7.0, 0.04), (9.0, 0.03))
    for i, (razon, amp) in enumerate(parciales):
        voz = amp * (0.75 + 0.25 * ciclo(1 + i % 3, 1.3 * i)) * np.sin(DOS_PI * q(f0 * razon) * t + i)
        y += panear(voz, 0.5 * np.sin(2.1 * i))
    tritono = np.clip(ciclo(2, -1.0), 0.0, 1.0) ** 2
    for razon, amp, pan in ((1.0, 0.32, -0.4), (1.004, 0.20, 0.4), (2.0, 0.10, 0.2)):
        y += panear(amp * tritono * np.sin(DOS_PI * q(midi(56) * razon) * t), pan)
    segunda = np.clip(ciclo(1, 2.0), 0.0, 1.0) ** 3
    y += panear(0.22 * segunda * np.sin(DOS_PI * q(midi(51)) * t), 0.3)
    y += panear(0.10 * segunda * np.sin(DOS_PI * q(midi(63)) * t + 1.0), -0.3)
    y *= 1.0 - 0.22 * (0.5 + 0.5 * np.sin(DOS_PI * q(6.5) * t)) * (0.5 + 0.5 * ciclo(3, 0.5))
    comun = ruido(n, g, 150.0, 900.0, color=1.5)
    for canal in (0, 1):
        aire = 0.6 * comun + 0.8 * ruido(n, g, 150.0, 900.0, color=1.5)
        y[canal] += 0.16 * aire * np.clip(0.6 + 0.5 * ciclo(2, 0.3 + canal) + 0.3 * lento(n, g, 0.1, 0.8), 0.0, None)
    return y


# --------------------------------------------------------------------------------------
# Medición: sonoridad (ITU-R BS.1770), pico real y máximo deslizante
# --------------------------------------------------------------------------------------

def _pond_k(n):
    """Respuesta en frecuencia de la ponderación K (BS.1770) para una FFT de n muestras."""
    z = np.exp(-1j * DOS_PI * np.fft.rfftfreq(n, 1.0 / SR) / SR)
    k = np.tan(np.pi * 1681.974450955533 / SR)
    vh = 10.0 ** (3.999843853973347 / 20.0)
    vb = vh ** 0.4996667741545416
    q = 0.7071752369554196
    a0 = 1.0 + k / q + k * k
    estante = ((vh + vb * k / q + k * k) + 2.0 * (k * k - vh) * z + (vh - vb * k / q + k * k) * z ** 2) / \
              (a0 + 2.0 * (k * k - 1.0) * z + (1.0 - k / q + k * k) * z ** 2)
    k = np.tan(np.pi * 38.13547087602444 / SR)
    q = 0.5003270373238773
    a0 = 1.0 + k / q + k * k
    paso_alto = (1.0 - 2.0 * z + z ** 2) / (1.0 + 2.0 * (k * k - 1.0) / a0 * z + (1.0 - k / q + k * k) / a0 * z ** 2)
    return estante * paso_alto


def sonoridad(x):
    """Sonoridad integrada en LUFS (BS.1770, con las dos puertas) de una señal mono o estéreo."""
    x = np.atleast_2d(x)
    n = x.shape[-1]
    y = np.fft.irfft(np.fft.rfft(x, axis=-1) * _pond_k(n), n, axis=-1)
    bloque, paso = n_(0.4), n_(0.1)
    if n < bloque:
        return -70.0
    ac = np.concatenate([np.zeros((x.shape[0], 1)), np.cumsum(y ** 2, axis=-1)], axis=-1)
    ini = np.arange(0, n - bloque + 1, paso)
    z = np.sum(ac[:, ini + bloque] - ac[:, ini], axis=0) / bloque
    nivel = -0.691 + 10.0 * np.log10(z + 1e-20)
    vivos = nivel > -70.0
    if not vivos.any():
        return -70.0
    umbral = -0.691 + 10.0 * np.log10(np.mean(z[vivos])) - 10.0
    return float(-0.691 + 10.0 * np.log10(np.mean(z[vivos & (nivel > umbral)])))


def nivel_golpe(x):
    """Nivel del golpe más fuerte: máximo de la potencia media en ventanas de 50 ms (dB)."""
    x = np.atleast_2d(x)
    v = n_(0.05)
    ac = np.concatenate([[0.0], np.cumsum(np.sum(x ** 2, axis=0))])
    return float(10.0 * np.log10(np.max(ac[v:] - ac[:-v]) / v + 1e-20))


def max_deslizante(a, w):
    """Máximo en cada ventana [i, i+w-1] (algoritmo de van Herk, vectorizado)."""
    n = len(a)
    nb = -(-n // w)
    b = np.concatenate([a, np.full(nb * w - n, -np.inf)]).reshape(nb, w)
    delante = np.maximum.accumulate(b, axis=1).ravel()
    detras = np.maximum.accumulate(b[:, ::-1], axis=1)[:, ::-1].ravel()
    m = n - w + 1
    return np.maximum(detras[:m], delante[w - 1:w - 1 + m])


def pico_real(x, factor=4):
    """Pico entre muestras (dBFS): sobremuestrea por 4 con relleno de ceros en frecuencia."""
    x = np.atleast_2d(x)
    n = x.shape[-1]
    esp = np.fft.rfft(x, axis=-1)
    y = np.fft.irfft(esp, n * factor, axis=-1) * factor
    return db(np.max(np.abs(y)))


def limitar(x, techo, circular):
    """Limitador con anticipación (3 ms), enlazado en estéreo; no deja pasar nada sobre `techo`.

    En circular la ganancia también es periódica, así que no toca la costura del bucle.
    """
    w = n_(0.003)
    pico = np.max(np.abs(x), axis=0)
    if float(np.max(pico)) <= techo:
        return x
    n = len(pico)
    if circular:
        ext = np.concatenate([pico[-2 * w:], pico, pico[:2 * w]])
    else:
        ext = np.concatenate([np.zeros(2 * w), pico, np.zeros(2 * w)])
    env = max_deslizante(ext, 2 * w + 1)  # centrado: env[i] cubre ext[i .. i+2w]
    gan = np.minimum(1.0, techo / np.maximum(env, 1e-9))
    ventana = np.hanning(2 * w + 3)[1:-1]
    gan = np.convolve(gan, ventana / np.sum(ventana), mode="valid")
    return x * gan[:n]


# --------------------------------------------------------------------------------------
# Mezcla: buses estéreo, eco, reverb estéreo y masterizado
# --------------------------------------------------------------------------------------

def reverb_estereo(x, g, t60, agudos=5000.0, graves=150.0, retardo=0.02, comun=0.45, circular=True):
    """Reverberación estéreo: convolución con dos colas de ruido que decaen.

    Las dos colas comparten una parte (`comun`) para que el campo sea ancho pero la suma a
    mono no se cancele; los agudos decaen antes que los graves. Devuelve solo la señal
    reverberada. En circular la cola da la vuelta al bucle.
    """
    m = n_(t60 * 1.2)
    t = t_(m)
    base, a, b = (g.standard_normal(m) for _ in range(3))
    d = n_(retardo)
    n = x.shape[-1]
    nn = n if circular else n + m + d
    esp = np.fft.rfft(x, nn, axis=-1)
    y = np.zeros((2, nn))
    for canal, propia in ((0, a), (1, b)):
        r = np.sqrt(comun) * base + np.sqrt(1.0 - comun) * propia
        r = (filtrar(r, graves, 1100.0) * np.exp(-6.9 * t / t60)
             + filtrar(r, 1100.0, agudos) * np.exp(-6.9 * t / (0.6 * t60)))
        r *= rampa(m, 0.008)
        r /= np.sqrt(np.sum(r ** 2))
        ri = np.zeros(nn)
        ri[d:d + m] = r
        entrada = esp[canal] + 0.3 * esp[1 - canal]
        y[canal] = np.fft.irfft(entrada * np.fft.rfft(ri), nn)
    return y[:, :n]


class Pista:
    """Una pieza: buses estéreo con nivel, panorama y envío a la reverb.

    El nivel de cada bus se fija midiéndolo, no a ojo: los instrumentos tonales por su
    sonoridad (LUFS con puerta, es decir, «cuando suenan») y la percusión por su golpe más
    fuerte (ventana de 50 ms). Así el equilibrio de la mezcla es el que dice la tabla de
    cada pieza aunque cambien las notas.
    """

    def __init__(self, ident, seg, circular=True):
        self.ident = ident
        self.g = gen(ident)
        self.seg = seg
        self.n = n_(seg)
        self.circular = circular
        self.buses = {}
        self.informe = []
        self.desfase = 0.0 if circular else 0.05  # sin bucle: el primer ataque no empieza en la muestra 0

    def bus(self, nombre, nivel, pan=0.0, rev=0.25, lo=None, hi=None, golpe=False):
        self.buses[nombre] = dict(buf=np.zeros((2, self.n)), nivel=nivel, pan=pan, rev=rev,
                                  lo=lo, hi=hi, golpe=golpe)

    def poner(self, bus, x, t0, gan=1.0, pan=None):
        """Suma un sonido (mono o estéreo) en el bus, a partir del segundo t0."""
        b = self.buses[bus]
        if x.ndim == 1:
            x = panear(x, b["pan"] if pan is None else pan)
        sumar(b["buf"], gan * x, int(round((t0 + self.desfase) * SR)), self.circular)

    def tocar(self, bus, inst, t0, *args, vel=1.0, pan=None, hum=0.006, nvar=2, **kw):
        """Toca una nota humanizada: variante al azar, y tiempo y volumen un poco sueltos."""
        g = self.g
        x = nota(inst, *args, var=int(g.integers(nvar)), **kw)
        dt = float(np.clip(g.normal(0.0, hum), -2.5 * hum, 2.5 * hum)) if hum else 0.0
        self.poner(bus, x, t0 + dt, vel * g.uniform(0.92, 1.05), pan)

    def eco(self, bus, retardo, g1=0.28, g2=0.12, cruzado=True):
        """Eco de dos repeticiones; con `cruzado` la primera salta al lado contrario."""
        b = self.buses[bus]
        x = b["buf"]
        primera = desplazar(x[::-1] if cruzado else x, n_(retardo), self.circular)
        b["buf"] = x + g1 * primera + g2 * desplazar(x, n_(2 * retardo), self.circular)

    def mezclar(self, t60=1.6, agudos=5000.0, rev=1.0, retardo=0.02):
        seco = np.zeros((2, self.n))
        envio = np.zeros((2, self.n))
        for nombre, b in self.buses.items():
            x = b["buf"]
            if not np.any(x):
                continue
            if b["lo"] or b["hi"]:
                x = filtrar(x, b["lo"], b["hi"], orden=2, circular=self.circular)
            medido = nivel_golpe(x) if b["golpe"] else sonoridad(x)
            gan = 10.0 ** ((b["nivel"] - medido) / 20.0)
            seco += gan * x
            envio += gan * b["rev"] * x
            self.informe.append((nombre, b["nivel"], sonoridad(gan * x), nivel_golpe(gan * x),
                                 db(np.max(np.abs(gan * x)))))
        humedo = reverb_estereo(envio, self.g, t60, agudos=agudos, retardo=retardo, circular=self.circular)
        return seco + rev * humedo


def masterizar(x, lufs, techo_db, circular):
    """Corta subgraves y ultrasonidos, quita la continua, ajusta la sonoridad y limita los picos."""
    x = filtrar(x, 35.0, None, orden=3, circular=circular)
    x = filtrar(x, None, 16000.0, orden=4, circular=circular)
    x = x - np.mean(x, axis=-1, keepdims=True)
    techo = 10.0 ** (techo_db / 20.0)
    gan = 10.0 ** ((lufs - sonoridad(x)) / 20.0)
    y = x
    for _ in range(5):
        y = limitar(x * gan, techo, circular)
        error = lufs - sonoridad(y)
        if abs(error) < 0.03:
            break
        gan *= 10.0 ** (error / 20.0)
    return y


# --------------------------------------------------------------------------------------
# Material temático común
# --------------------------------------------------------------------------------------
# Todo el juego vive en Re menor pentatónica (Re Fa Sol La Do) y su relativo, Fa mayor
# pentatónica, que tiene las mismas notas. Los tempos son parientes de 75 pulsos por
# minuto: 75 (claro, exploración, peligro, recuerdo, liberación, lobby), 150 (emboscada,
# furia) y 120 a medio tiempo (jefe).
#
# Dos temas, los dos propios (no citan ninguna obra):
#
# * La LLAMADA DEL ALUX, leitmotiv del juego: La Do Re | Sol La, larga-corta-larga y
#   corta-larga. Sale de la frase de flauta de `capas_claro` (La… Do Re… Sol La). Como sus
#   notas están en las dos pentatónicas, suena melancólica sobre Re menor y luminosa sobre
#   Fa mayor sin cambiar una sola nota. Notas: (pulso de inicio, duración, nota MIDI).
# * El MOTIVO DEL GUARDIÁN (Nojoch Tuunich), de `capas_jefe` y `capas_recuerdo`: seis
#   notas, corta-corta-larga dos veces, grados 5-1-3 | 2-1-5.

LLAMADA = ((0.0, 1.5, 69), (1.5, 0.5, 72), (2.0, 2.0, 74), (4.0, 1.0, 67), (5.0, 3.0, 69))
RITMO_GUARDIAN = ((0, 1), (1, 1), (2, 2), (4, 1), (5, 1), (6, 2))
GUARDIAN_MENOR = (57, 62, 65, 64, 62, 69)  # La Re Fa | Mi Re La
GUARDIAN_MAYOR = (72, 77, 81, 79, 77, 84)  # Do Fa La | Sol Fa Do
VARIANTE_MENOR = (62, 65, 69, 67, 65, 74)  # el motivo una cuarta más arriba, sobre Si bemol


def guardian(notas, tr=0, escala=1.0):
    """El motivo del guardián como lista (inicio, duración, nota)."""
    return tuple((i * escala, d * escala, m + tr) for (i, d), m in zip(RITMO_GUARDIAN, notas))


def frase(p, bus, inst, notas, t0, pulso, vel=1.0, tr=0, ligado=1.0, hum=0.008, **kw):
    """Toca una lista de notas (inicio, duración, nota) con un instrumento de soplo o tecla."""
    for ini, dur, m in notas:
        p.tocar(bus, inst, t0 + ini * pulso, m + tr, round(dur * pulso * ligado, 4), vel=vel, hum=hum, nvar=1, **kw)


def acorde(p, bus, inst, notas, t0, dur, vel=1.0, antes=0.4, **kw):
    """Acorde de colchón: entra un poco antes del compás y se solapa con el siguiente."""
    for m in notas:
        p.tocar(bus, inst, t0 - antes, m, round(dur, 4), vel=vel, hum=0.0, nvar=1, **kw)


# --------------------------------------------------------------------------------------
# mus_claro: el Claro de los Aluxes
# --------------------------------------------------------------------------------------
# Acordes del claro: colchón, bajo y motivo de kalimba (corchea, nota MIDI, intensidad).
# Son los de `capas_claro`; aquí la progresión se alarga a 18 compases en cinco secciones.

AC_CLARO = {
    "re": dict(pad=(50, 57, 65), bajo=38, mot=((0, 62, 1.0), (2, 65, 0.7), (3, 69, 0.8), (5, 74, 0.9), (6, 69, 0.6))),
    "fa": dict(pad=(53, 57, 60), bajo=41, mot=((0, 60, 1.0), (2, 65, 0.7), (3, 69, 0.8), (5, 72, 0.9), (6, 69, 0.6))),
    "sol": dict(pad=(55, 60, 62), bajo=43, mot=((0, 62, 1.0), (2, 67, 0.7), (3, 72, 0.8), (5, 74, 0.9), (6, 67, 0.6))),
    "re2": dict(pad=(50, 57, 65), bajo=38, mot=((0, 62, 1.0), (2, 69, 0.7), (3, 65, 0.8), (5, 69, 0.8), (7, 72, 0.6))),
    "do": dict(pad=(48, 55, 62), bajo=36, mot=((0, 60, 1.0), (2, 67, 0.7), (3, 74, 0.8), (5, 72, 0.9), (6, 67, 0.6))),
    "la": dict(pad=(57, 62, 67), bajo=33, mot=((0, 57, 1.0), (2, 62, 0.7), (3, 67, 0.8), (5, 69, 0.8), (7, 72, 0.6))),
}
PROG_CLARO = ("re", "fa", "sol", "re2",  # A: presentación
              "do", "la", "re", "fa",  # A': respuesta
              "sol", "do", "fa", "la",  # B: curiosidad (marimba, sonaja)
              "re", "fa", "sol", "la",  # C: esperanza (dúo de flauta y ocarina)
              "do", "sol")  # puente de vuelta
# Flauta de barro (negra de inicio, duración, nota). Empieza con la llamada del alux.
FLAUTA_CLARO = (
    (5, 1.5, 69), (6.5, 0.5, 72), (7, 2, 74), (9, 1, 67), (10, 2.5, 69),  # A: la llamada
    (13, 1, 72), (14, 0.5, 69), (14.5, 2.5, 67),
    (21, 1.5, 69), (22.5, 0.5, 72), (23, 1, 74), (24, 2, 77), (26, 1, 74), (27, 0.5, 72), (27.5, 2.5, 69),  # A'
    (33, 0.5, 74), (33.5, 0.5, 72), (34, 1, 74), (35, 1.5, 79), (37, 1, 74), (38, 2, 72),  # B
    (41, 0.5, 69), (41.5, 0.5, 72), (42, 1.5, 77), (43.5, 0.5, 74), (44, 1.5, 72), (45.5, 0.5, 69), (46, 1, 67), (47, 1, 69),
    (48, 1.5, 69), (49.5, 0.5, 72), (50, 2, 74), (52, 1, 67), (53, 2.5, 69),  # C: la llamada otra vez
    (56, 1, 74), (57, 1, 77), (58, 1.5, 79), (59.5, 0.5, 77), (60, 2, 74), (62, 2, 72),
)
OCARINA_CLARO = (
    (18, 1, 79), (19, 1.5, 81),  # eco de la llamada
    (48, 1.5, 81), (49.5, 0.5, 84), (50, 2, 86), (52, 1, 79), (53, 2.5, 81),  # C: a la octava
    (56, 2, 79), (58, 2, 84), (60, 2, 81), (62, 1.5, 79),
    (66, 1, 67), (67, 2.5, 69),  # puente: «Sol La», la cola de la llamada
)


def mus_claro():
    """Tema del Claro: cálido y curioso. Re menor pentatónica, 75 BPM, 18 compases de 4/4."""
    negra = 60.0 / 75.0
    comp = 4 * negra
    p = Pista("mus_claro", len(PROG_CLARO) * comp)
    p.bus("coro", -30.0, rev=0.5)
    p.bus("colchon", -31.0, rev=0.4)
    p.bus("bajo", -25.0, rev=0.05)
    p.bus("kalimba", -23.0, pan=-0.25, rev=0.30)
    p.bus("brillo", -33.0, pan=0.30, rev=0.40)
    p.bus("marimba", -26.0, pan=0.22, rev=0.25)
    p.bus("flauta", -22.0, pan=0.12, rev=0.45)
    p.bus("ocarina", -26.0, pan=-0.35, rev=0.50)
    p.bus("tambor", -20.0, rev=0.20, golpe=True)
    p.bus("mano", -25.0, pan=0.25, rev=0.25, golpe=True)
    p.bus("tepo", -24.0, pan=-0.40, rev=0.30, golpe=True)
    p.bus("sonaja", -31.0, pan=0.45, rev=0.20, golpe=True)
    p.bus("lluvia", -35.0, rev=0.30)
    for i, nombre in enumerate(PROG_CLARO):
        ac = AC_CLARO[nombre]
        sec = i // 4
        t0 = i * comp
        fuerza = (0.75, 0.85, 0.92, 1.0, 0.7)[sec]
        acorde(p, "coro", coro, ac["pad"], t0, comp + 1.6, vel=fuerza, vocal="u" if sec < 2 else "o", ataque=1.1, rel=1.5)
        acorde(p, "colchon", colchon, ac["pad"], t0, comp + 1.6, vel=fuerza)
        p.tocar("bajo", bajo, t0, ac["bajo"] + 12, round(comp * 0.95, 4), vel=0.8, nvar=1)
        p.tocar("bajo", bajo, t0, ac["bajo"], round(comp * 0.95, 4), vel=0.6 * fuerza, nvar=1)
        for corchea, m, vel in ac["mot"]:
            tt = t0 + corchea * negra / 2
            p.tocar("kalimba", kalimba, tt, m, 1.8, vel=vel * fuerza)
            if corchea in (0, 5) and sec in (1, 3):  # brillo: la misma nota una octava arriba
                p.tocar("brillo", kalimba, tt, m + 12, 1.2, vel=0.6 if corchea else 0.4)
        if sec in (2, 3):  # marimba grave en 3+3+2
            raiz = ac["bajo"] + 12
            quinta = raiz + (5 if nombre == "la" else 7)
            for tiempo, m, vel in ((0, raiz, 1.0), (0.75, quinta, 0.7), (1.5, raiz + 12, 0.85),
                                   (2.5, quinta, 0.7), (3.0, raiz + 12, 0.8), (3.5, quinta, 0.6)):
                p.tocar("marimba", marimba, t0 + tiempo * negra, m, 1.2, vel=vel)
        # Tambor: grave en 1 y 3, toque agudo de mano en 2 y 4
        if sec in (0, 4):
            graves, agudos = ((0, 0.7),), ((3, 0.6),) if sec == 0 else ()
        else:
            graves = ((0, 1.0), (2, 0.6))
            agudos = ((1, 0.7), (3, 0.7)) + (((3.5, 0.45),) if i % 2 else ())
        for tiempo, vel in graves:
            p.tocar("tambor", huehuetl, t0 + tiempo * negra, 92.0, 0.5, vel=vel, nvar=3, hum=0.004, tau=0.16, piel=0.2)
        for tiempo, vel in agudos:
            p.tocar("mano", tambor_mano, t0 + tiempo * negra, 210.0, 0.18, vel=vel, nvar=3, hum=0.004)
        if sec in (2, 3):
            for c, vel in enumerate((0.5, 0.3, 0.9, 0.3, 0.5, 0.3, 0.9, 0.45)):
                p.tocar("sonaja", sonaja, t0 + c * negra / 2, 0.09, vel=vel, nvar=4, hum=0.005)
        if sec == 3:
            for s, m, vel in ((0, 50, 0.9), (3, 57, 0.7), (6, 57, 0.8), (8, 50, 0.9), (11, 57, 0.7), (14, 50, 0.5)):
                p.tocar("tepo", teponaztli, t0 + s * negra / 4, m, 0.4, vel=vel, nvar=3, hum=0.004)
    frase(p, "flauta", flauta, FLAUTA_CLARO, 0.0, negra, ligado=1.02, ataque=0.09, rel=0.25)
    frase(p, "ocarina", ocarina, OCARINA_CLARO, 0.0, negra, ligado=1.02, rel=0.3)
    p.poner("lluvia", nota(palo_lluvia, 3.6), 16.9 * comp)
    p.poner("lluvia", nota(palo_lluvia, 2.4, sentido=-1.0), 7.5 * comp, 0.6)
    for k in ("kalimba", "brillo"):  # eco de corchea con puntillo, cruzado
        p.eco(k, 0.75 * negra)
    return p, p.mezclar(t60=1.8, agudos=5500.0)


# --------------------------------------------------------------------------------------
# mus_exploracion: fuera del claro
# --------------------------------------------------------------------------------------
# Seis acordes de dos compases de 6/4. (colchón, bajo, «gotas» de kalimba: negra y nota)
AC_EXPLORA = (
    dict(pad=(50, 57, 60, 65), bajo=38, gotas=((1, 74), (2.5, 77), (6, 81), (9.5, 74))),  # Re m7
    dict(pad=(55, 60, 62, 69), bajo=43, gotas=((0.5, 79), (3, 74), (7.5, 72), (10, 79))),  # Sol sus
    dict(pad=(53, 60, 67, 69), bajo=41, gotas=((0, 77), (1.5, 81), (4, 84), (8.5, 79), (10.5, 72))),  # Fa add9
    dict(pad=(48, 55, 62, 67), bajo=36, gotas=((1, 79), (4.5, 74), (6, 72), (9, 67))),  # Do sus2
    dict(pad=(46, 53, 62, 65, 72), bajo=34, gotas=((0.5, 77), (2, 74), (7, 82), (9.5, 77))),  # Si bemol add9
    dict(pad=(45, 57, 62, 67), bajo=33, gotas=((1, 74), (3.5, 79), (5, 81), (10, 69))),  # La 7sus4
)
OCARINA_EXPLORA = (
    (4, 3, 69), (7, 1, 72), (8, 4, 74), (14, 2, 67), (16, 5, 69),  # la llamada, al doble de lenta
    (30, 2, 72), (32, 1, 74), (33, 3, 77), (36, 2, 74), (38, 4, 72),
    (50, 3, 77), (53, 1, 74), (54, 2, 72), (56, 3, 74),
    (62, 4, 69), (66, 1, 72), (67, 4, 69),
)


def mus_exploracion():
    """Exploración: el mismo mundo con más aire. Re menor pentatónica, 75 BPM, 12 compases de 6/4."""
    negra = 60.0 / 75.0
    largo = 12 * negra  # cada acorde dura dos compases
    p = Pista("mus_exploracion", len(AC_EXPLORA) * largo)
    p.bus("coro", -27.0, rev=0.6)
    p.bus("colchon", -29.0, rev=0.5)
    p.bus("bajo", -26.0, rev=0.05)
    p.bus("kalimba", -27.0, pan=-0.3, rev=0.45)
    p.bus("ocarina", -23.0, pan=0.2, rev=0.6)
    p.bus("flauta", -27.0, pan=-0.4, rev=0.7)
    p.bus("campanas", -34.0, rev=0.6)
    p.bus("tambor", -21.0, rev=0.35, golpe=True)
    p.bus("tepo", -25.0, pan=0.4, rev=0.6, golpe=True)
    p.bus("sonaja", -33.0, pan=-0.5, rev=0.4, golpe=True)
    p.bus("lluvia", -34.0, rev=0.4)
    g = p.g
    for i, ac in enumerate(AC_EXPLORA):
        t0 = i * largo
        acorde(p, "coro", coro, ac["pad"][-3:], t0, largo + 3.0, antes=1.0, vocal="u", ataque=2.2, rel=2.8)
        acorde(p, "colchon", colchon, ac["pad"], t0, largo + 3.0, antes=1.0, ataque=2.0, rel=2.6)
        p.tocar("bajo", bajo, t0, ac["bajo"] + 12, 6.0, vel=0.8, nvar=1, tau=2.2)
        p.tocar("bajo", bajo, t0, ac["bajo"], 6.0, vel=0.7, nvar=1, tau=2.2)
        p.tocar("bajo", bajo, t0 + 6 * negra, ac["bajo"] + 12, 4.0, vel=0.45, nvar=1, tau=1.6)
        for tiempo, m in ac["gotas"]:
            p.tocar("kalimba", kalimba, t0 + tiempo * negra, m, 1.8, vel=g.uniform(0.6, 1.0), hum=0.015)
        p.tocar("tambor", huehuetl, t0, 70.0, 0.9, vel=1.0, nvar=3, tau=0.32, piel=0.2)
        p.tocar("tambor", huehuetl, t0 + 6 * negra, 70.0, 0.9, vel=0.55, nvar=3, tau=0.32, piel=0.2)
        p.tocar("tambor", huehuetl, t0 + 6.75 * negra, 92.0, 0.5, vel=0.35, nvar=3, tau=0.16, piel=0.2)
        for tiempo in (5.5, 11.5):
            p.tocar("sonaja", sonaja, t0 + tiempo * negra, 0.22, vel=g.uniform(0.6, 1.0), nvar=4, tau=0.07, ataque=0.04)
    frase(p, "ocarina", ocarina, OCARINA_EXPLORA, 0.0, negra, ligado=1.03, ataque=0.08, rel=0.5)
    frase(p, "flauta", flauta, ((43, 1, 67), (44, 3, 69), (20.5, 1, 55), (21.5, 2.5, 57)), 0.0, negra,
          ataque=0.12, rel=0.6, aire=0.12)
    for tiempo, m, vel in ((26, 50, 0.9), (26.75, 57, 0.7), (63, 57, 0.8), (63.5, 57, 0.5), (64.25, 50, 0.9)):
        p.tocar("tepo", teponaztli, tiempo * negra, m, 0.4, vel=vel, nvar=3)
    for tiempo, m in ((3, 86), (15.5, 91), (28, 89), (34.5, 93), (47, 86), (52, 94), (59.5, 89), (70, 91)):
        p.tocar("campanas", campana, tiempo * negra, m, 2.2, vel=g.uniform(0.5, 1.0), pan=g.uniform(-0.7, 0.7),
                hum=0.02, tau=0.6)
    p.poner("lluvia", nota(palo_lluvia, 5.0), 23.2 * negra)
    p.poner("lluvia", nota(palo_lluvia, 4.4, sentido=-1.0), 66.5 * negra, 0.8)
    p.eco("kalimba", 1.5 * negra, g1=0.45, g2=0.25)
    p.eco("ocarina", 1.5 * negra, g1=0.22, g2=0.10)
    return p, p.mezclar(t60=2.6, agudos=5000.0, rev=1.15, retardo=0.03)


# --------------------------------------------------------------------------------------
# mus_peligro: tensión, enemigos cerca
# --------------------------------------------------------------------------------------

def mus_peligro():
    """Tensión: dron grave en Re, tambor como latido a 75 por minuto y sonajas sueltas. Sin melodía."""
    negra = 60.0 / 75.0
    comp = 4 * negra
    seg = 12 * comp
    p = Pista("mus_peligro", seg)
    p.bus("dron", -24.0, rev=0.25, hi=2600.0)
    p.bus("latido", -17.5, rev=0.25, golpe=True)
    p.bus("sonaja", -30.0, rev=0.5, golpe=True)
    p.bus("tepo", -27.0, pan=-0.45, rev=0.7, golpe=True)
    p.bus("caracol", -29.0, pan=0.3, rev=0.7, hi=1800.0)
    p.bus("ocarina", -29.0, pan=-0.3, rev=0.8)
    p.bus("coro", -31.0, rev=0.6)
    g = p.g
    p.poner("dron", nota(dron_peligro, seg), 0.0)
    for i in range(12):
        t0 = i * comp
        pulsos = (0, 2) if i < 4 or i >= 10 else (0, 1, 2, 3)
        fuerza = (0.70, 0.74, 0.78, 0.82, 0.86, 0.90, 0.94, 0.97, 1.0, 1.0, 0.85, 0.75)[i]
        for k in pulsos:
            tt = t0 + k * negra
            vel = fuerza * (1.0 if k % 2 == 0 else 0.85)
            p.tocar("latido", huehuetl, tt, 58.0, 0.8, vel=vel, nvar=3, hum=0.003, tau=0.26, barrido=0.8, piel=0.3)
            p.tocar("latido", huehuetl, tt + 0.27, 52.0, 0.6, vel=0.62 * vel, nvar=3, hum=0.006, tau=0.20,
                    barrido=0.6, piel=0.2)
    # Sonajas sueltas: sacudidas aisladas y dos «cascabeles» que se aceleran
    for tiempo in (2.5, 7.75, 13.0, 17.5, 22.25, 27.0, 29.5, 34.75, 38.5, 43.25, 45.0):
        p.tocar("sonaja", sonaja, tiempo * negra, 0.18, vel=g.uniform(0.45, 0.9), pan=g.uniform(-0.8, 0.8),
                nvar=4, hum=0.03, tau=0.05, ataque=0.03)
    for inicio, pan in ((19.0, 0.6), (40.0, -0.6)):
        tt = inicio * negra
        for k in range(14):
            p.tocar("sonaja", sonaja, tt, 0.07, vel=0.3 + 0.05 * k, pan=pan - 0.03 * k * np.sign(pan), nvar=4,
                    hum=0.004, tau=0.02)
            tt += 0.16 * 0.92 ** k
    for tiempo, m, vel in ((9.5, 50, 0.8), (10.0, 56, 0.6), (25.5, 56, 0.7), (37.0, 50, 0.9), (37.33, 50, 0.6),
                           (37.66, 56, 0.8)):
        p.tocar("tepo", teponaztli, tiempo * negra, m, 0.4, vel=vel, nvar=3, hum=0.01)
    # Caracol lejano, y la llamada del alux rota: sus dos primeras notas, graves y sin resolver
    p.tocar("caracol", caracol, 24 * negra, 38, 5.6, vel=1.0, nvar=1, hum=0.0, crece=3.0)
    p.tocar("caracol", caracol, 44 * negra, 39, 3.2, vel=0.6, nvar=1, hum=0.0, crece=2.0)
    p.tocar("ocarina", ocarina, 32.5 * negra, 57, 2.6, vel=1.0, nvar=1, hum=0.0, ataque=0.3, rel=0.8, cae=0.7, aire=0.2)
    p.tocar("ocarina", ocarina, 36 * negra, 60, 3.4, vel=0.9, nvar=1, hum=0.0, ataque=0.3, rel=1.4, cae=1.0, aire=0.2)
    # Voces: Re y Mi bemol, un roce de segunda menor que crece y se va
    for m, t0, dur, vel in ((50, 14.0, 9.0, 0.8), (51, 16.0, 7.0, 0.6), (50, 40.0, 7.0, 0.7), (56, 41.0, 6.0, 0.45)):
        p.tocar("coro", coro, t0 * negra, m, round(dur * negra, 4), vel=vel, nvar=1, hum=0.0, vocal="u",
                ataque=3.0, rel=3.0)
    return p, p.mezclar(t60=2.8, agudos=4200.0, rev=1.1, retardo=0.035)


# --------------------------------------------------------------------------------------
# mus_emboscada: combate de emboscada
# --------------------------------------------------------------------------------------
# Raíz del dron por compás (seis secciones de cuatro compases) y las dos notas del ostinato.
RAICES_EMB = (38, 38, 38, 38,  # 1: arranque
              38, 38, 41, 36,  # 2: entran palmadas, teponaztli y trompa
              38, 38, 41, 36,  # 3: la llamada del alux en la flauta
              34, 34, 36, 36,  # 4: subida sobre Si bemol y Do
              38, 38, 41, 36,  # 5: clímax, flauta y ocarina
              38, 38, 38, 36)  # 6: respiro y redoble de vuelta
OSTINATO_EMB = {38: (74, 77), 41: (77, 79), 36: (72, 74), 34: (74, 77)}
FLAUTA_EMB = (
    (32, 1.5, 69), (33.5, 0.5, 72), (34, 2, 74), (36, 1, 67), (37, 3, 69),
    (40, 1.5, 77), (41.5, 0.5, 74), (42, 2, 72), (44, 1, 69), (45, 1, 72), (46, 2, 74),
    (64, 1.5, 74), (65.5, 0.5, 77), (66, 2, 79), (68, 1, 72), (69, 3, 74),  # la llamada una cuarta arriba
    (72, 1.5, 81), (73.5, 0.5, 79), (74, 2, 77), (76, 1, 74), (77, 1, 77), (78, 2, 74),
)
TROMPA_EMB = (
    (16, 6, 50), (22, 2, 57), (24, 4, 53), (28, 4, 55),
    (48, 4, 50), (52, 4, 53), (56, 4, 55), (60, 4, 60),
    (64, 8, 50), (72, 4, 53), (76, 4, 48),
    (88, 4, 45), (92, 4, 48),
)


def mus_emboscada():
    """Emboscada: tambores, dron que late y ostinato. Re menor, 150 BPM, 24 compases de 4/4."""
    negra = 0.4
    semi = 0.1
    comp = 1.6
    p = Pista("mus_emboscada", len(RAICES_EMB) * comp)
    p.bus("tom", -15.0, pan=-0.1, rev=0.12, golpe=True)
    p.bus("fondo", -16.5, rev=0.15, golpe=True)
    p.bus("palmada", -18.5, pan=0.25, rev=0.15, golpe=True)
    p.bus("tepo", -21.5, pan=-0.45, rev=0.2, golpe=True)
    p.bus("sonaja", -27.5, pan=0.5, rev=0.1, golpe=True)
    p.bus("dron", -23.0, rev=0.08)
    p.bus("ostinato", -25.0, pan=0.3, rev=0.2)
    p.bus("marimba", -27.0, pan=-0.3, rev=0.2)
    p.bus("trompa", -23.5, pan=-0.2, rev=0.3)
    p.bus("trompa2", -28.0, pan=0.25, rev=0.3)
    p.bus("flauta", -21.5, pan=0.1, rev=0.3)
    p.bus("ocarina", -27.0, pan=-0.3, rev=0.35)
    for i, raiz in enumerate(RAICES_EMB):
        sec, j = divmod(i, 4)
        t0 = i * comp
        ultimo = i == len(RAICES_EMB) - 1
        toms = ((0, 1.0), (3, 0.7), (6, 0.8), (8, 0.95), (11, 0.7), (14, 0.8))
        if ultimo:  # redoble de cierre que empuja a la vuelta
            toms = toms[:3] + tuple((8 + k, 0.5 + 0.07 * k) for k in range(8))
        for s, vel in toms:
            p.tocar("tom", huehuetl, t0 + s * semi, 96.0, 0.4, vel=vel, nvar=4, hum=0.003, tau=0.11, barrido=0.7, piel=0.5)
        for s in (0, 8) if sec == 4 else (0,):
            p.tocar("fondo", huehuetl, t0 + s * semi, 62.0, 0.7, vel=1.0 if s == 0 else 0.7, nvar=3, hum=0.003,
                    tau=0.22, barrido=0.8, piel=0.3)
        if ultimo:
            palmadas = ((4, 0.9), (10, 0.5), (12, 0.9), (13, 0.6), (14, 0.75), (15, 0.9))
        elif sec == 0 or (sec == 5 and j < 2):
            palmadas = ()
        else:
            palmadas = ((4, 0.9), (12, 0.9)) + (((15, 0.5),) if i % 2 else ())
        for s, vel in palmadas:
            p.tocar("palmada", tambor, t0 + s * semi, 250.0, 0.16, vel=vel, nvar=4, hum=0.003, tau=0.045, barrido=0.4,
                    piel=0.9, banda=(900.0, 5000.0), tau_piel=0.02)
        if sec in (1, 2, 4):
            golpes = ((2, 57, 0.7), (5, 50, 0.8), (7, 57, 0.6), (10, 57, 0.8), (13, 50, 0.7), (15, 57, 0.5))
        elif sec == 3:
            golpes = ((2, 57, 0.7), (10, 57, 0.8), (13, 50, 0.7))
        else:
            golpes = ()
        for s, m, vel in golpes:
            p.tocar("tepo", teponaztli, t0 + s * semi, m, 0.3, vel=vel, nvar=3, hum=0.003)
        suave = 0.6 if sec == 0 else 1.0
        for s in range(0, 16, 2 if (sec == 5 and j < 2) else 1):
            vel = 0.9 if s % 4 == 2 else (0.55 if s % 2 == 0 else 0.3)
            p.tocar("sonaja", sonaja, t0 + s * semi, 0.07, vel=vel * suave, nvar=4, hum=0.003, tau=0.018)
        for k in range(8):  # dron grave que late en corcheas
            p.poner("dron", nota(pulso_dron, raiz, 0.2), t0 + 0.2 * k, 1.0 if k % 2 == 0 else 0.75)
        if (sec == 0 and j < 2) or (sec == 5 and j < 2):
            continue
        notas = OSTINATO_EMB[raiz]
        for s, cual, vel in ((0, 0, 1.0), (3, 0, 0.75), (6, 1, 0.9), (10, 0, 0.8), (12, 1, 0.9)):
            p.tocar("ostinato", kalimba, t0 + s * semi, notas[cual], 0.5, vel=vel, hum=0.004)
            if sec >= 3:
                p.tocar("marimba", marimba, t0 + s * semi, notas[cual] - 12, 0.5, vel=vel, hum=0.004)
    frase(p, "trompa", trompa, TROMPA_EMB, 0.0, negra, ligado=1.03, hum=0.004)
    frase(p, "trompa2", trompa, TROMPA_EMB[4:11], 0.0, negra, tr=12, ligado=1.03, hum=0.004)
    p.tocar("trompa", caracol, 80 * negra, 50, 3.3, nvar=1, hum=0.0, crece=2.5)
    frase(p, "flauta", flauta, FLAUTA_EMB, 0.0, negra, ligado=1.05, hum=0.005, ataque=0.03, rel=0.08, vib=0.004, aire=0.1)
    frase(p, "ocarina", ocarina, FLAUTA_EMB[11:], 0.0, negra, tr=12, ligado=1.05, hum=0.005, ataque=0.03, rel=0.08)
    return p, p.mezclar(t60=0.9, agudos=5000.0, rev=1.0, retardo=0.012)


# --------------------------------------------------------------------------------------
# mus_jefe y mus_jefe_furia: Nojoch Tuunich
# --------------------------------------------------------------------------------------
# Las dos fases comparten forma, armonía y melodías; cambian el tempo (120 BPM a medio
# tiempo frente a 150 BPM), la percusión y la instrumentación. Siete secciones de cuatro
# compases: (nombre, raíz del dron en cada compás).
FORMA_JEFE = (
    ("A", (38, 38, 38, 38)),  # el motivo, y un eco que se queda a medias
    ("B", (34, 34, 38, 38)),  # variante sobre Si bemol y vuelta
    ("C", (43, 36, 38, 33)),  # lamento: notas largas
    ("A2", (38, 38, 38, 38)),  # el motivo otra vez; la flauta lo olvida a la mitad
    ("D", (41, 36, 34, 33)),  # la llamada del alux, lejos; la piedra contesta
    ("A3", (38, 38, 34, 36)),  # el motivo entero, a octavas
    ("E", (34, 36, 38, 33)),  # cierre y redoble
)
VOCES_JEFE = {38: (50, 57, 65), 34: (53, 58, 62), 43: (55, 58, 62), 36: (48, 55, 64), 33: (52, 57, 64),
              41: (53, 57, 60)}
OSTINATO_JEFE = {38: (74, 77), 34: (74, 77), 43: (74, 79), 36: (72, 79), 33: (76, 81), 41: (72, 77)}
LARGAS_JEFE = ((0, 4, 55), (4, 4, 60), (8, 6, 62), (14, 2, 57))
LAMENTO_JEFE = ((0, 3, 69), (3, 1, 67), (4, 2, 65), (6, 2, 64), (8, 4, 62), (12, 2, 64), (14, 2, 57))
CIERRE_JEFE = ((0, 3, 74), (3, 1, 72), (4, 3, 67), (7, 1, 69), (8, 4, 65), (12, 3, 64))


def _jefe(furia):
    ident = "mus_jefe_furia" if furia else "mus_jefe"
    negra = 0.4 if furia else 0.5
    semi = negra / 4
    comp = 4 * negra
    p = Pista(ident, 4 * len(FORMA_JEFE) * comp)
    p.bus("roca", -15.5, rev=0.15, golpe=True)
    p.bus("fondo", -17.0, rev=0.2, golpe=True)
    p.bus("losas", -18.0, pan=0.2, rev=0.25, golpe=True)
    p.bus("grava", -29.0 if furia else -31.0, pan=0.45, rev=0.15, golpe=True)
    p.bus("tepo", -22.0, pan=-0.45, rev=0.3, golpe=True)
    p.bus("dron", -23.0 if furia else -24.0, rev=0.1)
    p.bus("trompa", -21.5, pan=-0.18, rev=0.35)
    p.bus("trompa2", -25.0 if furia else -27.0, pan=0.22, rev=0.35)
    p.bus("kalimba", -27.0, pan=0.3, rev=0.3)
    p.bus("flauta", -23.0, pan=0.12, rev=0.45)
    p.bus("ocarina", -25.0, pan=-0.35, rev=0.5)
    p.bus("coro", -27.0 if furia else -29.0, rev=0.5)
    vocal = "a" if furia else "o"

    def motivo(notas, t0, gan=1.0, octava=0, bus="trompa", hasta=6):
        """El motivo en la trompa, doblado por una kalimba grave que marca el ataque."""
        for ini, dur, m in guardian(notas, octava)[:hasta]:
            p.tocar(bus, trompa, t0 + ini * negra, m, round(dur * negra * 1.08, 4), vel=gan, nvar=1, hum=0.005)
            p.tocar("kalimba", kalimba, t0 + ini * negra, m + 12, 0.9, vel=0.8 * gan, hum=0.005, brillo=0.6)

    def largas(notas, t0, gan=0.9):
        for ini, dur, m in notas:
            p.tocar("trompa", trompa, t0 + ini * negra, m, round(dur * negra * 1.04, 4), vel=gan, nvar=1, hum=0.005,
                    ataque=0.12, rel=0.3)
            if furia:
                p.tocar("trompa2", trompa, t0 + ini * negra, m + 12, round(dur * negra * 1.04, 4), vel=0.7 * gan,
                        nvar=1, hum=0.005, ataque=0.12, rel=0.3)

    for i, (sec, raices) in enumerate(FORMA_JEFE):
        ts = i * 4 * comp
        for j, raiz in enumerate(raices):
            t0 = ts + j * comp
            cierre = sec == "E" and j == 3  # último compás: redoble que empuja a la vuelta
            ligero = sec in ("C", "D")
            if furia:
                rocas = ((0, 1.0), (3, 0.7), (6, 0.8), (8, 0.95), (11, 0.7), (14, 0.8))
                if ligero:
                    rocas = ((0, 1.0), (6, 0.7), (8, 0.9), (14, 0.7))
                losas = ((4, 0.9), (10, 0.5), (12, 0.9), (13, 0.6), (14, 0.75), (15, 0.9)) if cierre \
                    else ((4, 0.9), (12, 0.9)) + (((15, 0.5),) if j % 2 else ())
                granos = [(s, 0.9 if s % 4 == 2 else (0.55 if s % 2 == 0 else 0.3)) for s in range(16)]
                fondos = ((0, 1.0), (8, 0.8)) if sec == "A3" else ((0, 1.0),)
                pulsos, largo = 8, negra / 2
            else:
                if cierre:
                    rocas = ((0, 0.9), (6, 0.6), (8, 0.7), (10, 0.8), (12, 0.9), (14, 1.0))
                    losas = ((4, 0.7), (12, 0.9), (15, 0.6))
                elif ligero:
                    rocas = ((0, 0.9), (10, 0.5))
                    losas = ((8, 0.6),)
                elif sec == "A3":
                    rocas = ((0, 1.0), (3, 0.5), (6, 0.6), (10, 0.8), (14, 0.5))
                    losas = ((8, 1.0), (15, 0.5))
                else:
                    rocas = ((0, 1.0), (6, 0.55), (10, 0.75))
                    losas = ((8, 0.9),) + (((15, 0.4),) if j % 2 else ())
                granos = [(s, 0.8 if s % 4 == 2 else 0.4) for s in range(0, 16, 4 if ligero else 2)]
                fondos = ((0, 1.0),) if not ligero or j % 2 == 0 else ()
                pulsos, largo = 4, negra
            for s, vel in rocas:
                p.tocar("roca", golpe_roca, t0 + s * semi, vel=vel, nvar=4, hum=0.003)
            for s, vel in losas:
                p.tocar("losas", choque_losas, t0 + s * semi, vel=vel, nvar=4, hum=0.003)
            for s, vel in granos:
                p.tocar("grava", grava, t0 + s * semi, vel=vel, nvar=4, hum=0.003)
            for s, vel in fondos:
                p.tocar("fondo", huehuetl, t0 + s * semi, 56.0, 0.9, vel=vel, nvar=3, hum=0.003, tau=0.30, barrido=0.7,
                        piel=0.25)
            if furia and j == 3 and not cierre:  # relleno de tambor al final de cada sección
                for k in range(4):
                    p.tocar("fondo", huehuetl, t0 + (12 + k) * semi, 84.0 - 6.0 * k, 0.4, vel=0.5 + 0.12 * k, nvar=2,
                            hum=0.003, tau=0.12, piel=0.4)
            for k in range(pulsos):
                p.poner("dron", nota(pulso_dron, raiz, round(largo, 4)), t0 + k * largo, 1.0 if k % 2 == 0 else 0.75)
            fuerza = dict(A=0.0, B=0.6, C=0.9, A2=0.6, D=0.9, A3=1.0, E=0.9)[sec]
            if furia:
                fuerza = max(fuerza, 0.7)
            if fuerza:
                acorde(p, "coro", coro, VOCES_JEFE[raiz], t0, comp + 1.0, vel=fuerza, antes=0.3, vocal=vocal,
                       ataque=0.7, rel=1.0)
            if furia:  # ostinato de dos notas, como en la emboscada
                notas = OSTINATO_JEFE[raiz]
                for s, cual, vel in ((0, 0, 1.0), (3, 0, 0.75), (6, 1, 0.9), (10, 0, 0.8), (12, 1, 0.9)):
                    p.tocar("kalimba", kalimba, t0 + s * semi, notas[cual], 0.5, vel=0.7 * vel, hum=0.004)
                if not ligero:
                    for s, m, vel in ((2, 57, 0.7), (5, 50, 0.8), (7, 57, 0.6), (10, 57, 0.8), (13, 50, 0.7)):
                        p.tocar("tepo", teponaztli, t0 + s * semi, m, 0.3, vel=vel, nvar=3, hum=0.003)
            elif sec in ("A2", "D", "E"):
                for s, m, vel in ((4, 50, 0.8), (7, 57, 0.6), (12, 50, 0.7), (14, 57, 0.8)):
                    p.tocar("tepo", teponaztli, t0 + s * semi, m, 0.4, vel=vel, nvar=3, hum=0.004)
        # Melodía de la sección
        if sec == "A":
            motivo(GUARDIAN_MENOR, ts)
            if furia:
                motivo(GUARDIAN_MENOR, ts + 2 * comp, 0.8, octava=12, bus="trompa2")
            else:  # eco lejano de la segunda mitad del motivo, que no llega a terminar
                for ini, m in ((4, 76), (5, 74)):
                    p.tocar("kalimba", kalimba, ts + 2 * comp + ini * negra, m, 0.9, vel=0.5, brillo=0.6)
        elif sec == "B":
            motivo(VARIANTE_MENOR, ts)
            motivo(GUARDIAN_MENOR, ts + 2 * comp)
            motivo(GUARDIAN_MENOR, ts + 2 * comp, 0.6, octava=12, bus="trompa2")
        elif sec == "C":
            largas(LARGAS_JEFE, ts)
            frase(p, "flauta", flauta, LAMENTO_JEFE, ts, negra, ligado=1.03, ataque=0.08, rel=0.3,
                  cae=0.0 if furia else 0.3)
        elif sec == "A2":
            motivo(GUARDIAN_MENOR, ts)
            frase(p, "flauta", flauta, ((0, 1, 69), (1, 1, 74), (2, 2, 77), (4, 4, 76)), ts, negra, ligado=1.03,
                  ataque=0.06, rel=0.4, cae=0.6)
            if furia:
                motivo(GUARDIAN_MENOR, ts + 2 * comp, 0.85, octava=12, bus="trompa2")
            else:  # solo recuerda la primera mitad
                motivo(GUARDIAN_MENOR, ts + 2 * comp, 0.8, hasta=3)
        elif sec == "D":
            frase(p, "ocarina", ocarina, LLAMADA, ts, negra, tr=12 if furia else 0, ligado=1.03, rel=0.3)
            largas(((8, 3, 62), (11, 1, 60), (12, 4, 57)), ts, 1.0)
        elif sec == "A3":
            motivo(GUARDIAN_MENOR, ts)
            motivo(GUARDIAN_MENOR, ts, 0.8, octava=12, bus="trompa2")
            motivo(GUARDIAN_MENOR, ts + 2 * comp)
            motivo(GUARDIAN_MENOR, ts + 2 * comp, 0.8, octava=12, bus="trompa2")
            frase(p, "flauta", flauta, guardian(GUARDIAN_MENOR, 12), ts + 2 * comp, negra, vel=0.8, ligado=1.03,
                  ataque=0.05, rel=0.2)
        else:
            largas(((0, 4, 53), (4, 4, 55), (8, 4, 57), (12, 4, 52)), ts)
            frase(p, "flauta", flauta, CIERRE_JEFE, ts, negra, ligado=1.03, ataque=0.08, rel=0.4,
                  cae=0.0 if furia else 0.3)
    if furia:
        return p, p.mezclar(t60=0.9, agudos=5000.0, retardo=0.012)
    return p, p.mezclar(t60=1.5, agudos=4500.0, retardo=0.02)


def mus_jefe():
    """Nojoch Tuunich, fase 1 «Olvido»: pesada y triste. Re menor, 120 BPM a medio tiempo, 28 compases."""
    return _jefe(False)


def mus_jefe_furia():
    """Fase 2 «Furia»: el mismo tema a 150 BPM, con el pulso doblado, ostinato y trompas a octavas."""
    return _jefe(True)


# --------------------------------------------------------------------------------------
# mus_recuerdo: fase 3 «Recuerdo», el ritual
# --------------------------------------------------------------------------------------
# Acordes en Fa mayor (colchón, bajo y arpegio de acompañamiento). Los tres primeros son
# los de `capas_recuerdo`.
AC_RECUERDO = {
    "fa": dict(pad=(53, 57, 60), bajo=41, arp=(65, 69, 72)),
    "re": dict(pad=(50, 57, 65), bajo=38, arp=(62, 65, 69)),
    "do": dict(pad=(48, 55, 62), bajo=36, arp=(60, 62, 67)),
    "sib": dict(pad=(53, 58, 62), bajo=34, arp=(65, 70, 74)),
    "sol": dict(pad=(55, 58, 62), bajo=43, arp=(62, 67, 70)),
    "fa2": dict(pad=(53, 55, 60), bajo=41, arp=(65, 67, 72)),
    "do4": dict(pad=(48, 53, 55), bajo=36, arp=(60, 65, 67)),
}
PROG_RECUERDO = ("fa", "fa", "re", "do",  # A: el motivo en mayor y su respuesta
                 "fa", "fa", "re", "do",  # A': con campanas de jade
                 "sib", "fa", "sol", "do",  # B: la llamada del alux y su espejo
                 "fa", "fa", "re", "do",  # A'': el motivo lo canta la flauta
                 "fa2", "do4")  # coda
RESPUESTA_1 = guardian((81, 79, 77, 74, 77, 79))  # La Sol Fa | Re Fa Sol
RESPUESTA_2 = ((0, 1, 84), (1, 1, 81), (2, 2, 77), (4, 4, 79))  # Do La Fa | Sol (larga)
ESPEJO = ((0.0, 1.5, 74), (1.5, 0.5, 72), (2.0, 2.0, 70), (4.0, 1.0, 69), (5.0, 3.0, 67))  # la llamada, hacia abajo


def mus_recuerdo():
    """Fase 3 «Recuerdo»: el tema del guardián, tierno y ritual. Fa mayor, 75 BPM, 18 compases de 4/4."""
    negra = 60.0 / 75.0
    comp = 4 * negra
    p = Pista("mus_recuerdo", len(PROG_RECUERDO) * comp)
    p.bus("coro", -28.5, rev=0.55)
    p.bus("colchon", -31.0, rev=0.4)
    p.bus("bajo", -25.0, rev=0.05)
    p.bus("arpegio", -30.0, pan=0.35, rev=0.35)
    p.bus("kalimba", -22.5, pan=-0.22, rev=0.35)
    p.bus("campanas", -31.0, pan=0.3, rev=0.5)
    p.bus("flauta", -23.5, pan=0.12, rev=0.5)
    p.bus("ocarina", -27.0, pan=-0.35, rev=0.55)
    p.bus("tambor", -19.5, rev=0.3, golpe=True)
    p.bus("mano", -26.0, pan=0.25, rev=0.3, golpe=True)
    p.bus("tepo", -25.0, pan=-0.4, rev=0.4, golpe=True)
    p.bus("sonaja", -32.0, pan=0.45, rev=0.3, golpe=True)
    p.bus("lluvia", -35.0, rev=0.3)
    for i, nombre in enumerate(PROG_RECUERDO):
        ac = AC_RECUERDO[nombre]
        sec = i // 4
        t0 = i * comp
        fuerza = (0.75, 0.85, 0.9, 1.0, 0.7)[sec]
        acorde(p, "coro", coro, ac["pad"], t0, comp + 1.6, vel=fuerza, vocal="a" if sec == 3 else "o", ataque=1.1, rel=1.5)
        acorde(p, "colchon", colchon, ac["pad"], t0, comp + 1.6, vel=fuerza)
        p.tocar("bajo", bajo, t0, ac["bajo"] + 12, round(comp * 0.95, 4), vel=0.8, nvar=1)
        p.tocar("bajo", bajo, t0, ac["bajo"], round(comp * 0.95, 4), vel=0.6 * fuerza, nvar=1)
        for k, corchea in enumerate((1, 3, 5, 7)):  # arpegio a contratiempo, muy suave
            p.tocar("arpegio", kalimba, t0 + corchea * negra / 2, ac["arp"][k % 3], 1.2,
                    vel=0.8 if k % 2 == 0 else 0.6, brillo=0.5)
        # Pulso ritual: el tambor grave como un corazón tranquilo
        p.tocar("tambor", huehuetl, t0, 80.0, 0.8, vel=1.0, nvar=3, hum=0.004, tau=0.26, piel=0.2)
        if sec != 4:
            p.tocar("tambor", huehuetl, t0 + 2 * negra, 80.0, 0.8, vel=0.6, nvar=3, hum=0.004, tau=0.26, piel=0.2)
            p.tocar("mano", tambor_mano, t0 + 3 * negra, 210.0, 0.18, vel=0.7, nvar=3, hum=0.004)
        if sec in (2, 3):
            for tiempo in (1, 3):
                p.tocar("sonaja", sonaja, t0 + tiempo * negra, 0.2, vel=0.8, nvar=4, hum=0.006, tau=0.06, ataque=0.035)
        if sec == 3:
            for tiempo, m, vel in ((1.5, 57, 0.8), (3.5, 53, 0.7)):
                p.tocar("tepo", teponaztli, t0 + tiempo * negra, m, 0.4, vel=vel, nvar=3, hum=0.004)
    mayor = guardian(GUARDIAN_MAYOR)
    # (compás, frase, kalimba, flauta: «largas» solo sostiene las notas largas, campanas)
    for compas, notas, con_kalimba, con_flauta, con_campanas in (
            (0, mayor, True, "largas", False), (2, RESPUESTA_1, True, "largas", False),
            (4, mayor, True, "largas", True), (6, RESPUESTA_2, True, "largas", False),
            (8, LLAMADA, False, "todo", False), (10, ESPEJO, False, "todo", False),
            (12, mayor, True, "todo", True), (14, RESPUESTA_2, True, "todo", True)):
        t0 = compas * comp
        for ini, dur, m in notas:
            tt = t0 + ini * negra
            if con_kalimba:
                p.tocar("kalimba", kalimba, tt, m, 1.8, vel=1.0 if dur >= 2 else 0.85)
            if con_flauta == "todo" or dur >= 2:
                p.tocar("flauta", flauta, tt, m, round(dur * negra * (1.02 if con_flauta == "todo" else 0.95), 4),
                        nvar=1, ataque=0.09, rel=0.3)
            if con_campanas:
                p.tocar("campanas", campana, tt, m + 12, 1.4, vel=0.8, tau=0.35)
    # La ocarina acompaña A' con dos notas largas, responde en B y cierra la coda
    frase(p, "ocarina", ocarina, ((16, 4, 69), (20, 4, 72), (38.5, 0.5, 77), (39, 1.5, 81), (46.5, 1.5, 72),
                                  (65, 1.5, 77), (66.5, 1.5, 72), (68, 3, 67)), 0.0, negra, ligado=1.02, rel=0.4)
    p.poner("lluvia", nota(palo_lluvia, 4.0), 16.6 * comp)
    p.poner("lluvia", nota(palo_lluvia, 2.6, sentido=-1.0), 7.4 * comp, 0.6)
    for k in ("kalimba", "campanas"):  # eco de corchea con puntillo
        p.eco(k, 0.75 * negra)
    return p, p.mezclar(t60=2.0, agudos=5500.0, rev=1.05)


# --------------------------------------------------------------------------------------
# mus_liberacion: el guardián, libre
# --------------------------------------------------------------------------------------
AC_LIBERA = {
    "fa": dict(pad=(53, 57, 60, 65), bajo=41, arp=(65, 69, 72, 77)),
    "fa/la": dict(pad=(57, 60, 65), bajo=45, arp=(65, 69, 72, 77)),
    "sib": dict(pad=(53, 58, 60, 62), bajo=46, arp=(65, 70, 72, 74)),
    "do4": dict(pad=(55, 60, 65), bajo=36, arp=(60, 65, 67, 72)),
    "rem": dict(pad=(50, 57, 60, 65), bajo=38, arp=(62, 65, 69, 72)),
    "do": dict(pad=(52, 55, 60), bajo=36, arp=(60, 64, 67, 72)),
    "solm": dict(pad=(55, 58, 62, 65), bajo=43, arp=(62, 65, 67, 70)),
}
PROG_LIBERA = ("fa", "fa/la", "sib", "do4",  # A: el motivo del guardián, al doble de lento
               "rem", "do", "sib", "fa",  # B: la llamada del alux y su respuesta en mayor
               "fa", "fa/la", "sib", "do4",  # A': el motivo en la trompa, con destellos de kalimba
               "sib", "fa/la", "solm", "do4")  # C: descenso sereno y vuelta
CANTO_LIBERA_B = ((24, 1.5, 77), (25.5, 0.5, 79), (26, 2, 81), (28, 1, 79), (29, 3, 77))
CANTO_LIBERA_C = ((48, 2, 81), (50, 1, 79), (51, 1, 77), (52, 3, 72), (55, 1, 74), (56, 2, 77), (58, 2, 79),
                  (60, 2, 81), (62, 2, 79))


def mus_liberacion():
    """Después de liberar al guardián: sereno y luminoso. Fa mayor pentatónica, 75 BPM, 16 compases."""
    negra = 60.0 / 75.0
    comp = 4 * negra
    p = Pista("mus_liberacion", len(PROG_LIBERA) * comp)
    p.bus("coro", -27.5, rev=0.6)
    p.bus("colchon", -30.0, rev=0.45)
    p.bus("bajo", -25.5, rev=0.05)
    p.bus("kalimba", -26.0, pan=-0.28, rev=0.4)
    p.bus("canto", -25.0, pan=0.3, rev=0.45)
    p.bus("campanas", -31.0, rev=0.55)
    p.bus("flauta", -22.5, pan=0.12, rev=0.5)
    p.bus("ocarina", -25.0, pan=-0.35, rev=0.55)
    p.bus("trompa", -25.0, pan=0.2, rev=0.55, hi=2500.0)
    p.bus("tambor", -21.5, rev=0.35, golpe=True)
    p.bus("sonaja", -34.0, pan=0.45, rev=0.35, golpe=True)
    p.bus("lluvia", -34.0, rev=0.35)
    g = p.g
    for i, nombre in enumerate(PROG_LIBERA):
        ac = AC_LIBERA[nombre]
        sec = i // 4
        t0 = i * comp
        fuerza = (0.8, 0.85, 1.0, 0.9)[sec]
        acorde(p, "coro", coro, ac["pad"][-3:], t0, comp + 2.0, vel=fuerza, antes=0.6, vocal="a" if sec >= 2 else "o",
               ataque=1.4, rel=1.8)
        acorde(p, "colchon", colchon, ac["pad"], t0, comp + 2.0, vel=fuerza, antes=0.6, ataque=1.3, rel=1.8)
        p.tocar("bajo", bajo, t0, ac["bajo"] + (12 if ac["bajo"] < 40 else 0), round(comp * 0.95, 4), vel=0.8, nvar=1, tau=1.6)
        if ac["bajo"] < 40:
            p.tocar("bajo", bajo, t0, ac["bajo"], round(comp * 0.95, 4), vel=0.55, nvar=1, tau=1.6)
        # La figura de kalimba del claro (corcheas 0, 2, 3, 5 y 6), ahora en mayor
        for corchea, cual, vel in ((0, 0, 1.0), (2, 1, 0.7), (3, 2, 0.8), (5, 3, 0.9), (6, 2, 0.6)):
            p.tocar("kalimba", kalimba, t0 + corchea * negra / 2, ac["arp"][cual], 1.8, vel=vel * fuerza)
        if i % 2 == 0:
            p.tocar("tambor", huehuetl, t0, 76.0, 0.9, vel=1.0, nvar=3, tau=0.3, piel=0.15)
        if sec >= 2:
            for tiempo in (1, 3):
                p.tocar("sonaja", sonaja, t0 + tiempo * negra, 0.22, vel=0.8, nvar=4, hum=0.008, tau=0.07, ataque=0.04)
    aumentado = guardian(GUARDIAN_MAYOR, 0, 2.0)
    frase(p, "flauta", flauta, aumentado, 0.0, negra, ligado=1.01, ataque=0.1, rel=0.35)  # A
    for ini, dur, m in aumentado:
        p.tocar("campanas", campana, ini * negra, m + 12, 2.0, vel=0.8, pan=g.uniform(-0.5, 0.5), tau=0.5)
    frase(p, "ocarina", ocarina, LLAMADA, 16 * negra, negra, ligado=1.02, rel=0.4)  # B
    frase(p, "flauta", flauta, CANTO_LIBERA_B, 0.0, negra, ligado=1.02, ataque=0.09, rel=0.35)
    frase(p, "trompa", trompa, guardian(GUARDIAN_MAYOR, -12, 2.0), 32 * negra, negra, ligado=1.02, ataque=0.2, rel=0.5)  # A'
    for t0 in (32, 40):
        frase(p, "canto", kalimba, guardian(GUARDIAN_MAYOR), t0 * negra, negra)
    frase(p, "flauta", flauta, ((40, 2, 79), (42, 2, 77), (44, 4, 84)), 0.0, negra, vel=0.8, ligado=1.02, ataque=0.1, rel=0.4)
    frase(p, "flauta", flauta, CANTO_LIBERA_C, 0.0, negra, ligado=1.02, ataque=0.09, rel=0.35)  # C
    frase(p, "ocarina", ocarina, ((48, 4, 77), (52, 4, 81), (56, 4, 74), (60, 4, 72)), 0.0, negra, vel=0.8, rel=0.5)
    for tiempo, m in ((18.5, 89), (22, 93), (27.5, 96), (34, 91), (37.5, 96), (43, 89), (46.5, 93), (50.5, 98),
                      (54, 91), (57.5, 96), (61, 93), (63.25, 89)):
        p.tocar("campanas", campana, tiempo * negra, m, 1.8, vel=g.uniform(0.35, 0.7), pan=g.uniform(-0.8, 0.8),
                hum=0.02, tau=0.45)
    p.poner("lluvia", nota(palo_lluvia, 4.5), 7.5 * comp)
    p.poner("lluvia", nota(palo_lluvia, 4.0, sentido=-1.0), 15.0 * comp, 0.8)
    for k in ("kalimba", "canto"):
        p.eco(k, 0.75 * negra)
    return p, p.mezclar(t60=2.4, agudos=6000.0, rev=1.1, retardo=0.025)


# --------------------------------------------------------------------------------------
# mus_victoria: fanfarria (sin bucle)
# --------------------------------------------------------------------------------------

def mus_victoria():
    """Fanfarria de victoria: el motivo del guardián en mayor, la llamada del alux y acorde final de Fa."""
    p = Pista("mus_victoria", 10.5, circular=False)
    p.bus("trompa", -21.0, pan=-0.2, rev=0.35)
    p.bus("trompa2", -24.0, pan=0.22, rev=0.35)
    p.bus("kalimba", -23.0, pan=-0.28, rev=0.35)
    p.bus("marimba", -25.0, pan=0.3, rev=0.3)
    p.bus("flauta", -22.0, pan=0.12, rev=0.45)
    p.bus("ocarina", -26.0, pan=-0.35, rev=0.5)
    p.bus("coro", -25.0, rev=0.55)
    p.bus("bajo", -23.0, rev=0.05)
    p.bus("campanas", -28.0, rev=0.55)
    p.bus("tambor", -15.5, rev=0.25, golpe=True)
    p.bus("mano", -21.0, pan=0.25, rev=0.25, golpe=True)
    p.bus("sonaja", -29.0, pan=0.45, rev=0.3, golpe=True)
    # 1) El motivo del guardián en mayor, como toque de trompas (pulso de 0.25 s)
    fanfarria = guardian(GUARDIAN_MAYOR)
    for ini, dur, m in fanfarria:
        larga = 0.9 if ini == 6 else dur * 0.25 * 1.05
        p.tocar("trompa", trompa, ini * 0.25, m - 12, round(larga, 4), nvar=1, hum=0.004, ataque=0.03, rel=0.12)
        p.tocar("trompa2", trompa, ini * 0.25, m - 24 if ini < 6 else m - 19, round(larga, 4), nvar=1, hum=0.004, ataque=0.03)
        p.tocar("kalimba", kalimba, ini * 0.25, m, 0.9, hum=0.004)
        p.tocar("marimba", marimba, ini * 0.25, m - 12, 0.6, hum=0.004)
    p.tocar("flauta", flauta, 1.5, 84, 0.9, nvar=1, ataque=0.04, rel=0.3)
    p.tocar("bajo", bajo, 0.0, 41, 2.4, nvar=1, tau=1.4)
    # 2) La llamada del alux (pulso de 0.3 s) sobre Si bemol y Do, que resuelve en Fa
    frase(p, "flauta", flauta, LLAMADA[:4] + ((5.0, 2.0, 69),), 2.5, 0.3, ligado=1.03, hum=0.004, ataque=0.035, rel=0.1)
    frase(p, "ocarina", ocarina, LLAMADA[:4] + ((5.0, 2.0, 69),), 2.5, 0.3, tr=12, ligado=1.03, hum=0.004, ataque=0.035, rel=0.1)
    frase(p, "marimba", marimba, LLAMADA, 2.5, 0.3, hum=0.004)
    for t0, dur, notas, grave in ((2.5, 1.25, (53, 58, 62), 46), (3.7, 0.95, (55, 60, 64), 48)):
        for m in notas:
            p.tocar("trompa2", trompa, t0, m, dur, vel=0.8, nvar=1, hum=0.004, ataque=0.05)
        p.tocar("bajo", bajo, t0, grave, dur + 0.2, nvar=1, tau=1.0)
    # 3) Acorde final de Fa mayor
    fin = 4.6
    for i, m in enumerate((65, 69, 72, 77, 81, 84)):
        p.tocar("kalimba", kalimba, fin + 0.028 * i, m, 1.8, vel=0.9, hum=0.002)
    for m in (53, 60, 65, 69):
        p.tocar("coro", coro, fin - 0.1, m, 3.4, nvar=1, hum=0.0, vocal="a", ataque=0.2, rel=1.8)
    for m, bus in ((53, "trompa2"), (60, "trompa"), (65, "trompa"), (69, "trompa2")):
        p.tocar(bus, trompa, fin, m, 2.7, vel=0.9, nvar=1, hum=0.004, ataque=0.05, rel=1.2)
    p.tocar("flauta", flauta, fin, 77, 2.6, nvar=1, ataque=0.05, rel=1.2, vib=0.006)
    p.tocar("ocarina", ocarina, fin, 84, 2.4, nvar=1, vel=0.8, rel=1.2)
    p.tocar("bajo", bajo, fin, 41, 3.0, nvar=1, tau=1.3)
    p.tocar("bajo", bajo, fin, 29, 3.0, vel=0.5, nvar=1, tau=1.3)
    for t0, m, vel, pan in ((fin + 0.01, 77, 1.0, -0.4), (fin + 0.02, 84, 0.9, 0.4), (fin + 0.03, 89, 0.6, 0.0),
                            (fin + 0.8, 93, 0.5, 0.5), (fin + 1.3, 96, 0.4, -0.5), (fin + 1.9, 101, 0.3, 0.2)):
        p.tocar("campanas", campana, t0, m, 2.5, vel=vel, pan=pan, tau=0.7)
    # Tambores: golpes con la fanfarria, dos redobles y el golpe final
    for t0, vel in ((0.0, 1.0), (0.5, 0.7), (1.0, 0.8), (1.5, 1.0), (2.5, 0.9), (3.1, 0.6), (3.7, 0.8)):
        p.tocar("tambor", huehuetl, t0, 72.0, 0.8, vel=vel, nvar=3, hum=0.003, tau=0.24, barrido=0.7, piel=0.4)
    for inicio in (2.1, 4.2):
        for k in range(4):
            p.tocar("tambor", huehuetl, inicio + 0.1 * k, 96.0, 0.4, vel=0.45 + 0.12 * k, nvar=4, hum=0.003, tau=0.11, piel=0.5)
            p.tocar("mano", tambor_mano, inicio + 0.05 + 0.1 * k, 210.0, 0.18, vel=0.5 + 0.12 * k, nvar=3, hum=0.003)
    p.tocar("tambor", huehuetl, fin, 58.0, 1.2, vel=1.15, nvar=1, hum=0.0, tau=0.42, barrido=0.9, piel=0.45)
    for t0, vel in ((fin + 0.8, 0.35), (fin + 1.6, 0.22)):
        p.tocar("tambor", huehuetl, t0, 72.0, 0.8, vel=vel, nvar=3, tau=0.24, piel=0.3)
    for k in range(12):  # sonajas que tiemblan sobre el acorde y se apagan
        p.tocar("sonaja", sonaja, fin + 0.075 * k, 0.09, vel=1.0 - 0.07 * k, nvar=4, hum=0.004)
    p.eco("kalimba", 0.225)
    x = p.mezclar(t60=2.0, agudos=6000.0, rev=1.0)
    return p, x * salida(p.n, 1.2)


# --------------------------------------------------------------------------------------
# mus_lobby: la plaza al atardecer
# --------------------------------------------------------------------------------------
# Compás de 6/8 con la negra con puntillo a 75. Acordes: (bajo, segundo bajo, notas de la cuerda).
AC_LOBBY = {
    "fa": (41, 48, (53, 57, 60, 65)),
    "sib": (46, 53, (53, 58, 62, 65)),
    "rem": (38, 45, (50, 57, 62, 65)),
    "solm": (43, 50, (55, 58, 62, 67)),
    "do": (48, 43, (48, 55, 60, 64)),
    "do4": (48, 43, (48, 55, 60, 65)),
    "fa/la": (45, 48, (57, 60, 65, 69)),
}
PROG_LOBBY = ("fa", "fa", "sib", "fa", "rem", "solm", "do4", "do",  # A: marimba sola
              "fa", "fa", "sib", "fa", "rem", "sib", "do", "fa",  # A': con flauta, cierra en Fa
              "sib", "sib", "fa/la", "fa/la", "solm", "solm", "do", "do",  # B: canta la flauta
              "fa", "fa", "sib", "fa", "rem", "sib", "do", "fa",  # A'': todos, marimba a terceras
              "fa", "do4", "fa", "do4")  # puente: la llamada del alux
HEMIOLAS_LOBBY = (6, 14, 22, 30)  # compases en tres pulsos (2+2+2) en vez de dos (3+3)
# Melodía propia, por compás: (corchea, duración en corcheas, nota)
_LOBBY_A = (((0, 2, 69), (2, 1, 72), (3, 3, 77)), ((0, 1, 74), (1, 1, 72), (2, 1, 69), (3, 3, 72)),
            ((0, 2, 70), (2, 1, 74), (3, 3, 79)), ((0, 1, 77), (1, 1, 74), (2, 1, 72), (3, 3, 69)),
            ((0, 2, 74), (2, 1, 77), (3, 3, 81)))
_LOBBY_FIN_A = (((0, 1, 79), (1, 1, 77), (2, 1, 74), (3, 3, 70)), ((0, 2, 72), (2, 2, 74), (4, 2, 76)), ((0, 4, 79),))
_LOBBY_FIN_A2 = (((0, 1, 79), (1, 1, 77), (2, 1, 72), (3, 3, 74)), ((0, 2, 79), (2, 2, 77), (4, 2, 76)), ((0, 4, 77),))
_LOBBY_B = (((0, 3, 74), (3, 3, 77)), ((0, 2, 79), (2, 1, 77), (3, 3, 74)),
            ((0, 3, 72), (3, 3, 77)), ((0, 2, 81), (2, 1, 79), (3, 3, 77)),
            ((0, 3, 70), (3, 3, 74)), ((0, 2, 79), (2, 1, 77), (3, 2, 74), (5, 1, 70)),
            ((0, 2, 72), (2, 2, 76), (4, 2, 79)), ((0, 3, 79), (3, 1, 76), (4, 1, 74), (5, 1, 72)))
MELODIA_LOBBY = _LOBBY_A + _LOBBY_FIN_A + _LOBBY_A + _LOBBY_FIN_A2 + _LOBBY_B + _LOBBY_A + _LOBBY_FIN_A2
ESCALA_FA = (53, 55, 57, 58, 60, 62, 64)  # Fa mayor


def _tercera_abajo(m):
    """La nota que queda una tercera por debajo dentro de la escala de Fa mayor."""
    grados = [n + 12 * o for o in range(-1, 5) for n in ESCALA_FA]
    return grados[grados.index(m) - 2]


def mus_lobby():
    """Lobby social: una plaza al atardecer. Fa mayor, 6/8 con la negra con puntillo a 75, 36 compases."""
    corchea = 60.0 / 225.0
    comp = 6 * corchea
    p = Pista("mus_lobby", len(PROG_LOBBY) * comp)
    p.bus("marimba", -22.0, pan=-0.2, rev=0.3)
    p.bus("marimba2", -27.0, pan=0.3, rev=0.3)
    p.bus("flauta", -22.5, pan=0.15, rev=0.45)
    p.bus("ocarina", -24.0, pan=-0.35, rev=0.5)
    p.bus("cuerda", -24.5, pan=0.28, rev=0.25)
    p.bus("bajo", -24.0, rev=0.05)
    p.bus("coro", -30.0, rev=0.5)
    p.bus("campana", -31.0, pan=-0.5, rev=0.8, hi=3000.0)
    p.bus("tambor", -19.0, rev=0.2, golpe=True)
    p.bus("mano", -23.0, pan=0.25, rev=0.25, golpe=True)
    p.bus("tepo", -25.0, pan=-0.4, rev=0.3, golpe=True)
    p.bus("sonaja", -29.0, pan=0.45, rev=0.2, golpe=True)
    for i, nombre in enumerate(PROG_LOBBY):
        grave, grave2, tonos = AC_LOBBY[nombre]
        sec = min(i // 8, 4)
        t0 = i * comp
        hemiola = i in HEMIOLAS_LOBBY
        fuerza = (0.8, 0.9, 0.75, 1.0, 0.7)[sec]
        # Cuerda pulsada: arpegio de seis corcheas (3+3), o de tres pares en las hemiolas
        if hemiola:
            orden, vels = (0, 3, 1, 3, 2, 3), (1.0, 0.6, 0.95, 0.6, 0.95, 0.6)
        else:
            orden, vels = (0, 2, 3, 1, 2, 3), (1.0, 0.6, 0.7, 0.8, 0.6, 0.7)
        for c in range(6):
            p.tocar("cuerda", cuerda, t0 + c * corchea, tonos[orden[c]], 1.4, vel=vels[c] * fuerza, hum=0.007)
        for c, m, vel in ((0, grave, 1.0), (2, grave2, 0.8), (4, grave, 0.85)) if hemiola \
                else ((0, grave, 1.0), (3, grave2, 0.7)):
            p.tocar("bajo", bajo, t0 + c * corchea, m, 0.9, vel=vel, nvar=1, tau=0.5)
        if sec in (2, 3):
            acorde(p, "coro", coro, tonos[1:], t0, comp + 1.2, vel=fuerza, antes=0.3, vocal="o", ataque=0.8, rel=1.1)
        # Percusión ligera: sonaja en corcheas, tambor en 1 y mano en 4 (o 1-3-5 en las hemiolas)
        acentos = (1.0, 0.35, 0.9, 0.35, 0.9, 0.35) if hemiola else (1.0, 0.35, 0.5, 0.8, 0.35, 0.5)
        for c in range(6):
            p.tocar("sonaja", sonaja, t0 + c * corchea, 0.08, vel=acentos[c] * (0.6 if sec in (0, 4) else 1.0),
                    nvar=4, hum=0.005, tau=0.022)
        if sec in (1, 3) or hemiola:
            p.tocar("tambor", huehuetl, t0, 104.0, 0.45, vel=1.0, nvar=3, hum=0.004, tau=0.13, piel=0.3)
            for c, vel in ((2, 0.8), (4, 0.8)) if hemiola else ((3, 0.8),) + (((5, 0.45),) if i % 2 else ()):
                p.tocar("mano", tambor_mano, t0 + c * corchea, 210.0, 0.18, vel=vel, nvar=3, hum=0.004)
        elif sec == 2:
            p.tocar("tambor", huehuetl, t0, 104.0, 0.45, vel=0.6, nvar=3, hum=0.004, tau=0.13, piel=0.3)
        if sec == 3 and not hemiola:
            for c, m, vel in ((2, 57, 0.8), (5, 53, 0.7)):
                p.tocar("tepo", teponaztli, t0 + c * corchea, m, 0.35, vel=vel, nvar=3, hum=0.004)
        if sec == 2:  # la marimba acompaña a la flauta a contratiempo
            for c in (2, 5):
                p.tocar("marimba2", marimba, t0 + c * corchea, tonos[2] + 12, 0.8, vel=0.8)
                p.tocar("marimba2", marimba, t0 + c * corchea, tonos[3] + 12, 0.8, vel=0.7)
        if i >= len(MELODIA_LOBBY):
            continue
        for c, dur, m in MELODIA_LOBBY[i]:
            tt = t0 + c * corchea
            if sec == 2:
                p.tocar("flauta", flauta, tt, m, round(dur * corchea * 1.02, 4), nvar=1, ataque=0.06, rel=0.2)
                continue
            p.tocar("marimba", marimba, tt, m, 1.0, vel=1.0 if c in (0, 3) else 0.85)
            if dur >= 3:  # las notas largas se sostienen con un redoble suave
                for k in range(1, int((dur * corchea - 0.12) / 0.105)):
                    p.tocar("marimba", marimba, tt + 0.105 * k, m, 0.8, vel=0.5 * 0.93 ** k, hum=0.008)
            if sec == 1:
                p.tocar("flauta", flauta, tt, m, round(dur * corchea * 1.02, 4), vel=0.7, nvar=1, ataque=0.06, rel=0.2)
            if sec == 3:
                p.tocar("marimba2", marimba, tt, _tercera_abajo(m), 1.0, vel=0.9)
                p.tocar("flauta", flauta, tt, m, round(dur * corchea * 1.02, 4), vel=0.75, nvar=1,
                        ataque=0.06, rel=0.2)
    # Puente: la llamada del alux en la ocarina y la respuesta de la marimba
    t0 = 32 * comp
    frase(p, "ocarina", ocarina, ((0, 2, 69), (2, 1, 72), (3, 3, 74), (6, 2, 67), (8, 4, 69)), t0, corchea, ligado=1.03, rel=0.3)
    frase(p, "marimba", marimba, ((12, 2, 65), (14, 1, 69), (15, 3, 72), (18, 2, 74), (20, 1, 72), (21, 3, 67)), t0, corchea)
    p.tocar("campana", campana, t0, 65, 5.0, nvar=1, hum=0.0, tau=1.6, ataque=0.01)  # una campana lejana
    return p, p.mezclar(t60=1.5, agudos=5500.0, rev=1.0, retardo=0.018)


# --------------------------------------------------------------------------------------
# Catálogo
# --------------------------------------------------------------------------------------
# lufs: sonoridad integrada objetivo; rango: el que valida `--check`. Combate y jefe van a
# -18 LUFS (rango -19…-17); los temas tranquilos a -20 (rango -21…-19). El encargo no fija
# rango para `mus_peligro` ni `mus_victoria`: la tensión va con los tranquilos (suena debajo
# del combate) y la fanfarria con los de combate.
SUAVE, FUERTE = (-21.0, -19.0), (-19.0, -17.0)
PIEZAS = (
    dict(id="mus_claro", fn=mus_claro, bucle=True, lufs=-20.0, rango=SUAVE, bpm=75, key="re menor pentatónica"),
    dict(id="mus_exploracion", fn=mus_exploracion, bucle=True, lufs=-20.0, rango=SUAVE, bpm=75, key="re menor pentatónica"),
    dict(id="mus_peligro", fn=mus_peligro, bucle=True, lufs=-20.0, rango=SUAVE, bpm=75, key="re (dron, con segunda menor y tritono)"),
    dict(id="mus_emboscada", fn=mus_emboscada, bucle=True, lufs=-18.0, rango=FUERTE, bpm=150, key="re menor"),
    dict(id="mus_jefe", fn=mus_jefe, bucle=True, lufs=-18.0, rango=FUERTE, bpm=120, key="re menor"),
    dict(id="mus_jefe_furia", fn=mus_jefe_furia, bucle=True, lufs=-18.0, rango=FUERTE, bpm=150, key="re menor"),
    dict(id="mus_recuerdo", fn=mus_recuerdo, bucle=True, lufs=-20.0, rango=SUAVE, bpm=75, key="fa mayor"),
    dict(id="mus_liberacion", fn=mus_liberacion, bucle=True, lufs=-20.0, rango=SUAVE, bpm=75, key="fa mayor pentatónica"),
    dict(id="mus_victoria", fn=mus_victoria, bucle=False, lufs=-18.0, rango=FUERTE, bpm=120, key="fa mayor"),
    dict(id="mus_lobby", fn=mus_lobby, bucle=True, lufs=-20.0, rango=SUAVE, bpm=75, key="fa mayor"),
)
POR_ID = {q["id"]: q for q in PIEZAS}


# --------------------------------------------------------------------------------------
# Archivos: WAV intermedio, MP3 con ffmpeg y medición sobre el MP3 decodificado
# --------------------------------------------------------------------------------------

def escribir_wav(ruta: Path, x: np.ndarray) -> None:
    """WAV estéreo de 24 bits (intermedio; no se versiona)."""
    datos = np.ascontiguousarray(np.round(np.clip(x.T, -1.0, 1.0) * 8388607.0).astype("<i4"))
    crudo = datos.view(np.uint8).reshape(-1, 4)[:, :3].tobytes()
    with wave.open(str(ruta), "wb") as w:
        w.setnchannels(2)
        w.setsampwidth(3)
        w.setframerate(SR)
        w.writeframes(crudo)


def codificar(wav: Path, mp3: Path) -> None:
    """MP3 con libmp3lame en VBR de calidad 5, sin metadatos (para que sea reproducible)."""
    subprocess.run(["ffmpeg", "-v", "error", "-y", "-i", str(wav), "-c:a", "libmp3lame", "-q:a", "5",
                    "-map_metadata", "-1", "-fflags", "+bitexact", str(mp3)], check=True)


def decodificar(mp3: Path) -> np.ndarray:
    """Decodifica el MP3 con ffmpeg a float (2, n) a 44.1 kHz."""
    crudo = subprocess.run(["ffmpeg", "-v", "error", "-i", str(mp3), "-f", "f32le", "-ac", "2", "-ar", str(SR), "-"],
                           check=True, capture_output=True).stdout
    return np.frombuffer(crudo, dtype="<f4").astype(np.float64).reshape(-1, 2).T


def medir_ffmpeg(mp3: Path):
    """Sonoridad integrada (LUFS) y pico real (dBFS) del MP3 según el filtro `ebur128` de ffmpeg."""
    err = subprocess.run(["ffmpeg", "-nostats", "-hide_banner", "-i", str(mp3), "-af", "ebur128=peak=true",
                          "-f", "null", "-"], check=True, capture_output=True, text=True).stderr
    resumen = err[err.rindex("Summary:"):]
    lufs = float(re.search(r"I:\s+(-?[\d.]+) LUFS", resumen).group(1))
    pico = float(re.search(r"Peak:\s+(-?[\d.]+) dBFS", resumen).group(1))
    return lufs, pico


def formato_de(mp3: Path) -> str:
    return subprocess.run(["ffprobe", "-v", "error", "-select_streams", "a:0", "-show_entries",
                           "stream=codec_name,sample_rate,channels", "-of", "csv=p=0", str(mp3)],
                          check=True, capture_output=True, text=True).stdout.strip()


def con_margenes(cuerpo: np.ndarray) -> np.ndarray:
    """[pre = últimos 0.5 s][cuerpo][post = primeros 0.5 s]: ver la convención de bucle."""
    m = n_(MARGEN)
    return np.concatenate([cuerpo[:, -m:], cuerpo, cuerpo[:, :m]], axis=1)


def generar(ids, tmp: Path, detalle: bool) -> None:
    SALIDA.mkdir(parents=True, exist_ok=True)
    tmp.mkdir(parents=True, exist_ok=True)
    ruta_json = SALIDA / "musica.json"
    pistas = json.loads(ruta_json.read_text(encoding="utf-8"))["tracks"] if ruta_json.exists() else {}
    for q in PIEZAS:
        if q["id"] not in ids:
            continue
        _CACHE.clear()
        p, mezcla = q["fn"]()
        if detalle:
            print(f"\n{q['id']}: nivel de cada bus en la mezcla (antes del masterizado)")
            print(f"  {'bus':<10}{'objetivo':>9}{'LUFS':>8}{'golpe':>8}{'pico':>8}")
            for nombre, objetivo, lufs, golpe, pico in p.informe:
                print(f"  {nombre:<10}{objetivo:>9.1f}{lufs:>8.1f}{golpe:>8.1f}{pico:>8.1f}")
        wav, mp3 = tmp / f"{q['id']}.wav", SALIDA / f"{q['id']}.mp3"
        techo, ajuste = -2.6, 0.0
        for intento in range(5):  # se corrige con lo que mide ffmpeg sobre el MP3 ya codificado
            cuerpo = masterizar(mezcla, q["lufs"] + ajuste, techo, p.circular)
            escribir_wav(wav, con_margenes(cuerpo) if q["bucle"] else cuerpo)
            codificar(wav, mp3)
            lufs, pico = medir_ffmpeg(mp3)
            if pico > PICO_MAX - 0.1:
                techo -= pico - (PICO_MAX - 0.4)
            elif abs(lufs - q["lufs"]) > 0.2:
                ajuste += q["lufs"] - lufs
            else:
                break
        seg = (cuerpo.shape[1] + (2 * n_(MARGEN) if q["bucle"] else 0)) / SR
        pistas[q["id"]] = {
            "file": mp3.name, "bus": "Music",
            "loop": [MARGEN, round(MARGEN + p.seg, 6)] if q["bucle"] else None,
            "seconds": round(seg, 3), "bytes": mp3.stat().st_size, "lufs": lufs, "peak_db": pico,
            "bpm": q["bpm"], "key": q["key"],
        }
        print(f"{q['id']:<17} {seg:6.2f} s  {mp3.stat().st_size:>8} bytes  {lufs:6.1f} LUFS  pico {pico:5.1f} dBFS"
              f"  ({intento + 1} pasada{'s' if intento else ''})")
    orden = [q["id"] for q in PIEZAS if q["id"] in pistas]
    ruta_json.write_text(json.dumps({"version": 1, "tracks": {k: pistas[k] for k in orden}}, ensure_ascii=False,
                                    indent=2) + "\n", encoding="utf-8")
    procedencia = [{
        "id": k, "archivo": f"game/web/static/audio/{pistas[k]['file']}", "tipo": "música", "bus": "Music",
        "duracion_s": pistas[k]["seconds"], "bytes": pistas[k]["bytes"],
        "origen": f"síntesis propia: art/audio/gen_musica.py, función {POR_ID[k]['fn'].__name__}()",
        "licencia": "original del proyecto ALUX, sin material de terceros",
        "semilla": [SEMILLA, zlib.crc32(k.encode("utf-8"))],
    } for k in orden]
    (DOC / "manifiesto_musica.json").write_text(json.dumps(procedencia, ensure_ascii=False, indent=2) + "\n",
                                                encoding="utf-8")


# --------------------------------------------------------------------------------------
# Comprobación (--check): todo se mide sobre el MP3 decodificado
# --------------------------------------------------------------------------------------
# Bandas del espectro (Hz) y límites de su energía respecto al total, en dB: (mínimo, máximo).
BANDAS = (
    ("<35", 0.0, 35.0, None, -22.0),  # subgraves: cortados
    ("35-150", 35.0, 150.0, -20.0, -1.5),  # graves: presentes sin retumbar
    ("150-600", 150.0, 600.0, None, None),
    ("600-2k", 600.0, 2000.0, None, None),
    ("2k-5k", 2000.0, 5000.0, -40.0, -9.0),  # presencia: ni apagada ni estridente
    ("5k-10k", 5000.0, 10000.0, None, -14.0),
    (">10k", 10000.0, 1e9, -62.0, -22.0),  # aire: suave, pero que exista
)
DESFASES = (0, 529, 1105, 2257, -1105)  # muestras: desplazamientos típicos de un decodificador de MP3


def _corr(a, b):
    return float(np.sum(a * b) / (np.sqrt(np.sum(a * a) * np.sum(b * b)) + 1e-20))


def comprobar_pista(ident, datos):
    """Mide una pista del manifiesto. Devuelve (fila de medidas, lista de fallos)."""
    q = POR_ID[ident]
    mp3 = SALIDA / datos["file"]
    fallos = []
    if not mp3.exists():
        return None, ["falta el archivo"]
    x = decodificar(mp3)
    n = x.shape[1]
    seg = n / SR
    tam = mp3.stat().st_size
    lufs, pico = medir_ffmpeg(mp3)
    pico4 = pico_real(x)
    if formato_de(mp3) != "mp3,44100,2":
        fallos.append(f"formato {formato_de(mp3)}")
    if abs(seg - datos["seconds"]) > 0.03:
        fallos.append(f"dura {seg:.3f} s y el manifiesto dice {datos['seconds']}")
    if tam != datos["bytes"]:
        fallos.append("bytes ≠ manifiesto")
    if tam > LIMITE_ARCHIVO:
        fallos.append(f"pesa {tam} bytes")
    if abs(lufs - datos["lufs"]) > 0.11 or abs(pico - datos["peak_db"]) > 0.11:
        fallos.append("LUFS o pico ≠ manifiesto")
    if not q["rango"][0] <= lufs <= q["rango"][1]:
        fallos.append(f"sonoridad {lufs} fuera de {q['rango']}")
    if max(pico, pico4) > PICO_MAX:
        fallos.append(f"pico real {max(pico, pico4):.2f} dBFS")
    if float(np.max(np.abs(x))) >= 0.999:
        fallos.append("recorte")
    dc = float(np.max(np.abs(np.mean(x, axis=1))))
    if dc > 1e-3:
        fallos.append(f"continua {dc:.5f}")
    # Estéreo: correlación entre canales, global y en ventanas de 3 s
    corr = _corr(x[0], x[1])
    v = n_(3.0)
    ventanas = [_corr(x[0, i:i + v], x[1, i:i + v]) for i in range(0, n - v + 1, v // 2)
                if rms(x[:, i:i + v]) > 10.0 ** (-55.0 / 20.0)]
    corr_min = min(ventanas) if ventanas else corr
    lado = db(rms(x[0] - x[1]) / (rms(x[0] + x[1]) + 1e-12))
    if corr < 0.05 or corr_min < 0.0:
        fallos.append(f"correlación L/R {corr:.2f} (mínima {corr_min:.2f})")
    if corr > 0.97 or lado < -30.0:
        fallos.append("casi mono")
    # Espectro
    pot = np.sum(np.abs(np.fft.rfft(x, axis=1)) ** 2, axis=0)
    f = np.fft.rfftfreq(n, 1.0 / SR)
    total = float(np.sum(pot)) + 1e-30
    bandas = []
    for nombre, lo, hi, minimo, maximo in BANDAS:
        e = 10.0 * np.log10(float(np.sum(pot[(f >= lo) & (f < hi)])) / total + 1e-30)
        bandas.append(e)
        if (minimo is not None and e < minimo) or (maximo is not None and e > maximo):
            fallos.append(f"banda {nombre} Hz a {e:.1f} dB")
    # Huecos: ningún segundo debe quedarse en silencio (en los bucles)
    v = n_(1.0)
    ac = np.concatenate([[0.0], np.cumsum(np.sum(x ** 2, axis=0))])
    por_seg = 10.0 * np.log10((ac[v::v // 4] - ac[:-v:v // 4]) / (2 * v) + 1e-20)
    hueco = float(np.min(por_seg)) - 20.0 * np.log10(rms(x))
    costura = ""
    if datos["loop"]:
        if hueco < -24.0:
            fallos.append(f"hueco de {hueco:.0f} dB")
        i0, i1 = (int(round(t * SR)) for t in datos["loop"])
        if abs(datos["loop"][0] - MARGEN) > 1e-9 or abs(seg - (datos["loop"][1] + MARGEN)) > 0.03:
            fallos.append("los puntos de bucle no cuadran con la duración")
        w = n_(0.05)
        c50 = _corr(x[:, i0:i0 + w], x[:, i1:i1 + w])  # (a) lo que sigue a loop[1] es lo que sigue a loop[0]
        m = n_(MARGEN) - 2400
        c_pre = _corr(x[:, i0 - m:i0], x[:, i1 - m:i1])
        c_post = _corr(x[:, i0:i0 + m], x[:, i1:i1 + m])
        # (b) el salto de loop[1] a loop[0] frente a los saltos entre muestras que ya hay en el material
        dif = np.max(np.abs(np.diff(x[:, i0:i1], axis=1)), axis=0)
        p999, dmax = float(np.percentile(dif, 99.9)), float(np.max(dif))
        peor = 0.0
        for d in DESFASES:
            salto = float(np.max(np.abs(x[:, i0 + d] - x[:, i1 + d - 1])))
            natural = float(np.max(np.abs(x[:, i0 + d] - x[:, i0 + d - 1])))
            peor = max(peor, salto / max(p999, 1e-9))
            if salto > max(p999, 1.5 * natural + 1e-4):
                fallos.append(f"escalón en la costura (desfase {d}): {salto:.5f} frente a p99.9 {p999:.5f}")
        if min(c50, c_pre, c_post) <= 0.98:
            fallos.append(f"costura: correlación {c50:.4f} (pre {c_pre:.4f}, post {c_post:.4f})")
        costura = f"{c50:.4f} {min(c_pre, c_post):.4f} {peor:5.2f}"
    else:
        cola = db(rms(x[:, -n_(0.05):]))
        inicio = db(rms(x[:, :n_(0.003)]))
        penultimo = db(rms(x[:, -n_(3.0):-n_(2.0)]))
        ultimo = db(rms(x[:, -n_(1.0):]))
        if cola > -60.0 or inicio > -40.0:
            fallos.append(f"no empieza o no acaba en silencio ({inicio:.0f} / {cola:.0f} dBFS)")
        if not ultimo < penultimo - 6.0:
            fallos.append("no termina con una cola que se apaga")
        if not 8.0 <= seg <= 12.0:
            fallos.append(f"dura {seg:.1f} s")
        costura = f"(sin bucle; cola {ultimo:.0f} dBFS)"
    fila = (f"{ident:<16}{seg:>7.2f}{tam:>9}{lufs:>7.1f}{pico:>6.1f}{pico4:>6.1f}{corr:>6.2f}{corr_min:>6.2f}{lado:>6.1f}"
            + "".join(f"{e:>7.1f}" for e in bandas) + f"{hueco:>6.0f}  {costura}")
    return fila, fallos


def comprobar() -> int:
    """Mide y valida lo que hay en disco. Devuelve el número de fallos."""
    ruta_json = SALIDA / "musica.json"
    if not ruta_json.exists():
        print("FALTA game/web/static/audio/musica.json")
        return 1
    manifiesto = json.loads(ruta_json.read_text(encoding="utf-8"))
    pistas = manifiesto.get("tracks", {})
    print(f"{'pieza':<16}{'seg':>7}{'bytes':>9}{'LUFS':>7}{'pico':>6}{'x4':>6}{'corr':>6}{'mín':>6}{'L-R':>6}"
          + "".join(f"{b[0]:>7}" for b in BANDAS) + f"{'hueco':>6}  costura: corr50 pre/post salto÷p99.9")
    total_fallos = 0
    total_bytes = 0
    for q in PIEZAS:
        if q["id"] not in pistas:
            print(f"{q['id']:<16} FALTA en el manifiesto")
            total_fallos += 1
            continue
        fila, fallos = comprobar_pista(q["id"], pistas[q["id"]])
        if fila:
            print(fila)
            total_bytes += pistas[q["id"]]["bytes"]
        for texto in fallos:
            print(f"    FALLO {q['id']}: {texto}")
        total_fallos += len(fallos)
    sobran = sorted(set(pistas) - set(POR_ID))
    if manifiesto.get("version") != 1 or sobran:
        print(f"    FALLO manifiesto: versión o pistas desconocidas {sobran}")
        total_fallos += 1
    ruta_proc = DOC / "manifiesto_musica.json"
    proc = json.loads(ruta_proc.read_text(encoding="utf-8")) if ruta_proc.exists() else []
    if {e["id"]: e["bytes"] for e in proc} != {k: v["bytes"] for k, v in pistas.items()}:
        print("    FALLO art/audio/manifiesto_musica.json no coincide con musica.json")
        total_fallos += 1
    print(f"\nTotal: {total_bytes} bytes = {total_bytes / 1e6:.3f} MB (límite {LIMITE_TOTAL / 1e6:.0f} MB; "
          f"por archivo {LIMITE_ARCHIVO / 1e6:.1f} MB)")
    if total_bytes > LIMITE_TOTAL:
        print("    FALLO: se supera el presupuesto total")
        total_fallos += 1
    print("OK: todo dentro de rango" if not total_fallos else f"{total_fallos} FALLO(S)")
    return total_fallos


def espectrogramas(ids, tmp: Path) -> None:
    """Una hoja de espectrograma por pieza (frecuencia logarítmica, 90 dB de rango) para revisarlas a ojo."""
    carpeta = tmp / "espectros"
    carpeta.mkdir(parents=True, exist_ok=True)
    for ident in ids:
        mp3 = SALIDA / f"{ident}.mp3"
        if mp3.exists():
            subprocess.run(["ffmpeg", "-v", "error", "-y", "-i", str(mp3), "-lavfi",
                            "showspectrumpic=s=1500x560:mode=combined:color=intensity:scale=log:fscale=log:"
                            "drange=90:legend=1", str(carpeta / f"{ident}.png")], check=True)
    print(f"Espectrogramas en {carpeta}")


def main() -> int:
    ap = argparse.ArgumentParser(description="Genera y comprueba la música de ALUX.")
    ap.add_argument("--check", action="store_true", help="solo medir y validar los archivos que hay en disco")
    ap.add_argument("--solo", default="", help="ids separados por comas (por defecto, todas las piezas)")
    ap.add_argument("--espectros", action="store_true", help="generar una hoja de espectrograma por pieza")
    ap.add_argument("--detalle", action="store_true", help="imprimir el nivel de cada instrumento en la mezcla")
    ap.add_argument("--tmp", type=Path, default=Path(tempfile.gettempdir()) / "alux_musica",
                    help="carpeta temporal para los WAV intermedios y los espectrogramas (fuera del repositorio)")
    a = ap.parse_args()
    ids = [s for s in a.solo.split(",") if s] or [q["id"] for q in PIEZAS]
    desconocidas = [s for s in ids if s not in POR_ID]
    if desconocidas:
        print(f"Piezas desconocidas: {desconocidas}")
        return 2
    if not a.check:
        generar(ids, a.tmp, a.detalle)
    if a.espectros:
        espectrogramas(ids, a.tmp)
    return 1 if comprobar() else 0


if __name__ == "__main__":
    sys.exit(main())
