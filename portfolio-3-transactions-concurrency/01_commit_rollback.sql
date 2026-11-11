-- =====================================================================
-- SpatialHub - Portfolio 3: Transactions and Concurrency
-- File: 01_commit_rollback.sql
-- Shows ACID behaviour of the "buy a ticket" business transaction:
--   T1 success -> COMMIT, T2 payment failure -> ROLLBACK,
--   T3 SAVEPOINT (partial rollback), T4 constraint violation aborts all.
-- Run in psql:  \i 01_commit_rollback.sql
-- =====================================================================
\set ON_ERROR_STOP off

-- reset event 1 test data for repeatable runs
DELETE FROM payment WHERE reference LIKE 'P3-%';
DELETE FROM ticket  WHERE event_id = 1 AND user_id IN (5, 6);
UPDATE ar_event SET tickets_sold = (SELECT count(*) FROM ticket WHERE event_id = 1 AND status <> 'cancelled')
WHERE event_id = 1;

\echo '=== Starting state of event 1 ==='
SELECT event_id, title, capacity, tickets_sold FROM ar_event WHERE event_id = 1;

-- ---------------------------------------------------------------------
\echo '=== T1: successful purchase -> COMMIT (Atomicity + Durability) ==='
BEGIN;
  INSERT INTO ticket (event_id, user_id, price_paid, status) VALUES (1, 5, 5000, 'paid');
  UPDATE ar_event SET tickets_sold = tickets_sold + 1 WHERE event_id = 1;
  INSERT INTO payment (ticket_id, amount_ngn, provider, reference, status)
  VALUES (currval('ticket_ticket_id_seq'), 5000, 'paystack', 'P3-T1-OK', 'success');
COMMIT;
SELECT event_id, tickets_sold FROM ar_event WHERE event_id = 1;
SELECT t.ticket_id, t.user_id, t.status, p.reference FROM ticket t JOIN payment p USING (ticket_id)
WHERE p.reference = 'P3-T1-OK';

-- ---------------------------------------------------------------------
\echo '=== T2: payment gateway declines -> ROLLBACK (nothing is kept) ==='
BEGIN;
  INSERT INTO ticket (event_id, user_id, price_paid, status) VALUES (1, 6, 5000, 'reserved');
  UPDATE ar_event SET tickets_sold = tickets_sold + 1 WHERE event_id = 1;
  \echo '   inside T2 the seat looks taken:'
  SELECT tickets_sold AS inside_t2 FROM ar_event WHERE event_id = 1;
  -- application receives "card declined" from the gateway
ROLLBACK;
\echo '   after ROLLBACK the seat and the ticket are gone:'
SELECT tickets_sold AS after_rollback FROM ar_event WHERE event_id = 1;
SELECT count(*) AS user6_tickets FROM ticket WHERE event_id = 1 AND user_id = 6;

-- ---------------------------------------------------------------------
\echo '=== T3: SAVEPOINT - keep the ticket, undo only a failed upsell ==='
BEGIN;
  INSERT INTO ticket (event_id, user_id, price_paid, status) VALUES (1, 6, 5000, 'paid');
  UPDATE ar_event SET tickets_sold = tickets_sold + 1 WHERE event_id = 1;
  SAVEPOINT before_upsell;
    -- try to also book user 6 onto event 3, but with an invalid price
    INSERT INTO ticket (event_id, user_id, price_paid) VALUES (3, 6, -100);   -- violates CHECK
  ROLLBACK TO SAVEPOINT before_upsell;
  INSERT INTO payment (ticket_id, amount_ngn, provider, reference, status)
  SELECT ticket_id, 5000, 'wallet', 'P3-T3-SAVEPOINT', 'success'
  FROM ticket WHERE event_id = 1 AND user_id = 6;
COMMIT;
SELECT t.event_id, t.user_id, p.reference FROM ticket t JOIN payment p USING (ticket_id)
WHERE t.user_id = 6;

-- ---------------------------------------------------------------------
\echo '=== T4: Consistency - a CHECK violation aborts the whole transaction ==='
BEGIN;
  UPDATE ar_event SET price_ngn = 6000 WHERE event_id = 1;             -- fine on its own
  UPDATE ar_event SET tickets_sold = capacity + 1 WHERE event_id = 1;  -- violates chk_not_oversold
  UPDATE ar_event SET title = title || ' (edited)' WHERE event_id = 1;  -- rejected: txn already aborted
COMMIT;   -- PostgreSQL turns this into ROLLBACK
SELECT event_id, price_ngn, title FROM ar_event WHERE event_id = 1;   -- price still 5000
