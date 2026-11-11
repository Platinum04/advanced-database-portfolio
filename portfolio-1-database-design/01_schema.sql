-- =====================================================================
-- SpatialHub - Location-Based AR Platform
-- Portfolio 1: Database Design and Modelling
-- File: 01_schema.sql   |   DBMS: PostgreSQL 16 + PostGIS 3
-- Run:  psql -d spatialhub -f 01_schema.sql
-- =====================================================================

-- PostGIS gives us the GEOGRAPHY type for real-world anchor positions
CREATE EXTENSION IF NOT EXISTS postgis;

-- Clean re-run (drop in reverse dependency order)
DROP TABLE IF EXISTS anchor_interaction, ar_session, payment, ticket, ar_event,
                     spatial_anchor, experience_tag, tag, ar_experience,
                     asset_3d, venue, city, app_user CASCADE;

-- ---------------------------------------------------------------------
-- 1. USERS (visitors, creators and admins share one table; role column)
-- ---------------------------------------------------------------------
CREATE TABLE app_user (
    user_id      BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    username     VARCHAR(40)  NOT NULL UNIQUE,
    email        VARCHAR(120) NOT NULL UNIQUE,
    full_name    VARCHAR(100) NOT NULL,
    role         VARCHAR(10)  NOT NULL DEFAULT 'visitor'
                 CHECK (role IN ('visitor', 'creator', 'admin')),
    created_at   TIMESTAMPTZ  NOT NULL DEFAULT now(),
    CONSTRAINT chk_email_format CHECK (email LIKE '%_@_%._%')
);

-- ---------------------------------------------------------------------
-- 2. LOCATION HIERARCHY: city -> venue  (city is also our future shard key)
-- ---------------------------------------------------------------------
CREATE TABLE city (
    city_id       SMALLINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    name          VARCHAR(60) NOT NULL,
    country_code  CHAR(2)     NOT NULL,          -- ISO 3166-1 alpha-2
    region        VARCHAR(20) NOT NULL
                  CHECK (region IN ('africa-west', 'europe-west', 'americas-east')),
    CONSTRAINT uq_city UNIQUE (name, country_code)
);

CREATE TABLE venue (
    venue_id   BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    city_id    SMALLINT     NOT NULL REFERENCES city(city_id),
    name       VARCHAR(100) NOT NULL,
    venue_type VARCHAR(20)  NOT NULL
               CHECK (venue_type IN ('museum', 'park', 'campus', 'mall', 'heritage_site', 'street')),
    address    VARCHAR(200),
    location   GEOGRAPHY(POINT, 4326) NOT NULL,   -- WGS84 lon/lat
    CONSTRAINT uq_venue_name_city UNIQUE (city_id, name)
);

-- ---------------------------------------------------------------------
-- 3. CONTENT: 3D assets and AR experiences
-- ---------------------------------------------------------------------
CREATE TABLE asset_3d (
    asset_id        BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    creator_id      BIGINT       NOT NULL REFERENCES app_user(user_id),
    title           VARCHAR(100) NOT NULL,
    file_format     VARCHAR(5)   NOT NULL CHECK (file_format IN ('glb', 'gltf', 'usdz')),
    file_url        VARCHAR(300) NOT NULL UNIQUE,
    file_size_bytes BIGINT       NOT NULL CHECK (file_size_bytes > 0),
    polygon_count   INTEGER      NOT NULL CHECK (polygon_count > 0),
    uploaded_at     TIMESTAMPTZ  NOT NULL DEFAULT now()
);

CREATE TABLE ar_experience (
    experience_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    creator_id    BIGINT       NOT NULL REFERENCES app_user(user_id),
    title         VARCHAR(120) NOT NULL,
    description   TEXT,
    status        VARCHAR(10)  NOT NULL DEFAULT 'draft'
                  CHECK (status IN ('draft', 'published', 'archived')),
    created_at    TIMESTAMPTZ  NOT NULL DEFAULT now()
);

-- Many-to-many: an experience has many tags; a tag labels many experiences
CREATE TABLE tag (
    tag_id SMALLINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    name   VARCHAR(30) NOT NULL UNIQUE
);

CREATE TABLE experience_tag (
    experience_id BIGINT   NOT NULL REFERENCES ar_experience(experience_id) ON DELETE CASCADE,
    tag_id        SMALLINT NOT NULL REFERENCES tag(tag_id)                  ON DELETE CASCADE,
    PRIMARY KEY (experience_id, tag_id)               -- composite key
);

