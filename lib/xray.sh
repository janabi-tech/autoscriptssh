# File: /opt/janabitech/lib/xray.sh
# Purpose: Xray-core manager (vmess / vless / trojan over ws-nontls / ws-tls / grpc).
#          Reuses the SAME domain + Let's Encrypt SSL certificate that the SSH
#          stack already provisions in /opt/janabitech/core/keys/.

# FIX: Guard the config source so xray.sh can be sourced on a half-installed
#      box without aborting (system.sh already does this; xray.sh did not).
[ -f /opt/janabitech/core/janabitech.conf ] && source /opt/janabitech/core/janabitech.conf
source /opt/janabitech/lib/system.sh
source /opt/janabitech/lib/db.sh
# FIX: installer_utils.sh provides safe_deploy_systemd() and ensure_package()
#      used by xray_install(). Source it here as well so that any caller of
#      xray.sh (bin/janabitech, menus, etc.) has these helpers available.
[ -f /opt/janabitech/lib/installer_utils.sh ] && source /opt/janabitech/lib/installer_utils.sh

# ----------------------------------------------------------------------
# Constants – DO NOT CHANGE without also updating the inbound generator.
# Port layout (Cloudflare-friendly where possible):
#   vmess  ws  (no TLS)  -> 8080
#   vmess  ws  (TLS)     -> 2053
#   vmess  grpc (TLS)    -> 2087
#   vless  ws  (no TLS)  -> 2052
#   vless  ws  (TLS)     -> 2083
#   vless  grpc (TLS)    -> 8443
#   trojan ws  (no TLS)  -> 2082
#   trojan ws  (TLS)     -> 2096
#   trojan grpc (TLS)    -> 10008
# ----------------------------------------------------------------------
XRAY_BIN="/opt/janabitech/bin/xray"
XRAY_DIR="/opt/janabitech/xray"
XRAY_CONF="${XRAY_DIR}/config.json"
XRAY_ACCESS_LOG="/opt/janabitech/logs/xray-access.log"
XRAY_ERROR_LOG="/opt/janabitech/logs/xray-error.log"
XRAY_SERVICE="janabitech-xray"
XRAY_GEO_DIR="${XRAY_DIR}/geo"

XRAY_VERSION="v25.2.21"

# Cloudflare-friendly port assignments (kept in a single source of truth)
declare -A XRAY_PORTS=(
    [vmess_ws_nontls]=8080
    [vmess_ws_tls]=2053
    [vmess_grpc]=2087
    [vless_ws_nontls]=2052
    [vless_ws_tls]=2083
    [vless_grpc]=8443
    [trojan_ws_nontls]=2082
    [trojan_ws_tls]=2096
    [trojan_grpc]=10008
)

# WS path per protocol (used for both tls and non-tls variants of the same protocol)
declare -A XRAY_WS_PATH=(
    [vmess]="/vmess"
    [vless]="/vless"
    [trojan]="/trojan"
)

# gRPC serviceName per protocol
declare -A XRAY_GRPC_SVC=(
    [vmess]="vmess-grpc"
    [vless]="vless-grpc"
    [trojan]="trojan-grpc"
)

# ----------------------------------------------------------------------
# Helpers
# ----------------------------------------------------------------------
xray_log() {
    local level="$1"; shift
    local msg="$*"
    log_event "$level" "[XRAY] $msg"
    if [ -t 1 ]; then
        case "$level" in
            INFO)  echo -e "\033[0;32m[XRAY]\033[0m $msg" ;;
            WARN)  echo -e "\033[0;33m[XRAY]\033[0m $msg" ;;
            ERROR) echo -e "\033[0;31m[XRAY]\033[0m $msg" ;;
            *)     echo "[XRAY] $msg" ;;
        esac
    fi
}

xray_validate_username() {
    local username="$1"
    if [[ ! "$username" =~ ^[a-zA-Z0-9_-]{3,32}$ ]]; then
        xray_log "ERROR" "Invalid username '$username'. Use 3-32 alphanumeric, hyphens or underscores."
        return 1
    fi
    # FIX: explicit success (previously relied on the implicit exit status of
    #      the `if` block, which is fragile across bash versions).
    return 0
}

xray_validate_protocol() {
    local p="$1"
    case "$p" in
        vmess|vless|trojan) return 0 ;;
        *) xray_log "ERROR" "Unknown protocol '$p' (expected: vmess|vless|trojan)."; return 1 ;;
    esac
}

# parse_duration <value> <unit>
#   unit must be: minutes | hours | days
# echoes absolute expiry timestamp (YYYY-MM-DD HH:MM:SS) on stdout
xray_compute_expiry() {
    local value="$1"
    local unit="$2"

    if [[ -z "$value" || -z "$unit" ]]; then
        xray_log "ERROR" "Duration value and unit are required."
        return 1
    fi
    if ! [[ "$value" =~ ^-?[0-9]+$ ]]; then
        xray_log "ERROR" "Duration must be an integer (got '$value')."
        return 1
    fi

    case "$unit" in
        minutes|minute|min|m)  date -d "+${value} minutes" +"%Y-%m-%d %H:%M:%S" ;;
        hours|hour|hr|h)       date -d "+${value} hours"   +"%Y-%m-%d %H:%M:%S" ;;
        days|day|d)            date -d "+${value} days"    +"%Y-%m-%d %H:%M:%S" ;;
        *) xray_log "ERROR" "Unknown unit '$unit' (use: minutes|hours|days)."; return 1 ;;
    esac
}

