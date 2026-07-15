#!/bin/bash
# File: /opt/imagitech/installers/04-deploy-xray.sh
# Purpose: Installs Xray-core and generates the multi-protocol JSON config

source /opt/imagitech/core/imagitech.conf 2>/dev/null || true
source /opt/imagitech/lib/system.sh
source /opt/imagitech/lib/installer_utils.sh

log_event "INFO" "Deploying Phase 4: Multi-Protocol Core"

safe_create_dir "/opt/imagitech/xray"
safe_create_dir "/var/log/xray"

# 0. Nuke conflicting generic installations
if systemctl is-active --quiet xray.service; then
    log_event "INFO" "Cleaning up conflicting services"
    systemctl stop xray.service >/dev/null 2>&1
    systemctl disable xray.service >/dev/null 2>&1
fi

# 1. Download Xray-Core
if [ ! -f "/opt/imagitech/xray/xray" ]; then
    log_event "INFO" "Downloading Core Engine..."
    LATEST_XRAY=$(curl -sI https://github.com/XTLS/Xray-core/releases/latest | grep -i location | awk -F '/' '{print $NF}' | tr -d '\r')
    if [[ -z "$LATEST_XRAY" ]]; then LATEST_XRAY="v1.8.24"; fi
    
    ARCH="64"
    if [[ $(uname -m) == "aarch64" ]]; then ARCH="arm64-v8a"; fi
    
    wget -qO /tmp/xray.zip "https://github.com/XTLS/Xray-core/releases/download/${LATEST_XRAY}/Xray-linux-${ARCH}.zip"
    unzip -q /tmp/xray.zip xray -d /opt/imagitech/xray/
    chmod +x /opt/imagitech/xray/xray
    rm -f /tmp/xray.zip
fi

# 2. Generate REALITY Keys
log_event "INFO" "Generating Next-Gen Cryptographic Keys..."
if [ ! -f "/opt/imagitech/core/keys/reality.pub" ]; then
    XRAY_KEYS=$(/opt/imagitech/xray/xray x25519)
    # Different Xray versions output either "Private key:" or "PrivateKey:"
    REALITY_PRIV=$(echo "$XRAY_KEYS" | grep -iE "Private[ _]?Key" | awk -F': ' '{print $2}' | tr -d ' ')
    REALITY_PUB=$(echo "$XRAY_KEYS" | grep -iE "Public[ _]?Key|Password" | awk -F': ' '{print $2}' | tr -d ' ')
    REALITY_SHORTID=$(openssl rand -hex 8)

    echo "$REALITY_PRIV" > /opt/imagitech/core/keys/reality.priv
    echo "$REALITY_PUB" > /opt/imagitech/core/keys/reality.pub
    echo "$REALITY_SHORTID" > /opt/imagitech/core/keys/reality.sid
else
    REALITY_PRIV=$(cat /opt/imagitech/core/keys/reality.priv)
    REALITY_PUB=$(cat /opt/imagitech/core/keys/reality.pub)
    REALITY_SHORTID=$(cat /opt/imagitech/core/keys/reality.sid)
fi



cat <<EOF > /opt/imagitech/xray/config.json
{
  "log": {
    "loglevel": "warning",
    "access": "/var/log/xray/access.log",
    "error": "/var/log/xray/error.log"
  },
  "api": {
    "tag": "api",
    "services": [
      "StatsService",
      "HandlerService"
    ]
  },
  "stats": {},
  "policy": {
    "levels": {
      "0": {
        "statsUserUplink": true,
        "statsUserDownlink": true,
        "statsUserOnline": true
      }
    },
    "system": {
      "statsInboundUplink": true,
      "statsInboundDownlink": true,
      "statsOutboundUplink": true,
      "statsOutboundDownlink": true
    }
  },
  "routing": {
    "rules": [
      {
        "inboundTag": [
          "api-inbound"
        ],
        "outboundTag": "api",
        "type": "field"
      }
    ]
  },
  "inbounds": [
    {
      "tag": "api-inbound",
      "listen": "127.0.0.1",
      "port": 10085,
      "protocol": "dokodemo-door",
      "settings": {
        "address": "127.0.0.1"
      }
    },
    {
      "listen": "127.0.0.1",
      "port": 10001,
      "protocol": "vless",
      "tag": "vless-reality-gatekeeper",
      "settings": {
        "clients": [],
        "decryption": "none",
        "fallbacks": [
          {
            "dest": 10005,
            "xver": 1
          }
        ]
      },
      "streamSettings": {
        "network": "tcp",
        "security": "reality",
        "realitySettings": {
          "dest": "${REALITY_SNI:-www.microsoft.com}:443",
          "serverNames": [
            "${REALITY_SNI:-www.microsoft.com}",
            "www.apple.com"
          ],
          "privateKey": "${REALITY_PRIV}",
          "shortIds": [
            "${REALITY_SHORTID}"
          ]
        },
        "sockopt": {
          "acceptProxyProtocol": true
        }
      },
      "sniffing": {
        "enabled": true,
        "destOverride": ["http", "tls", "quic"]
      }
    },
    {
      "listen": "127.0.0.1",
      "port": 10005,
      "protocol": "vless",
      "tag": "vless-xhttp",
      "settings": {
        "clients": [],
        "decryption": "none"
      },
      "streamSettings": {
        "network": "xhttp",
        "security": "none",
        "xhttpSettings": {
          "mode": "auto",
          "path": "/xhttp"
        },
        "sockopt": {
          "acceptProxyProtocol": true
        }
      }
    },
    {
      "listen": "127.0.0.1",
      "port": 10002,
      "protocol": "vless",
      "tag": "vless-ws",
      "settings": {
        "clients": [],
        "decryption": "none"
      },
      "streamSettings": {
        "network": "ws",
        "security": "none",
        "wsSettings": {
          "path": "/vless"
        }
      }
    },
    {
      "listen": "127.0.0.1",
      "port": 10003,
      "protocol": "vmess",
      "tag": "vmess-ws",
      "settings": {
        "clients": []
      },
      "streamSettings": {
        "network": "ws",
        "security": "none",
        "wsSettings": {
          "path": "/vmess"
        }
      }
    },
    {
      "listen": "127.0.0.1",
      "port": 10004,
      "protocol": "trojan",
      "tag": "trojan-ws",
      "settings": {
        "clients": []
      },
      "streamSettings": {
        "network": "ws",
        "security": "none",
        "wsSettings": {
          "path": "/trojan"
        }
      }
    }
  ],
  "outbounds": [
    {
      "protocol": "freedom",
      "tag": "direct"
    },
    {
      "protocol": "blackhole",
      "tag": "block"
    }
  ]
}
EOF

# 4. Deploy Xray Systemd Service
cat <<EOF > /tmp/imagitech-xray.service.tmp
[Unit]
Description=Imagitech Xray-Core Engine
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/opt/imagitech/xray
ExecStart=/opt/imagitech/xray/xray run -c /opt/imagitech/xray/config.json
Restart=always
RestartSec=3
LimitNOFILE=1048576

[Install]
WantedBy=multi-user.target
EOF

safe_deploy_systemd "imagitech-xray"

# Update HAProxy's list of REALITY SNIs
mkdir -p /etc/haproxy
echo "${REALITY_SNI:-www.microsoft.com}" > /etc/haproxy/reality_sni.lst
systemctl reload haproxy >/dev/null 2>&1 || true

# Force restart Xray to pick up config.json changes
systemctl restart imagitech-xray >/dev/null 2>&1

log_event "INFO" "Multi-Protocol Core Deployed Successfully."