-- ---------------------------------------------------------------------
-- 4. SPATIAL ANCHORS: where a 3D asset is pinned in the real world
-- ---------------------------------------------------------------------
CREATE TABLE spatial_anchor (
    anchor_id           BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    experience_id       BIGINT NOT NULL REFERENCES ar_experience(experience_id) ON DELETE CASCADE,
    asset_id            BIGINT NOT NULL REFERENCES asset_3d(asset_id),
    venue_id            BIGINT REFERENCES venue(venue_id),      -- NULL = open street anchor
    location            GEOGRAPHY(POINT, 4326) NOT NULL,
    altitude_m          NUMERIC(7,2) NOT NULL DEFAULT 0,
    heading_deg         NUMERIC(5,2) NOT NULL DEFAULT 0 CHECK (heading_deg >= 0 AND heading_deg < 360),
    scale               NUMERIC(6,3) NOT NULL DEFAULT 1 CHECK (scale > 0),
    activation_radius_m NUMERIC(6,1) NOT NULL DEFAULT 25 CHECK (activation_radius_m BETWEEN 1 AND 1000),
    created_at          TIMESTAMPTZ  NOT NULL DEFAULT now()
);

-- ---------------------------------------------------------------------
-- 5. EVENTS, TICKETS, PAYMENTS (live AR events at a venue)
-- ---------------------------------------------------------------------
CREATE TABLE ar_event (
    event_id      BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    experience_id BIGINT        NOT NULL REFERENCES ar_experience(experience_id),
    venue_id      BIGINT        NOT NULL REFERENCES venue(venue_id),
    title         VARCHAR(120)  NOT NULL,
    starts_at     TIMESTAMPTZ   NOT NULL,
    ends_at       TIMESTAMPTZ   NOT NULL,
    capacity      INTEGER       NOT NULL CHECK (capacity > 0),
    tickets_sold  INTEGER       NOT NULL DEFAULT 0,          -- controlled denormalisation (see README)
    price_ngn     NUMERIC(10,2) NOT NULL DEFAULT 0 CHECK (price_ngn >= 0),
    CONSTRAINT chk_event_time  CHECK (ends_at > starts_at),
    CONSTRAINT chk_not_oversold CHECK (tickets_sold BETWEEN 0 AND capacity)
);

CREATE TABLE ticket (
    ticket_id    BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    event_id     BIGINT        NOT NULL REFERENCES ar_event(event_id),
    user_id      BIGINT        NOT NULL REFERENCES app_user(user_id),
    price_paid   NUMERIC(10,2) NOT NULL CHECK (price_paid >= 0),
    status       VARCHAR(10)   NOT NULL DEFAULT 'reserved'
                 CHECK (status IN ('reserved', 'paid', 'cancelled', 'used')),
    purchased_at TIMESTAMPTZ   NOT NULL DEFAULT now(),
    CONSTRAINT uq_one_ticket_per_user UNIQUE (event_id, user_id)
);

CREATE TABLE payment (
    payment_id   BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    ticket_id    BIGINT        NOT NULL UNIQUE REFERENCES ticket(ticket_id),  -- 1:1
    amount_ngn   NUMERIC(10,2) NOT NULL CHECK (amount_ngn >= 0),
    provider     VARCHAR(20)   NOT NULL CHECK (provider IN ('paystack', 'flutterwave', 'card', 'wallet')),
    reference    VARCHAR(40)   NOT NULL UNIQUE,
    status       VARCHAR(10)   NOT NULL CHECK (status IN ('pending', 'success', 'failed', 'refunded')),
    paid_at      TIMESTAMPTZ   NOT NULL DEFAULT now()
);

-- ---------------------------------------------------------------------
-- 6. USAGE DATA: AR sessions and anchor interactions (high volume)
-- ---------------------------------------------------------------------
CREATE TABLE ar_session (
    session_id    BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    user_id       BIGINT      NOT NULL REFERENCES app_user(user_id),
    experience_id BIGINT      NOT NULL REFERENCES ar_experience(experience_id),
    device_type   VARCHAR(15) NOT NULL
                  CHECK (device_type IN ('webxr_browser', 'android_arcore', 'ios_arkit', 'headset')),
    started_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
    ended_at      TIMESTAMPTZ,
    CONSTRAINT chk_session_time CHECK (ended_at IS NULL OR ended_at >= started_at)
);

CREATE TABLE anchor_interaction (
    interaction_id   BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    session_id       BIGINT      NOT NULL REFERENCES ar_session(session_id) ON DELETE CASCADE,
    anchor_id        BIGINT      NOT NULL REFERENCES spatial_anchor(anchor_id) ON DELETE CASCADE,
    interaction_type VARCHAR(10) NOT NULL CHECK (interaction_type IN ('view', 'tap', 'collect', 'share')),
    occurred_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- NOTE: Only PK/UNIQUE indexes exist at this stage on purpose.
-- Portfolio 2 adds B-tree and GiST (spatial) indexes and measures the difference.
