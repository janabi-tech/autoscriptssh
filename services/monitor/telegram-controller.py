# === Decompiled from telegram-controller.pyc ===
# Source: PyInstaller binary, Python 3.11 bytecode
# Decompiled with pycdc (Decompyle++)
# NOTE: Some constructs may be imperfect due to bytecode decompiler limitations.
# ============================================================================

# Source Generated with Decompyle++
# File: telegram-controller.pyc (Python 3.11)

'''
IMAGITECH TELEGRAM CONTROLLER v3.0
Professional VPS management panel via Telegram.
Features Inline Keyboards and Dynamic Message Editing.
'''
import json
import urllib.request as urllib
import urllib.error as urllib
import urllib.parse as urllib
import time
import subprocess
import os
import sqlite3
import base64
import random
import string
import re
import shlex
CONF_FILE = '/opt/imagitech/core/telegram.conf'
IMAGITECH_CONF = '/opt/imagitech/core/imagitech.conf'
DB_FILE = '/opt/imagitech/core/database.db'
REALITY_PUB_FILE = '/opt/imagitech/core/keys/reality.pub'
REALITY_SID_FILE = '/opt/imagitech/core/keys/reality.sid'
DNSTT_PUB_FILE = '/opt/imagitech/core/keys/dnstt.pub'
GEO_FILE = '/opt/imagitech/core/server_geo.env'
ONLINE_FILE = '/opt/imagitech/core/online_users.txt'

def load_config():
    if not os.path.exists(CONF_FILE):
        return (None, None)
    (token, admin) = None
    f = open(CONF_FILE, 'r')
    for line in f:
        line = line.strip()
        if line.startswith('BOT_TOKEN='):
            token = line.split('=', 1)[1].strip('"\'')
            continue
        if line.startswith('ADMIN_ID='):
            admin = line.split('=', 1)[1].strip('"\'')
        None(None, None)
    with None:
        if not None:
            pass
    return (token, admin)


def load_server_config():
    conf = { }
    if os.path.exists(IMAGITECH_CONF):
        f = open(IMAGITECH_CONF, 'r')
        for line in f:
            line = line.strip()
            if not '=' in line and line.startswith('#'):
                (k, v) = line.split('=', 1)
                conf[k.strip()] = v.strip('"\'')
            None(None, None)
        with None:
            if not None:
                pass
    return conf


def read_file(path, default = ('',)):
    
    try:
        f = open(path, 'r')
        
        try:
            None(None, None)
            return 
            with None:
                if not None, f.read().strip():
                    
                    try:
                        
                        try:
                            return None
                        except Exception:
                            return 






def load_geo():
    geo = { }
    if os.path.exists(GEO_FILE):
        f = open(GEO_FILE, 'r')
        for line in f:
            line = line.strip()
            if '=' in line:
                (k, v) = line.split('=', 1)
                geo[k.strip()] = v.strip('"\'')
            None(None, None)
        with None:
            if not None:
                pass
    return geo


def get_ip():
    
    try:
        result = subprocess.run('curl -s4 ifconfig.me', shell = True, capture_output = True, text = True, timeout = 8)
        return result.stdout.strip()
    except Exception:
        return 'Unknown'



def api_request(token, method, data = (None,)):
    url = f'''https://api.telegram.org/bot{token}/{method}'''
    
    try:
        if data:
            req = urllib.request.Request(url, data = json.dumps(data).encode('utf-8'), headers = {
                'Content-Type': 'application/json' })
        else:
            req = urllib.request.Request(url)
        resp = urllib.request.urlopen(req, timeout = 15)
        
        try:
            None(None, None)
            return 
            with None:
                if not None, json.loads(resp.read().decode()):
                    
                    try:
                        
                        try:
                            return None
                        except Exception:
                            print(f'''API Error ({method}): {e}''')
                            None = None
                            del e
                            return None
                            e = None
                            del e






def run_cmd(cmd, timeout = (15,)):
    
    try:
        r = subprocess.run(cmd, shell = True, capture_output = True, text = True, timeout = timeout)
        return r.stdout.strip() if r.stdout.strip() else r.stderr.strip()
    except subprocess.TimeoutExpired:
        return '⏱ Command timed out.'
        except Exception:
            e = None
            del e
            return None
            None = 
            del e



def send_message(token, chat_id, text, reply_markup = (None,)):
    payload = {
        'chat_id': chat_id,
        'text': text,
        'parse_mode': 'HTML',
        'disable_web_page_preview': True }
    if reply_markup:
        payload['reply_markup'] = reply_markup
    api_request(token, 'sendMessage', payload)


def edit_message(token, chat_id, message_id, text, reply_markup = (None,)):
    payload = {
        'chat_id': chat_id,
        'message_id': message_id,
        'text': text,
        'parse_mode': 'HTML',
        'disable_web_page_preview': True }
    if reply_markup:
        payload['reply_markup'] = reply_markup
    api_request(token, 'editMessageText', payload)


def delete_message(token, chat_id, message_id):
    api_request(token, 'deleteMessage', {
        'chat_id': chat_id,
        'message_id': message_id })


def rand_password(length = (8,)):
    pass
# WARNING: Decompyle incomplete


def db_query(query, params, fetch = ((), True)):
    
    try:
        conn = sqlite3.connect(DB_FILE)
        c = conn.cursor()
        c.execute(query, params)
        if fetch:
            rows = c.fetchall()
            conn.close()
            return rows
        None.commit()
        conn.close()
        return True
    except Exception:
        e = None
        del e
        return None
        None = 
        del e



