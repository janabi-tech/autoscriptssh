# File: /opt/janabitech/lib/users.sh
# Purpose: Business logic for user lifecycle.

source /opt/janabitech/core/janabitech.conf 2>/dev/null || true
:
:

sync_xray_users() {
    local config_file="/opt/janabitech/xray/config.json"
    if [ ! -f "$config_file" ]; then return 0; fi

    local raw_vision=$(sqlite3 /opt/janabitech/core/database.db "SELECT '{\"id\":\"' || uuid || '\",\"email\":\"' || username || '\",\"flow\":\"xtls-rprx-vision\"}' FROM users WHERE status='ACTIVE' AND account_type='XRAY';")
    local raw_std=$(sqlite3 /opt/janabitech/core/database.db "SELECT '{\"id\":\"' || uuid || '\",\"email\":\"' || username || '\"}' FROM users WHERE status='ACTIVE' AND account_type='XRAY';")
    local raw_trojan=$(sqlite3 /opt/janabitech/core/database.db "SELECT '{\"password\":\"' || uuid || '\",\"email\":\"' || username || '\"}' FROM users WHERE status='ACTIVE' AND account_type='XRAY';")

    local clients_vision="[$(echo -n "$raw_vision" | paste -sd, -)]"
    local clients_std="[$(echo -n "$raw_std" | paste -sd, -)]"
    local clients_trojan="[$(echo -n "$raw_trojan" | paste -sd, -)]"

    # Fallback to empty array if query was completely empty (paste returns empty string if no input with -n)
    if [ "$clients_vision" == "[]" ] || [ "$clients_vision" == "[ ]" ] || [ -z "$raw_vision" ]; then clients_vision="[]"; fi
    if [ "$clients_std" == "[]" ] || [ "$clients_std" == "[ ]" ] || [ -z "$raw_std" ]; then clients_std="[]"; fi
    if [ "$clients_trojan" == "[]" ] || [ "$clients_trojan" == "[ ]" ] || [ -z "$raw_trojan" ]; then clients_trojan="[]"; fi

    jq --argjson vision "$clients_vision" \
       --argjson standard "$clients_std" \
       --argjson trojan "$clients_trojan" \
       '( .inbounds[] | select(.tag == "vless-reality-gatekeeper") | .settings.clients ) = $vision |
        ( .inbounds[] | select(.tag == "vless-xhttp") | .settings.clients ) = $standard |
        ( .inbounds[] | select(.tag == "vless-ws") | .settings.clients ) = $standard |
        ( .inbounds[] | select(.tag == "vmess-ws") | .settings.clients ) = $standard |
        ( .inbounds[] | select(.tag == "trojan-ws") | .settings.clients ) = $trojan' \
       "$config_file" > "${config_file}.tmp"
       
    if [ $? -eq 0 ]; then
        mv "${config_file}.tmp" "$config_file"
        # Phase 2: Zero-Downtime Xray API Integration
        # Inject the modified configuration directly into memory instantly
        if [ -x "/opt/janabitech/xray/xray" ]; then
            /opt/janabitech/xray/xray api adu -server=127.0.0.1:10085 "$config_file" >/dev/null 2>&1
        fi
    else
        rm -f "${config_file}.tmp"
        log_event "ERROR" "Failed to sync XRAY users to JSON config."
    fi
}

kick_xray_user() {
    local username="$1"
    if [ ! -x "/opt/janabitech/xray/xray" ]; then return 0; fi
    # Instantly sever connections and remove the user from Xray memory across all protocols
    for tag in vless-reality-gatekeeper vless-xhttp vless-ws vmess-ws trojan-ws; do
        /opt/janabitech/xray/xray api rmu -server=127.0.0.1:10085 -tag="$tag" "$username" >/dev/null 2>&1
    done
}

validate_username() {
    local username="$1"
    if [[ ! "$username" =~ ^[a-zA-Z0-9_-]{3,32}$ ]]; then
        log_event "ERROR" "Invalid username '$username'. Use 3-32 alphanumeric chars, hyphens, or underscores only."
        return 1
    fi
}

