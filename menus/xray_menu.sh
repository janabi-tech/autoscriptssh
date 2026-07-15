# XRAY Panel - Imagi-Tech VPN

menu_xray() {
    while true; do
        clear
        draw_line
        echo -e "                   ${BOLD}XRAY ACCOUNT PANEL${NC}                  "
        draw_line
        echo -e "  ${CYAN}[01]${NC} VLESS Reality xHTTP"
        echo -e "  ${CYAN}[02]${NC} VLESS Reality Vision"
        echo -e "  ${CYAN}[03]${NC} VLESS WS TLS"
        echo -e "  ${CYAN}[04]${NC} Trojan WS TLS"
        echo -e "  ${CYAN}[05]${NC} VMESS WS TLS"
        echo -e "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo -e "  ${CYAN}[07]${NC} User Details (Print Links)"
        echo -e "  ${CYAN}[08]${NC} Delete User"
        echo -e "  ${CYAN}[09]${NC} Renew User"
        echo -e "  ${CYAN}[10]${NC} Trial Account"
        echo -e "  ${CYAN}[11]${NC} User List"
        echo -e "  ${CYAN}[12]${NC} Online Users"
        echo -e "  ${CYAN}[13]${NC} Bandwidth Usage"
        echo -e ""
        echo -e "  ${RED}[00]${NC} Return to Main Menu"
        draw_line
        read -p " Select Option : " opt

        case $opt in
            1) execute_xray_add_user "VLESS Reality xHTTP" ;;
            2) execute_xray_add_user "VLESS Reality Vision" ;;
            3) execute_xray_add_user "VLESS WS TLS" ;;
            4) execute_xray_add_user "Trojan WS TLS" ;;
            5) execute_xray_add_user "VMESS WS TLS" ;;
            7) execute_xray_user_details "XRAY" ;;
            8) execute_del_user "XRAY" ;;
            9) execute_renew_user "XRAY" ;;
            10) execute_xray_trial_user ;;
            11) execute_list_users "XRAY" ;;
            12) execute_online_users "XRAY" ;;
            13) execute_xray_bandwidth ;;
            0|00) return ;;
            *) echo -e "${RED}Invalid option${NC}"; sleep 1 ;;
        esac
    done
}

execute_xray_user_details() {
    local list_type="${1:-XRAY}"
    clear
    echo -e "${CYAN}=== PRINT XRAY LINKS ===${NC}"
    select_user_from_list "$list_type"
    if [[ -z "$FINAL_USERNAME" ]]; then return; fi
    
    local USERNAME="$FINAL_USERNAME"
    local EXP_DATE_FORMATTED=$(date -d "$FINAL_EXPIRY" +"%B %d, %Y" 2>/dev/null || echo "$FINAL_EXPIRY")
    
    local UUID=$(sqlite3 "$DB_PATH" "SELECT uuid FROM users WHERE username='$USERNAME';")
    local REALITY_PBK=$(cat /opt/imagitech/core/keys/reality.pub 2>/dev/null || echo "")
    local REALITY_SID=$(cat /opt/imagitech/core/keys/reality.sid 2>/dev/null || echo "")
    
    IP_ADDR=$(curl -sS ipv4.icanhazip.com)
    source /opt/imagitech/core/server_geo.env 2>/dev/null
    
    local PORT="443"
    local SNI="${REALITY_SNI:-www.microsoft.com}"
    
    # Generate Links
    local LINK_XHTTP="vless://${UUID}@${IP_ADDR}:${PORT}?security=reality&encryption=none&pbk=${REALITY_PBK}&headerType=none&fp=chrome&type=xhttp&path=%2Fxhttp&sni=${SNI}&sid=${REALITY_SID}&spx=%2F#${USERNAME}-xHTTP"
    local LINK_VISION="vless://${UUID}@${IP_ADDR}:${PORT}?security=reality&encryption=none&pbk=${REALITY_PBK}&headerType=none&fp=chrome&type=tcp&flow=xtls-rprx-vision&sni=${SNI}&sid=${REALITY_SID}&spx=%2F#${USERNAME}-Vision"
    local LINK_VLESS_WS="vless://${UUID}@${PRIMARY_DOMAIN}:${PORT}?path=%2Fvless&security=tls&encryption=none&type=ws&sni=${PRIMARY_DOMAIN}#${USERNAME}-VLESS"
    local VMESS_JSON="{\"v\":\"2\",\"ps\":\"${USERNAME}\",\"add\":\"${PRIMARY_DOMAIN}\",\"port\":\"443\",\"id\":\"${UUID}\",\"aid\":\"0\",\"net\":\"ws\",\"type\":\"none\",\"host\":\"${PRIMARY_DOMAIN}\",\"path\":\"/vmess\",\"tls\":\"tls\",\"sni\":\"${PRIMARY_DOMAIN}\"}"
    local LINK_VMESS_WS="vmess://$(echo -n "${VMESS_JSON}" | base64 -w0)"
    local LINK_TROJAN_WS="trojan://${UUID}@${PRIMARY_DOMAIN}:${PORT}?path=%2Ftrojan&security=tls&type=ws&sni=${PRIMARY_DOMAIN}#${USERNAME}-Trojan"

    clear
    echo -e "${GREEN}User links fetched successfully${NC}"
    echo -e "========================================"
    echo -e "Username      : ${USERNAME}"
    echo -e "Expires On    : ${EXP_DATE_FORMATTED}"
    echo -e "UUID          : ${UUID}"
    echo -e "========================================"
    echo -e "${ORANGE}1. VLESS REALITY xHTTP${NC}"
    echo -e "${CYAN}${LINK_XHTTP}${NC}\n"
    
    echo -e "${ORANGE}2. VLESS REALITY Vision${NC}"
    echo -e "${CYAN}${LINK_VISION}${NC}\n"
    
    echo -e "${ORANGE}3. VLESS WS TLS${NC}"
    echo -e "${CYAN}${LINK_VLESS_WS}${NC}\n"
    
    echo -e "${ORANGE}4. VMESS WS TLS${NC}"
    echo -e "${CYAN}${LINK_VMESS_WS}${NC}\n"
    
    echo -e "${ORANGE}5. Trojan WS TLS${NC}"
    echo -e "${CYAN}${LINK_TROJAN_WS}${NC}"
    echo -e "========================================"
    
    pause
}

