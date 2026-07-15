source /opt/janabitech/core/janabitech.conf 2>/dev/null || true
:
if [ -f /opt/janabitech/menus/xray_menu.sh ]; then
    :
fi

# --- Root Enforcement ---
if [ "${EUID}" -ne 0 ]; then
    echo -e "\033[0;31m[FATAL] You must be root to access the Janabitech Dashboard.\033[0m"
    echo -e "\033[0;33mType this command to become root: sudo su -\033[0m"
    exit 1
fi

# --- License Enforcement ---
if [ -f "/opt/janabitech/core/license_status" ] && [ "$(cat /opt/janabitech/core/license_status)" == "REVOKED" ]; then
    # Perform a real-time check in case they just renewed
    IP=$(curl -s4 ifconfig.me)
    RESPONSE=$(curl -s --max-time 10 "https://vpn.janabitech.online/api/v1/ip/verify?ip=${IP}")
    STATUS=$(echo "$RESPONSE" | grep -o '"status":"[^"]*"' | cut -d'"' -f4)
    
    if [ "$STATUS" == "active" ]; then
        echo "ACTIVE" > /opt/janabitech/core/license_status
        rm -f /opt/janabitech/core/license.env
        systemctl enable xray haproxy nginx dropbear stunnel4 janabitech-ws janabitech-dnstt janabitech-udp-custom 2>/dev/null
        systemctl start xray haproxy nginx dropbear stunnel4 janabitech-ws janabitech-dnstt janabitech-udp-custom 2>/dev/null
    else
        clear
        echo -e "\033[1;31m============================================================\033[0m"
        echo -e "\033[1;31m                  ❌ LICENSE REVOKED ❌                    \033[0m"
        echo -e "\033[1;31m============================================================\033[0m"
        echo -e "\033[1;33m Your server license has expired or has been revoked.\033[0m"
        echo -e "\033[1;33m All VPN services (Xray, HAProxy, Nginx) have been disabled.\033[0m"
        echo -e ""
        echo -e "\033[1;36m Please renew your license at: @imagivpnbot\033[0m"
        echo -e "\033[1;31m============================================================\033[0m"
        echo -e ""
        echo -e "\033[1;33mDo you want to permanently uninstall the Janabitech platform? (y/N)\033[0m"
        read -p "> " choice
        if [[ "$choice" =~ ^[Yy]$ ]]; then
            /opt/janabitech/bin/janabitech sys uninstall
        fi
        exit 1
    fi
fi

# --- ANSI Color Palette (Extended) ---
RED='\033[0;31m'
GREEN='\033[0;32m'
ORANGE='\033[0;33m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
WHITE='\033[1;37m'
DIM='\033[2m'
NC='\033[0m'
BOLD='\033[1m'
BG_CYAN='\033[46m'
BRIGHT_CYAN='\033[1;36m'
BRIGHT_GREEN='\033[1;32m'
BRIGHT_RED='\033[1;31m'
BRIGHT_MAGENTA='\033[1;35m'
BRIGHT_YELLOW='\033[1;33m'

# --- Box Drawing Constants ---
BOX_W=58  # Width of the horizontal rules

draw_top()  { echo -e "${CYAN}╔$(printf '═%.0s' $(seq 1 $BOX_W))╗${NC}"; }
draw_mid()  { echo -e "${CYAN}╠$(printf '═%.0s' $(seq 1 $BOX_W))╣${NC}"; }
draw_bot()  { echo -e "${CYAN}╚$(printf '═%.0s' $(seq 1 $BOX_W))╝${NC}"; }
draw_thin() { echo -e "${DIM}${CYAN}╟$(printf '─%.0s' $(seq 1 $BOX_W))╢${NC}"; }
draw_line() { echo -e "${CYAN}$(printf '━%.0s' $(seq 1 $((BOX_W + 2))))${NC}"; }

# Print a centered line inside the left/right frame
center_text() {
    local text="$1"
    local color="${2:-$NC}"
    local visible=$(echo -e "$text" | sed 's/\x1b\[[0-9;]*m//g')
    local len=${#visible}
    local pad_l=$(( (BOX_W - len) / 2 ))
    local pad_r=$(( BOX_W - len - pad_l ))
    printf "${CYAN}║${NC}%${pad_l}s${color}%s${NC}%${pad_r}s${CYAN}║${NC}\n" "" "$text" ""
}

# Print a left-aligned row with right border
row() {
    local content="$1"
    local visible=$(echo -e "$content" | sed 's/\x1b\[[0-9;]*m//g')
    local len=${#visible}
    local pad_r=$(( BOX_W - len - 1 ))
    if [ $pad_r -lt 0 ]; then pad_r=0; fi
    printf "${CYAN}║${NC} %b%${pad_r}s${CYAN}║${NC}\n" "$content" ""
}

# Print an empty row with borders
empty_row() { printf "${CYAN}║%${BOX_W}s║${NC}\n" ""; }

# --- Live Data Harvesters ---
fetch_server_geo() {
    local geo_file="/opt/janabitech/core/server_geo.env"
    
    # Only fetch the data if the cache file doesn't exist yet
    if [ ! -f "$geo_file" ]; then
        # 1. Get the public IP
        local ip=$(curl -sS -4 ipv4.icanhazip.com 2>/dev/null)
        
        # 2. Fetch Geo data using 'org' instead of 'isp'
        local geo_data=$(curl -sS "http://ip-api.com/line/$ip?fields=country,org" 2>/dev/null)
        
        # 3. Parse the lines safely
        local country=$(echo "$geo_data" | sed -n '1p')
        
        # 4. Extract org and strip the trailing ' (region)' text using sed
        local org_clean=$(echo "$geo_data" | sed -n '2p' | sed 's/ *(.*)//')
        
        # 5. Save to the core architecture directory
        echo "SERVER_IP=\"${ip:-Unknown}\"" > "$geo_file"
        echo "SERVER_COUNTRY=\"${country:-Unknown}\"" >> "$geo_file"
        echo "SERVER_ISP=\"${org_clean:-Unknown}\"" >> "$geo_file"
    fi
}

fetch_license_info() {
    local cache_file="/opt/janabitech/core/license.env"
    
    if [ ! -f "$cache_file" ] || test $(find "$cache_file" -mmin +360 2>/dev/null); then
        local ip=$(curl -sS -4 ipv4.icanhazip.com 2>/dev/null)
        local api_res=$(curl -sS -A "Janabitech-CLI/1.0" "https://vpn.janabitech.online/api/v1/ip/verify?ip=$ip" 2>/dev/null)
        
        local lic_name=$(echo "$api_res" | grep -o '"name":"[^"]*' | cut -d'"' -f4)
        local lic_exp=$(echo "$api_res" | grep -o '"expires_at":"[^"]*' | cut -d'"' -f4 | cut -d'T' -f1)
        if [[ "$lic_exp" > "2099" ]]; then
            lic_exp="Lifetime"
        fi
        
        echo "LIC_NAME=\"${lic_name:-Unknown}\"" > "$cache_file"
        echo "LIC_EXPIRES=\"${lic_exp:-Unknown}\"" >> "$cache_file"
    fi
}

get_system_stats() {
    # Existing dynamic stats
    OS_INFO=$(grep -w PRETTY_NAME /etc/os-release | cut -d= -f2 | tr -d '"')
    UPTIME=$(uptime -p | sed 's/up //')
    RAM_USED=$(free -m | awk 'NR==2{print $3}')
    RAM_TOTAL=$(free -m | awk 'NR==2{print $2}')
    CPU_USAGE=$(top -bn1 | grep "Cpu(s)" | sed "s/.*, *\([0-9.]*\)%* id.*/\1/" | awk '{print 100 - $1"%"}')
    
    # New Static Geo Stats & License Info
    fetch_server_geo
    fetch_license_info
    source /opt/janabitech/core/server_geo.env 2>/dev/null
    source /opt/janabitech/core/license.env 2>/dev/null
    
    # Server Bandwidth Stats
    BW_TODAY="0.00 MB"
    BW_MONTH="0.00 MB"
    if command -v vnstat &>/dev/null; then
        # Use default interface. vnstat --oneline returns semicolon-separated values
        # Field 6: Total Today, Field 11: Total Month
        local vn_data=$(vnstat --oneline 2>/dev/null)
        if [[ "$vn_data" =~ ^[0-9]+ ]]; then
            BW_TODAY=$(echo "$vn_data" | cut -d';' -f6)
            BW_MONTH=$(echo "$vn_data" | cut -d';' -f11)
        fi
    fi
}

get_db_stats() {
    TOTAL_USERS=$(sqlite3 "$DB_PATH" "SELECT COUNT(*) FROM users;" 2>/dev/null || echo "0")
    ACTIVE_USERS=$(sqlite3 "$DB_PATH" "SELECT COUNT(*) FROM users WHERE status='ACTIVE';" 2>/dev/null || echo "0")
    EXPIRED_USERS=$(sqlite3 "$DB_PATH" "SELECT COUNT(*) FROM users WHERE status='EXPIRED';" 2>/dev/null || echo "0")
}

check_service() {
    if systemctl is-active --quiet "$1" 2>/dev/null; then
        echo -e "${GREEN}[ON]${NC}"
    else
        echo -e "${RED}[OFF]${NC}"
    fi
}

pause() {
    echo ""
    read -n 1 -s -r -p "Press any key to return..."
}

# ==========================================================
# [01] SSH PANEL
# ==========================================================
menu_ssh_panel() {
    while true; do
        clear
        draw_line
        echo -e "                   ${BOLD}SSH ACCOUNT PANEL${NC}                   "
        draw_line
        echo -e "  ${CYAN}[01]${NC} Create SSH Account"
        echo -e "  ${CYAN}[02]${NC} Create Trial SSH"
        echo -e "  ${CYAN}[03]${NC} Renew SSH Account"
        echo -e "  ${CYAN}[04]${NC} Delete SSH Account"
        echo -e "  ${CYAN}[05]${NC} Check Online Users"
        echo -e "  ${CYAN}[06]${NC} List Members"
        echo -e "  ${CYAN}[07]${NC} User Details (Print Credentials)"
        echo -e "  ${CYAN}[08]${NC} Locked/Banned Users"
        echo -e ""
        echo -e "  ${RED}[00]${NC} Return to Main Menu"
        draw_line
        read -p " Select Option : " opt

        case $opt in
            1) execute_add_user ;;
            2) execute_trial_user ;;
            3) execute_renew_user ;;
            4) execute_del_user ;;
            5) execute_online_users "SSH" ;;
            6) execute_list_users "SSH" ;;
            7) execute_user_details "SSH" ;;
            8) execute_locked_users "SSH" ;;
            0|00) return ;;
            *) echo -e "${RED}Invalid option${NC}"; sleep 1 ;;
        esac
    done
}

