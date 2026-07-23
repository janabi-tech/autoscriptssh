#!/usr/bin/env python3
# File: /opt/janabitech/services/monitor/daemon.py
# Purpose: Real-time Multi-Login, Bandwidth Accounting, and OS Reaper

import os
import time
import sqlite3
import subprocess
import datetime
import pwd
from collections import defaultdict

# --- CONFIGURATION ---
DB_PATH = "/opt/janabitech/core/database.db"
ONLINE_FILE = "/opt/janabitech/core/online_users.txt"
CHECK_INTERVAL = 30  

class VirtarixtechMonitor:
    def __init__(self):
        self.db_path = DB_PATH
        self.user_policies = {} 
        self.active_sessions = defaultdict(list)
        self.pid_io_cache = {}
        self.setup_iptables()

    def log_event(self, level, msg):
        timestamp = datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S")
        print(f"[{timestamp}] [{level}] {msg}")

    def setup_iptables(self):
        try:
            subprocess.run("iptables -N VIRTARIXTECH-ACCT", shell=True, stderr=subprocess.DEVNULL)
            check_link = subprocess.run("iptables -C OUTPUT -j VIRTARIXTECH-ACCT", shell=True, stderr=subprocess.DEVNULL)
            if check_link.returncode != 0:
                subprocess.run("iptables -I OUTPUT -j VIRTARIXTECH-ACCT", shell=True, stderr=subprocess.DEVNULL)
        except Exception as e:
            self.log_event("ERROR", f"IPTables setup failed: {e}")

    def fetch_user_policies(self):
        try:
            conn = sqlite3.connect(self.db_path)
            cursor = conn.cursor()
            cursor.execute("SELECT username, max_logins, expiry_date, data_usage, data_limit FROM users WHERE status='ACTIVE'")
            self.user_policies = {
                row[0]: {
                    'max_logins': row[1], 
                    'expiry': row[2],
                    'data_usage': row[3] or 0,
                    'data_limit': row[4] or 0
                } 
                for row in cursor.fetchall()
            }
            conn.close()
        except Exception as e:
            self.log_event("ERROR", f"Database access failed: {e}")

    def reconcile_state(self):
        self.active_sessions.clear()
        try:
            cmd = "ps -eo user:32,pid,command | grep -E 'dropbear|sshd' | grep -v grep"
            output = subprocess.check_output(cmd, shell=True, text=True)
            
            for line in output.strip().split('\n'):
                if not line.strip(): continue
                parts = line.split()
                if len(parts) >= 3:
                    user, pid = parts[0], parts[1]
                    ignored_users = ['root', 'nobody', 'syslog', 'stunnel4', 'messagebus', 'danted', 'systemd-resolve']
                    if user in ignored_users: continue
                        
                    try:
                        if pwd.getpwnam(user).pw_shell != '/bin/false': continue
                    except KeyError:
                        pass 

                    self.active_sessions[user].append(pid)
        except subprocess.CalledProcessError:
            pass 

    def process_bandwidth(self):
        usage_updates = {}
        current_pids = set()
        
        try:
            for user, pids in self.active_sessions.items():
                for pid in pids:
                    current_pids.add(pid)
                    io_file = f"/proc/{pid}/io"
                    try:
                        with open(io_file, 'r') as f:
                            rchar = 0
                            wchar = 0
                            for line in f:
                                if line.startswith('rchar:'):
                                    rchar = int(line.split()[1])
                                elif line.startswith('wchar:'):
                                    wchar = int(line.split()[1])
                            
                            current_total = rchar + wchar
                            last_total = self.pid_io_cache.get(pid, 0)
                            
                            if current_total >= last_total:
                                delta = current_total - last_total
                            else:
                                delta = current_total
                                
                            self.pid_io_cache[pid] = current_total
                            
                            if delta > 0:
                                usage_updates[user] = usage_updates.get(user, 0) + delta
                    except (FileNotFoundError, PermissionError, ValueError):
                        pass

            # Cleanup dead pids from cache
            self.pid_io_cache = {pid: v for pid, v in self.pid_io_cache.items() if pid in current_pids}

            if usage_updates:
                conn = sqlite3.connect(self.db_path)
                cursor = conn.cursor()
                for user, data_bytes in usage_updates.items():
                    cursor.execute("UPDATE users SET data_usage = data_usage + ? WHERE username = ?", (data_bytes, user))
                conn.commit()
                conn.close()

        except Exception as e:
            self.log_event("ERROR", f"Bandwidth tracking failed: {e}")

    def enforce_expiry_and_limits(self):
        now = datetime.datetime.now()
        conn = None
        try:
            for user, policy in list(self.user_policies.items()):
                try:
                    expiry_date = datetime.datetime.strptime(policy['expiry'], "%Y-%m-%d %H:%M:%S")
                    if now >= expiry_date:
                        self.log_event("INFO", f"User '{user}' expired. Executing OS wipe.")
                        subprocess.run(["pkill", "-u", user], check=False, stderr=subprocess.DEVNULL)
                        # The Reaper: Eradicate the Linux account entirely
                        subprocess.run(["userdel", "-f", user], check=False, stderr=subprocess.DEVNULL)
                        # SOCKS5 caches credentials, so we forcefully restart Dante to drop rogue connections
                        subprocess.run(["systemctl", "restart", "danted"], check=False, stderr=subprocess.DEVNULL)
                        
                        if not conn: conn = sqlite3.connect(self.db_path)
                        conn.cursor().execute("UPDATE users SET status='EXPIRED' WHERE username=?", (user,))
                        conn.commit()
                        del self.user_policies[user]
                except Exception as e:
                    pass

                # Enforce bandwidth limit
                data_usage = policy.get('data_usage', 0)
                data_limit = policy.get('data_limit', 0)
                if data_limit > 0 and data_usage >= data_limit:
                    self.log_event("WARN", f"Bandwidth limit exceeded: {user}. Locking account.")
                    subprocess.run(["usermod", "-L", user], check=False, stderr=subprocess.DEVNULL)
                    subprocess.run(["pkill", "-u", user], check=False, stderr=subprocess.DEVNULL)
                    
                    if not conn: conn = sqlite3.connect(self.db_path)
                    conn.cursor().execute("UPDATE users SET status='LOCKED' WHERE username=?", (user,))
                    conn.commit()

            for user, pids in self.active_sessions.items():
                policy = self.user_policies.get(user)
                if not policy:
                    subprocess.run(["pkill", "-u", user], check=False, stderr=subprocess.DEVNULL)
                    continue
                max_allowed = policy['max_logins']
                if max_allowed > 0 and len(pids) > max_allowed:
                    self.log_event("WARN", f"Multi-login violation: {user}. Locking account.")
                    subprocess.run(["usermod", "-L", user], check=False, stderr=subprocess.DEVNULL)
                    subprocess.run(["pkill", "-u", user], check=False, stderr=subprocess.DEVNULL)
                    
                    if not conn: conn = sqlite3.connect(self.db_path)
                    conn.cursor().execute("UPDATE users SET status='LOCKED' WHERE username=?", (user,))
                    conn.commit()
        finally:
            if conn: conn.close()

    def purge_ghost_accounts(self):
        """Hunts down users marked as EXPIRED in the DB and ensures they are wiped from the OS."""
        try:
            conn = sqlite3.connect(self.db_path)
            cursor = conn.cursor()
            cursor.execute("SELECT username FROM users WHERE status != 'ACTIVE'")
            inactive_users = cursor.fetchall()
            conn.close()

            for (user,) in inactive_users:
                try:
                    pwd.getpwnam(user) # Throws KeyError if they are already wiped
                    self.log_event("INFO", f"Reaping ghost OS account for expired user: {user}")
                    subprocess.run(["pkill", "-u", user], check=False, stderr=subprocess.DEVNULL)
                    subprocess.run(["userdel", "-f", user], check=False, stderr=subprocess.DEVNULL)
                except KeyError:
                    pass # System is clean
        except Exception as e:
            pass

    def write_ui_report(self):
        try:
            with open(ONLINE_FILE, "w") as f:
                if not self.active_sessions:
                    f.write("No active VPN connections right now.\n")
                else:
                    for user, pids in self.active_sessions.items():
                        f.write(f"{user}|{len(pids)}\n")
        except IOError:
            pass

    def run(self):
        self.log_event("INFO", "Monitor Daemon started (Resilient Engine).")
        while True:
            try:
                self.fetch_user_policies()
                self.reconcile_state()
                self.process_bandwidth()           # 1. Catch bytes first
                self.enforce_expiry_and_limits()   # 2. Kill violators
                self.purge_ghost_accounts()        # 3. Clean up the OS
                self.write_ui_report()             # 4. Update the Bash menu
            except Exception as e:
                self.log_event("ERROR", f"Daemon cycle failed: {e}. Recovering in 15s.")
                time.sleep(15)
            time.sleep(CHECK_INTERVAL)

if __name__ == "__main__":
    monitor = JanabitechMonitor()
    monitor.run()
