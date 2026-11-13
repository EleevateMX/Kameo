#!/usr/bin/env python3
"""Frente 3: aves ambientales (`amb_aves`).

El bucle actual tiene doce cantos de diez tipos (dos tipos salen dos veces), hechos con
barridos de seno puro con envolvente de campana: de cerca delatan el sintetizador y, a los
pocos minutos, se reconocen los que se repiten. Los candidatos cambian tres cosas:

  - la nota: la altura ya no es un barrido limpio (bamboleo aleatorio, vibrato de ritmo
    irregular), lleva armónicos que cambian, soplo alrededor del tono, un «chif» de ruido en
    el ataque y una resonancia de pico que hace variar el volumen según pasa la altura;
  - el repertorio: dieciocho «especies» inventadas (ninguna imita un ave ni una grabación
    concreta); en cada bucle cada una sale como mucho una vez, así que no hay figura repetida;
  - la distancia: filtro de agudos por lejanía, copias dispersas por el follaje y más sala.

Candidatos (mismo bucle de 27.43 s y misma convención que el actual):
  A «lejanas» : nueve cantos, todos lejos, cada 2.2–3.8 s; mucha sala y pocos agudos.
  B «timbre»  : once cantos a media distancia, con todo el detalle de la nota nueva.
  C «bandada» : un coro lejano de cientos de píos en oleadas y solo cinco cantos solistas.
"""

from __future__ import annotations

import numpy as np

from comun import (
    AQUI, AUDIO_MP3, DOS_PI, SR, bucle_candidato, cuerpo_de, fase_de, filtrar, gen, guardar, leer,
    lento, lin, modos, n_, poner, rampa, reverb, rms, ruido, salida, t_,
)

CUADROS = 1050  # los mismos que el bucle actual: 27.43 s
GRAVES, AGUDOS = 250.0, 8500.0
CORTES = (0, 200, 1000, 4000, 8000, 1e9)
# Niveles del juego fuera de combate y lejos de las ruinas (game_client.gd, _update_soundscape)
NIVEL_SELVA, NIVEL_AVES = 0.75, 0.5
SUBIDA_CONTEXTO = 9.0  # dB que se suben por igual las mezclas en contexto, para oírlas sin tocar el volumen


def _vago(n, g, lo, hi):
    """Modulador aleatorio (RMS ~1); en notas muy cortas se queda en un valor fijo."""
    if n < int(1.5 * SR / lo):
        return np.full(n, float(g.normal()))
    return lento(n, g, lo, hi)


def nota(g, seg, f0, f1, curva=1.0, arco=0.0, bamb=0.010, vib=0.0, vib_hz=20.0, arm=0.15, soplo=0.07,
         chif=0.25, pico=0.4, dureza=1.4, res=None):
    """Una nota de ave (pico ~1): tono que se mueve de forma irregular, con soplo y ataque de ruido.

    `f0`→`f1` con curvatura `curva` y un arco de `arco` semitonos; `bamb` es el bamboleo
    aleatorio de la altura; `vib` y `vib_hz`, un vibrato cuyo ritmo y hondura derivan; `arm`,
    el nivel de los armónicos; `pico` (0..1), dónde cae el máximo de la envolvente; `res`,
    (centro, ancho) en Hz de la resonancia que colorea el volumen.
    """
    n = max(n_(seg), 64)
    u = (np.arange(n) + 0.5) / n
    t = t_(n)
    f = f0 * (f1 / f0) ** (u ** curva) * 2.0 ** (arco * np.sin(np.pi * u) / 12.0)
    f = f * (1.0 + bamb * _vago(n, g, 5.0, 40.0))
    if vib > 0.0:
        ritmo = vib_hz * (1.0 + 0.18 * _vago(n, g, 1.0, 7.0))
        hondo = 0.55 + 0.45 * np.clip(0.5 + 0.5 * _vago(n, g, 1.0, 6.0), 0.0, 1.0)
        f = f * (1.0 + vib * hondo * np.sin(DOS_PI * np.cumsum(ritmo) / SR + g.uniform(0.0, DOS_PI)))
    w = fase_de(f)
    a2 = arm * (0.55 + 0.45 * np.sin(np.pi * u))
    y = np.sin(w) + a2 * np.sin(2 * w + 0.7) + 0.4 * a2 * np.sin(3 * w + 1.9)
    x = np.where(u < pico, 0.5 * u / pico, 0.5 + 0.5 * (u - pico) / (1.0 - pico))
    env = np.sin(np.pi * x) ** dureza * np.clip(1.0 + 0.18 * _vago(n, g, 12.0, 70.0), 0.3, None)
    env = env * rampa(n, min(0.008, 0.25 * seg)) * salida(n, min(0.012, 0.3 * seg))  # sin esquinas: ni un clic
    if res is not None:
        env = env * (0.45 + 0.55 / (1.0 + ((f - res[0]) / res[1]) ** 2))
    y = y * env
    fm = float(np.sqrt(f0 * f1))
    if soplo:
        y += soplo * ruido(n, g, 0.75 * fm, 1.35 * fm, orden=3) * env
    if chif:
        k = min(n, n_(0.014))
        y[:k] += chif * 0.3 * ruido(k, g, 0.9 * f0, min(3.0 * f0, 9000.0)) * np.exp(-t[:k] / 0.0035) * rampa(k, 0.001)
    return y