execute_add_user() {
    while true; do
        clear
        echo -e "${CYAN}=== CREATE SSH ACCOUNT ===${NC}"
        
        read -p "Username: " USERNAME
        if [[ -z "$USERNAME" ]]; then echo -e "${RED}[ERROR] Username cannot be empty.${NC}"; sleep 1.5; continue; fi
        
        # Auto-generate password if left blank
        local rand_pass=$(< /dev/urandom tr -dc _A-Z-a-z-0-9 | head -c8)
        read -p "Password [default: random]: " PASSWORD
        PASSWORD=${PASSWORD:-$rand_pass}
        
        read -p "Duration (Days) [default: 30]: " DAYS
        DAYS=${DAYS:-30}

        read -p "Max Simultaneous Logins (0 = Unlimited) [Default: 2]: " MAX_LOGINS
        MAX_LOGINS=${MAX_LOGINS:-2}

        read -p "Bandwidth Limit in GB (0 = Unlimited) [Default: 0]: " BW_LIMIT
        BW_LIMIT=${BW_LIMIT:-0}

        /opt/janabitech/bin/janabitech user add "$USERNAME" "$PASSWORD" "$DAYS" "$MAX_LOGINS" "$BW_LIMIT" "SSH" > /dev/null 2>&1
        API_STATUS=$?
        
        if [ $API_STATUS -eq 2 ]; then
            echo -e "\n${ORANGE}[!] User '${USERNAME}' already exists.${NC}"
            read -p "Do you want to create another user? (y/n): " RETRY
            if [[ "$RETRY" =~ ^[Yy] ]]; then continue; else return; fi
        elif [ $API_STATUS -ne 0 ]; then
            echo -e "\n${RED}[-] Failed to create account. Ensure username is 3-32 chars.${NC}"; pause; return
        fi
        break
    done
    print_user_receipt "$USERNAME" "$PASSWORD" "$DAYS" "days" "$MAX_LOGINS" "$BW_LIMIT"
}

execute_trial_user() {
    clear
    echo -e "${CYAN}=== CREATE TRIAL SSH ACCOUNT ===${NC}"
    
    # Auto-generate trial user and random password
    USERNAME="trial$((RANDOM % 9000 + 1000))"
    PASSWORD=$(< /dev/urandom tr -dc _A-Z-a-z-0-9 | head -c6)
    
    echo -e "Generated Username : ${GREEN}${USERNAME}${NC}"
    echo -e "Generated Password : ${GREEN}${PASSWORD}${NC}\n"
    
    read -p "Duration in Hours [default: 2]: " HOURS
    HOURS=${HOURS:-2}

    read -p "Max Simultaneous Logins (0 = Unlimited) [Default: 2]: " MAX_LOGINS
    MAX_LOGINS=${MAX_LOGINS:-2}

    read -p "Bandwidth Limit in GB (0 = Unlimited) [Default: 0]: " BW_LIMIT
    BW_LIMIT=${BW_LIMIT:-0}

    /opt/janabitech/bin/janabitech user trial "$USERNAME" "$PASSWORD" "$HOURS" "$MAX_LOGINS" "$BW_LIMIT" "SSH" > /dev/null 2>&1
    print_user_receipt "$USERNAME" "$PASSWORD" "$HOURS" "hours" "$MAX_LOGINS" "$BW_LIMIT"
}

execute_renew_user() {
    local list_type="${1:-SSH}"
    clear
    echo -e "${CYAN}=== RENEW ${list_type} ACCOUNT ===${NC}"
    select_user_from_list "$list_type"
    if [[ -z "$FINAL_USERNAME" ]]; then return; fi

    local OLD_DATE_FORMATTED=$(date -d "$FINAL_EXPIRY" +"%B %d, %Y" 2>/dev/null || echo "$FINAL_EXPIRY")

    echo -e "\nUser: ${GREEN}${FINAL_USERNAME}${NC} | Current Expiry: ${ORANGE}${OLD_DATE_FORMATTED}${NC}"
    echo -e "What would you like to modify?"
    echo -e "  1. Expiry Date (Days)"
    echo -e "  2. Max Logins (Devices)"
    echo -e "  3. Bandwidth (GB)"
    read -p "Select option [1-3]: " MOD_OPT

    if [[ "$MOD_OPT" == "1" ]]; then
        echo -e "Enter days to add (e.g., 30) or days to deduct (e.g., -5):"
        read -p "Modification (Days): " MOD_DAYS
        if ! [[ "$MOD_DAYS" =~ ^-?[0-9]+$ ]]; then
            echo -e "${RED}[-] Invalid input.${NC}"; sleep 2; return
        fi
        /opt/janabitech/bin/janabitech user renew "$FINAL_USERNAME" "$MOD_DAYS" > /dev/null 2>&1
        local NEW_EXPIRY=$(sqlite3 "$DB_PATH" "SELECT expiry_date FROM users WHERE username='$FINAL_USERNAME';" 2>/dev/null)
        local NEW_DATE_FORMATTED=$(date -d "$NEW_EXPIRY" +"%B %d, %Y" 2>/dev/null || echo "$NEW_EXPIRY")
        local MOD_DISPLAY=""
        if [ "$MOD_DAYS" -lt 0 ]; then MOD_DISPLAY="${RED}${MOD_DAYS} Days${NC}"
        else MOD_DISPLAY="${GREEN}+${MOD_DAYS} Days${NC}"; fi
        
        clear
        echo -e "${GREEN}Account renewed successfully${NC}       "
        draw_line
        echo -e "Username      : ${GREEN}${FINAL_USERNAME}${NC}"
        echo -e "Modification  : ${MOD_DISPLAY}"
        echo -e "Old Expiry    : ${ORANGE}${OLD_DATE_FORMATTED}${NC}"
        echo -e "New Expiry    : ${GREEN}${NEW_DATE_FORMATTED}${NC}"
        draw_line
    elif [[ "$MOD_OPT" == "2" ]]; then
        read -p "Enter new Max Logins (0 = Unlimited): " NEW_LOGINS
        if ! [[ "$NEW_LOGINS" =~ ^[0-9]+$ ]]; then
            echo -e "${RED}[-] Invalid input.${NC}"; sleep 2; return
        fi
        sqlite3 "$DB_PATH" "UPDATE users SET max_logins=$NEW_LOGINS WHERE username='$FINAL_USERNAME';" 2>/dev/null
        echo -e "${GREEN}[+] Max Logins updated to ${NEW_LOGINS} for ${FINAL_USERNAME}${NC}"
    elif [[ "$MOD_OPT" == "3" ]]; then
        read -p "Enter new Bandwidth Limit in GB (0 = Unlimited): " NEW_BW
        if ! [[ "$NEW_BW" =~ ^[0-9]+$ ]]; then
            echo -e "${RED}[-] Invalid input.${NC}"; sleep 2; return
        fi
        local DATA_BYTES=$((NEW_BW * 1073741824))
        sqlite3 "$DB_PATH" "UPDATE users SET data_limit=$DATA_BYTES WHERE username='$FINAL_USERNAME';" 2>/dev/null
        echo -e "${GREEN}[+] Bandwidth updated to ${NEW_BW} GB for ${FINAL_USERNAME}${NC}"
    else
        echo -e "${RED}[-] Invalid option.${NC}"
        sleep 2; return
    fi
    
    pause
}