def generate_single_link(username, uuid, protocol):
    '''Generate a single XRAY link with full receipt details for a specific protocol.'''
    server_conf = load_server_config()
    ip = get_ip()
    domain = server_conf.get('PRIMARY_DOMAIN', 'example.com')
    reality_pbk = read_file(REALITY_PUB_FILE)
    reality_sid = read_file(REALITY_SID_FILE)
    sni = server_conf.get('REALITY_SNI', 'www.microsoft.com')
    port = '443'
    link = ''
    address = domain
    port_tls = port
    port_ntls = '80, 8080'
    security = 'tls / none'
    sni_disp = domain
    path = ''
    extras = { }
    if protocol == 'VLESS Reality xHTTP':
        address = ip
        security = 'reality'
        sni_disp = sni
        path = '/xhttp'
        extras = {
            'Public Key': reality_pbk,
            'Short ID': reality_sid }
        port_ntls = None
        link = f'''vless://{uuid}@{ip}:{port}?security=reality&encryption=none&pbk={reality_pbk}&headerType=none&fp=chrome&type=xhttp&path=%2Fxhttp&sni={sni}&sid={reality_sid}#{username}-xHTTP'''
    elif protocol == 'VLESS Reality Vision':
        address = ip
        security = 'reality'
        sni_disp = sni
        extras = {
            'Public Key': reality_pbk,
            'Short ID': reality_sid }
        port_ntls = None
        link = f'''vless://{uuid}@{ip}:{port}?security=reality&encryption=none&pbk={reality_pbk}&headerType=none&fp=chrome&type=tcp&flow=xtls-rprx-vision&sni={sni}&sid={reality_sid}#{username}-Vision'''
    elif protocol == 'VLESS WS TLS':
        path = '/vless'
        link = f'''vless://{uuid}@{domain}:{port}?path=%2Fvless&security=tls&encryption=none&type=ws&sni={domain}#{username}-VLESS'''
    elif protocol == 'VMess WS TLS':
        path = '/vmess'
        vmess_json = json.dumps({
            'v': '2',
            'ps': username,
            'add': domain,
            'port': port,
            'id': uuid,
            'aid': '0',
            'net': 'ws',
            'type': 'none',
            'host': domain,
            'path': '/vmess',
            'tls': 'tls',
            'sni': domain }, separators = (',', ':'))
        link = f'''vmess://{base64.b64encode(vmess_json.encode()).decode()}'''
    elif protocol == 'Trojan WS TLS':
        path = '/trojan'
        link = f'''trojan://{uuid}@{domain}:{port}?path=%2Ftrojan&security=tls&type=ws&sni={domain}#{username}-Trojan'''
    return {
        'link': link,
        'address': address,
        'port_tls': port_tls,
        'port_ntls': port_ntls,
        'security': security,
        'sni': sni_disp,
        'path': path,
        'extras': extras }


def generate_all_links(username, uuid):
    server_conf = load_server_config()
    ip = get_ip()
    domain = server_conf.get('PRIMARY_DOMAIN', 'example.com')
    reality_pbk = read_file(REALITY_PUB_FILE)
    reality_sid = read_file(REALITY_SID_FILE)
    sni = server_conf.get('REALITY_SNI', 'www.microsoft.com')
    port = '443'
    links = { }
    links['VLESS Reality xHTTP'] = f'''vless://{uuid}@{ip}:{port}?security=reality&encryption=none&pbk={reality_pbk}&headerType=none&fp=chrome&type=xhttp&path=%2Fxhttp&sni={sni}&sid={reality_sid}#{username}-xHTTP'''
    links['VLESS Reality Vision'] = f'''vless://{uuid}@{ip}:{port}?security=reality&encryption=none&pbk={reality_pbk}&headerType=none&fp=chrome&type=tcp&flow=xtls-rprx-vision&sni={sni}&sid={reality_sid}#{username}-Vision'''
    links['VLESS WS TLS'] = f'''vless://{uuid}@{domain}:{port}?path=%2Fvless&security=tls&encryption=none&type=ws&sni={domain}#{username}-VLESS'''
    vmess_json = json.dumps({
        'v': '2',
        'ps': username,
        'add': domain,
        'port': port,
        'id': uuid,
        'aid': '0',
        'net': 'ws',
        'type': 'none',
        'host': domain,
        'path': '/vmess',
        'tls': 'tls',
        'sni': domain }, separators = (',', ':'))
    links['VMess WS TLS'] = f'''vmess://{base64.b64encode(vmess_json.encode()).decode()}'''
    links['Trojan WS TLS'] = f'''trojan://{uuid}@{domain}:{port}?path=%2Ftrojan&security=tls&type=ws&sni={domain}#{username}-Trojan'''
    return (links, ip, domain)


def build_xray_receipt(username, uuid, protocol, expiry, max_logins, data_limit):
    '''Build a full XRAY receipt for a single protocol, matching CLI format.'''
    login_disp = 'Unlimited' if str(max_logins) == '0' else f'''{max_logins} Devices'''
    bw_disp = 'Unlimited'
    if data_limit and int(data_limit) > 0:
        bw_disp = f'''{int(data_limit) // 1073741824} GB'''
    info = generate_single_link(username, uuid, protocol)
    msg = f'''🛡️ <b>{protocol}</b>\n━━━━━━━━━━━━━━━━━━━━━━━━\n'''
    msg += f'''Address     : <code>{info['address']}</code>\n'''
    msg += f'''Port (TLS)  : {info['port_tls']}\n'''
    if info['port_ntls']:
        msg += f'''Port (NTLS) : {info['port_ntls']}\n'''
    msg += f'''UUID / Pass : <code>{uuid}</code>\n'''
    msg += f'''Security    : {info['security']}\n'''
    msg += f'''SNI Domain  : <code>{info['sni']}</code>\n'''
    for k, v in info['extras'].items():
        msg += f'''{k}  : <code>{v}</code>\n'''
        if info['path']:
            msg += f'''Path        : {info['path']}\n'''
    msg += f'''Limit       : {login_disp}\n'''
    msg += f'''Data        : {bw_disp}\n'''
    msg += f'''Expiration  : {expiry}\n'''
    msg += '━━━━━━━━━━━━━━━━━━━━━━━━\n'
    msg += f'''<code>{info['link']}</code>\n'''
    msg += '━━━━━━━━━━━━━━━━━━━━━━━━'
    return msg