ESPECIES = ("caida", "dos_notas", "trino", "gorjeo", "arrullo", "eco", "ululo", "pios", "carraca", "flauteo",
            "silbo_sube", "zumbon", "chasquidos", "silbo_largo", "burbujeo", "graznido", "tamborileo", "pregunta")


def canto(tipo, g):
    """Un canto (mono, pico 1). Cada llamada sale distinta: tono, ritmo e intervalos al azar."""
    y = np.zeros(n_(3.2))
    k_t = g.uniform(0.86, 1.18)  # tono de este individuo
    k_v = g.uniform(0.85, 1.2)  # rapidez

    def d(s):
        return s / k_v

    if tipo == "caida":  # silbos ligados que caen
        t0, f = 0.0, 2500.0 * k_t
        for i in range(int(g.integers(2, 4))):
            dur = d(g.uniform(0.24, 0.36))
            poner(y, nota(g, dur, f, f * g.uniform(0.62, 0.74), curva=0.8, vib=0.012 * i, res=(2000.0 * k_t, 700.0)), t0, 1.0 - 0.18 * i)
            t0 += dur + d(g.uniform(0.06, 0.14))
            f *= g.uniform(0.84, 0.92)
    elif tipo == "dos_notas":  # grave-aguda, la segunda con inflexión
        f = 1650.0 * k_t
        poner(y, nota(g, d(0.15), f, f * 1.03, arm=0.1), 0.0, 0.85)
        f2 = f * 2.0 ** (g.uniform(3.0, 5.5) / 12.0)
        poner(y, nota(g, d(0.27), f2 * 0.97, f2 * g.uniform(1.0, 1.06), arco=0.6, vib=0.008, pico=0.3), d(0.22), 1.0)
    elif tipo == "trino":  # notas cortas que se aprietan o se sueltan
        k = int(g.integers(7, 14))
        acel = g.uniform(-0.03, 0.035)
        t0, f = 0.0, 2900.0 * k_t
        for i in range(k):
            poner(y, nota(g, d(0.05), f, f * 1.22, bamb=0.02, soplo=0.05, chif=0.15), t0, 0.45 + 0.55 * np.sin(np.pi * (i + 0.5) / k))
            t0 += d(0.085) * (1.0 - acel * i) * g.uniform(0.93, 1.07)
            f *= g.uniform(0.985, 1.02)
    elif tipo == "gorjeo":  # nota larga que tiembla sin compás fijo
        poner(y, nota(g, d(g.uniform(0.5, 0.8)), 2300.0 * k_t, 2050.0 * k_t, bamb=0.03, vib=g.uniform(0.06, 0.10),
                      vib_hz=g.uniform(14.0, 24.0), res=(2200.0 * k_t, 500.0)), 0.0, 1.0)
    elif tipo == "arrullo":  # paloma: notas graves, redondas y con soplo
        t0 = 0.0
        for i in range(int(g.integers(3, 5))):
            dur = d(g.uniform(0.26, 0.36))
            poner(y, nota(g, dur, 520.0 * k_t, 480.0 * k_t, arco=1.2, arm=0.28, soplo=0.16, chif=0.05, pico=0.45, dureza=1.1), t0,
                  (0.8, 1.0, 0.75, 0.55)[i])
            t0 += dur + d(g.uniform(0.05, 0.12))
    elif tipo == "eco":  # una nota clara que se repite cada vez más lejos y más apagada
        f = 1350.0 * k_t
        for i in range(int(g.integers(3, 5))):
            x = nota(g, d(0.22), f, 0.94 * f, curva=0.6, arm=0.1)
            poner(y, filtrar(x, 300.0, 5000.0 * 0.6 ** i), d(0.34) * i * g.uniform(0.97, 1.03), 0.6 ** i)
    elif tipo == "ululo":  # sube y baja despacio, dos veces
        for j, (dur, gan) in enumerate(((0.55, 1.0), (0.42, 0.6))):
            poner(y, nota(g, d(dur), 950.0 * k_t, 980.0 * k_t, arco=g.uniform(6.0, 8.5), arm=0.22, soplo=0.12, chif=0.05, pico=0.5,
                          dureza=1.2), d(0.72) * j, gan)
    elif tipo == "pios":  # píos que bajan en escalera, a destiempo
        t0, f = 0.0, 3900.0 * k_t
        for i in range(int(g.integers(4, 7))):
            poner(y, nota(g, d(g.uniform(0.05, 0.075)), f, 1.18 * f, soplo=0.05), t0, 1.0 - 0.1 * i)
            t0 += d(g.uniform(0.10, 0.17))
            f *= g.uniform(0.90, 0.96)
    elif tipo == "carraca":  # llamada seca de ruido, con un traqueteo que no va a compás
        n = n_(d(g.uniform(0.4, 0.6)))
        u = np.arange(n) / n
        ritmo = g.uniform(22.0, 30.0) * (1.0 + 0.2 * _vago(n, g, 1.0, 6.0)) * (1.0 - 0.25 * u)
        golpe = (0.5 + 0.5 * np.sin(DOS_PI * np.cumsum(ritmo) / SR)) ** 3
        port = ruido(n, g, 1700.0 * k_t, 3200.0 * k_t, orden=6) + 0.4 * ruido(n, g, 3400.0 * k_t, 5200.0 * k_t, orden=6)
        poner(y, port * golpe * np.sin(np.pi * u) ** 0.8, 0.0, 1.0)
    elif tipo == "flauteo":  # notas sueltas, aflautadas, con intervalos al azar
        t0, f = 0.0, 1800.0 * k_t
        for i in range(int(g.integers(3, 5))):
            poner(y, nota(g, d(0.2), f, f * g.uniform(0.96, 1.04), arm=0.08, soplo=0.12, pico=0.3), t0, (0.9, 1.0, 0.8, 0.7)[i])
            t0 += d(g.uniform(0.24, 0.32))
            f *= 2.0 ** (g.choice([-5.0, -3.0, 2.0, 4.0, 5.0]) / 12.0)
            f = float(np.clip(f, 1300.0 * k_t, 2900.0 * k_t))
    elif tipo == "silbo_sube":  # un solo silbo que sube y corta
        poner(y, nota(g, d(g.uniform(0.3, 0.42)), 1600.0 * k_t, 3300.0 * k_t, curva=1.8, pico=0.75, dureza=1.0, chif=0.3,
                      res=(2900.0 * k_t, 900.0)), 0.0, 1.0)
    elif tipo == "zumbon":  # nota áspera: el tono se abre y se cierra muy deprisa
        t0, f = 0.0, 2400.0 * k_t
        for i in range(2):
            n = n_(d(g.uniform(0.28, 0.42)))
            x = nota(g, n / SR, f, f * 0.93, arm=0.3, soplo=0.1)
            aspero = 0.5 + 0.5 * np.sin(DOS_PI * np.cumsum(g.uniform(70.0, 95.0) * (1.0 + 0.1 * _vago(len(x), g, 2.0, 9.0))) / SR)
            poner(y, x * (0.25 + 0.75 * aspero ** 2), t0, 1.0 - 0.25 * i)
            t0 += n / SR + d(0.12)
            f *= 0.88
    elif tipo == "chasquidos":  # parloteo: chasquidos de tono y ruido, sin compás
        t0 = 0.0
        for i in range(int(g.integers(6, 11))):
            f = g.uniform(3000.0, 4800.0) * k_t
            x = nota(g, g.uniform(0.018, 0.032), f, f * g.uniform(0.7, 0.9), arm=0.3, soplo=0.5, chif=0.8, pico=0.2, dureza=1.0)
            poner(y, x, t0, g.uniform(0.5, 1.0))
            t0 += d(g.uniform(0.07, 0.16))
    elif tipo == "silbo_largo":  # silbo largo y triste que apenas sube y luego cae temblando
        poner(y, nota(g, d(g.uniform(0.9, 1.3)), 1180.0 * k_t, 1040.0 * k_t, arco=1.6, curva=1.6, vib=0.012, vib_hz=6.5, arm=0.12,
                      soplo=0.14, chif=0.08, pico=0.35, dureza=0.9), 0.0, 1.0)
    elif tipo == "burbujeo":  # gorgoteo: gotas de tono que caen cada vez más juntas y más graves
        t0, f = 0.0, 2500.0 * k_t
        sep = d(0.11)
        for i in range(int(g.integers(8, 13))):
            poner(y, nota(g, 0.045, f, f * 0.58, curva=0.7, arm=0.2, soplo=0.04, chif=0.1, pico=0.25), t0, 0.55 + 0.45 * np.sin(np.pi * (i + 1) / 13.0))
            t0 += sep * g.uniform(0.9, 1.1)
            sep *= 0.92
            f *= 0.955
    elif tipo == "graznido":  # graznido ronco y lejano: tono con muchos armónicos, ruido y aspereza
        t0 = 0.0
        for i in range(int(g.integers(2, 4))):
            n = n_(d(g.uniform(0.16, 0.26)))
            u = np.arange(n) / n
            w = fase_de(g.uniform(620.0, 820.0) * k_t * (1.0 + 0.08 * np.sin(np.pi * u)) * (1.0 + 0.03 * _vago(n, g, 8.0, 50.0)))
            x = sum(np.sin(k * w + 0.5 * k) / k ** 0.7 for k in range(1, 9))
            x = x * (0.55 + 0.45 * np.sin(DOS_PI * np.cumsum(np.full(n, g.uniform(55.0, 80.0))) / SR)) + 1.2 * ruido(n, g, 1200.0, 4500.0)
            x = filtrar(x, 900.0, 3800.0) * np.sin(np.pi * u) ** 0.7
            poner(y, x / np.max(np.abs(x)), t0, 1.0 - 0.15 * i)
            t0 += n / SR + d(g.uniform(0.08, 0.2))
    elif tipo == "tamborileo":  # un pico golpea un tronco: redoble que se frena (no es un canto)
        t0 = 0.0
        sep = 1.0 / g.uniform(17.0, 22.0)
        f = g.uniform(620.0, 900.0)
        for i in range(int(g.integers(10, 17))):
            x = modos(((f, 1.0, 0.012), (2.6 * f, 0.5, 0.006), (4.9 * f, 0.25, 0.003)), 0.06)
            x[:n_(0.004)] += 0.5 * ruido(n_(0.004), g, 1500.0, 6000.0) * np.exp(-t_(n_(0.004)) / 0.001)
            poner(y, x, t0, (0.6 + 0.4 * np.exp(-i / 5.0)) * g.uniform(0.85, 1.0))
            t0 += sep * g.uniform(0.96, 1.04)
            sep *= 1.025
    elif tipo == "pregunta":  # dos notas iguales y una tercera que sube, como quien pregunta
        f = 2000.0 * k_t
        poner(y, nota(g, d(0.12), f, f * 0.98, arm=0.12), 0.0, 0.8)
        poner(y, nota(g, d(0.12), f * 1.01, f * 0.99, arm=0.12), d(0.19), 0.85)
        poner(y, nota(g, d(0.3), f * 1.05, f * g.uniform(1.4, 1.6), curva=1.5, vib=0.01, pico=0.6, res=(2700.0 * k_t, 800.0)), d(0.40), 1.0)
    fin = int(np.nonzero(y)[0][-1]) + 1
    y = y[:fin] * salida(fin, 0.01)
    return y / np.max(np.abs(y)) * (0.6 if tipo in ("carraca", "graznido", "chasquidos") else 1.0)


