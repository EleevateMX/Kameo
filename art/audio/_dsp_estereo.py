#!/usr/bin/env python3
"""Síntesis, acabado y medición en estéreo a 44.1 kHz para el audio de ALUX.

Módulo común de `gen_ambiente.py` y `gen_cine.py`. Todo se sintetiza con numpy (senos,
ruido filtrado por FFT y envolventes): no hay grabaciones ni muestras de terceros, y las
semillas son fijas. Las funciones de síntesis básicas son copias adaptadas a 44.1 kHz y a
dos canales de las de `gen_audio.py` (que no se importa ni se toca).

Convenciones:
  - una señal mono es un array de forma (n,); una estéreo, de forma (2, n) (izquierda, derecha);
  - los tiempos van en segundos y las frecuencias en Hz;
  - la panorámica `p` va de -1 (izquierda) a +1 (derecha), con ley de potencia constante.
"""

from __future__ import annotations

import json
import os
import re
import subprocess
import tempfile
import zlib
from pathlib import Path

import numpy as np

SR = 44100  # frecuencia de muestreo
SEMILLA = 20261112  # semilla base; cada sonido deriva la suya de su nombre
DOS_PI = 2.0 * np.pi
CUADRO_MP3 = 1152  # muestras por cuadro MPEG-1 capa III
RAIZ = Path(__file__).resolve().parents[2]
SALIDA = RAIZ / "game" / "web" / "static" / "audio"
MANIFIESTO = RAIZ / "art" / "audio" / "manifiesto_ambiente_cine.json"
LICENCIA = "original del proyecto ALUX, sin material de terceros"


def carpeta_tmp() -> Path:
    """Carpeta de los WAV intermedios y los espectrogramas (fuera del repositorio)."""
    d = Path(os.environ.get("ALUX_AUDIO_TMP", Path(tempfile.gettempdir()) / "alux_audio"))
    d.mkdir(parents=True, exist_ok=True)
    return d


# --------------------------------------------------------------------------------------
# Utilidades básicas
# --------------------------------------------------------------------------------------

def semilla_de(nombre: str) -> list:
    return [SEMILLA, zlib.crc32(nombre.encode("utf-8"))]


def gen(nombre: str) -> np.random.Generator:
    """Generador aleatorio propio de cada sonido (independiente del orden de ejecución)."""
    return np.random.default_rng(semilla_de(nombre))


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


def lin(d: float) -> float:
    return 10.0 ** (d / 20.0)


def rms(x: np.ndarray) -> float:
    return float(np.sqrt(np.mean(np.square(x)))) if np.size(x) else 0.0


def buen_tam(n: int) -> int:
    """Menor tamaño ≥ n de la forma 2^a·3^b·5^c (para que las FFT sean rápidas)."""
    mejor = 1 << max(1, int(n - 1).bit_length())
    p5 = 1
    while p5 < mejor:
        p35 = p5
        while p35 < mejor:
            q = p35
            while q < n:
                q *= 2
            mejor = min(mejor, q)
            p35 *= 3
        p5 *= 5
    return mejor


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


def campana_env(n: int, exp: float = 1.0) -> np.ndarray:
    """Envolvente de campana (seno al exponente `exp`): sube y baja sin esquinas."""
    return np.sin(np.pi * (np.arange(n) + 0.5) / n) ** exp


def tramo(t: np.ndarray, a: float, b: float) -> np.ndarray:
    """Rampa lineal recortada: 0 antes de `a`, 1 después de `b`."""
    return np.clip((t - a) / max(b - a, 1e-9), 0.0, 1.0)


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
    """Filtra en el dominio de la frecuencia (último eje; sirve para mono y estéreo).

    Con `circular=True` la señal se trata como periódica (lo que necesitan los bucles);
    si no, se rellena con ceros para que la cola no se enrolle sobre el principio.
    """
    x = np.asarray(x, dtype=float)
    n = x.shape[-1]
    if circular:
        h = _respuesta(np.fft.rfftfreq(n, 1.0 / SR), lo, hi, orden)
        return np.fft.irfft(np.fft.rfft(x, axis=-1) * h, n, axis=-1)
    m = 2048
    nn = buen_tam(n + 2 * m)
    xp = np.zeros(x.shape[:-1] + (nn,))
    xp[..., m:m + n] = x
    h = _respuesta(np.fft.rfftfreq(nn, 1.0 / SR), lo, hi, orden)
    return np.fft.irfft(np.fft.rfft(xp, axis=-1) * h, nn, axis=-1)[..., m:m + n]