def build_ssh_panel(username, password, ip, domain, conf, expiry, max_logins, data_limit):
    port_ws_http = conf.get('PORT_WS_HTTP', '80')
    port_ws_https = conf.get('PORT_WS_HTTPS', '443')
    port_socks = conf.get('PORT_SOCKS', '1080')
    port_dropbear = conf.get('PORT_DROPBEAR', '109')
    port_dropbear_alt = conf.get('PORT_DROPBEAR_ALT', '143')
    ns_domain = conf.get('NS_DOMAIN', domain)
    dnstt_pub = read_file('/opt/imagitech/core/keys/dnstt.pub')
    login_disp = 'Unlimited' if str(max_logins) == '0' else f'''{max_logins} Devices'''
    bw_disp = 'Unlimited'
    if data_limit and int(data_limit) > 0:
        bw_disp = f'''{int(data_limit) // 1073741824} GB'''
    msg = []['🔐 <b>SSH ACCOUNT DETAILS</b>\n━━━━━━━━━━━━━━━━━━━━━━━━\n👤 Username    : <code>'][f'''{username}''']['</code>\n🔑 Password    : <code>'][f'''{password}''']['</code>\n📅 Expires     : '][f'''{expiry}''']['\n📱 Limit       : '][f'''{login_disp}''']['\n💾 Data        : '][f'''{bw_disp}''']['\n🌐 Server IP   : <code>'][f'''{ip}''']['</code>\n🏠 Host        : <code>'][f'''{domain}''']['</code>\n━━━━━━━━━━━━━━━━━━━━━━━━\n<b>🔌 CONNECTION PORTS</b>\nOpenSSH     : 22\nDropbear    : '][f'''{port_dropbear}'''][', '][f'''{port_dropbear_alt}''']['\nSSH WS      : 80, 8080, 8880\nSSH WSS     : 443, 8443\nDNSTT       : 53, 5300\nSOCKS5      : '][f'''{port_socks}''']['\nUDP Custom  : 1-65535\n━━━━━━━━━━━━━━━━━━━━━━━━\n<b>⚙️ QUICK CONNECT</b>\nSSH-80  : <code>'][f'''{domain}'''][':80@'][f'''{username}'''][':'][f'''{password}''']['</code>\nSSH-443 : <code>'][f'''{domain}'''][':443@'][f'''{username}'''][':'][f'''{password}''']['</code>\nSOCKS5  : <code>'][f'''{domain}'''][':'][f'''{port_socks}'''][':'][f'''{username}'''][':'][f'''{password}''']['</code>\nCustom  : <code>'][f'''{domain}'''][':8080@'][f'''{username}'''][':'][f'''{password}''']['</code>\n━━━━━━━━━━━━━━━━━━━━━━━━\n<b>📜 PAYLOADS</b>\n<b>WSS:</b> <code>GET wss://bug.com [protocol][crlf]Host: '][f'''{domain}''']['[crlf]Upgrade: websocket[crlf][crlf]</code>\n\n<b>WS:</b> <code>GET / HTTP/1.1[crlf]Host: '][f'''{domain}''']['[crlf]Upgrade: websocket[crlf][crlf]</code>\n\n<b>Custom:</b> <code>GET http://'][f'''{domain}'''][':8080 HTTP/1.1[crlf]Host: [SNI_BUG_HOST][crlf]Upgrade: websocket[crlf]Connection: Upgrade[crlf][crlf]</code>\n━━━━━━━━━━━━━━━━━━━━━━━━\nNameserver: <code>'][f'''{ns_domain}''']['</code>\nDNS: <code>1.1.1.1</code> / <code>8.8.8.8</code>\nPublic Key: <code>'][f'''{dnstt_pub.strip()}''']([]['🔐 <b>SSH ACCOUNT DETAILS</b>\n━━━━━━━━━━━━━━━━━━━━━━━━\n👤 Username    : <code>'][f'''{username}''']['</code>\n🔑 Password    : <code>'][f'''{password}''']['</code>\n📅 Expires     : '][f'''{expiry}''']['\n📱 Limit       : '][f'''{login_disp}''']['\n💾 Data        : '][f'''{bw_disp}''']['\n🌐 Server IP   : <code>'][f'''{ip}''']['</code>\n🏠 Host        : <code>'][f'''{domain}''']['</code>\n━━━━━━━━━━━━━━━━━━━━━━━━\n<b>🔌 CONNECTION PORTS</b>\nOpenSSH     : 22\nDropbear    : '][f'''{port_dropbear}'''][', '][f'''{port_dropbear_alt}''']['\nSSH WS      : 80, 8080, 8880\nSSH WSS     : 443, 8443\nDNSTT       : 53, 5300\nSOCKS5      : '][f'''{port_socks}''']['\nUDP Custom  : 1-65535\n━━━━━━━━━━━━━━━━━━━━━━━━\n<b>⚙️ QUICK CONNECT</b>\nSSH-80  : <code>'][f'''{domain}'''][':80@'][f'''{username}'''][':'][f'''{password}''']['</code>\nSSH-443 : <code>'][f'''{domain}'''][':443@'][f'''{username}'''][':'][f'''{password}''']['</code>\nSOCKS5  : <code>'][f'''{domain}'''][':'][f'''{port_socks}'''][':'][f'''{username}'''][':'][f'''{password}''']['</code>\nCustom  : <code>'][f'''{domain}'''][':8080@'][f'''{username}'''][':'][f'''{password}''']['</code>\n━━━━━━━━━━━━━━━━━━━━━━━━\n<b>📜 PAYLOADS</b>\n<b>WSS:</b> <code>GET wss://bug.com [protocol][crlf]Host: '][f'''{domain}''']['[crlf]Upgrade: websocket[crlf][crlf]</code>\n\n<b>WS:</b> <code>GET / HTTP/1.1[crlf]Host: '][f'''{domain}''']['[crlf]Upgrade: websocket[crlf][crlf]</code>\n\n<b>Custom:</b> <code>GET http://'][f'''{domain}'''][':8080 HTTP/1.1[crlf]Host: [SNI_BUG_HOST][crlf]Upgrade: websocket[crlf]Connection: Upgrade[crlf][crlf]</code>\n━━━━━━━━━━━━━━━━━━━━━━━━\nNameserver: <code>'][f'''{ns_domain}''']['</code>\nDNS: <code>1.1.1.1</code> / <code>8.8.8.8</code>\nPublic Key: <code>'][f'''{dnstt_pub.strip()}''']['</code>'])
    return msg


def get_license_info(ip):
    
    def process_date(date_str):
        if not date_str == 'Unknown' or date_str:
            return 'Unknown'
        date_part = None.split('T')[0]
        
        try:
            year = int(date_part.split('-')[0])
            if year > 2099:
                return 'Lifetime'
        except:
            pass

        return date_part

    
    try:
        url = f'''https://vpn.imagitech.online/api/v1/ip/verify?ip={ip}'''
        req = urllib.request.Request(url, headers = {
            'User-Agent': 'Imagitech-Controller/1.0' })
        resp = urllib.request.urlopen(req, timeout = 8)
        data = json.loads(resp.read().decode())
        
        try:
            None(None, None)
            return 
            with None:
                if not None, (data.get('name', 'N/A'), process_date(data.get('expires_at', 'Unknown'))):
                    
                    try:
                        
                        try:
                            return None
                        except urllib.error.HTTPError:
                            json.loads(e.read().decode()) = None
                            del e
                            return None
                            
                            None = None, (data.get('name', 'N/A'), process_date(data.get('expires_at', 'Unknown')))
                            del e
                            return ('Unknown', 'Unknown')
                            e = None
                            del e
                            except Exception:
                                return ('Unknown', 'Unknown')






def get_main_menu_keyboard():
    return {
        'inline_keyboard': [
            [
                {
                    'text': 'Add SSH',
                    'callback_data': 'prompt_/add_user_ssh' },
                {
                    'text': 'Add XRAY',
                    'callback_data': 'xray_proto_add' }],
            [
                {
                    'text': 'Trial SSH',
                    'callback_data': 'prompt_/add_trial_ssh' },
                {
                    'text': 'Trial XRAY',
                    'callback_data': 'xray_proto_trial' }],
            [
                {
                    'text': 'Renew User',
                    'callback_data': 'renew_menu' },
                {
                    'text': '📋 List Users',
                    'callback_data': 'list_users' },
                {
                    'text': '🟢 Online',
                    'callback_data': 'online' }],
            [
                {
                    'text': 'ℹ️ User Info',
                    'callback_data': 'prompt_/user_info' },
                {
                    'text': '🔑 SSH Info',
                    'callback_data': 'prompt_/ssh_info' },
                {
                    'text': '🌐 Xray Links',
                    'callback_data': 'prompt_/xray_info' }],
            [
                {
                    'text': '📊 Status',
                    'callback_data': 'status' },
                {
                    'text': '📡 Bandwidth',
                    'callback_data': 'bandwidth' },
                {
                    'text': '🔌 Ports',
                    'callback_data': 'ports' }],
            [
                {
                    'text': '🔒 Domain & SSL',
                    'callback_data': 'domain_ssl' },
                {
                    'text': '🪪 License',
                    'callback_data': 'license_status' }],
            [
                {
                    'text': '🛠 Service Manager',
                    'callback_data': 'service_manager' },
                {
                    'text': '♻️ Reboot',
                    'callback_data': 'reboot_confirm' }]] }


