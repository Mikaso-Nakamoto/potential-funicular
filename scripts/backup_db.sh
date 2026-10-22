#!/usr/bin/env bash
# Резервная копия базы записей. Безопасна на работающем боте (sqlite3 .backup
# через Python, без блокировки записи).
#
#   ./scripts/backup_db.sh                     # копия в backups/
#   KEEP_DAYS=90 ./scripts/backup_db.sh        # хранить 90 дней
#
# В cron (каждый день в 21:30):
#   30 21 * * * cd /home/YOUR_USER/massage-bot && ./scripts/backup_db.sh >> backups/backup.log 2>&1
set -euo pipefail
cd "$(dirname "$0")/.."

DB="${DB_PATH:-data/massage.sqlite3}"
BACKUP_DIR="${BACKUP_DIR:-backups}"
KEEP_DAYS="${KEEP_DAYS:-60}"

if [ ! -f "$DB" ]; then
  echo "База не найдена: $DB" >&2
  exit 1
fi

mkdir -p "$BACKUP_DIR"
STAMP="$(date +%Y%m%d-%H%M%S)"
OUT="$BACKUP_DIR/massage-$STAMP.sqlite3"

python3 - "$DB" "$OUT" <<'PY'
import sqlite3, sys
src, dst = sys.argv[1], sys.argv[2]
with sqlite3.connect(src) as conn:
    backup = sqlite3.connect(dst)
    with backup:
        conn.backup(backup)
    backup.close()
PY

gzip -f "$OUT"
SIZE="$(du -h "$OUT.gz" | cut -f1)"
echo "$(date '+%F %T') копия: $OUT.gz ($SIZE)"

# удаляем старое
find "$BACKUP_DIR" -name 'massage-*.sqlite3.gz' -mtime "+$KEEP_DAYS" -print -delete || true
