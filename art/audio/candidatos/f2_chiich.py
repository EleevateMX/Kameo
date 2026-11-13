#!/usr/bin/env python3
"""Frente 2: la voz de Chiich Yaxché (la abuela árbol) en el plano 4 de «El llamado».

La voz actual son pulsos de crujido (30–56 por segundo) que excitan dos resonancias de madera:
tiene la curva de una frase, pero ningún rasgo de voz, y puede sonar a puerta. Los candidatos
son una voz anciana sugerida, sin palabras: pulsos glotales a altura de voz (con el temblor y
la ronquera de una voz vieja), formantes de vocales abiertas que se mueven de sílaba en
sílaba, y la misma entonación de dos frases —una llamada que sube y un refunfuño que cae—
en los mismos tiempos que la actual (14.80–16.50 s y 16.90–18.56 s de la cinemática).

Candidatos:
  A «murmullo»: voz de anciana que tararea con la boca entreabierta (unos 172 Hz); poca madera.
  B «tronco»  : voz más grave (124 Hz) que suena dentro del árbol: cada pulso golpea también la
                madera hueca y el tronco resuena y cruje alrededor.
  C «susurro» : voz de aire: susurro con las mismas vocales y un hilo de voz por debajo.

La pista en contexto se obtiene de `gen_cine.fx_llamado()` (importado, sin tocarlo) quitándole
solo la voz: el resto de la pista es idéntico, muestra a muestra, antes del acabado.
"""

from __future__ import annotations

import hashlib
import shutil
from pathlib import Path

import numpy as np

import _dsp_estereo as D
import gen_cine
from comun import (
    AQUI, AUDIO_MP3, DOS_PI, SR, Tracto, convolucionar, db, env_pulsos, filtrar, filtro_variable, gen,
    granos, guardar, leer, lento, lin, modos, n_, pan, poner, pulsos, rampa, reverb, rms, ruido,
    ruido_st, salida, suavizar, t_, tmp,
)

T_PLANO = 14.5  # el plano 4 empieza aquí; el búfer de la voz, también
SEG_VOZ = 4.4
CORTES = (0, 150, 400, 1000, 3000, 1e9)

# Vocales de una voz de mujer mayor (Hz, ancho, ganancia) y murmullo nasal entre sílabas
VOCALES = {
    "a": ((800.0, 80.0, 1.00), (1150.0, 90.0, 0.60), (2800.0, 120.0, 0.16), (3500.0, 130.0, 0.06), (4950.0, 140.0, 0.010)),
    "o": ((450.0, 70.0, 1.00), (800.0, 80.0, 0.38), (2830.0, 100.0, 0.14), (3500.0, 130.0, 0.04), (4950.0, 135.0, 0.005)),
    "e": ((420.0, 60.0, 1.00), (1650.0, 80.0, 0.22), (2700.0, 120.0, 0.11), (3300.0, 150.0, 0.05), (4950.0, 200.0, 0.005)),
    "u": ((340.0, 50.0, 1.00), (720.0, 60.0, 0.26), (2530.0, 170.0, 0.04), (3500.0, 180.0, 0.012), (4950.0, 200.0, 0.002)),
    "m": ((270.0, 60.0, 0.70), (1050.0, 150.0, 0.08), (2300.0, 200.0, 0.03), (3300.0, 250.0, 0.010), (4950.0, 300.0, 0.001)),
}

# Sílabas: (inicio, duración, tono inicial y final en semitonos sobre la base, vocal inicial y final, fuerza)
# Frase 1, la llamada: tres sílabas con la segunda acentuada, pausa, y dos más con la última hacia arriba
FRASE_1 = ((0.00, 0.22, 0.0, 1.0, "e", "e", 0.80), (0.24, 0.36, 4.0, 3.0, "a", "a", 1.25), (0.62, 0.26, 1.5, -1.0, "o", "o", 0.80),
           (1.02, 0.18, 0.0, 2.0, "a", "a", 0.85), (1.22, 0.50, 3.0, 8.0, "o", "a", 1.30))
