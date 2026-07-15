# === Decompiled from server.pyc ===
# Source: PyInstaller binary, Python 3.11 bytecode
# Decompiled with pycdc (Decompyle++)
# NOTE: Some constructs may be imperfect due to bytecode decompiler limitations.
# ============================================================================

# Source Generated with Decompyle++
# File: server.pyc (Python 3.11)

'''
IMAGITECH TRIAL API SERVER
Allows remote creation of SSH and XRAY trial accounts.
'''
import os
import sys
import json
import sqlite3
import subprocess
import urllib.request as urllib
import logging
from http.server import HTTPServer, BaseHTTPRequestHandler
from datetime import datetime
logging.basicConfig(level = logging.INFO, format = '%(asctime)s [%(levelname)s] %(message)s', handlers = [
    logging.StreamHandler(sys.stdout)])
CONF_FILE = '/opt/imagitech/core/trial-api.conf'
IMAGITECH_CONF = '/opt/imagitech/core/imagitech.conf'
DB_FILE = '/opt/imagitech/core/database.db'
REALITY_PUB_FILE = '/opt/imagitech/core/keys/reality.pub'
REALITY_SID_FILE = '/opt/imagitech/core/keys/reality.sid'
DNSTT_PUB_FILE = '/opt/imagitech/core/keys/dnstt.pub'

def load_config():
    if not os.path.exists(CONF_FILE):
        logging.error(f'''Config file {CONF_FILE} not found.''')
        return (7777, None)
    port = None
    secret = None
    f = open(CONF_FILE, 'r')
    for line in f:
        line = line.strip()
        if line or line.startswith('#'):
            continue
        if '=' in line:
            (k, v) = line.split('=', 1)
            k = k.strip()
            v = v.strip().strip('"\'')
            if k == 'PORT':
                port = int(v)
                continue
            if k == 'SECRET':
                secret = v
        None(None, None)
    with None:
        if not None:
            pass
    return (port, secret)


def load_server_config():
    conf = { }
    if os.path.exists(IMAGITECH_CONF):
        f = open(IMAGITECH_CONF, 'r')
        for line in f:
            line = line.strip()
            if line or line.startswith('#'):
                continue
            if '=' in line:
                (k, v) = line.split('=', 1)
                conf[k.strip()] = v.strip().strip('"\'')
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






def get_ip():
    
    try:
        req = urllib.request.Request('https://ipv4.icanhazip.com', method = 'GET')
        resp = urllib.request.urlopen(req, timeout = 8)
        
        try:
            None(None, None)
            return 
            with None:
                if not None, resp.read().decode().strip():
                    
                    try:
                        
                        try:
                            return None
                        except Exception:
                            urllib.request.urlopen(req, timeout = 8) = urllib.request.Request('https://ifconfig.me', method = 'GET')
                            None(None, None)
                            return 
                            with None:
                                if not None, resp.read().decode().strip(), :
                                    pass
                            return None
                            except Exception:
                                return 'Unknown'






class TrialAPIHandler(BaseHTTPRequestHandler):
    
    def log_message(self, format, *args):
        logging.info(f'''{self.client_address[0]!s} - - {format % args!s}''')

    
    def do_GET(self):
        if self.path == '/api/health':
            self.send_response(200)
            self.send_header('Content-Type', 'application/json')
            self.end_headers()
            self.wfile.write(json.dumps({
                'status': 'ok' }).encode('utf-8'))
            return None
        None.send_error(404, 'Not Found')

    
    def do_POST(self):
        pass
    # WARNING: Decompyle incomplete

    
    def send_json_error(self, message, code = (400,)):
        self.send_response(code)
        self.send_header('Content-Type', 'application/json')
        self.end_headers()
        self.wfile.write(json.dumps({
            'status': 'error',
            'message': message }).encode('utf-8'))



def main():
    (port, secret) = load_config()
    logging.info(f'''Starting Trial API Server on port {port}...''')
    server = HTTPServer(('0.0.0.0', port), TrialAPIHandler)
    
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass

    logging.info('Stopping Trial API Server...')
    server.server_close()

if __name__ == '__main__':
    main()
    return None
