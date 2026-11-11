# Portfolio 4: NoSQL and Advanced Data Models

Case study: SpatialHub | NoSQL database: MongoDB 8 (documents and a time series collection)

## Why use NoSQL for part of SpatialHub

The relational design from Portfolio 1 is still where tickets and payments belong. They need proper transactions and strict rules, as Portfolio 3 showed. But two parts of an AR platform fit a document database better:

| Workload | The problem in PostgreSQL | What MongoDB gives me |
|---|---|---|
| Loading a scene. When the app opens an experience, it needs every anchor, its position and the 3D model to load. | That's a join across 5 tables every time someone opens an experience. | One document per experience, so the whole scene comes back in a single read. |
| Device telemetry. Head position, frame rate and eye tracking, sent a couple of times every second. | It's a lot of inserts, and the fields depend on the device. Headsets send eye tracking and controller data, phones send light levels and tracking state. A single table would be full of empty columns. | A time series collection where each document only has the fields its device actually sends. |

So I'm using both. PostgreSQL stays the main source of truth, and `01_migrate_from_postgres.py` builds the MongoDB side from it.

## How the data is shaped

**experiences**: one document per experience, with the anchors inside it. There's a real example in [sample-documents/experience_lagos_heritage_trail.json](sample-documents/experience_lagos_heritage_trail.json).

```json
{ "_id": 1, "title": "Lagos Heritage AR Trail", "status": "published",
  "tags": ["education", "heritage", "tourism"],
  "creator": { "user_id": 1, "username": "ada_xr", "name": "Adaeze Okafor" },
  "anchors": [
    { "anchor_id": 1, "venue": "National Museum Onikan",
      "location": { "type": "Point", "coordinates": [3.4026, 6.44395] },
      "altitude_m": 1.2, "heading_deg": 90.0, "scale": 1.0, "activation_radius_m": 15.0,
      "asset": { "asset_id": 1, "title": "Benin Bronze Head (replica scan)",
                 "format": "glb", "url": "https://cdn.spatialhub.test/assets/benin-head.glb",
                 "polygons": 120000 } } ] }
```

- I put the anchors inside the experience because they're always loaded together, and one experience only has a handful of anchors, not millions.
- For the 3D asset I only copied the fields the app needs to render it (title, format, URL, polygon count). The full record stays in PostgreSQL. This is called the extended reference pattern.
- The downside is that if a creator renames an asset, every copy has to be updated. Asset details hardly ever change and scenes get loaded all the time, so I'm fine with that.

**anchors**: 200,008 small documents, each with a GeoJSON point and a 2dsphere index. This handles "what's near me" across every experience, the same job the GiST index did in Portfolio 2.

**telemetry**: a time series collection. MongoDB groups the readings from each session into compressed buckets on its own. There's a headset sample and a phone sample in `sample-documents/` if you want to see how different they are.

**Validation**: the experiences collection has a `$jsonSchema` rule for required fields, allowed status values and the heading range. A flexible schema doesn't mean anything goes.

## Files

| File | What it does |
|---|---|
| 01_migrate_from_postgres.py | Reads from PostgreSQL, builds the experiences and anchors collections, and creates the indexes and validation rule |
| 02_nosql_queries.py | Seven queries: scene read, nearby search with explain, tags, telemetry, aggregation, an update and a validation test |
| 03_mongosh_queries.js | The main queries written for mongosh, so you can paste them into Compass or Atlas |
| sample-documents/ | Real documents exported from the database |
| results/ | The output from both Python scripts |

To run it (local MongoDB or the free Atlas tier both work):

```bash
pip install "psycopg[binary]" pymongo
export DATABASE_URL="postgresql://postgres:<pw>@localhost:5432/spatialhub"
export MONGODB_URI="mongodb+srv://<user>:<pw>@<cluster>.mongodb.net"   # or mongodb://localhost:27017
python 01_migrate_from_postgres.py
python 02_nosql_queries.py
```

## Results

| Test | What happened |
|---|---|
| Migration | 4 experience documents and 200,008 anchor documents in 3.6 seconds |
| Q1, scene in one read | A single `findOne` returned 3 anchors with their model details inside |
| Q2, nearby search within 300 m | Found the 20 nearest anchors using the 2dsphere index. It looked at 36 of the 200,008 documents and took 1 ms. |
| Q3, tags | MongoDB used the index on the tags array |
| Q4, telemetry | 12,000 readings from 100 sessions. Headset readings have eye gaze and controller fields, phone readings have light level and tracking state, all in the same collection. |
| Q5, frame rate report | Headsets averaged 88.1 fps, iPhones 58.0, Android 50.0, and WebXR in the browser 42.0, with 2.07% of browser readings below 30 fps. The browser is clearly the weakest platform. |
| Q6, adding an anchor | `$push` added a new anchor to the scene in one atomic update |
| Q7, validation | A document with `status: "live"` was rejected with error 121 |

In case the plan for Q2 looks odd: there are several index scan stages in it because MongoDB searches in growing rings around the user and stops once it has 20 results. That's why it only had to look at so few documents.

## PostgreSQL vs MongoDB for this project

| | PostgreSQL | MongoDB |
|---|---|---|
| Good for in SpatialHub | Tickets, payments, users. The main source of truth. | Loading scenes, telemetry, data that's different per device |
| Consistency | Full transactions across many rows | Atomic per document. Multi-document transactions exist but cost more. |
| Schema | Fixed. Changes need a migration. | Flexible, with optional validation rules |
| Location queries | PostGIS, which has more functions | 2dsphere, with `$near` and `$geoWithin` |
| Scaling out | Mostly a bigger server plus read replicas | Sharding is built in (I use it in Portfolio 5) |

Other NoSQL types I could add later: Redis (key-value) for a live "collect all the artefacts" leaderboard, and a graph database like Neo4j for "friends who visited this spot" suggestions.

## Screenshots

| File | Shows |
|---|---|
| screenshots/p4-01-scene-document.png | A full experience document |
| screenshots/p4-02-near-explain.png | The nearby search and its plan |
| screenshots/p4-03-telemetry-aggregation.png | The telemetry data and frame rate report |
| screenshots/p4-04-validation.png | The anchor update and the rejected document |