execute_xray_add_user() {
    local PROTOCOL="$1"
    while true; do
        clear
        echo -e "${CYAN}=== CREATE XRAY ACCOUNT (${PROTOCOL}) ===${NC}"
        
        read -p "Username: " USERNAME
        if [[ -z "$USERNAME" ]]; then echo -e "${RED}[ERROR] Username cannot be empty.${NC}"; sleep 1.5; continue; fi
        
        read -p "Duration (Days) [default: 30]: " DAYS
        DAYS=${DAYS:-30}

        read -p "Max Simultaneous Logins (0 = Unlimited) [Default: 2]: " MAX_LOGINS
        MAX_LOGINS=${MAX_LOGINS:-2}

        read -p "Bandwidth Limit in GB (0 = Unlimited) [Default: 0]: " BW_LIMIT
        BW_LIMIT=${BW_LIMIT:-0}

        local SNI=""
        if [[ "$PROTOCOL" == *"Reality"* ]]; then
            # Reality SNI must match the backend global configuration to function
            SNI="${REALITY_SNI:-www.microsoft.com}"
        fi

        # Auto-generate password since XRAY doesn't care much, but SSH needs one for the unified DB
        PASSWORD=$(< /dev/urandom tr -dc _A-Z-a-z-0-9 | head -c8)

        /opt/imagitech/bin/imagitech user add "$USERNAME" "$PASSWORD" "$DAYS" "$MAX_LOGINS" "$BW_LIMIT" "XRAY" > /dev/null 2>&1
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
    print_xray_receipt "$USERNAME" "$DAYS" "days" "$PROTOCOL" "$SNI"
}

execute_xray_trial_user() {
    clear
    echo -e "${CYAN}=== CREATE XRAY TRIAL ===${NC}"
    
    USERNAME="trial$((RANDOM % 9000 + 1000))"
    PASSWORD=$(< /dev/urandom tr -dc _A-Z-a-z-0-9 | head -c6)
    
    echo -e "Generated Username : ${GREEN}${USERNAME}${NC}\n"
    
    read -p "Duration in Hours [default: 2]: " HOURS
    HOURS=${HOURS:-2}

    /opt/imagitech/bin/imagitech user trial "$USERNAME" "$PASSWORD" "$HOURS" "2" "0" "XRAY" > /dev/null 2>&1
    
    echo "1. VLESS Reality xHTTP"
    echo "2. VLESS Reality Vision"
    echo "3. VLESS WS TLS"
    echo "4. VMESS WS TLS"
    read -p "Choice: " choice
    
    local PROTOCOL="VLESS Reality Vision"
    case $choice in
        1) PROTOCOL="VLESS Reality xHTTP" ;;
        2) PROTOCOL="VLESS Reality Vision" ;;
        3) PROTOCOL="VLESS WS TLS" ;;
        4) PROTOCOL="VMESS WS TLS" ;;
    esac

    local SNI=""
    if [[ "$PROTOCOL" == *"Reality"* ]]; then
        SNI="${REALITY_SNI:-www.microsoft.com}" # Default for trial to save time
    fi
    print_xray_receipt "$USERNAME" "$HOURS" "hours" "$PROTOCOL" "$SNI"
}

