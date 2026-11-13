#!/usr/bin/env python3
"""Candidatos de ajuste de timbre y mezcla del audio de ALUX (carpeta de revisión).

Genera en esta carpeta, para cada frente, el sonido actual como referencia (`__actual.mp3`)
y dos o tres candidatos (`__A_…`, `__B_…`, `__C_…`), todos en MP3 (`libmp3lame -q:a 4`), y
`medidas.json` con lo que mide cada archivo. No toca nada de lo que usa el juego: lee los
sonidos actuales de `game/` y los generadores de `art/audio/` y solo escribe aquí.

Todo es síntesis con numpy (semillas fijas): ni grabaciones ni muestras de terceros.

Uso (un solo proceso; cada frente tarda entre unos segundos y medio minuto):
    python art/audio/candidatos/gen_candidatos.py                  # todos los frentes
    python art/audio/candidatos/gen_candidatos.py --solo balam     # balam, chiich, aves, graves, jefe
    python art/audio/candidatos/gen_candidatos.py --medir          # solo vuelve a medir los MP3
    python art/audio/candidatos/gen_candidatos.py --espectros DIR  # espectrogramas comparativos
    python art/audio/candidatos/gen_candidatos.py --tablas         # tablas Markdown (las de LEEME.md)
"""

from __future__ import annotations

import argparse
import json
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import comun as C  # noqa: E402

FRENTES = ("balam", "chiich", "aves", "graves", "jefe")
MEDIDAS = C.AQUI / "medidas.json"


def _efectos(sonidos, cortes) -> dict:
    """Efectos mono del motor: copia el actual (WAV → MP3) y genera los candidatos a su sonoridad."""
    grupos = {}
    for frente, seg, agudos, fundido, candidatos in sonidos:
        wav = C.AUDIO_WAV / f"{frente}.wav"
        C.a_mp3(wav, C.AQUI / f"{frente}__actual.mp3", C.SR_FX, 1)
        objetivo = C.lufs_m(C.leer(wav, 1))
        nombres = [f"{frente}__actual"]
        for fila in candidatos:
            sufijo, fn = fila[0], fila[1]
            seg_c = fila[3] if len(fila) > 3 else seg  # algún candidato «con cola» dura más
            nombre = f"{frente}__{sufijo}"
            x = C.acabar_fx(fn(C.gen(nombre)), seg_c, agudos, fundido)
            C.guardar(nombre, C.igualar(x, objetivo), C.SR_FX)
            nombres.append(nombre)
        grupos[frente] = {"archivos": nombres, "canales": 1, "cortes": list(cortes)}
    return grupos


def frente_balam() -> dict:
    import f1_balam as F
    return _efectos(F.SONIDOS, F.CORTES)


def frente_jefe() -> dict:
    import f5_jefe as F
    return _efectos(F.SONIDOS, F.CORTES)


def frente_chiich() -> dict:
    import f2_chiich as F
    return F.generar()


def frente_aves() -> dict:
    import f3_aves as F
    return F.generar()


def frente_graves() -> dict:
    import f4_graves as F
    return F.generar()


def medir(grupos: dict) -> dict:
    """Mide los MP3 de la carpeta (decodificados), grupo a grupo."""
    for frente, grp in grupos.items():
        grp["medidas"] = {}
        for nombre in grp["archivos"]:
            ruta = C.AQUI / f"{nombre}.mp3"
            m = C.medir(C.leer(ruta, grp["canales"]), grp["cortes"])
            m["bytes"] = ruta.stat().st_size
            grp["medidas"][nombre] = m
    return grupos


def imprimir(grupos: dict) -> None:
    for frente, grp in grupos.items():
        c = grp["cortes"]
        cab = " ".join(f"{('<' if i == 0 else '') + str(int(c[i + 1])) if c[i + 1] < 1e8 else '>' + str(int(c[i])):>6}"
                       for i in range(len(c) - 1))
        print(f"\n{frente}  (bandas en %: {cab})")
        print(f"  {'archivo':<38}{'seg':>6}{'pico':>7}{'RMS':>7}{'RMS50':>7}{'LUFS-M':>8}{'>200Hz':>8}{'LUFS-I':>8}{'bytes':>8}  bandas")
        for nombre, m in grp["medidas"].items():
            li = f"{m['lufs_i']:>8.1f}" if "lufs_i" in m else f"{'':>8}"
            print(f"  {nombre:<38}{m['seg']:>6.2f}{m['pico']:>7.1f}{m['rms']:>7.1f}{m['rms50']:>7.1f}{m['lufs_m']:>8.1f}"
                  f"{m['lufs_m_200']:>8.1f}{li}{m['bytes']:>8}  " + " ".join(f"{b:>5.1f}" for b in m["bandas"]))


