"""
SpatialHub - Portfolio 4: NoSQL and Advanced Data Models
File: 01_migrate_from_postgres.py

Reads the relational SpatialHub data (Portfolios 1-2) from PostgreSQL and
reshapes it into MongoDB documents:

  experiences  - one rich document per AR experience: tags, creator and the
                 full list of anchors (each with an embedded 3D-asset
                 snapshot) -> the AR client gets a whole scene in ONE read.
  anchors      - one document per anchor with a GeoJSON point and a 2dsphere
                 index -> "what is near me?" across all experiences.

Requirements:  pip install "psycopg[binary]" pymongo
Env vars:      DATABASE_URL  (PostgreSQL, default dbname=spatialhub)
               MONGODB_URI   (default mongodb://localhost:27017,
                              or your Atlas "mongodb+srv://..." string)
"""
import os
import time
from decimal import Decimal

import psycopg
from psycopg.rows import dict_row, tuple_row
from pymongo import MongoClient, GEOSPHERE, ASCENDING

PG = os.environ.get("DATABASE_URL", "dbname=spatialhub")
MONGO = os.environ.get("MONGODB_URI", "mongodb://localhost:27017")

db = MongoClient(MONGO)["spatialhub"]


def num(v):
    return float(v) if isinstance(v, Decimal) else v


def migrate():
    t0 = time.time()
    db.experiences.drop()
    db.anchors.drop()

    # JSON-schema validation: NoSQL does not have to mean "no rules"
    db.create_collection("experiences", validator={"$jsonSchema": {
        "bsonType": "object",
        "required": ["_id", "title", "status", "creator", "anchors"],
        "properties": {
            "status": {"enum": ["draft", "published", "archived"]},
            "anchors": {"bsonType": "array", "items": {
                "bsonType": "object",
                "required": ["anchor_id", "location", "asset"],
                "properties": {"heading_deg": {"bsonType": "double", "minimum": 0, "maximum": 359.99}}}}}}})

    with psycopg.connect(PG, row_factory=dict_row) as pg:
        # ---------- experiences (Portfolio 1 hand-made data: ids 1-4) ----------
        exps = pg.execute("""
            SELECT x.experience_id, x.title, x.description, x.status, x.created_at,
                   u.user_id, u.username, u.full_name,
                   COALESCE(array_agg(t.name ORDER BY t.name) FILTER (WHERE t.name IS NOT NULL), '{}') AS tags
            FROM ar_experience x
            JOIN app_user u ON u.user_id = x.creator_id
            LEFT JOIN experience_tag et ON et.experience_id = x.experience_id
            LEFT JOIN tag t ON t.tag_id = et.tag_id
            WHERE x.experience_id <= 4
            GROUP BY x.experience_id, u.user_id ORDER BY x.experience_id""").fetchall()

        for e in exps:
            anchors = pg.execute("""
                SELECT a.anchor_id, ST_X(a.location::geometry) lon, ST_Y(a.location::geometry) lat,
                       a.altitude_m, a.heading_deg, a.scale, a.activation_radius_m,
                       v.name venue, s.asset_id, s.title asset_title, s.file_format, s.file_url,
                       s.polygon_count
                FROM spatial_anchor a
                JOIN asset_3d s ON s.asset_id = a.asset_id
                LEFT JOIN venue v ON v.venue_id = a.venue_id
                WHERE a.experience_id = %s AND a.anchor_id <= 8
                ORDER BY a.anchor_id""", (e["experience_id"],)).fetchall()
            db.experiences.insert_one({
                "_id": e["experience_id"],
                "title": e["title"],
                "description": e["description"],
                "status": e["status"],
                "tags": e["tags"],
                "creator": {"user_id": e["user_id"], "username": e["username"], "name": e["full_name"]},
                "created_at": e["created_at"],
                "anchors": [{
                    "anchor_id": a["anchor_id"],
                    "venue": a["venue"],
                    "location": {"type": "Point", "coordinates": [a["lon"], a["lat"]]},
                    "altitude_m": num(a["altitude_m"]),
                    "heading_deg": num(a["heading_deg"]),
                    "scale": num(a["scale"]),
                    "activation_radius_m": num(a["activation_radius_m"]),
                    "asset": {   # extended-reference pattern: copy what the renderer needs
                        "asset_id": a["asset_id"], "title": a["asset_title"],
                        "format": a["file_format"], "url": a["file_url"],
                        "polygons": a["polygon_count"]},
                } for a in anchors],
            })
        print(f"experiences: {db.experiences.count_documents({})} documents")

        # ---------- all anchors -> geo collection ----------
        batch, total = [], 0
        cur = pg.cursor(name="anchors_cursor", row_factory=tuple_row)  # server-side cursor: stream 200k rows
        cur.execute("""SELECT anchor_id, experience_id, asset_id,
                              ST_X(location::geometry), ST_Y(location::geometry), activation_radius_m
                       FROM spatial_anchor""")
        for aid, xid, asid, lon, lat, rad in cur:
            batch.append({"_id": aid, "experience_id": xid, "asset_id": asid,
                          "location": {"type": "Point", "coordinates": [lon, lat]},
                          "activation_radius_m": num(rad)})
            if len(batch) == 5000:
                db.anchors.insert_many(batch); total += len(batch); batch = []
        if batch:
            db.anchors.insert_many(batch); total += len(batch)
        print(f"anchors:     {total} documents")

    db.anchors.create_index([("location", GEOSPHERE)], name="location_2dsphere")
    db.anchors.create_index([("experience_id", ASCENDING)])
    db.experiences.create_index([("anchors.location", GEOSPHERE)], name="anchors_location_2dsphere")
    db.experiences.create_index([("tags", ASCENDING)])   # multikey index on an array
    print(f"indexes created; migration took {time.time() - t0:.1f} s")


if __name__ == "__main__":
    migrate()
