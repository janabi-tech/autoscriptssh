# File: /opt/janabitech/lib/system.sh
# Purpose: Core system utilities and logging.

# Safely source config ONLY if it exists (prevents errors on fresh install)
if [ -f /opt/janabitech/core/janabitech.conf ]; then
    source /opt/janabitech/core/janabitech.conf 2>/dev/null || true
fi

# Fallback values for early execution before config is generated
LOG_DIR="${LOG_DIR:-/opt/janabitech/logs}"
DB_PATH="${DB_PATH:-/opt/janabitech/core/database.db}"

# Fix ghost text on some SSH clients (like Termius) by forcing full reset
clear() {
    # Use standard system clear which properly reads terminfo to prevent emulator ghosting
    command clear
}

log_event() {
    local level="$1"
    local message="$2"
    local timestamp=$(date +"%Y-%m-%d %H:%M:%S")
    local log_file="${LOG_DIR}/janabitech.log"
    
    # Ensure log directory exists safely
    mkdir -p "$LOG_DIR"
    
    echo "[$timestamp] [$level] $message" >> "$log_file"
    
    # Print to stdout if running interactively
    if [ -t 1 ]; then
        case "$level" in
            "INFO")  echo -e "\033[0;32m[INFO]\033[0m $message" ;;
            "WARN")  echo -e "\033[0;33m[WARN]\033[0m $message" ;;
            "ERROR") echo -e "\033[0;31m[ERROR]\033[0m $message" ;;
            *)       echo -e "[$level] $message" ;;
        esac
    fi
}

check_root() {
    if [ "${EUID}" -ne 0 ]; then
        log_event "ERROR" "Execution attempted without root privileges."
        exit 1
    fi
}

change_host_domain() {
    local new_domain="$1"
    if [[ -z "$new_domain" ]]; then return 1; fi
    
    # Safely update the global configuration
    sed -i "s/PRIMARY_DOMAIN=.*/PRIMARY_DOMAIN=\"$new_domain\"/" /opt/janabitech/core/janabitech.conf
    log_event "INFO" "Primary Host Domain updated to: $new_domain"
}

change_sni_domain() {
    local new_sni="$1"
    if [[ -z "$new_sni" ]]; then return 1; fi
    
    # 1. Update global config
    if grep -q "REALITY_SNI" /opt/janabitech/core/janabitech.conf; then
        sed -i "s/REALITY_SNI=.*/REALITY_SNI=\"$new_sni\"/" /opt/janabitech/core/janabitech.conf
    else
        echo "REALITY_SNI=\"$new_sni\"" >> /opt/janabitech/core/janabitech.conf
    fi
    source /opt/janabitech/core/janabitech.conf 2>/dev/null || true
    
    # 2. Redeploy Xray to apply the new SNI
    log_event "INFO" "Fetching Xray deployer to apply new SNI..."
    if [[ -n "$GITHUB_TOKEN" ]]; then
        curl -H "Authorization: token ${GITHUB_TOKEN}" -sS -L -o /tmp/04-deploy-xray.sh "https://vpn.janabitech.online/raw/installers/04-deploy-xray.sh"
    else
        curl -sS -L -o /tmp/04-deploy-xray.sh "https://vpn.janabitech.online/raw/installers/04-deploy-xray.sh"
    fi
    if [ -f "/tmp/04-deploy-xray.sh" ] && ! grep -q "404: N[o]t Found" "/tmp/04-deploy-xray.sh"; then
        chmod +x /tmp/04-deploy-xray.sh
        /tmp/04-deploy-xray.sh
        rm -f /tmp/04-deploy-xray.sh
    else
        log_event "ERROR" "Cannot fetch 04-deploy-xray.sh to apply SNI changes."
        return 1
    fi
    
    log_event "INFO" "REALITY SNI Domain updated to $new_sni and Xray restarted."
}

