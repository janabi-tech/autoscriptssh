#!/bin/bash
# File: /opt/janabitech/installers/02-deploy-routing.sh
# Purpose: Idempotent deployment of Dropbear, Stunnel, and the Async Proxy.

source /opt/janabitech/core/janabitech.conf 2>/dev/null || true
source /opt/janabitech/lib/installer_utils.sh

log_event "INFO" "Deploying Phase 2: Data Plane & Routing Engine"

safe_create_dir "/opt/janabitech/services/routing"

# --- 1. Configure Dropbear & OpenSSH ---
log_event "INFO" "Configuring SSH and Decoy Services..."

# Install Nginx
apt-get install -y nginx >/dev/null 2>&1
systemctl stop nginx

# Configure Nginx Decoy
cat <<EOF > /etc/nginx/sites-available/default
server {
    listen 127.0.0.1:8081 default_server proxy_protocol;
    server_name _;

    # Ensure real IP is logged from HAProxy Proxy Protocol
    set_real_ip_from 127.0.0.1/32;
    real_ip_header proxy_protocol;

    root /var/www/html;
    index index.html;

    location / {
        try_files \$uri \$uri/ =404;
    }
}
EOF

# Create a sleek default HTML page for the decoy
cat <<EOF > /var/www/html/index.html
<!DOCTYPE html>
<html>
<head>
<title>System Status</title>
<style>
    body { background-color: #f4f4f9; color: #333; font-family: sans-serif; text-align: center; padding-top: 100px; }
    h1 { color: #5a5a5a; }
</style>
</head>
<body>
    <h1>Service Running</h1>
    <p>The system backend is operational.</p>
</body>
</html>
EOF

systemctl enable nginx >/dev/null 2>&1
systemctl restart nginx
# Write the Premium Default Banner
cat <<'EOF' > /etc/issue.net
</strong> <p style="text-align:center"><b> <br>
<font color="#00aaaa">════════════════════════════</font><br>
<b><font color="#00ffff">janabitech VPN PREMIUM</font></b><br>
<font color="#00aaaa">════════════════════════════</font><br>
<b><font color="#ff00ff">GET YOUR SUBSCRIPTION</font></b><br>
<font color="#ff00ff">Bot: t.me/imagivpnbot</font><br>
<font color="#ff00ff">Channel: t.me/janabitech001</font><br>
<font color="#00aaaa">════════════════════════════</font><br>
<b><font color="#ff4444">TERMS OF SERVICE</font></b><br>
<font color="#ff8800">- No Abuse, Spam, Illegal -</font><br>
<font color="#ff8800">- Do Not Share Configs -</font><br>
<font color="#ff8800">- Violation = Termination -</font><br>
<font color="#00aaaa">════════════════════════════</font><br>
<font color="#00ffff">Powered by †hε drεαmεr</font><br>
<font color="#aaaaaa">janabitech.online</font><br>
<font color="#00aaaa">════════════════════════════</font><br>
</b></p>
EOF

# Enforce banner globally (Ubuntu 20/22/24 & Debian 11/12 fix)
# 1. Fallback for older OS
if [ -f "/etc/ssh/sshd_config" ]; then
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
fi

# 2. Priority Drop-in for Modern OS (Ubuntu 24.04+)
if [ -d "/etc/ssh/sshd_config.d" ]; then
    mkdir -p /etc/ssh/sshd_config.d
    echo "Banner /etc/issue.net" > /etc/ssh/sshd_config.d/99-janabitech-banner.conf
    echo "MaxStartups 1000:30:2000" >> /etc/ssh/sshd_config.d/99-janabitech-banner.conf
    echo "ClientAliveInterval 60" >> /etc/ssh/sshd_config.d/99-janabitech-banner.conf
    echo "ClientAliveCountMax 3" >> /etc/ssh/sshd_config.d/99-janabitech-banner.conf
fi

# 3. Reload Daemons and Robustly Enable SSH
systemctl daemon-reload
if systemctl list-unit-files | grep -q "ssh"; then
    systemctl enable ssh >/dev/null 2>&1 || systemctl enable sshd >/dev/null 2>&1
    systemctl enable ssh.socket >/dev/null 2>&1
    systemctl restart ssh >/dev/null 2>&1 || systemctl restart sshd >/dev/null 2>&1
    systemctl restart ssh.socket >/dev/null 2>&1
fi

# Configure Dropbear ports and explicitly force the banner flag (-b)
cat <<EOF > /etc/default/dropbear
NO_START=0
DROPBEAR_PORT=${PORT_DROPBEAR}
DROPBEAR_EXTRA_ARGS="-p ${PORT_DROPBEAR_ALT} -w -g -K 60 -I 0 -b /etc/issue.net"
DROPBEAR_RECEIVE_WINDOW=65536
EOF

systemctl daemon-reload

# Disable dropbear socket activation to prevent it from hijacking Port 22 (Ubuntu 22.04+)
systemctl stop dropbear.socket >/dev/null 2>&1
systemctl disable dropbear.socket >/dev/null 2>&1

systemctl enable dropbear >/dev/null 2>&1
systemctl restart dropbear

# --- 2. The Async WebSocket Proxy ---
log_event "INFO" "Deploying WebSocket Handler..."

# The master installer already placed the file here, just ensure it's executable
if [ -f /opt/janabitech/services/routing/ws-proxy ]; then
    chmod +x /opt/janabitech/services/routing/ws-proxy
else
    chmod +x /opt/janabitech/services/routing/ws-proxy.py
fi

cat <<EOF > /tmp/janabitech-ws.service.tmp
[Unit]
Description=janabitech Async WS Multiplexer
After=network.target dropbear.service

[Service]
Type=simple
User=root
WorkingDirectory=/opt/janabitech/services/routing
ExecStart=/bin/bash -c 'if [ -f /opt/janabitech/services/routing/ws-proxy ]; then exec /opt/janabitech/services/routing/ws-proxy; else exec /usr/bin/python3 /opt/janabitech/services/routing/ws-proxy.py; fi'
Restart=always
RestartSec=3
LimitNOFILE=1048576

[Install]
WantedBy=multi-user.target
EOF

safe_deploy_systemd "janabitech-ws"

# --- 2b. WSS Injection Handler ---
log_event "INFO" "Deploying Secure Injection Handler..."

if [ -f /opt/janabitech/services/routing/wss-injector ]; then
    chmod +x /opt/janabitech/services/routing/wss-injector
else
    chmod +x /opt/janabitech/services/routing/wss-injector.py 2>/dev/null || true
fi

cat <<EOF > /tmp/janabitech-wss.service.tmp
[Unit]
Description=janabitech WSS Injection Handler
After=network.target

[Service]
Type=simple
User=root
ExecStart=/bin/bash -c 'if [ -f /opt/janabitech/services/routing/wss-injector ]; then exec /opt/janabitech/services/routing/wss-injector; else exec /usr/bin/python3 /opt/janabitech/services/routing/wss-injector.py; fi'
Restart=always
RestartSec=3
LimitNOFILE=65535

[Install]
WantedBy=multi-user.target
EOF

safe_deploy_systemd "janabitech-wss"

# --- 3. HAProxy (Layer 7 SNI & SSL Multiplexer) ---
log_event "INFO" "Configuring TLS Multiplexer..."

# Use our idempotent TLS generator
ensure_tls_cert "$PRIMARY_DOMAIN"

# Keep the cert path compatible for now, or just symlink it
cp /opt/janabitech/core/keys/stunnel.pem /opt/janabitech/core/keys/haproxy.pem
chmod 600 /opt/janabitech/core/keys/haproxy.pem

# Ensure the SNI list file exists before HAProxy starts, 
# otherwise HAProxy will crash on startup. Phase 04 populates it.
touch /etc/haproxy/reality_sni.lst

cat <<EOF > /etc/haproxy/haproxy.cfg
global
    log /dev/log local0
    log /dev/log local1 notice
    chroot /var/lib/haproxy
    stats socket /run/haproxy/admin.sock mode 660 level admin expose-fd listeners
    stats timeout 30s
    user haproxy
    group haproxy
    daemon
    ca-base /etc/ssl/certs
    crt-base /etc/ssl/private
    ssl-default-bind-ciphers ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305:DHE-RSA-AES128-GCM-SHA256:DHE-RSA-AES256-GCM-SHA384
    ssl-default-bind-ciphersuites TLS_AES_128_GCM_SHA256:TLS_AES_256_GCM_SHA384:TLS_CHACHA20_POLY1305_SHA256
    ssl-default-bind-options no-sslv3 no-tlsv10 no-tlsv11

defaults
    log     global
    mode    tcp
    option  tcplog
    option  dontlognull
    timeout connect 5s
    timeout client  50s
    timeout server  50s
    timeout tunnel  1h
    option  clitcpka
    option  srvtcpka

# Stage 1: The Raw TCP SNI Gateway
frontend https_front
    bind *:${PORT_WS_HTTPS}
    mode tcp
    tcp-request inspect-delay 5s
    tcp-request content accept if { req_ssl_hello_type 1 }
    # Accept non-TLS (raw HTTP injection) immediately when data arrives
    tcp-request content accept if { req.len 6 } !{ req_ssl_hello_type 1 }

    acl is_ssl req_ssl_hello_type 1

    # Route to Xray REALITY only if the SNI matches our configured REALITY SNI
    acl is_reality_sni req.ssl_sni -f /etc/haproxy/reality_sni.lst
    use_backend xray_reality if is_ssl is_reality_sni
    
    # TLS traffic with non-Reality SNI goes to local decrypter for TLS termination
    use_backend local_decrypter if is_ssl
    
    # Non-TLS traffic (raw HTTP injection from VPN apps) goes to WSS Injector
    default_backend backend_wss_injector

backend local_decrypter
    mode tcp
    server loopback 127.0.0.1:9443 send-proxy-v2 no-check

backend xray_reality
    mode tcp
    server xray 127.0.0.1:10001 send-proxy-v2 no-check

backend backend_wss_injector
    mode tcp
    server wss_inj 127.0.0.1:4430 no-check

# Stage 1.5: The Raw HTTP Router (Multiplexes 80 and 8080 for Xray and WS-Proxy)
frontend http_front
    bind *:80
    bind *:8080
    bind *:8880
    mode tcp
    tcp-request inspect-delay 5s
    tcp-request content accept if HTTP
    
    use_backend backend_vless if { req.payload(0,256) -m sub /vless }
    use_backend backend_vmess if { req.payload(0,256) -m sub /vmess }
    use_backend backend_trojan if { req.payload(0,256) -m sub /trojan }
    use_backend backend_xhttp if { req.payload(0,256) -m sub /xhttp }
    
    default_backend backend_sshws

# Stage 2: The Decrypted HTTP Router
frontend https_decrypted
    bind 127.0.0.1:9443 ssl crt /opt/janabitech/core/keys/haproxy.pem accept-proxy
    mode tcp
    tcp-request inspect-delay 5s
    tcp-request content accept if HTTP

    # Route based on HTTP PATH via payload substring search
    use_backend backend_vless if { req.payload(0,256) -m sub /vless }
    use_backend backend_vmess if { req.payload(0,256) -m sub /vmess }
    use_backend backend_trojan if { req.payload(0,256) -m sub /trojan }
    use_backend backend_xhttp if { req.payload(0,256) -m sub /xhttp }
    
    # Default fallback: Route all unmatched payloads (custom HTTP Injector payloads) to SSH WS
    default_backend backend_sshws

backend backend_vless
    mode tcp
    server vless 127.0.0.1:10002 no-check

backend backend_vmess
    mode tcp
    server vmess 127.0.0.1:10003 no-check

backend backend_trojan
    mode tcp
    server trojan 127.0.0.1:10004 no-check

backend backend_xhttp
    mode tcp
    server xhttp 127.0.0.1:10005 no-check

backend backend_sshws
    mode tcp
    server sshws 127.0.0.1:9880 no-check

backend backend_nginx
    mode tcp
    server nginx 127.0.0.1:8081 send-proxy no-check
EOF

# Optional fallback ports (legacy 8443 directly to SSH)
cat <<EOF >> /etc/haproxy/haproxy.cfg

frontend legacy_ssl
    bind *:8443 ssl crt /opt/janabitech/core/keys/haproxy.pem
    mode tcp
    default_backend backend_legacy_ssh

backend backend_legacy_ssh
    mode tcp
    server ssh 127.0.0.1:${PORT_SSH}
EOF

# Ensure HAProxy restarts on failure (Fixes Ubuntu 20.04 boot race conditions)
mkdir -p /etc/systemd/system/haproxy.service.d
cat <<EOF > /etc/systemd/system/haproxy.service.d/override.conf
[Service]
Restart=on-failure
RestartSec=5
EOF
systemctl daemon-reload

systemctl enable haproxy >/dev/null 2>&1
systemctl restart haproxy

log_event "INFO" "Routing Engine Deployed Successfully."
