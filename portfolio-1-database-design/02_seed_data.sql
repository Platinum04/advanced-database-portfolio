-- =====================================================================
-- SpatialHub - Portfolio 1 sample data
-- File: 02_seed_data.sql   (run after 01_schema.sql)
-- Small, hand-written data set used to check the design.
-- Portfolio 2 will generate a much larger data set for performance tests.
-- NOTE: ST_MakePoint takes (longitude, latitude) - in that order.
-- =====================================================================

INSERT INTO app_user (username, email, full_name, role) VALUES
 ('ada_xr',     'ada@spatialhub.test',     'Adaeze Okafor',   'creator'),
 ('tunde3d',    'tunde@spatialhub.test',   'Tunde Bakare',    'creator'),
 ('zainab_v',   'zainab@spatialhub.test',  'Zainab Musa',     'visitor'),
 ('kelechi',    'kelechi@spatialhub.test', 'Kelechi Eze',     'visitor'),
 ('emma_ldn',   'emma@spatialhub.test',    'Emma Clarke',     'visitor'),
 ('admin',      'admin@spatialhub.test',   'Platform Admin',  'admin');

INSERT INTO city (name, country_code, region) VALUES
 ('Lagos',  'NG', 'africa-west'),
 ('Abuja',  'NG', 'africa-west'),
 ('London', 'GB', 'europe-west');

INSERT INTO venue (city_id, name, venue_type, address, location) VALUES
 (1, 'Freedom Park Lagos',        'park',          'Broad Street, Lagos Island',
     ST_SetSRID(ST_MakePoint(3.3935, 6.4513), 4326)::geography),
 (1, 'National Museum Onikan',    'museum',        'Awolowo Road, Onikan, Lagos',
     ST_SetSRID(ST_MakePoint(3.4025, 6.4440), 4326)::geography),
 (1, 'Yaba Tech Hub Street',      'street',        'Herbert Macaulay Way, Yaba',
     ST_SetSRID(ST_MakePoint(3.3792, 6.5095), 4326)::geography),
 (2, 'Millennium Park Abuja',     'park',          'Maitama, Abuja',
     ST_SetSRID(ST_MakePoint(7.5100, 9.0700), 4326)::geography),
 (3, 'South Bank Walk',           'street',        'Queen''s Walk, London SE1',
     ST_SetSRID(ST_MakePoint(-0.1160, 51.5070), 4326)::geography);

INSERT INTO asset_3d (creator_id, title, file_format, file_url, file_size_bytes, polygon_count) VALUES
 (1, 'Benin Bronze Head (replica scan)', 'glb',  'https://cdn.spatialhub.test/assets/benin-head.glb',  8400000, 120000),
 (1, 'Talking Drum',                     'glb',  'https://cdn.spatialhub.test/assets/talking-drum.glb', 2100000,  35000),
 (2, 'Danfo Bus Low-Poly',               'gltf', 'https://cdn.spatialhub.test/assets/danfo.gltf',       3500000,  18000),
 (2, 'Holographic Guide Avatar',         'usdz', 'https://cdn.spatialhub.test/assets/guide.usdz',       5600000,  60000),
 (1, 'Eyo Masquerade',                   'glb',  'https://cdn.spatialhub.test/assets/eyo.glb',          6900000,  90000);

INSERT INTO ar_experience (creator_id, title, description, status) VALUES
 (1, 'Lagos Heritage AR Trail', 'Walk Lagos Island and unlock 3D cultural artefacts.', 'published'),
 (2, 'Yaba Tech Street Tour',   'AR guide to the Yaba tech cluster.',                  'published'),
 (2, 'Abuja Night Lights',      'Evening AR light show in Millennium Park.',           'draft'),
 (1, 'Thames AR Story Walk',    'African diaspora stories along the South Bank.',     'published');

INSERT INTO tag (name) VALUES ('heritage'), ('education'), ('tourism'), ('tech'), ('night-event');

INSERT INTO experience_tag (experience_id, tag_id) VALUES
 (1,1),(1,2),(1,3),
 (2,4),(2,3),
 (3,5),(3,3),
 (4,1),(4,3);

