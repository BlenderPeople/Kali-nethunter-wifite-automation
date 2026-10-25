# Kali-nethunter-wifite-automation

Автоматизация полного цикла аудита Wi-Fi на Kali NetHunter: захват рукопожатия через Wifite, конвертация в формат hashcat и брутфорс — с возвратом Wi-Fi адаптера в нормальный режим.

## Что делают скрипты

Два скрипта работают в связке:

| Скрипт | Где запускается | Назначение |
|---|---|---|
| `monitor_and_run.sh` | Android shell (root) | Отключает Wi-Fi, поднимает `wlan0`, активирует Nexmon monitor mode, запускает Kali chroot |
| `auto_wifite.sh` | Внутри Kali chroot | Запускает Wifite, проверяет рукопожатие, конвертирует `.cap` → `.hc22000`, запускает hashcat |

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
