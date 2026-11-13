#!/usr/bin/env python3
"""Voz por granos formánticos para el audio de ALUX (44.1 kHz).

Módulo común de `gen_audio.py` (la voz de Balam) y `gen_cine.py` (la voz de Chiich Yaxché).
Una voz se hace así: los pulsos de la garganta se generan uno a uno, cada uno con su periodo
y su fuerza (jitter, shimmer, subarmónicos); cada pulso dispara, por cada formante, un seno
amortiguado; el tracto se lee en el instante de cada pulso, así que los formantes se mueven
de un pulso a otro; y el aire es ruido que pasa por los mismos formantes con un filtro que
cambia con el tiempo. Todo es síntesis con numpy: no parte de ninguna voz ni de ningún
animal grabados.

Estas funciones son las mismas con las que se hicieron los candidatos que el dueño del
proyecto eligió de oído el 13 de noviembre de 2026 (`art/audio/candidatos/`): no cambiarlas
sin volver a escuchar, porque los sonidos elegidos dejarían de salir muestra a muestra.
"""

from __future__ import annotations

import numpy as np

from _dsp_estereo import DOS_PI, SR, buen_tam, convolucionar, n_, t_


class Tracto:
    """Formantes que se mueven: frecuencia, ancho y ganancia de cada uno en una rejilla de tiempo."""

    def __init__(self, tc, F, B, G):
        self.tc = np.asarray(tc, dtype=float)
        self.F, self.B, self.G = (np.asarray(m, dtype=float) for m in (F, B, G))

    def en(self, t):
        """Valores interpolados en los instantes `t`: tres arrays (len(t), formantes)."""
        t = np.atleast_1d(t)
        return tuple(np.stack([np.interp(t, self.tc, m[:, j]) for j in range(m.shape[1])], axis=1)
                     for m in (self.F, self.B, self.G))

    def ganancia(self, tc, f, ancho=1.0):
        """Respuesta (tramas × frecuencias) para `filtro_variable`."""
        F, B, G = self.en(tc)
        h = np.zeros((len(tc), len(f)))
        for j in range(F.shape[1]):
            h += G[:, j, None] / (1.0 + ((f[None, :] - F[:, j, None]) / (0.5 * ancho * B[:, j, None])) ** 2)
        return h


def mezclar_formantes(tc, a, cerrado, abierto, escala=1.0):
    """Tracto que va de una forma «cerrada» a otra «abierta» según `a` (0..1 en la rejilla `tc`).

    Cada forma es una lista de (frecuencia, ancho, ganancia). `escala` multiplica las
    frecuencias (un tracto más largo, < 1, baja todos los formantes); puede ser un array de la rejilla.
    """
    c, o = np.asarray(cerrado, dtype=float), np.asarray(abierto, dtype=float)
    a = np.asarray(a, dtype=float)[:, None]
    m = c[None, :, :] * (1.0 - a[:, :, None]) + o[None, :, :] * a[:, :, None]
    return Tracto(tc, m[:, :, 0] * np.reshape(np.broadcast_to(escala, (len(tc),)), (-1, 1)), m[:, :, 1], m[:, :, 2])


def pulsos(n, g, f0, jitter=0.02, shimmer=0.1, sub=0.0, retardo=0.0, triple=0.0):
    """Instantes y amplitudes de los pulsos de una fuente glotal irregular.

    `f0` es la altura (Hz, número o array de n muestras). `jitter` varía el periodo de un
    ciclo al siguiente; `shimmer`, la amplitud. `sub` (0..1, número o array) debilita un pulso
    de cada dos y `retardo` lo retrasa (fracción de periodo): es el subarmónico de una voz
    ronca. `triple` debilita además uno de cada tres. Devuelve (tiempos en s, amplitudes).
    """
    f0 = np.broadcast_to(np.asarray(f0, dtype=float), (n,))
    fase0 = np.cumsum(f0) / SR
    r = g.standard_normal(int(fase0[-1]) + 3)
    fj = f0 * np.clip(1.0 + jitter * r[np.floor(fase0).astype(int)], 0.4, 1.8)
    fase = np.cumsum(fj) / SR
    k = np.floor(fase)
    idx = np.nonzero(np.diff(k) > 0)[0] + 1
    frac = (fase[idx] - k[idx]) / (fase[idx] - fase[idx - 1])
    t = (idx - frac) / SR
    amp = np.clip(1.0 + shimmer * g.standard_normal(len(t)), 0.15, None)
    par = (np.arange(len(t)) % 2).astype(float)
    amp *= 1.0 - np.broadcast_to(np.asarray(sub, dtype=float), (n,))[idx] * par
    t = t + par * np.broadcast_to(np.asarray(retardo, dtype=float), (n,))[idx] / fj[idx]
    amp *= 1.0 - np.broadcast_to(np.asarray(triple, dtype=float), (n,))[idx] * (np.arange(len(t)) % 3 == 2)
    return t, amp