def ruido(n, g, lo=None, hi=None, orden=2, color=0.0):
    """Ruido limitado en banda, con RMS 1. Es periódico en n, así que sirve para bucles."""
    esp = np.fft.rfft(g.standard_normal(n))
    h = _respuesta(np.fft.rfftfreq(n, 1.0 / SR), lo, hi, orden, color)
    h[0] = 0.0
    y = np.fft.irfft(esp * h, n)
    return y / (rms(y) + 1e-12)


def ruido_st(n, g, lo=None, hi=None, orden=2, color=0.0, ancho=0.5):
    """Ruido estéreo (RMS 1 por canal): centro común más una parte lateral independiente.

    La correlación entre canales es (1 - ancho²) / (1 + ancho²): con ancho 0.5, 0.6.
    """
    m = ruido(n, g, lo, hi, orden, color)
    s = ruido(n, g, lo, hi, orden, color)
    return np.stack([m + ancho * s, m - ancho * s]) / np.sqrt(1.0 + ancho * ancho)


def lento(n, g, lo, hi):
    """Modulador aleatorio lento (ruido de muy baja frecuencia, RMS 1, periódico en n)."""
    return ruido(n, g, lo, hi, orden=2)


def rafaga(seg, g, lo, hi, tau, ataque=0.001, color=0.0, orden=2):
    """Golpe de ruido filtrado con caída exponencial."""
    n = n_(seg)
    return ruido(n, g, lo, hi, orden, color) * env_perc(n, tau, ataque)


def ruido_barrido(n, g, fc, ancho=0.6, color=1.0, f_min=120.0, f_max=9000.0, bandas=14):
    """Ruido cuya banda se desplaza con el tiempo (soplidos, ráfagas, estelas).

    Se reparte un mismo ruido en bandas fijas (logarítmicas) y cada una se pondera con
    una campana centrada en `fc(t)`; `ancho` es la desviación en octavas. Periódico en n.
    """
    f = np.fft.rfftfreq(n, 1.0 / SR)
    esp = np.fft.rfft(g.standard_normal(n))
    if color:
        esp = esp * (np.maximum(f, 25.0) / 1000.0) ** (-0.5 * color)
    esp[0] = 0.0
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


def pan(x, p):
    """Mono → estéreo con ley de potencia constante. `p` puede variar con el tiempo."""
    a = (np.clip(p, -1.0, 1.0) + 1.0) * (np.pi / 4.0)
    return np.stack([np.cos(a) * x, np.sin(a) * x])


def poner(buf, x, t0, gan=1.0, p=0.0, circular=False):
    """Suma `x` en `buf` a partir del segundo t0.

    Si `buf` es estéreo y `x` mono, se coloca en la panorámica `p`. Con `circular`, lo que
    se sale por el final da la vuelta y se suma al principio (bucles).
    """
    n = buf.shape[-1]
    if buf.ndim == 2 and np.ndim(x) == 1:
        x = pan(x, p)
    m = x.shape[-1]
    i0 = int(round(t0 * SR))
    if circular:
        a = i0 % n
        hecho = 0
        while hecho < m:
            k = min(m - hecho, n - a)
            buf[..., a:a + k] += gan * x[..., hecho:hecho + k]
            hecho += k
            a = 0
    else:
        a, b = max(i0, 0), min(i0 + m, n)
        if b > a:
            buf[..., a:b] += gan * x[..., a - i0:b - i0]


def saturar(y, k=2.2):
    """Saturación suave de los picos (da peso a los golpes sin recortarlos en seco)."""
    return np.tanh(k * y / (np.max(np.abs(y)) + 1e-12)) / np.tanh(k)