# apply_delta_expiry <current_expiry> <value> <unit>
xray_apply_delta() {
    local current="$1"
    local value="$2"
    local unit="$3"

    local cur_epoch
    cur_epoch=$(date -d "$current" +%s 2>/dev/null) || {
        xray_log "ERROR" "Cannot parse existing expiry '$current'."
        return 1
    }

    local delta_seconds=0
    case "$unit" in
        minutes|minute|min|m)  delta_seconds=$(( value * 60 )) ;;
        hours|hour|hr|h)       delta_seconds=$(( value * 3600 )) ;;
        days|day|d)            delta_seconds=$(( value * 86400 )) ;;
        *) xray_log "ERROR" "Unknown unit '$unit' (use: minutes|hours|days)."; return 1 ;;
    esac

    # FIX: If the account is already expired, renew from NOW instead of from
    #      the old (past) expiry. Without this, renewing an expired user by
    #      N days produced an expiry that was still in the past, so the next
    #      purge-expired cron tick immediately re-expired the account.
    local now_epoch
    now_epoch=$(date +%s)
    local base_epoch=$cur_epoch
    if [ "$cur_epoch" -lt "$now_epoch" ]; then
        base_epoch=$now_epoch
    fi

    local new_epoch=$(( base_epoch + delta_seconds ))
    date -d "@$new_epoch" +"%Y-%m-%d %H:%M:%S"
}

# ----------------------------------------------------------------------
# Binary installation
# ----------------------------------------------------------------------
xray_detect_arch() {
    local arch
    arch=$(uname -m)
    case "$arch" in
        x86_64|amd64) echo "64" ;;
        i386|i686)    echo "32" ;;
        aarch64|arm64) echo "arm64-v8a" ;;
        armv7l|armv6l) echo "arm32-v7a" ;;
        *) echo "unsupported" ;;
    esac
}

xray_install_binary() {
    if [ -x "$XRAY_BIN" ]; then
        xray_log "INFO" "Xray binary already present at $XRAY_BIN"
        return 0
    fi

    local arch
    arch=$(xray_detect_arch)
    if [ "$arch" == "unsupported" ]; then
        xray_log "ERROR" "Unsupported architecture: $(uname -m)"
        return 1
    fi

    mkdir -p /opt/janabitech/bin "$XRAY_GEO_DIR"
    local tmp="/tmp/xray-core-${XRAY_VERSION}.zip"
    local extract_dir="/tmp/xray-extract"
    local url="https://github.com/XTLS/Xray-core/releases/download/${XRAY_VERSION}/Xray-linux-${arch}.zip"

    # FIX: ensure wget is available (it is part of the base PACKAGES list,
    #      but xray_install can be invoked standalone via the menu).
    if ! command -v wget >/dev/null 2>&1; then
        DEBIAN_FRONTEND=noninteractive apt-get install -y wget >/dev/null 2>&1 || true
    fi

    xray_log "INFO" "Downloading Xray-core ${XRAY_VERSION} (${arch}) ..."
    if ! wget -qO "$tmp" "$url"; then
        xray_log "ERROR" "Download failed: $url"
        rm -f "$tmp"
        return 1
    fi

    # FIX: clean any stale extraction dir from a previous failed run BEFORE
    #      unzipping so we don't mix old arch files with the new ones.
    rm -rf "$extract_dir"
    if ! unzip -o -q "$tmp" -d "$extract_dir"; then
        xray_log "ERROR" "Unzip failed."
        rm -f "$tmp" ; rm -rf "$extract_dir"
        return 1
    fi

    if [ ! -f "$extract_dir/xray" ]; then
        xray_log "ERROR" "Downloaded archive did not contain the xray binary (URL may be wrong: $url)."
        rm -rf "$extract_dir" "$tmp"
        return 1
    fi

    mv -f "$extract_dir/xray" "$XRAY_BIN"
    chmod +x "$XRAY_BIN"

    # Geosite/Geoip data files (best-effort – not fatal if missing).
    # The bundled config.json references geoip:private which Xray-core
    # resolves from geoip.dat; if missing, Xray falls back to built-in
    # private CIDRs so it still boots.
    if [ -f "$extract_dir/geoip.dat" ]; then
        mv -f "$extract_dir/geoip.dat" "${XRAY_GEO_DIR}/geoip.dat"
    fi
    if [ -f "$extract_dir/geosite.dat" ]; then
        mv -f "$extract_dir/geosite.dat" "${XRAY_GEO_DIR}/geosite.dat"
    fi

    rm -rf "$extract_dir" "$tmp"
    xray_log "INFO" "Xray binary installed: $("$XRAY_BIN" version 2>/dev/null | head -n1)"
}

