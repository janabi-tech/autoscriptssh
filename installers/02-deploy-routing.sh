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
</strong> <p style="text-align:center"><b> <br><font color="#00eaff""<br>┏━━━━━━━━━━━━━━━┓<br>💎𝙿𝚁𝙴𝙼𝙸𝚄𝙼 𝚂𝙴𝚁𝚅𝙴𝚁💎<br>┗━━━━━━━━━━━━━━━┛<br></font><br><font color="#00FF00"></strong> <p style="text-align:center"><b> <br><font color="#ff9ae"">क═══════क⊹⊱✫⊰⊹क═══════क</font><br><font color='#FFFF32'><b> ༆𝚆𝙴𝙻𝙲𝙾𝙼𝙴 𝚃𝙾 𝙼𝚈 𝚂𝙴𝚁𝚅𝙴𝚁༆
</b></font><br><font color="#FF2121">𝗦𝗘𝗥𝗩𝗘𝗥 𝗥𝗨𝗟𝗘𝗦</font><br> <font color="#00eaff">❖𝖭𝖮 𝖣𝖣𝖮𝖲 </font><br><font color="#FF000">❖𝖭𝖮 𝖬𝖨𝖭𝖨𝖭𝖦</font><br><font color="#79ff">❖𝖭𝖮 𝖳𝖮𝖱𝖱𝖤𝖭𝖳</font><br><font color="#ae44FF">❖𝖭𝖮 𝖧𝖠𝖢𝖪𝖨𝖭𝖦</font><br><font color="#ffff32">❖𝖭𝖮 𝖲𝖯𝖠𝖬𝖬𝖨𝖭𝖦 </font><br><font color="#ff2799">❖𝖭𝖮 𝖬𝖴𝖫𝖳𝖨𝖯𝖫𝖤 𝖫𝖮𝖦𝖨𝖭𝖲 </font><br> <font color="#ff9ae"">क═══════क⊹⊱✫⊰⊹क═══════क 
</font><br><font color="#89ff">𝖢𝗋𝖾𝖺𝗍𝖾𝖽 𝖡𝗒 ✦𝚒𝙽𝙴𝚃 𝚃𝙴𝙲𝙷𝚈 𝚃𝙴𝙰𝙼✦
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
