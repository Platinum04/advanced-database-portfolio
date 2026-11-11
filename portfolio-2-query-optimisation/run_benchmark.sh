#!/usr/bin/env bash
# SpatialHub - Portfolio 2 benchmark runner
# Usage: ./run_benchmark.sh            (uses PG* env vars, database spatialhub)
# Runs the workload before and after indexing and saves the plans in results/.
set -euo pipefail
DB=${DB:-spatialhub}
PSQL="psql -X -d $DB"
mkdir -p results

echo "Dropping Portfolio 2 indexes (clean baseline)..."
$PSQL -q -c "DROP INDEX IF EXISTS idx_anchor_location_gist, idx_session_user_started,
             idx_interaction_time_brin, idx_interaction_anchor;"

echo "Run 1: BEFORE indexes (first pass warms the cache, second pass is recorded)"
$PSQL -f 02_queries.sql > /dev/null
$PSQL -f 02_queries.sql > results/before_indexes.txt

echo "Creating indexes..."
$PSQL -f 03_create_indexes.sql > results/index_sizes.txt

echo "Run 2: AFTER indexes"
$PSQL -f 02_queries.sql > /dev/null
$PSQL -f 02_queries.sql > results/after_indexes.txt

echo "Materialised view test..."
$PSQL -f 04_materialized_view.sql > results/materialized_view.txt

echo "Summary of execution times:"
paste <(grep -E "^Q[0-9]|Execution Time" results/before_indexes.txt) \
      <(grep -E "^Q[0-9]|Execution Time" results/after_indexes.txt | sed 's/^/   AFTER -> /')