change_ns_domain() {
    local new_ns="$1"
    if [[ -z "$new_ns" ]]; then return 1; fi
    
    # 1. Update global config
    sed -i "s/NS_DOMAIN=.*/NS_DOMAIN=\"$new_ns\"/" /opt/janabitech/core/janabitech.conf
    source /opt/janabitech/core/janabitech.conf 2>/dev/null || true
    
    # 2. Re-write the systemd service to use the new NS domain
    cat <<EOF > /etc/systemd/system/janabitech-dnstt.service
[Unit]
Description=Janabitech DNSTT Server
After=network.target

[Service]
Type=simple
User=root
ExecStart=/opt/janabitech/bin/dnstt-server -udp :5300 -privkey-file /opt/janabitech/core/keys/dnstt.key ${new_ns} 127.0.0.1:${PORT_DROPBEAR}
Restart=always

[Install]
WantedBy=multi-user.target
EOF

    # 3. Apply changes
    systemctl daemon-reload
    systemctl restart janabitech-dnstt
    log_event "INFO" "NS Domain updated to $new_ns and DNSTT Service restarted."
}

renew_ssl_cert() {
    local domain="$1"
    [[ -z "$domain" ]] && domain=$(grep PRIMARY_DOMAIN /opt/janabitech/core/janabitech.conf | cut -d'"' -f2)
    
    log_event "INFO" "Initiating Let's Encrypt SSL generation for: $domain"
    
    # 1. Free Port 80 by killing the WS proxy temporarily
    systemctl stop janabitech-ws haproxy janabitech-xray nginx apache2 >/dev/null 2>&1
    
    # 2. Install acme.sh if not present
    if [ ! -d "/root/.acme.sh" ]; then
        log_event "INFO" "Installing acme.sh client..."
        curl -sL https://get.acme.sh | sh -s email=admin@$domain >/dev/null 2>&1
    fi
    
    local ACME="/root/.acme.sh/acme.sh"
    
    # 3. Issue and Install Certificate
    $ACME --issue -d "$domain" --standalone --server letsencrypt --force \
        --pre-hook "systemctl stop haproxy nginx janabitech-ws 2>/dev/null || true" \
        --post-hook "systemctl start haproxy nginx janabitech-ws 2>/dev/null || true"
    $ACME --installcert -d "$domain" \
        --fullchain-file /opt/janabitech/core/keys/fullchain.cer \
        --key-file /opt/janabitech/core/keys/private.key
        
    # 4. Bundle for HAProxy and Verify
    if [ -s /opt/janabitech/core/keys/fullchain.cer ]; then
        cat /opt/janabitech/core/keys/fullchain.cer /opt/janabitech/core/keys/private.key > /opt/janabitech/core/keys/haproxy.pem
        chmod 600 /opt/janabitech/core/keys/haproxy.pem
        # Keep stunnel.pem for legacy compatibility just in case
        cp /opt/janabitech/core/keys/haproxy.pem /opt/janabitech/core/keys/stunnel.pem
        log_event "INFO" "TLS Certificate successfully bundled and secured."
    else
        log_event "ERROR" "Failed to generate TLS Certificate. Is the domain pointing to this server IP?"
    fi
    
    # 5. Restore Services
    systemctl start janabitech-ws haproxy janabitech-xray
    log_event "INFO" "Data plane services restored."
}

generate_dnstt_key() {
    log_event "INFO" "Generating fresh DNSTT cryptographic keys..."
    cd /opt/janabitech/core/keys
    rm -f dnstt.key dnstt.pub
    
    /opt/janabitech/bin/dnstt-server -gen-key -privkey-file dnstt.key -pubkey-file dnstt.pub
    systemctl restart janabitech-dnstt
    
    log_event "INFO" "New DNSTT keys generated. Public key is ready for client payloads."
}

set_auto_reboot() {
    local input="$1"
    
    # Safely remove any existing Janabitech reboot cron jobs
    crontab -l 2>/dev/null | grep -v "/sbin/reboot" | crontab -
    
    if [[ "$input" =~ ^([0-9]{1,2}):([0-9]{2})$ ]]; then
        local hour="${BASH_REMATCH[1]}"
        local min="${BASH_REMATCH[2]}"
        # Schedule daily reboot at specific time
        (crontab -l 2>/dev/null; echo "$min $hour * * * /sbin/reboot") | crontab -
        log_event "INFO" "Server auto-reboot scheduled for every day at $input."
    elif [[ "$input" =~ ^[0-9]+$ ]] && [ "$input" -gt 0 ]; then
        # Schedule the new reboot (e.g., 0 */6 * * * means minute 0, every 6th hour)
        (crontab -l 2>/dev/null; echo "0 */$input * * * /sbin/reboot") | crontab -
        log_event "INFO" "Server auto-reboot scheduled for every $input hours."
    else
        log_event "INFO" "Server auto-reboot has been disabled."
    fi
}

