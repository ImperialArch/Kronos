CREATE TABLE IF NOT EXISTS implants (
    id TEXT PRIMARY KEY,
    hostname TEXT NOT NULL,
    username TEXT NOT NULL,
    os_info TEXT NOT NULL,
    first_seen INTEGER NOT NULL,
    last_seen INTEGER NOT NULL
);

CREATE TABLE IF NOT EXISTS tasks (
    task_id TEXT PRIMARY KEY,
    target_implant_id TEXT NOT NULL,
    command TEXT NOT NULL,
    args TEXT NOT NULL,
    created_at INTEGER NOT NULL,
    completed_at INTEGER,
    FOREIGN KEY (target_implant_id) REFERENCES implants(id)
);

CREATE TABLE IF NOT EXISTS results (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    task_id TEXT NOT NULL,
    output TEXT NOT NULL,
    received_at INTEGER NOT NULL
);