xray_install_systemd() {
    # FIX: write the temp unit file with mode 600 so a non-root user on the
    #      box cannot swap it before safe_deploy_systemd moves it into place.
    local tmp_unit="/tmp/${XRAY_SERVICE}.service.tmp"
    umask 077
    cat <<EOF > "$tmp_unit"
[Unit]
Description=Janabitech Xray-core (vmess/vless/trojan over ws-nontls/ws-tls/grpc)
After=network.target stunnel4.service
Wants=network.target

[Service]
Type=simple
User=root
WorkingDirectory=${XRAY_DIR}
ExecStart=${XRAY_BIN} run -config ${XRAY_CONF}
Restart=on-failure
RestartSec=3
LimitNOFILE=1048576
AmbientCapabilities=CAP_NET_BIND_SERVICE
CapabilityBoundingSet=CAP_NET_BIND_SERVICE

[Install]
WantedBy=multi-user.target
EOF
    umask 022
    safe_deploy_systemd "$XRAY_SERVICE"
}

xray_install() {
    xray_log "INFO" "Installing Xray-core manager ..."

    mkdir -p "$XRAY_DIR" "$XRAY_GEO_DIR" "$(dirname "$XRAY_ACCESS_LOG")" "$(dirname "$XRAY_ERROR_LOG")"

    # FIX: make sure unzip + openssl are present. 05-deploy-xray.sh calls
    #      ensure_package("unzip") before us, but 'janabitech xray install'
    #      from the menu skips that, so we self-provision here.
    local dep
    for dep in unzip openssl; do
        if ! command -v "$dep" >/dev/null 2>&1; then
            xray_log "INFO" "Installing missing dependency: $dep"
            DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends "$dep" >/dev/null 2>&1 || {
                xray_log "ERROR" "Cannot install $dep — apt-get failed."
                return 1
            }
        fi
    done

    # FIX: open firewall ports BEFORE deploying the systemd unit so the
    #      service is reachable the moment it starts. Also guard the ufw
    #      call so we don't error out on systems without ufw installed.
    local p
    if command -v ufw >/dev/null 2>&1; then
        for p in "${XRAY_PORTS[@]}"; do
            ufw allow "${p}/tcp" >/dev/null 2>&1 || true
        done
    fi

    xray_install_binary   || return 1
    xray_generate_config  || return 1
    xray_install_systemd  || return 1

    # FIX: safe_deploy_systemd skips restart when the unit file is unchanged,
    #      which means a re-install never reloads the freshly regenerated
    #      config.json. Always restart here so the new config takes effect.
    systemctl restart "$XRAY_SERVICE" >/dev/null 2>&1 || true

    xray_log "INFO" "Xray-core deployed. Manage via 'janabitech xray ...' or menu option 09."
}

xray_uninstall() {
    xray_log "WARN" "Removing Xray-core and all xray accounts ..."

    systemctl stop "$XRAY_SERVICE" >/dev/null 2>&1
    systemctl disable "$XRAY_SERVICE" >/dev/null 2>&1
    rm -f "/etc/systemd/system/${XRAY_SERVICE}.service"
    systemctl daemon-reload

    # FIX: remove the 'xray purge-expired' cron entry that 05-deploy-xray.sh
    #      added. Without this, cron kept invoking 'janabitech xray
    #      purge-expired' every 5 minutes against the now-dropped table,
    #      silently logging errors forever.
    crontab -l 2>/dev/null | grep -v "xray purge-expired" | crontab - 2>/dev/null || true

    rm -rf "$XRAY_DIR" "$XRAY_BIN"

    sqlite3 "$DB_PATH" "DROP TABLE IF EXISTS xray_users;" 2>/dev/null
    sqlite3 "$DB_PATH" "DROP TABLE IF EXISTS xray_meta;" 2>/dev/null

    xray_log "INFO" "Xray-core removed."
}

# ----------------------------------------------------------------------
# Config (JSON) generator
# ----------------------------------------------------------------------
# Helper: emit a JSON-safe string
json_escape() {
    # Reads stdin, returns escaped string content (without surrounding quotes)
    sed -e 's/\\/\\\\/g' -e 's/"/\\"/g'
}