def reverb(x, g, t60=0.8, mezcla=0.2, circular=False, agudos=5000.0, graves=180.0,
           retardo=0.012, ancho=0.7, seco=1.0, cola_agudos=0.55):
    """Reverberación: convolución con ruido que decae (los agudos, más deprisa).

    Con entrada estéreo usa una respuesta distinta por canal, parcialmente correlacionadas
    (`ancho`), así que la cola abre el estéreo sin dejar de sumar bien en mono. En modo
    circular la cola se enrolla (bucles). Si no, devuelve la señal alargada con la cola.
    `cola_agudos` es la duración de la cola por encima de ~1.6 kHz, como fracción de t60.
    """
    x = np.asarray(x, dtype=float)
    est = x.ndim == 2
    m = n_(t60 * 1.1)
    corte = min(1600.0, 0.5 * agudos)

    def respuesta():
        r = g.standard_normal(m)
        t = t_(m)
        lo_ = filtrar(r * np.exp(-6.9 * t / t60), graves, corte)
        hi_ = filtrar(g.standard_normal(m) * np.exp(-6.9 * t / (cola_agudos * t60)), corte, agudos)
        return (lo_ + hi_) * rampa(m, 0.004)

    a = respuesta()
    ris = [a]
    if est:
        b = respuesta()
        ris = [a + ancho * b, a - ancho * b]
    ris = [r / (np.sqrt(np.sum(r ** 2)) + 1e-12) for r in ris]
    d = n_(retardo)
    n = x.shape[-1]
    if circular:
        nn, n_sal = n, n
    else:
        n_sal = n + m + d
        nn = buen_tam(n_sal)
    y = np.zeros(x.shape[:-1] + (n_sal,))
    y[..., :n] = seco * x
    for c, ri in enumerate(ris):
        ri_n = np.zeros(nn)
        poner(ri_n, ri, d / SR, circular=True)
        xc = x[c] if est else x
        hum = np.fft.irfft(np.fft.rfft(xc, nn) * np.fft.rfft(ri_n), nn)[:n_sal]
        if est:
            y[c] += mezcla * hum
        else:
            y += mezcla * hum
    return y


def trenes(n, g, por_seg, amp_sigma=0.6, dens=None):
    """Tren de impulsos al azar (posiciones uniformes, amplitudes log-normales con signo).

    `dens` (array 0..1 de n muestras, opcional) modula la densidad a lo largo del tiempo.
    Sirve para texturas de miles de granos: se convoluciona después con un grano.
    """
    cuantos = int(round(por_seg * n / SR))
    pos = g.integers(0, n, cuantos)
    amp = np.exp(g.normal(0.0, amp_sigma, cuantos)) * g.choice((-1.0, 1.0), cuantos)
    if dens is not None:
        amp = amp * (g.uniform(0.0, 1.0, cuantos) < dens[pos])
    y = np.zeros(n)
    np.add.at(y, pos, amp)
    return y


def convolucionar(x, nucleo, circular=True):
    """Convolución por FFT de `x` con un núcleo corto (circular por defecto)."""
    n = x.shape[-1]
    if circular:
        k = np.zeros(n)
        poner(k, nucleo, 0.0, circular=True)
        return np.fft.irfft(np.fft.rfft(x, axis=-1) * np.fft.rfft(k), n, axis=-1)
    nn = buen_tam(n + len(nucleo))
    return np.fft.irfft(np.fft.rfft(x, nn, axis=-1) * np.fft.rfft(nucleo, nn), nn, axis=-1)[..., :n]


# --------------------------------------------------------------------------------------
# Instrumentos (inspiración mesoamericana: barro, madera, caracol, parche, semillas)
# --------------------------------------------------------------------------------------

F_MAX = 15000.0  # ningún parcial por encima de esto

# Parciales de barra/campana: (razón de frecuencia, amplitud, factor de duración)
PARC_CAMPANA = ((1.0, 1.0, 1.0), (2.0, 0.45, 0.7), (3.01, 0.25, 0.5),
                (4.2, 0.16, 0.35), (5.43, 0.09, 0.25))
# Parciales de barra de vidrio: más inarmónicos (cristal, destellos)
PARC_CRISTAL = ((1.0, 1.0, 1.0), (2.76, 0.40, 0.45), (5.40, 0.20, 0.25), (8.93, 0.07, 0.12))

# Motivo del guardián Nojoch Tuunich (propio del proyecto; es el mismo de `gen_audio.py`):
# seis notas con ritmo corta-corta-larga dos veces (pulso de inicio y duración, en pulsos).
RITMO_MOTIVO = ((0, 1), (1, 1), (2, 2), (4, 1), (5, 1), (6, 2))
MOTIVO_MENOR = (57, 62, 65, 64, 62, 69)  # La Re Fa | Mi Re La
MOTIVO_MAYOR = (72, 77, 81, 79, 77, 84)  # Do Fa La | Sol Fa Do


