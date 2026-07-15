# File: /opt/imagitech/lib/db.sh
# Purpose: Database interaction layer.

source /opt/imagitech/core/imagitech.conf 2>/dev/null || true
:

init_database() {
    log_event "INFO" "Initializing database schema at $DB_PATH"
    
    mkdir -p "$(dirname "$DB_PATH")"
    
    sqlite3 "$DB_PATH" <<EOF
CREATE TABLE IF NOT EXISTS users (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    username TEXT UNIQUE NOT NULL,
    uuid TEXT,
    protocols TEXT DEFAULT 'ssh,ws,socks',
    account_type TEXT DEFAULT 'SSH',
    expiry_date TEXT NOT NULL,
    max_logins INTEGER DEFAULT 2,
    bandwidth_limit_mb INTEGER DEFAULT 0,
    bandwidth_used_mb INTEGER DEFAULT 0,
    status TEXT DEFAULT 'ACTIVE',
    is_trial INTEGER DEFAULT 0,
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

    local trial_exists=$(sqlite3 "$DB_PATH" "PRAGMA table_info(users);" | grep "is_trial")
    if [[ -z "$trial_exists" ]]; then
        sqlite3 "$DB_PATH" "ALTER TABLE users ADD COLUMN is_trial INTEGER DEFAULT 0;"
    fi
}

sqlite3() {
    command sqlite3 -cmd ".timeout 5000" "$@"
}
export -f sqlite3

db_query() {
    local query="$1"
    sqlite3 "$DB_PATH" "$query"
}