def get_back_keyboard(target = ('main_menu',)):
    return {
        'inline_keyboard': [
            [
                {
                    'text': '🔙 Back',
                    'callback_data': target }]] }


def cmd_start(token, chat_id, message_id = (None,)):
    geo = load_geo()
    ip = get_ip()
    country = geo.get('SERVER_COUNTRY', '🌐')
    isp = geo.get('SERVER_ISP', 'Unknown ISP')
    (lic_name, lic_expires) = get_license_info(ip)
    msg = f'''━━━━━━━━━━━━━━━━━━━\n🛡️ <b>IMAGITECH CONTROLLER</b> 🛡️\n━━━━━━━━━━━━━━━━━━━\n\n🖥 <b>Server:</b> <code>{ip}</code> ({country})\n📡 <b>ISP:</b> {isp}\n👤 <b>License Name:</b> <code>{lic_name}</code>\n⏰ <b>License Expires:</b> {lic_expires}\n\nSelect an action below to manage your infrastructure:'''
    if message_id:
        edit_message(token, chat_id, message_id, msg, get_main_menu_keyboard())
        return None
    None(token, chat_id, msg, get_main_menu_keyboard())


def cb_status(token, chat_id, message_id):
    uptime = run_cmd('uptime -p')
    cpu = run_cmd('top -bn1 | grep \'load average\' | awk \'{printf "%.2f", $(NF-2)}\'')
    mem = run_cmd('free -m | awk \'NR==2{printf "%s / %s MB (%.1f%%)", $3, $2, $3*100/$2}\'')
    disk = run_cmd('df -h / | awk \'NR==2{printf "%s / %s (%s)", $3, $2, $5}\'')
    users = db_query("SELECT COUNT(*) FROM users WHERE status='ACTIVE'")
    user_count = users[0][0] if users and isinstance(users, list) else 0
    swap = run_cmd('free -m | awk \'NR==3{printf "%s / %s MB", $3, $2}\'')
    msg = f'''📊 <b>SYSTEM STATUS</b>\n━━━━━━━━━━━━━━━━\n⏱ Uptime     : {uptime}\n🧠 CPU Load   : {cpu}\n💾 Memory     : {mem}\n💿 Disk       : {disk}\n🔄 Swap       : {swap}\n👥 Active VPN : {user_count} users\n━━━━━━━━━━━━━━━━'''
    edit_message(token, chat_id, message_id, msg, get_back_keyboard())


def cb_bandwidth(token, chat_id, message_id):
    bw = run_cmd('vnstat --oneline 2>/dev/null')
    if bw and 'Not enough' in bw or 'Error' in bw:
        bw_full = run_cmd('vnstat -d 2>/dev/null | tail -n 8')
        if not bw_full:
            bw_full = 'vnStat not configured.'
        edit_message(token, chat_id, message_id, f'''📶 <b>BANDWIDTH</b>\n\n<pre>{bw_full}</pre>''', get_back_keyboard())
        return None
    parts = None.split(';')
    if len(parts) >= 11:
        msg = f'''📶 <b>BANDWIDTH USAGE</b>\n━━━━━━━━━━━━━━━━\n<b>Today</b>\n  ↓ RX: {parts[3]}\n  ↑ TX: {parts[4]}\n  ⊕ Total: {parts[5]}\n\n<b>This Month</b>\n  ↓ RX: {parts[8]}\n  ↑ TX: {parts[9]}\n  ⊕ Total: {parts[10]}\n━━━━━━━━━━━━━━━━'''
    else:
        msg = f'''📶 <b>BANDWIDTH</b>\n\n<pre>{bw}</pre>'''
    edit_message(token, chat_id, message_id, msg, get_back_keyboard())


def cb_ports(token, chat_id, message_id):
    conf = load_server_config()
    msg = f'''🔌 <b>PORT MAP</b>\n━━━━━━━━━━━━━━━━\n  OpenSSH           : {conf.get('PORT_SSH', '22')}\n  Dropbear          : {conf.get('PORT_DROPBEAR', '109')}, {conf.get('PORT_DROPBEAR_ALT', '143')}\n  HAProxy HTTP      : {conf.get('PORT_WS_HTTP', '80')}, 8080, 8880\n  HAProxy HTTPS     : {conf.get('PORT_WS_HTTPS', '443')}, 8443\n  Custom SSH (HTTP) : 8880\n  SOCKS5            : {conf.get('PORT_SOCKS', '1080')}\n  SSL/TLS           : 8443\n  UDPGW             : 7300\n━━━━━━━━━━━━━━━━\n  VLESS Reality     : 10001\n  VLESS xHTTP       : 10005\n  VLESS WS          : 10002\n  VMess WS          : 10003\n  Trojan WS         : 10004\n  Xray API          : 10085\n━━━━━━━━━━━━━━━━'''
    edit_message(token, chat_id, message_id, msg, get_back_keyboard())


def cb_list_users(token, chat_id, message_id):
    rows = db_query('SELECT username, status, expiry_date, max_logins FROM users ORDER BY expiry_date DESC')
    if rows and isinstance(rows, list) or len(rows) == 0:
        edit_message(token, chat_id, message_id, '📋 No users in database.', get_back_keyboard())
        return None
    msg = f'''{len(rows)} total)\n━━━━━━━━━━━━━━━━\n'''
    for r in rows:
        (uname, status, exp, ml) = r
        icon = '🟢' if status == 'ACTIVE' else '🔴'
        ml_txt = '∞' if ml == 0 else str(ml)
        msg += f'''{icon} <code>{uname}</code> │ {exp[:10]} │ {ml_txt}🔌\n'''
        msg += '━━━━━━━━━━━━━━━━'
        edit_message(token, chat_id, message_id, msg[:4000], get_back_keyboard())
        return None


def cb_online(token, chat_id, message_id):
    if os.path.exists(ONLINE_FILE):
        data = read_file(ONLINE_FILE)
    else:
        data = run_cmd('/opt/imagitech/bin/imagitech sys online')
    if data and 'starting' in data.lower() or 'no active' in data.lower():
        edit_message(token, chat_id, message_id, '🟡 No active connections right now.', get_back_keyboard())
        return None
    msg = None
    for line in data.strip().split('\n'):
        parts = line.split('|')
        if len(parts) == 2:
            uname = parts[0].strip()
            count = parts[1].strip()
            icon = '🔴' if int(count) >= 3 else '🟢'
            msg += f'''{icon} <code>{uname}</code> — {count} device(s)\n'''
            continue
        msg += f'''  {line}\n'''
        msg += '━━━━━━━━━━━━━━━━'
        edit_message(token, chat_id, message_id, msg, get_back_keyboard())
        return None