# Generate the full xray config.json with all 9 inbounds and ALL current users.
xray_generate_config() {
    mkdir -p "$XRAY_DIR"

    local cert_file="/opt/janabitech/core/keys/fullchain.cer"
    local key_file="/opt/janabitech/core/keys/private.key"

    # Fallback to self-signed if Let's Encrypt not yet issued (keeps xray bootable)
    if [ ! -s "$cert_file" ] || [ ! -s "$key_file" ]; then
        xray_log "WARN" "TLS cert/key not found – generating self-signed fallback so Xray can boot."
        mkdir -p "$(dirname "$cert_file")"
        openssl req -x509 -nodes -days 3650 -newkey rsa:2048 \
            -keyout "$key_file" -out "$cert_file" \
            -subj "/CN=${PRIMARY_DOMAIN:-localhost}" >/dev/null 2>&1
        # FIX: actually verify the openssl call produced non-empty cert/key
        #      files. Previously, if openssl was missing or failed silently,
        #      the config.json referenced empty files and Xray crashed on
        #      boot with a confusing TLS error.
        if [ ! -s "$cert_file" ] || [ ! -s "$key_file" ]; then
            xray_log "ERROR" "Self-signed cert generation failed (openssl error). Cannot continue."
            return 1
        fi
        chmod 600 "$key_file" "$cert_file"
    fi

    # Build client arrays per protocol
    local vmess_clients vless_clients trojan_clients
    vmess_clients=$(xray_build_clients_json vmess)
    vless_clients=$(xray_build_clients_json vless)
    trojan_clients=$(xray_build_clients_json trojan)

    cat > "$XRAY_CONF" <<JSON
{
  "log": {
    "loglevel": "warning",
    "access": "${XRAY_ACCESS_LOG}",
    "error": "${XRAY_ERROR_LOG}"
  },
  "dns": {
    "servers": ["1.1.1.1", "8.8.8.8", "localhost"]
  },
  "inbounds": [
    {
      "tag": "vmess-ws-nontls",
      "listen": "0.0.0.0",
      "port": ${XRAY_PORTS[vmess_ws_nontls]},
      "protocol": "vmess",
      "settings": {
        "clients": [${vmess_clients}],
        "decryption": "none"
      },
      "streamSettings": {
        "network": "ws",
        "wsSettings": {
          "path": "${XRAY_WS_PATH[vmess]}"
        }
      },
      "sniffing": { "enabled": true, "destOverride": ["http","tls"] }
    },
    {
      "tag": "vmess-ws-tls",
      "listen": "0.0.0.0",
      "port": ${XRAY_PORTS[vmess_ws_tls]},
      "protocol": "vmess",
      "settings": {
        "clients": [${vmess_clients}],
        "decryption": "none"
      },
      "streamSettings": {
        "network": "ws",
        "security": "tls",
        "tlsSettings": {
          "serverName": "${PRIMARY_DOMAIN}",
          "certificates": [
            { "certificateFile": "${cert_file}", "keyFile": "${key_file}" }
          ]
        },
        "wsSettings": {
          "path": "${XRAY_WS_PATH[vmess]}"
        }
      },
      "sniffing": { "enabled": true, "destOverride": ["http","tls"] }
    },
    {
      "tag": "vmess-grpc",
      "listen": "0.0.0.0",
      "port": ${XRAY_PORTS[vmess_grpc]},
      "protocol": "vmess",
      "settings": {
        "clients": [${vmess_clients}],
        "decryption": "none"
      },
      "streamSettings": {
        "network": "grpc",
        "security": "tls",
        "tlsSettings": {
          "serverName": "${PRIMARY_DOMAIN}",
          "certificates": [
            { "certificateFile": "${cert_file}", "keyFile": "${key_file}" }
          ]
        },
        "grpcSettings": {
          "serviceName": "${XRAY_GRPC_SVC[vmess]}"
        }
      },
      "sniffing": { "enabled": true, "destOverride": ["http","tls"] }
    },
    {
      "tag": "vless-ws-nontls",
      "listen": "0.0.0.0",
      "port": ${XRAY_PORTS[vless_ws_nontls]},
      "protocol": "vless",
      "settings": {
        "clients": [${vless_clients}],
        "decryption": "none"
      },
      "streamSettings": {
        "network": "ws",
        "wsSettings": {
          "path": "${XRAY_WS_PATH[vless]}"
        }
      },
      "sniffing": { "enabled": true, "destOverride": ["http","tls"] }
    },
    {
      "tag": "vless-ws-tls",
      "listen": "0.0.0.0",
      "port": ${XRAY_PORTS[vless_ws_tls]},
      "protocol": "vless",
      "settings": {
        "clients": [${vless_clients}],
        "decryption": "none"
      },
      "streamSettings": {
        "network": "ws",
        "security": "tls",
        "tlsSettings": {
          "serverName": "${PRIMARY_DOMAIN}",
          "certificates": [
            { "certificateFile": "${cert_file}", "keyFile": "${key_file}" }
          ]
        },
        "wsSettings": {
          "path": "${XRAY_WS_PATH[vless]}"
        }
      },
      "sniffing": { "enabled": true, "destOverride": ["http","tls"] }
    },
    {
      "tag": "vless-grpc",
      "listen": "0.0.0.0",
      "port": ${XRAY_PORTS[vless_grpc]},
      "protocol": "vless",
      "settings": {
        "clients": [${vless_clients}],
        "decryption": "none"
      },
      "streamSettings": {
        "network": "grpc",
        "security": "tls",
        "tlsSettings": {
          "serverName": "${PRIMARY_DOMAIN}",
          "certificates": [
            { "certificateFile": "${cert_file}", "keyFile": "${key_file}" }
          ]
        },
        "grpcSettings": {
          "serviceName": "${XRAY_GRPC_SVC[vless]}"
        }
      },
      "sniffing": { "enabled": true, "destOverride": ["http","tls"] }
    },
    {
      "tag": "trojan-ws-nontls",
      "listen": "0.0.0.0",
      "port": ${XRAY_PORTS[trojan_ws_nontls]},
      "protocol": "trojan",
      "settings": {
        "clients": [${trojan_clients}]
      },
      "streamSettings": {
        "network": "ws",
        "wsSettings": {
          "path": "${XRAY_WS_PATH[trojan]}"
        }
      },
      "sniffing": { "enabled": true, "destOverride": ["http","tls"] }
    },
    {
      "tag": "trojan-ws-tls",
      "listen": "0.0.0.0",
      "port": ${XRAY_PORTS[trojan_ws_tls]},
      "protocol": "trojan",
      "settings": {
        "clients": [${trojan_clients}]
      },
      "streamSettings": {
        "network": "ws",
        "security": "tls",
        "tlsSettings": {
          "serverName": "${PRIMARY_DOMAIN}",
          "certificates": [
            { "certificateFile": "${cert_file}", "keyFile": "${key_file}" }
          ]
        },
        "wsSettings": {
          "path": "${XRAY_WS_PATH[trojan]}"
        }
      },
      "sniffing": { "enabled": true, "destOverride": ["http","tls"] }
    },
    {
      "tag": "trojan-grpc",
      "listen": "0.0.0.0",
      "port": ${XRAY_PORTS[trojan_grpc]},
      "protocol": "trojan",
      "settings": {
        "clients": [${trojan_clients}]
      },
      "streamSettings": {
        "network": "grpc",
        "security": "tls",
        "tlsSettings": {
          "serverName": "${PRIMARY_DOMAIN}",
          "certificates": [
            { "certificateFile": "${cert_file}", "keyFile": "${key_file}" }
          ]
        },
        "grpcSettings": {
          "serviceName": "${XRAY_GRPC_SVC[trojan]}"
        }
      },
      "sniffing": { "enabled": true, "destOverride": ["http","tls"] }
    }
  ],
  "outbounds": [
    { "protocol": "freedom", "tag": "direct", "settings": { "domainStrategy": "UseIPv4" } },
    { "protocol": "blackhole", "tag": "blocked", "settings": { "response": { "type": "http" } } }
  ],
  "routing": {
    "domainStrategy": "AsIs",
    "rules": [
      { "type": "field", "outboundTag": "blocked", "ip": ["geoip:private"] }
    ]
  }
}
JSON

    # Validate config (if xray binary present)
    if [ -x "$XRAY_BIN" ]; then
        if ! "$XRAY_BIN" run -test -config "$XRAY_CONF" >/dev/null 2>&1; then
            xray_log "ERROR" "Generated config failed validation. Check $XRAY_CONF"
            return 1
        fi
    fi
    return 0
}

