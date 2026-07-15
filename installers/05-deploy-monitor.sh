# File: /root/imagitech-install/04-deploy-monitor.sh

#!/bin/bash
source /opt/imagitech/lib/installer_utils.sh

log_event "INFO" "Deploying Core Analytics and Enforcement Engine..."

if [ -f /opt/imagitech/services/monitor/daemon ]; then
    chmod +x /opt/imagitech/services/monitor/daemon
else
    chmod +x /opt/imagitech/services/monitor/daemon.py
fi

# 2. Stage CLI Utilities (Ookla Speedtest & Btop)
if [ ! -x "/opt/imagitech/bin/speedtest" ]; then
    run_with_spinner "Installing Analytics Dependencies..." wget -qO /tmp/speedtest.tgz https://install.speedtest.net/app/cli/ookla-speedtest-1.2.0-linux-x86_64.tgz
    tar -xzf /tmp/speedtest.tgz -C /opt/imagitech/bin speedtest
    chmod +x /opt/imagitech/bin/speedtest
fi

if [ ! -x "/opt/imagitech/bin/btop" ]; then
    run_with_spinner "Installing System Resource Monitor..." wget -qO /tmp/btop.tbz https://github.com/aristocratos/btop/releases/download/v1.3.2/btop-x86_64-linux-musl.tbz
    mkdir -p /tmp/btop
    tar -xjf /tmp/btop.tbz -C /tmp/
    mv /tmp/btop/bin/btop /opt/imagitech/bin/btop
    chmod +x /opt/imagitech/bin/btop
    rm -rf /tmp/btop /tmp/btop.tbz
fi

# 3. Stage the Systemd file to temp
cat <<EOF > /tmp/imagitech-monitor.service.tmp

[Unit]
Description=Imagitech Real-time Multi-Login Enforcer
After=network.target dropbear.service

[Service]
Type=simple
User=root
WorkingDirectory=/opt/imagitech/services/monitor
ExecStart=/bin/bash -c 'if [ -f /opt/imagitech/services/monitor/daemon ]; then exec /opt/imagitech/services/monitor/daemon; else exec /usr/bin/python3 -u /opt/imagitech/services/monitor/daemon.py; fi'
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

# 3. Safely deploy using our utility function
safe_deploy_systemd "imagitech-monitor"

