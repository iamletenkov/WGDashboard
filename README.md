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
- `WGD_VERSION` и `AWG_TOOLS_REF` — версии образа WGDashboard и утилит AmneziaWG. Утилиты
  собираются из исходников при сборке (`wgdashboard/Dockerfile`): в образе WGDashboard лежит
  `awg` эпохи 2.0, и модуль 3.x отвечает на неё «Invalid argument». Тег `AWG_TOOLS_REF`
  держите равным версии модуля на хосте.
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