def _colocar(seco, envio, g, c, tt, cerca, p, nivel=1.0, copias=4):
    """Pone un canto a una distancia: cuanto más lejos, menos agudos, menos directo y más sala;
    el follaje deja copias tardías, apagadas y repartidas alrededor."""
    c = filtrar(c, 320.0, 1700.0 + 6500.0 * cerca ** 1.4)
    poner(seco, c, tt, nivel * (0.18 + 0.82 * cerca), p, circular=True)
    apagado = filtrar(c, 320.0, 2400.0)
    for _ in range(copias):
        poner(seco, apagado, tt + g.uniform(0.03, 0.15), nivel * g.uniform(0.07, 0.18),
              float(np.clip(p + g.uniform(-0.6, 0.6), -1.0, 1.0)), circular=True)
    poner(envio, c, tt, nivel * (0.45 + 1.0 * (1.0 - cerca)), p, circular=True)


def _lecho(n, g, por_seg, oleadas=True):
    """Bandada lejana: cientos de píos mínimos en oleadas; solo se oyen como coro con sala."""
    seg = n / SR
    lecho = np.zeros((2, n))
    dens = np.clip(0.5 + 0.6 * lento(n, g, 0.03, 0.2), 0.03, 1.0) if oleadas else np.ones(n)
    focos = g.uniform(-0.9, 0.9, 4)
    for _ in range(int(por_seg * seg)):
        t0 = g.uniform(0.0, seg)
        if g.uniform() > dens[int(t0 * SR) % n]:
            continue
        f0 = 1800.0 * (5200.0 / 1800.0) ** g.uniform()
        x = nota(g, g.uniform(0.03, 0.09), f0, f0 * g.uniform(0.7, 1.4), soplo=0.0, chif=0.0, bamb=0.02)
        poner(lecho, x, t0, g.uniform(0.2, 1.0), float(np.clip(g.choice(focos) + g.normal(0.0, 0.25), -1.0, 1.0)), circular=True)
    lecho = filtrar(lecho, 900.0, 4200.0, circular=True)
    lecho = reverb(lecho, g, t60=2.4, mezcla=1.0, circular=True, agudos=4200.0, seco=0.12)
    return lecho / (rms(lecho) + 1e-12)