def kalimba(f, seg, g, brillo=1.0):
    """Lengüeta tipo kalimba/marimba: seno + 4.º armónico con caída rápida y un toque."""
    tau = 0.55 * (261.6 / f) ** 0.5
    n = n_(min(seg, 5.0 * tau))
    t = t_(n)
    y = np.sin(DOS_PI * f * t) * np.exp(-t / tau)
    if 4 * f < F_MAX:
        y += 0.40 * brillo * np.sin(DOS_PI * 4 * f * t) * np.exp(-t / (0.28 * tau))
    if 6.3 * f < F_MAX:
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
    soplo = ruido(n, g, 1.5 * f, min(6.0 * f, 7500.0)) * (1.0 + 2.0 * np.exp(-t / 0.05))
    return (y + aire * soplo) * env_asr(n, ataque, min(rel, seg / 2))


def colchon(f, seg, ataque, rel):
    """Colchón cálido: tres voces desafinadas de onda casi triangular, de entrada lenta."""
    n = n_(seg)
    t = t_(n)
    y = np.zeros(n)
    for desaf, fase in ((-0.004, 0.0), (0.0, 2.1), (0.004, 4.2)):
        w = DOS_PI * f * (1.0 + desaf) * t + fase
        y += np.sin(w) + np.sin(3 * w) / 9.0 + np.sin(5 * w) / 25.0
    return y / 3.0 * env_asr(n, ataque, min(rel, seg / 2))


def colchon_st(f, seg, ataque, rel, ancho=0.6):
    """Colchón estéreo: las voces desafinadas se reparten entre los dos canales."""
    n = n_(seg)
    t = t_(n)
    y = np.zeros((2, n))
    for desaf, fase, p in ((-0.004, 0.0, -ancho), (0.0, 2.1, 0.0), (0.004, 4.2, ancho)):
        w = DOS_PI * f * (1.0 + desaf) * t + fase
        y += pan(np.sin(w) + np.sin(3 * w) / 9.0 + np.sin(5 * w) / 25.0, p)
    return y / 3.0 * env_asr(n, ataque, min(rel, seg / 2))


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


def tambor_grave(g, f0=62.0, seg=1.1, tau=0.32, gan_piel=0.35):
    """Tambor grande de tronco (tipo huéhuetl): cuerpo grave largo y parche apagado."""
    y = tambor(f0, seg, g, tau=tau, barrido=0.45, t_barr=0.04, piel=gan_piel,
               banda=(150.0, 1200.0), tau_piel=0.02)
    n = len(y)
    y += 0.35 * np.sin(DOS_PI * 1.51 * f0 * t_(n) + 0.4) * np.exp(-t_(n) / (0.6 * tau))
    return y * salida(n, min(0.2, seg / 3))


def madera(g, f=320.0, seg=0.35, tau=0.07):
    """Golpe de madera hueca (lengüeta de tronco ahuecado, tipo tunkul)."""
    y = modos(((f, 1.0, tau), (2.71 * f, 0.35, 0.45 * tau), (5.15 * f, 0.15, 0.25 * tau)), seg)
    k = min(len(y), n_(0.012))
    y[:k] += 0.3 * ruido(k, g, 800, 5000) * np.exp(-t_(k) / 0.003)
    return y


def sonaja(seg, g, granos=28.0, brillo=1.0, crece=0.0):
    """Sonaja de semillas: granos cortos de ruido agudo dentro de una sacudida.

    `crece` > 0 hace que la sacudida vaya a más (redoble que crece).
    """
    n = n_(seg)
    u = np.arange(n) / n
    tren = trenes(n, g, granos * 12.0, amp_sigma=0.5)
    grano = rafaga(0.012, g, 3500.0, 9500.0 * brillo, tau=0.0025, ataque=0.0003)
    y = convolucionar(tren, grano, circular=False)
    env = (u ** crece if crece > 0 else np.ones(n)) * (0.55 + 0.45 * np.sin(DOS_PI * granos / 4.0 * u * seg) ** 2)
    return y / (rms(y) + 1e-12) * env * rampa(n, 0.01) * salida(n, min(0.08, seg / 3))


def campana(f, seg, tau=0.35, ataque=0.003, parciales=PARC_CAMPANA):
    """Campanita: parciales algo inarmónicos; los agudos se apagan antes."""
    n = n_(seg)
    t = t_(n)
    y = np.zeros(n)
    for razon, amp, kt in parciales:
        if f * razon < F_MAX:
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


