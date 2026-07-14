# File: /opt/janabitech/lib/db.sh
# Purpose: Database interaction layer.

source /opt/janabitech/core/janabitech.conf
source /opt/janabitech/lib/system.sh

init_database() {
    log_event "INFO" "Initializing database schema at $DB_PATH"
    
    mkdir -p "$(dirname "$DB_PATH")"
    
    sqlite3 "$DB_PATH" <<EOF
CREATE TABLE IF NOT EXISTS users (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    username TEXT UNIQUE NOT NULL,
    uuid TEXT,
    protocols TEXT DEFAULT 'ssh,ws,socks',
    expiry_date TEXT NOT NULL,
    max_logins INTEGER DEFAULT 2,
    bandwidth_limit_mb INTEGER DEFAULT 0,
    bandwidth_used_mb INTEGER DEFAULT 0,
    status TEXT DEFAULT 'ACTIVE',
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP
);
EOF
    chmod 600 "$DB_PATH"

    # Migration: Safely add the precision byte-tracking column if it doesn't exist
    local col_exists=$(sqlite3 "$DB_PATH" "PRAGMA table_info(users);" | grep "data_usage")
    if [[ -z "$col_exists" ]]; then
        sqlite3 "$DB_PATH" "ALTER TABLE users ADD COLUMN data_usage BIGINT DEFAULT 0;"
    fi

    local limit_exists=$(sqlite3 "$DB_PATH" "PRAGMA table_info(users);" | grep "data_limit")
    if [[ -z "$limit_exists" ]]; then
        sqlite3 "$DB_PATH" "ALTER TABLE users ADD COLUMN data_limit BIGINT DEFAULT 0;"
    fi

    # Xray accounts table (vmess / vless / trojan over ws-nontls / ws-tls / grpc)
    sqlite3 "$DB_PATH" <<'XEOF'
CREATE TABLE IF NOT EXISTS xray_users (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    username TEXT UNIQUE NOT NULL,
    protocol TEXT NOT NULL,             -- vmess | vless | trojan
    uuid TEXT NOT NULL,                 -- used as uuid (vmess/vless) or password (trojan)
    expiry_date TEXT NOT NULL,          -- absolute expiry timestamp
    max_logins INTEGER DEFAULT 0,       -- reserved (0 = unlimited)
    data_limit BIGINT DEFAULT 0,        -- reserved quota in bytes (0 = unlimited)
    data_usage BIGINT DEFAULT 0,
    status TEXT DEFAULT 'ACTIVE',
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP
);
XEOF

    # Xray service metadata (single-row key/value store)
    sqlite3 "$DB_PATH" <<'MEOF'
CREATE TABLE IF NOT EXISTS xray_meta (
    k TEXT PRIMARY KEY,
    v TEXT
);
MEOF
}

db_query() {
    local query="$1"
    sqlite3 "$DB_PATH" "$query"
}