def _solistas(n, g, cuantos, hueco, cerca, t60, sala, agudos_sala, excluir=(), nivel=1.0):
    """Reparte `cuantos` cantos de especies distintas por el bucle. Devuelve la mezcla y lo que cantó."""
    seg = n / SR
    seco = np.zeros((2, n))
    envio = np.zeros((2, n))
    orden = [e for e in g.permutation(ESPECIES) if e not in excluir][:cuantos]
    huecos = g.uniform(*hueco, size=len(orden))
    huecos *= seg / huecos.sum()  # el último hueco da la vuelta al bucle: el reparto es circular
    tt = g.uniform(0.3, 1.2)
    p_prev = 0.0
    for tipo, salto in zip(orden, huecos):
        p = g.uniform(-0.9, 0.9)
        if abs(p - p_prev) < 0.35:  # el siguiente canta desde otro sitio
            p = -p if abs(p) > 0.2 else p + 0.6
        p_prev = p
        _colocar(seco, envio, g, canto(tipo, g), tt, g.uniform(*cerca), p, nivel)
        tt += salto
    cola = reverb(envio, g, t60=t60, mezcla=1.0, circular=True, agudos=agudos_sala, seco=0.0)
    return seco + sala * cola, orden


def aves_a(n, g):
    y, orden = _solistas(n, g, 9, (2.3, 3.6), (0.05, 0.42), t60=2.1, sala=0.75, agudos_sala=3800.0,
                         excluir=("chasquidos", "graznido"))
    return y + 0.020 * _lecho(n, g, 10.0), orden