def _n(v, d=1) -> str:
    return f"{v:.{d}f}".replace("-", "−")


def _cab_bandas(c) -> list:
    out = []
    for i in range(len(c) - 1):
        if i == 0:
            out.append(f"< {int(c[1])} Hz")
        elif c[i + 1] > 1e8:
            out.append(f"> {int(c[i])} Hz")
        else:
            out.append(f"{int(c[i])}–{int(c[i + 1])} Hz")
    return out


def tabla_md(grp: dict) -> str:
    """Tabla Markdown de un grupo de `medidas.json` (un sonido actual y sus candidatos)."""
    bucle = "extra" in grp and any("bucle_s" in e for e in grp["extra"].values())
    largo = any("lufs_i" in m for m in grp["medidas"].values())
    cab = ["Archivo", "s", "Pico (dBFS)", "RMS"]
    cab += ["LUFS", "LUFS-M máx", "íd. > 200 Hz"] if largo else ["RMS 50 ms", "LUFS-M", "íd. > 200 Hz", "Máximo en (s)", "A −20 dB (s)"]
    cab += [b + " (%)" for b in _cab_bandas(grp["cortes"])]
    voz = grp.get("frente") == "balam"
    cab += ["Costura", "I·D"] if bucle else ["Tramas periódicas (%)"] if voz else ["Centro (Hz)"]
    cab += ["Bytes"]
    filas = ["| " + " | ".join(cab) + " |", "|" + " --- |" * len(cab)]
    for nombre, m in grp["medidas"].items():
        f = [f"`{nombre}.mp3`", f"{m['seg']:.2f}", _n(m["pico"]), _n(m["rms"])]
        if largo:
            f += [_n(m["lufs_i"]), _n(m["lufs_m"]), _n(m["lufs_m_200"])]
        else:
            f += [_n(m["rms50"]), _n(m["lufs_m"]), _n(m["lufs_m_200"]), f"{m['t_pico']:.2f}", f"{m['seg_20db']:.2f}"]
        f += [f"{b:.0f}" for b in m["bandas"]]
        if bucle:
            e = grp["extra"].get(nombre)
            f += [f"{e['costura_corr']:.4f}", f"{e['corr_canales']:.2f}"] if e else ["(juego)", ""]
        elif voz:
            f += [str(m["tramas_periodicas"])]
        else:
            f += [str(m["centroide"])]
        f += [str(m["bytes"])]
        filas.append("| " + " | ".join(f) + " |")
    return "\n".join(filas)


# Sonidos del juego que entran en la tabla de mezcla: (archivo, ajuste en dB con que lo lanza el juego, cuándo)
MEZCLA_FX = (
    ("balam_rugido", None, "sin evento en el juego"),
    ("balam_grunido", -3.0, "al transformarse (−9 los de otros jugadores)"),
    ("balam_especial", -2.0, "zarpazo a plena carga (−8 los de otros)"),
    ("zarpazo", 3.0, "suena a la vez que `balam_especial` (−5 los de otros)"),
    ("transformar", 0.0, "suena a la vez que `balam_grunido`"),
    ("jefe_paso", -2.0, "cada paso (+2 al cambiar de sitio, +3 al arrancar la embestida)"),
    ("jefe_aviso", -1.0, "antes de la losa (−3 barrido, +1 embestida)"),
    ("jefe_losa", 0.0, "golpe de losa; la música baja 5 dB"),
    ("jefe_barrido", 0.0, "barrido y al soltarse las cadenas"),
    ("jefe_embestida", 0.0, "anuncio de la embestida, con `jefe_aviso` a +1"),
    ("jefe_choque", 2.0, "choque; la música baja 8 dB"),
    ("jefe_aturdido", 0.0, "a la vez que `jefe_choque`"),
    ("pilar_rompe", 0.0, "a la vez que `jefe_choque` (−2 cuando cae una columna sola)"),
    ("jefe_cae", 0.0, "liberación; la música baja 10 dB"),
    ("liberacion", 0.0, "a la vez que `jefe_cae` (sin posición)"),
    ("jefe_despierta", 2.0, "despertar; la música baja 7 dB"),
)
MEZCLA_BUCLES = (
    ("amb_selva", 0.75, "base (×0.4 en las ruinas)"),
    ("amb_aves", 0.5, "0.2 en combate; ×0.2 en las ruinas"),
    ("amb_insectos", 0.3, ""),
    ("amb_viento", 0.2, "hasta 0.5 en la pirámide; +0.2 en combate"),
    ("amb_agua", 0.6, "junto al cenote"),
    ("amb_cenote", 0.45, "junto al cenote"),
    ("amb_ruinas", 0.7, "en el santuario (0.4 en la pirámide)"),
)
BUS_SFX = -1.8  # dB: efectos 0.9 × general 0.9 (volúmenes por defecto)
BUS_AMB = -2.9  # dB: ambiente 0.8 × general 0.9
BUS_MUS = -4.0  # dB: música 0.7 × general 0.9


