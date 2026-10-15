# WGDashboard + nginx

WGDashboard (AmneziaWG) за nginx с Let's Encrypt. Туннели работают в модуле ядра хоста,
контейнер только управляет ими. Проверено на Debian 12 и Debian 13 с модулем AmneziaWG 3.1.

## 1. Подготовка хоста

Модуль ядра ставится на хост: без него `awg-quick` в контейнере откатывается на медленный
`amneziawg-go` («Unknown device type»).

```bash
apt-get update && apt-get -y full-upgrade          # заголовки есть только для текущего ядра из репозитория
apt-get -y install linux-headers-amd64 dkms git curl ca-certificates iptables
reboot                                             # если обновилось ядро
```

Если `full-upgrade` падает на `grub-pc` с «/dev/vda does not exist» (шаблон хостера готовили
на другом диске), укажите настоящий диск и доделайте настройку — до перезагрузки:

```bash
ls -l /dev/disk/by-id/ | grep -v part              # найти диск, например scsi-0QEMU_QEMU_HARDDISK_drive-scsi0-0-0-0
echo "grub-pc grub-pc/install_devices multiselect /dev/disk/by-id/<диск>" | debconf-set-selections
dpkg --configure -a                                # ждём «grub-install success»
```

Модуль AmneziaWG из PPA Amnezia (ключ — `amnezia.gpg`, сборки focal собираются через DKMS
и на Debian):

```bash
cat > /etc/apt/sources.list.d/amnezia.sources <<EOF
Types: deb
URIs: https://ppa.launchpadcontent.net/amnezia/ppa/ubuntu
Suites: focal
Components: main
Signed-By: /usr/share/keyrings/amnezia.gpg
EOF
apt-get update && apt-get -y install amneziawg-dkms amneziawg-tools
modprobe amneziawg && modinfo amneziawg | grep ^version   # версия модуля = AWG_TOOLS_REF в .env
echo amneziawg > /etc/modules-load.d/amneziawg.conf
echo "net.ipv4.ip_forward = 1" > /etc/sysctl.d/99-awg-forward.conf && sysctl --system
```

Docker — из официального репозитория Docker (`docker-ce`, `docker-compose-plugin`).

## 2. Запуск

```bash
git clone https://github.com/iamletenkov/WGDashboard && cd WGDashboard
cp .env.example .env    # DOMAIN, CERTBOT_EMAIL, PASSWORD, PUBLIC_IP, WG_AUTOSTART
docker compose up -d --build
```

- DNS-запись `DOMAIN` должна указывать на сервер до запуска: certbot сразу запрашивает сертификат.
- Панель слушает только `127.0.0.1:5000`, снаружи — через nginx на 443.
- `WGD_VERSION` и `AWG_TOOLS_REF` — версии WGDashboard и утилит AmneziaWG. Образ собирается
  поверх официального `ghcr.io/wgdashboard/wgdashboard:${WGD_VERSION}` (`wgdashboard/Dockerfile`):
  - утилиты AmneziaWG собираются из исходников: в официальном образе лежит `awg` эпохи 2.0,
    и модуль 3.x отвечает на неё «Invalid argument». `AWG_TOOLS_REF` держите равным версии
    модуля на хосте;
  - панель собирается из исходников той же версии с патчами из `wgdashboard/patches/` и
    пересобранным веб-интерфейсом (см. раздел 4).
- Сборка веб-интерфейса требует около 1 ГБ свободной памяти. На хосте с 1 ГБ соберите образ
  на другой машине и перенесите: `docker save <образ> | gzip | ssh root@<хост> 'gunzip | docker load'`.
- `WG_AUTOSTART` — интерфейсы через `||` (`awg0||awg1`), которые поднимаются при каждом старте контейнера; без него
  после перезапуска контейнера туннель остаётся выключенным.
- `PUBLIC_IP` — адрес для конфигов клиентов; без него контейнер спрашивает ifconfig.me и
  может записать адрес чужого выхода.

## 3. Интерфейс AmneziaWG

Создать интерфейс, например `awg0`, и прописать в нём:

