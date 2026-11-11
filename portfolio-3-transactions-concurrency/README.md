# Portfolio 3: Transactions and Concurrency

Case study: SpatialHub | Database: PostgreSQL 16

## The problem I wanted to test

SpatialHub sells tickets to live AR events, and some of them have very few places. "Abuja Night Lights Launch" only has 2, because every guest needs a headset. Buying a ticket is really four steps:

1. Check there's a seat left.
2. Create the ticket.
3. Add one to `tickets_sold` on the event.
4. Save the payment.

If only some of those steps happen, or two people's steps get mixed together, we either sell seats we don't have or take someone's money for nothing. This part shows both problems and the ways to stop them.

## Files

| File | What it shows |
|---|---|
| 01_commit_rollback.sql | COMMIT, ROLLBACK, a SAVEPOINT, and what happens when a constraint fails halfway through |
| 02_concurrency_demo.py | Two real database connections running at the same moment. It shows the lost update, three fixes, isolation levels and a deadlock. |
| 03_two_terminal_lock_demo.sql | The row lock demo split into steps, so you can do it by hand in two psql or pgAdmin windows |
| results/ | The real output from both scripts |

To run them:

```bash
psql -d spatialhub -f 01_commit_rollback.sql
pip install "psycopg[binary]"
DATABASE_URL="postgresql://postgres:<password>@localhost:5432/spatialhub" python 02_concurrency_demo.py
```

## Part A: commit and rollback

| Test | What happens | Result |
|---|---|---|
| T1, normal purchase | Ticket, counter and payment, then COMMIT | `tickets_sold` went from 2 to 3 and the payment was saved |
| T2, card declined | Ticket and counter, then ROLLBACK | Inside the transaction the counter showed 4. After the rollback it was back to 3 and the user had no ticket. |
| T3, savepoint | An extra booking fails partway through, so I roll back to the savepoint and carry on | The main ticket and payment were kept, and only the failed booking was thrown away |
| T4, constraint failure | One statement pushes `tickets_sold` above capacity | PostgreSQL aborted the whole transaction, so COMMIT turned into a ROLLBACK. An earlier price change in the same transaction was undone too (price stayed at 5000). |

So that covers atomicity (all or nothing), consistency (the constraints hold) and durability (committed data stays).

## Part B: two buyers, one seat

For each test, event 3 has a capacity of 2 and one seat is already sold. Two users click buy at exactly the same time. The script uses a thread barrier to make sure the timing really overlaps.

| Test | How it works | What happened |
|---|---|---|
| 1. The bug | The app reads `tickets_sold`, checks it in Python, then writes back the old value plus one. READ COMMITTED, which is PostgreSQL's default. | Both users read 1 out of 2, both committed, and both wrote 2. The event ended up with 3 tickets for 2 seats and a counter saying 2. None of my CHECK constraints caught it, because each write looked fine on its own. |
| 2. Row lock | `SELECT ... FOR UPDATE` | The first buyer got the lock in about 2 ms. The second had to wait about half a second for the first to finish, then saw it was sold out and rolled back. |
| 3. Conditional update | `UPDATE ... SET tickets_sold = tickets_sold + 1 WHERE tickets_sold < capacity RETURNING ...` | One update changed a row and the other changed nothing, so that user got "sold out". No waiting and no explicit lock in the app. |
| 4. SERIALIZABLE | Same code as the bug, but at SERIALIZABLE isolation, with a retry | Both read 1 out of 2. One committed. The other got error 40001 (serialization failure), retried, saw it was full and stopped. |
| 5. Non-repeatable read | Read the price twice in one transaction while someone else changes it | Under READ COMMITTED it changed from 5000 to 6000 between the two reads. Under REPEATABLE READ both reads said 5000. |
| 6. Deadlock | Two admins lock two events in opposite order | PostgreSQL spotted the cycle, cancelled one of them with error 40P01, and the other one went through. |

## What I'd actually use and why

The naive version fails because there's a gap between reading the count and writing it back. Both buyers make their decision based on the same old number, and one update quietly wipes out the other. That's a lost update. Constraints only check one row at a time, so they can't enforce "real tickets must not be more than capacity" across rows.

The row lock always works, but everyone queues behind whoever holds it. In my test the half second "payment gateway" delay was spent holding the lock, which made the second person wait. I wouldn't hold a lock while calling an outside service in a real system.

The conditional update is what I'd use for SpatialHub's checkout. The check and the increment happen in a single statement, the lock only lasts for that statement, and the app just looks at whether a row was updated.

SERIALIZABLE is the safest option for complicated rules that touch several tables, but the app has to catch the 40001 error and retry, and when lots of people are competing, lots of transactions get thrown away. I'd keep it for rarer things like paying out creators.

For reports that read the same data more than once, like an end of day sales report, REPEATABLE READ keeps the numbers consistent within the report.

To avoid deadlocks, always lock rows in the same order (for example lowest `event_id` first), and still retry on 40P01 just in case.

## Screenshots

| File | Shows |
|---|---|
| screenshots/p3-01-commit-rollback.png | T1 to T4 |
| screenshots/p3-02-lost-update.png | The oversold result |
| screenshots/p3-03-fixes.png | The three fixes, including the 40001 retry |
| screenshots/p3-04-isolation-deadlock.png | The isolation level test and the deadlock |
