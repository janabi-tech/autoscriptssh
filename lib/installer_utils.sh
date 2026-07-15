# File: /opt/janabitech/lib/installer_utils.sh
# Purpose: Idempotent helper functions for safe deployment.

# Ensure we have our logging function
:

run_with_spinner() {
    local message="$1"
    shift
    local delay=0.1
    local spinstr='⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏'
    
    # Start the command in the background
    "$@" >/dev/null 2>&1 &
    local pid=$!
    
    # Hide cursor
    tput civis 2>/dev/null || true
    
    while ps -p $pid > /dev/null; do
        local temp=${spinstr#?}
        printf "\r\033[K  \033[0;36m%s\033[0m [\033[0;32m%c\033[0m]" "$message" "$spinstr"
        local spinstr=$temp${spinstr%"$temp"}
        sleep $delay
    done
    
    # Show cursor
    tput cnorm 2>/dev/null || true
    
    wait $pid
    local exit_status=$?
    
    if [ $exit_status -eq 0 ]; then
        printf "\r\033[K  \033[0;36m%s\033[0m [\033[0;32m✓\033[0m]\n" "$message"
    else
        printf "\r\033[K  \033[0;36m%s\033[0m [\033[0;31m✗\033[0m]\n" "$message"
    fi
    return $exit_status
}

ensure_package() {
    local pkg="$1"
    if ! dpkg -s "$pkg" >/dev/null 2>&1; then
        run_with_spinner "Installing system dependencies..." env DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends "$pkg"
    fi
}

safe_create_dir() {
    local dir="$1"
    if [ ! -d "$dir" ]; then
        mkdir -p "$dir"
    fi
}

safe_deploy_systemd() {
    local service_name="$1"
    local service_file="/etc/systemd/system/${service_name}.service"
    local temp_file="/tmp/${service_name}.service.tmp"
    
    # The calling script will write the unit file to the temp location first
    if [ ! -f "$temp_file" ]; then
        log_event "ERROR" "Cannot deploy core service. Temp file missing."
        return 1
    fi

    # Check if the service file already exists and is identical
    if [ -f "$service_file" ] && cmp -s "$temp_file" "$service_file"; then
        log_event "INFO" "Service is unchanged. Skipping deployment."
        rm -f "$temp_file"
    else
        log_event "INFO" "Deploying/Updating core service..."
        mv "$temp_file" "$service_file"
        systemctl daemon-reload
        systemctl enable "$service_name" >/dev/null 2>&1
        systemctl restart "$service_name"
    fi
}

ensure_tls_cert() {
    local domain="$1"
    local cert_path="/opt/janabitech/core/keys/stunnel.pem"
    local priv_key="/opt/janabitech/core/keys/private.key"
    local full_chain="/opt/janabitech/core/keys/fullchain.cer"
    
    # Check if a valid cert already exists (crude check for Let's Encrypt issuer to avoid rate limits)
    if [ -s "$cert_path" ] && grep -q "Let's Encrypt" <(openssl x509 -in "$cert_path" -text -noout 2>/dev/null); then
        log_event "INFO" "Valid Let's Encrypt TLS Certificate already exists. Skipping ACME generation."
        return 0
    fi
    
    log_event "INFO" "Initiating ACME Let's Encrypt sequence for domain: $domain..."
    
    # Ensure acme.sh is installed
    if [ ! -f "/root/.acme.sh/acme.sh" ]; then
        run_with_spinner "Configuring TLS providers..." bash -c "curl -s https://get.acme.sh | sh -s email=admin@${domain}"
    fi
    
    # Force renew/issue via standalone mode (requires port 80 to be free)
    /root/.acme.sh/acme.sh --set-default-ca --server letsencrypt >/dev/null 2>&1
    
    log_event "INFO" "Attempting cryptographic challenge..."
    ensure_package "socat"
    
    # Free port 80 completely before challenge
    systemctl stop janabitech-ws nginx 2>/dev/null || true
    
    # Suppress output, run in standalone mode
    if /root/.acme.sh/acme.sh --issue -d "$domain" --standalone --force \
        --pre-hook "systemctl stop haproxy nginx janabitech-ws 2>/dev/null || true" \
        --post-hook "systemctl start haproxy nginx janabitech-ws 2>/dev/null || true" >/dev/null 2>&1; then
        log_event "INFO" "ACME Challenge Successful! Installing certificate..."
        
        # Install the certificate into our core directory and configure automatic reload
        /root/.acme.sh/acme.sh --install-cert -d "$domain" \
            --key-file "$priv_key" \
            --fullchain-file "$full_chain" \
            --reloadcmd "cat $full_chain $priv_key > $cert_path && cp $cert_path /opt/janabitech/core/keys/haproxy.pem && systemctl restart haproxy stunnel4 janabitech-ws 2>/dev/null || true" >/dev/null 2>&1
            
        # Initial concatenation for the first run
        cat "$full_chain" "$priv_key" > "$cert_path"
        chmod 600 "$cert_path"
        cp "$cert_path" /opt/janabitech/core/keys/haproxy.pem
        chmod 600 /opt/janabitech/core/keys/haproxy.pem
        
        systemctl start janabitech-ws 2>/dev/null || true
        
        log_event "INFO" "Let's Encrypt SSL applied successfully."
        return 0
    else
        log_event "WARN" "ACME Challenge Failed. This usually means your domain is not pointing to this VPS IP yet."
        log_event "WARN" "Falling back to self-signed TLS generation so services can boot..."
        
        run_with_spinner "Generating Self-Signed TLS Certificate ($domain)..." openssl req -x509 -nodes -days 3650 -newkey rsa:2048 \
            -keyout "$priv_key" \
            -out "$full_chain" \
            -subj "/C=US/ST=NY/L=NY/O=Janabitech/CN=$domain"
            
        cat "$full_chain" "$priv_key" > "$cert_path"
        chmod 600 "$cert_path"
        cp "$cert_path" /opt/janabitech/core/keys/haproxy.pem
        chmod 600 /opt/janabitech/core/keys/haproxy.pem
        
        systemctl start janabitech-ws 2>/dev/null || true
        
        log_event "INFO" "Self-signed TLS fallback generated successfully."
    fi
}
