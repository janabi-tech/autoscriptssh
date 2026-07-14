#!/bin/bash
# File: /root/janabitech-install/05-deploy-xray.sh
# Purpose: Deploy Xray-core with vmess/vless/trojan over ws-nontls/ws-tls/grpc.
#          Shares the SAME domain + Let's Encrypt SSL certificate that the SSH
#          stack already provisions in /opt/janabitech/core/keys/.

source /opt/janabitech/core/janabitech.conf
source /opt/janabitech/lib/installer_utils.sh
source /opt/janabitech/lib/db.sh
source /opt/janabitech/lib/xray.sh

log_event "INFO" "Deploying Phase 5: Xray-core Manager (vmess/vless/trojan)"

# 1. Ensure required packages are available
ensure_package "unzip"

# 2. Ensure db schema for xray exists (idempotent)
init_database

# 3. Install xray binary, generate config, deploy systemd unit
xray_install
if [ $? -ne 0 ]; then
    log_event "ERROR" "Xray deployment failed."
    exit 1
fi

# 4. Schedule daily expired-account purger (idempotent)
CRON_LINE="*/5 * * * * /opt/janabitech/bin/janabitech xray purge-expired >/dev/null 2>&1"
if ! crontab -l 2>/dev/null | grep -qF "xray purge-expired"; then
    (crontab -l 2>/dev/null; echo "$CRON_LINE") | crontab -
    log_event "INFO" "Scheduled xray expired-account purger (every 5 minutes)."
fi

log_event "INFO" "Xray-core deployed. Manage via menu option 09 or 'janabitech xray ...'"
