# WGDashboard + nginx 

1. Создать Amnesia интерфейс, например, с именем `awg0`.

2. При создании\после создания прописать в интерфейсе:

```
PostUp = iptables -A FORWARD -i awg0 -j ACCEPT; iptables -A FORWARD -o awg0 -j ACCEPT; iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE;

PostDown = iptables -D FORWARD -i awg0 -j ACCEPT; iptables -D FORWARD -o awg0 -j ACCEPT; iptables -t nat -D POSTROUTING -o eth0 -j MASQUERADE;
```