change_banner() {
    # Open the file directly in nano for the user
    nano /etc/issue.net
    
    # Once the user exits nano, restart daemons to apply changes instantly
    systemctl restart dropbear >/dev/null 2>&1
    systemctl restart ssh >/dev/null 2>&1 || systemctl restart sshd >/dev/null 2>&1
    systemctl restart ssh.socket >/dev/null 2>&1 # Ubuntu 24.04 fix
    
    log_event "INFO" "SSH Banner updated and services restarted successfully."
}

uninstall_script() {
    log_event "WARN" "Initiating complete uninstallation of Janabitech VPN Platform..."
    
    # 1. Stop and Disable all managed services
    local services=(janabitech-ws janabitech-dnstt janabitech-monitor janabitech-udp-custom haproxy janabitech-xray dropbear danted)
    for svc in "${services[@]}"; do
        systemctl stop "$svc" >/dev/null 2>&1
        systemctl disable "$svc" >/dev/null 2>&1
    done
    
    # 2. Remove Systemd Unit Files
    rm -f /etc/systemd/system/janabitech-*.service
    systemctl daemon-reload
    
    # 3. Clean routing rules & accounting chains
    iptables -t nat -D PREROUTING -p udp --dport 53 -j REDIRECT --to-ports 5300 2>/dev/null
    iptables -D INPUT -p udp --dport 5300 -j ACCEPT 2>/dev/null
    iptables -D OUTPUT -j JANABITECH-ACCT 2>/dev/null
    iptables -F JANABITECH-ACCT 2>/dev/null
    iptables -X JANABITECH-ACCT 2>/dev/null
    
    if command -v netfilter-persistent &> /dev/null; then
        netfilter-persistent save >/dev/null 2>&1
    fi
    
    # 4. Remove Bashrc bindings and Global CLI commands
    sed -i '/menu/d' /root/.bashrc
    rm -f /usr/local/bin/janabitech /usr/local/sbin/menu
    
    # Clean up the installer script and heartbeat cron
    rm -f /root/install.sh
    rm -f /etc/cron.hourly/janabitech-heartbeat
    
    # 5. Remove all created VPN users safely from database records
    log_event "INFO" "Removing VPN users..."
    local DB_PATH="/opt/janabitech/core/database.db"
    if [ -f "$DB_PATH" ] && command -v sqlite3 &>/dev/null; then
        for u in $(sqlite3 "$DB_PATH" "SELECT username FROM users;" 2>/dev/null); do
            userdel -f "$u" 2>/dev/null
        done
    fi

    # 6. Clean SSH config
    rm -f /etc/ssh/sshd_config.d/99-janabitech-banner.conf
    sed -i '/Banner \/etc\/issue.net/d' /etc/ssh/sshd_config
    sed -i '/MaxStartups/d' /etc/ssh/sshd_config
    systemctl restart ssh >/dev/null 2>&1 || systemctl restart sshd >/dev/null 2>&1

    log_event "INFO" "Uninstallation complete. Your VPS is now clean."
    log_event "INFO" "Note: Any existing backups were preserved in /root/janabitech_backups_saved."
    
    echo -e "\n${GREEN}[✓] Uninstallation Complete.${NC}"
    echo -e "${ORANGE}[*] Server will reboot to finalize cleanup...${NC}"

    mv /opt/janabitech/backups /root/janabitech_backups_saved 2>/dev/null || true
    rm -rf /opt/janabitech
    
    for i in {6..1}; do
        echo -ne "\r${CYAN}Rebooting in ${i} seconds...${NC} "
        sleep 1
    done
    echo -e "\n${GREEN}Rebooting now!${NC}"
    
    reboot
    exit 0
}