def tabla_mezcla() -> str:
    """Niveles actuales de los sonidos de los cinco frentes y de los que suenan con ellos."""
    filas = ["| Sonido | Pico (dBFS) | RMS | LUFS-M | íd. > 200 Hz | Ajuste en el juego (dB) | LUFS-M a la salida | Cuándo |",
             "| --- | --- | --- | --- | --- | --- | --- | --- |"]
    for nombre, ajuste, cuando in MEZCLA_FX:
        m = C.medir(C.leer(C.AUDIO_WAV / f"{nombre}.wav", 1), (0, 200, 1e9))
        sal = "—" if ajuste is None else _n(m["lufs_m"] + ajuste + BUS_SFX)
        aj = "—" if ajuste is None else _n(ajuste, 0).replace("−", "−") if ajuste < 0 else f"+{ajuste:.0f}" if ajuste > 0 else "0"
        filas.append(f"| `{nombre}` | {_n(m['pico'])} | {_n(m['rms'])} | {_n(m['lufs_m'])} | {_n(m['lufs_m_200'])} | {aj} | {sal} | {cuando} |")
    filas += ["", "| Capa de ambiente | Pico (dBFS) | LUFS | LUFS-M máx | íd. > 200 Hz | Volumen de la capa | LUFS a la salida | Cuándo |",
              "| --- | --- | --- | --- | --- | --- | --- | --- |"]
    import _dsp_estereo as D
    for nombre, vol, cuando in MEZCLA_BUCLES:
        m = C.medir(C.leer(C.AUDIO_MP3 / f"{nombre}.mp3", 2), (0, 200, 1e9))
        filas.append(f"| `{nombre}` | {_n(m['pico'])} | {_n(m['lufs_i'])} | {_n(m['lufs_m'])} | {_n(m['lufs_m_200'])} | {vol:.2f} "
                     f"({_n(float(D.db(vol)))} dB) | {_n(m['lufs_i'] + float(D.db(vol)) + BUS_AMB)} | {cuando} |")
    return "\n".join(filas)


def main() -> int:
    ap = argparse.ArgumentParser(description="Genera y mide los candidatos de ajuste de audio.")
    ap.add_argument("--solo", default="", help="frentes separados por comas: " + ", ".join(FRENTES))
    ap.add_argument("--medir", action="store_true", help="no generar: solo medir lo que hay en disco")
    ap.add_argument("--espectros", type=Path, default=None, help="carpeta para los espectrogramas comparativos")
    ap.add_argument("--tablas", action="store_true", help="imprimir en Markdown las tablas de medidas.json y la de mezcla")
    a = ap.parse_args()
    if a.tablas:
        for nombre, grp in json.loads(MEDIDAS.read_text(encoding="utf-8")).items():
            print(f"\n<!-- {nombre} -->\n" + tabla_md(grp))
        print("\n<!-- mezcla -->\n" + tabla_mezcla())
        return 0
    previas = json.loads(MEDIDAS.read_text(encoding="utf-8")) if MEDIDAS.exists() else {}
    frentes = [s for s in a.solo.split(",") if s] or list(FRENTES)
    if set(frentes) - set(FRENTES):
        print("frentes desconocidos:", sorted(set(frentes) - set(FRENTES)))
        return 2
    for fr in frentes:
        t0 = time.time()
        if a.medir:
            grupos = {k: v for k, v in previas.items() if v.get("frente") == fr}
        else:
            grupos = globals()[f"frente_{fr}"]()
            for g in grupos.values():
                g["frente"] = fr
        grupos = medir(grupos)
        imprimir(grupos)
        previas.update(grupos)
        if a.espectros is not None:
            a.espectros.mkdir(parents=True, exist_ok=True)
            for nombre, grp in grupos.items():
                C.espectro_comparado([C.AQUI / f"{x}.mp3" for x in grp["archivos"]], a.espectros / f"{nombre}.png",
                                     canales=grp["canales"])
        print(f"  ({fr}: {time.time() - t0:.1f} s)")
    MEDIDAS.write_text(json.dumps(previas, ensure_ascii=False, indent=1) + "\n", encoding="utf-8")
    fallos = [n for grp in previas.values() for n, m in grp.get("medidas", {}).items()
              if m["pico"] > -1.0 or m["dc"] > 5e-4]
    if fallos:
        print("FALLO (recorte o continua):", fallos)
    return 1 if fallos else 0


if __name__ == "__main__":
    sys.exit(main())