def granos(n, t_pulsos, amp, tracto, ataque=0.0008, fases=None):
    """Voz por granos formánticos: cada pulso dispara, por formante, un seno amortiguado.

    El ancho del formante fija la caída del grano (π·ancho) y `ataque` (s) su entrada: cuanto
    más lenta, menos agudos. El tracto se lee en el instante de cada pulso, así que los
    formantes se mueven de un pulso a otro sin costuras.
    """
    y = np.zeros(n + n_(0.1))
    F, B, G = tracto.en(t_pulsos)
    if fases is None:
        fases = np.zeros(F.shape[1])
    for p in range(len(t_pulsos)):
        pos = t_pulsos[p] * SR
        i0 = int(np.floor(pos)) + 1
        if i0 < 0 or i0 >= n:
            continue
        for j in range(F.shape[1]):
            if G[p, j] <= 1e-4:
                continue
            alfa = np.pi * B[p, j]
            m = min(int(SR * 6.2 / alfa), len(y) - i0)
            t = (np.arange(m) + (i0 - pos)) / SR
            gr = np.exp(-alfa * t) * np.sin(DOS_PI * F[p, j] * t + fases[j])
            ka = min(m, int(ataque * SR) + 1)
            gr[:ka] *= 0.5 - 0.5 * np.cos(np.pi * np.clip(t[:ka] / ataque, 0.0, 1.0))
            y[i0:i0 + m] += amp[p] * G[p, j] * gr
    return y[:n]


def env_pulsos(n, t_pulsos, amp, tau):
    """Envolvente que salta en cada pulso y cae con constante `tau` (s): ruido a ráfagas glotales."""
    imp = np.zeros(n)
    i = np.clip((np.asarray(t_pulsos) * SR).astype(int), 0, n - 1)
    np.add.at(imp, i, amp)
    k = n_(6.0 * tau)
    return convolucionar(imp, np.exp(-t_(k) / tau), circular=False)


def suavizar(x, seg):
    """Media móvil con ventana de Hann de `seg` segundos (por FFT: barata aunque sea larga)."""
    k = np.hanning(max(3, n_(seg)))
    k /= k.sum()
    n = len(x)
    nn = buen_tam(n + len(k))
    y = np.fft.irfft(np.fft.rfft(x, nn) * np.fft.rfft(k, nn), nn)
    return y[len(k) // 2:len(k) // 2 + n]


def filtro_variable(x, ganancia, nfft=2048, salto=256):
    """Filtro de fase cero que cambia con el tiempo (tramas con solapamiento del 87 %).

    `ganancia(tc, f)` devuelve la respuesta (tramas × frecuencias) en los instantes `tc` (s).
    """
    n = len(x)
    w = np.sqrt(np.hanning(nfft + 1)[:-1])
    xp = np.concatenate([np.zeros(nfft), x, np.zeros(nfft + salto)])
    nf = 1 + (len(xp) - nfft) // salto
    idx = np.arange(nfft)[None, :] + salto * np.arange(nf)[:, None]
    esp = np.fft.rfft(xp[idx] * w, axis=1)
    tc = (salto * np.arange(nf) + nfft / 2 - nfft) / SR
    h = ganancia(np.clip(tc, 0.0, n / SR), np.fft.rfftfreq(nfft, 1.0 / SR))
    tramas = np.fft.irfft(esp * h, nfft, axis=1) * w
    y = np.zeros(len(xp))
    for i in range(nf):
        y[i * salto:i * salto + nfft] += tramas[i]
    return y[nfft:nfft + n] * (salto / (0.5 * nfft))
