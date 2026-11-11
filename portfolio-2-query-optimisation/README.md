# Portfolio 2: Query Processing and Optimisation

Case study: SpatialHub | Database: PostgreSQL 16 with PostGIS 3

## Why this matters for an AR app

When someone holds up their phone, the app has to ask "what's near me?" and get an answer fast. If that query is slow, the 3D content pops in late and the whole effect falls apart. So for this part I wanted to see how the important queries behave with a realistic amount of data, and how much the right index actually helps.

What I did:

1. Generated a big data set on top of the Portfolio 1 database.
2. Ran four real queries from the app with `EXPLAIN (ANALYZE, BUFFERS)`.
3. Added one index for each query, picked to match how that query reads the data.
4. Ran them again and compared the plans and times.
5. Tried a materialised view as a cache for the "trending" leaderboard.

## Files

| File | What it does |
|---|---|
| 01_generate_data.sql | Adds 20k users, 2k venues, 5k assets, 3k experiences, 200k anchors, 200k sessions and 1 million interactions. The random seed is fixed, so it gives the same data every time. |
| 02_queries.sql | The four queries (Q1 to Q4) with EXPLAIN ANALYZE |
| 03_create_indexes.sql | The GiST, composite B-tree, BRIN and foreign key indexes, plus a size comparison |
| 04_materialized_view.sql | The trending anchors leaderboard as a materialised view |
| run_benchmark.sh | Runs everything in order and saves the output to `results/` |
| results/ | The full query plans from before and after, the index sizes, and the materialised view test |

To run it: `psql -d spatialhub -f 01_generate_data.sql`, then `bash run_benchmark.sh`. The script runs each query twice and keeps the second run, so the first run warms up the cache and doesn't skew the numbers.

## Results

| Query | Before | After | Faster by |
|---|---|---|---|
| Q1: anchors within 300 m of a user, nearest first | Full parallel scan of 200k anchors, 168.2 ms | GiST index scan, 7.4 ms | about 23x |
| Q2: a user's 20 latest sessions | Full scan plus sort, 11.3 ms | Composite B-tree, 0.12 ms | about 98x |
| Q3: interactions for one day | Full scan of 1M rows, 139.6 ms | BRIN index, 8.1 ms | about 17x |
| Q4: engagement for one anchor | Full scan of 1M rows, 36.4 ms | Index on the foreign key, 0.08 ms | about 470x |
| Trending leaderboard | Live aggregate, 168.2 ms | Materialised view, 0.08 ms | about 2,000x |

These were measured on PostgreSQL 16.15 with JIT turned off (I explain why below). The exact times will be different on another machine, but the plans should change the same way.

Index sizes:

| Index | Type | Size |
|---|---|---|
| B-tree on interaction time (only built to compare) | B-tree | 21 MB |
| idx_anchor_location_gist | GiST | 14 MB |
| idx_interaction_anchor | B-tree | 11 MB |
| idx_session_user_started | B-tree, two columns | 6 MB |
| idx_interaction_time_brin | BRIN | 24 kB |

## What I learned from each one

**Q1, the spatial search.** A normal B-tree can't help with "within 300 metres" because location has two dimensions and a B-tree only sorts on one. Without an index, PostgreSQL worked out the distance to every one of the 200,000 anchors. The GiST index groups anchors into boxes, so it only looks inside the boxes near the user and checks a few dozen real distances. For an AR app, that's the difference between content that's already there and content that shows up half a second late.

**Q2, column order matters.** The query filters on `user_id` and sorts by `started_at` newest first. With the index on `(user_id, started_at DESC)`, that user's sessions sit together and already in the right order, so PostgreSQL reads 7 rows instead of 200,000 and doesn't need to sort.

**Q3, BRIN for a log table.** Interactions get written in time order, so the rows are physically in the same order as the timestamps. BRIN only stores the earliest and latest time for each block of pages, which is enough to skip almost the whole table. It came out at 24 kB against 21 MB for a B-tree on the same column. The catch is that it only works while the rows stay in time order. If old rows got updated or back-filled a lot, I'd switch to a B-tree.

**Q4, foreign keys don't get indexes automatically.** PostgreSQL indexes primary keys and unique columns, but not foreign key columns. So looking up one anchor's interactions meant scanning a million rows. This was the biggest relative improvement of the lot, and it also speeds up cascade deletes from `spatial_anchor`.

**The materialised view.** The leaderboard is a 30 day total, and working it out live on every app launch costs around 170 ms. Reading it from the materialised view takes 0.08 ms. The trade-off is that it can be a few minutes out of date. Refreshing it with `REFRESH MATERIALIZED VIEW CONCURRENTLY` takes about 370 ms and doesn't block anyone reading it (that needs a unique index on the view, which I added). Running that every 5 minutes is fine for a leaderboard.

**Something I didn't expect: JIT.** My first run showed Q1 at 489 ms before indexing. When I read the full plan, 475 ms of that was JIT compilation, not the scan itself. The plan's cost estimate was so high that PostgreSQL decided it was worth compiling the query to machine code, which didn't pay off here. I turned JIT off in `02_queries.sql` so the comparison is between the access methods and nothing else. The lesson for me was to read the whole EXPLAIN output and not just the time at the bottom. On a real server I'd raise `jit_above_cost` so normal app queries never trigger it.

**Indexes aren't free.** Every index slows down inserts and takes disk space. The interaction log gets written to constantly, which is part of why I picked BRIN over a B-tree for its time column.

## Screenshots

| File | Shows |
|---|---|
| screenshots/p2-01-data-volume.png | Row counts after generating the data |
| screenshots/p2-02-q1-before-after.png | Q1 going from a full scan to the GiST index |
| screenshots/p2-03-timings-summary.png | The before and after times |
| screenshots/p2-04-index-sizes.png | BRIN at 24 kB against the 21 MB B-tree |
