<p align="center">  
<img src="https://user-images.githubusercontent.com/76937659/153705486-44e6c1b2-74fa-4d44-be1c-36c8fdb83331.gif"/>  
<P>
<p align="center"><img src="https://readme-typing-svg.herokuapp.com?color=blue&center=true&vCenter=true&lines=🚀𝗩𝗜𝗥𝗧𝗔𝗥𝗜𝗫-𝗧𝗘𝗖𝗛[𝗔𝘂𝘁𝗼𝗩𝗣𝗡𝗦𝗰𝗿𝗶𝗽𝘁]🚀"
</p>
<p align="center">  
<img src="https://user-images.githubusercontent.com/76937659/153705486-44e6c1b2-74fa-4d44-be1c-36c8fdb83331.gif"/>  

---

Janabitech Provisions a multi-protocol proxy environment complete with real-time tracking, aggressive bandwidth enforcement, multi-login prevention, anti-DDoS features, and a dynamic CLI dashboard. 

Built exclusively for **Ubuntu (20.04, 22.04, 24.04)** and **Debian (11, 12)** LTS to guarantee 100% stability.

## 🌟 Elite Features

### 🔌 Next-Gen Tunneling & Routing
- **OpenSSH & Dropbear:** Multi-port SSH tunneling (Ports 22, 109, 143, 8880).
- **Stunnel4 (SSL/TLS):** Encrypted TLS bridging and SNI routing (Ports 443, 447, 777).
- **Asynchronous WebSocket Proxy:** High-performance async WS multiplexer supporting HTTP Injection and ISP Bypassing on ports 80, 443, and 8880.
- **UDP Custom:** High-performance direct UDP tunneling for intensive gaming/voice packets (Ports 1-65535).
- **DNSTT (SlowDNS):** Advanced payload encapsulation through DNS queries for deeply restricted networks (Ports 53, 5300).
- **Dante SOCKS5 Proxy:** Standalone, high-speed SOCKS5 proxy (Port 1080).
- **Xray-core Manager:** Full vmess / vless / trojan manager over ws (no TLS), ws (TLS) and gRPC (TLS) – **shares the same domain + Let's Encrypt SSL certificate** provisioned by the SSH stack.

### 🛡️ Security & Active Monitoring
- **Python-Powered Active Monitor:** A resilient Python background daemon (`daemon.py`) tracks active logins in real-time, strictly enforcing maximum concurrent logins.
- **Bandwidth Limits & Accounting:** Granular byte tracking using low-level `/proc/io` data, securely logged to an SQLite3 database. Enforces strict GB limits on accounts.
- **The OS Reaper:** Automatically eradicates Linux accounts and instantly drops connections the exact second a user's subscription expires.
- **Military-Grade Backups:** Uses AES-256-CBC with PBKDF2 to encrypt your database, TLS certificates, and DNS keys. Seamless SFTP disaster recovery.
- **TCP KeepAlives:** Enforced kernel-level heartbeats prevent Cloudflare and Azure from silently dropping idle connections.

## 📦 Zero-Touch Installation



To deploy the platform on a fresh Ubuntu or Debian server, run the following command as `root`:

```bash
apt update && apt upgrade -y && 
```

```bash
bash <(curl -sS -L https://raw.githubusercontent.com/virtarix-tech/autoscriptssh/main/install.sh)
```

<p align="center">

<h2 align="center">
Auto Script Install XRAY/SSH Websocket Service
Mod By Virtarix-Tech Dev
<p align="center">
<img src="https://img.shields.io/badge/Release-v2.8.0-lime.svg">
<img src="https://img.shields.io/badge/Systemd-Required-cyan.svg">
</p> 
<h2 align="center"> Supported Linux Distribution</h2>
<p align="center"><img src="https://d33wubrfki0l68.cloudfront.net/5911c43be3b1da526ed609e9c55783d9d0f6b066/9858b/assets/img/debian-ubuntu-hover.png"width="400"></p> 
<p align="center">
<img src="https://img.shields.io/static/v1?style=for-the-badge&logo=debian&label=Debian%209&message=Stretch&color=red"> 
<img src="https://img.shields.io/static/v1?style=for-the-badge&logo=debian&label=Debian%2010&message=Buster&color=cyan">  
<img src="https://img.shields.io/static/v1?style=for-the-badge&logo=debian&label=Debian%2011&message=bullseye&color=lime"> 
  
<p align="center">
<img src="https://img.shields.io/static/v1?style=for-the-badge&logo=ubuntu&label=Ubuntu%2020.04&message=Focal&color=aqua">
<img src="https://img.shields.io/static/v1?style=for-the-badge&logo=ubuntu&label=Ubuntu%2022.04&message=Jammy&color=lime">
<img src="https://img.shields.io/static/v1?style=for-the-badge&logo=ubuntu&label=Ubuntu%2024.04&message=Noble&color=red">
<p> 



