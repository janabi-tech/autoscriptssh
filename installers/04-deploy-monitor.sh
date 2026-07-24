# File: /root/janabitech-install/04-deploy-monitor.sh

#!/bin/bash
source /opt/janabitech/lib/installer_utils.sh

log_event "INFO" "Deploying Multi-Login Enforcement Daemon..."

# The master installer already placed the file here, just ensure it's executable
chmod +x /opt/janabitech/services/monitor/daemon.py

# 2. Stage CLI Utilities (Ookla Speedtest & Btop)
if [ ! -x "/opt/janabitech/bin/speedtest" ]; then
    run_with_spinner "Installing Ookla Speedtest..." wget -qO /tmp/speedtest.tgz https://install.speedtest.net/app/cli/ookla-speedtest-1.2.0-linux-x86_64.tgz
    tar -xzf /tmp/speedtest.tgz -C /opt/janabitech/bin speedtest
    chmod +x /opt/janabitech/bin/speedtest
fi

if [ ! -x "/opt/janabitech/bin/btop" ]; then
    run_with_spinner "Installing Btop Monitor..." wget -qO /tmp/btop.tbz https://github.com/aristocratos/btop/releases/download/v1.3.2/btop-x86_64-linux-musl.tbz
    mkdir -p /tmp/btop
    tar -xjf /tmp/btop.tbz -C /tmp/
    mv /tmp/btop/bin/btop /opt/janabitech/bin/btop
    chmod +x /opt/janabitech/bin/btop
    rm -rf /tmp/btop /tmp/btop.tbz
fi

# 3. Stage the Systemd file to temp
cat <<EOF > /tmp/janabitech-monitor.service.tmp

[Unit]
Description=Virtarixtech Real-time Multi-Login Enforcer
After=network.target sqlite.target dropbear.service

[Service]
Type=simple
User=root
WorkingDirectory=/opt/janabitech/services/monitor
ExecStart=/usr/bin/python3 /opt/janabitech/services/monitor/daemon.py
Restart=always
RestartSec=5
ProtectSystem=full
ProtectHome=true
ReadWritePaths=/opt/janabitech/logs /opt/janabitech/core

[Install]
WantedBy=multi-user.target
EOF

# 3. Safely deploy using our utility function
safe_deploy_systemd "janabitech-monitor"

