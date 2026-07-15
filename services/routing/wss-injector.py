# === Decompiled from wss-injector.pyc ===
# Source: PyInstaller binary, Python 3.11 bytecode
# Decompiled with pycdc (Decompyle++)
# NOTE: Some constructs may be imperfect due to bytecode decompiler limitations.
# ============================================================================

# Source Generated with Decompyle++
# File: wss-injector.pyc (Python 3.11)

import socket
import ssl
import threading
import logging
import re
import base64
import hashlib
from collections import defaultdict
LISTEN_HOST = '127.0.0.1'
LISTEN_PORT = 4430
SSH_HOST = '127.0.0.1'
SSH_PORT = 22
CERT_FILE = '/opt/imagitech/core/keys/haproxy.pem'
lock = threading.Lock()
logging.basicConfig(level = logging.INFO, format = '%(asctime)s - %(levelname)s - %(message)s')

def forward(src, dst, label = ('',)):
    '''Forward bytes from src socket to dst socket.'''
    
    try:
        data = src.recv(8192)
        if not data:
            pass
        else:
            dst.sendall(data)
        
        try:
            pass
        except (ConnectionResetError, BrokenPipeError, OSError):
            
            try:
                pass
            except Exception:
                e = None
                logging.debug(f'''Forward error ({label}): {e}''')
                
                try:
                    e = None
                    del e
                e = None
                del e
                try:
                    
                    try:
                        src.close()
                    except Exception:
                        pass

                    
                    try:
                        dst.close()
                        return None
                    except Exception:
                        return None
                        src.close()
                    except Exception:
                        pass

                    dst.close()






def handle_client(client_sock, addr):
    '''Handle a single WSS injection client.'''
    peer_ip = addr[0]
    ssh_sock = None
    tls_sock = None
    
    try:
        client_sock.settimeout(10)
        data = client_sock.recv(8192)
        if not data:
            for s in (client_sock, tls_sock, ssh_sock):
                if s:
                    s.close()
                    continue
                    except Exception:
                        continue
                return None
                
                try:
                    req_str = data.decode('utf-8', errors = 'ignore')
                    logging.debug(f'''WSS Inject from {peer_ip}: {repr(req_str[:120])}''')
                    match = re.search('Sec-WebSocket-Key:\\s*([^\\r\\n]+)', req_str, re.IGNORECASE)
                    if match:
                        key = match.group(1).strip()
                        magic = '258EAFA5-E914-47DA-95CA-C5AB0DC85B11'
                        accept = base64.b64encode(hashlib.sha1((key + magic).encode('utf-8')).digest()).decode('utf-8')
                        response = f'''HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Accept: {accept}\r\n\r\n'''
                    else:
                        response = 'HTTP/1.1 200 Connection Established\r\n\r\n'
                    client_sock.sendall(response.encode('utf-8'))
                    client_sock.settimeout(None)
                    ctx = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
                    ctx.load_cert_chain(CERT_FILE)
                    ctx.minimum_version = ssl.TLSVersion.TLSv1_2
                    tls_sock = ctx.wrap_socket(client_sock, server_side = True)
                    client_sock = None
                    ssh_sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
                    ssh_sock.settimeout(5)
                    ssh_sock.connect((SSH_HOST, SSH_PORT))
                    ssh_sock.settimeout(None)
                    t1 = threading.Thread(target = forward, args = (tls_sock, ssh_sock, 'client→ssh'), daemon = True)
                    t2 = threading.Thread(target = forward, args = (ssh_sock, tls_sock, 'ssh→client'), daemon = True)
                    t1.start()
                    t2.start()
                    t1.join()
                    t2.join()
                    
                    try:
                        pass
                    except ssl.SSLError:
                        e = None
                        logging.debug(f'''TLS negotiation failed from {peer_ip}: {e}''')
                        
                        try:
                            e = None
                            del e
                        e = None
                        del e
                        except socket.timeout:
                            logging.debug(f'''Timeout from {peer_ip}''')
                            
                            try:
                                pass
                            except Exception:
                                e = None
                                logging.debug(f'''Handler error from {peer_ip}: {e}''')
                                
                                try:
                                    e = None
                                    del e
                                e = None
                                del e
                                try:
                                    for s in (client_sock, tls_sock, ssh_sock):
                                        if s:
                                            s.close()
                                            continue
                                            except Exception:
                                                continue
                                        return None
                                        for s in (client_sock, tls_sock, ssh_sock):
                                            if s:
                                                s.close()
                                                continue
                                                except Exception:
                                                    continue








def main():
    server = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    server.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    server.bind((LISTEN_HOST, LISTEN_PORT))
    server.listen(256)
    logging.info(f'''WSS Injector listening on {LISTEN_HOST}:{LISTEN_PORT}''')
    
    try:
        (client_sock, addr) = server.accept()
        t = threading.Thread(target = handle_client, args = (client_sock, addr), daemon = True)
        t.start()
    except Exception:
        e = None
        logging.error(f'''Accept error: {e}''')
        e = None
        del e
    except:
        e = None
        del e

    continue

if __name__ == '__main__':
    
    try:
        main()
        return None
    except KeyboardInterrupt:
        logging.info('Shutting down WSS Injector.')
        return None
        return None

