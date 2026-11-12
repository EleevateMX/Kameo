#!/usr/bin/env python3
"""Manifiesto de assets de audio: procedencia y licencia de cada archivo que suena en ALUX.

Une los manifiestos que escriben los generadores (efectos, ambientes y cinemáticas, música),
comprueba que cada archivo declarado existe y que no hay audio en el juego sin declarar, y
escribe docs/ASSETS_AUDIO.md.

    python3 art/audio/manifiesto.py            # escribe docs/ASSETS_AUDIO.md
    python3 art/audio/manifiesto.py --check    # sólo comprueba (código ≠ 0 si algo no cuadra)
"""
from __future__ import annotations

import json
import sys
from pathlib import Path

RAIZ = Path(__file__).resolve().parents[2]
PARTES = ["manifiesto_efectos.json", "manifiesto_musica.json", "manifiesto_ambiente_cine.json"]
CARPETAS = [("game/assets/audio", ".wav"), ("game/web/static/audio", ".mp3")]
SALIDA = RAIZ / "docs" / "ASSETS_AUDIO.md"
# Lo que sigue en el repositorio pero no viaja en la versión web (lo sustituyen los MP3 del mezclador)
EXCLUIDO_WEB = ("game/assets/audio/mus_", "game/assets/audio/amb_")


def cargar() -> list[dict]:
    todo: list[dict] = []
    for nombre in PARTES:
        ruta = Path(__file__).with_name(nombre)
        if ruta.exists():
            todo += json.loads(ruta.read_text(encoding="utf-8"))
    return todo


def comprobar(todo: list[dict]) -> list[str]:
    fallos = []
    declarados = {e["archivo"] for e in todo}
    for e in todo:
        ruta = RAIZ / e["archivo"]
        if not ruta.exists():
            fallos.append(f"declarado pero no existe: {e['archivo']}")
        elif ruta.stat().st_size != e["bytes"]:
            fallos.append(f"tamaño distinto del declarado: {e['archivo']} ({ruta.stat().st_size} ≠ {e['bytes']})")
        if "original del proyecto" not in e.get("licencia", ""):
            fallos.append(f"licencia sin revisar: {e['archivo']} → {e.get('licencia')!r}")
    for carpeta, ext in CARPETAS:
        for ruta in sorted((RAIZ / carpeta).glob("*" + ext)):
            rel = ruta.relative_to(RAIZ).as_posix()
            if rel not in declarados:
                fallos.append(f"audio sin declarar en ningún manifiesto: {rel}")
    return fallos


def tabla(filas: list[dict]) -> str:
    out = ["| Archivo | Bus | Duración | Tamaño | Origen |", "| --- | --- | --- | --- | --- |"]
    for e in sorted(filas, key=lambda e: e["id"]):
        origen = e["origen"].replace("síntesis propia: ", "")
        out.append(f"| `{Path(e['archivo']).name}` | {e['bus']} | {e['duracion_s']:.2f} s | {e['bytes'] / 1024:.0f} KB | {origen} |")
    return "\n".join(out)


def escribir(todo: list[dict]) -> None:
    web = [e for e in todo if not e["archivo"].startswith(EXCLUIDO_WEB)]
    grupos = [
        ("Música", [e for e in web if e["tipo"] == "música"]),
        ("Ambientes", [e for e in web if e["tipo"] == "ambiente"]),
        ("Bandas sonoras de las cinemáticas", [e for e in web if e["tipo"] == "cinemática"]),
        ("Efectos e interfaz (dentro de la descarga del juego)", [e for e in web if e["archivo"].startswith("game/assets/audio/")]),
    ]
    provisionales = [e for e in todo if e["archivo"].startswith(EXCLUIDO_WEB)]
    total = sum(e["bytes"] for e in web)
    lineas = [
        "# Assets de audio: procedencia y licencias",
        "",
        "Generado por `python3 art/audio/manifiesto.py` a partir de los manifiestos de los generadores",
        "(`art/audio/manifiesto_*.json`). No editar a mano.",
        "",
        "## Resumen",
        "",
        f"- **{len(web)} archivos** de audio viajan con el juego ({total / 1e6:.1f} MB en disco), todos **síntesis propia**:",
        "  salen de los scripts de `art/audio/` (numpy: osciladores, ruido filtrado, envolventes,",
        "  reverberación), con semillas fijas. No hay grabaciones, muestras ni bibliotecas de terceros.",
        "- **Licencia:** original del proyecto ALUX. No hay atribuciones que cumplir ni licencias que renovar.",
        "- **Motion Array: no se usa nada.** Su licencia estándar excluye expresamente apps, software y",
        "  videojuegos (haría falta su plan Business, que se contrata aparte). Si algún día se quiere usar",
        "  material suyo, antes hay que tener esa licencia por escrito y anotar aquí cada archivo con ella.",
        "  Lo mismo para cualquier otra biblioteca: sin licencia que permita distribuirlo dentro de un",
        "  videojuego, no entra.",
        "- **Nadie ha escuchado todavía estos archivos.** Se han comprobado con mediciones (niveles,",
        "  espectro, costuras de bucle, tiempos), no de oído: ver [AUDIO.md](AUDIO.md).",
        "- Cualquier audio nuevo tiene que declararse en su manifiesto: `manifiesto.py --check` falla si",
        "  hay un archivo sin declarar o con una licencia que no sea la del proyecto.",
        "",
    ]
    for titulo, filas in grupos:
        if not filas:
            continue
        lineas += [f"## {titulo}", "", f"{len(filas)} archivos, {sum(e['bytes'] for e in filas) / 1e6:.2f} MB.", "", tabla(filas), ""]
    if provisionales:
        lineas += [
            "## Bucles provisionales que ya no viajan en la versión web",
            "",
            f"{len(provisionales)} archivos de la primera capa (mono, 22 kHz). Siguen en `game/assets/audio/` para",
            "ejecutar el juego fuera del navegador, pero la exportación web los excluye: los sustituyen la música",
            "y los ambientes de arriba.",
            "",
            tabla(provisionales),
            "",
        ]
    SALIDA.write_text("\n".join(lineas), encoding="utf-8")


def main() -> int:
    todo = cargar()
    fallos = comprobar(todo)
    for f in fallos:
        print("✗", f)
    if "--check" not in sys.argv:
        escribir(todo)
        print(f"{SALIDA.relative_to(RAIZ)} escrito: {len(todo)} archivos declarados")
    print("Manifiesto correcto." if not fallos else f"{len(fallos)} problema(s).")
    return 1 if fallos else 0


if __name__ == "__main__":
    sys.exit(main())