# Frase 2, el refunfuño: siete sílabas más bajas y más rápidas, que caen
FRASE_2 = ((0.00, 0.16, 2.0, 2.0, "a", "a", 0.70), (0.18, 0.22, 3.0, 2.0, "o", "o", 0.90), (0.42, 0.16, 1.0, 1.0, "e", "e", 0.70),
           (0.62, 0.16, 1.0, 0.0, "o", "o", 0.70), (0.80, 0.16, 0.0, 0.0, "a", "a", 0.70), (0.98, 0.24, 0.0, -2.0, "o", "o", 0.90),
           (1.24, 0.44, -3.0, -8.0, "o", "u", 0.80))
INICIO_1, INICIO_2 = 0.30, 2.40


def _guion(n):
    """Curvas de la frase a lo largo del búfer: tono (semitonos), fuerza, ronquera y tracto."""
    t = t_(n)
    tono = np.zeros(n)
    fuerza = np.zeros(n)
    ronca = np.zeros(n)
    claves = []  # (instante, formantes)
    for t0, frase in ((INICIO_1, FRASE_1), (INICIO_2, FRASE_2)):
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
    tc = np.array([c[0] for c in claves])
    m = np.array([c[1] for c in claves])
    return tono, fuerza, ronca, tc, m


def _voz(g, n, base, escala, aire, susurro=0.0, temblor=0.022, ataque=0.0009, pecho=0.55):
    """La frase sin palabras (mono) y su envolvente. `susurro` (0..1) cambia voz por aire.

    `pecho` es la ganancia de un formante grave fijo, justo encima de la altura de la voz: da
    el calor de la fundamental, que los formantes de las vocales solos dejan flaca.
    """
    t = t_(n)
    tono, fuerza, ronca, tc, m = _guion(n)
    grave = np.tile([[1.12 * base / escala, 110.0, pecho]], (len(tc), 1, 1))
    m = np.concatenate([grave, m], axis=1)
    tr = Tracto(tc, m[:, :, 0] * escala, m[:, :, 1] * (1.0 + 0.6 * susurro), m[:, :, 2])
    # voz vieja: temblor de unos 5 Hz que no es regular, y altura que deriva
    tiembla = np.sin(DOS_PI * np.cumsum(5.2 * (1.0 + 0.12 * lento(n, g, 0.5, 2.5))) / SR)
    f0 = base * 2.0 ** (tono / 12.0) * (1.0 + temblor * tiembla * (0.6 + 0.4 * lento(n, g, 0.3, 1.5))) \
        * (1.0 + 0.012 * lento(n, g, 1.0, 6.0)) * (1.0 - 0.10 * ronca)
    tp, amp = pulsos(n, g, f0, jitter=0.018 + 0.05 * ronca, shimmer=0.12, sub=0.10 + 0.75 * ronca, retardo=0.06)
    env_p = np.interp(tp, t, fuerza * (1.0 + 0.08 * tiembla))
    vivo = env_p > 1e-3
    tp, amp = tp[vivo], amp[vivo] * env_p[vivo]
    voz = granos(n, tp, amp, tr, ataque=ataque)
    nivel = rms(voz[fuerza > 0.3]) + 1e-12
    voz /= nivel
    # aire de la voz: ruido a ráfagas glotales por el mismo tracto (más cuando la voz se rompe)
    soplo = ruido(n, g, 300, 9000, color=0.6) * (0.5 * fuerza + env_pulsos(n, tp, amp, 0.0015))
    soplo = filtro_variable(soplo, lambda tt, f: tr.ganancia(tt, f, ancho=1.6) * (f / (f + 900.0)))
    soplo /= rms(soplo[fuerza > 0.3]) + 1e-12
    y = (1.0 - susurro) * voz + (aire + susurro) * soplo
    return y, fuerza, tr, (tp, amp)


def _crujido(g, seg, f, ritmo=(9.0, 17.0)):
    """El tronco cruje al moverse: pega y resbala lento, grave y apagado (no una puerta: sin tono que suba)."""
    n = n_(seg)
    u = np.arange(n) / n
    tp, amp = pulsos(n, g, ritmo[0] + (ritmo[1] - ritmo[0]) * np.sin(np.pi * u), jitter=0.3, shimmer=0.5)
    tr = Tracto(np.array([0.0, seg]), np.tile([f, 2.71 * f, 5.15 * f], (2, 1)), np.tile([14.0, 30.0, 60.0], (2, 1)),
                np.tile([1.0, 0.45, 0.15], (2, 1)))
    y = granos(n, tp, amp * np.interp(tp, t_(n), np.sin(np.pi * u) ** 0.8), tr, ataque=0.0015)
    return filtrar(y, 80, 1600) / (np.max(np.abs(y)) + 1e-12)


