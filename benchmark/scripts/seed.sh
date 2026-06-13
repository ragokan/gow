#!/usr/bin/env bash
# Reset the users table to a deterministic, identical starting state so both
# apps are benchmarked against the same data.
set -euo pipefail
ROWS="${1:-10000}"
export PGPASSWORD=benchpass
psql -h 127.0.0.1 -U bench -d benchdb -v ON_ERROR_STOP=1 -q <<SQL
TRUNCATE users RESTART IDENTITY;
INSERT INTO users (name, email, age)
SELECT 'user' || g,
       'user' || g || '@example.com',
       (g % 80) + 18
FROM generate_series(1, ${ROWS}) g;
SQL
echo "seeded ${ROWS} rows"
