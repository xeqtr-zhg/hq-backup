#!/bin/bash

set -euo pipefail

# ===== МЕНЯЕТЕ ТОЛЬКО ЭТИ 9 СТРОК (пароли не должны содержать символ ' ) =====
# =============================================================================
DB_HOST="localhost"                # адрес базы данных (обычно localhost)
DB_NAME='mysite_db'                # имя базы данных (оставьте пустым '', если базы нет)
DB_USER='mysite_user'              # пользователь базы данных
DB_PASS='пароль_базы'              # пароль базы данных
# =============================================================================
FTP_HOST="ftp.example.com"         # адрес FTP-сервера, куда кладём копии
FTP_USER='ftp_login'               # логин FTP
FTP_PASS='ftp_пароль'              # пароль FTP
FTP_DIR="backups/mysite"           # папка на FTP (создастся сама), только под бэкапы
# =============================================================================
KEEP_COPIES=7                      # сколько копий хранить (старые перезаписываются по кругу)
# =============================================================================
# =============================================================================

SCRIPT_PATH="$(cd "$(dirname "$0")" && pwd)/$(basename "$0")"
SITE_DIR="$(dirname "$SCRIPT_PATH")"

N=$(( $(date +%s) / 86400 % KEEP_COPIES + 1 ))
FTP_BASE="ftp://$FTP_HOST/$FTP_DIR"
DB_FAILED=0

if [ -n "$DB_NAME" ]; then
  set +e
  MYSQL_PWD="$DB_PASS" mysqldump -h"$DB_HOST" -u"$DB_USER" --single-transaction --quick --no-tablespaces "$DB_NAME" \
    | gzip \
    | curl -sS --fail --ftp-create-dirs -u "$FTP_USER:$FTP_PASS" -T - "$FTP_BASE/db_$N.sql.gz"
  DB_RC=("${PIPESTATUS[@]}")
  set -e
  if [[ "${DB_RC[*]}" =~ [1-9] ]]; then
    echo "$(date '+%F %T') ОШИБКА: не удалось сделать копию базы (mysqldump: ${DB_RC[0]}, gzip: ${DB_RC[1]}, curl: ${DB_RC[2]}). Файлы сайта всё равно будут отправлены." >&2
    curl -sS -u "$FTP_USER:$FTP_PASS" -Q "-DELE $FTP_DIR/db_$N.sql.gz" "$FTP_BASE/" > /dev/null 2>&1 || true
    DB_FAILED=1
  fi
fi

set +e
tar -czf - -C "$SITE_DIR" --exclude="./$(basename "$SCRIPT_PATH")" . \
  | curl -sS --fail --ftp-create-dirs -u "$FTP_USER:$FTP_PASS" -T - "$FTP_BASE/files_$N.tar.gz"
RC=("${PIPESTATUS[@]}")
set -e
if [ "${RC[0]}" -gt 1 ] || [ "${RC[1]}" -ne 0 ]; then
  echo "$(date '+%F %T') ОШИБКА при отправке файлов сайта (tar: ${RC[0]}, curl: ${RC[1]})" >&2
  exit 1
fi

if [ "$DB_FAILED" -ne 0 ]; then
  echo "$(date '+%F %T') файлы сайта отправлены, но копия базы НЕ сделана (копия $N из $KEEP_COPIES)" >&2
  exit 1
fi

if [ -z "$DB_NAME" ]; then
  echo "$(date '+%F %T') бэкап файлов выполнен, база не копировалась (копия $N из $KEEP_COPIES)"
else
  echo "$(date '+%F %T') бэкап выполнен (копия $N из $KEEP_COPIES)"
fi