# Build the per-protocol "clients" array as a JSON fragment on stdout.
# Empty result is "[]" so the inbound remains syntactically valid.
xray_build_clients_json() {
    local proto="$1"
    local rows
    rows=$(sqlite3 -separator '|' "$DB_PATH" \
        "SELECT username,uuid,expiry_date,status FROM xray_users WHERE protocol='${proto}';" 2>/dev/null)

    if [ -z "$rows" ]; then
        echo ""
        return 0
    fi

    local first=1
    local now_epoch
    now_epoch=$(date +%s)

    while IFS='|' read -r uname secret exp status; do
        # Skip expired users entirely so they cannot authenticate
        local exp_epoch
        exp_epoch=$(date -d "$exp" +%s 2>/dev/null || echo 0)
        if [ "$exp_epoch" -lt "$now_epoch" ] || [ "$status" != "ACTIVE" ]; then
            continue
        fi

        if [ $first -eq 0 ]; then echo ","; fi
        first=0

        case "$proto" in
            vmess)
                printf '{"id":"%s","alterId":0,"email":"%s@janabitech"}' "$secret" "$uname"
                ;;
            vless)
                printf '{"id":"%s","email":"%s@janabitech","level":0}' "$secret" "$uname"
                ;;
            trojan)
                printf '{"password":"%s","email":"%s@janabitech"}' "$secret" "$uname"
                ;;
        esac
    done <<< "$rows"
}