```
MTU = 1280

PostUp = iptables -A FORWARD -i awg0 -j ACCEPT; iptables -A FORWARD -o awg0 -j ACCEPT; iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE; iptables -t mangle -A FORWARD -o awg0 -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --clamp-mss-to-pmtu; iptables -t mangle -A FORWARD -i awg0 -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --clamp-mss-to-pmtu

PostDown = iptables -D FORWARD -i awg0 -j ACCEPT; iptables -D FORWARD -o awg0 -j ACCEPT; iptables -t nat -D POSTROUTING -o eth0 -j MASQUERADE; iptables -t mangle -D FORWARD -o awg0 -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --clamp-mss-to-pmtu; iptables -t mangle -D FORWARD -i awg0 -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --clamp-mss-to-pmtu
```

- `eth0` — внешний интерфейс хоста (`ip route get 1.1.1.1`, после `dev`).
- MTU 1280 подходит и для мобильных клиентов, и для туннеля внутри другого туннеля; ниже 1280
  не ставить — пропадает IPv6 на интерфейсе, и `awg-quick` падает на IPv6-маршрутах пиров.
- В `Peers Settings` задать тот же MTU для новых клиентов.
- Править конфиг при `SaveConfig = true` — только через панель или при остановленном интерфейсе.

## 4. AmneziaWG 3.x в панели

Патчи в `wgdashboard/patches/` добавляют в панель параметры AmneziaWG 3.x:
`HeaderProtectionKey`, `ContentPaddingAddition`, `RandomTrailers`, `DisableCookies`,
`RekeyAfterTime`, `RekeyTimeout`, `RejectAfterTime`, `KeepaliveTimeout`, `MaxHandshakeAttempts`.

- `0001` — изменения из [WGDashboard PR #1360](https://github.com/WGDashboard/WGDashboard/pull/1360)
  (закрыт без слияния): поля в формах создания и правки конфигурации, сохранение в файл,
  выдача в скачиваемых конфигах и QR-кодах клиентов.
- `0002` — незаданный параметр (`0` или пусто) не пишется ни в файл сервера, ни в конфиг
  клиента. Без этого конфигурации AmneziaWG 1.0/2.0 ломаются: `awg` отвергает
  `HeaderProtectionKey = 0`, интерфейс не поднимается после «Save», клиенты без поддержки 3.x
  не импортируют конфиг. Новая конфигурация по умолчанию — с `DisableCookies = off`
  (защита от потока handshake включена).

Как пользоваться:
- **Новая конфигурация AWG 3.x:** форма уже заполняет `HeaderProtectionKey` случайным ключом и
  делает `S1`–`S4` одинаковыми и не меньше 12 — без этого модуль ядра отвергает защиту заголовков.
  Клиенту нужен AmneziaWG 3.x (KeeneticOS 5.2 Alpha 11+, свежие приложения AmneziaVPN/AmneziaWG).
- **Конфигурация AWG 1.0/2.0:** `HeaderProtectionKey` оставить `0`, остальные новые поля — `0`;
  в файл они не попадут, клиенты работают как раньше.
- После правки настроек проверить: `awg show <интерфейс> | grep -E "header protection|content padding"`.

При обновлении WGDashboard (`WGD_VERSION`) сборка проверяет, что патчи накладываются
(`git apply`): если нет — сборка падает, патчи нужно перенести на новую версию.

Проверка патчей (2026-10-15, v4.3.3): во временном контейнере созданы конфигурации AWG 3.1 и
AWG 2.0 через API, добавлены пиры, сохранены настройки, скачаны конфиги; клиент из скачанного
конфига AWG 3.1 проходит handshake. На коде только с `0001` конфигурация AWG 2.0 не поднимается.

## 5. Обновление работающего сервера

```bash
cd WGDashboard && git pull
docker compose up -d --build wgdashboard
```

Туннели при перезапуске контейнера не падают: интерфейсы живут в ядре хоста
(`network_mode: host`), панель только управляет ими. `autoheal` перезапускает контейнер, если
панель перестала отвечать по HTTP (у официального образа healthcheck проверяет лишь, что
процессы запущены, и зависшую панель не замечает).
