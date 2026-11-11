-- =====================================================================
-- SpatialHub - Portfolio 2: caching with a materialised view
-- File: 04_materialized_view.sql
-- The "Trending anchors" leaderboard is read on every app launch but only
-- needs to be fresh every few minutes. Pre-computing it trades a little
-- staleness for a large speed gain.
-- =====================================================================
\timing on
SET jit = off;   -- same reason as in 02_queries.sql

\echo '=== Live aggregate (what the app would run every time) ==='
EXPLAIN (ANALYZE, BUFFERS)
SELECT ai.anchor_id, c.name AS city_hint, count(*) AS interactions_30d
FROM anchor_interaction ai
JOIN spatial_anchor a ON a.anchor_id = ai.anchor_id
CROSS JOIN LATERAL (SELECT CASE WHEN ST_Y(a.location::geometry) > 40 THEN 'London'
                                WHEN ST_X(a.location::geometry) > 6  THEN 'Abuja'
                                ELSE 'Lagos' END AS name) c
WHERE ai.occurred_at >= now() - interval '30 days'
GROUP BY ai.anchor_id, c.name
ORDER BY interactions_30d DESC
LIMIT 10;

DROP MATERIALIZED VIEW IF EXISTS mv_trending_anchors;
CREATE MATERIALIZED VIEW mv_trending_anchors AS
SELECT ai.anchor_id,
       CASE WHEN ST_Y(a.location::geometry) > 40 THEN 'London'
            WHEN ST_X(a.location::geometry) > 6  THEN 'Abuja'
            ELSE 'Lagos' END AS city_hint,
       count(*) AS interactions_30d
FROM anchor_interaction ai
JOIN spatial_anchor a ON a.anchor_id = ai.anchor_id
WHERE ai.occurred_at >= now() - interval '30 days'
GROUP BY 1, 2;

-- Unique index: needed for REFRESH ... CONCURRENTLY (no read blocking)
CREATE UNIQUE INDEX ON mv_trending_anchors (anchor_id);
CREATE INDEX ON mv_trending_anchors (interactions_30d DESC);

\echo '=== Reading the materialised view ==='
EXPLAIN (ANALYZE, BUFFERS)
SELECT * FROM mv_trending_anchors ORDER BY interactions_30d DESC LIMIT 10;

SELECT * FROM mv_trending_anchors ORDER BY interactions_30d DESC, anchor_id LIMIT 10;

\echo '=== Refresh without blocking readers (e.g. scheduled every 5 minutes) ==='
REFRESH MATERIALIZED VIEW CONCURRENTLY mv_trending_anchors;