# ----------------------------------------------------------------------
# User lifecycle
# ----------------------------------------------------------------------
xray_create_user() {
    local username="$1"
    local protocol="$2"
    local value="$3"
    local unit="$4"

    xray_validate_username "$username" || return 3
    xray_validate_protocol "$protocol" || return 3

    if [ -z "$value" ] || [ -z "$unit" ]; then
        xray_log "ERROR" "Usage: xray add <user> <protocol> <value> <unit>"
        return 1
    fi

    # FIX: reject non-positive durations when creating a brand-new account.
    #      The regex in xray_compute_expiry allows negatives (because the
    #      renew path needs them for deductions), but a freshly created
    #      account with a negative duration starts out already expired,
    #      which is never what the operator wanted.
    if ! [[ "$value" =~ ^-?[0-9]+$ ]]; then
        xray_log "ERROR" "Duration must be an integer (got '$value')."
        return 1
    fi
    if [ "$value" -lt 1 ]; then
        xray_log "ERROR" "Duration must be >= 1 for new accounts (got '$value')."
        return 1
    fi

    local exists
    exists=$(db_query "SELECT COUNT(*) FROM xray_users WHERE username='${username}';")
    # FIX: guard against empty db_query output (e.g. transient sqlite error)
    #      so the test doesn't throw 'integer expression expected'.
    if [ "${exists:-0}" -gt 0 ]; then
        xray_log "WARN" "Xray user '$username' already exists."
        return 2
    fi

    local secret
    secret=$(cat /proc/sys/kernel/random/uuid 2>/dev/null || uuidgen)

    # Trojan uses the secret as a password (any string), but UUID is fine too
    local expiry
    expiry=$(xray_compute_expiry "$value" "$unit") || return 1

    db_query "INSERT INTO xray_users (username, protocol, uuid, expiry_date, status) \
              VALUES ('${username}', '${protocol}', '${secret}', '${expiry}', 'ACTIVE');"

    # FIX: if config generation fails after the INSERT, roll back the row so
    #      we don't leave an orphan user in the DB that's not in config.json.
    if ! xray_generate_config; then
        db_query "DELETE FROM xray_users WHERE username='${username}';"
        xray_log "ERROR" "Failed to generate xray config. User '$username' rolled back."
        return 1
    fi
    systemctl restart "$XRAY_SERVICE" >/dev/null 2>&1

    xray_log "INFO" "Provisioned ${protocol} user '${username}' (expires ${expiry})."
    return 0
}

xray_create_trial() {
    local username="$1"
    local protocol="$2"
    local minutes="${3:-30}"

    xray_validate_username "$username" || return 3
    xray_validate_protocol "$protocol" || return 3

    if ! [[ "$minutes" =~ ^[0-9]+$ ]]; then
        xray_log "ERROR" "Trial duration must be a positive number of minutes."
        return 1
    fi
    # FIX: reject 0-minute trials (regex above allows them) — they would
    #      create an account that's expired the instant it's created.
    if [ "$minutes" -lt 1 ]; then
        xray_log "ERROR" "Trial duration must be at least 1 minute."
        return 1
    fi

    local exists
    exists=$(db_query "SELECT COUNT(*) FROM xray_users WHERE username='${username}';")
    if [ "${exists:-0}" -gt 0 ]; then
        xray_log "WARN" "Xray user '$username' already exists."
        return 2
    fi

    local secret
    secret=$(cat /proc/sys/kernel/random/uuid 2>/dev/null || uuidgen)

    local expiry
    expiry=$(xray_compute_expiry "$minutes" "minutes") || return 1

    db_query "INSERT INTO xray_users (username, protocol, uuid, expiry_date, status) \
              VALUES ('${username}', '${protocol}', '${secret}', '${expiry}', 'ACTIVE');"

    # FIX: same rollback safety net as xray_create_user.
    if ! xray_generate_config; then
        db_query "DELETE FROM xray_users WHERE username='${username}';"
        xray_log "ERROR" "Failed to generate xray config. Trial user '$username' rolled back."
        return 1
    fi
    systemctl restart "$XRAY_SERVICE" >/dev/null 2>&1

    xray_log "INFO" "Trial ${protocol} user '${username}' provisioned (${minutes} min, expires ${expiry})."
    return 0
}

xray_renew_user() {
    local username="$1"
    local value="$2"
    local unit="$3"

    if [ -z "$username" ] || [ -z "$value" ] || [ -z "$unit" ]; then
        xray_log "ERROR" "Usage: xray renew <user> <value> <unit>"
        return 1
    fi
    if ! [[ "$value" =~ ^-?[0-9]+$ ]]; then
        xray_log "ERROR" "Duration must be an integer (got '$value')."
        return 1
    fi

    local current
    current=$(db_query "SELECT expiry_date FROM xray_users WHERE username='${username}';")
    if [ -z "$current" ]; then
        xray_log "ERROR" "Xray user '$username' not found."
        return 2
    fi

    local new_exp
    new_exp=$(xray_apply_delta "$current" "$value" "$unit") || return 1

    db_query "UPDATE xray_users SET expiry_date='${new_exp}', status='ACTIVE' WHERE username='${username}';"

    # FIX: same rollback pattern — if config regen fails, undo the expiry bump
    #      so the on-disk config matches the DB row.
    if ! xray_generate_config; then
        db_query "UPDATE xray_users SET expiry_date='${current}' WHERE username='${username}';"
        xray_log "ERROR" "Failed to regenerate config; renewal of '$username' rolled back."
        return 1
    fi
    systemctl restart "$XRAY_SERVICE" >/dev/null 2>&1

    xray_log "INFO" "Renewed '$username'. New expiry: ${new_exp}."
    return 0
}

