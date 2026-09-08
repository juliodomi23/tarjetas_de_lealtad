#!/bin/sh
# Respaldo diario de la SQLite. El servicio corre en EasyPanel como tipo "App"
# (Nixpacks, no Compose) — no hay sqlite3 CLI en el host ni el archivo expuesto
# fuera del contenedor, asi que el respaldo se saca con VACUUM INTO desde
# dentro del contenedor (better-sqlite3 ya esta instalado ahi) y se copia al
# host con docker cp. Instalado en el VPS como /root/lealtad-backup.sh, cron:
#   0 4 * * * /root/lealtad-backup.sh >> /var/log/lealtad-backup.log 2>&1
set -eu

DEST="${BACKUP_DIR:-/root/backups/lealtad}"
KEEP_DAYS=30

CID=$(docker ps --filter name=lealtad -q | head -1)
[ -z "$CID" ] && { echo "contenedor lealtad no encontrado"; exit 1; }

mkdir -p "$DEST"
STAMP=$(date +%Y-%m-%d_%H%M)
docker exec "$CID" node -e "require('better-sqlite3')('/data/loyalty.db').exec(\"VACUUM INTO '/data/backup-tmp.db'\")"
docker cp "$CID":/data/backup-tmp.db "$DEST/loyalty-$STAMP.db"
docker exec "$CID" rm -f /data/backup-tmp.db
# borra respaldos de más de KEEP_DAYS días
find "$DEST" -name 'loyalty-*.db' -mtime +$KEEP_DAYS -delete
echo "$(date -Iseconds) respaldo OK → $DEST/loyalty-$STAMP.db"
