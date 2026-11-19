#!/usr/bin/env bash
# Run against a disposable PostgreSQL using a private Unix socket.
set -euo pipefail

demo_dir=$(mktemp -d /tmp/cluster-kb-local.XXXXXX)
cleanup() {
    if [[ -s "$demo_dir/data/postmaster.pid" ]]; then
        pg_ctl -D "$demo_dir/data" -m fast -w stop >/dev/null
    fi
    rm -rf -- "$demo_dir"
}
trap cleanup EXIT
initdb -D "$demo_dir/data" -A trust -U kb --no-locale -E UTF8 >/dev/null
pg_ctl -D "$demo_dir/data" -l "$demo_dir/server.log" \
    -o "-k $demo_dir -c listen_addresses=''" -w start >/dev/null
createdb -h "$demo_dir" -U kb -p 5432 cluster_kb_demo
export DATABASE_URL="host=$demo_dir user=kb port=5432 dbname=cluster_kb_demo"
PSQL="psql -h $demo_dir -U kb -p 5432 -d cluster_kb_demo -v ON_ERROR_STOP=1 -q" \
    bash ../scripts/migrate.sh ../seminar02/migrations >&2
if [[ ${1:-demo} = test ]]; then
    KB_TEST_MUTATE_DEMO=1 "${PYTHON:-python3}" -m unittest discover -s kb -p 'test_*.py' -v
else
    "${PYTHON:-python3}" -m kb all --node a01n01 --at 2026-10-01T09:01:00Z --demo-profile
fi
