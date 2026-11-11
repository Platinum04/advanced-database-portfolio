-- =====================================================================
-- SpatialHub - Portfolio 2: the four workload queries under test
-- File: 02_queries.sql
-- Run once BEFORE 03_create_indexes.sql and once AFTER, then compare.
-- Each query is shown with EXPLAIN (ANALYZE, BUFFERS) so we see the
-- chosen plan, the real execution time and the pages read.
-- =====================================================================
\timing off
-- JIT compilation is switched off for a fair comparison: on the un-indexed
-- plans the very high cost estimates trigger JIT, and its compile time
-- (hundreds of ms) would hide the real scan cost. See README section 4.
SET jit = off;

\echo '=================================================================='
\echo 'Q1. AR client: anchors within 300 m of a user in Yaba, Lagos (nearest first)'
\echo '=================================================================='
EXPLAIN (ANALYZE, BUFFERS, COSTS)
SELECT anchor_id, experience_id, asset_id,
       ST_Distance(location, ST_SetSRID(ST_MakePoint(3.3792, 6.5095), 4326)::geography) AS dist_m
FROM spatial_anchor
WHERE ST_DWithin(location, ST_SetSRID(ST_MakePoint(3.3792, 6.5095), 4326)::geography, 300)
ORDER BY dist_m
LIMIT 20;

\echo '=================================================================='
\echo 'Q2. Profile page: a user''s 20 most recent AR sessions'
\echo '=================================================================='
EXPLAIN (ANALYZE, BUFFERS, COSTS)
SELECT s.session_id, s.device_type, s.started_at, x.title
FROM ar_session s
JOIN ar_experience x ON x.experience_id = s.experience_id
WHERE s.user_id = (SELECT user_id FROM app_user WHERE username = 'user5000')
ORDER BY s.started_at DESC
LIMIT 20;

\echo '=================================================================='
\echo 'Q3. Analytics: interactions by type for one day, 30 days ago'
\echo '=================================================================='
EXPLAIN (ANALYZE, BUFFERS, COSTS)
SELECT interaction_type, count(*)
FROM anchor_interaction
WHERE occurred_at >= date_trunc('day', now() - interval '30 days')
  AND occurred_at <  date_trunc('day', now() - interval '29 days')
GROUP BY interaction_type
ORDER BY count(*) DESC;

\echo '=================================================================='
\echo 'Q4. Creator dashboard: engagement for one anchor (FK lookup)'
\echo '=================================================================='
EXPLAIN (ANALYZE, BUFFERS, COSTS)
SELECT ai.interaction_type, count(*) AS total, max(ai.occurred_at) AS last_seen
FROM anchor_interaction ai
WHERE ai.anchor_id = 1234
GROUP BY ai.interaction_type;