xray_delete_user() {
    local username="$1"
    if [ -z "$username" ]; then
        xray_log "ERROR" "Usage: xray del <user>"
        return 1
    fi

    # FIX: confirm the row exists before we touch systemd; otherwise 'del'
    #      on a non-existent user silently restarts xray for nothing and
    #      logs a misleading 'Deleted' message.
    local exists
    exists=$(db_query "SELECT COUNT(*) FROM xray_users WHERE username='${username}';")
    if [ "${exists:-0}" -eq 0 ]; then
        xray_log "ERROR" "Xray user '$username' not found."
        return 2
    fi

    db_query "DELETE FROM xray_users WHERE username='${username}';"
    if ! xray_generate_config; then
        xray_log "ERROR" "Failed to regenerate config after deleting '$username'."
        return 1
    fi
    systemctl restart "$XRAY_SERVICE" >/dev/null 2>&1

    xray_log "INFO" "Deleted xray user '$username'."
    return 0
}

xray_purge_expired() {
    # FIX: bail out silently if the xray_users table doesn't exist (e.g.
    #      xray was uninstalled but the cron line wasn't). Previously this
    #      fired sqlite errors every 5 minutes from the cron job.
    local table_exists
    table_exists=$(sqlite3 "$DB_PATH" \
        "SELECT name FROM sqlite_master WHERE type='table' AND name='xray_users';" 2>/dev/null)
    if [ -z "$table_exists" ]; then
        return 0
    fi

    local now_sql
    now_sql=$(date +"%Y-%m-%d %H:%M:%S")

    local n
    n=$(db_query "SELECT COUNT(*) FROM xray_users WHERE expiry_date < '${now_sql}';")
    if [ "${n:-0}" -gt 0 ]; then
        db_query "UPDATE xray_users SET status='EXPIRED' WHERE expiry_date < '${now_sql}';"
        xray_log "INFO" "Marked ${n} expired xray account(s)."
        xray_generate_config || return 1
        systemctl restart "$XRAY_SERVICE" >/dev/null 2>&1
    fi
}

# ----------------------------------------------------------------------
# Link generation (vmess://, vless://, trojan://)
# ----------------------------------------------------------------------
xray_b64url() {
    # base64url without padding (RFC 4648 §5)
    base64 -w0 | tr '+/' '-_' | tr -d '='
}

xray_links_for_user() {
    local username="$1"
    local row
    row=$(sqlite3 -separator '|' "$DB_PATH" \
        "SELECT username,protocol,uuid,expiry_date,status FROM xray_users WHERE username='${username}';" 2>/dev/null)

    if [ -z "$row" ]; then
        xray_log "ERROR" "User '$username' not found."
        return 1
    fi

    local uname proto secret exp status
    IFS='|' read -r uname proto secret exp status <<< "$row"

    local host="${PRIMARY_DOMAIN}"
    local path="${XRAY_WS_PATH[$proto]}"
    local grpc="${XRAY_GRPC_SVC[$proto]}"

    # WS path (url-encode nothing here – simple slash is fine in vmess/vless/trojan URIs)
    echo "==================== ${proto^^} ACCOUNT: ${uname} ===================="
    echo "Expires : ${exp}"
    echo "Status  : ${status}"
    echo "UUID/PSK: ${secret}"
    echo "Host    : ${host}"
    echo "----------------------------------------------------------------"

    case "$proto" in
        vmess)
            # VMess link is a base64(JSON) blob
            local common="{\"v\":\"2\",\"ps\":\"${uname}-wsnontls\",\"add\":\"${host}\",\"port\":\"${XRAY_PORTS[vmess_ws_nontls]}\",\"id\":\"${secret}\",\"aid\":\"0\",\"net\":\"ws\",\"type\":\"none\",\"host\":\"${host}\",\"path\":\"${path}\",\"tls\":\"\"}"
            echo "VMess WS (no TLS)  : vmess://$(echo -n "$common" | xray_b64url)"

            common="{\"v\":\"2\",\"ps\":\"${uname}-wstls\",\"add\":\"${host}\",\"port\":\"${XRAY_PORTS[vmess_ws_tls]}\",\"id\":\"${secret}\",\"aid\":\"0\",\"net\":\"ws\",\"type\":\"none\",\"host\":\"${host}\",\"path\":\"${path}\",\"tls\":\"tls\",\"sni\":\"${host}\"}"
            echo "VMess WS (TLS)     : vmess://$(echo -n "$common" | xray_b64url)"

            common="{\"v\":\"2\",\"ps\":\"${uname}-grpc\",\"add\":\"${host}\",\"port\":\"${XRAY_PORTS[vmess_grpc]}\",\"id\":\"${secret}\",\"aid\":\"0\",\"net\":\"grpc\",\"type\":\"none\",\"host\":\"${host}\",\"path\":\"${grpc}\",\"tls\":\"tls\",\"sni\":\"${host}\"}"
            echo "VMess gRPC (TLS)   : vmess://$(echo -n "$common" | xray_b64url)"
            ;;
        vless)
            echo "VLESS WS (no TLS)  : vless://${secret}@${host}:${XRAY_PORTS[vless_ws_nontls]}?encryption=none&security=&type=ws&host=${host}&path=${path}#${uname}-wsnontls"
            echo "VLESS WS (TLS)     : vless://${secret}@${host}:${XRAY_PORTS[vless_ws_tls]}?encryption=none&security=tls&sni=${host}&type=ws&host=${host}&path=${path}#${uname}-wstls"
            echo "VLESS gRPC (TLS)   : vless://${secret}@${host}:${XRAY_PORTS[vless_grpc]}?encryption=none&security=tls&sni=${host}&type=grpc&serviceName=${grpc}#${uname}-grpc"
            ;;
        trojan)
            echo "Trojan WS (no TLS) : trojan://${secret}@${host}:${XRAY_PORTS[trojan_ws_nontls]}?security=&type=ws&host=${host}&path=${path}#${uname}-wsnontls"
            echo "Trojan WS (TLS)    : trojan://${secret}@${host}:${XRAY_PORTS[trojan_ws_tls]}?security=tls&sni=${host}&type=ws&host=${host}&path=${path}#${uname}-wstls"
            echo "Trojan gRPC (TLS)  : trojan://${secret}@${host}:${XRAY_PORTS[trojan_grpc]}?security=tls&sni=${host}&type=grpc&serviceName=${grpc}#${uname}-grpc"
            ;;
    esac
    echo "================================================================"
}

