#!/bin/sh
# Respaldo diario de la SQLite. Cron sugerido (crontab -e en el VPS):
#   0 4 * * * /ruta/al/repo/backup.sh >> /var/log/lealtad-backup.log 2>&1
set -eu

DB="${DB_FILE:-/root/tarjetas-lealtad/loyalty.db}"
DEST="${BACKUP_DIR:-/root/backups/lealtad}"
KEEP_DAYS=30

mkdir -p "$DEST"
STAMP=$(date +%Y-%m-%d)
sqlite3 "$DB" ".backup '$DEST/loyalty-$STAMP.db'"
# borra respaldos de más de KEEP_DAYS días
find "$DEST" -name 'loyalty-*.db' -mtime +$KEEP_DAYS -delete
echo "$(date -Iseconds) respaldo OK → $DEST/loyalty-$STAMP.db"