print_xray_receipt() {
    local USERNAME="$1"
    local TIME_VAL="$2"
    local TIME_TYPE="$3"
    local PROTOCOL="$4"
    
    local UUID=$(sqlite3 "$DB_PATH" "SELECT uuid FROM users WHERE username='$USERNAME';")
    local REALITY_PBK=$(cat /opt/imagitech/core/keys/reality.pub 2>/dev/null || echo "")
    local REALITY_SID=$(cat /opt/imagitech/core/keys/reality.sid 2>/dev/null || echo "")
    
    IP_ADDR=$(curl -sS ipv4.icanhazip.com)
    source /opt/imagitech/core/server_geo.env 2>/dev/null
    
    if [ "$TIME_TYPE" == "hours" ]; then
        EXP_DATE_FORMATTED=$(date -d "+${TIME_VAL} hours" +"%B %d, %Y - %H:%M")
    else
        EXP_DATE_FORMATTED=$(date -d "+${TIME_VAL} days" +"%B %d, %Y")
    fi

    # Protocol specifics
    local LINK=""
    local SNI="${5:-${REALITY_SNI:-www.microsoft.com}}"
    local PATH_URI=""
    local PORT="443"
    
    if [[ "$PROTOCOL" == "VLESS Reality xHTTP" ]]; then
        PATH_URI="/xhttp"
        LINK="vless://${UUID}@${IP_ADDR}:${PORT}?security=reality&encryption=none&pbk=${REALITY_PBK}&headerType=none&fp=chrome&type=xhttp&path=%2F${PATH_URI:1}&sni=${SNI}&sid=${REALITY_SID}&spx=%2F#${USERNAME}-xHTTP"
    elif [[ "$PROTOCOL" == "VLESS Reality Vision" ]]; then
        LINK="vless://${UUID}@${IP_ADDR}:${PORT}?security=reality&encryption=none&pbk=${REALITY_PBK}&headerType=none&fp=chrome&type=tcp&flow=xtls-rprx-vision&sni=${SNI}&sid=${REALITY_SID}&spx=%2F#${USERNAME}-Vision"
    elif [[ "$PROTOCOL" == "VLESS WS TLS" ]]; then
        PATH_URI="/vless"
        LINK="vless://${UUID}@${PRIMARY_DOMAIN}:${PORT}?path=%2Fvless&security=tls&encryption=none&type=ws&sni=${PRIMARY_DOMAIN}#${USERNAME}-WS"
    elif [[ "$PROTOCOL" == "VMESS WS TLS" ]]; then
        PATH_URI="/vmess"
        local VMESS_JSON="{\"v\":\"2\",\"ps\":\"${USERNAME}\",\"add\":\"${PRIMARY_DOMAIN}\",\"port\":\"443\",\"id\":\"${UUID}\",\"aid\":\"0\",\"net\":\"ws\",\"type\":\"none\",\"host\":\"${PRIMARY_DOMAIN}\",\"path\":\"/vmess\",\"tls\":\"tls\",\"sni\":\"${PRIMARY_DOMAIN}\"}"
        LINK="vmess://$(echo -n "${VMESS_JSON}" | base64 -w0)"
    elif [[ "$PROTOCOL" == "Trojan WS TLS" ]]; then
        PATH_URI="/trojan"
        LINK="trojan://${UUID}@${PRIMARY_DOMAIN}:${PORT}?path=%2Ftrojan&security=tls&type=ws&sni=${PRIMARY_DOMAIN}#${USERNAME}-Trojan"
    fi

    local DB_STATS=$(sqlite3 "$DB_PATH" "SELECT max_logins, data_limit FROM users WHERE username='$USERNAME';" 2>/dev/null)
    local MAX_LOGINS=$(echo "$DB_STATS" | cut -d'|' -f1)
    local BW_LIMIT_BYTES=$(echo "$DB_STATS" | cut -d'|' -f2)
    
    local BW_LIMIT="Unlimited"
    if [[ -n "$BW_LIMIT_BYTES" && "$BW_LIMIT_BYTES" -gt 0 ]]; then
        BW_LIMIT="$((BW_LIMIT_BYTES / 1073741824)) GB"
    fi
    
    local LOGIN_DISP="Unlimited"
    if [[ -n "$MAX_LOGINS" && "$MAX_LOGINS" -gt 0 ]]; then
        LOGIN_DISP="$MAX_LOGINS Devices"
    fi

    clear
    echo -e "${GREEN}${PROTOCOL} Successfully Installed!${NC}"
    echo -e "━━━━━━━━━━━━━━━━━━━━━━━━"
    if [[ "$PROTOCOL" == *"Reality"* ]]; then
        echo -e "Address     : ${IP_ADDR}"
    else
        echo -e "Address     : ${PRIMARY_DOMAIN}"
    fi
    echo -e "Port (TLS)  : ${PORT}"
    if [[ "$PROTOCOL" != *"Reality"* ]]; then
        echo -e "Port (NTLS) : 80, 8080"
    fi
    echo -e "UUID / Pass : ${UUID}"
    
    if [[ "$PROTOCOL" == *"Reality"* ]]; then
        echo -e "Security    : reality"
        echo -e "SNI Domain  : ${SNI}"
        echo -e "Public Key  : ${REALITY_PBK}"
        echo -e "Short ID    : ${REALITY_SID}"
    else
        echo -e "Security    : tls / none"
        echo -e "SNI Domain  : ${PRIMARY_DOMAIN}"
    fi
    
    if [[ -n "$PATH_URI" ]]; then
        echo -e "Path        : ${PATH_URI}"
    fi
    
    echo -e "Limit       : ${LOGIN_DISP}"
    echo -e "Data        : ${BW_LIMIT}"
    echo -e "Expiration  : ${EXP_DATE_FORMATTED}"
    echo -e "━━━━━━━━━━━━━━━━━━━━━━━━"
    echo -e "${CYAN}${LINK}${NC}"
    echo -e "━━━━━━━━━━━━━━━━━━━━━━━━"
    
    pause
}

