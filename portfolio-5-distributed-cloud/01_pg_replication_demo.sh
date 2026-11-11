#!/usr/bin/env bash
# =====================================================================
# SpatialHub - Portfolio 5A: PostgreSQL streaming replication + failover
# File: 01_pg_replication_demo.sh
# Builds a PRIMARY (port 5433) and a hot-standby REPLICA (port 5434) on one
# machine, then demonstrates: replication of writes, read-only replica,
# replication lag monitoring, synchronous commit, and failover by promotion.
# Needs: PostgreSQL 16 server binaries (Linux / macOS / WSL). Run as a
# non-root user that can run initdb, e.g.:  bash 01_pg_replication_demo.sh
# =====================================================================
set -euo pipefail
PGBIN=${PGBIN:-/usr/lib/postgresql/16/bin}
BASE=${BASE:-/tmp/spatialhub-repl}
SOCK=$BASE/sock
P="psql -X -h $SOCK -U postgres -v ON_ERROR_STOP=1"

step() { echo; echo "=== $* ==="; }

# ---- clean start ----
$PGBIN/pg_ctl -D $BASE/primary stop -m fast >/dev/null 2>&1 || true
$PGBIN/pg_ctl -D $BASE/replica stop -m fast >/dev/null 2>&1 || true
rm -rf $BASE && mkdir -p $SOCK

step "1. Initialise PRIMARY (Lagos data centre, port 5433)"
$PGBIN/initdb -D $BASE/primary -U postgres -A trust >/dev/null
cat >> $BASE/primary/postgresql.conf <<EOF
port = 5433
unix_socket_directories = '$SOCK'
listen_addresses = ''
wal_level = replica
max_wal_senders = 5
hot_standby = on
EOF
echo "local replication all trust" >> $BASE/primary/pg_hba.conf
$PGBIN/pg_ctl -D $BASE/primary -l $BASE/primary.log start >/dev/null
$P -p 5433 -c "CREATE DATABASE spatialhub;"
$P -p 5433 -d spatialhub -q <<'SQL'
CREATE TABLE ar_event (event_id int PRIMARY KEY, title text, capacity int, tickets_sold int);
INSERT INTO ar_event VALUES (1, 'Heritage Night AR Walk', 50, 3), (3, 'Abuja Night Lights Launch', 2, 2);
SQL
echo "primary running, sample table created"

step "2. Clone REPLICA with pg_basebackup (London data centre, port 5434)"
$PGBIN/pg_basebackup -h $SOCK -p 5433 -U postgres -D $BASE/replica -R -X stream -C -S london_slot
sed -i.bak "s/^port = 5433/port = 5434/" $BASE/replica/postgresql.conf
echo "primary_slot_name = 'london_slot'" >> $BASE/replica/postgresql.conf
$PGBIN/pg_ctl -D $BASE/replica -l $BASE/replica.log start >/dev/null
sleep 2
$P -p 5434 -d spatialhub -c "SELECT pg_is_in_recovery() AS replica_in_recovery_mode;"

step "3. Replication status seen from the PRIMARY"
$P -p 5433 -c "SELECT application_name, state, sync_state, sent_lsn, replay_lsn,
                      pg_wal_lsn_diff(sent_lsn, replay_lsn) AS lag_bytes
               FROM pg_stat_replication;"

step "4. Write on PRIMARY -> read on REPLICA"
$P -p 5433 -d spatialhub -c "INSERT INTO ar_event VALUES (10, 'Lekki AR Art Fair', 300, 0);"
sleep 1
$P -p 5434 -d spatialhub -c "SELECT * FROM ar_event ORDER BY event_id;"

step "5. REPLICA is read-only (write attempt must fail)"
$P -p 5434 -d spatialhub -c "UPDATE ar_event SET tickets_sold = 1 WHERE event_id = 10;" || echo ">> rejected as expected"

step "6. Synchronous replication: COMMIT waits for the replica"
$P -p 5433 -c "ALTER SYSTEM SET synchronous_standby_names = 'walreceiver';" -c "SELECT pg_reload_conf();" >/dev/null
sleep 1
$P -p 5433 -c "SELECT application_name, sync_state FROM pg_stat_replication;"
$P -p 5433 -d spatialhub -c "\timing on" -c "UPDATE ar_event SET tickets_sold = tickets_sold + 1 WHERE event_id = 10;"
$P -p 5433 -c "ALTER SYSTEM RESET synchronous_standby_names;" -c "SELECT pg_reload_conf();" >/dev/null

step "7. FAILOVER: the primary crashes"
$PGBIN/pg_ctl -D $BASE/primary stop -m immediate
$P -p 5433 -c "SELECT 1;" 2>&1 | head -1 || true
echo ">> primary is down; replica still serves reads:"
$P -p 5434 -d spatialhub -c "SELECT event_id, title, tickets_sold FROM ar_event ORDER BY event_id;"

step "8. Promote the REPLICA to be the new primary"
$P -p 5434 -c "SELECT pg_promote(wait => true) AS promoted;"
$P -p 5434 -c "SELECT pg_is_in_recovery() AS still_replica;"
$P -p 5434 -d spatialhub -c "INSERT INTO ar_event VALUES (11, 'Post-failover event', 100, 0);" \
                         -c "SELECT event_id, title FROM ar_event ORDER BY event_id;"
echo; echo "Failover complete: writes are accepted on the former replica (port 5434)."

$PGBIN/pg_ctl -D $BASE/replica stop -m fast >/dev/null
