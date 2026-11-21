#!/bin/bash
# AmneziaWG (gizlenmis WireGuard) - telefon icin, UDP 443 uzerinden. Proxy kurallari 10.8.0.0/15 (wg0 + awg0) icin.
set -e
apt-get install -y golang-go git make gcc qrencode >/dev/null
cd /opt
[ -x /usr/local/bin/amneziawg-go ] || { rm -rf awg; git clone -q https://github.com/amnezia-vpn/amneziawg-go awg; cd awg; make >/dev/null; install -m755 amneziawg-go /usr/local/bin/; cd /opt; }
command -v awg-quick >/dev/null || { rm -rf awgt; git clone -q https://github.com/amnezia-vpn/amneziawg-tools awgt; cd awgt/src; make >/dev/null; make install WITH_WGQUICK=yes WITH_SYSTEMDUNITS=yes >/dev/null; cd /opt; }
D=/etc/amnezia/amneziawg; mkdir -p $D; cd $D; umask 077
if [ ! -f awg0.conf ]; then
  awg genkey > s.key; awg pubkey < s.key > s.pub; awg genkey > c.key; awg pubkey < c.key > c.pub
  O="Jc = 4
Jmin = 40
Jmax = 70
S1 = 52
S2 = 71
H1 = 1834957212
H2 = 529183844
H3 = 2058129551
H4 = 991208821"
  cat > awg0.conf <<X
[Interface]
Address = 10.9.0.1/24
ListenPort = 51821
PrivateKey = $(cat s.key)
$O
PostUp = iptables -t nat -A POSTROUTING -s 10.9.0.0/24 -o eth0 -j MASQUERADE
PostDown = iptables -t nat -D POSTROUTING -s 10.9.0.0/24 -o eth0 -j MASQUERADE

[Peer]
PublicKey = $(cat c.pub)
AllowedIPs = 10.9.0.2/32
X
  cat > /root/telefon.conf <<X
[Interface]
PrivateKey = $(cat c.key)
Address = 10.9.0.2/32
DNS = 1.1.1.1
MTU = 1280
$O

[Peer]
PublicKey = $(cat s.pub)
Endpoint = 62.83.118.72:443
AllowedIPs = 0.0.0.0/0
PersistentKeepalive = 25
X
fi
mkdir -p /etc/systemd/system/awg-quick@awg0.service.d
printf '[Service]\nEnvironment=WG_QUICK_USERSPACE_IMPLEMENTATION=amneziawg-go\n' > /etc/systemd/system/awg-quick@awg0.service.d/u.conf
# UDP 443 artik AmneziaWG'ye
iptables -t nat -D PREROUTING -i eth0 -p udp --dport 443 -j REDIRECT --to-ports 51820 2>/dev/null || true
sed -i 's/--to-ports 51820/--to-ports 51821/' /usr/local/sbin/t2s-up.sh
# proxy kurallari: kaynak 10.8.0.0/15 (wg0 + awg0)
iptables -t mangle -D PREROUTING -i wg0 -p tcp -m multiport --dports 443 ! -d 10.8.0.0/24 -j MARK --set-mark 0x64 2>/dev/null || true
iptables -D FORWARD -i wg0 -p udp --dport 443 -j REJECT 2>/dev/null || true
iptables -D FORWARD -i wg0 -o tun0 -j ACCEPT 2>/dev/null || true
iptables -D FORWARD -i tun0 -o wg0 -j ACCEPT 2>/dev/null || true
sed -i 's/-i wg0 -p tcp -m multiport --dports 443 ! -d 10.8.0.0\/24/-s 10.8.0.0\/15 -p tcp -m multiport --dports 443 ! -d 10.8.0.0\/15/g; s/"-i wg0 -o tun0 -j ACCEPT" "-i tun0 -o wg0 -j ACCEPT" "-i wg0 -p udp --dport 443 -j REJECT"/"-s 10.8.0.0\/15 -o tun0 -j ACCEPT" "-i tun0 -d 10.8.0.0\/15 -j ACCEPT" "-s 10.8.0.0\/15 -p udp --dport 443 -j REJECT"/' /usr/local/sbin/t2s-up.sh /usr/local/sbin/t2s-down.sh
systemctl daemon-reload
systemctl enable --now awg-quick@awg0
systemctl restart t2s
sleep 3
echo "--- durum:"; systemctl is-active awg-quick@awg0 t2s
iptables -t mangle -S PREROUTING; iptables -t nat -S PREROUTING
echo "--- telefon QR:"
qrencode -t ansiutf8 -m 1 < /root/telefon.conf
