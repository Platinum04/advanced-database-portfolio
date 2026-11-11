-- =====================================================================
-- SpatialHub - Portfolio 3: manual two-window locking demo
-- File: 03_two_terminal_lock_demo.sql
-- Open TWO psql windows (or two pgAdmin Query Tool tabs) on spatialhub
-- and run the steps in the order shown. Screenshot both windows at step 3.
-- =====================================================================

-- SETUP (either window): leave exactly one seat on event 3
DELETE FROM payment WHERE ticket_id IN (SELECT ticket_id FROM ticket WHERE event_id = 3);
DELETE FROM ticket WHERE event_id = 3;
INSERT INTO ticket (event_id, user_id, price_paid, status) VALUES (3, 1, 7500, 'paid');
UPDATE ar_event SET tickets_sold = 1 WHERE event_id = 3;

-- STEP 1 - WINDOW A (buyer: user 3)
BEGIN;
SELECT capacity, tickets_sold FROM ar_event WHERE event_id = 3 FOR UPDATE;  -- shows 1/2, row now LOCKED

-- STEP 2 - WINDOW B (buyer: user 4)
BEGIN;
SELECT capacity, tickets_sold FROM ar_event WHERE event_id = 3 FOR UPDATE;  -- HANGS: waiting for A's lock

-- STEP 3 - any third window: see who is blocking whom
SELECT pid, state, wait_event_type, wait_event, pg_blocking_pids(pid) AS blocked_by, left(query, 60) AS query
FROM pg_stat_activity
WHERE datname = 'spatialhub' AND query ILIKE '%FOR UPDATE%' AND pid <> pg_backend_pid();

-- STEP 4 - WINDOW A: buy the last seat and release the lock
INSERT INTO ticket (event_id, user_id, price_paid, status) VALUES (3, 3, 7500, 'paid');
UPDATE ar_event SET tickets_sold = tickets_sold + 1 WHERE event_id = 3;
COMMIT;

-- STEP 5 - WINDOW B: its SELECT now returns 2/2 -> sold out, so give up
ROLLBACK;