xray_list_users() {
    echo "==================== XRAY ACCOUNTS ===================="
    printf "%-4s | %-15s | %-8s | %-20s | %-8s\n" "S/N" "USERNAME" "PROTOCOL" "EXPIRY" "STATUS"
    echo "------------------------------------------------------"
    local i=1
    sqlite3 -separator '|' "$DB_PATH" \
        "SELECT username,protocol,expiry_date,status FROM xray_users ORDER BY id ASC;" 2>/dev/null | \
    while IFS='|' read -r uname proto exp status; do
        printf "%-4s | %-15s | %-8s | %-20s | %-8s\n" "$i" "$uname" "$proto" "$exp" "$status"
        ((i++))
    done
    echo "======================================================"
}

xray_restart() {
    xray_log "INFO" "Restarting ${XRAY_SERVICE} ..."
    xray_generate_config || return 1
    systemctl restart "$XRAY_SERVICE"
    if systemctl is-active --quiet "$XRAY_SERVICE"; then
        xray_log "INFO" "Xray is running."
    else
        xray_log "ERROR" "Xray failed to start. Check: journalctl -u ${XRAY_SERVICE} -n 50"
        return 1
    fi
}

xray_status() {
    echo "==================== XRAY STATUS ===================="
    if [ -x "$XRAY_BIN" ]; then
        echo "Binary   : $("$XRAY_BIN" version 2>/dev/null | head -n1)"
    else
        echo "Binary   : NOT INSTALLED (run: janabitech xray install)"
    fi
    echo "Config   : ${XRAY_CONF}"
    echo "Domain   : ${PRIMARY_DOMAIN}"
    echo "Cert     : /opt/janabitech/core/keys/fullchain.cer"
    echo "Service  : ${XRAY_SERVICE} ($(systemctl is-active ${XRAY_SERVICE} 2>/dev/null))"
    echo ""
    echo "Listening ports:"
    printf "  vmess  ws  (no TLS) : %s\n" "${XRAY_PORTS[vmess_ws_nontls]}"
    printf "  vmess  ws  (TLS)    : %s\n" "${XRAY_PORTS[vmess_ws_tls]}"
    printf "  vmess  grpc (TLS)   : %s\n" "${XRAY_PORTS[vmess_grpc]}"
    printf "  vless  ws  (no TLS) : %s\n" "${XRAY_PORTS[vless_ws_nontls]}"
    printf "  vless  ws  (TLS)    : %s\n" "${XRAY_PORTS[vless_ws_tls]}"
    printf "  vless  grpc (TLS)   : %s\n" "${XRAY_PORTS[vless_grpc]}"
    printf "  trojan ws  (no TLS) : %s\n" "${XRAY_PORTS[trojan_ws_nontls]}"
    printf "  trojan ws  (TLS)    : %s\n" "${XRAY_PORTS[trojan_ws_tls]}"
    printf "  trojan grpc (TLS)   : %s\n" "${XRAY_PORTS[trojan_grpc]}"
    echo ""
    local total active expired
    total=$(sqlite3 "$DB_PATH" "SELECT COUNT(*) FROM xray_users;" 2>/dev/null || echo 0)
    active=$(sqlite3 "$DB_PATH" "SELECT COUNT(*) FROM xray_users WHERE status='ACTIVE';" 2>/dev/null || echo 0)
    expired=$(sqlite3 "$DB_PATH" "SELECT COUNT(*) FROM xray_users WHERE status='EXPIRED';" 2>/dev/null || echo 0)
    echo "Accounts : ${active} active / ${expired} expired / ${total} total"
    echo "====================================================="
}