def cuerno(f, seg, g, ataque=0.07, rel=0.45, f_tope=4500.0):
    """Caracol/cuerno grave: armónicos que se abren con la envolvente y entrada desde abajo."""
    n = n_(seg)
    t = t_(n)
    entrada = 2.0 ** (-0.7 * np.exp(-t / 0.045) / 12.0)
    vib = 1.0 + 0.007 * np.sin(DOS_PI * 5.6 * t) * np.clip((t - 0.35) / 0.4, 0.0, 1.0)
    w = fase_de(f * entrada * vib)
    env = rampa(n, ataque) * (0.8 + 0.2 * np.clip(t / 0.5, 0.0, 1.0)) * salida(n, min(rel, seg / 2))
    y = np.zeros(n)
    for k in range(1, 14):
        if k * f > f_tope:
            break
        y += np.sin(k * w + 0.3 * k) / k ** 1.0 * env ** (1.0 + 0.3 * (k - 1))
    y += 0.05 * ruido(n, g, 300, 2500, color=1.0) * env
    return y


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
# Piedra, Silencio y cristal (piezas de los efectos)
# --------------------------------------------------------------------------------------

def tirones(n, g, lo=6.0, hi=32.0, dureza=1.5):
    """Envolvente irregular de «pega y resbala»: piedra que roza contra piedra."""
    return np.clip(0.55 + 0.6 * lento(n, g, lo, hi), 0.0, None) ** dureza


def crujidos(seg, g, cuantos, banda=(600.0, 3500.0), crece=0.0, ancho=0.0):
    """Chasquidos de piedra que se agrieta, repartidos al azar.

    Con `crece` > 0 se agolpan y se refuerzan hacia el final; con `crece` < 0 hacen lo
    contrario (la piedra se asienta). Con `ancho` > 0 devuelve estéreo, con cada chasquido
    en una panorámica al azar dentro de ±ancho.
    """
    y = np.zeros((2, n_(seg))) if ancho > 0 else np.zeros(n_(seg))
    for _ in range(cuantos):
        u = g.uniform(0.0, 1.0) ** (1.0 / (1.0 + crece) if crece >= 0 else 1.0 - crece)
        fc = g.uniform(*banda)
        d = g.uniform(0.008, 0.03)
        amp = g.uniform(0.3, 1.0) * (0.25 + 0.75 * (u if crece >= 0 else 1.0 - u))
        p = g.uniform(-ancho, ancho) if ancho > 0 else 0.0
        poner(y, rafaga(d, g, 0.6 * fc, 1.7 * fc, tau=d / 4.0, ataque=0.0005), u * (seg - 0.05), amp, p)
        if g.uniform() < 0.3:  # algunos dejan una resonancia corta de piedra
            m = n_(0.05)
            poner(y, np.sin(DOS_PI * fc / 3.0 * t_(m)) * env_perc(m, 0.012), u * (seg - 0.05), 0.6 * amp, p)
    return y


def chasquido(g, gan=1.0, grave=150.0):
    """Grieta gorda: chasquido seco, resonancia de bloque y un golpe sordo debajo."""
    y = np.zeros(n_(0.25))
    poner(y, rafaga(0.09, g, 700, 6500, tau=0.012, ataque=0.0005), 0.0, 1.0)
    poner(y, modos(((1.6 * grave, 0.6, 0.05), (2.7 * grave, 0.4, 0.035), (5.1 * grave, 0.25, 0.02)), 0.2), 0.0, 0.9)
    poner(y, glis(grave, 0.5 * grave, 0.2) * env_perc(n_(0.2), 0.05), 0.0, 0.7)
    return gan * y


def impacto_piedra(g, seg=0.6, f0=110.0, f1=42.0, tau=0.14, brillo=1.0):
    """Porrazo de piedra: caída grave, golpe de ruido, resonancias de bloque y chasquido."""
    y = np.zeros(n_(seg))
    d = seg - 0.01
    poner(y, glis(f0, f1, d) * env_perc(n_(d), tau, 0.002), 0.0, 1.0)
    poner(y, rafaga(min(d, 0.3), g, 180, 1800, tau=0.03, color=1.0), 0.0, 1.0)
    poner(y, rafaga(min(d, 0.08), g, 1500, 7000, tau=0.009), 0.0, 0.8 * brillo)
    poner(y, modos(((1.9 * f0, 0.5, 0.06), (3.1 * f0, 0.4, 0.045), (4.7 * f0, 0.3, 0.03),
                    (8.2 * f0, 0.15, 0.02)), min(d, 0.35)), 0.0, 1.2)
    poner(y, rafaga(d, g, 45, 300, tau=1.2 * tau, ataque=0.02, color=2.0), 0.0, 0.5)
    return y