create_vpn_user() {
    local username="$1"
    local password="$2"
    local days="$3"
    local max_logins="${4:-2}"
    local bw_limit_gb="${5:-0}"
    local account_type="${6:-SSH}"
    validate_username "$username" || return 3
    
    if [[ -z "$username" || -z "$password" || -z "$days" ]]; then
        log_event "ERROR" "Missing arguments for user creation."
        return 1
    fi

    # Check if user already exists in DB
    local exists=$(db_query "SELECT COUNT(*) FROM users WHERE username='$username';")
    if [ "$exists" -gt 0 ]; then
        log_event "WARN" "User $username already exists."
        return 2
    fi

    local exp_date=$(date -d "+${days} days" +"%Y-%m-%d %H:%M:%S")
    local os_exp_date=$(date -d "+${days} days" +"%Y-%m-%d")

    # 1. Create Linux PAM User (Business logic)
    useradd -e "$os_exp_date" -s /bin/false -M "$username" >/dev/null 2>&1
    echo "$username:$password" | chpasswd

    # 2. Insert metadata to SQLite
    local uuid=$(uuidgen)
    local data_limit_bytes=$((bw_limit_gb * 1073741824))
    db_query "INSERT INTO users (username, uuid, expiry_date, max_logins, data_limit, account_type) VALUES ('$username', '$uuid', '$exp_date', $max_logins, $data_limit_bytes, '$account_type');"
    
    log_event "INFO" "Successfully provisioned user: $username for $days days (Max Logins: $max_logins, Limit: ${bw_limit_gb}GB)."
    sync_xray_users
    return 0
}

create_trial_user() {
    local username="$1"
    local password="$2"
    local hours="$3"
    local max_logins="${4:-2}"
    local bw_limit_gb="${5:-0}"
    local account_type="${6:-SSH}"
    validate_username "$username" || return 3

    if [[ -z "$username" || -z "$password" || -z "$hours" ]]; then
        log_event "ERROR" "Missing arguments for trial creation."
        return 1
    fi

    local exp_date=$(date -d "+${hours} hours" +"%Y-%m-%d %H:%M:%S")
    local os_exp_date=$(date -d "+${hours} hours" +"%Y-%m-%d")

    # Native OS Account
    # We do NOT use -e "$os_exp_date" here because if the trial expires today, Linux PAM locks it immediately.
    # Our Python daemon (daemon.py) will precisely enforce the hour/minute expiry anyway.
    useradd -M -s /bin/false "$username" 2>/dev/null
    if [ $? -ne 0 ]; then
        log_event "ERROR" "Failed to create OS user: $username. User may already exist."
        return 2
    fi
    echo "$username:$password" | chpasswd

    # Database Entry (Now includes max_logins)
    local uuid=$(uuidgen)
    local data_limit_bytes=$((bw_limit_gb * 1073741824))
    db_query "INSERT INTO users (username, uuid, expiry_date, max_logins, data_limit, account_type, is_trial) VALUES ('$username', '$uuid', '$exp_date', $max_logins, $data_limit_bytes, '$account_type', 1);"
    
    log_event "INFO" "Successfully provisioned trial user: $username for $hours hours (Max Logins: $max_logins, Limit: ${bw_limit_gb}GB)."
    sync_xray_users
    return 0
}

renew_user() {
    local username="$1"
    local mod_days="$2"

    if [[ -z "$username" || -z "$mod_days" ]]; then
        log_event "ERROR" "Missing arguments for user renewal."
        return 1
    fi

    # 1. Fetch current expiry from database
    local current_expiry=$(db_query "SELECT expiry_date FROM users WHERE username='$username';")
    if [[ -z "$current_expiry" ]]; then
        log_event "ERROR" "User $username not found in database."
        return 2
    fi

    # 2. Bulletproof Date Math (Convert to Epoch seconds, apply math, convert back)
    local current_epoch=$(date -d "$current_expiry" +%s)
    local now_epoch=$(date +%s)
    local base_epoch=$current_epoch
    # If user has already expired, renew starting from now instead of the past expired date
    if [ "$current_epoch" -lt "$now_epoch" ]; then
        base_epoch=$now_epoch
    fi
    local mod_seconds=$(( mod_days * 86400 ))
    local new_epoch=$(( base_epoch + mod_seconds ))
    
    local new_exp_date=$(date -d "@$new_epoch" +"%Y-%m-%d %H:%M:%S")
    local os_exp_date=$(date -d "@$new_epoch" +"%Y-%m-%d")

    # 4. Update the Linux PAM Account and unlock it
    usermod -e "$os_exp_date" "$username" >/dev/null 2>&1
    usermod -U "$username" >/dev/null 2>&1

    # 5. Update the Database
    db_query "UPDATE users SET expiry_date='$new_exp_date', status='ACTIVE' WHERE username='$username';"

    log_event "INFO" "Successfully modified user $username. Expiry shifted by $mod_days days to $new_exp_date."
    sync_xray_users
    return 0
}

delete_vpn_user() {
    local username="$1"
    
    userdel -f "$username" >/dev/null 2>&1
    db_query "DELETE FROM users WHERE username='$username';"
    log_event "INFO" "User $username completely deleted from system."
    sync_xray_users
    kick_xray_user "$username"
    return 0
}
