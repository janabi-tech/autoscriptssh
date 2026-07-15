#!/bin/bash
# JanabiTech Enterprise Deployment Pipeline
# (c) 2026 JanabiTech. All rights reserved.

REPO_URL="https://vpn.janabitech.online/raw"

# --- UI Colors ---
GREEN='\033[0;32m'
CYAN='\033[0;36m'
RED='\033[0;31m'
ORANGE='\033[0;33m'
NC='\033[0m'

clear
echo -e "${CYAN}======================================================${NC}"
echo -e "${GREEN}      JANABITECH ENTERPRISE DEPLOYMENT PIPELINE        ${NC}"
echo -e "${CYAN}======================================================${NC}"

if [ "${EUID}" -ne 0 ]; then
    echo -e "${RED}[FATAL] Please run as root. (Type: sudo su -)${NC}"
    exit 1
fi

# Fix system hostname resolution if missing from /etc/hosts to prevent sudo warnings
CURRENT_HOSTNAME=$(hostname)
if [ -n "$CURRENT_HOSTNAME" ]; then
    if ! grep -q "127.0.0.1 $CURRENT_HOSTNAME" /etc/hosts; then
        echo "127.0.0.1 $CURRENT_HOSTNAME" >> /etc/hosts
    fi
fi

export GITHUB_TOKEN

echo -e "${ORANGE}[*] Verifying Server IP License...${NC}"
SERVER_IP=$(curl -s4 ifconfig.me)
API_URL="https://vpn.janabitech.online/api/v1"

# Query the Cloudflare Worker API
RESPONSE=$(curl -s --max-time 10 "${API_URL}/ip/verify?ip=${SERVER_IP}")
STATUS=$(echo "$RESPONSE" | grep -o '"status":"[^"]*"' | cut -d'"' -f4)
EXPIRES=$(echo "$RESPONSE" | grep -o '"expires_at":"[^"]*"' | cut -d'"' -f4 | cut -d'T' -f1)
DOMAIN=$(echo "$RESPONSE" | grep -o '"domain":"[^"]*"' | cut -d'"' -f4)

if [ "$STATUS" != "active" ]; then
    echo -e "\n${RED}============================================${NC}"
    echo -e "${RED}  ❌ THIS IP IS NOT LICENSED${NC}"
    echo -e "${RED}  IP: ${SERVER_IP}${NC}"
    echo -e ""
    echo -e "${CYAN}  Purchase a license via our Telegram bot:${NC}"
    echo -e "${CYAN}  https://t.me/imagivpnbot${NC}"
    echo -e "${RED}============================================${NC}\n"
    exit 1
fi

EXPIRES=$(echo "$RESPONSE" | grep -o '"expires_at":"[^"]*"' | cut -d'"' -f4 | cut -d'T' -f1)
DOMAIN=$(echo "$RESPONSE" | grep -o '"domain":"[^"]*"' | cut -d'"' -f4)

if [[ "$EXPIRES" > "2099" ]]; then
    echo -e "${GREEN}[✓] License active until: Lifetime${NC}"
else
    echo -e "${GREEN}[✓] License active until: ${EXPIRES}${NC}"
fi

if [ -n "$DOMAIN" ] && [ "$DOMAIN" != "null" ]; then
    echo -e "${GREEN}[✓] Licensed domain: ${DOMAIN}${NC}"
    export JANABITECH_DOMAIN="${DOMAIN}"
    export JANABITECH_NS_DOMAIN="ns-${DOMAIN}"
fi

# Ensure basic fetch tools are present before we even start
apt-get update -y >/dev/null 2>&1
apt-get install -y curl wget procps >/dev/null 2>&1

# --- 1. System Scaffolding ---
echo -e "${CYAN}[*] Bootstrapping Base Architecture...${NC}"
mkdir -p /opt/janabitech/{bin,lib,logs,menus,services,core}
mkdir -p /opt/janabitech/core/keys
mkdir -p /opt/janabitech/services/{monitor,routing}
mkdir -p /root/janabitech-tmp
cd /root/janabitech-tmp

# --- 2. Secure Fetch Function ---
fetch_file() {
    local remote_path="$1"
    local local_path="$2"
    
    echo -e "  -> Fetching deployment module..."
    
    local curl_status=0
    if [[ -n "$GITHUB_TOKEN" ]]; then
        curl -H "Authorization: token ${GITHUB_TOKEN}" -sS -L -f -o "$local_path" "${REPO_URL}/${remote_path}" || curl_status=$?
    else
        curl -sS -L -f -o "$local_path" "${REPO_URL}/${remote_path}" || curl_status=$?
    fi
    
    if [ $curl_status -ne 0 ] || [ ! -s "$local_path" ] || grep -q "404: N[o]t Found" "$local_path" || grep -q "File not found" "$local_path"; then
        echo -e "${RED}[FATAL] Failed to download ${remote_path}. Halting to prevent system corruption.${NC}"
        exit 1
    fi
}

# --- 3. Stage Libraries & Core Files ---
echo -e "\n${CYAN}[*] Provisioning core system modules...${NC}"
fetch_file "payload.tar.gz" "/tmp/payload.tar.gz"
tar -xzf /tmp/payload.tar.gz -C /opt/janabitech/
rm -f /tmp/payload.tar.gz
chmod -R 755 /opt/janabitech/bin/ /opt/janabitech/lib/ /opt/janabitech/menus/ /opt/janabitech/services/

# --- 4. Fetch & Execute Deployment Phases ---
echo -e "\n${GREEN}[*] Initiating Deployment Phases...${NC}"

PHASES=(
    "01-core-setup.sh"
    "02-deploy-routing.sh"
    "03-deploy-sidecars.sh"
    "04-deploy-xray.sh"
    "05-deploy-monitor.sh"
)