def aves_b(n, g):
    y, orden = _solistas(n, g, 11, (1.7, 3.1), (0.35, 0.9), t60=1.9, sala=0.55, agudos_sala=4500.0)
    return y + 0.010 * _lecho(n, g, 10.0), orden


def aves_c(n, g):
    y, orden = _solistas(n, g, 5, (4.4, 6.2), (0.08, 0.4), t60=2.1, sala=0.75, agudos_sala=3800.0,
                         excluir=("chasquidos", "graznido", "carraca", "tamborileo"), nivel=0.5)
    return y + 0.075 * _lecho(n, g, 26.0), orden


CANDIDATOS = (
    ("A_lejanas", aves_a, "nueve cantos de especies distintas, todos lejos y espaciados, con mucha sala"),
    ("B_timbre", aves_b, "once cantos de especies distintas a media distancia, con la nota nueva"),
    ("C_bandada", aves_c, "coro lejano en oleadas y cinco cantos solistas muy espaciados"),
)


def _en_selva(aves_mp3, nombre):
    """30 s del bucle de aves sobre `amb_selva`, con los niveles relativos del juego."""
    n = n_(30.0)
    selva = cuerpo_de(leer(AUDIO_MP3 / "amb_selva.mp3", 2))
    aves = cuerpo_de(leer(aves_mp3, 2))
    i = np.arange(n)
    y = NIVEL_SELVA * selva[:, i % selva.shape[-1]] + NIVEL_AVES * aves[:, i % aves.shape[-1]]
    y = y * lin(SUBIDA_CONTEXTO) * rampa(n, 0.3) * salida(n, 0.5)
    guardar(nombre, y)