def _tronco(x, mezcla):
    """La voz dentro de un tronco hueco: se suma su paso por las resonancias de la cavidad."""
    ri = modos(((132.0, 0.45, 0.050), (287.0, 1.0, 0.035), (455.0, 0.7, 0.025), (910.0, 0.3, 0.012)), 0.25)
    hueco = convolucionar(x, ri, circular=False)
    return x + mezcla * hueco * (rms(x) / (rms(hueco) + 1e-12))


def _entorno(g, mono, fuerza, crujidos_gan, aire_gan):
    """Coloca la voz (estéreo, algo a la izquierda como la actual) con su aire y sus crujidos."""
    n = len(mono)
    y = pan(mono, -0.15)
    lleno = np.clip(suavizar(fuerza, 0.35), 0.0, None)
    y = y + aire_gan * rms(mono[fuerza > 0.3]) * ruido_st(n, g, 150, 1100, color=1.2, ancho=0.6) * lleno
    for t0, f in ((0.05, 150.0), (2.10, 120.0)):  # mismos sitios que en la pista actual
        poner(y, _crujido(g, 0.5, f), t0, crujidos_gan * rms(mono[fuerza > 0.3]), 0.3)
    return y


def voz_a(g):
    n = n_(SEG_VOZ)
    mono, fuerza, _, _ = _voz(g, n, base=172.0, escala=0.95, aire=0.28)
    return _entorno(g, _tronco(mono, 0.15), fuerza, crujidos_gan=0.35, aire_gan=0.10)


def voz_b(g):
    n = n_(SEG_VOZ)
    mono, fuerza, tr, (tp, amp) = _voz(g, n, base=124.0, escala=0.86, aire=0.22, temblor=0.018, ataque=0.0011, pecho=0.25)
    # cada pulso de la voz golpea también la madera: tres modos fijos de tabla hueca
    madera = Tracto(np.array([0.0, SEG_VOZ]), np.tile([208.0, 395.0, 760.0], (2, 1)), np.tile([26.0, 40.0, 70.0], (2, 1)),
                    np.tile([1.0, 0.7, 0.35], (2, 1)))
    tabla = granos(n, tp, amp, madera, ataque=0.0015)
    mono = mono + 0.45 * tabla / (rms(tabla[fuerza > 0.3]) + 1e-12)
    return _entorno(g, _tronco(mono, 0.40), fuerza, crujidos_gan=0.9, aire_gan=0.12)


def voz_c(g):
    n = n_(SEG_VOZ)
    mono, fuerza, _, _ = _voz(g, n, base=150.0, escala=0.93, aire=0.25, susurro=0.72)
    return _entorno(g, _tronco(mono, 0.20), fuerza, crujidos_gan=0.30, aire_gan=0.18)


CANDIDATOS = (
    ("A_murmullo", voz_a, "voz de anciana que tararea (172 Hz), vocales abiertas, poca madera"),
    ("B_tronco", voz_b, "voz grave (124 Hz) dentro del tronco: madera golpeada por cada pulso, cavidad y crujidos"),
    ("C_susurro", voz_c, "susurro con las mismas vocales y un hilo de voz por debajo"),
)


def _sin_voz():
    """La pista de efectos de «El llamado» sin la voz de árbol, y la voz actual aislada.

    `gen_cine.silaba` se sustituye un momento por una versión muda que consume los mismos
    números aleatorios: así todo lo demás sale idéntico y la resta deja la voz sola.
    El resultado se guarda en la carpeta temporal (con la huella de los generadores) para no
    repetir las dos pasadas cada vez que se retoca un candidato.
    """
    huella = hashlib.sha1(b"".join(Path(m.__file__).read_bytes() for m in (gen_cine, D))).hexdigest()
    cache = tmp() / "llamado_base.npz"
    if cache.exists():
        z = np.load(cache)
        if str(z["huella"]) == huella:
            return z["resto"], z["voz"]
    completa = gen_cine.fx_llamado()
    original = gen_cine.silaba
    gen_cine.silaba = lambda *a, **k: 0.0 * original(*a, **k)
    try:
        resto = gen_cine.fx_llamado()
    finally:
        gen_cine.silaba = original
    np.savez(cache, huella=huella, resto=resto, voz=completa - resto)
    return resto, completa - resto