for PHASE in "${PHASES[@]}"; do
    fetch_file "installers/${PHASE}" "/root/janabitech-tmp/${PHASE}"
    chmod +x "/root/janabitech-tmp/${PHASE}"
    
    echo -e "\n${ORANGE}>>> Executing Deployment Phase <<<${NC}"
    /root/janabitech-tmp/"${PHASE}"
    
    if [ $? -ne 0 ]; then
        echo -e "${RED}[FATAL] Phase ${PHASE} failed. Halting installation to protect OS integrity.${NC}"
        exit 1
    fi
done

# --- 5. Symlink Global Commands ---
echo -e "\n${CYAN}[*] Binding Global CLI Interfaces...${NC}"

rm -f /usr/bin/menu /usr/local/sbin/menu /usr/local/bin/janabitech /opt/janabitech/bin/janabitech

# Symlink the multi-call core binary globally
ln -sf /opt/janabitech/bin/janabitech_core /usr/local/sbin/menu
ln -sf /opt/janabitech/bin/janabitech_core /usr/local/bin/janabitech
ln -sf /opt/janabitech/bin/janabitech_core /opt/janabitech/bin/janabitech

# --- 6. Cleanup & Finalization ---
cd /root
rm -rf /root/janabitech-tmp


# Setup Hourly API Heartbeat & License Enforcer
cat <<'EOF' > /etc/cron.hourly/janabitech-heartbeat
#!/bin/bash
IP=$(curl -s4 ifconfig.me)

# 1. Send Heartbeat
curl -s -X POST https://vpn.janabitech.online/api/v1/ip/heartbeat \
    -H "Content-Type: application/json" \
    -d "{\"ip\": \"$IP\"}" > /dev/null 2>&1

# 2. Strict License Enforcement
RESPONSE=$(curl -s --max-time 10 "https://vpn.janabitech.online/api/v1/ip/verify?ip=${IP}")
STATUS=$(echo "$RESPONSE" | grep -o '"status":"[^"]*"' | cut -d'"' -f4)

if [ -n "$STATUS" ] && [ "$STATUS" != "active" ]; then
    systemctl stop xray haproxy nginx dropbear stunnel4 janabitech-ws janabitech-dnstt janabitech-udp-custom 2>/dev/null
    systemctl disable xray haproxy nginx dropbear stunnel4 janabitech-ws janabitech-dnstt janabitech-udp-custom 2>/dev/null
    echo "REVOKED" > /opt/janabitech/core/license_status
else
    if [ -f "/opt/janabitech/core/license_status" ] && [ "$(cat /opt/janabitech/core/license_status)" == "REVOKED" ]; then
        # License was renewed! Re-enable services.
        systemctl enable xray haproxy nginx dropbear stunnel4 janabitech-ws janabitech-dnstt janabitech-udp-custom 2>/dev/null
        systemctl start xray haproxy nginx dropbear stunnel4 janabitech-ws janabitech-dnstt janabitech-udp-custom 2>/dev/null
    fi
    echo "ACTIVE" > /opt/janabitech/core/license_status
fi
EOF
chmod +x /etc/cron.hourly/janabitech-heartbeat
rm -f /etc/cron.daily/janabitech-heartbeat

# --- Tamper Detection: systemd .path watcher ---
# If the cron heartbeat is deleted or modified, this triggers an immediate re-check
cat <<'EOF' > /etc/systemd/system/janabitech-license-guard.path
[Unit]
Description=Watch for tampering of license heartbeat cron

[Path]
PathChanged=/etc/cron.hourly/janabitech-heartbeat
PathExists=/etc/cron.hourly/janabitech-heartbeat
Unit=janabitech-license-guard.service

[Install]
WantedBy=multi-user.target
EOF

cat <<'EOF' > /etc/systemd/system/janabitech-license-guard.service
[Unit]
Description=License tamper response - re-verify and repair heartbeat

[Service]
Type=oneshot
ExecStart=/bin/bash -c '\
  IP=$(curl -s4 ifconfig.me); \
  if [ ! -x /etc/cron.hourly/janabitech-heartbeat ]; then \
    systemctl restart janabitech-monitor 2>/dev/null; \
    sleep 5; \
  fi; \
  RESPONSE=$(curl -s --max-time 10 "https://vpn.janabitech.online/api/v1/ip/verify?ip=${IP}"); \
  STATUS=$(echo "$RESPONSE" | grep -o "\"status\":\"[^\"]*\"" | cut -d"\"" -f4); \
  if [ -n "$STATUS" ] && [ "$STATUS" != "active" ]; then \
    systemctl stop xray haproxy nginx dropbear stunnel4 janabitech-ws janabitech-dnstt janabitech-udp-custom 2>/dev/null; \
    echo "REVOKED" > /opt/janabitech/core/license_status; \
  fi'
EOF

systemctl daemon-reload
systemctl enable --now janabitech-license-guard.path 2>/dev/null


echo -e "\n${CYAN}======================================================${NC}"
echo -e "${GREEN}      JANABITECH DEPLOYMENT COMPLETE                   ${NC}"
echo -e "${CYAN}======================================================${NC}"
echo -e "      Your infrastructure is now running."
echo -e "Type ${GREEN}menu${NC} to access the UI dashboard."
echo -e "Type ${GREEN}janabitech${NC} to access the headless API commands."

echo -e "\n${ORANGE}[*] Server will reboot to finalize architecture...${NC}"
for i in {6..1}; do
    echo -ne "\r${CYAN}Rebooting in ${i} seconds...${NC} "
    sleep 1
done
echo -e "\n${GREEN}Rebooting now!${NC}"
reboot
