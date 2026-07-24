# File: /root/virtarixtech-install/04-deploy-monitor.sh

#!/bin/bash
source /opt/virtarixtech/lib/installer_utils.sh

log_event "INFO" "Deploying Multi-Login Enforcement Daemon..."

# The master installer already placed the file here, just ensure it's executable
chmod +x /opt/virtarixtech/services/monitor/daemon.py

# 2. Stage CLI Utilities (Ookla Speedtest & Btop)
if [ ! -x "/opt/virtarixtech/bin/speedtest" ]; then
    run_with_spinner "Installing Ookla Speedtest..." wget -qO /tmp/speedtest.tgz https://install.speedtest.net/app/cli/ookla-speedtest-1.2.0-linux-x86_64.tgz
    tar -xzf /tmp/speedtest.tgz -C /opt/virtarixtech/bin speedtest
    chmod +x /opt/virtarixtech/bin/speedtest
fi

if [ ! -x "/opt/virtarixtech/bin/btop" ]; then
    run_with_spinner "Installing Btop Monitor..." wget -qO /tmp/btop.tbz https://github.com/aristocratos/btop/releases/download/v1.3.2/btop-x86_64-linux-musl.tbz
    mkdir -p /tmp/btop
    tar -xjf /tmp/btop.tbz -C /tmp/
    mv /tmp/btop/bin/btop /opt/virtarixtech/bin/btop
    chmod +x /opt/virtarixtech/bin/btop
    rm -rf /tmp/btop /tmp/btop.tbz
fi

# 3. Stage the Systemd file to temp
cat <<EOF > /tmp/virtarixtech-monitor.service.tmp

[Unit]
Description=Virtarixtech Real-time Multi-Login Enforcer
After=network.target sqlite.target dropbear.service

[Service]
Type=simple
User=root
WorkingDirectory=/opt/virtarixtech/services/monitor
ExecStart=/usr/bin/python3 /opt/virtarixtech/services/monitor/daemon.py
Restart=always
RestartSec=5
ProtectSystem=full
ProtectHome=true
ReadWritePaths=/opt/virtarixtech/logs /opt/virtarixtech/core

[Install]
WantedBy=multi-user.target
EOF

# 3. Safely deploy using our utility function
safe_deploy_systemd "virtarixtech-monitor"