def cb_license_status(token, chat_id, message_id):
    ip = get_ip()
    (lic_name, lic_expires) = get_license_info(ip)
    msg = f'''🪪 <b>LICENSE STATUS</b>\n━━━━━━━━━━━━━━━━\n🖥 IP: <code>{ip}</code>\n👤 Name: <code>{lic_name}</code>\n⏰ Expires: {lic_expires}\n━━━━━━━━━━━━━━━━'''
    edit_message(token, chat_id, message_id, msg, get_back_keyboard())


def cb_domain_ssl(token, chat_id, message_id):
    conf = load_server_config()
    primary = conf.get('PRIMARY_DOMAIN', 'N/A')
    ns = conf.get('NS_DOMAIN', 'N/A')
    sni = conf.get('REALITY_SNI', 'www.microsoft.com')
    msg = f'''🔒 <b>DOMAIN & SSL SETTINGS</b>\n━━━━━━━━━━━━━━━━\n🏠 <b>Host:</b> <code>{primary}</code>\n🌐 <b>NS:</b> <code>{ns}</code>\n🎭 <b>REALITY SNI:</b> <code>{sni}</code>\n━━━━━━━━━━━━━━━━\nSelect an action to modify:'''
    keyboard = {
        'inline_keyboard': [
            [
                {
                    'text': '🏠 Change Host Domain',
                    'callback_data': 'change_host' }],
            [
                {
                    'text': '🌐 Change NS Domain',
                    'callback_data': 'change_ns' }],
            [
                {
                    'text': '🎭 Change REALITY SNI',
                    'callback_data': 'change_sni' }],
            [
                {
                    'text': '🔑 Generate SlowDNS Key',
                    'callback_data': 'gen_slowdns' }],
            [
                {
                    'text': '🔙 Back to Main',
                    'callback_data': 'main_menu' }]] }
    edit_message(token, chat_id, message_id, msg, keyboard)


def cb_reboot_confirm(token, chat_id, message_id):
    msg = '⚠️ <b>Are you sure you want to reboot the server?</b>'
    keyboard = {
        'inline_keyboard': [
            [
                {
                    'text': '✅ Yes, Reboot',
                    'callback_data': 'reboot_exec' }],
            [
                {
                    'text': '❌ Cancel',
                    'callback_data': 'main_menu' }]] }
    edit_message(token, chat_id, message_id, msg, keyboard)


def cb_reboot_exec(token, chat_id, message_id):
    msg = '🔄 <b>Rebooting VPS now.</b>\nThe bot will go offline briefly.'
    edit_message(token, chat_id, message_id, msg)
    run_cmd('reboot')


def cb_sni_menu(token, chat_id, message_id):
    msg = '🎭 <b>Select REALITY SNI</b>\n\nChoose a preset or enter a custom one:'
    keyboard = {
        'inline_keyboard': [
            [
                {
                    'text': '🌍 www.bing.com',
                    'callback_data': 'exec_sni_www.bing.com' },
                {
                    'text': '🌍 www.apple.com',
                    'callback_data': 'exec_sni_www.apple.com' }],
            [
                {
                    'text': '🌍 www.amazon.com',
                    'callback_data': 'exec_sni_www.amazon.com' },
                {
                    'text': '🌍 www.cloudflare.com',
                    'callback_data': 'exec_sni_cloudflare.com' }],
            [
                {
                    'text': '🇷🇺 storage.yandex.net',
                    'callback_data': 'exec_sni_storage.yandex.net' },
                {
                    'text': '🇷🇺 www.ya.ru',
                    'callback_data': 'exec_sni_www.ya.ru' }],
            [
                {
                    'text': '🇹🇲 pl02.launch.tel',
                    'callback_data': 'exec_sni_pl02.launch.tel' },
                {
                    'text': '🇷🇺 eh.vk.com',
                    'callback_data': 'exec_sni_eh.vk.com' }],
            [
                {
                    'text': '🇯🇵 lovelive-anime.jp',
                    'callback_data': 'exec_sni_www.lovelive-anime.jp' },
                {
                    'text': '🇹🇲 iping.ggff.net',
                    'callback_data': 'exec_sni_iping.ggff.net' }],
            [
                {
                    'text': '✏️ Enter Custom SNI',
                    'callback_data': 'prompt_sni' }],
            [
                {
                    'text': '🔙 Back',
                    'callback_data': 'domain_ssl' }]] }
    edit_message(token, chat_id, message_id, msg, keyboard)


def cb_prompt_input(token, chat_id, message_id, action, user_states):
    if action == 'prompt_/add_user_ssh':
        text = 'Enter: username password days [max_logins] [bw_gb]'
    elif action.startswith('prompt_/add_user_xray_'):
        text = 'Enter: username password days [max_logins] [bw_gb]'
    elif action == 'prompt_/add_trial_ssh':
        text = 'Enter: hours [max_logins] [bw_gb]'
    elif action.startswith('prompt_/add_trial_xray_'):
        text = 'Enter: hours [max_logins] [bw_gb]'
    elif action == 'prompt_/renew_user':
        text = 'Enter: username days'
    elif action == 'prompt_/renew_logins':
        text = 'Enter: username new_max_logins\n(0 = Unlimited)'
    elif action == 'prompt_/renew_bw':
        text = 'Enter: username bandwidth_gb\n(0 = Unlimited)'
    elif action == 'prompt_/user_info':
        text = 'ℹ️ <b>User Info</b>\nReply with username:'
    elif action == 'prompt_/ssh_info':
        text = '🔑 <b>SSH Info</b>\nReply with username:'
    elif action == 'prompt_/xray_info':
        text = '🌐 <b>Xray Links</b>\nReply with username:'
    else:
        prompts = {
            'change_host': '🏠 <b>Change Host Domain</b>\nReply with domain:\n<code>example.com</code>',
            'change_ns': '🌐 <b>Change NS Domain</b>\nReply with NS domain:\n<code>ns.example.com</code>',
            'change_sni': '🎭 <b>Change REALITY SNI</b>\nReply with SNI:\n<code>www.apple.com</code>',
            'prompt_sni': '🎭 <b>Enter Custom SNI</b>\nReply with SNI domain:\n<code>www.apple.com</code>',
            'del_user': '❌ <b>Delete User</b>\nReply with username:\n<code>username</code>',
            'restart': '🔁 <b>Restart Service</b>\nReply with service:\n<code>haproxy</code>' }
        text = prompts.get(action, 'Unknown action.')
    back_target = 'domain_ssl' if 'change_' in action or action == 'prompt_sni' else 'main_menu'
    edit_message(token, chat_id, message_id, text, get_back_keyboard(back_target))
    state = action.replace('prompt_/', '/')
    if action == 'prompt_sni':
        state = '/set_sni'
    user_states[str(chat_id)] = state


