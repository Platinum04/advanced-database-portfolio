-- =====================================================================
-- SpatialHub - Portfolio 2: optimisation step
-- File: 03_create_indexes.sql
-- One index per query, each chosen for the access pattern of that query.
-- =====================================================================

-- Q1: spatial search. A B-tree cannot answer "within 300 m" on 2-D data;
-- a GiST (R-tree-like) index on the geography column can, and also
-- supports KNN ordering.
CREATE INDEX idx_anchor_location_gist ON spatial_anchor USING GIST (location);

-- Q2: equality on user_id + ORDER BY started_at DESC LIMIT 20.
-- A composite B-tree in that exact order lets PostgreSQL read the
-- 20 newest rows straight from the index with no sort.
CREATE INDEX idx_session_user_started ON ar_session (user_id, started_at DESC);

-- Q3: time-range scan on an append-only log. Rows arrive in time order,
-- so a BRIN index (stores min/max per block range) is tiny and still
-- lets the planner skip almost every block.
CREATE INDEX idx_interaction_time_brin ON anchor_interaction USING BRIN (occurred_at);

-- Q4: PostgreSQL does NOT index foreign keys automatically.
-- Index the FK column used for the lookup.
CREATE INDEX idx_interaction_anchor ON anchor_interaction (anchor_id);

ANALYZE spatial_anchor, ar_session, anchor_interaction;

-- Index size comparison (BRIN vs what a B-tree on the same column would cost)
CREATE INDEX idx_interaction_time_btree_tmp ON anchor_interaction (occurred_at);
\echo '=== Index sizes ==='
SELECT indexrelname AS index_name,
       pg_size_pretty(pg_relation_size(indexrelid)) AS size
FROM pg_stat_user_indexes
WHERE indexrelname IN ('idx_anchor_location_gist', 'idx_session_user_started',
                       'idx_interaction_time_brin', 'idx_interaction_time_btree_tmp',
                       'idx_interaction_anchor')
ORDER BY pg_relation_size(indexrelid) DESC;
DROP INDEX idx_interaction_time_btree_tmp;   -- only built for the size comparison