execute_xray_user_details_from_list() {
    local FINAL_USERNAME="$1"
    local FINAL_EXPIRY="$2"
    
    local USERNAME="$FINAL_USERNAME"
    local EXP_DATE_FORMATTED=$(date -d "$FINAL_EXPIRY" +"%B %d, %Y" 2>/dev/null || echo "$FINAL_EXPIRY")
    
    local UUID=$(sqlite3 "$DB_PATH" "SELECT uuid FROM users WHERE username='$USERNAME';")
    local REALITY_PBK=$(cat /opt/imagitech/core/keys/reality.pub 2>/dev/null || echo "")
    local REALITY_SID=$(cat /opt/imagitech/core/keys/reality.sid 2>/dev/null || echo "")
    
    IP_ADDR=$(curl -sS ipv4.icanhazip.com)
    
    echo -e "\n${CYAN}Which protocol link would you like to generate?${NC}"
    echo "1. VLESS Reality xHTTP"
    echo "2. VLESS Reality Vision"
    echo "3. VLESS WS TLS"
    echo "4. Trojan WS TLS"
    echo "5. VMESS WS TLS"
    read -p "Select Protocol [1-5]: " proto_sel
    
    local PROTOCOL=""
    case $proto_sel in
        1) PROTOCOL="VLESS Reality xHTTP" ;;
        2) PROTOCOL="VLESS Reality Vision" ;;
        3) PROTOCOL="VLESS WS TLS" ;;
        4) PROTOCOL="Trojan WS TLS" ;;
        5) PROTOCOL="VMESS WS TLS" ;;
        *) echo -e "${RED}Invalid selection.${NC}"; return ;;
    esac

    local LINK=""
    local SNI="${REALITY_SNI:-www.microsoft.com}"
    local PATH_URI=""
    local PORT="443"
    
    if [[ "$PROTOCOL" == "VLESS Reality xHTTP" ]]; then
        PATH_URI="/xhttp"
        LINK="vless://${UUID}@${IP_ADDR}:${PORT}?security=reality&encryption=none&pbk=${REALITY_PBK}&headerType=none&fp=chrome&type=xhttp&path=%2F${PATH_URI:1}&sni=${SNI}&sid=${REALITY_SID}&spx=%2F#${USERNAME}-xHTTP"
    elif [[ "$PROTOCOL" == "VLESS Reality Vision" ]]; then
        LINK="vless://${UUID}@${IP_ADDR}:${PORT}?security=reality&encryption=none&pbk=${REALITY_PBK}&headerType=none&fp=chrome&type=tcp&flow=xtls-rprx-vision&sni=${SNI}&sid=${REALITY_SID}&spx=%2F#${USERNAME}-Vision"
    elif [[ "$PROTOCOL" == "VLESS WS TLS" ]]; then
        PATH_URI="/vless"
        LINK="vless://${UUID}@${PRIMARY_DOMAIN}:${PORT}?path=%2Fvless&security=tls&encryption=none&type=ws&sni=${PRIMARY_DOMAIN}#${USERNAME}-WS"
    elif [[ "$PROTOCOL" == "VMESS WS TLS" ]]; then
        PATH_URI="/vmess"
        local VMESS_JSON="{\"v\":\"2\",\"ps\":\"${USERNAME}\",\"add\":\"${PRIMARY_DOMAIN}\",\"port\":\"443\",\"id\":\"${UUID}\",\"aid\":\"0\",\"net\":\"ws\",\"type\":\"none\",\"host\":\"${PRIMARY_DOMAIN}\",\"path\":\"/vmess\",\"tls\":\"tls\",\"sni\":\"${PRIMARY_DOMAIN}\"}"
        LINK="vmess://$(echo -n "${VMESS_JSON}" | base64 -w0)"
    elif [[ "$PROTOCOL" == "Trojan WS TLS" ]]; then
        PATH_URI="/trojan"
        LINK="trojan://${UUID}@${PRIMARY_DOMAIN}:${PORT}?path=%2Ftrojan&security=tls&type=ws&sni=${PRIMARY_DOMAIN}#${USERNAME}-Trojan"
    fi

    clear
    echo -e "${GREEN}${PROTOCOL} Details:${NC}"
    echo -e "━━━━━━━━━━━━━━━━━━━━━━━━"
    if [[ "$PROTOCOL" == *"Reality"* ]]; then
        echo -e "Address     : ${IP_ADDR}"
    else
        echo -e "Address     : ${PRIMARY_DOMAIN}"
    fi
    echo -e "Port        : ${PORT}"
    echo -e "UUID / Pass : ${UUID}"
    
    if [[ "$PROTOCOL" == *"Reality"* ]]; then
        echo -e "Security    : reality"
        echo -e "SNI Domain  : ${SNI}"
        echo -e "Public Key  : ${REALITY_PBK}"
        echo -e "Short ID    : ${REALITY_SID}"
    else
        echo -e "Security    : tls"
        echo -e "SNI Domain  : ${PRIMARY_DOMAIN}"
    fi
    
    if [[ -n "$PATH_URI" ]]; then
        echo -e "Path        : ${PATH_URI}"
    fi
    
    echo -e "Expiration  : ${EXP_DATE_FORMATTED}"
    echo -e "━━━━━━━━━━━━━━━━━━━━━━━━"
    echo -e "${CYAN}${LINK}${NC}"
    echo -e "━━━━━━━━━━━━━━━━━━━━━━━━"
    
    pause
}

execute_xray_bandwidth() {
    clear
    echo -e "${CYAN}=== XRAY BANDWIDTH USAGE ===${NC}"
    draw_line
    printf "${BOLD}%-5s | %-15s | %-15s${NC}\n" "S/N" "USERNAME" "DATA USED"
    draw_line
    
    local i=1
    sqlite3 -separator '|' "$DB_PATH" "SELECT username, data_usage FROM users WHERE account_type='XRAY' ORDER BY data_usage DESC;" | while read -r line; do
        local uname=$(echo "$line" | cut -d'|' -f1)
        local bytes=$(echo "$line" | cut -d'|' -f2)
        local formatted=$(format_bytes "$bytes")
        printf "${GREEN}%-5s${NC} | ${CYAN}%-15s${NC} | ${ORANGE}%-15s${NC}\n" "$i" "$uname" "$formatted"
        ((i++))
    done
    draw_line
    pause
}