# Move this OUTSIDE to prevent nested function errors
safe_fetch() {
    local repo_url="https://vpn.janabitech.online/raw"
    local file_path="$1"
    local target_path="$2"
    local tmp_dir="/tmp/janabitech_update"
    local filename=$(basename "$file_path")
    
    echo -e "  \033[0;36m-> Fetching ${filename}...\033[0m"
    if [[ -n "$GITHUB_TOKEN" ]]; then
        curl -H "Authorization: token ${GITHUB_TOKEN}" -sS -L -o "$tmp_dir/$filename" "$repo_url/$file_path"
    else
        curl -sS -L -o "$tmp_dir/$filename" "$repo_url/$file_path"
    fi
    
    # regex bracket protects the code from the quine bug
    if [ -s "$tmp_dir/$filename" ] && ! grep -q "404: N[o]t Found" "$tmp_dir/$filename"; then
        cp -f "$tmp_dir/$filename" "$target_path"
        chmod +x "$target_path" 2>/dev/null || true
    else
        log_event "ERROR" "Failed to fetch $file_path. Skipping."
        echo -e "  \033[0;31m[!] Failed to fetch $filename\033[0m"
    fi
}

update_script() {
    log_event "INFO" "Initiating platform update from GitHub..."
    local tmp_dir="/tmp/janabitech_update"

    # Ensure a fresh staging area
    rm -rf "$tmp_dir"
    mkdir -p "$tmp_dir"

    echo -e "\033[0;33m[*] Downloading latest core files...\033[0m"
    
    # 1. Update Core Libraries
    safe_fetch "lib/system.sh" "/opt/janabitech/lib/system.sh"
    safe_fetch "lib/users.sh" "/opt/janabitech/lib/users.sh"
    safe_fetch "lib/services.sh" "/opt/janabitech/lib/services.sh"
    safe_fetch "lib/db.sh" "/opt/janabitech/lib/db.sh"
    safe_fetch "lib/installer_utils.sh" "/opt/janabitech/lib/installer_utils.sh"
    
    # 2. Update APIs and Menus
    safe_fetch "bin/janabitech" "/opt/janabitech/bin/janabitech"
    safe_fetch "menus/main_menu.sh" "/opt/janabitech/menus/main_menu.sh"
    safe_fetch "menus/xray_menu.sh" "/opt/janabitech/menus/xray_menu.sh"
    
    # 3. Update Python Services
    safe_fetch "services/monitor/daemon.py" "/opt/janabitech/services/monitor/daemon.py"
    safe_fetch "services/monitor/telegram-controller.py" "/opt/janabitech/services/monitor/telegram-controller.py"
    safe_fetch "services/routing/ws-proxy.py" "/opt/janabitech/services/routing/ws-proxy.py"
    safe_fetch "services/routing/wss-injector.py" "/opt/janabitech/services/routing/wss-injector.py"

    # 4. Database Migrations (Direct query to avoid infinite sourcing loop)
    echo -e "  \033[0;36m-> Running database migrations...\033[0m"
    local DB_PATH="/opt/janabitech/core/database.db"
    
    local col_exists=$(sqlite3 "$DB_PATH" "PRAGMA table_info(users);" | grep "data_usage")
    if [[ -z "$col_exists" ]]; then
        sqlite3 "$DB_PATH" "ALTER TABLE users ADD COLUMN data_usage BIGINT DEFAULT 0;"
    fi
    
    local type_exists=$(sqlite3 "$DB_PATH" "PRAGMA table_info(users);" | grep "account_type")
    if [[ -z "$type_exists" ]]; then
        sqlite3 "$DB_PATH" "ALTER TABLE users ADD COLUMN account_type TEXT DEFAULT 'SSH';"
    fi
    
    local limit_exists=$(sqlite3 "$DB_PATH" "PRAGMA table_info(users);" | grep "data_limit")
    if [[ -z "$limit_exists" ]]; then
        sqlite3 "$DB_PATH" "ALTER TABLE users ADD COLUMN data_limit BIGINT DEFAULT 0;"
    fi

    # Clean up staging area
    rm -rf "$tmp_dir"

    # Restart background daemons to restore services
    systemctl daemon-reload
    systemctl restart janabitech-ws janabitech-monitor >/dev/null 2>&1

    log_event "INFO" "Platform update complete."
    echo -e "\n\033[0;32m[+] Update applied successfully! System is running the latest version.\033[0m"
}

