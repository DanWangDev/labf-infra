#!/usr/bin/env bash
# Nightly backup for the shared labf-db PostgreSQL instance.
#
# Dumps every database in labf-db to ./backups/<db>-<timestamp>.dump
# (custom-format pg_dump — restorable with pg_restore) and prunes backups
# older than BACKUP_RETENTION_DAYS (default 14).
#
# Usage:
#   ./backup.sh
#
# Schedule it daily from the host (Synology Task Scheduler or crontab):
#   30 2 * * * cd /volume1/docker/labf-infra && ./backup.sh >> backups.log 2>&1
#
# COPY THE BACKUPS OFF-SITE. Local backups do not survive a NAS failure.
# (e.g. Synology Hyper Backup, rclone to cloud storage, or Cloudflare R2.)

set -euo pipefail

DB_PASSWORD="${DB_PASSWORD:?DB_PASSWORD must be set}"
RETENTION_DAYS="${BACKUP_RETENTION_DAYS:-14}"
BACKUP_DIR="$(cd "$(dirname "$0")" && pwd)/backups"

mkdir -p "$BACKUP_DIR"

echo "backup: dumping databases from labf-db..."
DATABASES=$(docker exec labf-db psql -U hub -d postgres -tAc \
  "SELECT datname FROM pg_database WHERE datistemplate = false AND datname <> 'postgres'")

if [ -z "$DATABASES" ]; then
  echo "backup: no databases found, nothing to do."
  exit 0
fi

for DB in $DATABASES; do
  TIMESTAMP=$(date +%Y%m%d-%H%M%S)
  TARGET="$BACKUP_DIR/${DB}-${TIMESTAMP}.dump"
  echo "backup: dumping '$DB' -> $TARGET"
  docker exec labf-db pg_dump -U hub -Fc "$DB" > "$TARGET"
done

echo "backup: pruning backups older than ${RETENTION_DAYS} days..."
find "$BACKUP_DIR" -name '*.dump' -mtime "+${RETENTION_DAYS}" -delete

echo "backup: done. Files:"
ls -lh "$BACKUP_DIR" | tail -n +2