def cb_gen_slowdns(token, chat_id, message_id):
    out = run_cmd('/opt/imagitech/bin/imagitech config dnstt')
    edit_message(token, chat_id, message_id, f'''✅ <b>SlowDNS Key Re-generated</b>\n\n<pre>{out}</pre>''', get_back_keyboard('domain_ssl'))


def cb_service_manager(token, chat_id, message_id):
    text = '🛠 <b>SERVICE MANAGER</b>\n━━━━━━━━━━━━━━━━\nSelect a service to restart:'
    kb = {
        'inline_keyboard': [
            [
                {
                    'text': '🔄 Restart All',
                    'callback_data': 'exec_restart_all' }],
            [
                {
                    'text': 'Dropbear',
                    'callback_data': 'exec_restart_dropbear' },
                {
                    'text': 'WS Proxy',
                    'callback_data': 'exec_restart_imagitech-ws' }],
            [
                {
                    'text': 'HAProxy',
                    'callback_data': 'exec_restart_haproxy' },
                {
                    'text': 'Xray Core',
                    'callback_data': 'exec_restart_imagitech-xray' }],
            [
                {
                    'text': 'DNSTT',
                    'callback_data': 'exec_restart_imagitech-dnstt' },
                {
                    'text': 'Nginx',
                    'callback_data': 'exec_restart_nginx' }],
            [
                {
                    'text': '◀️ Back to Main',
                    'callback_data': 'main_menu' }]] }
    edit_message(token, chat_id, message_id, text, kb)


