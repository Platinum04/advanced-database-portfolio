-- =====================================================================
-- SpatialHub - Portfolio 2: Query Processing and Optimisation
-- File: 01_generate_data.sql
-- Adds a large synthetic data set on top of the Portfolio 1 database so
-- that query plans and index effects become measurable.
--   ~20k users, 2k venues, 5k assets, 3k experiences,
--   200k spatial anchors, 200k AR sessions, 1M anchor interactions
-- Run: psql -d spatialhub -f 01_generate_data.sql      (takes ~1 minute)
-- =====================================================================
SELECT setseed(0.8103);     -- repeatable random data

-- Users (25% creators)
INSERT INTO app_user (username, email, full_name, role)
SELECT 'user' || g, 'user' || g || '@spatialhub.test', 'Test User ' || g,
       CASE WHEN g % 4 = 0 THEN 'creator' ELSE 'visitor' END
FROM generate_series(1, 20000) g;

-- Venues spread around each city centre
-- city 1 Lagos (3.38, 6.50), 2 Abuja (7.49, 9.06), 3 London (-0.12, 51.50)
INSERT INTO venue (city_id, name, venue_type, address, location)
SELECT c, 'Venue ' || g, (ARRAY['museum','park','campus','mall','heritage_site','street'])[1 + g % 6],
       'Generated address ' || g,
       ST_SetSRID(ST_MakePoint(
           (ARRAY[3.38, 7.49, -0.12])[c] + (random() - 0.5) * 0.30,
           (ARRAY[6.50, 9.06, 51.50])[c] + (random() - 0.5) * 0.30), 4326)::geography
FROM generate_series(1, 2000) g, LATERAL (SELECT 1 + (g % 3) AS c) x;

-- 3D assets and experiences owned by creators
INSERT INTO asset_3d (creator_id, title, file_format, file_url, file_size_bytes, polygon_count)
SELECT (SELECT user_id FROM app_user WHERE role = 'creator' ORDER BY user_id OFFSET (g % 5000) LIMIT 1),
       'Asset ' || g, (ARRAY['glb','gltf','usdz'])[1 + g % 3],
       'https://cdn.spatialhub.test/gen/asset-' || g || '.glb',
       (500000 + random() * 20000000)::bigint, (1000 + random() * 200000)::int
FROM generate_series(1, 5000) g;

INSERT INTO ar_experience (creator_id, title, description, status)
SELECT (SELECT user_id FROM app_user WHERE role = 'creator' ORDER BY user_id OFFSET (g % 5000) LIMIT 1),
       'Experience ' || g, 'Generated experience ' || g,
       (ARRAY['published','published','published','draft','archived'])[1 + g % 5]
FROM generate_series(1, 3000) g;

-- 200k spatial anchors, clustered around the three cities
INSERT INTO spatial_anchor (experience_id, asset_id, venue_id, location, altitude_m, heading_deg, scale, activation_radius_m)
SELECT 1 + (random() * 3002)::int,
       1 + (random() * 5004)::int,
       NULL,
       ST_SetSRID(ST_MakePoint(
           (ARRAY[3.38, 7.49, -0.12])[c] + (random() - 0.5) * 0.30,
           (ARRAY[6.50, 9.06, 51.50])[c] + (random() - 0.5) * 0.30), 4326)::geography,
       round((random() * 5)::numeric, 2), round((random() * 359)::numeric, 2),
       round((0.5 + random() * 2)::numeric, 3), (10 + (random() * 90)::int)
FROM generate_series(1, 200000) g, LATERAL (SELECT 1 + (g % 3) AS c) x;

-- 200k AR sessions over the last 12 months (users picked from real user_ids)
INSERT INTO ar_session (user_id, experience_id, device_type, started_at, ended_at)
SELECT u, 1 + (random() * 3002)::int,
       (ARRAY['webxr_browser','android_arcore','ios_arkit','headset'])[1 + (random() * 3)::int],
       t, t + (random() * interval '60 minutes')
FROM (SELECT ids.a[1 + floor(random() * cardinality(ids.a))::int] AS u,
             now() - random() * interval '365 days' AS t
      FROM generate_series(1, 200000),
           (SELECT array_agg(user_id) AS a FROM app_user) ids) s;

-- 1M anchor interactions, inserted in time order (as a real log would be)
INSERT INTO anchor_interaction (session_id, anchor_id, interaction_type, occurred_at)
SELECT 1 + (random() * 200004)::int,
       anc.a[1 + floor(random() * cardinality(anc.a))::int],
       (ARRAY['view','view','view','tap','collect','share'])[1 + (random() * 5)::int],
       now() - interval '365 days' + (g / 1000000.0) * interval '365 days'
FROM generate_series(1, 1000000) g,
     (SELECT array_agg(anchor_id) AS a FROM spatial_anchor) anc;   -- only real anchor ids

-- Fresh statistics for the query planner
ANALYZE;

SELECT 'spatial_anchor' AS t, count(*) FROM spatial_anchor
UNION ALL SELECT 'ar_session', count(*) FROM ar_session
UNION ALL SELECT 'anchor_interaction', count(*) FROM anchor_interaction;
