#!/usr/bin/env python3
"""Utilidades comunes de los candidatos de ajuste de audio (art/audio/candidatos).

Todo es síntesis con numpy: no hay grabaciones ni muestras de terceros. Se apoya en
`art/audio/_dsp_estereo.py` (que se importa, no se edita) y añade lo que los candidatos
necesitan y los generadores del juego no tienen:

  - una voz por granos formánticos (un grano amortiguado por formante y por pulso glotal),
    con pulsos irregulares (jitter, shimmer, subarmónicos) y formantes que se mueven;
  - un filtro de formantes variable en el tiempo (por tramas con solapamiento) para el aire;
  - medidas pensadas para comparar: sonoridad momentánea máxima, reparto por bandas y la
    misma sonoridad tras un pasa-altos de 200 Hz (lo que queda en un altavoz pequeño);
  - escritura a MP3 (`libmp3lame -q:a 4`) y espectrogramas comparativos.
"""

from __future__ import annotations

import os
import sys
from pathlib import Path

import numpy as np

AQUI = Path(__file__).resolve().parent
sys.path.insert(0, str(AQUI.parent))
import _dsp_estereo as D  # noqa: E402
from _dsp_estereo import (  # noqa: E402,F401
    CUADRO_MP3, DOS_PI, SR, buen_tam, campana, campana_env, convolucionar, db, env_perc, fase_de,
    filtrar, glis, lento, limitar, lin, modos, n_, pan, poner, rafaga, rampa, reverb, rms, ruido,
    ruido_barrido, ruido_st, salida, saturar, t_, tirones, trenes,
)

RAIZ = AQUI.parents[2]
AUDIO_WAV = RAIZ / "game" / "assets" / "audio"  # efectos del juego (solo lectura)
AUDIO_MP3 = RAIZ / "game" / "web" / "static" / "audio"  # ambientes y cinemáticas (solo lectura)
SR_FX = 22050  # los efectos del juego van a 22.05 kHz mono: los candidatos se entregan igual
CALIDAD = 4  # LAME -q:a (lo pedido para la carpeta de revisión)
SEMILLA_BASE = "candidatos-2026-11"


def tmp() -> Path:
    """Carpeta de los WAV intermedios y los espectrogramas (fuera del repositorio)."""
    d = Path(os.environ.get("ALUX_AUDIO_TMP", D.carpeta_tmp())) / "candidatos"
    d.mkdir(parents=True, exist_ok=True)
    return d


def gen(nombre: str) -> np.random.Generator:
    """Generador aleatorio propio de cada candidato (semilla fija derivada de su nombre)."""
    return D.gen(f"{SEMILLA_BASE}:{nombre}")


# --------------------------------------------------------------------------------------
# Voz: pulsos glotales irregulares y granos formánticos
# --------------------------------------------------------------------------------------

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


# --------------------------------------------------------------------------------------
# Medidas
# --------------------------------------------------------------------------------------

def _k(x):
    """Ponderación K (BS.1770) de una señal (canales, n) a 44.1 kHz."""
    n = x.shape[-1]
    nn = buen_tam(n)
    return np.fft.irfft(np.fft.rfft(x, nn, axis=-1) * D._respuesta_k(np.fft.rfftfreq(nn, 1.0 / SR)), nn, axis=-1)[..., :n]


def lufs_m(x) -> float:
    """Sonoridad momentánea máxima (ventana de 400 ms, ponderación K), en LUFS.

    Para efectos cortos es la medida que mejor se compara: la sonoridad integrada necesita
    varios segundos y castiga las colas. Los sonidos de menos de 400 ms se rellenan con silencio.
    """
    x = np.atleast_2d(np.asarray(x, dtype=float))
    b = n_(0.4)
    x = np.concatenate([np.zeros((x.shape[0], b)), x, np.zeros((x.shape[0], b))], axis=-1)
    k = _k(x)
    ac = np.concatenate([[0.0], np.cumsum(np.sum(k ** 2, axis=0))])
    ini = np.arange(0, x.shape[-1] - b + 1, n_(0.01))
    return float(-0.691 + 10.0 * np.log10(np.max(ac[ini + b] - ac[ini]) / b + 1e-20))


