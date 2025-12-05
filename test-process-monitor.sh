#!/bin/bash
set -uo pipefail

PROCESS_NAME="test"
API_URL="https://test.com/monitoring/test/api"
LOG_FILE="/var/log/monitoring.log"
PID_FILE="/var/run/test-monitor.pid"
LOCK_FILE="/var/run/test-monitor.lock"

log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') [$$] $*" >> "$LOG_FILE"
}

# Защита от двойного запуска
if ! (set -o noclobber; echo "$$" > "$LOCK_FILE") 2> /dev/null; then
    exit 1
fi
trap 'rm -f "$LOCK_FILE" 2>/dev/null' EXIT

# Создаём лог-файл, если его нет
sudo touch "$LOG_FILE" 2>/dev/null || true
sudo chmod 640 "$LOG_FILE" 2>/dev/null || true

if pgrep -x "$PROCESS_NAME" > /dev/null; then
    CURRENT_PID=$(pgrep -x -o "$PROCESS_NAME")

    # Первый запуск — запоминаем PID
    if [[ ! -f "$PID_FILE" ]]; then
        echo "$CURRENT_PID" > "$PID_FILE"
        log "Процесс $PROCESS_NAME обнаружен (PID $CURRENT_PID)"
    fi

    OLD_PID=$(cat "$PID_FILE" 2>/dev/null || echo 0)

    # Если PID изменился — процесс перезапускался!
    if [[ "$CURRENT_PID" -ne "$OLD_PID" ]]; then
        log "ПЕРЕЗАПУСК! Был PID $OLD_PID → стал PID $CURRENT_PID"
        echo "$CURRENT_PID" > "$PID_FILE"
    fi

    # Пробуем достучаться до сервера
    if curl -f -s --max-time 10 "$API_URL" > /dev/null 2>&1; then
        log "OK: сервер мониторинга ответил"
    else
        log "ОШИБКА: не удалось связаться с $API_URL"
    fi
else
    # Процесс не запущен — удаляем старый PID и молчим
    rm -f "$PID_FILE"
fi
