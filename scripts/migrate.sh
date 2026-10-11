#!/usr/bin/env bash
# Apply db/migrations/*.sql in order, once each, inside the CloudNativePG pod.
# Runs as the superuser over the local socket, but `SET ROLE cairn` so objects are owned by the app role.
# Usage: scripts/migrate.sh [--seed]   (--seed also loads SYNTHETIC demo data)
set -euo pipefail
cd "$(dirname "$0")/.."
POD="${DB_POD:-cairn-db-1}"
psql_in() { kubectl -n cairn exec -i "$POD" -c postgres -- psql -U postgres -d cairn -qtA -v ON_ERROR_STOP=1 "$@"; }

echo "SET ROLE cairn; CREATE TABLE IF NOT EXISTS schema_migrations (name text PRIMARY KEY, applied_at timestamptz NOT NULL DEFAULT now());" | psql_in
for f in db/migrations/*.sql; do
  name=$(basename "$f")
  done_already=$(echo "SELECT 1 FROM schema_migrations WHERE name = '$name';" | psql_in)
  if [ "$done_already" = "1" ]; then echo "skip  $name"; continue; fi
  { echo "SET ROLE cairn;"; cat "$f"; echo "INSERT INTO schema_migrations(name) VALUES ('$name');"; } | psql_in -1
  echo "apply $name"
done
if [ "${1:-}" = "--seed" ]; then
  { echo "SET ROLE cairn;"; cat db/seed/synthetic.sql; } | psql_in -1
  echo "seeded synthetic demo data"
fi
