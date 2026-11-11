"""
SpatialHub - Portfolio 3: Concurrency problems and control mechanisms
File: 02_concurrency_demo.py

Uses two real database connections running at the same moment (threads +
a barrier), so the race conditions are reproduced, not just described.

  Demo 1  Lost update: two buyers race for the LAST ticket (naive code)
  Demo 2  Fix A: pessimistic locking with SELECT ... FOR UPDATE
  Demo 3  Fix B: atomic conditional UPDATE (no read-then-write gap)
  Demo 4  Fix C: SERIALIZABLE isolation + retry on serialization failure
  Demo 5  Non-repeatable read: READ COMMITTED vs REPEATABLE READ
  Demo 6  Deadlock detection

Requirements:  pip install "psycopg[binary]"
Run:           python 02_concurrency_demo.py
Connection:    set DATABASE_URL, e.g.
               postgresql://postgres:yourpassword@localhost:5432/spatialhub
"""
import os
import threading
import time

import psycopg
from psycopg import errors

DSN = os.environ.get("DATABASE_URL", "dbname=spatialhub")
EVENT = 3            # "Abuja Night Lights Launch", capacity = 2
BUYERS = (3, 4)      # Zainab and Kelechi try to buy at the same moment


_print_lock = threading.Lock()


def log(who, msg):
    with _print_lock:
        print(f"  [{time.strftime('%H:%M:%S')}.{int(time.time()*1000)%1000:03d}] {who:<8} {msg}", flush=True)


def reset(sold_already=1):
    """Event 3 has capacity 2. Pre-sell one seat so exactly ONE seat is left."""
    with psycopg.connect(DSN, autocommit=True) as c:
        c.execute("DELETE FROM payment WHERE ticket_id IN (SELECT ticket_id FROM ticket WHERE event_id=%s)", (EVENT,))
        c.execute("DELETE FROM ticket WHERE event_id=%s", (EVENT,))
        c.execute("INSERT INTO ticket(event_id,user_id,price_paid,status) VALUES (%s,1,7500,'paid')", (EVENT,))
        c.execute("UPDATE ar_event SET tickets_sold=%s WHERE event_id=%s", (sold_already, EVENT))


def state(title):
    with psycopg.connect(DSN) as c:
        cap, sold = c.execute("SELECT capacity,tickets_sold FROM ar_event WHERE event_id=%s", (EVENT,)).fetchone()
        real = c.execute("SELECT count(*) FROM ticket WHERE event_id=%s AND status<>'cancelled'", (EVENT,)).fetchone()[0]
    flag = "OVERSOLD / INCONSISTENT" if real > cap or real != sold else "consistent"
    print(f"  >> {title}: capacity={cap}, tickets_sold counter={sold}, real tickets={real}  -> {flag}\n")


def race(worker):
    barrier = threading.Barrier(2)
    threads = [threading.Thread(target=worker, args=(u, barrier)) for u in BUYERS]
    for t in threads: t.start()
    for t in threads: t.join()


# ---------------------------------------------------------------- Demo 1
def naive_buy(user, barrier):
    who = f"user{user}"
    with psycopg.connect(DSN) as c:                       # READ COMMITTED (default)
        cap, sold = c.execute("SELECT capacity,tickets_sold FROM ar_event WHERE event_id=%s", (EVENT,)).fetchone()
        log(who, f"reads sold={sold}/{cap} -> seat available, buying...")
        barrier.wait()                                    # both have now read the same value
        if sold < cap:
            c.execute("INSERT INTO ticket(event_id,user_id,price_paid,status) VALUES (%s,%s,7500,'paid')", (EVENT, user))
            c.execute("UPDATE ar_event SET tickets_sold=%s WHERE event_id=%s", (sold + 1, EVENT))
            c.commit()
            log(who, f"COMMIT, wrote tickets_sold={sold + 1}")


# ---------------------------------------------------------------- Demo 2
def locked_buy(user, barrier):
    who = f"user{user}"
    with psycopg.connect(DSN) as c:
        barrier.wait()
        t0 = time.time()
        cap, sold = c.execute("SELECT capacity,tickets_sold FROM ar_event WHERE event_id=%s FOR UPDATE", (EVENT,)).fetchone()
        log(who, f"got row lock after {1000*(time.time()-t0):.0f} ms, sees sold={sold}/{cap}")
        time.sleep(0.5)                                   # simulate calling the payment gateway
        if sold < cap:
            c.execute("INSERT INTO ticket(event_id,user_id,price_paid,status) VALUES (%s,%s,7500,'paid')", (EVENT, user))
            c.execute("UPDATE ar_event SET tickets_sold=tickets_sold+1 WHERE event_id=%s", (EVENT,))
            c.commit(); log(who, "COMMIT -> ticket bought")
        else:
            c.rollback(); log(who, "SOLD OUT -> ROLLBACK")