execute_del_user() {
    local list_type="${1:-SSH}"
    clear
    echo -e "${CYAN}=== DELETE ${list_type} ACCOUNT(S) ===${NC}"
    
    mapfile -t USER_LIST < <(sqlite3 -separator '|' "$DB_PATH" "SELECT username FROM users WHERE account_type='$list_type';")
    local user_count=${#USER_LIST[@]}
    
    if [ "$user_count" -eq 0 ]; then
        echo -e "\n${ORANGE}[!] No users found in the database.${NC}"; pause; return
    fi

    draw_line
    printf "${BOLD}%-5s | %-15s${NC}\n" "S/N" "USERNAME"
    draw_line
    
    local i=1
    for uname in "${USER_LIST[@]}"; do
        printf "${GREEN}%-5s${NC} | ${CYAN}%-15s${NC}\n" "$i" "$uname"
        ((i++))
    done
    draw_line
    
    echo -e "Enter S/N(s) separated by commas or ranges (e.g., 1,3 or 4-6)"
    read -p "Select targets: " TARGET_INPUT
    if [[ -z "$TARGET_INPUT" ]]; then return; fi

    # Parse ranges and commas into a distinct list of IDs
    local TO_DELETE=()
    local parsed_list=$(echo "$TARGET_INPUT" | awk -F, '{
        for(i=1; i<=NF; i++) {
            if ($i ~ /-/) { split($i, a, "-"); for(j=a[1]; j<=a[2]; j++) printf "%s ", j } 
            else { printf "%s ", $i }
        }
    }')

    for sn in $parsed_list; do
        if [[ "$sn" =~ ^[0-9]+$ ]] && [ "$sn" -le "$user_count" ] && [ "$sn" -gt 0 ]; then
            local index=$((sn - 1))
            TO_DELETE+=("${USER_LIST[$index]}")
        fi
    done

    if [ ${#TO_DELETE[@]} -eq 0 ]; then
        echo -e "\n${RED}[-] Invalid selection.${NC}"; pause; return
    fi

    echo -e "\n${ORANGE}[*] Deleting ${#TO_DELETE[@]} account(s)...${NC}"
    for target in "${TO_DELETE[@]}"; do
        /opt/janabitech/bin/janabitech user del "$target" > /dev/null 2>&1
        echo -e "  - Deleted: ${RED}${target}${NC}"
    done
    pause
}


execute_list_users() {
    local list_type="${1:-SSH}"
    clear
    echo -e "${CYAN}=== ${list_type} MEMBERS LIST ===${NC}"
    draw_line
    printf "${BOLD}%-4s | %-12s | %-11s | %-4s | %-18s | %-7s${NC}\n" "S/N" "USERNAME" "EXPIRES" "STAT" "BW" "CONN"
    draw_line
    
    declare -A online_counts
    if [ -f "/opt/janabitech/core/online_users.txt" ]; then
        while IFS='|' read -r uname count; do
            if [[ -n "$uname" && "$count" =~ ^[0-9]+$ ]]; then
                online_counts["$uname"]="$count"
            fi
        done < <(cat /opt/janabitech/core/online_users.txt || true)
    fi

    local i=1
    sqlite3 -separator '|' "$DB_PATH" "SELECT username, expiry_date, status, data_usage, data_limit, max_logins FROM users WHERE account_type='$list_type';" | while read -r line; do
        local uname=$(echo "$line" | cut -d'|' -f1)
        local exp=$(echo "$line" | cut -d'|' -f2 | cut -d' ' -f1)
        local status=$(echo "$line" | cut -d'|' -f3)
        local data_u=$(echo "$line" | cut -d'|' -f4)
        local data_l=$(echo "$line" | cut -d'|' -f5)
        local max_l=$(echo "$line" | cut -d'|' -f6)
        
        if [ "$status" == "ACTIVE" ]; then 
            status_color="${GREEN}"
            status="ACTV"
        else 
            status_color="${RED}"
            status="LCKD"
        fi
        
        if [ "$data_l" -eq 0 ]; then
            local bw_str="$(format_bytes "$data_u" | sed 's/ //')/Unl"
        else
            local bw_str="$(format_bytes "$data_u" | sed 's/ //')/$(format_bytes "$data_l" | sed 's/ //')"
        fi
        
        local c_count="${online_counts[$uname]:-0}"
        if [ "$max_l" -eq 0 ]; then
            local conn_str="${c_count}/Unl"
        else
            local conn_str="${c_count}/${max_l}"
        fi

        printf "${GREEN}%-4s${NC} | ${CYAN}%-12.12s${NC} | ${ORANGE}%-11s${NC} | ${status_color}%-4s${NC} | ${CYAN}%-18s${NC} | ${ORANGE}%-7s${NC}\n" "$i" "$uname" "$exp" "$status" "$bw_str" "$conn_str"
        ((i++))
    done
    draw_line
    pause
}

print_ssh_user_details() {
    local USERNAME="$1"
    local EXP_DATE_FORMATTED=$(date -d "$2" +"%B %d, %Y" 2>/dev/null || echo "$2")
    
    local IP_ADDR=$(curl -sS ipv4.icanhazip.com)
    local PUB_KEY=$(cat /opt/janabitech/core/keys/dnstt.pub 2>/dev/null || echo "Missing Key")
    local MAX_LOGINS=$(sqlite3 "$DB_PATH" "SELECT max_logins FROM users WHERE username='$USERNAME';" 2>/dev/null || echo "2")
    local LOGIN_DISP="$MAX_LOGINS"
    if [ "$MAX_LOGINS" -eq 0 ]; then LOGIN_DISP="Unlimited"; fi

    source /opt/janabitech/core/server_geo.env 2>/dev/null
    local COUNTRY="${SERVER_COUNTRY:-Unknown}"
    local ISP="${SERVER_ISP:-Unknown}"

    clear
    echo -e "${GREEN}User details fetched successfully${NC}       "
    echo -e "======== ACCOUNT DETAILS ========"
    echo -e "Username      : ${USERNAME}"
    echo -e "Password      : ${RED}[HIDDEN]${NC} (Encrypted by OS)"
    echo -e "Expires On    : ${EXP_DATE_FORMATTED}"
    echo -e "Public IP     : ${IP_ADDR} (${COUNTRY})"
    echo -e "Host          : ${PRIMARY_DOMAIN}"
    echo -e "ISP Provider  : ${ISP}"
    echo -e "========================================"
    echo -e "Nameserver    : ${NS_DOMAIN}"
    echo -e "PubKey        : ${PUB_KEY}\n"
    echo -e "DNS Resolver  : 1.1.1.1 / 8.8.8.8\n"
    
    echo -e "OpenSSH     : 22"
    echo -e "Dropbear    : ${PORT_DROPBEAR:-109}, ${PORT_DROPBEAR_ALT:-143}"
    echo -e "SSH WS      : 80, 8080, 8880"
    echo -e "SSH WSS     : 443, 8443"
    echo -e "DNSTT       : 53, 5300"
    echo -e "SOCKS5      : ${PORT_SOCKS:-1080}"
    echo -e "UDP Custom  : 1-65535"
    echo -e "========================================"
    echo -e "SSH-80        : ${PRIMARY_DOMAIN}:${PORT_WS_HTTP:-80}@${USERNAME}:[PASS]"
    echo -e "SSH-443       : ${PRIMARY_DOMAIN}:${PORT_WS_HTTPS:-443}@${USERNAME}:[PASS]"
    echo -e "SOCKS5        : ${PRIMARY_DOMAIN}:${PORT_SOCKS:-1080}:${USERNAME}:[PASS]"
    echo -e "SSH-8880      : ${PRIMARY_DOMAIN}:8880@${USERNAME}:[PASS]"
    echo -e "========================================"
    echo -e "WSS Payload"
    echo -e "GET wss://bug.com [protocol][crlf]Host: ${PRIMARY_DOMAIN}[crlf]Upgrade: websocket[crlf][crlf]\n"
    echo -e "WS Payload"
    echo -e "GET / HTTP/1.1[crlf]Host: ${PRIMARY_DOMAIN}[crlf]Upgrade: websocket[crlf][crlf]\n"
    echo -e "Custom Payload"
    echo -e "GET http://${PRIMARY_DOMAIN}:8880 HTTP/1.1[crlf]Host: [SNI_BUG_HOST][crlf]Upgrade: websocket[crlf]Connection: Upgrade[crlf][crlf]"
    echo -e "========================================"
    pause
}

execute_online_users() {
    local list_type="${1:-SSH}"
    clear
    echo -e "${CYAN}=== ACTIVE CONNECTIONS ===${NC}"
    draw_line
    printf "${BOLD}%-20s | %-15s${NC}\n" "USERNAME" "ACTIVE DEVICES"
    draw_line
    
    local raw_data=$(/opt/janabitech/bin/janabitech sys online)
    
    if [[ "$raw_data" == *"No active"* ]] || [[ "$raw_data" == *"starting"* ]]; then
        echo -e "${ORANGE}$raw_data${NC}"
    else
        # removed
        echo "$raw_data" | while IFS='|' read -r uname count; do
            local act_type=$(sqlite3 "$DB_PATH" "SELECT account_type FROM users WHERE username='$uname';" 2>/dev/null)
            if [[ -n "$act_type" && "$act_type" != "$list_type" ]]; then continue; fi
            # removed
            # Add a red warning if count is high
            if [ "$count" -ge 3 ]; then
                printf "${GREEN}%-20s${NC} | ${RED}%-15s${NC}\n" "$uname" "$count"
            else
                printf "${GREEN}%-20s${NC} | ${CYAN}%-15s${NC}\n" "$uname" "$count"
            fi
        done
    fi
    draw_line
    pause
}

execute_user_details() {
    local list_type="${1:-SSH}"
    clear
    echo -e "${CYAN}=== PRINT USER DETAILS ===${NC}"
    select_user_from_list "$list_type"
    if [[ -z "$FINAL_USERNAME" ]]; then return; fi
    
    # Format the absolute expiry date fetched from the list selection
    local EXP_DATE_FORMATTED=$(date -d "$FINAL_EXPIRY" +"%B %d, %Y" 2>/dev/null || echo "$FINAL_EXPIRY")
    local USERNAME="$FINAL_USERNAME"
    local PASSWORD="[HIDDEN]" # Security constraint: PAM handles auth, DB stores metadata
    
    # Fetch dynamic server data
    local IP_ADDR=$(curl -sS ipv4.icanhazip.com)
    local PUB_KEY=$(cat /opt/janabitech/core/keys/dnstt.pub 2>/dev/null || echo "Missing Key")

    local MAX_LOGINS=$(sqlite3 "$DB_PATH" "SELECT max_logins FROM users WHERE username='$FINAL_USERNAME';" 2>/dev/null || echo "2")
    local LOGIN_DISP="$MAX_LOGINS"
    if [ "$MAX_LOGINS" -eq 0 ]; then LOGIN_DISP="Unlimited"; fi

    source /opt/janabitech/core/server_geo.env 2>/dev/null
    local COUNTRY="${SERVER_COUNTRY:-Unknown}"
    local ISP="${SERVER_ISP:-Unknown}"

    clear
    echo -e "${GREEN}User details fetched successfully${NC}       "
    
    echo -e "======== ACCOUNT DETAILS ========"
    echo -e "Username      : ${USERNAME}"
    echo -e "Password      : ${RED}${PASSWORD}${NC} (Encrypted by OS)"
    echo -e "Expires On    : ${EXP_DATE_FORMATTED}"
    echo -e "Public IP     : ${IP_ADDR} (${COUNTRY})"
    echo -e "Host          : ${PRIMARY_DOMAIN}"
    echo -e "ISP Provider  : ${ISP}"
    echo -e "========================================"
    echo -e "Nameserver    : ${NS_DOMAIN}"
    echo -e "PubKey        : ${PUB_KEY}"
    echo -e "DNS Resolver  : 1.1.1.1 / 8.8.8.8\n"
    
    echo -e "OpenSSH     : 22"
    echo -e "Dropbear    : ${PORT_DROPBEAR:-109}, ${PORT_DROPBEAR_ALT:-143}"
    echo -e "SSH WS      : 80, 8080, 8880"
    echo -e "SSH WSS     : 443, 8443"
    echo -e "DNSTT       : 53, 5300"
    echo -e "SOCKS5      : ${PORT_SOCKS:-1080}"
    echo -e "UDP Custom  : 1-65535"
    echo -e "========================================"
    echo -e "SSH-80        : ${PRIMARY_DOMAIN}:${PORT_WS_HTTP:-80}@${USERNAME}:${PASSWORD}"
    echo -e "SSH-443       : ${PRIMARY_DOMAIN}:${PORT_WS_HTTPS:-443}@${USERNAME}:${PASSWORD}"
    echo -e "SOCKS5        : ${PRIMARY_DOMAIN}:${PORT_SOCKS:-1080}:${USERNAME}:${PASSWORD}"
    echo -e "SSH-8880      : ${PRIMARY_DOMAIN}:8880@${USERNAME}:${PASSWORD}"
    echo -e "========================================"
    echo -e "WSS Payload"
    echo -e "GET wss://bug.com [protocol][crlf]Host: ${PRIMARY_DOMAIN}[crlf]Upgrade: websocket[crlf][crlf]\n"
    echo -e "WS Payload"
    echo -e "GET / HTTP/1.1[crlf]Host: ${PRIMARY_DOMAIN}[crlf]Upgrade: websocket[crlf][crlf]\n"
    echo -e "Custom Payload"
    echo -e "GET http://${PRIMARY_DOMAIN}:8880 HTTP/1.1[crlf]Host: [SNI_BUG_HOST][crlf]Upgrade: websocket[crlf]Connection: Upgrade[crlf][crlf]"
    echo -e "========================================"
    echo -e "     NO SPAM | NO DDOS | NO TORRENT"
    echo -e "========================================"
    
    pause
}

# --- Helper function for Interactive Lists ---
select_user_from_list() {
    local list_type="${1:-SSH}"
    local user_count=$(sqlite3 "$DB_PATH" "SELECT COUNT(*) FROM users WHERE account_type='$list_type';" 2>/dev/null || echo "0")
    if [ "$user_count" -eq 0 ]; then
        echo -e "\n${ORANGE}[!] No ${list_type} users found in the database.${NC}"
        sleep 2; FINAL_USERNAME=""; return
    fi

    draw_line
    printf "${BOLD}%-5s | %-15s | %-15s${NC}\n" "S/N" "USERNAME" "EXPIRES ON"
    draw_line
    
    mapfile -t USER_LIST < <(sqlite3 -separator '|' "$DB_PATH" "SELECT username, expiry_date FROM users WHERE account_type='$list_type';")
    local i=1
    for user_data in "${USER_LIST[@]}"; do
        local uname=$(echo "$user_data" | cut -d'|' -f1)
        local exp=$(echo "$user_data" | cut -d'|' -f2 | cut -d' ' -f1)
        printf "${GREEN}%-5s${NC} | ${CYAN}%-15s${NC} | ${ORANGE}%-15s${NC}\n" "$i" "$uname" "$exp"
        ((i++))
    done
    draw_line
    echo -e "${ORANGE}[0] Cancel${NC}\n"

    read -p "Select S/N or type Username: " TARGET_USER
    if [[ "$TARGET_USER" == "0" || -z "$TARGET_USER" ]]; then FINAL_USERNAME=""; return; fi

    FINAL_USERNAME=""
    if [[ "$TARGET_USER" =~ ^[0-9]+$ ]] && [ "$TARGET_USER" -le "${#USER_LIST[@]}" ] && [ "$TARGET_USER" -gt 0 ]; then
        local index=$((TARGET_USER - 1))
        FINAL_USERNAME=$(echo "${USER_LIST[$index]}" | cut -d'|' -f1)
        FINAL_EXPIRY=$(echo "${USER_LIST[$index]}" | cut -d'|' -f2)
    else
        for user_data in "${USER_LIST[@]}"; do
            local uname=$(echo "$user_data" | cut -d'|' -f1)
            if [[ "$uname" == "$TARGET_USER" ]]; then
                FINAL_USERNAME="$uname"
                FINAL_EXPIRY=$(echo "$user_data" | cut -d'|' -f2)
                break
            fi
        done
    fi

    if [[ -z "$FINAL_USERNAME" ]]; then
        echo -e "\n${RED}[-] Invalid selection.${NC}"; sleep 1; FINAL_USERNAME=""
    fi
}

print_user_receipt() {
    local USERNAME="$1"
    local PASSWORD="$2"
    local TIME_VAL="$3"
    local TIME_TYPE="$4"
    local MAX_LOGINS="${5:-2}" 
    local BW_LIMIT="${6:-0}"
    
    IP_ADDR=$(curl -sS ipv4.icanhazip.com)
    PUB_KEY=$(cat /opt/janabitech/core/keys/dnstt.pub 2>/dev/null || echo "Missing Key")
    
    source /opt/janabitech/core/server_geo.env 2>/dev/null
    local COUNTRY="${SERVER_COUNTRY:-Unknown}"
    local ISP="${SERVER_ISP:-Unknown}"
    
    local EXP_LABEL="Expires On  "
    local HEADER_MSG="Account Created Successfully"
    local FOOTER_MSG=""

    if [ "$TIME_TYPE" == "hours" ]; then
        EXP_DATE_FORMATTED=$(date -d "+${TIME_VAL} hours" +"%B %d, %Y - %H:%M")
        EXP_LABEL="Valid Until "
        HEADER_MSG="Trial Account Activated"
        FOOTER_MSG="\n${DIM}  ⏳ This trial will expire and be removed automatically.${NC}"
    else
        EXP_DATE_FORMATTED=$(date -d "+${TIME_VAL} days" +"%B %d, %Y")
    fi

    local LOGIN_DISP="$MAX_LOGINS"
    if [ "$MAX_LOGINS" -eq 0 ]; then LOGIN_DISP="Unlimited"; fi

    local BW_DISP="${BW_LIMIT} GB"
    if [ "$BW_LIMIT" -eq 0 ]; then BW_DISP="Unlimited"; fi

    local UUID=$(sqlite3 "$DB_PATH" "SELECT uuid FROM users WHERE username='$USERNAME';")

    clear
    local SEP="${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

    echo -e "$SEP"
    echo -e "   ✅ ${BRIGHT_GREEN}${HEADER_MSG}${NC} ✅"
    echo -e "$SEP"
    echo -e "👤 ${DIM}Username${NC}  : ${BRIGHT_GREEN}${USERNAME}${NC}"
    echo -e "🔑 ${DIM}Password${NC}  : ${BRIGHT_GREEN}${PASSWORD}${NC}"
    echo -e "📱 ${DIM}Limit${NC}     : ${BRIGHT_CYAN}${LOGIN_DISP}${NC}"
    echo -e "💾 ${DIM}Data${NC}      : ${BRIGHT_CYAN}${BW_DISP}${NC}"
    if [ "$TIME_TYPE" == "hours" ]; then
        echo -e "⏳ ${DIM}Duration${NC}  : ${BRIGHT_YELLOW}${TIME_VAL} hours${NC}"
    fi
    echo -e "📅 ${DIM}${EXP_LABEL}${NC} : ${BRIGHT_YELLOW}${EXP_DATE_FORMATTED}${NC}"
    echo -e "$SEP"
    echo -e "🌍 ${BRIGHT_WHITE}SERVER DETAILS${NC} 🌍"
    echo -e "IP      : ${GREEN}${IP_ADDR}${NC} ${DIM}(${COUNTRY})${NC}"
    echo -e "Host    : ${BRIGHT_GREEN}${PRIMARY_DOMAIN}${NC}"
    echo -e "ISP     : ${CYAN}${ISP}${NC}"
    echo -e "NS      : ${CYAN}${NS_DOMAIN}${NC}"
    echo -e "DNS     : ${CYAN}1.1.1.1 / 8.8.8.8${NC}"
    echo -e "DNSTT   : ${DIM}${PUB_KEY}${NC}"
    echo -e ""
    echo -e "$SEP"
    echo -e "🔌 ${BRIGHT_WHITE}CONNECTION PORTS${NC} 🔌"
    echo -e "OpenSSH     : ${GREEN}22${NC}"
    echo -e "Dropbear    : ${GREEN}${PORT_DROPBEAR:-109}, ${PORT_DROPBEAR_ALT:-143}${NC}"
    echo -e "SSH WS      : ${GREEN}80, 8080, 8880${NC}"
    echo -e "SSH WSS     : ${GREEN}443, 8443${NC}"
    echo -e "DNSTT       : ${GREEN}53, 5300${NC}"
    echo -e "SOCKS5      : ${GREEN}${PORT_SOCKS:-1080}${NC}"
    echo -e "UDP Custom  : ${GREEN}1-65535${NC}"
    echo -e "$SEP"
    echo -e "⚙️ ${BRIGHT_WHITE}QUICK CONNECT${NC} ⚙️"
    echo -e "SSH-80  : ${PRIMARY_DOMAIN}:80@${USERNAME}:${PASSWORD}"
    echo -e "SSH-443 : ${PRIMARY_DOMAIN}:443@${USERNAME}:${PASSWORD}"
    echo -e "SOCKS5  : ${PRIMARY_DOMAIN}:${PORT_SOCKS:-1080}:${USERNAME}:${PASSWORD}"
    echo -e "Custom  : ${PRIMARY_DOMAIN}:8080@${USERNAME}:${PASSWORD}"
    echo -e "$SEP"
    echo -e "📜 ${BRIGHT_WHITE}PAYLOADS${NC} 📜"
    echo -e "${BRIGHT_CYAN}WSS:${NC} GET wss://bug.com [protocol][crlf]Host: ${PRIMARY_DOMAIN}[crlf]Upgrade: websocket[crlf][crlf]"
    echo -e "$SEP"
    echo -e "${BRIGHT_CYAN}WS:${NC} GET / HTTP/1.1[crlf]Host: ${PRIMARY_DOMAIN}[crlf]Upgrade: websocket[crlf][crlf]"
    echo -e "$SEP"
    echo -e "${BRIGHT_CYAN}Custom:${NC} GET http://${PRIMARY_DOMAIN}:8080 HTTP/1.1[crlf]Host: [SNI_BUG_HOST][crlf]Upgrade: websocket[crlf]Connection: Upgrade[crlf][crlf]"
    echo -e "$SEP"
    echo -e "⚠ ${BRIGHT_RED}NO SPAM • NO DDOS • NO TORRENT${NC} ⚠"
    echo -e "🛒 ${BRIGHT_MAGENTA}Subscribe → @imagivpnbot  •  t.me/janabitech001${NC}"
    echo -e "$SEP"
    echo -e "${DIM}Copy the text above to share with the user${NC}"
    if [[ -n "$FOOTER_MSG" ]]; then echo -e "$FOOTER_MSG"; fi
    
    pause
}

execute_locked_users() {
    local list_type="${1:-SSH}"
    clear
    echo -e "${CYAN}=== LOCKED/BANNED ${list_type} USERS ===${NC}"
    
    local locked_count=$(sqlite3 "$DB_PATH" "SELECT COUNT(*) FROM users WHERE status='LOCKED' AND account_type='$list_type';" 2>/dev/null || echo "0")
    if [ "$locked_count" -eq 0 ]; then
        echo -e "\n${GREEN}[+] No locked ${list_type} users found.${NC}"
        pause
        return
    fi

    draw_line
    printf "${BOLD}%-5s | %-15s | %-15s${NC}\n" "S/N" "USERNAME" "EXPIRY DATE"
    draw_line
    
    mapfile -t USER_LIST < <(sqlite3 -separator '|' "$DB_PATH" "SELECT username, expiry_date FROM users WHERE status='LOCKED' AND account_type='$list_type';")
    local i=1
    for user_data in "${USER_LIST[@]}"; do
        local uname=$(echo "$user_data" | cut -d'|' -f1)
        local exp=$(echo "$user_data" | cut -d'|' -f2 | cut -d' ' -f1)
        printf "${RED}%-5s${NC} | ${CYAN}%-15s${NC} | ${ORANGE}%-15s${NC}\n" "$i" "$uname" "$exp"
        ((i++))
    done
    draw_line
    echo -e "${ORANGE}[0] Cancel${NC}\n"

    read -p " Select S/N to UNLOCK user: " TARGET_USER
    if [[ "$TARGET_USER" == "0" || -z "$TARGET_USER" ]]; then return; fi

    local FINAL_USERNAME=""
    if [[ "$TARGET_USER" =~ ^[0-9]+$ ]] && [ "$TARGET_USER" -le "${#USER_LIST[@]}" ] && [ "$TARGET_USER" -gt 0 ]; then
        local index=$((TARGET_USER - 1))
        FINAL_USERNAME=$(echo "${USER_LIST[$index]}" | cut -d'|' -f1)
    fi

    if [[ -z "$FINAL_USERNAME" ]]; then
        echo -e "\n${RED}[-] Invalid selection.${NC}"; sleep 1; return
    fi

    echo -e "\n${GREEN}Unlocking user: ${FINAL_USERNAME}...${NC}"
    usermod -U "$FINAL_USERNAME" 2>/dev/null
    sqlite3 "$DB_PATH" "UPDATE users SET status='ACTIVE' WHERE username='$FINAL_USERNAME';" 2>/dev/null
    echo -e "${GREEN}[+] User unlocked successfully!${NC}"
    pause
}

# ==========================================================
# [02] DOMAIN & SSL
# ==========================================================
menu_domain_ssl() {
    while true; do
        clear
        # Re-source config inside the loop so the UI updates dynamically if a domain changes
        source /opt/janabitech/core/janabitech.conf 2>/dev/null || true
        local PUB_KEY=$(cat /opt/janabitech/core/keys/dnstt.pub 2>/dev/null || echo "Missing Key")
        
        draw_line
        echo -e "                   ${BOLD}DOMAIN & SSL${NC}                     "
        draw_line
        echo -e "  Current Host : ${GREEN}${PRIMARY_DOMAIN}${NC}"
        echo -e "  Current SNI  : ${MAGENTA}${REALITY_SNI:-www.microsoft.com}${NC}"
        echo -e "  Current NS   : ${CYAN}${NS_DOMAIN}${NC}"
        echo -e "  SlowDNS Pub  : ${ORANGE}${PUB_KEY}${NC}"
        draw_line
        echo -e "  ${CYAN}[01]${NC} Change Host Domain"
        echo -e "  ${CYAN}[02]${NC} Change NS Domain"
        echo -e "  ${CYAN}[03]${NC} Change REALITY SNI Domain"
        echo -e "  ${CYAN}[04]${NC} Renew SSL Certificate (Let's Encrypt)"
        echo -e "  ${CYAN}[05]${NC} View Certificate Status"
        echo -e "  ${CYAN}[06]${NC} Generate New SlowDNS Key"
        echo -e ""
        echo -e "  ${RED}[00]${NC} Return to Main Menu"
        draw_line
        read -p " Select Option : " opt

        case $opt in
            1) 
                echo -e "\n${CYAN}Current Domain: ${PRIMARY_DOMAIN}${NC}"
                read -p "Enter New Host Domain: " new_host
                if [[ -n "$new_host" ]]; then
                    /opt/janabitech/bin/janabitech config host "$new_host"
                    echo ""
                    read -p "Renew Let's Encrypt SSL for $new_host now? (y/n): " do_ssl
                    if [[ "$do_ssl" =~ ^[Yy] ]]; then
                        echo -e "\n${ORANGE}[*] Requesting Certificate... this takes 30-60 seconds...${NC}"
                        /opt/janabitech/bin/janabitech cert renew "$new_host"
                    fi
                fi
                pause ;;
            2) 
                echo -e "\n${CYAN}Current NS Domain: ${NS_DOMAIN}${NC}"
                read -p "Enter New NS Domain: " new_ns
                if [[ -n "$new_ns" ]]; then
                    /opt/janabitech/bin/janabitech config ns "$new_ns"
                fi
                pause ;;
            3)
                echo -e "\n${MAGENTA}Current REALITY SNI: ${REALITY_SNI:-www.microsoft.com}${NC}"
                echo -e "\n  ${BOLD}Global Defaults${NC}"
                echo -e "  ${CYAN}[1]${NC} www.bing.com"
                echo -e "  ${CYAN}[2]${NC} www.apple.com"
                echo -e "  ${CYAN}[3]${NC} www.amazon.com"
                echo -e "  ${CYAN}[4]${NC} www.cloudflare.com"
                echo -e "\n  ${BOLD}Regional Presets${NC}"
                echo -e "  ${CYAN}[5]${NC} storage.yandex.net"
                echo -e "  ${CYAN}[6]${NC} pl02.launch.tel"
                echo -e "  ${CYAN}[7]${NC} www.ya.ru"
                echo -e "  ${CYAN}[8]${NC} www.lovelive-anime.jp"
                echo -e "  ${CYAN}[9]${NC} iping.ggff.net"
                echo -e "  ${CYAN}[10]${NC} eh.vk.com"
                echo -e "\n  ${BOLD}Custom${NC}"
                echo -e "  ${CYAN}[11]${NC} Enter Custom SNI manually"
                echo -e "  ${RED}[0]${NC} Cancel"
                echo -e ""
                read -p " Select Option : " sni_opt

                local new_sni=""
                case $sni_opt in
                    1) new_sni="www.bing.com" ;;
                    2) new_sni="www.apple.com" ;;
                    3) new_sni="www.amazon.com" ;;
                    4) new_sni="www.cloudflare.com" ;;
                    5) new_sni="storage.yandex.net" ;;
                    6) new_sni="pl02.launch.tel" ;;
                    7) new_sni="www.ya.ru" ;;
                    8) new_sni="www.lovelive-anime.jp" ;;
                    9) new_sni="iping.ggff.net" ;;
                    10) new_sni="eh.vk.com" ;;
                    11)
                        echo -e "${ORANGE}[!] We recommend checking valid SNIs at https://www.ssllabs.com/ssltest/${NC}"
                        read -p "Enter Custom SNI (e.g., www.microsoft.com): " new_sni
                        ;;
                    0) ;;
                    *) echo -e "${RED}Invalid option${NC}" ;;
                esac

                if [[ -n "$new_sni" ]]; then
                    /opt/janabitech/bin/janabitech config sni "$new_sni"
                fi
                pause ;;
            4) 
                echo -e "\n${ORANGE}[*] Requesting Let's Encrypt Certificate. Services will temporarily pause...${NC}"
                /opt/janabitech/bin/janabitech cert renew "$PRIMARY_DOMAIN"
                pause ;;
            5) 
                clear
                echo -e "${CYAN}=== ACME.SH CERTIFICATE STATUS ===${NC}"
                /root/.acme.sh/acme.sh --list 2>/dev/null || echo -e "${RED}acme.sh is not installed yet.${NC}"
                pause ;;
            6) 
                echo -e "\n${ORANGE}[*] Warning: Changing keys will break existing SlowDNS clients.${NC}"
                echo -e "1. Generate Random Keys"
                echo -e "2. Input Custom Keys"
                read -p "Select Option: " key_opt
                if [[ "$key_opt" == "1" ]]; then
                    read -p "Are you sure? (y/n): " confirm_dnstt
                    if [[ "$confirm_dnstt" =~ ^[Yy] ]]; then
                        /opt/janabitech/bin/janabitech dnstt renew
                    fi
                elif [[ "$key_opt" == "2" ]]; then
                    read -p "Enter Public Key: " custom_pub
                    read -p "Enter Private Key: " custom_priv
                    if [[ -n "$custom_pub" && -n "$custom_priv" ]]; then
                        echo "$custom_pub" > /opt/janabitech/core/keys/dnstt.pub
                        echo "$custom_priv" > /opt/janabitech/core/keys/dnstt.key
                        systemctl restart janabitech-dnstt
                        echo -e "${GREEN}Custom keys applied!${NC}"
                    else
                        echo -e "${RED}Keys cannot be empty.${NC}"
                    fi
                fi
                pause ;;
            0|00) return ;;
            *) echo -e "${RED}Invalid option${NC}"; sleep 1 ;;
        esac
    done
}