def _acabar_pista(x):
    """El mismo acabado que da gen_cine a la pista de efectos (−18 LUFS, techo −4.2 dBFS)."""
    seg = gen_cine.total("llamado") + gen_cine.COLA
    return gen_cine.acabar(x, seg, gen_cine.FX_LUFS[2], gen_cine.FX_TECHO, 14000.0)


def generar() -> dict:
    resto, voz_actual = _sin_voz()
    a, b = n_(T_PLANO), n_(T_PLANO + SEG_VOZ + 0.6)
    fuera = float(np.max(np.abs(voz_actual[:, :a - 10]))) if a > 10 else 0.0
    assert fuera < 1e-6, f"la resta no aísla la voz ({fuera})"
    nivel_actual = D.lufs(voz_actual[:, a:b])
    sueltas = {"actual": voz_actual[:, a:b]}
    pistas = {}
    for sufijo, fn, _ in CANDIDATOS:
        g = gen(f"chiich_voz__{sufijo}")
        v = filtrar(fn(g), 110.0, 6000.0)
        v = reverb(v, g, t60=0.9, mezcla=0.18, agudos=4500.0)[:, :n_(SEG_VOZ + 0.3)]  # la misma sala corta que la actual…
        v = reverb(v, g, t60=1.5, mezcla=0.2, agudos=6000.0)  # …y la sala de toda la pista
        v = np.concatenate([v, np.zeros((2, max(0, b - a - v.shape[-1])))], axis=-1)[:, :b - a]
        v = v * rampa(b - a, 0.01) * salida(b - a, 0.3)
        v = v * lin(nivel_actual - D.lufs(v))  # misma sonoridad que la voz actual dentro de la pista
        sueltas[sufijo] = v
        y = resto.copy()
        m = min(b, y.shape[-1])
        y[:, a:m] += v[:, :m - a]
        pistas[sufijo] = _acabar_pista(y)
    # Frases sueltas: todas con la misma ganancia, la que deja la actual en −20 LUFS
    gan = lin(-20.0 - nivel_actual)
    gan = min(gan, lin(-1.5) / max(float(np.max(np.abs(v))) for v in sueltas.values()))
    for sufijo, v in sueltas.items():
        guardar(f"chiich_voz__{sufijo}", v * gan)
    shutil.copyfile(AUDIO_MP3 / "cine_llamado_fx.mp3", AQUI / "cine_llamado_fx__actual.mp3")
    for sufijo, y in pistas.items():
        guardar(f"cine_llamado_fx__{sufijo}", y)
    # Los mismos hitos de tiempo que exige `gen_cine.py --check` a la pista de efectos de «El llamado»
    hitos = {}
    for sufijo in ["actual"] + list(pistas):
        x = leer(AQUI / f"cine_llamado_fx__{sufijo}.mp3", 2)
        fallos = [que for cine, pista, que, prueba in gen_cine.HITOS if cine == "llamado" and pista == "fx" and not prueba(x)]
        sello = gen_cine._tramo_db(x, 10.0, 14.0, 60, 250) - gen_cine._tramo_db(x, 15.0, 18.0, 60, 250)
        voz = gen_cine._tramo_db(x, 14.8, 18.2, 200, 1500) - gen_cine._tramo_db(x, 10.0, 14.0, 200, 1500)
        hitos[f"cine_llamado_fx__{sufijo}"] = {"fallos": fallos, "sello_sobre_plano4_db": round(sello, 1),
                                               "voz_sobre_plano3_db": round(voz, 1)}
        print(f"  hitos de cine_llamado_fx__{sufijo}: {'ok' if not fallos else fallos}; sello {sello:+.1f} dB (mín. +6), "
              f"voz {voz:+.1f} dB (mín. +6); LUFS {D.lufs(x):.1f}, pico {db(np.max(np.abs(x))):.1f} dBFS")
    orden = ["actual"] + [c[0] for c in CANDIDATOS]
    return {
        "chiich_voz": {"archivos": [f"chiich_voz__{s}" for s in orden], "canales": 2, "cortes": list(CORTES)},
        "cine_llamado_fx": {"archivos": [f"cine_llamado_fx__{s}" for s in orden], "canales": 2, "cortes": list(CORTES),
                            "extra": hitos},
    }
