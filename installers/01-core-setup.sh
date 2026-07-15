# File: /root/janabitech-install/01-core-setup.sh
# Purpose: Bootstraps the environment idempotently.

#!/bin/bash
source /opt/janabitech/lib/installer_utils.sh

log_event "INFO" "Starting Phase 1: Core Infrastructure Setup"

# 1. Scaffolding Directories safely
safe_create_dir "/opt/janabitech/bin"
safe_create_dir "/opt/janabitech/core/keys"
safe_create_dir "/opt/janabitech/lib"
safe_create_dir "/opt/janabitech/logs"
safe_create_dir "/opt/janabitech/services/monitor"

# 2. Idempotent Dependency Installation
PACKAGES=(
    "curl" "wget" "git" "cron" "iptables" "lsof" "tar" "unzip" "uuid-runtime"
    "ca-certificates" "openssl" "sqlite3" "bzip2" "dropbear" "haproxy" "nginx"
    "dante-server" "python3" "vnstat" "socat" "jq"
)

log_event "INFO" "Verifying core dependencies..."
DEBIAN_FRONTEND=noninteractive apt-get update -y > /dev/null 2>&1

# Fix system hostname resolution if missing from /etc/hosts to prevent sudo warnings
CURRENT_HOSTNAME=$(hostname)
if [ -n "$CURRENT_HOSTNAME" ]; then
    if ! grep -q "127.0.0.1 $CURRENT_HOSTNAME" /etc/hosts; then
        echo "127.0.0.1 $CURRENT_HOSTNAME" >> /etc/hosts
    fi
fi
# Network Optimizations (TCP BBR)
cat <<EOF > /etc/sysctl.d/99-janabitech-bbr.conf
net.core.default_qdisc=fq
net.ipv4.tcp_congestion_control=bbr
net.ipv4.ip_forward=1
EOF
sysctl --system >/dev/null 2>&1
for pkg in "${PACKAGES[@]}"; do
    ensure_package "$pkg"
done

log_event "INFO" "Whitelisting VPN user shell..."
if ! grep -qxF '/bin/false' /etc/shells; then
    echo "/bin/false" >> /etc/shells
fi
# 3. Log Rotation Configuration
log_event "INFO" "Setting up log rotation..."
cat <<EOF > /etc/logrotate.d/janabitech
/opt/janabitech/logs/*.log {
    daily
    missingok
    rotate 7
    compress
    delaycompress
    notifempty
    create 0640 root root
}
EOF

# 4. Safe Configuration Generation
CONF_FILE="/opt/janabitech/core/janabitech.conf"
if [ ! -f "$CONF_FILE" ]; then
    log_event "INFO" "Configuration file missing. Initiating interactive setup."
    
    if [ -n "$JANABITECH_DOMAIN" ]; then
        DOMAIN="$JANABITECH_DOMAIN"
        NS_DOMAIN="$JANABITECH_NS_DOMAIN"
        log_event "INFO" "Auto-configuring licensed domain: $DOMAIN"
    else
        read -p "Primary VPN Domain (e.g., vpn.janabitech.online): " DOMAIN < /dev/tty
        read -p "Nameserver Domain (e.g., ns-vpn.janabitech.online): " NS_DOMAIN < /dev/tty
    fi
    
    cat <<EOF > "$CONF_FILE"
# JANABITECH GLOBAL CONFIGURATION
BASE_DIR="/opt/janabitech"
PRIMARY_DOMAIN="$DOMAIN"
NS_DOMAIN="$NS_DOMAIN"
MAX_LOGINS_DEFAULT=2
PORT_SSH=22
PORT_DROPBEAR=109
PORT_DROPBEAR_ALT=143
PORT_WS_HTTP=80
PORT_WS_HTTPS=443
PORT_SOCKS=1080
EOF

    log_event "INFO" "Configuration saved."
else
    log_event "INFO" "Existing configuration found. Sourcing values."
    source "$CONF_FILE"
fi

# 4. Safe Database Initialization
# (Calls the function we wrote in Phase 2)
source /opt/janabitech/lib/db.sh
init_database

log_event "INFO" "Configuring automatic UI dashboard on root login..."
if ! grep -qx "menu" /root/.bashrc; then
    echo -e "\n# Auto-start janabitech Dashboard" >> /root/.bashrc
    echo '[[ $- == *i* ]] && menu' >> /root/.bashrc
fi

# Suppress SSH MOTD banners so the menu starts purely at the top
touch /root/.hushlogin

# Setup Log Rotation
cat <<EOF > /etc/logrotate.d/janabitech
/opt/janabitech/logs/janabitech.log {
    daily
    rotate 7
    compress
    missingok
    notifempty
    copytruncate
}
EOF

log_event "INFO" "Phase 1 Complete."