INSERT INTO spatial_anchor (experience_id, asset_id, venue_id, location, altitude_m, heading_deg, scale, activation_radius_m) VALUES
 (1, 1, 2, ST_SetSRID(ST_MakePoint(3.40260, 6.44395), 4326)::geography, 1.20,  90, 1.0, 15),
 (1, 2, 1, ST_SetSRID(ST_MakePoint(3.39340, 6.45120), 4326)::geography, 0.80, 180, 1.5, 20),
 (1, 5, 1, ST_SetSRID(ST_MakePoint(3.39380, 6.45150), 4326)::geography, 0.00, 270, 2.0, 30),
 (2, 3, 3, ST_SetSRID(ST_MakePoint(3.37915, 6.50960), 4326)::geography, 0.00,  45, 1.0, 40),
 (2, 4, 3, ST_SetSRID(ST_MakePoint(3.37930, 6.50940), 4326)::geography, 1.60,   0, 1.0, 10),
 (3, 4, 4, ST_SetSRID(ST_MakePoint(7.51010, 9.07010), 4326)::geography, 2.00, 120, 3.0, 50),
 (4, 4, 5, ST_SetSRID(ST_MakePoint(-0.11610, 51.50710), 4326)::geography, 1.70, 200, 1.0, 20),
 (4, 1, NULL, ST_SetSRID(ST_MakePoint(-0.11900, 51.50800), 4326)::geography, 1.20, 10, 1.0, 15);

INSERT INTO ar_event (experience_id, venue_id, title, starts_at, ends_at, capacity, price_ngn) VALUES
 (1, 1, 'Heritage Night AR Walk',   '2026-12-05 18:00+01', '2026-12-05 21:00+01', 50,   5000),
 (2, 3, 'Yaba XR Demo Day',         '2026-12-12 10:00+01', '2026-12-12 16:00+01', 200,     0),
 (3, 4, 'Abuja Night Lights Launch','2026-12-20 19:00+01', '2026-12-20 22:00+01', 2,    7500);  -- capacity 2: used in Portfolio 3

INSERT INTO ticket (event_id, user_id, price_paid, status) VALUES
 (1, 3, 5000, 'paid'),
 (1, 4, 5000, 'paid'),
 (2, 3,    0, 'paid'),
 (2, 5,    0, 'reserved');

-- keep the counter in line with the tickets just inserted
UPDATE ar_event e
SET tickets_sold = (SELECT count(*) FROM ticket t
                    WHERE t.event_id = e.event_id AND t.status <> 'cancelled');

INSERT INTO payment (ticket_id, amount_ngn, provider, reference, status) VALUES
 (1, 5000, 'paystack',    'PSK-0001-HNW', 'success'),
 (2, 5000, 'flutterwave', 'FLW-0002-HNW', 'success');

INSERT INTO ar_session (user_id, experience_id, device_type, started_at, ended_at) VALUES
 (3, 1, 'webxr_browser',  '2026-11-01 16:00+01', '2026-11-01 16:42+01'),
 (4, 1, 'android_arcore', '2026-11-02 10:15+01', '2026-11-02 10:51+01'),
 (3, 2, 'webxr_browser',  '2026-11-03 13:00+01', '2026-11-03 13:20+01'),
 (5, 4, 'ios_arkit',      '2026-11-04 12:00+00', '2026-11-04 12:35+00'),
 (4, 2, 'headset',        '2026-11-05 15:30+01', NULL);              -- still active

INSERT INTO anchor_interaction (session_id, anchor_id, interaction_type, occurred_at) VALUES
 (1, 1, 'view',    '2026-11-01 16:05+01'),
 (1, 1, 'tap',     '2026-11-01 16:06+01'),
 (1, 2, 'view',    '2026-11-01 16:20+01'),
 (1, 3, 'collect', '2026-11-01 16:30+01'),
 (2, 2, 'view',    '2026-11-02 10:20+01'),
 (2, 3, 'share',   '2026-11-02 10:40+01'),
 (3, 4, 'view',    '2026-11-03 13:05+01'),
 (3, 5, 'tap',     '2026-11-03 13:10+01'),
 (4, 7, 'view',    '2026-11-04 12:10+00'),
 (4, 8, 'collect', '2026-11-04 12:25+00'),
 (5, 5, 'view',    '2026-11-05 15:35+01');