def handle_text_command(text, token, chat_id, message_id, user_states):
    delete_message(token, chat_id, message_id)
    parts = text.strip().split()
    if not parts:
        return None
    cmd = None[0].lower().split('@')[0]
    if cmd in ('/start', '/help', '/menu'):
        user_states.pop(str(chat_id), None)
        cmd_start(token, chat_id)
        return None
    state = None.pop(str(chat_id), None)
    xray_protocol = None
    if state:
        if state.startswith('/add_user_xray_'):
            xray_protocol = state.replace('/add_user_xray_', '')
            cmd = '/add_user_xray'
            parts = [
                cmd] + parts
        elif state.startswith('/add_trial_xray_'):
            xray_protocol = state.replace('/add_trial_xray_', '')
            cmd = '/add_trial_xray'
            parts = [
                cmd] + parts
        else:
            state_to_cmd = {
                'change_host': '/set_host',
                'change_ns': '/set_ns',
                '/set_sni': '/set_sni',
                '/add_user_ssh': '/add_user_ssh',
                '/add_trial_ssh': '/add_trial_ssh',
                '/renew_user': '/renew_user',
                '/renew_logins': '/renew_logins',
                '/renew_bw': '/renew_bw',
                '/del_user': '/del_user',
                '/user_info': '/user_info',
                '/ssh_info': '/ssh_info',
                '/xray_info': '/xray_info',
                '/restart': '/restart' }
            if state in state_to_cmd:
                cmd = state_to_cmd[state]
                parts = [
                    cmd] + parts
    out = ''
    send_xray = False
    send_xray_single = False
    send_ssh = False
    user = ''
    if cmd == '/add_user_ssh':
        if len(parts) >= 4:
            days = parts[3]
            pwd = parts[2]
            user = parts[1]
            ml = parts[4] if len(parts) > 4 else '2'
            bw = parts[5] if len(parts) > 5 else '0'
            out = run_cmd(f'''/opt/imagitech/bin/imagitech user add {shlex.quote(user)} {shlex.quote(pwd)} {shlex.quote(str(days))} {shlex.quote(str(ml))} {shlex.quote(str(bw))} SSH''')
            if 'already exists' not in out.lower() and 'error' not in out.lower():
                send_ssh = True
            else:
                out = 'Usage: username password days [max_logins] [bw_gb]'
        elif cmd == '/add_user_xray':
            if len(parts) >= 4:
                days = parts[3]
                pwd = parts[2]
                user = parts[1]
                ml = parts[4] if len(parts) > 4 else '2'
                bw = parts[5] if len(parts) > 5 else '0'
                out = run_cmd(f'''/opt/imagitech/bin/imagitech user add {shlex.quote(user)} {shlex.quote(pwd)} {shlex.quote(str(days))} {shlex.quote(str(ml))} {shlex.quote(str(bw))} XRAY''')
                if 'already exists' not in out.lower() and 'error' not in out.lower():
                    if xray_protocol:
                        send_xray_single = True
                    else:
                        send_xray = True
                else:
                    out = 'Usage: username password days [max_logins] [bw_gb]'
            elif cmd == '/add_trial_ssh':
                hours = parts[1] if len(parts) > 1 else '2'
                ml = parts[2] if len(parts) > 2 else '2'
                bw = parts[3] if len(parts) > 3 else '0'
                user = f'''trial{random.randint(1000, 9999)}'''
                pwd = rand_password(6)
                out = run_cmd(f'''/opt/imagitech/bin/imagitech user trial {shlex.quote(user)} {shlex.quote(pwd)} {shlex.quote(str(hours))} {shlex.quote(str(ml))} {shlex.quote(str(bw))} SSH''')
                if 'error' not in out.lower():
                    send_ssh = True
                elif cmd == '/add_trial_xray':
                    hours = parts[1] if len(parts) > 1 else '2'
                    ml = parts[2] if len(parts) > 2 else '2'
                    bw = parts[3] if len(parts) > 3 else '0'
                    user = f'''trial{random.randint(1000, 9999)}'''
                    pwd = rand_password(6)
                    out = run_cmd(f'''/opt/imagitech/bin/imagitech user trial {shlex.quote(user)} {shlex.quote(pwd)} {shlex.quote(str(hours))} {shlex.quote(str(ml))} {shlex.quote(str(bw))} XRAY''')
                    if 'error' not in out.lower():
                        if xray_protocol:
                            send_xray_single = True
                        else:
                            send_xray = True
                    elif cmd == '/renew_user':
                        if len(parts) >= 3:
                            out = run_cmd(f'''/opt/imagitech/bin/imagitech user renew {shlex.quote(parts[1])} {shlex.quote(parts[2])}''')
                            row = db_query('SELECT expiry_date FROM users WHERE username=?', (parts[1],))
                            if row and len(row) > 0:
                                new_exp = row[0][0]
                                out = f'''✅ <b>Account renewed</b>\n━━━━━━━━━━━━━━━━━━━━━━━━\nUsername    : <code>{parts[1]}</code>\nModification: {'+' if int(parts[2]) > 0 else ''}{parts[2]} Days\nNew Expiry  : {new_exp}\n━━━━━━━━━━━━━━━━━━━━━━━━'''
                            else:
                                out = 'Usage: username days'
                        elif cmd == '/renew_logins':
                            if len(parts) >= 3:
                                new_logins = parts[2]
                                uname = parts[1]
                                if new_logins.isdigit():
                                    db_query(f'''UPDATE users SET max_logins={new_logins} WHERE username=?''', (uname,), fetch = False)
                                    disp = 'Unlimited' if new_logins == '0' else f'''{new_logins} Devices'''
                                    out = f'''✅ Max Logins updated to <b>{disp}</b> for <code>{uname}</code>'''
                                else:
                                    out = 'Invalid input. Enter a number (0 = Unlimited).'
                            else:
                                out = 'Usage: username max_logins'
                        elif cmd == '/renew_bw':
                            if len(parts) >= 3:
                                new_bw = parts[2]
                                uname = parts[1]
                                if new_bw.isdigit():
                                    data_bytes = int(new_bw) * 1073741824
                                    db_query(f'''UPDATE users SET data_limit={data_bytes} WHERE username=?''', (uname,), fetch = False)
                                    disp = 'Unlimited' if new_bw == '0' else f'''{new_bw} GB'''
                                    out = f'''✅ Bandwidth updated to <b>{disp}</b> for <code>{uname}</code>'''
                                else:
                                    out = 'Invalid input. Enter a number (0 = Unlimited).'
                            else:
                                out = 'Usage: username bandwidth_gb'
                        elif cmd == '/del_user':
                            if len(parts) >= 2:
                                out = run_cmd(f'''/opt/imagitech/bin/imagitech user del {shlex.quote(parts[1])}''')
                            else:
                                out = 'Usage: /del_user user'
                        elif cmd == '/user_info':
                            if len(parts) >= 2:
                                row = db_query('SELECT uuid, expiry_date, max_logins, status, data_limit, data_usage, account_type FROM users WHERE username=?', (parts[1],))
                                if row and len(row) > 0:
                                    (u, e, m, s, d, du, at) = row[0]
                                    login_d = 'Unlimited' if str(m) == '0' else f'''{m} Devices'''
                                    bw_d = 'Unlimited'
                                    if d and int(d) > 0:
                                        bw_d = f'''{int(d) // 1073741824} GB'''
                                    du_val = int(du) if du else 0
                                    if du_val > 1073741824:
                                        used_d = f'''{du_val / 1073741824:.2f} GB'''
                                    else:
                                        used_d = f'''{du_val / 1048576:.2f} MB'''
                                    out = f'''ℹ️ <b>User Info — {parts[1]}</b>\n━━━━━━━━━━━━━━━━━━━━━━━━\nStatus     : {s}\nType       : {at}\nExpiry     : {e}\nMax Logins : {login_d}\nData Limit : {bw_d}\nData Used  : {used_d}\nUUID       : <code>{u}</code>\n━━━━━━━━━━━━━━━━━━━━━━━━'''
                                else:
                                    out = f'''User <code>{parts[1]}</code> not found.'''
                            else:
                                out = 'Usage: /user_info user'
                        elif cmd == '/ssh_info':
                            if len(parts) >= 2:
                                user = parts[1]
                                send_ssh = True
                            else:
                                out = 'Usage: /ssh_info user'
                        elif cmd == '/xray_info':
                            if len(parts) >= 2:
                                user = parts[1]
                                send_xray = True
                            else:
                                out = 'Usage: /xray_info user'
                        elif cmd == '/restart':
                            if len(parts) >= 2:
                                out = run_cmd(f'''systemctl restart {shlex.quote(parts[1])}''')
                            else:
                                out = 'Usage: /restart service'
                        elif cmd == '/set_host':
                            if len(parts) >= 2:
                                out = run_cmd(f'''/opt/imagitech/bin/imagitech config host {shlex.quote(parts[1])}''')
                            else:
                                out = 'Usage: /set_host domain'
                        elif cmd == '/set_ns':
                            if len(parts) >= 2:
                                out = run_cmd(f'''/opt/imagitech/bin/imagitech config ns {shlex.quote(parts[1])}''')
                            else:
                                out = 'Usage: /set_ns domain'
                        elif cmd == '/set_sni':
                            if len(parts) >= 2:
                                out = run_cmd(f'''/opt/imagitech/bin/imagitech config sni {shlex.quote(parts[1])}''')
                            else:
                                out = 'Usage: /set_sni domain'
                        else:
                            out = 'Unknown command or input.'
    if send_ssh and send_xray or send_xray_single:
        row = db_query('SELECT uuid, expiry_date, max_logins, data_limit FROM users WHERE username=?', (user,))
        if row and len(row) > 0:
            (uuid, exp, max_logins, data_limit) = row[0]
            conf = load_server_config()
            if send_ssh:
                pwd_show = pwd if cmd in ('/add_trial_ssh', '/add_user_ssh') else '[Password hidden]'
                ip = get_ip()
                domain = conf.get('PRIMARY_DOMAIN', 'example.com')
                ssh_msg = build_ssh_panel(user, pwd_show, ip, domain, conf, exp, max_logins, data_limit)
                send_message(token, chat_id, ssh_msg)
            if send_xray_single and xray_protocol:
                proto_map = {
                    'reality_xhttp': 'VLESS Reality xHTTP',
                    'reality_vision': 'VLESS Reality Vision',
                    'vless_ws': 'VLESS WS TLS',
                    'trojan_ws': 'Trojan WS TLS',
                    'vmess_ws': 'VMess WS TLS' }
                proto_name = proto_map.get(xray_protocol, 'VLESS WS TLS')
                receipt = build_xray_receipt(user, uuid, proto_name, exp, max_logins, data_limit)
                send_message(token, chat_id, receipt)
            elif send_xray:
                login_disp = 'Unlimited' if str(max_logins) == '0' else f'''{max_logins} Devices'''
                bw_disp = 'Unlimited'
                if data_limit and int(data_limit) > 0:
                    bw_disp = f'''{int(data_limit) // 1073741824} GB'''
                (links, ip, domain) = generate_all_links(user, uuid)
                for proto_name in ('VLESS Reality xHTTP', 'VLESS Reality Vision', 'VLESS WS TLS', 'Trojan WS TLS', 'VMess WS TLS'):
                    receipt = build_xray_receipt(user, uuid, proto_name, exp, max_logins, data_limit)
                    send_message(token, chat_id, receipt)
                    out = f'''✅ Success processing {user}'''
                    if out:
                        send_message(token, chat_id, out, get_main_menu_keyboard())
                        return None
                    return None


def set_bot_commands(token):
    commands = [
        {
            'command': 'start',
            'description': 'Show main dashboard' }]
    api_request(token, 'setMyCommands', {
        'commands': commands })