# ==========================================================
# [03] RUNNING SERVICES
# ==========================================================
menu_services() {
    while true; do
        clear
        draw_line
        echo -e "                 ${BOLD}RUNNING SERVICES${NC}                   "
        draw_line
        echo -e "  ${CYAN}OpenSSH           :${NC} 22"
        echo -e "  ${CYAN}Dropbear          :${NC} 109, 143"
        echo -e "  ${CYAN}HAProxy HTTP      :${NC} 80, 8080, 8880"
        echo -e "  ${CYAN}HAProxy HTTPS     :${NC} 443, 8443"
        echo -e "  ${CYAN}Xray/V2Ray        :${NC} 80, 8080, 443"
        echo -e "  ${CYAN}SlowDNS (DNSTT)   :${NC} 53, 5300"
        echo -e "  ${CYAN}Nginx Decoy       :${NC} 8081"
        echo -e "  ${CYAN}UDP Custom        :${NC} 1-65535"
        echo -e "  ${CYAN}SOCKS5 Proxy      :${NC} 1080"
        draw_line
        echo -e "  ${CYAN}[01]${NC} Restart All Services"
        echo -e "  ${CYAN}[02]${NC} Restart Dropbear"
        echo -e "  ${CYAN}[03]${NC} Restart WebSocket Proxy"
        echo -e "  ${CYAN}[04]${NC} Restart HAProxy"
        echo -e "  ${CYAN}[05]${NC} Restart Xray Core"
        echo -e "  ${CYAN}[06]${NC} Restart DNSTT"
        echo -e ""
        echo -e "  ${RED}[00]${NC} Return to Main Menu"
        draw_line
        read -p " Select Option : " opt

        case $opt in
            1) /opt/janabitech/bin/janabitech service restart all; pause ;;
            2) /opt/janabitech/bin/janabitech service restart dropbear; pause ;;
            3) /opt/janabitech/bin/janabitech service restart janabitech-ws; pause ;;
            4) /opt/janabitech/bin/janabitech service restart haproxy; pause ;;
            5) /opt/janabitech/bin/janabitech service restart janabitech-xray; pause ;;
            6) /opt/janabitech/bin/janabitech service restart janabitech-dnstt; pause ;;
            0|00) return ;;
            *) echo -e "${RED}Invalid option${NC}"; sleep 1 ;;
        esac
    done
}

