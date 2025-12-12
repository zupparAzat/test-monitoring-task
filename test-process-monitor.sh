#!/bin/bash

# =============================================================================
# Мониторинг процесса test и отчёт на внешний сервер мониторинга

set -uo pipefail

PROCESS_NAME="test"
API_URL="https://test.com/monitoring/test/api"
LOG_FILE="/var/log/monitoring.log"
PID_FILE="/var/run/test-monitor.pid"
LOCK_FILE="/var/run/test-monitor.lock"

# Функция логирования с датой
log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') [$$] $*" >> "$LOG_FILE"
}

# Защита от параллельных запусков
if ! (set -o noclobber; echo "$$" > "$LOCK_FILE") 2>/dev/null; then
    log "ERROR: Скрипт уже запущен (PID $(cat $LOCK_FILE)). Выходим."
    exit 1
fi
trap 'rm -f "$LOCK_FILE"; exit' INT TERM EXIT

# Проверяем, запущен ли процесс test
if pgrep -x "$PROCESS_NAME" > /dev/null; then
    CURRENT_PID=$(pgrep -x -o "$PROCESS_NAME")  # самый старый (основной) процесс

    # Сохраняем PID при первом запуске скрипта или если файл потерялся
    if [[ ! -f "$PID_FILE" ]]; then
        echo "$CURRENT_PID" > "$PID_FILE"
        log "Процесс $PROCESS_NAME обнаружен впервые (PID $CURRENT_PID)"
    fi

    OLD_PID=$(cat "$PID_FILE" 2>/dev/null || echo 0)

    # Если PID изменился — процесс был перезапущен
    if [[ "$CURRENT_PID" -ne "$OLD_PID" ]]; then
        log "ВНИМАНИЕ: Процесс $PROCESS_NAME был перезапущен! Старый PID: $OLD_PID → Новый PID: $CURRENT_PID"
        echo "$CURRENT_PID" > "$PID_FILE"
    fi

    # Делаем HTTPS-запрос (используем timeout 10 сек)
    if curl -f -s -m 10 --connect-timeout 5 "$API_URL" > /dev/null 2>&1; then
        # Всё ок, можно писать в лог раз в сутки, чтобы не спамить
        [[ "$(date +%H%M)" == "0000" ]] && log "OK: Процесс $PROCESS_NAME работает, сервер мониторинга доступен"
    else
        log "ERROR: Не удалось достучаться до $API_URL (процесс $PROCESS_NAME работает)"
    fi
else
    # Процесс не запущен — ничего не делаем, но можно оставить тихий лог для отладки
    [[ -f "$PID_FILE" ]] && rm -f "$PID_FILE"
    # log "Процесс $PROCESS_NAME не запущен — пропускаем проверку"   # закомментировано по ТЗ
    exit 0
fi

exit 0