def main():
    user_states = { }
    print('Imagitech Telegram Controller v3.0 starting...')
    offset_file = '/opt/imagitech/core/telegram_offset.txt'
    offset = int(read_file(offset_file, '0'))
    commands_set = False
    (token, admin_id) = load_config()
    if not token or admin_id:
        time.sleep(10)
        continue
    if not commands_set:
        set_bot_commands(token)
        commands_set = True
    updates = api_request(token, 'getUpdates', {
        'offset': offset,
        'timeout': 10 })
    if updates and 'result' in updates:
        for update in updates['result']:
            offset = update['update_id'] + 1
            f = open(offset_file, 'w')
            f.write(str(offset))
            None(None, None)
        with None:
            if not None:
                pass
    
    if 'message' in update and 'text' in update['message']:
        chat_id = str(update['message']['chat']['id'])
        msg_id = update['message']['message_id']
        text = update['message']['text'].strip()
        if chat_id == admin_id:
            handle_text_command(text, token, chat_id, msg_id, user_states)
            continue
            except Exception:
                e = None
                print(f'''Error in text handler: {e}''')
                send_message(token, chat_id, f'''❌ <b>Error processing command:</b>\n<pre>{e}</pre>''')
                e = None
                del e
                continue
                e = None
                del e
        continue
    if 'callback_query' in update:
        cq = update['callback_query']
        data = cq['data']
        chat_id = str(cq['message']['chat']['id'])
        msg_id = cq['message']['message_id']
        if chat_id == admin_id:
            if data == 'main_menu':
                user_states.pop(chat_id, None)
                cmd_start(token, chat_id, msg_id)
            elif data == 'status':
                cb_status(token, chat_id, msg_id)
            elif data == 'bandwidth':
                cb_bandwidth(token, chat_id, msg_id)
            elif data == 'ports':
                cb_ports(token, chat_id, msg_id)
            elif data == 'list_users':
                cb_list_users(token, chat_id, msg_id)
            elif data == 'online':
                cb_online(token, chat_id, msg_id)
            elif data == 'license_status':
                cb_license_status(token, chat_id, msg_id)
            elif data == 'domain_ssl':
                cb_domain_ssl(token, chat_id, msg_id)
            elif data == 'reboot_confirm':
                cb_reboot_confirm(token, chat_id, msg_id)
            elif data == 'reboot_exec':
                cb_reboot_exec(token, chat_id, msg_id)
            elif data == 'service_manager':
                cb_service_manager(token, chat_id, msg_id)
            elif data.startswith('exec_restart_'):
                svc = data.split('exec_restart_')[1]
                if svc == 'all':
                    out = run_cmd('/opt/imagitech/bin/imagitech service restart all')
                    msg = '✅ <b>All Services Restarted</b>'
                else:
                    out = run_cmd(f'''/opt/imagitech/bin/imagitech service restart {shlex.quote(svc)}''')
                    msg = f'''✅ <b>{svc} Restarted</b>'''
                edit_message(token, chat_id, msg_id, f'''{msg}\n\n<pre>{out}</pre>''', get_back_keyboard('service_manager'))
            elif data == 'gen_slowdns':
                cb_gen_slowdns(token, chat_id, msg_id)
            elif data == 'change_sni':
                cb_sni_menu(token, chat_id, msg_id)
            elif data.startswith('exec_sni_'):
                sni = data.split('exec_sni_')[1]
                out = run_cmd(f'''/opt/imagitech/bin/imagitech config sni {shlex.quote(sni)}''')
                edit_message(token, chat_id, msg_id, f'''✅ <b>SNI Updated to {sni}</b>\n\n<pre>{out}</pre>''', get_back_keyboard('domain_ssl'))
            elif data == 'xray_proto_add':
                kb = {
                    'inline_keyboard': [
                        [
                            {
                                'text': 'VLESS Reality xHTTP',
                                'callback_data': 'prompt_/add_user_xray_reality_xhttp' }],
                        [
                            {
                                'text': 'VLESS Reality Vision',
                                'callback_data': 'prompt_/add_user_xray_reality_vision' }],
                        [
                            {
                                'text': 'VLESS WS TLS',
                                'callback_data': 'prompt_/add_user_xray_vless_ws' }],
                        [
                            {
                                'text': 'Trojan WS TLS',
                                'callback_data': 'prompt_/add_user_xray_trojan_ws' }],
                        [
                            {
                                'text': 'VMess WS TLS',
                                'callback_data': 'prompt_/add_user_xray_vmess_ws' }],
                        [
                            {
                                'text': '🔙 Back',
                                'callback_data': 'main_menu' }]] }
                edit_message(token, chat_id, msg_id, '🌐 <b>Select XRAY Protocol:</b>', kb)
            elif data == 'xray_proto_trial':
                kb = {
                    'inline_keyboard': [
                        [
                            {
                                'text': 'VLESS Reality xHTTP',
                                'callback_data': 'prompt_/add_trial_xray_reality_xhttp' }],
                        [
                            {
                                'text': 'VLESS Reality Vision',
                                'callback_data': 'prompt_/add_trial_xray_reality_vision' }],
                        [
                            {
                                'text': 'VLESS WS TLS',
                                'callback_data': 'prompt_/add_trial_xray_vless_ws' }],
                        [
                            {
                                'text': 'Trojan WS TLS',
                                'callback_data': 'prompt_/add_trial_xray_trojan_ws' }],
                        [
                            {
                                'text': 'VMess WS TLS',
                                'callback_data': 'prompt_/add_trial_xray_vmess_ws' }],
                        [
                            {
                                'text': '🔙 Back',
                                'callback_data': 'main_menu' }]] }
                edit_message(token, chat_id, msg_id, '🧪 <b>Select Trial XRAY Protocol:</b>', kb)
            elif data == 'renew_menu':
                kb = {
                    'inline_keyboard': [
                        [
                            {
                                'text': '📅 Expiry Date (Days)',
                                'callback_data': 'prompt_/renew_user' }],
                        [
                            {
                                'text': '📱 Max Logins (Devices)',
                                'callback_data': 'prompt_/renew_logins' }],
                        [
                            {
                                'text': '💾 Bandwidth (GB)',
                                'callback_data': 'prompt_/renew_bw' }],
                        [
                            {
                                'text': '🔙 Back',
                                'callback_data': 'main_menu' }]] }
                edit_message(token, chat_id, msg_id, '♻️ <b>Renew User — Select Option:</b>', kb)
            elif data in ('del_user', 'change_host', 'change_ns', 'prompt_sni') or data.startswith('prompt_/'):
                cb_prompt_input(token, chat_id, msg_id, data, user_states)
            api_request(token, 'answerCallbackQuery', {
                'callback_query_id': cq['id'] })
            continue
            except Exception:
                e = None
                print(f'''Error in callback handler: {e}''')
                send_message(token, chat_id, f'''❌ <b>Error processing action:</b>\n<pre>{e}</pre>''')
                api_request(token, 'answerCallbackQuery', {
                    'callback_query_id': cq['id'] })
                e = None
                del e
                continue
                e = None
                del e
    continue
    time.sleep(1)
    continue

if __name__ == '__main__':
    main()
    return None
