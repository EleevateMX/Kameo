#!/usr/bin/env bash
# Respaldo completo de la base de datos de la beta (formato de pg_dump, restaurable).
#
#   DATABASE_URL=postgres://… scripts/beta-backup.sh            → backups/alux-AAAAMMDD-HHMM.dump
#   scripts/beta-backup.sh --restore backups/alux-….dump         restaura sobre DATABASE_URL
#
# Necesita pg_dump / pg_restore de la misma versión mayor que el servidor (16) y acceso a la
# base de datos: en Render, usa la URL *externa* y añade tu IP a la lista de acceso sólo
# mientras dure. Los respaldos quedan fuera de Git (carpeta backups/ ignorada).
set -euo pipefail
: "${DATABASE_URL:?Define DATABASE_URL con la cadena de conexión (URL externa en Render)}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

if [ "${1:-}" = "--restore" ]; then
  file="${2:?Indica el archivo .dump a restaurar}"
  echo "Vas a REEMPLAZAR los datos de la base de datos de destino con $file."
  read -r -p "Escribe RESTAURAR para continuar: " ok
  [ "$ok" = "RESTAURAR" ] || { echo "Cancelado."; exit 1; }
  pg_restore --clean --if-exists --no-owner --no-privileges --dbname "$DATABASE_URL" "$file"
  echo "Restaurado."
  exit 0
fi

mkdir -p "$ROOT/backups"
out="$ROOT/backups/alux-$(date -u +%Y%m%d-%H%M).dump"
pg_dump --format=custom --no-owner --no-privileges --dbname "$DATABASE_URL" --file "$out"
echo "Respaldo guardado en $out ($(du -h "$out" | cut -f1))"
pg_restore --list "$out" | grep -c "TABLE DATA" | xargs -I{} echo "Tablas con datos en el respaldo: {}"
