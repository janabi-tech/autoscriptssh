# === Decompiled from daemon.pyc ===
# Source: PyInstaller binary, Python 3.11 bytecode
# Decompiled with pycdc (Decompyle++)
# NOTE: Some constructs may be imperfect due to bytecode decompiler limitations.
# ============================================================================

# Source Generated with Decompyle++
# File: daemon.pyc (Python 3.11)

import os
import time
import sqlite3
import subprocess
import datetime
import pwd
import json
import urllib.request as urllib
import urllib.parse as urllib
import urllib.error as urllib
from collections import defaultdict
DB_PATH = '/opt/imagitech/core/database.db'
ONLINE_FILE = '/opt/imagitech/core/online_users.txt'
CHECK_INTERVAL = 30
LICENSE_CHECK_INTERVAL = 1800
LICENSE_API_URL = 'https://vpn.imagitech.online/api/v1/ip/verify'
LICENSE_STATUS_FILE = '/opt/imagitech/core/license_status'
HEARTBEAT_API_URL = 'https://vpn.imagitech.online/api/v1/ip/heartbeat'
CRON_HEARTBEAT_PATH = '/etc/cron.hourly/imagitech-heartbeat'
MAX_LICENSE_FAILURES = 3
VPN_SERVICES = [
    'xray',
    'haproxy',
    'nginx',
    'dropbear',
    'stunnel4',
    'imagitech-ws',
    'imagitech-dnstt',
    'imagitech-udp-custom']

class ImagitechMonitor:
    
    def __init__(self):
        self.db_path = DB_PATH
        self.user_policies = { }
        self.active_sessions = defaultdict(list)
        self.pid_io_cache = { }
        self.xray_io_cache = { }
        self._alerted_ghosts = set()
        self._license_valid = True
        self._license_fail_count = 0
        self._last_license_check = 0
        self._server_ip = None
        self.uuid_to_user = { }
        self.setup_iptables()

    
    def log_event(self, level, msg):
        timestamp = datetime.datetime.now().strftime('%Y-%m-%d %H:%M:%S')
        print(f'''[{timestamp}] [{level}] {msg}''')

    
    def send_telegram_alert(self, msg):
        
        try:
            if not os.path.exists('/opt/imagitech/core/telegram.conf'):
                return None
            result = None.run([
                'systemctl',
                'is-active',
                '--quiet',
                'imagitech-telegram'], check = False)
            if result.returncode != 0:
                return None
            (token, admin_id) = None
            f = open('/opt/imagitech/core/telegram.conf', 'r')
            for line in f:
                if line.startswith('BOT_TOKEN='):
                    token = line.split('=', 1)[1].strip().strip('"\'')
                if line.startswith('ADMIN_ID='):
                    admin_id = line.split('=', 1)[1].strip().strip('"\'')
                
                try:
                    None(None, None)
                with None:
                    if not None:
                        
                        try:
                            
                            try:
                                if token or admin_id:
                                    url = f'''https://api.telegram.org/bot{token}/sendMessage'''
                                    data = json.dumps({
                                        'chat_id': admin_id,
                                        'text': msg,
                                        'parse_mode': 'HTML' }).encode('utf-8')
                                    req = urllib.request.Request(url, data = data, headers = {
                                        'Content-Type': 'application/json' })
                                    response = urllib.request.urlopen(req, timeout = 5)
                                    
                                    try:
                                        None(None, None)
                                        return None
                                        with None:
                                            if not None:
                                                
                                                try:
                                                    
                                                    try:
                                                        return None
                                                        return None
                                                        return None
                                                    except Exception:
                                                        e = None
                                                        self.log_event('ERROR', f'''Failed to send Telegram alert: {e}''')
                                                        e = None
                                                        del e
                                                        return None
                                                        e = None
                                                        del e








    
    def setup_iptables(self):
        
        try:
            subprocess.run('iptables -N IMAGITECH-ACCT', shell = True, stderr = subprocess.DEVNULL)
            check_link = subprocess.run('iptables -C OUTPUT -j IMAGITECH-ACCT', shell = True, stderr = subprocess.DEVNULL)
            if check_link.returncode != 0:
                subprocess.run('iptables -I OUTPUT -j IMAGITECH-ACCT', shell = True, stderr = subprocess.DEVNULL)
                return None
            return None
        except Exception:
            e = None
            self.log_event('ERROR', f'''IPTables setup failed: {e}''')
            e = None
            del e
            return None
            e = None
            del e


    
    def fetch_user_policies(self):
        
        try:
            conn = sqlite3.connect(self.db_path)
            cursor = conn.cursor()
            
            try:
                cursor.execute("SELECT username, max_logins, expiry_date, data_usage, data_limit, uuid, is_trial FROM users WHERE status='ACTIVE'")
                has_trial_col = True
                
                try:
                    pass
                except sqlite3.OperationalError:
                    cursor.execute("SELECT username, max_logins, expiry_date, data_usage, data_limit, uuid FROM users WHERE status='ACTIVE'")
                    has_trial_col = False
                    
                    try:
                        pass
                    try:
                        self.user_policies = { }
                        self.uuid_to_user = { }
                        for row in cursor.fetchall():
                            if has_trial_col:
                                (username, max_logins, expiry, usage, limit, uuid, is_trial) = row
                            else:
                                (username, max_logins, expiry, usage, limit, uuid) = row
                                is_trial = 0
                            if not usage and limit and is_trial:
                                self.user_policies[username] = {
                                    'max_logins': max_logins,
                                    'expiry': expiry,
                                    'data_usage': 0,
                                    'data_limit': 0,
                                    'uuid': uuid,
                                    'is_trial': 0 }
                                if uuid:
                                    self.uuid_to_user[uuid] = username
                            conn.close()
                            return None
                            except Exception:
                                e = None
                                self.log_event('ERROR', f'''Database access failed: {e}''')
                                e = None
                                del e
                                return None
                                e = None
                                del e





    
    def reconcile_state(self):
        self.active_sessions.clear()
        
        try:
            cmd = "ps -eo user:32,pid,command | grep -E 'dropbear|sshd' | grep -v grep"
            output = subprocess.check_output(cmd, shell = True, text = True)
            for line in output.strip().split('\n'):
                if not line.strip():
                    continue
                parts = line.split()
                if len(parts) >= 3:
                    pid = parts[1]
                    user = parts[0]
                    ignored_users = [
                        'root',
                        'nobody',
                        'syslog',
                        'stunnel4',
                        'messagebus',
                        'danted',
                        'systemd-resolve']
                    if user in ignored_users:
                        continue
                    if pwd.getpwnam(user).pw_shell != '/bin/false':
                        
                        try:
                            continue
                        except KeyError:
                            
                            try:
                                pass
                            try:
                                self.active_sessions[user].append(pid)
                                continue
                                return None
                            except subprocess.CalledProcessError:
                                return None




    
    def process_bandwidth(self):
        pass
    # WARNING: Decompyle incomplete

    
    def process_xray_bandwidth(self):