create_backup() {
    local backup_dir="/opt/janabitech/backups"
    mkdir -p "$backup_dir"
    local timestamp=$(date +"%Y%m%d_%H%M%S")
    local backup_file="$backup_dir/janabitech_backup_$timestamp.tar.gz"
    local encrypted_file="${backup_file}.enc"

    cd /opt/janabitech
    
    # Safely extract VPN users' credentials for backup
    grep "/bin/false" /etc/passwd > core/vpn_passwd.bak 2>/dev/null || true
    grep -f <(awk -F: '/\/bin\/false/{print $1}' /etc/passwd) /etc/shadow > core/vpn_shadow.bak 2>/dev/null || true
    
    # Stage external configs
    mkdir -p core/ext
    [ -f /etc/haproxy/haproxy.cfg ] && cp /etc/haproxy/haproxy.cfg core/ext/haproxy.cfg
    [ -f /etc/issue.net ] && cp /etc/issue.net core/ext/issue.net
    [ -f /etc/xray/domain ] && cp /etc/xray/domain core/ext/xray_domain
    
    local tar_files="core/database.db core/janabitech.conf core/keys/ core/vpn_passwd.bak core/vpn_shadow.bak core/ext/"
    [ -f core/telegram.conf ] && tar_files="$tar_files core/telegram.conf"
    
    tar -czf "$backup_file" $tar_files >/dev/null 2>&1
    
    # Cleanup staging files
    rm -f core/vpn_passwd.bak core/vpn_shadow.bak
    rm -rf core/ext

    echo -e "\n\033[0;36m=== SECURE BACKUP ===\033[0m"
    read -s -p "Enter encryption password: " ENC_PASS
    echo
    read -s -p "Confirm password: " ENC_PASS2
    echo
    
    if [ "$ENC_PASS" != "$ENC_PASS2" ]; then
        echo -e "\033[0;31m[-] Passwords do not match. Aborting.\033[0m"
        rm -f "$backup_file"
        return 1
    fi

    openssl enc -aes-256-cbc -pbkdf2 -in "$backup_file" -out "$encrypted_file" -pass pass:"$ENC_PASS" >/dev/null 2>&1
    rm -f "$backup_file"

    echo -e "\n\033[0;32m[+] Encrypted backup saved to:\033[0m $encrypted_file"
    log_event "INFO" "Encrypted backup created: $encrypted_file"
}