def generar() -> dict:
    import shutil
    shutil.copyfile(AUDIO_MP3 / "amb_aves.mp3", AQUI / "amb_aves__actual.mp3")
    _en_selva(AQUI / "amb_aves__actual.mp3", "amb_aves_en_selva__actual")
    extra = {}
    for sufijo, fn, _ in CANDIDATOS:
        nombre = f"amb_aves__{sufijo}"
        g = gen(nombre)
        cuerpo, orden = fn(CUADROS * 1152, g)
        extra[nombre] = bucle_candidato(nombre, cuerpo, GRAVES, AGUDOS)
        extra[nombre]["cantos"] = [str(o) for o in orden]
        print(f"  {nombre}: cantos {', '.join(orden)}; costura corr {extra[nombre]['costura_corr']:.4f}")
        _en_selva(AQUI / f"{nombre}.mp3", f"amb_aves_en_selva__{sufijo}")
    orden = ["actual"] + [c[0] for c in CANDIDATOS]
    return {
        "amb_aves": {"archivos": [f"amb_aves__{s}" for s in orden], "canales": 2, "cortes": list(CORTES), "extra": extra},
        "amb_aves_en_selva": {"archivos": [f"amb_aves_en_selva__{s}" for s in orden], "canales": 2, "cortes": list(CORTES)},
    }
