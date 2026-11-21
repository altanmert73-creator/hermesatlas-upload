#!/bin/bash
# wg0 istemcilerinin TCP trafigini Oxylabs ISP proxy (Deutsche Telekom) uzerinden cikarir.
set -e
P=http://disp.oxylabs.io:8001
apt-get install -y unzip curl iptables >/dev/null
cd /tmp
curl -sL -o t.zip https://github.com/xjasonlyu/tun2socks/releases/latest/download/tun2socks-linux-arm64.zip
unzip -oq t.zip
install -m755 tun2socks-linux-arm64 /usr/local/bin/tun2socks

cat > /usr/local/sbin/t2s-up.sh <<'X'
#!/bin/bash
for i in $(seq 40); do ip link show tun0 >/dev/null 2>&1 && break; sleep 0.5; done
ip addr add 198.18.0.1/15 dev tun0 2>/dev/null || true
ip link set tun0 up
sysctl -qw net.ipv4.conf.all.rp_filter=0 net.ipv4.conf.tun0.rp_filter=0
ip route replace default dev tun0 table 100
ip rule add fwmark 0x64 lookup 100 priority 100 2>/dev/null || true
M="-i wg0 -p tcp ! -d 10.8.0.0/24 -j MARK --set-mark 0x64"
iptables -t mangle -C PREROUTING $M 2>/dev/null || iptables -t mangle -A PREROUTING $M
for R in "-i wg0 -o tun0 -j ACCEPT" "-i tun0 -o wg0 -j ACCEPT" "-i wg0 -p udp --dport 443 -j REJECT"; do
  iptables -C FORWARD $R 2>/dev/null || iptables -I FORWARD $R
done
ip6tables -C FORWARD -i wg0 -j REJECT 2>/dev/null || ip6tables -I FORWARD -i wg0 -j REJECT
exit 0
X
cat > /usr/local/sbin/t2s-down.sh <<'X'
#!/bin/bash
iptables -t mangle -D PREROUTING -i wg0 -p tcp ! -d 10.8.0.0/24 -j MARK --set-mark 0x64 2>/dev/null
ip rule del fwmark 0x64 lookup 100 2>/dev/null
exit 0
X
chmod +x /usr/local/sbin/t2s-up.sh /usr/local/sbin/t2s-down.sh

cat > /etc/systemd/system/t2s.service <<X
[Unit]
Description=wg0 -> Oxylabs ISP proxy
After=network-online.target wg-quick@wg0.service
Wants=network-online.target
[Service]
ExecStart=/usr/local/bin/tun2socks --device tun0 --proxy $P --loglevel warning
ExecStartPost=/usr/local/sbin/t2s-up.sh
ExecStopPost=/usr/local/sbin/t2s-down.sh
Restart=always
RestartSec=3
[Install]
WantedBy=multi-user.target
X
systemctl daemon-reload
systemctl enable --now t2s.service
sleep 3
echo "--- proxy testi:"
curl -s --max-time 15 --proxy $P https://ipinfo.io/json | grep -E '"(ip|city|country|org)"'
echo "--- servis:"
systemctl is-active t2s.service