restore_backup() {
    local encrypted_file="$1"
    
    if [ ! -f "$encrypted_file" ]; then
        log_event "ERROR" "Backup file not found: $encrypted_file"
        return 1
    fi

    local temp_archive="/tmp/restored_backup.tar.gz"
    
    if [[ "$encrypted_file" == *.tar.gz ]]; then
        # Unencrypted archive directly
        cp "$encrypted_file" "$temp_archive"
    else
        echo -e "\n\033[0;36m=== DECRYPT BACKUP ===\033[0m"
        read -s -p "Enter decryption password (or your Telegram ADMIN_ID if auto-backup): " ENC_PASS
        echo

        # Attempt decryption
        if ! openssl enc -d -aes-256-cbc -pbkdf2 -in "$encrypted_file" -out "$temp_archive" -pass pass:"$ENC_PASS" 2>/dev/null; then
            echo -e "\033[0;31m[-] Incorrect password or corrupted archive.\033[0m"
            rm -f "$temp_archive"
            return 1
        fi
    fi

    log_event "WARN" "Restoring system state from archive..."
    tar -xzf "$temp_archive" -C /opt/janabitech >/dev/null 2>&1
    rm -f "$temp_archive"

    # Run database migrations in case restoring an older backup
    local DB_PATH="/opt/janabitech/core/database.db"
    if [ -f "$DB_PATH" ]; then
        local col_exists=$(sqlite3 "$DB_PATH" "PRAGMA table_info(users);" | grep "data_usage")
        if [[ -z "$col_exists" ]]; then
            sqlite3 "$DB_PATH" "ALTER TABLE users ADD COLUMN data_usage BIGINT DEFAULT 0;"
        fi
        local limit_exists=$(sqlite3 "$DB_PATH" "PRAGMA table_info(users);" | grep "data_limit")
        if [[ -z "$limit_exists" ]]; then
            sqlite3 "$DB_PATH" "ALTER TABLE users ADD COLUMN data_limit BIGINT DEFAULT 0;"
        fi
        local type_exists=$(sqlite3 "$DB_PATH" "PRAGMA table_info(users);" | grep "account_type")
        if [[ -z "$type_exists" ]]; then
            sqlite3 "$DB_PATH" "ALTER TABLE users ADD COLUMN account_type TEXT DEFAULT 'SSH';"
        fi
    fi

    # Restore VPN Linux users safely
    if [ -f /opt/janabitech/core/vpn_passwd.bak ]; then
        log_event "INFO" "Restoring VPN user system accounts..."
        while IFS= read -r line; do
            local uname=$(echo "$line" | cut -d: -f1)
            # Remove user if they already exist to prevent duplicates
            if grep -q "^$uname:" /etc/passwd; then
                userdel -f "$uname" 2>/dev/null
            fi
            echo "$line" >> /etc/passwd
        done < /opt/janabitech/core/vpn_passwd.bak
        rm -f /opt/janabitech/core/vpn_passwd.bak
    fi

    if [ -f /opt/janabitech/core/vpn_shadow.bak ]; then
        while IFS= read -r line; do
            local uname=$(echo "$line" | cut -d: -f1)
            sed -i "/^$uname:/d" /etc/shadow
            echo "$line" >> /etc/shadow
        done < /opt/janabitech/core/vpn_shadow.bak
        rm -f /opt/janabitech/core/vpn_shadow.bak
    fi

    # Restore External Configs
    if [ -d /opt/janabitech/core/ext ]; then
        # Note: We deliberately skip restoring haproxy.cfg to prevent breaking routing updates
        [ -f /opt/janabitech/core/ext/issue.net ] && cp /opt/janabitech/core/ext/issue.net /etc/issue.net
        [ -f /opt/janabitech/core/ext/xray_domain ] && cp /opt/janabitech/core/ext/xray_domain /etc/xray/domain
        rm -rf /opt/janabitech/core/ext
    fi

    chmod 600 /opt/janabitech/core/keys/* 2>/dev/null || true
    systemctl restart janabitech-ws janabitech-dnstt haproxy dropbear >/dev/null 2>&1
    
    # Crucial: Re-generate Xray config so it uses the RESTORED Reality private keys
    if [[ -n "$GITHUB_TOKEN" ]]; then
        curl -H "Authorization: token ${GITHUB_TOKEN}" -sS -L -o /tmp/04-deploy-xray.sh "https://vpn.janabitech.online/raw/installers/04-deploy-xray.sh"
    else
        curl -sS -L -o /tmp/04-deploy-xray.sh "https://vpn.janabitech.online/raw/installers/04-deploy-xray.sh"
    fi
    if [ -f "/tmp/04-deploy-xray.sh" ]; then
        bash /tmp/04-deploy-xray.sh >/dev/null 2>&1
        rm -f /tmp/04-deploy-xray.sh
    fi
    
    :
    sync_xray_users
    
    # Guarantee Xray picks up the newly synced users if the dynamic API injection was too fast
    systemctl restart janabitech-xray >/dev/null 2>&1
    
    log_event "INFO" "System state successfully restored."
}

install_fail2ban() {
    log_event "INFO" "Initiating Fail2Ban deployment..."

    # 1. Install the package if missing
    if ! command -v fail2ban-server &> /dev/null; then
        echo -e "\033[0;33m[*] Installing Fail2Ban package (this may take a moment)...\033[0m"
        export DEBIAN_FRONTEND=noninteractive
        apt-get update >/dev/null 2>&1
        apt-get install -y fail2ban iptables python3-systemd >/dev/null 2>&1
    fi

    # 2. Deploy the custom Jail configuration
    echo -e "\033[0;36m[*] Writing strict SSH security rules...\033[0m"
    cat <<EOF > /etc/fail2ban/jail.local
[DEFAULT]
bantime  = 1h
findtime = 10m
maxretry = 3
banaction = iptables-multiport

[sshd]
enabled = true
port    = ${PORT_SSH:-22}
backend = systemd
EOF

    # 3. Apply and start the bouncer
    systemctl daemon-reload
    systemctl enable fail2ban >/dev/null 2>&1
    systemctl restart fail2ban >/dev/null 2>&1

    log_event "INFO" "Fail2Ban successfully configured to protect OpenSSH."
    echo -e "\n\033[0;32m[+] Deployment complete! Fail2Ban is now actively terminating botnets.\033[0m"
}

backup_telegram() {
    local telegram_conf="/opt/janabitech/core/telegram.conf"
    if [ ! -f "$telegram_conf" ]; then
        echo -e "\033[0;31m[-] Telegram bot is not configured. Please configure it in Settings first.\033[0m"
        return 1
    fi

    source "$telegram_conf"
    
    # Strip any potential Windows carriage returns
    BOT_TOKEN=$(echo "$BOT_TOKEN" | tr -d '\r')
    ADMIN_ID=$(echo "$ADMIN_ID" | tr -d '\r')
    GDRIVE_WEBAPP_URL=$(echo "$GDRIVE_WEBAPP_URL" | tr -d '\r')
    JANABITECH_BACKUP_URL=$(echo "$JANABITECH_BACKUP_URL" | tr -d '\r' | sed 's:/*$::')
    JANABITECH_NODE_KEY=$(echo "$JANABITECH_NODE_KEY" | tr -d '\r')

    if [ -z "$BOT_TOKEN" ] || [ -z "$ADMIN_ID" ]; then
        echo -e "\033[0;31m[-] Invalid Telegram configuration.\033[0m"
        return 1
    fi

    local backup_dir="/opt/janabitech/backups"
    mkdir -p "$backup_dir"
    local timestamp=$(date +"%Y%m%d_%H%M%S")
    local backup_file="$backup_dir/janabitech_backup_$timestamp.tar.gz"

    cd /opt/janabitech
    grep "/bin/false" /etc/passwd > core/vpn_passwd.bak 2>/dev/null || true
    grep -f <(awk -F: '/\/bin\/false/{print $1}' /etc/passwd) /etc/shadow > core/vpn_shadow.bak 2>/dev/null || true
    
    mkdir -p core/ext
    [ -f /etc/haproxy/haproxy.cfg ] && cp /etc/haproxy/haproxy.cfg core/ext/haproxy.cfg
    [ -f /etc/issue.net ] && cp /etc/issue.net core/ext/issue.net
    [ -f /etc/xray/domain ] && cp /etc/xray/domain core/ext/xray_domain
    
    local tar_files="core/database.db core/janabitech.conf core/keys/ core/vpn_passwd.bak core/vpn_shadow.bak core/ext/"
    [ -f core/telegram.conf ] && tar_files="$tar_files core/telegram.conf"
    
    tar -czf "$backup_file" $tar_files >/dev/null 2>&1
    rm -f core/vpn_passwd.bak core/vpn_shadow.bak
    rm -rf core/ext

    # Encrypt the backup using ADMIN_ID as the password
    local encrypted_file="${backup_file}.enc"
    openssl enc -aes-256-cbc -pbkdf2 -in "$backup_file" -out "$encrypted_file" -pass pass:"$ADMIN_ID" >/dev/null 2>&1
    rm -f "$backup_file"

    local cloud_link=""
    
    if [ -n "$JANABITECH_BACKUP_URL" ]; then
        # Centralized JanabiTech Backup Server (FileStation)
        local response_imagi
        local base_name=$(basename "$encrypted_file")
        # Uploading via secure Node Key API (Supported by the new FileStation backend)
        response_imagi=$(curl -s -X POST \
                              -H "X-Node-Key: ${JANABITECH_NODE_KEY}" \
                              -H "X-File-Name: ${base_name}" \
                              --data-binary "@${encrypted_file}" \
                              "${JANABITECH_BACKUP_URL}/_api/node_upload")
        
        # The backend returns JSON with the actual URL (it appends a random suffix for security)
        # e.g., {"ok": true, "url": "https://..."}
        cloud_link=$(echo "$response_imagi" | grep -o '"url": *"[^"]*"' | cut -d'"' -f4)
        
        # Fallback just in case parsing fails
        if [ -z "$cloud_link" ]; then
            cloud_link="${JANABITECH_BACKUP_URL}/${base_name}"
        fi
    elif [ -n "$GDRIVE_WEBAPP_URL" ]; then
        # Google Drive via Apps Script Web App
        local response_gdrive
        response_gdrive=$(curl -sL "$GDRIVE_WEBAPP_URL" -F "file=@$encrypted_file")
        cloud_link=$(echo "$response_gdrive" | grep -o 'https://drive.google.com/uc?export=download&id=[^" }]*' | head -n 1)
    fi

    if [ -z "$cloud_link" ]; then
        # Fallback to uguu.se for instant cloud link
        local response_uguu
        response_uguu=$(curl -sF "files[]=@$encrypted_file" https://uguu.se/upload.php 2>/dev/null)
        cloud_link=$(echo "$response_uguu" | grep -o '"url":"[^"]*' | cut -d'"' -f4 | sed 's/\\//g')
    fi

    local server_ip=$(curl -sS ifconfig.me 2>/dev/null || echo "Unknown IP")
    local domain_val=$(cat /etc/xray/domain 2>/dev/null || grep '^PRIMARY_DOMAIN=' /opt/janabitech/core/janabitech.conf 2>/dev/null | cut -d'"' -f2 | head -n1 || echo "Unknown Domain")

    local caption="📦 Manual System Backup
🌍 Server IP: ${server_ip}
🌐 Domain: ${domain_val}
🕒 Date & Time: $(date +"%Y-%m-%d %H:%M:%S")

🔑 Password: Your Telegram ADMIN_ID
☁️ Cloud Link: ${cloud_link:-Failed to upload to cloud}

Thank you for using JanabiTech AutoScript Pro! 🚀"

    # Determine if it's called from cron or user
    if [ "$1" == "cron" ]; then
        caption="🔄 Auto System Backup
🌍 Server IP: ${server_ip}
🌐 Domain: ${domain_val}
🕒 Date & Time: $(date +"%Y-%m-%d %H:%M:%S")

🔑 Password: Your Telegram ADMIN_ID
☁️ Cloud Link: ${cloud_link:-Failed to upload to cloud}

Thank you for using JanabiTech AutoScript Pro! 🚀"
        curl -s -F "document=@$encrypted_file" \
                -F "chat_id=$ADMIN_ID" \
                -F "caption=$caption" \
                "https://api.telegram.org/bot${BOT_TOKEN}/sendDocument" >/dev/null
    else
        echo -e "\n\033[0;36m[*] Uploading to Cloud and Telegram Bot...\033[0m"
        local response
        response=$(curl -s -w "\nHTTP_STATUS:%{http_code}" \
            -F "document=@$encrypted_file" \
            -F "chat_id=$ADMIN_ID" \
            -F "caption=$caption" \
            "https://api.telegram.org/bot${BOT_TOKEN}/sendDocument")
        
        if echo "$response" | grep -q '"ok":true'; then
            echo -e "\033[0;32m[+] Backup sent successfully!\033[0m"
            if [ -n "$cloud_link" ]; then
                echo -e "\033[0;32m[+] Cloud Link generated: $cloud_link\033[0m"
            fi
        else
            echo -e "\033[0;31m[-] Failed to send backup. Telegram API Response:\033[0m"
            echo "$response"
        fi
    fi
}


auto_backup_cron() {
    local opt="$1"
    if [ "$opt" == "0" ]; then
        crontab -l | grep -v 'sys backup_telegram cron' | crontab -
        echo -e "\033[0;32m[+] Auto Backup disabled.\033[0m"
        return 0
    fi
    
    local cron_expr=""
    case $opt in
        1) cron_expr="0 0 * * *" ;; # Daily at midnight
        2) cron_expr="0 0 * * 0" ;; # Weekly on Sunday
        *) echo "Invalid"; return 1 ;;
    esac

    crontab -l | grep -v 'sys backup_telegram cron' > /tmp/crontab.bak
    echo "$cron_expr /opt/janabitech/bin/janabitech sys backup_telegram cron >/dev/null 2>&1" >> /tmp/crontab.bak
    crontab /tmp/crontab.bak
    rm -f /tmp/crontab.bak
    echo -e "\033[0;32m[+] Auto Backup Schedule configured successfully.\033[0m"
}