def escombros(y, g, t_ini, t_fin, cuantos, lo=500.0, hi=2500.0, gan=0.35, graves=0.0, ancho=0.7,
              circular=False):
    """Cascotes que caen después de un golpe: chasquidos cada vez más flojos y espaciados.

    `graves` es la proporción de cascotes grandes, que suenan además con un golpe sordo.
    """
    for _ in range(cuantos):
        u = g.uniform(0.0, 1.0) ** 1.5
        t0 = t_ini + (t_fin - t_ini) * u
        fc = g.uniform(lo, hi)
        d = g.uniform(0.015, 0.045)
        amp = gan * g.uniform(0.3, 1.0) * (1.0 - 0.8 * u)
        p = g.uniform(-ancho, ancho)
        poner(y, rafaga(d, g, 0.6 * fc, 2.2 * fc, tau=d / 4.0, ataque=0.0005), t0, amp, p, circular)
        if g.uniform() < graves:
            poner(y, glis(g.uniform(140.0, 260.0), 80.0, 0.09) * env_perc(n_(0.09), 0.022), t0, 1.2 * amp, p,
                  circular)


def gemido(n, g, f, ronco=2.2, tope=1100.0):
    """Gemido grave de roca (RMS 1): tono bajo con FM y aspereza, como un gruñido muy lento.

    `f` puede ser un número o un array con la frecuencia en cada muestra.
    """
    t = t_(n)
    fc = np.broadcast_to(np.asarray(f, dtype=float), (n,))
    w = fase_de(fc) + ronco * np.sin(fase_de(0.5 * fc))
    aspereza = 1.0 + 0.5 * np.sin(DOS_PI * 23.0 * t + 0.5 * np.sin(DOS_PI * 5.0 * t))
    y = filtrar((np.sin(w) + 0.3 * ruido(n, g, 120, 700, color=1.0)) * aspereza, 55, tope)
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


def destellos(y, g, t_ini, t_fin, cuantos, f_lo, f_hi, gan, tau=0.012, ancho=0.9, circular=False):
    """Chispas vítreas: senos agudos muy cortos, repartidos al azar en tiempo y panorámica."""
    for _ in range(cuantos):
        f = f_lo * (f_hi / f_lo) ** g.uniform()
        d = 6.0 * tau
        x = np.sin(DOS_PI * f * t_(n_(d)) + g.uniform(0, DOS_PI)) * env_perc(n_(d), tau, 0.001)
        poner(y, x, g.uniform(t_ini, t_fin), gan * g.uniform(0.3, 1.0), g.uniform(-ancho, ancho), circular)


# --------------------------------------------------------------------------------------
# Acabado: sonoridad (BS.1770), limitador y medidas
# --------------------------------------------------------------------------------------

def _respuesta_k(f: np.ndarray) -> np.ndarray:
    """Módulo de la ponderación K de ITU-R BS.1770 a la frecuencia de muestreo SR."""
    z = np.exp(-1j * DOS_PI * f / SR)

    def biquad(b, a):
        return (b[0] + b[1] * z + b[2] * z * z) / (a[0] + a[1] * z + a[2] * z * z)

    # Etapa 1: realce de agudos (+4 dB); etapa 2: pasa-altos de 38 Hz
    gdb, q, fc = 3.999843853973347, 0.7071752369554196, 1681.974450955533
    a_ = 10.0 ** (gdb / 40.0)
    w0 = DOS_PI * fc / SR
    al = np.sin(w0) / (2.0 * q)
    c = np.cos(w0)
    s1 = biquad((a_ * ((a_ + 1) + (a_ - 1) * c + 2 * np.sqrt(a_) * al),
                 -2 * a_ * ((a_ - 1) + (a_ + 1) * c),
                 a_ * ((a_ + 1) + (a_ - 1) * c - 2 * np.sqrt(a_) * al)),
                ((a_ + 1) - (a_ - 1) * c + 2 * np.sqrt(a_) * al,
                 2 * ((a_ - 1) - (a_ + 1) * c),
                 (a_ + 1) - (a_ - 1) * c - 2 * np.sqrt(a_) * al))
    q, fc = 0.5003270373238773, 38.13547087602444
    w0 = DOS_PI * fc / SR
    al = np.sin(w0) / (2.0 * q)
    c = np.cos(w0)
    s2 = biquad(((1 + c) / 2, -(1 + c), (1 + c) / 2), (1 + al, -2 * c, 1 - al))
    return np.abs(s1 * s2)


