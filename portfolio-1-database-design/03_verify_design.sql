-- =====================================================================
-- SpatialHub - Portfolio 1 verification
-- File: 03_verify_design.sql   (run after 01 and 02)
-- Part A: queries that show the design answers real questions.
-- Part B: bad inserts that the constraints MUST reject (screenshot the errors).
-- Run in psql:  \i 03_verify_design.sql
-- =====================================================================

\echo '=== A1. Row count per table ==='
SELECT 'app_user' AS table_name, count(*) FROM app_user
UNION ALL SELECT 'city', count(*) FROM city
UNION ALL SELECT 'venue', count(*) FROM venue
UNION ALL SELECT 'asset_3d', count(*) FROM asset_3d
UNION ALL SELECT 'ar_experience', count(*) FROM ar_experience
UNION ALL SELECT 'spatial_anchor', count(*) FROM spatial_anchor
UNION ALL SELECT 'ar_event', count(*) FROM ar_event
UNION ALL SELECT 'ticket', count(*) FROM ticket
UNION ALL SELECT 'payment', count(*) FROM payment
UNION ALL SELECT 'ar_session', count(*) FROM ar_session
UNION ALL SELECT 'anchor_interaction', count(*) FROM anchor_interaction;

\echo '=== A2. Anchors within 1 km of a visitor standing at Freedom Park Lagos ==='
SELECT a.anchor_id, x.title AS experience, s.title AS asset,
       round(ST_Distance(a.location,
             ST_SetSRID(ST_MakePoint(3.3935, 6.4513), 4326)::geography)::numeric, 1) AS distance_m
FROM spatial_anchor a
JOIN ar_experience x ON x.experience_id = a.experience_id
JOIN asset_3d s      ON s.asset_id      = a.asset_id
WHERE ST_DWithin(a.location, ST_SetSRID(ST_MakePoint(3.3935, 6.4513), 4326)::geography, 1000)
ORDER BY distance_m;

\echo '=== A3. Experiences with their tags (many-to-many through experience_tag) ==='
SELECT x.title, string_agg(t.name, ', ' ORDER BY t.name) AS tags
FROM ar_experience x
JOIN experience_tag et ON et.experience_id = x.experience_id
JOIN tag t             ON t.tag_id         = et.tag_id
GROUP BY x.title ORDER BY x.title;

\echo '=== A4. Event seats left ==='
SELECT title, capacity, tickets_sold, capacity - tickets_sold AS seats_left
FROM ar_event ORDER BY event_id;

\echo '=== A5. Most engaged anchors ==='
SELECT ai.anchor_id, s.title AS asset, count(*) AS interactions
FROM anchor_interaction ai
JOIN spatial_anchor a ON a.anchor_id = ai.anchor_id
JOIN asset_3d s       ON s.asset_id  = a.asset_id
GROUP BY ai.anchor_id, s.title ORDER BY interactions DESC, ai.anchor_id;

-- ---------------------------------------------------------------------
-- Part B: constraint tests - each statement below SHOULD FAIL.
-- ON_ERROR_STOP is off so the script keeps going after each error.
-- ---------------------------------------------------------------------
\set ON_ERROR_STOP off

\echo '=== B1. Duplicate email (UNIQUE) - expect ERROR ==='
INSERT INTO app_user (username, email, full_name) VALUES ('ada2', 'ada@spatialhub.test', 'Copy Cat');

\echo '=== B2. Invalid role (CHECK) - expect ERROR ==='
INSERT INTO app_user (username, email, full_name, role) VALUES ('bad', 'bad@x.test', 'Bad Role', 'superuser');

\echo '=== B3. Anchor pointing to a non-existent asset (FOREIGN KEY) - expect ERROR ==='
INSERT INTO spatial_anchor (experience_id, asset_id, location)
VALUES (1, 999, ST_SetSRID(ST_MakePoint(3.39, 6.45), 4326)::geography);

\echo '=== B4. Heading of 400 degrees (CHECK) - expect ERROR ==='
INSERT INTO spatial_anchor (experience_id, asset_id, location, heading_deg)
VALUES (1, 1, ST_SetSRID(ST_MakePoint(3.39, 6.45), 4326)::geography, 400);

\echo '=== B5. Event ending before it starts (CHECK) - expect ERROR ==='
INSERT INTO ar_event (experience_id, venue_id, title, starts_at, ends_at, capacity)
VALUES (1, 1, 'Time travel', '2026-12-05 20:00+01', '2026-12-05 18:00+01', 10);

\echo '=== B6. Same user buying two tickets for one event (UNIQUE) - expect ERROR ==='
INSERT INTO ticket (event_id, user_id, price_paid) VALUES (1, 3, 5000);

\echo '=== B7. Selling more tickets than capacity (CHECK chk_not_oversold) - expect ERROR ==='
UPDATE ar_event SET tickets_sold = capacity + 1 WHERE event_id = 3;

\echo '=== B8. Two payments for one ticket (UNIQUE 1:1) - expect ERROR ==='
INSERT INTO payment (ticket_id, amount_ngn, provider, reference, status)
VALUES (1, 5000, 'card', 'CARD-DUP-1', 'success');

\set ON_ERROR_STOP on
\echo '=== Done: every Part B statement should have printed an ERROR above. ==='
