# Kali-nethunter-wifite-automation

Автоматизация полного цикла аудита Wi-Fi на Kali NetHunter: захват рукопожатия через Wifite, конвертация в формат hashcat и брутфорс — с возвратом Wi-Fi адаптера в нормальный режим.

## Что делают скрипты

Два скрипта работают в связке:

| Скрипт | Где запускается | Назначение |
|---|---|---|
| `monitor_and_run.sh` | Android shell (root) | Меню, отключение Wi-Fi, подъём `wlan0`, активация Nexmon monitor mode, запуск Kali chroot |
| `auto_wifite.sh` | Внутри Kali chroot | Wifite, проверка рукопожатия, конвертация `.cap` → `.hc22000`, hashcat |

`monitor_and_run.sh` — это точка входа: он показывает меню и вызывает `auto_wifite.sh` с нужными аргументами внутри chroot. `auto_wifite.sh` можно запускать и напрямую из chroot — например, для брутфорса без повторного включения мониторинга.

Ключевая особенность: **оба скрипта используют `trap cleanup EXIT`**, поэтому Wi-Fi возвращается в нормальный режим даже при ошибке, Ctrl+C или падении chroot.

## Требования

### Аппаратные

- Root-доступ на Android-устройстве
- Wi-Fi чип Broadcom/Cypress с поддержкой Nexmon (список совместимых устройств — в документации NetHunter)
- Kali NetHunter chroot (стандартная установка через NetHunter app)

### Программные (внутри chroot)

Устанавливаются одной командой:

```bash
bash /root/auto_wifite.sh -i
```

Или вручную:

```bash
apt update && apt install -y wifite hcxtools hashcat aircrack-ng
```

**Пояснение по пакетам:**

- **`wifite`** — автоматизированный аудит Wi-Fi. Зависит от `aircrack-ng`, `tshark`, `reaver` и других утилит.
- **`hcxtools`** — содержит `hcxpcapngtool`, который конвертирует `.cap`/`.pcap` в формат hashcat `-m 22000` (PMKID + EAPOL).
- **`hashcat`** — офлайн-брутфорс. В chroot на Android обычно работает CPU-режим; GPU-ускорение зависит от драйверов устройства.
- **`aircrack-ng`** — используется для проверки валидности рукопожатия перед конвертацией.

### Опционально

- Словарь: по умолчанию `/usr/share/wordlists/wifi-wordlist.txt`, при отсутствии скрипт ищет `rockyou.txt` или `wordlist-probable.txt`. Можно указать свой через `-w`.

## Установка

1. Скопируйте `auto_wifite.sh` в `/root/` внутри Kali chroot:
   ```bash
   cp auto_wifite.sh /data/local/nhsystem/kali-arm64/root/
   ```

2. Скопируйте `monitor_and_run.sh` в Android-хранилище:
   ```bash
   cp monitor_and_run.sh /data/local/tmp/
   ```

3. Дайте права на выполнение (в Android shell):
   ```bash
   chmod +x /data/local/tmp/monitor_and_run.sh
   ```

4. Установите зависимости внутри chroot:
   ```bash
   chroot /data/local/nhsystem/kali-arm64 /bin/bash -c "bash /root/auto_wifite.sh -i"
   ```

## Использование

### Интерактивное меню (рекомендуется)

```bash
su -c "sh /data/local/tmp/monitor_and_run.sh"
```

Появляется меню:

```
===== NetHunter Wi-Fi Audit =====
  1) Полный цикл (мониторинг + Wifite + брутфорс)
  2) Только брутфорс последнего .cap (с подтверждением)
  3) Выбрать .cap интерактивно и брутить
  4) Брутфорс конкретного файла
  5) Атака по маске (8 цифр)
  6) Список .cap
  7) Установить зависимости
  8) Включить мониторинг (без запуска скрипта)
  9) Выключить мониторинг / вернуть Wi-Fi
  0) Выход
```

Пункт **1** — полный цикл: скрипт отключит Wi-Fi, включит мониторинг, запустит Wifite. После захвата нажмите **Ctrl+C** — Wifite завершится, и `auto_wifite.sh` продолжит автоматически: проверит рукопожатие, конвертирует и запустит hashcat.

**Важно:** пункт 1 **не выключает мониторинг** после завершения `auto_wifite.sh`. Wi-Fi остаётся в monitor mode, чтобы можно было сразу выбрать пункты 2–5 без повторного включения. Вернуть Wi-Fi можно пунктом 9 или при выходе из меню (пункт 0) — сработает `trap cleanup EXIT`.

### Прямой запуск `auto_wifite.sh` (внутри chroot)

Если мониторинг уже включён (например, пунктом 8 меню), можно запускать брутфорс напрямую:

```bash
# Самый свежий .cap, с подтверждением
bash /root/auto_wifite.sh -c

# Интерактивный выбор .cap из списка
bash /root/auto_wifite.sh -c -s

# Конкретный файл
bash /root/auto_wifite.sh -c /root/hs/my-target.cap

# Атака по маске (8 цифр)
bash /root/auto_wifite.sh -c -m

# Другой словарь
bash /root/auto_wifite.sh -c -w /path/to/wordlist.txt

# Список .cap
bash /root/auto_wifite.sh -l

# Подробный отладочный вывод
bash /root/auto_wifite.sh -c -v
```

### Полный цикл без меню (одной командой)

```bash
su -c "sh /data/local/tmp/monitor_and_run.sh"   # затем пункт 1
```

Или, если нужен неинтерактивный запуск, меню можно обойти, вызвав `auto_wifite.sh` внутри chroot после ручного включения мониторинга:

```bash
# В Android shell:
su -c "svc wifi disable; ifconfig wlan0 up; nexutil -k1; nexutil -s0x613 -i -v2"

# В chroot:
chroot /data/local/nhsystem/kali-arm64 /bin/bash -c \
  "export LD_PRELOAD=/lib/libnexmonkali.so; bash /root/auto_wifite.sh"
```

## Важное поведение

- **Полный цикл брутит только `.cap` этой сессии.** Если захват не удался, скрипт выходит с сообщением, не трогая старые файлы. Используйте `-c -s` для ручного выбора.
- **Восстановление Wi-Fi гарантировано** через `trap cleanup EXIT` в обоих скриптах. Даже если chroot упадёт или hashcat будет прерван, `nexutil -m0` и `svc wifi enable` выполнятся.
- **`LD_PRELOAD` снимается** в cleanup, чтобы не влиять на последующие команды в Android shell.
- **Меню не сбрасывает мониторинг** после каждого действия — это сделано намеренно, чтобы можно было выполнить несколько операций подряд. Возврат Wi-Fi — пункт 9 или выход.