# ==========================================================
# [04] MONITORING
# ==========================================================
format_bytes() {
    local bytes=$1
    if [[ -z "$bytes" || "$bytes" -eq 0 ]]; then
        echo "0.00 MB"
    elif [[ $bytes -ge 1073741824 ]]; then
        echo "$(awk "BEGIN {printf \"%.2f\", $bytes/1073741824}") GB"
    else
        echo "$(awk "BEGIN {printf \"%.2f\", $bytes/1048576}") MB"
    fi
}

menu_monitoring() {
    while true; do
        clear
        draw_line
        echo -e "                    ${BOLD}MONITORING${NC}                      "
        draw_line
        echo -e "  ${CYAN}[01]${NC} Current Bandwidth Usage (All Users)"
        echo -e "  ${CYAN}[02]${NC} Top Users (Leaderboard)"
        echo -e "  ${CYAN}[03]${NC} Connection Logs"
        echo -e "  ${CYAN}[04]${NC} Failed Login Attempts"
        echo -e "  ${CYAN}[05]${NC} System Resource Usage"
        echo -e ""
        echo -e "  ${RED}[00]${NC} Return to Main Menu"
        draw_line
        read -p " Select Option : " opt

        case $opt in
            1) 
                clear
                echo -e "${CYAN}=== TOTAL BANDWIDTH USAGE ===${NC}"
                draw_line
                printf "${BOLD}%-5s | %-15s | %-15s${NC}\n" "S/N" "USERNAME" "DATA USED"
                draw_line
                
                local i=1
                sqlite3 -separator '|' "$DB_PATH" "SELECT username, data_usage FROM users ORDER BY username ASC;" | while read -r line; do
                    local uname=$(echo "$line" | cut -d'|' -f1)
                    local bytes=$(echo "$line" | cut -d'|' -f2)
                    local formatted=$(format_bytes "$bytes")
                    printf "${GREEN}%-5s${NC} | ${CYAN}%-15s${NC} | ${ORANGE}%-15s${NC}\n" "$i" "$uname" "$formatted"
                    ((i++))
                done
                draw_line
                pause ;;
            2) 
                clear
                echo -e "${CYAN}=== TOP USERS (DATA LEADERBOARD) ===${NC}"
                draw_line
                printf "${BOLD}%-5s | %-15s | %-15s${NC}\n" "RANK" "USERNAME" "DATA USED"
                draw_line
                
                local rank=1
                # Sort by data_usage descending, limit to top 10
                sqlite3 -separator '|' "$DB_PATH" "SELECT username, data_usage FROM users WHERE data_usage > 0 ORDER BY data_usage DESC LIMIT 10;" | while read -r line; do
                    local uname=$(echo "$line" | cut -d'|' -f1)
                    local bytes=$(echo "$line" | cut -d'|' -f2)
                    local formatted=$(format_bytes "$bytes")
                    
                    # Highlight the #1 user in red/gold
                    if [ "$rank" -eq 1 ]; then
                        printf "${RED}%-5s${NC} | ${GREEN}%-15s${NC} | ${ORANGE}%-15s${NC}\n" "#$rank" "$uname" "$formatted"
                    else
                        printf "${GREEN}%-5s${NC} | ${CYAN}%-15s${NC} | ${ORANGE}%-15s${NC}\n" "#$rank" "$uname" "$formatted"
                    fi
                    ((rank++))
                done
                if [ "$rank" -eq 1 ]; then
                    echo -e "  ${ORANGE}No data usage recorded yet.${NC}"
                fi
                draw_line
                pause ;;
            3) tail -n 50 /opt/janabitech/logs/janabitech.log; pause ;;
            4) grep "Failed password" /var/log/auth.log | tail -n 20; pause ;;
            5) 
               if [ -x "/opt/janabitech/bin/btop" ]; then
                   /opt/janabitech/bin/btop
               else
                   htop || top
               fi
               pause ;;
            0|00) return ;;
            *) echo -e "${RED}Invalid option${NC}"; sleep 1 ;;
        esac
    done
}