def lufs(x: np.ndarray) -> float:
    """Sonoridad integrada (LUFS, ITU-R BS.1770-4, con puertas) de una señal mono o estéreo."""
    x = np.atleast_2d(np.asarray(x, dtype=float))
    n = x.shape[-1]
    nn = buen_tam(n)
    k = np.fft.irfft(np.fft.rfft(x, nn, axis=-1) * _respuesta_k(np.fft.rfftfreq(nn, 1.0 / SR)), nn, axis=-1)[..., :n]
    b, salto = n_(0.4), n_(0.1)
    if n < b:
        return -0.691 + 10.0 * np.log10(np.sum(np.mean(k ** 2, axis=-1)) + 1e-20)
    ac = np.concatenate([np.zeros((k.shape[0], 1)), np.cumsum(k ** 2, axis=-1)], axis=-1)
    ini = np.arange(0, n - b + 1, salto)
    z = np.sum((ac[:, ini + b] - ac[:, ini]) / b, axis=0)  # potencia por bloque (suma de canales)
    lj = -0.691 + 10.0 * np.log10(z + 1e-20)
    z1 = z[lj > -70.0]
    if not len(z1):
        return -99.0
    rel = -0.691 + 10.0 * np.log10(np.mean(z1)) - 10.0
    z2 = z[(lj > -70.0) & (lj > rel)]
    return float(-0.691 + 10.0 * np.log10(np.mean(z2)))