def rms50(x) -> float:
    """RMS del tramo de 50 ms más fuerte (dBFS): la «pegada»."""
    x = np.atleast_2d(x)
    v = n_(0.05)
    ac = np.concatenate([[0.0], np.cumsum(np.mean(x ** 2, axis=0))])
    if x.shape[-1] <= v:
        return db(rms(x))
    return 10.0 * np.log10(np.max(ac[v:] - ac[:-v]) / v + 1e-20)


def bandas(x, cortes) -> list:
    """Reparto de la energía (en %) entre los cortes dados (Hz)."""
    return D.bandas_pct(np.atleast_2d(x), cortes=tuple(cortes))


def pasa_altos(x, f=200.0):
    """Lo que queda en un altavoz pequeño: pasa-altos de 4.º orden."""
    return filtrar(x, f, None, orden=4)


def tramas_periodicas(x) -> float:
    """% de tramas en las que la onda se repite con claridad (tramas de 80 ms cada 20 ms, solo
    donde hay señal; se busca el periodo de 2.5 a 40 ms en que más se repite y cuenta si la
    autocorrelación normalizada pasa de 0.5). Un zumbido de pulsos iguales da casi el 100 %;
    una voz ronca, bastante menos; un soplo, casi nada. No mide la altura: solo la regularidad."""
    m = np.mean(np.atleast_2d(x), axis=0)
    v, salto = n_(0.08), n_(0.02)
    if len(m) < 2 * v:
        return 0.0
    idx = np.arange(v)[None, :] + salto * np.arange((len(m) - v) // salto)[:, None]
    tr = m[idx] - np.mean(m[idx], axis=1, keepdims=True)
    pot = np.mean(tr ** 2, axis=1)
    tr = tr[pot > 0.003 * np.max(pot)]  # tramas a menos de 25 dB de la más fuerte
    r = np.fft.irfft(np.abs(np.fft.rfft(tr, 2 * buen_tam(v), axis=1)) ** 2, axis=1)[:, :v]
    r = r / (r[:, :1] + 1e-20) * (v / (v - np.arange(v)))[None, :]
    return float(100.0 * np.mean(np.max(r[:, int(0.0025 * SR):int(0.040 * SR)], axis=1) > 0.5))


def medir(x, cortes) -> dict:
    """Medidas de una señal a 44.1 kHz (mono o estéreo)."""
    x = np.atleast_2d(np.asarray(x, dtype=float))
    seg = x.shape[-1] / SR
    m = {
        "seg": round(seg, 2),
        "pico": round(float(db(np.max(np.abs(x)))), 1),
        "rms": round(float(db(rms(x))), 1),
        "rms50": round(float(rms50(x)), 1),
        "lufs_m": round(lufs_m(x), 1),
        "lufs_m_200": round(lufs_m(pasa_altos(x)), 1),
        "dc": float(np.max(np.abs(np.mean(x, axis=-1)))),
        "bandas": [round(b, 1) for b in bandas(x, cortes)],
    }
    if seg >= 3.0:
        m["lufs_i"] = round(D.lufs(x), 1)
    # Perfil: cuándo llega el máximo, cuánto tiempo pasa a menos de 20 dB de él y centro del espectro
    v = n_(0.01)
    ac = np.concatenate([[0.0], np.cumsum(np.mean(x ** 2, axis=0))])
    env = (ac[v:] - ac[:-v]) / v
    m["t_pico"] = round(float(np.argmax(env)) / SR, 3)
    m["seg_20db"] = round(float(np.sum(env > 0.01 * np.max(env))) / SR, 2)
    pot = np.sum(np.abs(np.fft.rfft(x, axis=-1)) ** 2, axis=0)
    f = np.fft.rfftfreq(x.shape[-1], 1.0 / SR)
    m["centroide"] = int(round(float(np.sum(f * pot) / (np.sum(pot) + 1e-20))))
    if seg <= 6.0:
        m["tramas_periodicas"] = round(tramas_periodicas(x))
    return m


# --------------------------------------------------------------------------------------
# Archivos
# --------------------------------------------------------------------------------------

def escribir_wav(ruta: Path, x: np.ndarray, sr: int) -> None:
    """WAV PCM de 24 bits a la frecuencia dada (intermedio; no se versiona)."""
    x = np.atleast_2d(x)
    datos = np.round(np.clip(x.T, -1.0, 1.0) * 8388607.0).astype("<i4")
    crudo = datos.reshape(-1).view(np.uint8).reshape(-1, 4)[:, :3].tobytes()
    c = x.shape[0]
    cab = b"RIFF" + (36 + len(crudo)).to_bytes(4, "little") + b"WAVEfmt " + (16).to_bytes(4, "little")
    cab += (1).to_bytes(2, "little") + c.to_bytes(2, "little") + sr.to_bytes(4, "little")
    cab += (sr * c * 3).to_bytes(4, "little") + (c * 3).to_bytes(2, "little") + (24).to_bytes(2, "little")
    cab += b"data" + len(crudo).to_bytes(4, "little")
    Path(ruta).write_bytes(cab + crudo)


def a_mp3(origen: Path, destino: Path, sr: int, canales: int) -> None:
    """Codifica con LAME (`-q:a 4`), sin etiquetas ni fechas (dos ejecuciones dan los mismos bytes)."""
    D._ffmpeg(["-y", "-v", "error", "-i", str(origen), "-c:a", "libmp3lame", "-q:a", str(CALIDAD),
               "-ar", str(sr), "-ac", str(canales), "-map_metadata", "-1", "-id3v2_version", "0",
               "-write_id3v1", "0", "-fflags", "+bitexact", "-flags:a", "+bitexact", str(destino)])


def guardar(nombre: str, x: np.ndarray, sr: int = SR) -> Path:
    """Escribe `<nombre>.mp3` en la carpeta de candidatos (mono si la señal es mono)."""
    wav = tmp() / f"{nombre}.wav"
    escribir_wav(wav, x, sr)
    mp3 = AQUI / f"{nombre}.mp3"
    a_mp3(wav, mp3, sr, 1 if np.ndim(x) == 1 else 2)
    return mp3


def leer(ruta: Path, canales: int) -> np.ndarray:
    """Decodifica un archivo de audio a 44.1 kHz: (n,) si se pide mono, (2, n) si estéreo."""
    crudo = D._ffmpeg(["-v", "error", "-i", str(ruta), "-f", "f32le", "-ac", str(canales), "-ar", str(SR), "-"],
                      binario=True)
    x = np.frombuffer(crudo, dtype="<f4").astype(np.float64)
    return x if canales == 1 else x.reshape(-1, 2).T


def a_22k(x: np.ndarray) -> np.ndarray:
    """Mono a 44.1 kHz → 22.05 kHz (remuestreo exacto por FFT; la señal debe ir ya filtrada)."""
    n = len(x) - len(x) % 4
    esp = np.fft.rfft(x[:n])
    m = n // 2
    return np.fft.irfft(esp[:m // 2 + 1], m) * 0.5


def acabar_fx(x, seg, agudos, fundido, graves=30.0):
    """Acabado de un efecto mono, como `acabar_efecto` de gen_audio.py: 3 ms de silencio delante,
    recorte a `seg`, filtros, entrada de 2 ms, fundido final y sin continua. Sale a 22.05 kHz."""
    n = n_(seg)
    n -= n % 4
    x = np.concatenate([np.zeros(n_(0.003)), x, np.zeros(max(0, n - len(x)))])[:n]
    x = filtrar(x, graves, None, orden=2)
    x = filtrar(x, None, min(agudos, 9500.0), orden=4)
    v = rampa(n, 0.002) * salida(n, fundido)
    v[0] = 0.0
    x = x * v
    x = x - v * (np.sum(x) / np.sum(v))
    return a_22k(x)


def igualar(x, objetivo_lufs_m, techo_db=-1.5, sr=SR_FX):
    """Ajusta el nivel para que la sonoridad momentánea máxima sea la del sonido actual.

    Si para eso el pico pasa de `techo_db`, se doman los picos con el limitador y se repite.
    """
    for _ in range(4):
        x = x * lin(objetivo_lufs_m - lufs_m(_sube(x, sr)))
        if db(np.max(np.abs(x))) <= techo_db:
            break
        x = _limitar_sr(x, lin(techo_db), sr)
    return x


def _sube(x, sr):
    """Señal a 44.1 kHz para medir (interpola por FFT si viene a 22.05 kHz)."""
    if sr == SR:
        return x
    n = len(x)
    esp = np.fft.rfft(x)
    return np.fft.irfft(np.concatenate([esp, np.zeros(n - len(esp) + 1)]), 2 * n) * 2.0


def _limitar_sr(x, techo, sr):
    if sr == SR:
        return limitar(x, techo)
    y = limitar(_sube(x, sr), techo * 0.98)
    return a_22k(np.concatenate([y, np.zeros((-len(y)) % 4)]))[:len(x)]


# --------------------------------------------------------------------------------------
# Bucles de ambiente (misma convención que gen_ambiente.py)
# --------------------------------------------------------------------------------------

MARGEN = 0.5  # segundos de `pre` y de `post`


def cuerpo_de(x):
    """Cuerpo circular de un bucle decodificado: quita el `pre` y el `post` de medio segundo."""
    h = n_(MARGEN)
    largo = int(round((x.shape[-1] - 2 * h) / CUADRO_MP3)) * CUADRO_MP3
    return x[:, h:h + largo]


def costura(x, largo):
    """Costura de un bucle decodificado, como la mide `gen_ambiente.py --check`: correlación
    mínima entre lo que suena tras `loop[1]` y tras `loop[0]` (con varios desfases del
    decodificador), salto máximo en el empalme y salto típico entre muestras (percentil 99.9)."""
    v = n_(0.05)
    ini = n_(MARGEN)
    fin = ini + largo
    corr_min, salto = 1.0, 0.0
    tipico = float(np.percentile(np.abs(np.diff(x, axis=-1)), 99.9))
    for des in (0, 529, 1105, 2257):
        a, b = x[:, ini + des:ini + des + v].ravel(), x[:, fin + des:fin + des + v].ravel()
        if len(b) < 2 * v:
            return 0.0, salto, tipico
        corr_min = min(corr_min, float(np.corrcoef(a, b)[0, 1]))
        salto = max(salto, float(np.max(np.abs(x[:, ini + des] - x[:, fin + des - 1]))))
    return corr_min, salto, tipico


def bucle_candidato(nombre, cuerpo, graves, agudos) -> dict:
    """Acaba un cuerpo circular como los bucles del juego (−28 LUFS, pico ≤ −6 dBFS, cuerpo de
    cuadros MP3 enteros, medio segundo repetido a cada lado), lo guarda y comprueba la costura."""
    import gen_ambiente as GA
    assert cuerpo.shape[-1] % CUADRO_MP3 == 0, "el cuerpo debe medir cuadros MP3 enteros"
    cuerpo = GA.acabar_bucle(cuerpo, graves, agudos)
    for _ in range(3):  # el MP3 cambia algo la sonoridad y los picos: se corrige midiendo el resultado
        mp3 = guardar(nombre, GA.con_margenes(cuerpo))
        x = leer(mp3, 2)
        falta = GA.LUFS_OBJ - D.lufs_ffmpeg(mp3)
        sobra = db(np.max(np.abs(x))) - (GA.PICO_MAX - 0.8)
        if abs(falta) <= 0.25 and sobra <= 0.0:
            break
        cuerpo = cuerpo * lin(falta)
        if sobra > 0.0:
            cuerpo = limitar(cuerpo, lin(GA.TECHO - sobra), circular=True)
    corr, salto, tipico = costura(x, cuerpo.shape[-1])
    return {"bucle_s": round(cuerpo.shape[-1] / SR, 3), "cuadros": cuerpo.shape[-1] // CUADRO_MP3,
            "lufs_ffmpeg": round(D.lufs_ffmpeg(mp3), 1), "costura_corr": round(corr, 4),
            "costura_salto": round(salto, 5), "salto_tipico": round(tipico, 5),
            "corr_canales": round(D.corr_canales(x), 2)}


def espectro_comparado(rutas, png: Path, canales=1, ancho=1800, alto=620, hueco=0.25) -> None:
    """Un solo espectrograma con varios archivos seguidos (el primero es el actual), separados
    por un hueco de silencio: sirve para compararlos de un vistazo."""
    trozos = []
    for r in rutas:
        x = leer(r, 1 if canales == 1 else 2)
        if canales == 2:
            x = 0.5 * (x[0] + x[1])
        trozos += [x, np.zeros(n_(hueco))]
    wav = tmp() / (png.stem + "_cmp.wav")
    escribir_wav(wav, np.concatenate(trozos[:-1]), SR)
    D._ffmpeg(["-y", "-v", "error", "-i", str(wav), "-lavfi",
               f"showspectrumpic=s={ancho}x{alto}:mode=combined:legend=1:scale=log:fscale=log:"
               f"drange=80:limit=-6:color=intensity", str(png)])