# ==========================================================
# [05] SETTINGS
# ==========================================================
menu_settings() {
    while true; do
        # 1. Auto Reboot Status
        local rb_status="${RED}[OFF]${NC}"
        local cron_entry=$(crontab -l 2>/dev/null | grep "/sbin/reboot" | head -n 1)
        if [[ -n "$cron_entry" ]]; then
            local min=$(echo "$cron_entry" | awk '{print $1}')
            local hr=$(echo "$cron_entry" | awk '{print $2}')
            if [[ "$hr" =~ ^\*/([0-9]+)$ ]]; then
                rb_status="${GREEN}[ON ${BASH_REMATCH[1]}H]${NC}"
            elif [[ "$hr" =~ ^[0-9]+$ ]] && [[ "$min" =~ ^[0-9]+$ ]]; then
                printf -v formatted_time "%02d:%02d" "$hr" "$min"
                rb_status="${GREEN}[ON ${formatted_time}]${NC}"
            else
                rb_status="${GREEN}[ON]${NC}"
            fi
        fi

        # 6. Fail2Ban Status
        local f2b_status="${RED}[OFF]${NC}"
        if systemctl is-active --quiet fail2ban; then
            f2b_status="${GREEN}[ON]${NC}"
        fi

        # 7. Telegram Bot Status
        local tg_status="${RED}[OFF]${NC}"
        if systemctl is-active --quiet janabitech-telegram; then
            tg_status="${GREEN}[ON]${NC}"
        fi

        # 8. Timezone Status
        local tz=$(timedatectl show --property=Timezone --value 2>/dev/null || cat /etc/timezone 2>/dev/null || echo "Unknown")
        local tz_status="${GREEN}[${tz}]${NC}"

        clear
        draw_line
        echo -e "                     ${BOLD}SETTINGS${NC}                       "
        draw_line
        printf "  ${CYAN}[01]${NC} %-35s %b\n" "Set Auto Reboot" "${rb_status}"
        printf "  ${CYAN}[02]${NC} %-35s\n" "Change SSH Banner"
        printf "  ${CYAN}[03]${NC} %-35s\n" "Speedtest Server"
        printf "  ${CYAN}[04]${NC} %-35s\n" "Uninstall Script"
        printf "  ${CYAN}[05]${NC} %-35s\n" "Refresh Server Geo-Data"
        printf "  ${CYAN}[06]${NC} %-35s %b\n" "Deploy Fail2Ban Firewall" "${f2b_status}"
        printf "  ${CYAN}[07]${NC} %-35s %b\n" "Configure Telegram Bot Controller" "${tg_status}"
        printf "  ${CYAN}[08]${NC} %-35s %b\n" "Set Server Timezone" "${tz_status}"
        echo -e ""
        echo -e "  ${RED}[00]${NC} Return to Main Menu"
        draw_line
        read -p " Select Option : " opt

        case $opt in
            1) 
                echo -e "\n${CYAN}Auto Reboot Schedule${NC}"
                echo "1. Every 6 Hours"
                echo "2. Every 12 Hours"
                echo "3. Every 24 Hours"
                echo "4. Set Specific Daily Time (e.g., 03:00 or 15:00)"
                echo "0. Turn Off Auto Reboot"
                read -p "Select Option: " rb_opt
                case $rb_opt in
                    1) /opt/janabitech/bin/janabitech sys autoreboot 6 ;;
                    2) /opt/janabitech/bin/janabitech sys autoreboot 12 ;;
                    3) /opt/janabitech/bin/janabitech sys autoreboot 24 ;;
                    4) 
                        read -p "Enter time in 24h format (HH:MM): " specific_time
                        if [[ "$specific_time" =~ ^([0-9]{1,2}):([0-9]{2})$ ]]; then
                            /opt/janabitech/bin/janabitech sys autoreboot "$specific_time"
                        else
                            echo -e "${RED}Invalid time format. Please use HH:MM (e.g., 15:30).${NC}"
                        fi
                        ;;
            0|00) /opt/janabitech/bin/janabitech sys autoreboot 0 ;;
                    *) echo -e "${RED}Invalid selection.${NC}" ;;
                esac
                pause ;;
            2) 
                clear
                echo -e "\n${CYAN}=== UPDATE SSH BANNER ===${NC}"
                echo -e "${ORANGE}Opening /etc/issue.net in nano editor...${NC}"
                echo -e "Instructions:"
                echo -e "  1. Edit your HTML code."
                echo -e "  2. Press ${GREEN}CTRL + O${NC} then ${GREEN}ENTER${NC} to save."
                echo -e "  3. Press ${GREEN}CTRL + X${NC} to exit."
                echo ""
                read -n 1 -s -r -p "Press any key to open the editor..."
                
                # Call the API which now handles launching nano natively
                /opt/janabitech/bin/janabitech sys banner
                
                pause ;;
            3) 
               clear
               echo -e "${CYAN}Initializing Server Speedtest...${NC}\n"
               if [ -x "/opt/janabitech/bin/speedtest" ]; then
                   /opt/janabitech/bin/speedtest --accept-license --accept-gdpr
               else
                   echo -e "${RED}[!] Ookla Speedtest binary not found. Please re-run the installer.${NC}"
               fi
               pause ;;
            4) 
                clear
                echo -e "${RED}${BOLD}======================================================${NC}"
                echo -e "${RED}${BOLD}  DANGER: COMPLETELY UNINSTALL JANABITECH PLATFORM     ${NC}"
                echo -e "${RED}${BOLD}======================================================${NC}"
                echo -e "This action will:"
                echo -e "  - Delete all VPN accounts & databases"
                echo -e "  - Remove all Sidecars, Ports, and Routing rules"
                echo -e "  - Wipe the /opt/janabitech directory entirely\n"
                
                read -p "Are you absolutely sure? (Type 'YES' to confirm): " confirm_wipe
                if [ "$confirm_wipe" == "YES" ]; then
                    echo -e "\n${ORANGE}[*] Wiping infrastructure...${NC}"
                    /opt/janabitech/bin/janabitech sys uninstall
                    echo -e "${GREEN}System is clean. Exiting...${NC}"
                    sleep 2
                    exit 0
                else
                    echo -e "\n${GREEN}Uninstallation aborted.${NC}"
                    pause
                fi
                ;;
            5)
                echo -e "\n${CYAN}[*] Flushing Server Geo-Data cache...${NC}"
                rm -f /opt/janabitech/core/server_geo.env
                fetch_server_geo
                echo -e "${GREEN}[+] Geographic data successfully refreshed!${NC}"
                pause ;;
            6)
                clear
                echo -e "\n${CYAN}=== DEPLOY FAIL2BAN FIREWALL ===${NC}"
                echo -e "${ORANGE}This will automatically install and configure Fail2Ban${NC}"
                echo -e "to instantly block bots that fail 3 login attempts.\n"
                read -p "Proceed with deployment? (y/n): " confirm_f2b
                if [[ "$confirm_f2b" =~ ^[Yy] ]]; then
                    echo ""
                    /opt/janabitech/bin/janabitech sys fail2ban
                fi
                pause ;;
            7)
                while true; do
                    clear
                    echo -e "\n${CYAN}=== TELEGRAM BOT CONTROLLER ===${NC}"
                    if systemctl is-active --quiet janabitech-telegram 2>/dev/null; then
                        echo -e "Status: ${GREEN}[ACTIVE]${NC}"
                    else
                        echo -e "Status: ${RED}[DISABLED/INACTIVE]${NC}"
                    fi
                    echo -e ""
                    echo -e "  ${CYAN}[1]${NC} Configure/Update Bot Token"
                    echo -e "  ${CYAN}[2]${NC} Enable & Start Bot"
                    echo -e "  ${CYAN}[3]${NC} Disable & Stop Bot"
                    echo -e "  ${RED}[0]${NC} Back to Settings"
                    echo -e ""
                    read -p "Select Option: " tbot_opt
                    
                    case $tbot_opt in
                        1)
                            echo -e "\nControl your VPS directly from Telegram."
                            read -p "Enter your Telegram Bot Token (from @BotFather): " bot_token
                            read -p "Enter your Telegram User ID (e.g., 123456789): " admin_id
                            
                            if [ -n "$bot_token" ] && [ -n "$admin_id" ]; then
                                echo "BOT_TOKEN=\"$bot_token\"" > /opt/janabitech/core/telegram.conf
                                echo "ADMIN_ID=\"$admin_id\"" >> /opt/janabitech/core/telegram.conf
                                
                                # Install systemd service
                                cat <<'EOF' > /tmp/janabitech-telegram.service.tmp