def limitar(x, techo, circular=False, anticipo=0.005, retencion=0.05):
    """Limitador con anticipación: la salida nunca supera `techo` (lineal).

    La ganancia baja antes del pico (sin chasquido) y se recupera despacio después.
    """
    x = np.asarray(x, dtype=float)
    a = np.max(np.abs(np.atleast_2d(x)), axis=0)
    if a.max() <= techo:
        return x
    blo = 32
    n = len(a)
    nb = -(-n // blo)
    ab = np.pad(a, (0, nb * blo - n)).reshape(nb, blo).max(axis=1)
    k = max(1, int(anticipo * SR / blo))
    kr = max(k, int(retencion * SR / blo))
    antes, despues = kr + k, 2 * k  # el máximo mira `antes` bloques atrás y `despues` adelante
    if circular:
        ext = np.concatenate([ab[-antes:], ab, ab[:despues]])
    else:
        ext = np.pad(ab, (antes, despues), mode="edge")
    mx = np.zeros(nb)
    for d in range(antes + despues + 1):
        np.maximum(mx, ext[d:d + nb], out=mx)
    gan = np.minimum(1.0, techo / np.maximum(mx, 1e-12))
    w = np.hanning(2 * k + 3)[1:-1]
    w /= w.sum()
    ext = np.concatenate([gan[-k:], gan, gan[:k]]) if circular else np.pad(gan, k, mode="edge")
    gs = np.convolve(ext, w, mode="valid")
    gi = np.interp(np.arange(n), (np.arange(nb) + 0.5) * blo, gs)
    return x * gi


def corr_canales(x: np.ndarray) -> float:
    """Correlación entre izquierda y derecha (1 = mono; < 0 = se cancela al sumar)."""
    a, b = x[0] - np.mean(x[0]), x[1] - np.mean(x[1])
    return float(np.sum(a * b) / (np.sqrt(np.sum(a * a) * np.sum(b * b)) + 1e-20))


def bandas_pct(x: np.ndarray, cortes=(0, 200, 1000, 4000, 8000, 1e9)) -> list:
    """Reparto de la energía por bandas, en % (suma de los dos canales)."""
    x = np.atleast_2d(x)
    pot = np.sum(np.abs(np.fft.rfft(x, axis=-1)) ** 2, axis=0)
    f = np.fft.rfftfreq(x.shape[-1], 1.0 / SR)
    tot = float(np.sum(pot)) + 1e-20
    return [float(np.sum(pot[(f >= a) & (f < b)])) / tot * 100.0 for a, b in zip(cortes[:-1], cortes[1:])]


# --------------------------------------------------------------------------------------
# Archivos: WAV intermedio, MP3 con ffmpeg, decodificación y medición
# --------------------------------------------------------------------------------------

def escribir_wav(ruta: Path, x: np.ndarray) -> None:
    """WAV PCM de 24 bits (intermedio sin pérdidas; no se versiona)."""
    x = np.atleast_2d(x)
    datos = np.round(np.clip(x.T, -1.0, 1.0) * 8388607.0).astype("<i4")
    crudo = datos.reshape(-1).view(np.uint8).reshape(-1, 4)[:, :3].tobytes()
    canales = x.shape[0]
    cab = b"RIFF" + (36 + len(crudo)).to_bytes(4, "little") + b"WAVEfmt " + (16).to_bytes(4, "little")
    cab += (1).to_bytes(2, "little") + canales.to_bytes(2, "little") + SR.to_bytes(4, "little")
    cab += (SR * canales * 3).to_bytes(4, "little") + (canales * 3).to_bytes(2, "little") + (24).to_bytes(2, "little")
    cab += b"data" + len(crudo).to_bytes(4, "little")
    Path(ruta).write_bytes(cab + crudo)


def _ffmpeg(args: list, binario=False):
    r = subprocess.run(["ffmpeg", "-hide_banner", "-nostdin"] + args, capture_output=True)
    if r.returncode != 0:
        raise RuntimeError("ffmpeg falló: " + r.stderr.decode("utf-8", "replace")[-600:])
    return r.stdout if binario else r.stderr.decode("utf-8", "replace")


def codificar_mp3(wav: Path, mp3: Path, calidad: int) -> None:
    """Codifica con LAME (VBR `-q:a calidad`), estéreo 44.1 kHz, sin etiquetas ni fechas."""
    _ffmpeg(["-y", "-v", "error", "-i", str(wav), "-c:a", "libmp3lame", "-q:a", str(calidad),
             "-ar", str(SR), "-ac", "2", "-map_metadata", "-1", "-id3v2_version", "0",
             "-write_id3v1", "0", "-fflags", "+bitexact", "-flags:a", "+bitexact", str(mp3)])


def decodificar(ruta: Path) -> np.ndarray:
    """Decodifica un archivo de audio a estéreo (2, n) en coma flotante."""
    crudo = _ffmpeg(["-v", "error", "-i", str(ruta), "-f", "f32le", "-ac", "2", "-ar", str(SR), "-"], binario=True)
    return np.frombuffer(crudo, dtype="<f4").reshape(-1, 2).T.astype(np.float64)


def lufs_ffmpeg(ruta: Path) -> float:
    """Sonoridad integrada medida por el filtro `ebur128` de ffmpeg."""
    txt = _ffmpeg(["-nostats", "-i", str(ruta), "-af", "ebur128", "-f", "null", "-"])
    m = re.findall(r"I:\s+(-?[\d.]+) LUFS", txt.split("Summary:")[-1])
    if not m:
        raise RuntimeError(f"ebur128 no dio medida para {ruta}")
    return float(m[0])


def espectrograma(ruta: Path, png: Path, ancho=1500, alto=560) -> None:
    """Espectrograma (frecuencia logarítmica, 90 dB de rango) para revisarlo a ojo."""
    _ffmpeg(["-y", "-v", "error", "-i", str(ruta), "-lavfi",
             f"showspectrumpic=s={ancho}x{alto}:mode=combined:legend=1:scale=log:fscale=log:"
             f"drange=90:limit=-12:color=intensity", str(png)])


def medir(ruta: Path) -> dict:
    """Mide un MP3 en disco: duración, tamaño, LUFS (ffmpeg), pico y salud básica."""
    x = decodificar(ruta)
    return {
        "x": x,
        "seconds": x.shape[-1] / SR,
        "bytes": ruta.stat().st_size,
        "lufs": lufs_ffmpeg(ruta),
        "peak_db": db(np.max(np.abs(x))),
        "dc": float(np.max(np.abs(np.mean(x, axis=-1)))),
        "corr": corr_canales(x),
        "bandas": bandas_pct(x),
    }


def actualizar_manifiesto(tipo: str, entradas: list) -> None:
    """Sustituye en el manifiesto de procedencia las entradas de un tipo y lo reescribe."""
    previas = []
    if MANIFIESTO.exists():
        previas = [e for e in json.loads(MANIFIESTO.read_text(encoding="utf-8")) if e.get("tipo") != tipo]
    todas = sorted(previas + entradas, key=lambda e: (e["tipo"], e["id"]))
    MANIFIESTO.write_text(json.dumps(todas, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def escribir_json(ruta: Path, datos: dict) -> None:
    ruta.write_text(json.dumps(datos, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
