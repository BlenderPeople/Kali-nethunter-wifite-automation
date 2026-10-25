#!/system/bin/sh
# monitor_and_run.sh — меню + запуск auto_wifite.sh в Kali chroot
# Запуск: su -c "sh /data/local/tmp/monitor_and_run.sh"
# Восстанавливает Wi-Fi при любом выходе (trap EXIT).

CHROOT_PATH="/data/local/nhsystem/kali-arm64"

# ---------- Проверка chroot ----------
if [ ! -d "$CHROOT_PATH" ]; then
    echo "[!] chroot не найден: $CHROOT_PATH" >&2
    echo "[!] Проверьте путь (kali-arm64 / kali-armhf) и повторите." >&2
    exit 1
fi

if [ ! -f "$CHROOT_PATH/root/auto_wifite.sh" ]; then
    echo "[!] Не найден $CHROOT_PATH/root/auto_wifite.sh" >&2
    echo "[!] Скопируйте скрипт в chroot: cp auto_wifite.sh $CHROOT_PATH/root/" >&2
    exit 1
fi

# ---------- Восстановление Wi-Fi при выходе ----------
cleanup() {
    echo ""
    echo "[*] Восстанавливаю Wi-Fi..."
    unset LD_PRELOAD 2>/dev/null || true
    nexutil -m0 2>/dev/null || true
    svc wifi enable 2>/dev/null || true
    echo "[*] Готово."
}
trap cleanup EXIT

# ---------- Вспомогательные функции ----------
run_in_chroot() {
    # $1 — аргументы для auto_wifite.sh (строка)
    chroot "$CHROOT_PATH" /bin/bash -c "
        export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
        export LD_PRELOAD=/lib/libnexmonkali.so
        bash /root/auto_wifite.sh $1
    "
}

enable_monitor() {
    echo "[*] Отключаю Wi-Fi..."
    svc wifi disable
    sleep 3

    echo "[*] Поднимаю wlan0..."
    ifconfig wlan0 up
    sleep 1

    echo "[*] Активирую Nexmon (monitor mode)..."
    nexutil -k1
    nexutil -s0x613 -i -v2
    sleep 2

    echo "[*] Проверяю интерфейс:"
    ifconfig wlan0 | grep -E "UP|flags" || true
}

disable_monitor() {
    echo "[*] Возвращаю Wi-Fi в нормальный режим..."
    nexutil -m0 2>/dev/null || true
    svc wifi enable 2>/dev/null || true
    echo "[*] Готово."
}

# ---------- Главное меню ----------
while true; do
    echo ""
    echo "===== NetHunter Wi-Fi Audit ====="
    echo "  1) Полный цикл (мониторинг + Wifite + брутфорс)"
    echo "  2) Только брутфорс последнего .cap (с подтверждением)"
    echo "  3) Выбрать .cap интерактивно и брутить"
    echo "  4) Брутфорс конкретного файла"
    echo "  5) Атака по маске (8 цифр)"
    echo "  6) Список .cap"
    echo "  7) Установить зависимости"
    echo "  8) Включить мониторинг (без запуска скрипта)"
    echo "  9) Выключить мониторинг / вернуть Wi-Fi"
    echo "  0) Выход"
    printf "[?] Выбор: "
    read -r choice

    case "$choice" in
        1)
            enable_monitor
            run_in_chroot ""
            ;;
        2)
            run_in_chroot "-c"
            ;;
        3)
            run_in_chroot "-c -s"
            ;;
        4)
            printf "[?] Путь к .cap внутри chroot (например /root/hs/foo.cap): "
            read -r cap
            if [ -n "$cap" ]; then
                run_in_chroot "-c $cap"
            else
                echo "[!] Пустой путь, отмена."
            fi
            ;;
        5)
            run_in_chroot "-c -m"
            ;;
        6)
            run_in_chroot "-l"
            ;;
        7)
            run_in_chroot "-i"
            ;;
        8)
            enable_monitor
            ;;
        9)
            disable_monitor
            ;;
        0)
            exit 0
            ;;
        *)
            echo "[!] Неверный выбор"
            ;;
    esac
done