[Unit]
Description=Janabitech Telegram Controller
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/opt/janabitech/services/monitor
ExecStart=/bin/bash -c 'if [ -f /opt/janabitech/services/monitor/telegram-controller ]; then exec /opt/janabitech/services/monitor/telegram-controller; else exec /usr/bin/python3 -u /opt/janabitech/services/monitor/telegram-controller.py; fi'
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF
                                mv /tmp/janabitech-telegram.service.tmp /etc/systemd/system/janabitech-telegram.service
                                systemctl daemon-reload
                                systemctl enable janabitech-telegram >/dev/null 2>&1
                                systemctl restart janabitech-telegram
                                
                                echo -e "\n${GREEN}[✓] Telegram Controller configured and started!${NC}"
                                echo -e "Send /start to your bot to test it."
                            else
                                echo -e "\n${RED}[!] Invalid configuration. Aborting.${NC}"
                            fi
                            pause
                            ;;
                        2)
                            echo -e "\n${CYAN}[*] Starting Bot Controller...${NC}"
                            systemctl enable janabitech-telegram >/dev/null 2>&1
                            systemctl start janabitech-telegram >/dev/null 2>&1
                            echo -e "${GREEN}[+] Bot Controller Enabled!${NC}"
                            pause
                            ;;
                        3)
                            echo -e "\n${ORANGE}[*] Stopping Bot Controller...${NC}"
                            systemctl stop janabitech-telegram >/dev/null 2>&1
                            systemctl disable janabitech-telegram >/dev/null 2>&1
                            echo -e "${GREEN}[+] Bot Controller Disabled!${NC}"
                            pause
                            ;;
            0|00) break ;;
                        *) echo -e "${RED}Invalid option${NC}"; sleep 1 ;;
                    esac
                done
                ;;
            8)
                while true; do
                    clear
                    echo -e "\n${CYAN}=== SET SERVER TIMEZONE ===${NC}"
                    echo -e "Current Timezone: ${GREEN}$(timedatectl show -p Timezone --value)${NC}"
                    echo -e ""
                    echo -e "  ${CYAN}[1]${NC} Africa/Lagos"
                    echo -e "  ${CYAN}[2]${NC} Asia/Jakarta"
                    echo -e "  ${CYAN}[3]${NC} Asia/Shanghai"
                    echo -e "  ${CYAN}[4]${NC} Europe/Moscow"
                    echo -e "  ${CYAN}[5]${NC} UTC"
                    echo -e "  ${CYAN}[6]${NC} Enter Custom Timezone"
                    echo -e "  ${RED}[0]${NC} Back to Settings"
                    echo -e ""
                    read -p "Select Option: " tz_opt
                    
                    case $tz_opt in
                        1) sudo timedatectl set-timezone Africa/Lagos; echo -e "${GREEN}Timezone set to Africa/Lagos${NC}"; pause ;;
                        2) sudo timedatectl set-timezone Asia/Jakarta; echo -e "${GREEN}Timezone set to Asia/Jakarta${NC}"; pause ;;
                        3) sudo timedatectl set-timezone Asia/Shanghai; echo -e "${GREEN}Timezone set to Asia/Shanghai${NC}"; pause ;;
                        4) sudo timedatectl set-timezone Europe/Moscow; echo -e "${GREEN}Timezone set to Europe/Moscow${NC}"; pause ;;
                        5) sudo timedatectl set-timezone UTC; echo -e "${GREEN}Timezone set to UTC${NC}"; pause ;;
                        6) 
                            echo -e "\nExample custom timezones: America/New_York, Europe/London"
                            read -p "Enter Timezone: " custom_tz
                            if timedatectl list-timezones | grep -q "^${custom_tz}$"; then
                                sudo timedatectl set-timezone "$custom_tz"
                                echo -e "${GREEN}Timezone set to $custom_tz${NC}"
                            else
                                echo -e "${RED}Invalid timezone. Use 'timedatectl list-timezones' to see valid options.${NC}"
                            fi
                            pause ;;
            0|00) break ;;
                        *) echo -e "${RED}Invalid option${NC}"; sleep 1 ;;
                    esac
                done
                ;;
            0|00) return ;;
            *) echo -e "${RED}Invalid option${NC}"; sleep 1 ;;
        esac
    done
}