<h2 align="center"><strong> 𝗡𝗘𝗧𝗪𝗢𝗥𝗞 𝗣𝗥𝗢𝗧𝗢𝗖𝗢𝗟𝗦 </h2>

<h2 align="center">

![Hits](https://img.shields.io/badge/SSH-Websocket-8020f3?style=for-the-badge&logo=Cloudflare&logoColor=aqua&edge_flat=false)
![Hits](https://img.shields.io/badge/XRAY-Vmess-f34b20?style=for-the-badge&logo=Cloudflare&logoColor=lime&edge_flat=false)
![Hits](https://img.shields.io/badge/XRAY-VLess-f34b20?style=for-the-badge&logo=Cloudflare&logoColor=aqua&edge_flat=false)
![Hits](https://img.shields.io/badge/XRAY-Trojan-f34b20?style=for-the-badge&logo=Cloudflare&logoColor=lime&edge_flat=false)
</h2>

PLEASE MAKE SURE YOUR DOMAIN SETTINGS IN YOUR CLOUDFLARE AS BELOW (SSL/TLS SETTINGS)<br>
<br>
1. Your SSL/TLS encryption mode is Full
2. Enable SSL/TLS Recommender ✅
3. Edge Certificates > Disable Always Use HTTPS (off)


## 🛠️ Operations & Usage

Once the installation completes, manage your server securely:

1. **Interactive Dashboard:** Type `menu` to launch the beautiful and comprehensive TUI panel for managing users, monitoring connections, and modifying system settings.

<p align="center">
   
</p>
   
2. **Headless Internal API:** Type `janabitech` followed by an API command to script automations natively.
   - Example: `janabitech user add test 12345 30 2 10` (Create user 'test', pass '12345', 30 days, 2 devices, 10GB Limit)
   - Example: `janabitech service restart all`
   - Example: `janabitech xray add alice vmess 30 days` (Create vmess xray user 'alice' for 30 days)
   - Example: `janabitech xray trial bob vless 60` (Create 60-minute vless trial)
   - Example: `janabitech xray renew alice 7 days` (Add 7 days to alice)
   - Example: `janabitech xray details alice` (Print vmess://, vless://, trojan:// client links)

## 🛰️ Xray Manager

The Xray-core manager is deployed automatically as Phase 5 of the installer. It listens on 9
inbounds (3 protocols × 3 transports) and reuses your existing `${PRIMARY_DOMAIN}` and the
Let's Encrypt certificate at `/opt/janabitech/core/keys/fullchain.cer`.

| Protocol | Transport        | Port | TLS |
|----------|------------------|------|-----|
| vmess    | ws (no TLS)      | 8080 | no  |
| vmess    | ws (TLS)         | 2053 | yes |
| vmess    | gRPC (TLS)       | 2087 | yes |
| vless    | ws (no TLS)      | 2052 | no  |
| vless    | ws (TLS)         | 2083 | yes |
| vless    | gRPC (TLS)       | 8443 | yes |
| trojan   | ws (no TLS)      | 2082 | no  |
| trojan   | ws (TLS)         | 2096 | yes |
| trojan   | gRPC (TLS)       | 10008| yes |

Each user is tied to **one** protocol and may use **all three** transports of that protocol.
Expiry can be set in **minutes**, **hours**, or **days**. A 5-minute cron job automatically
marks expired accounts and reloads the config so credentials stop working immediately.

## 📂 System Architecture

The script strictly adheres to modern Linux engineering principles. It avoids polluting your global namespace; all configurations, python daemons, and databases are strictly sandboxed.

- `/opt/janabitech/core/`: SQLite3 Databases, SSL certificates, DNSTT public/private keys.
- `/opt/janabitech/services/`: Python engine (`daemon.py`) and Async Routing Proxy (`ws-proxy.py`).
- `/opt/janabitech/lib/`: Core bash logic modules (including `xray.sh` for Xray management).
- `/opt/janabitech/bin/xray`: Xray-core binary (downloaded automatically).
- `/opt/janabitech/xray/`: Xray `config.json` and geo data.
- `/opt/janabitech/backups/`: Location for encrypted snapshots and disaster recovery via SFTP.

## ⚠️ Disclaimer
This software is intended for educational purposes, privacy enhancement, and legal network administration. Abuse of this service for spam, DDoS, or illegal operations is strictly prohibited. The developer takes no responsibility for misuse.


<div align="left">
  <p>
    <b>𝗦𝘂𝗯𝘀𝗰𝗿𝗶𝗯𝗲</b> → <a href="https://t.me/inet_adminbot">@inet_adminbot</a><br>
    <b>𝗖𝗵𝗮𝗻𝗻𝗲𝗹</b> → <a href="https://t.me/wifi_BypassTechy">@wifi_BypassTechy</a><br>
    <b>𝗗𝗲𝘃𝗲𝗹𝗼𝗽𝗲𝗿</b> → <a href="t.me/nkihoy">Virtarix Dev</a>
  </p>
</div>
