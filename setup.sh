#!/usr/bin/env bash
# HermesAtlas DE – Almanya sunucusu kurulumu (Debian 12 / Ubuntu 22–24, root olarak)
# Sunucuda masaüstü + Google Chrome + tarayıcıdan erişilen ekran (noVNC, HTTPS, port 6080) kurar.
# YouTube Studio bu sunucudaki Chrome'dan açılır -> yükleme/planlama Almanya IP'sinden yapılır.
# Şifre bu dosyada YOK: kurulum sonunda VNC şifresini sen yazarsın.
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive
U=hermes

apt-get update
apt-get install -y --no-install-recommends xfce4 xfce4-terminal dbus-x11 tigervnc-standalone-server tigervnc-common \
  novnc websockify openssl curl wget ca-certificates ufw locales tzdata fonts-dejavu fonts-noto-color-emoji xdg-utils git

# Almanya ayarları: dil, saat dilimi
sed -i 's/^# *de_DE.UTF-8/de_DE.UTF-8/' /etc/locale.gen && locale-gen
update-locale LANG=de_DE.UTF-8
timedatectl set-timezone Europe/Berlin || ln -sf /usr/share/zoneinfo/Europe/Berlin /etc/localtime

# Google Chrome
wget -q -O /tmp/chrome.deb https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb
apt-get install -y /tmp/chrome.deb

# Kullanıcı
id $U >/dev/null 2>&1 || useradd -m -s /bin/bash $U
mkdir -p /home/$U/.vnc /home/$U/Videos
cat > /home/$U/.vnc/xstartup <<'EOF'
#!/bin/sh
unset SESSION_MANAGER DBUS_SESSION_BUS_ADDRESS
export LANG=de_DE.UTF-8
exec dbus-launch --exit-with-session startxfce4
EOF
chmod +x /home/$U/.vnc/xstartup
cat > /home/$U/.vnc/config <<'EOF'
geometry=1600x1000
localhost
alwaysshared
EOF
chown -R $U:$U /home/$U

# Self-signed sertifika (tarayıcı ilk girişte uyarı verir, bir kez "devam et")
mkdir -p /etc/novnc-cert
[ -f /etc/novnc-cert/self.pem ] || openssl req -x509 -nodes -newkey rsa:2048 -days 3650 \
  -subj "/CN=hermes-de" -keyout /etc/novnc-cert/self.pem -out /etc/novnc-cert/self.pem

# Servisler
cat > /etc/systemd/system/vncserver@.service <<EOF
[Unit]
Description=TigerVNC :%i
After=network.target
[Service]
Type=forking
User=$U
ExecStartPre=-/usr/bin/vncserver -kill :%i
ExecStart=/usr/bin/vncserver :%i
ExecStop=/usr/bin/vncserver -kill :%i
Restart=on-failure
[Install]
WantedBy=multi-user.target
EOF
cat > /etc/systemd/system/novnc.service <<'EOF'
[Unit]
Description=noVNC
After=vncserver@1.service
[Service]
ExecStart=/usr/bin/websockify --web /usr/share/novnc --cert /etc/novnc-cert/self.pem --ssl-only 6080 localhost:5901
Restart=always
[Install]
WantedBy=multi-user.target
EOF

# Güvenlik duvarı: yalnız SSH ve 6080
ufw allow 22/tcp
ufw allow 6080/tcp
ufw --force enable

echo
echo "=== Şimdi VNC şifresini belirle (en az 6 karakter, kimseye/hiçbir yere yazma) ==="
su - $U -c "vncpasswd"
systemctl daemon-reload
systemctl enable --now vncserver@1 novnc
IP=$(curl -s https://api.ipify.org || hostname -I | awk '{print $1}')
echo
echo "HAZIR. Tarayıcıda aç:  https://$IP:6080/vnc.html"
echo "Sertifika uyarısında 'Gelişmiş -> devam et', sonra VNC şifresi."