menu_backup_restore() {
    while true; do
        clear
        draw_line
        echo -e "                 ${BOLD}BACKUP & RESTORE${NC}                   "
        draw_line
        local imagi_status="${RED}[OFF]${NC}"
        if grep -q "JANABITECH_BACKUP_URL" /opt/janabitech/core/telegram.conf 2>/dev/null; then
            imagi_status="${GREEN}[ON]${NC}"
        fi
        
        local tg_backup_status="${RED}[OFF]${NC}"
        if crontab -l 2>/dev/null | grep -q "sys backup_telegram"; then
            tg_backup_status="${GREEN}[ON]${NC}"
        fi
        
        printf "  ${CYAN}[01]${NC} %-40s\n" "Create System Backup (Local/Encrypted)"
        printf "  ${CYAN}[02]${NC} %-40s\n" "Restore from Backup"
        printf "  ${CYAN}[03]${NC} %-40s\n" "Send Backup to Telegram Bot"
        printf "  ${CYAN}[04]${NC} %-40s %b\n" "Setup Telegram Auto-Backup" "${tg_backup_status}"
        printf "  ${CYAN}[05]${NC} %-40s %b\n" "Setup JanabiTech Cloud Backup" "${imagi_status}"
        echo -e ""
        echo -e "  ${RED}[00]${NC} Return to Main Menu"
        draw_line
        read -p " Select Option : " opt

        case $opt in
            1)
                echo -e "\n${CYAN}Creating backup archive...${NC}"
                /opt/janabitech/bin/janabitech sys backup
                pause
                ;;
            2)
                clear
                echo -e "${CYAN}=== RESTORE SYSTEM BACKUP ===${NC}"
                local backup_dir="/opt/janabitech/backups"
                
                # Ensure directory exists and is writable for SFTP uploads
                if [ ! -d "$backup_dir" ]; then
                    mkdir -p "$backup_dir"
                    chmod 777 "$backup_dir"
                fi
                
                # Check if directory is empty
                local has_local=false
                if [ -n "$(ls -A "$backup_dir" 2>/dev/null)" ]; then
                    has_local=true
                    echo -e "Available Archives:\n"
                    # Read all encrypted backup files into an array, sorted by newest first
                    mapfile -t BACKUP_LIST < <(ls -1t "$backup_dir"/*.tar.gz.enc 2>/dev/null)

                    local i=1
                    for b_file in "${BACKUP_LIST[@]}"; do
                        local b_name=$(basename "$b_file")
                        local b_size=$(du -h "$b_file" | cut -f1)
                        local b_date=$(date -r "$b_file" +"%Y-%m-%d %H:%M:%S")
                        printf "  ${GREEN}[%02d]${NC} %-35s | %-5s | %-20s\n" "$i" "$b_name" "$b_size" "$b_date"
                        ((i++))
                    done
                else
                    echo -e "\n  ${ORANGE}[!] No local backups found in $backup_dir.${NC}"
                fi

                echo -e "\n  ${ORANGE}[99]${NC} Download and Restore from Cloud Link"
                echo -e "  ${RED}[00]${NC} Cancel"

                read -p " Select Backup to Restore (S/N): " sel_idx
                if [[ "$sel_idx" == "0" || -z "$sel_idx" ]]; then continue; fi

                local target_file=""

                if [[ "$sel_idx" == "99" ]]; then
                    read -p " Enter Cloud Link: " cloud_url
                    if [ -n "$cloud_url" ]; then
                        echo -e "\n${CYAN}Downloading backup from cloud...${NC}"
                        local dl_target="$backup_dir/cloud_backup_$(date +%s).tar.gz.enc"
                        
                        local wget_cmd="wget -q --show-progress --no-check-certificate"
                        if [[ "$cloud_url" == *"backups.janabitech.online"* ]]; then
                            # Auto-inject default credentials for the private backup server
                            # We MUST use --auth-no-challenge because the custom Python backend does not send a WWW-Authenticate header
                            wget_cmd="$wget_cmd --auth-no-challenge --http-user=admin --http-password=Janabitech001"
                        fi

                        if eval "$wget_cmd -O \"$dl_target\" \"$cloud_url\""; then
                            echo -e "${GREEN}[+] Download complete!${NC}"
                            target_file="$dl_target"
                        else
                            echo -e "${RED}[-] Download failed. Check the URL.${NC}"
                            rm -f "$dl_target"
                            pause
                            continue
                        fi
                    else
                        continue
                    fi
                elif [[ "$sel_idx" =~ ^[0-9]+$ ]] && [ "$sel_idx" -le "${#BACKUP_LIST[@]}" ] && [ "$sel_idx" -gt 0 ]; then
                    target_file="${BACKUP_LIST[$((sel_idx-1))]}"
                else
                    echo -e "\n${RED}Invalid selection.${NC}"
                    pause
                    continue
                fi

                if [ -n "$target_file" ]; then
                    echo -e "\n${RED}${BOLD}WARNING: Restoring will instantly overwrite your current users,${NC}"
                    echo -e "${RED}${BOLD}domains, TLS certificates, and SlowDNS keys!${NC}"
                    read -p "Are you absolutely sure? (Type 'YES' to confirm): " confirm_res
                    
                    if [ "$confirm_res" == "YES" ]; then
                        echo -e "\n${ORANGE}[*] Restoring system state and rebooting daemons...${NC}"
                        /opt/janabitech/bin/janabitech sys restore "$target_file"
                        echo -e "${GREEN}[+] Restore complete! System state reverted successfully.${NC}"
                    else
                        echo -e "\n${GREEN}Restore aborted.${NC}"
                    fi
                fi
                pause
                ;;
            3)
                /opt/janabitech/bin/janabitech sys backup_telegram
                pause
                ;;
            4)
                echo -e "\n${CYAN}Telegram Auto-Backup Schedule${NC}"
                echo "1. Daily (Midnight)"
                echo "2. Weekly (Sunday)"
                echo "0. Disable Auto-Backup"
                read -p "Select Option: " ab_opt
                if [[ "$ab_opt" =~ ^[0-2]$ ]]; then
                    /opt/janabitech/bin/janabitech sys autobackup "$ab_opt"
                else
                    echo -e "${RED}Invalid selection.${NC}"
                fi
                pause
                ;;
            5)
                echo -e "\n${CYAN}=== SETUP JANABITECH CLOUD BACKUP ===${NC}"
                if grep -q "JANABITECH_BACKUP_URL" /opt/janabitech/core/telegram.conf 2>/dev/null; then
                    read -p "JanabiTech Cloud Backup is currently enabled. Disable it? (y/n): " dis_opt
                    if [[ "$dis_opt" =~ ^[Yy] ]]; then
                        sed -i '/JANABITECH_BACKUP_URL=/d' /opt/janabitech/core/telegram.conf 2>/dev/null
                        sed -i '/JANABITECH_NODE_KEY=/d' /opt/janabitech/core/telegram.conf 2>/dev/null
                        echo -e "\033[0;32m[+] JanabiTech Cloud Backup disabled successfully!\033[0m"
                        pause
                        continue
                    fi
                fi
                echo -e "Enable automatic backups to the JanabiTech Cloud Server (backups.janabitech.online)."
                echo -e "Your backups will be encrypted on this VPS and securely sent to the cloud."
                echo -e ""
                read -p "Press Enter to enable JanabiTech Cloud Backup..." 
                sed -i '/JANABITECH_BACKUP_URL=/d' /opt/janabitech/core/telegram.conf 2>/dev/null
                sed -i '/JANABITECH_NODE_KEY=/d' /opt/janabitech/core/telegram.conf 2>/dev/null
                echo "JANABITECH_BACKUP_URL=\"https://backups.janabitech.online\"" >> /opt/janabitech/core/telegram.conf
                echo "JANABITECH_NODE_KEY=\"janabi-tech-global-node-key\"" >> /opt/janabitech/core/telegram.conf
                echo -e "\033[0;32m[+] JanabiTech Cloud Backup enabled successfully!\033[0m"
                echo -e ""
                read -p "Would you like to run a test backup now to verify the connection and get a download URL? [Y/n]: " run_test
                if [[ "$run_test" =~ ^[Yy]$ ]] || [ -z "$run_test" ]; then
                    :
                    create_backup
                fi
                pause
                ;;
            0|00) return ;;
            *) echo -e "${RED}Invalid option${NC}"; sleep 1 ;;
        esac
    done
}

# ==========================================================
# MAIN DASHBOARD LOOP
# ==========================================================
show_dashboard() {
    while true; do
        clear
        get_system_stats
        get_db_stats

        # ── HEADER ──────────────────────────────────────────
        draw_top
        center_text "✦  JANABITECH AUTOSCRIPT PRO  ✦" "$BOLD$BRIGHT_CYAN"
        center_text "Premium VPN Infrastructure Dashboard" "$DIM"
        draw_mid

        # ── SERVER INFORMATION ──────────────────────────────
        center_text "▸ SERVER INFORMATION ◂" "$BOLD$WHITE"
        draw_thin
        row "${DIM}  IP Address    ${NC}${BRIGHT_GREEN}${SERVER_IP}${NC}  ${DIM}(${SERVER_COUNTRY})${NC}"
        row "${DIM}  ISP / Host    ${NC}${CYAN}${SERVER_ISP}${NC}"
        row "${DIM}  Domain        ${NC}${BRIGHT_GREEN}${PRIMARY_DOMAIN}${NC}"
        row "${DIM}  OS            ${NC}${CYAN}${OS_INFO}${NC}"
        row "${DIM}  Uptime        ${NC}${GREEN}${UPTIME}${NC}"
        row "${DIM}  RAM / CPU     ${NC}${GREEN}${RAM_USED}MB${NC}${DIM} / ${NC}${GREEN}${RAM_TOTAL}MB${NC}  ${DIM}│${NC}  CPU ${BRIGHT_YELLOW}${CPU_USAGE}${NC}"
        draw_mid

        # ── SERVICE HEALTH GRID ─────────────────────────────
        center_text "▸ SERVICE HEALTH ◂" "$BOLD$WHITE"
        draw_thin

        local ws_st=$(check_service janabitech-ws)
        local ha_st=$(check_service haproxy)
        local db_st=$(check_service dropbear)
        local da_st=$(check_service danted)
        local ud_st=$(check_service janabitech-udp-custom)
        local dn_st=$(check_service janabitech-dnstt)
        local xr_st=$(check_service janabitech-xray)
        local mo_st=$(check_service janabitech-monitor)
        local tg_st=$(check_service janabitech-telegram)

        pad_svc() { if [[ "$1" == *"ON"* ]]; then echo -e "$1 "; else echo -e "$1"; fi; }
        
        ws_st=$(pad_svc "$ws_st")
        ha_st=$(pad_svc "$ha_st")
        da_st=$(pad_svc "$da_st")
        ud_st=$(pad_svc "$ud_st")
        xr_st=$(pad_svc "$xr_st")
        mo_st=$(pad_svc "$mo_st")

        row "  ${DIM}WS-Proxy${NC}   ${ws_st}   ${DIM}HAProxy${NC}    ${ha_st}   ${DIM}Dropbear${NC}   ${db_st}"
        row "  ${DIM}Dante${NC}      ${da_st}   ${DIM}UDP Custom${NC} ${ud_st}   ${DIM}DNSTT${NC}      ${dn_st}"
        row "  ${DIM}Xray${NC}       ${xr_st}   ${DIM}Monitor${NC}    ${mo_st}   ${DIM}Telegram${NC}   ${tg_st}"
        draw_mid

        # ── BANDWIDTH & USERS ───────────────────────────────
        center_text "▸ USAGE & ACCOUNTS ◂" "$BOLD$WHITE"
        draw_thin
        row "${DIM}  Bandwidth Today  ${NC}${BRIGHT_GREEN}${BW_TODAY}${NC}"
        row "${DIM}  Bandwidth Month  ${NC}${BRIGHT_CYAN}${BW_MONTH}${NC}"
        empty_row
        row "  ${BRIGHT_GREEN}● Active${NC} ${GREEN}${ACTIVE_USERS}${NC}    ${BRIGHT_RED}● Expired${NC} ${RED}${EXPIRED_USERS}${NC}    ${DIM}Total${NC} ${WHITE}${TOTAL_USERS}${NC}"
        draw_mid

        # ── LICENSE ─────────────────────────────────────────
        row "${DIM}  License${NC}   ${BRIGHT_GREEN}${LIC_NAME}${NC}  ${DIM}│  Expires${NC}  ${BRIGHT_YELLOW}${LIC_EXPIRES}${NC}"
        draw_mid

        # ── NAVIGATION MENU ────────────────────────────────
        empty_row
        row "  ${BRIGHT_CYAN}[01]${NC} SSH Panel            ${BRIGHT_CYAN}[02]${NC} Xray Panel"
        row "  ${BRIGHT_CYAN}[03]${NC} Domain & SSL         ${BRIGHT_CYAN}[04]${NC} Monitoring"
        row "  ${BRIGHT_CYAN}[05]${NC} Service Manager      ${BRIGHT_CYAN}[06]${NC} Backup & Restore"
        row "  ${BRIGHT_CYAN}[07]${NC} Settings             ${BRIGHT_CYAN}[08]${NC} Update Script"
        row "  ${BRIGHT_CYAN}[09]${NC} Reboot Server"
        empty_row
        row "  ${BRIGHT_RED}[00]${NC} Exit"
        empty_row
        draw_mid
        center_text "Subscribe → @imagivpnbot  •  t.me/janabitech001" "$BRIGHT_MAGENTA"
        draw_bot
        echo ""
        read -p " Select Option : " opt

        case $opt in
            1) menu_ssh_panel ;;
            2) menu_xray ;;
            3) menu_domain_ssl ;;
            4) menu_monitoring ;;
            5) menu_services ;;
            6) menu_backup_restore ;;
            7) menu_settings ;;
            8) 
               clear
               echo -e "${CYAN}=== UPDATE JANABITECH PLATFORM ===${NC}"
               echo -e "${ORANGE}This will fetch the latest core files from GitHub.${NC}"
               echo -e "Your users, database, domains, and configurations will ${GREEN}NOT${NC} be affected.\n"
               
               read -p "Proceed with update? (y/n): " confirm_update
               if [[ "$confirm_update" =~ ^[Yy] ]]; then
                   echo ""
                   /opt/janabitech/bin/janabitech sys update
                   pause
               fi
               ;;
            9) 
               read -p "Are you sure you want to reboot the server? (y/n): " confirm
               if [[ "$confirm" =~ ^[Yy] ]]; then reboot; fi
               ;;
            0|00) clear; exit 0 ;;
            *) echo -e "${RED}Invalid option${NC}"; sleep 1 ;;
        esac
    done
}

# Boot the HUD
# show_dashboard (run by monolith)