# ---------------------------------------------------------------- Demo 3
def atomic_buy(user, barrier):
    who = f"user{user}"
    with psycopg.connect(DSN) as c:
        barrier.wait()
        row = c.execute("""UPDATE ar_event SET tickets_sold = tickets_sold + 1
                           WHERE event_id=%s AND tickets_sold < capacity
                           RETURNING tickets_sold""", (EVENT,)).fetchone()
        if row:
            c.execute("INSERT INTO ticket(event_id,user_id,price_paid,status) VALUES (%s,%s,7500,'paid')", (EVENT, user))
            c.commit(); log(who, f"conditional UPDATE matched 1 row (sold={row[0]}) -> COMMIT")
        else:
            c.rollback(); log(who, "conditional UPDATE matched 0 rows -> SOLD OUT")


# ---------------------------------------------------------------- Demo 4
def serializable_buy(user, barrier, attempt=1):
    who = f"user{user}"
    with psycopg.connect(DSN) as c:
        c.isolation_level = psycopg.IsolationLevel.SERIALIZABLE
        try:
            cap, sold = c.execute("SELECT capacity,tickets_sold FROM ar_event WHERE event_id=%s", (EVENT,)).fetchone()
            log(who, f"attempt {attempt}: reads sold={sold}/{cap} (SERIALIZABLE snapshot)")
            if barrier: barrier.wait()
            if sold < cap:
                c.execute("INSERT INTO ticket(event_id,user_id,price_paid,status) VALUES (%s,%s,7500,'paid')", (EVENT, user))
                c.execute("UPDATE ar_event SET tickets_sold=%s WHERE event_id=%s", (sold + 1, EVENT))
                c.commit(); log(who, "COMMIT -> ticket bought")
            else:
                c.rollback(); log(who, "SOLD OUT")
        except (errors.SerializationFailure, errors.UniqueViolation) as e:
            c.rollback()
            log(who, f"ERROR {e.sqlstate} {type(e).__name__} -> rolled back, retrying")
            serializable_buy(user, None, attempt + 1)


# ---------------------------------------------------------------- Demo 5
def non_repeatable_read(level):
    print(f"  Isolation level: {level.name}")
    reader = psycopg.connect(DSN); reader.isolation_level = level
    writer = psycopg.connect(DSN, autocommit=True)
    p1 = reader.execute("SELECT price_ngn FROM ar_event WHERE event_id=1").fetchone()[0]
    log("reader", f"1st read of event 1 price = {p1}")
    writer.execute("UPDATE ar_event SET price_ngn = price_ngn + 1000 WHERE event_id=1")
    log("writer", "updates price +1000 and COMMITs")
    p2 = reader.execute("SELECT price_ngn FROM ar_event WHERE event_id=1").fetchone()[0]
    log("reader", f"2nd read in SAME transaction  = {p2}  -> "
                  f"{'NON-REPEATABLE READ' if p1 != p2 else 'repeatable (snapshot kept)'}")
    reader.rollback()
    writer.execute("UPDATE ar_event SET price_ngn = 5000 WHERE event_id=1")
    reader.close(); writer.close()


# ---------------------------------------------------------------- Demo 6
def deadlock():
    barrier = threading.Barrier(2)

    def worker(name, first, second):
        with psycopg.connect(DSN) as c:
            c.execute("SET deadlock_timeout = '200ms'")
            c.execute("UPDATE ar_event SET title=title WHERE event_id=%s", (first,))
            log(name, f"locked event {first}")
            barrier.wait()
            try:
                log(name, f"now wants event {second} ...")
                c.execute("UPDATE ar_event SET title=title WHERE event_id=%s", (second,))
                c.commit(); log(name, "COMMIT")
            except errors.DeadlockDetected as e:
                c.rollback(); log(name, f"ERROR {e.sqlstate} deadlock detected -> chosen as victim, ROLLBACK")

    ts = [threading.Thread(target=worker, args=("admin-A", 1, 2)), threading.Thread(target=worker, args=("admin-B", 2, 1))]
    for t in ts: t.start()
    for t in ts: t.join()


if __name__ == "__main__":
    print("\n=== Demo 1: LOST UPDATE - naive read-then-write, READ COMMITTED ===")
    reset(); state("before"); race(naive_buy); state("after")

    print("=== Demo 2: FIX A - pessimistic lock (SELECT ... FOR UPDATE) ===")
    reset(); race(locked_buy); state("after")

    print("=== Demo 3: FIX B - atomic conditional UPDATE ===")
    reset(); race(atomic_buy); state("after")

    print("=== Demo 4: FIX C - SERIALIZABLE isolation with retry ===")
    reset(); race(serializable_buy); state("after")

    print("=== Demo 5: NON-REPEATABLE READ ===")
    non_repeatable_read(psycopg.IsolationLevel.READ_COMMITTED)
    non_repeatable_read(psycopg.IsolationLevel.REPEATABLE_READ)

    print("\n=== Demo 6: DEADLOCK detection ===")
    deadlock()

    reset(sold_already=1)
    print("\nDone.")
