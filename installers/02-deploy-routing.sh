#!/bin/bash
# File: /opt/janabitech/installers/02-deploy-routing.sh
# Purpose: Idempotent deployment of Dropbear, Stunnel, and the Async Proxy.

source /opt/janabitech/core/janabitech.conf
source /opt/janabitech/lib/installer_utils.sh

log_event "INFO" "Deploying Phase 2: Data Plane & Routing Engine"

safe_create_dir "/opt/janabitech/services/routing"

# --- 1. Configure Dropbear & OpenSSH ---
log_event "INFO" "Configuring Dropbear and OpenSSH..."

# Write the Premium Default Banner
cat <<'EOF' > /etc/issue.net
</p><b><small><h6 style="text-align: center;"><span style="color: #fff9;"><span style="background-color:#;">💎 𝖶𝖤𝖫𝖢𝖮𝖬𝖤 𝖳𝖮 𝖬𝖸 𝖯𝖱𝖤𝖬𝖨𝖴𝖬 𝖵𝖯𝖲💎&nbsp</span></i> <small><font color=#"Tukul">
<b></span><h4  style="text-align: center;"><font color="#ff2d2d"></><big><span style="color: #aa3426"></span><big><span style="color: #ff0000"><layout><big><big>S<small> </span><span style="color: #ff4444"> E </span><span style="color: #f63940"><small> R <big><small> </span><span style="color: #f9555f">V</span><span style="color: #4d727f"> <small>E</span><span style="color: #208e9f"> R </span><span style="color: #188aa9"> </span><span style="color: #1086b3">   ~ P </span><span style="color: #0881bc"> R </span><span style="color: #007dc6">E </span><span style="color: #33649e"><big>M </span><span style="color: #4169E1">I </span><span style="color: #DC143C"><big>U</span><span style="color: #cc1928"><big> M<small><small><small><small><small></span><big/i> </p><br></p><big><h2 style="text-align: center;"><font color='cyan'><b>────────•••──────── </b></font> <br><font color='#ff1234'>&ensp; 🩸NO DDOS🩸 </font>
<br><font color='#fff111'>&ensp; 🩸NO MINING🩸 </font>
<br><font color='#eafe'>&ensp; 🩸NO HACKING🩸 </font>
<br><font color='#FFF00'>&ensp; 🩸NO MULTILOGIN🩸 </font>
<br><font color='#ff9'>&ensp; 🩸NO ILLEGAL ACTIVITIES🩸 </font><br><font color='aqua'><b><strong><big>────────•••────────
EOF

# Enforce banner globally (Ubuntu 20/22/24 & Debian 11/12 fix)
# 1. Fallback for older OS
sed -i 's/#Banner.*/Banner \/etc\/issue.net/g' /etc/ssh/sshd_config
if ! grep -q "^Banner /etc/issue.net" /etc/ssh/sshd_config; then
    echo "Banner /etc/issue.net" >> /etc/ssh/sshd_config
fi
sed -i 's/#MaxStartups.*/MaxStartups 1000:30:2000/g' /etc/ssh/sshd_config
if ! grep -q "^MaxStartups" /etc/ssh/sshd_config; then
    echo "MaxStartups 1000:30:2000" >> /etc/ssh/sshd_config
fi
sed -i 's/#ClientAliveInterval.*/ClientAliveInterval 60/g' /etc/ssh/sshd_config
if ! grep -q "^ClientAliveInterval" /etc/ssh/sshd_config; then
    echo "ClientAliveInterval 60" >> /etc/ssh/sshd_config
fi
sed -i 's/#ClientAliveCountMax.*/ClientAliveCountMax 3/g' /etc/ssh/sshd_config
if ! grep -q "^ClientAliveCountMax" /etc/ssh/sshd_config; then
    echo "ClientAliveCountMax 3" >> /etc/ssh/sshd_config
fi

# 2. Priority Drop-in for Modern OS (Ubuntu 24.04+)
mkdir -p /etc/ssh/sshd_config.d
echo "Banner /etc/issue.net" > /etc/ssh/sshd_config.d/99-janabitech-banner.conf
echo "MaxStartups 1000:30:2000" >> /etc/ssh/sshd_config.d/99-janabitech-banner.conf
echo "ClientAliveInterval 60" >> /etc/ssh/sshd_config.d/99-janabitech-banner.conf
echo "ClientAliveCountMax 3" >> /etc/ssh/sshd_config.d/99-janabitech-banner.conf

# 3. Reload Daemons (Including Ubuntu 24 Socket Activation)
systemctl daemon-reload
systemctl restart ssh >/dev/null 2>&1 || systemctl restart sshd >/dev/null 2>&1
systemctl restart ssh.socket >/dev/null 2>&1

# Configure Dropbear ports and explicitly force the banner flag (-b)
cat <<EOF > /etc/default/dropbear
NO_START=0
DROPBEAR_PORT=${PORT_DROPBEAR}
DROPBEAR_EXTRA_ARGS="-p ${PORT_DROPBEAR_ALT} -w -g -K 60 -I 0 -b /etc/issue.net"
DROPBEAR_RECEIVE_WINDOW=65536
EOF

systemctl daemon-reload
systemctl enable dropbear >/dev/null 2>&1
systemctl restart dropbear

# --- 2. The Async WebSocket Proxy ---
log_event "INFO" "Deploying Async WebSocket Multiplexer..."

# The master installer already placed the file here, just ensure it's executable
chmod +x /opt/janabitech/services/routing/ws-proxy.py

cat <<EOF > /tmp/janabitech-ws.service.tmp
[Unit]
Description=Janabitech Async WS Multiplexer
After=network.target dropbear.service

[Service]
Type=simple
User=root
WorkingDirectory=/opt/janabitech/services/routing
ExecStart=/usr/bin/python3 /opt/janabitech/services/routing/ws-proxy.py
Restart=always
RestartSec=3
LimitNOFILE=1048576

[Install]
WantedBy=multi-user.target
EOF

safe_deploy_systemd "janabitech-ws"

# --- 3. Stunnel (SSL Termination) ---
log_event "INFO" "Configuring Stunnel4 TLS Bridging..."

# Use our idempotent TLS generator
ensure_tls_cert "$PRIMARY_DOMAIN"

cat <<EOF > /etc/stunnel/stunnel.conf
pid = /var/run/stunnel.pid
cert = /opt/janabitech/core/keys/stunnel.pem
client = no
socket = a:SO_REUSEADDR=1
socket = a:SO_KEEPALIVE=1
socket = l:TCP_NODELAY=1
socket = r:TCP_NODELAY=1

[ssh-ws-ssl]
accept = ${PORT_WS_HTTPS}
connect = 127.0.0.1:${PORT_WS_HTTP}

[dropbear-ssl-447]
accept = 447
connect = 127.0.0.1:${PORT_SSH}

[dropbear-ssl-777]
accept = 777
connect = 127.0.0.1:${PORT_SSH}
EOF

# Ensure Stunnel boot flag is enabled
sed -i 's/ENABLED=0/ENABLED=1/g' /etc/default/stunnel4

systemctl enable stunnel4 >/dev/null 2>&1
systemctl restart stunnel4

log_event "INFO" "Routing Engine Deployed Successfully."
