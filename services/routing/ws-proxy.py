# ==============================================================================
# Reconstructed from bytecode (pycdc could not fully decompile Python 3.11
# async functions, so the function bodies below were manually reconstructed
# from the bytecode disassembly in `ws-proxy_bytecode_disassembly.txt`).
#
# What this service does:
#   This is a WebSocket-to-TCP proxy. It listens on 127.0.0.1:9880, accepts
#   WebSocket upgrade handshakes from clients (the kind of traffic that CDN
#   front-ends like Cloudflare can carry), and after the upgrade it pipes
#   the raw WebSocket data to a backend TCP service - here, Dropbear SSH
#   on 127.0.0.1:22. That lets SSH traffic pass through CDNs / WAFs that
#   would otherwise block non-HTTP ports.
# ==============================================================================

import asyncio
import logging
import sys
import re
import base64
import hashlib
from collections import defaultdict

logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')

# Backend the WebSocket payloads are forwarded to (Dropbear SSH).
BACKEND_HOST = '127.0.0.1'
BACKEND_PORT = 22


async def forward_stream(src_reader, dst_writer, direction):
    """
    Asynchronously forwards bytes from one stream to another.

    `direction` is just a label used for logging (e.g. 'Client -> Backend').
    """
    try:
        while True:
            data = await src_reader.read(8192)
            if not data:
                break
            dst_writer.write(data)
            await dst_writer.drain()
    except ConnectionResetError:
        pass
    except Exception as e:
        logging.debug(f"Stream error ({direction}): {e}")
    finally:
        if not dst_writer.is_closing():
            dst_writer.close()
            try:
                await dst_writer.wait_closed()
            except Exception:
                pass


async def handle_client(reader, writer):
    """
    Handle a single WebSocket client.

    1. Read the HTTP upgrade request.
    2. Parse the `Sec-WebSocket-Key` header.
    3. Compute `Sec-WebSocket-Accept` = base64(sha1(key + magic GUID)).
    4. Send back the 101 Switching Protocols response.
    5. Open a TCP connection to BACKEND_HOST:BACKEND_PORT.
    6. Pump bytes both ways until either side closes.
    """
    peer_ip = writer.get_extra_info('peername')[0] if writer.get_extra_info('peername') else 'Unknown'

    # 1. Read initial HTTP request with timeout.
    try:
        data = await asyncio.wait_for(reader.read(8192), timeout=15)
    except TimeoutError:
        logging.warning(f"Timeout reading initial payload from {peer_ip}")
        writer.close()
        return

    req_str = data.decode('utf-8', errors='ignore')

    # 2. Look for the WebSocket key header.
    match = re.search(r'Sec-WebSocket-Key:\s*([^\r\n]+)', req_str, re.IGNORECASE)
    if match:
        # 3. Compute the accept value per RFC 6455.
        key = match.group(1).strip()
        magic = '258EAFA5-E914-47DA-95CA-C5AB0DC85B11'
        accept = base64.b64encode(hashlib.sha1((key + magic).encode()).digest()).decode()
        response = (
            'HTTP/1.1 101 Switching Protocols\r\n'
            'Upgrade: websocket\r\n'
            'Connection: Upgrade\r\n'
            f'Sec-WebSocket-Accept: {accept}\r\n\r\n'
        )
        writer.write(response.encode())
        await writer.drain()
    else:
        # Not a WebSocket upgrade - respond with a bare 101 and let it fail naturally.
        writer.write(b'HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\n\r\n')
        await writer.drain()

    # 5. Open backend TCP connection (Dropbear on 127.0.0.1:22).
    try:
        backend_reader, backend_writer = await asyncio.open_connection(BACKEND_HOST, BACKEND_PORT)
    except Exception as e:
        logging.error(f"Could not connect to backend {BACKEND_HOST}:{BACKEND_PORT}: {e}")
        writer.close()
        return

    # 6. Pump bytes both ways.
    try:
        await asyncio.gather(
            forward_stream(reader,       backend_writer, 'Client -> Backend'),
            forward_stream(backend_reader, writer,       'Backend -> Client'),
        )
    except Exception as e:
        logging.error(f"Handler exception for {peer_ip}: {e}")
    finally:
        if not writer.is_closing():
            writer.close()
        if not backend_writer.is_closing():
            backend_writer.close()


async def main():
    """
    Entry point. Starts the asyncio TCP server bound to 127.0.0.1:9880.
    """
    server_9880 = await asyncio.start_server(handle_client, '127.0.0.1', 9880)
    logging.info('Async WS Multiplexer started on local port 9880')
    async with server_9880:
        await server_9880.serve_forever()


if __name__ == '__main__':
    try:
        asyncio.run(main())
    except KeyboardInterrupt:
        logging.info('Shutting down proxy.')
