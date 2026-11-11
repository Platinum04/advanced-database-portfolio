# Advanced Database Systems Portfolio (MIT 8103)

**Student:** Awodi Abdulmujeeb Ayomide
**Matric No.:** 2026/A/MIT/0184 | **Student ID:** 301892054
**Programme:** Master of Information Technology, Miva Open University, 2026/2027 First Semester

## My case study: SpatialHub

SpatialHub is a simulated company that runs a location-based augmented reality platform. Creators upload 3D models and pin them to real places using spatial anchors. Visitors walk around Lagos, Abuja or London, point a phone (or put on a headset, or open a WebXR page in the browser), and the content shows up where it was placed. The platform also sells tickets to live AR events.

The database has to handle location data, payments that need to be exact, and a steady stream of device data from headsets and phones, which is why I used it for all five parts of the portfolio.

## What's in each folder

| # | Activity | Folder | What I did |
|---|---|---|---|
| 1 | Database design and modelling | [portfolio-1-database-design](portfolio-1-database-design/) | 11 table schema in PostgreSQL with PostGIS, ER diagram, normalisation up to BCNF, constraint tests |
| 2 | Query processing and optimisation | [portfolio-2-query-optimisation](portfolio-2-query-optimisation/) | Loaded 1.4 million rows, compared query plans before and after GiST, B-tree and BRIN indexes, added a materialised view |
| 3 | Transactions and concurrency | [portfolio-3-transactions-concurrency](portfolio-3-transactions-concurrency/) | Reproduced two people buying the last ticket at once, then fixed it three different ways |
| 4 | NoSQL | [portfolio-4-nosql](portfolio-4-nosql/) | Moved scene data into MongoDB documents, geo queries, time series data from headsets and phones |
| 5 | Distributed and cloud | [portfolio-5-distributed-cloud](portfolio-5-distributed-cloud/) | PostgreSQL replication with a failover test, MongoDB sharding by region |
| - | Final write-up | [documentation](documentation/) | The 2 page summary, my reflection and the AI use declaration |

Every folder has its own README explaining what I built and what I found, the scripts, a `results` folder with the real output from running them, and a `screenshots` folder.

## Tools

PostgreSQL 16 with PostGIS 3, MongoDB 8, Python 3 (psycopg and pymongo), psql and pgAdmin, Mermaid for the diagrams, Git and GitHub.

## Running it

```bash
createdb spatialhub
psql -d spatialhub -f portfolio-1-database-design/01_schema.sql
psql -d spatialhub -f portfolio-1-database-design/02_seed_data.sql
psql -d spatialhub -f portfolio-2-query-optimisation/01_generate_data.sql
```

After that, each folder's README has the steps for that part.

## References

- PostgreSQL Global Development Group (2025) *PostgreSQL 16 Documentation*. https://www.postgresql.org/docs/16/
- PostGIS Project (2025) *PostGIS 3 Manual*. https://postgis.net/documentation/
- MongoDB Inc. (2025) *MongoDB Manual*. https://www.mongodb.com/docs/manual/
- Elmasri, R. and Navathe, S.B. (2016) *Fundamentals of Database Systems*. 7th edn. Pearson.
- Kleppmann, M. (2017) *Designing Data-Intensive Applications*. O'Reilly.
- Nigeria Data Protection Commission (2023) *Nigeria Data Protection Act 2023*.
- Miva Open University (2026) *MIT 8103 Advanced Database Systems course materials*, Study Sessions 1 to 6.

## AI use

I used Claude in the browser to help draft the SQL, Python and shell scripts and to generate the synthetic test data. I went through the scripts, ran them, checked the outputs against what I expected, and fixed the problems that came up along the way (they're described in my reflection in the documentation folder).
