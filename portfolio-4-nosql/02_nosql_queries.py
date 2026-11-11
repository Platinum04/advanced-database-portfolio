"""
SpatialHub - Portfolio 4: NoSQL queries, time-series telemetry and evidence
File: 02_nosql_queries.py   (run after 01_migrate_from_postgres.py)

  Q1  Load a whole AR scene in ONE read (document model)
  Q2  Geospatial $near on the anchors collection + explain() plan
  Q3  Multikey index query on the tags array
  Q4  Flexible schema: headset vs phone telemetry in a TIME-SERIES collection
  Q5  Aggregation pipeline: frame-rate quality report per device type
  Q6  Atomic in-document update ($push a new anchor)
  Q7  Schema validation rejects a bad document
  -> sample documents exported to sample-documents/*.json

Env var: MONGODB_URI (default mongodb://localhost:27017)
"""
import json
import os
import random
from datetime import datetime, timedelta, timezone

from bson import json_util
from pymongo import MongoClient
from pymongo.errors import WriteError

db = MongoClient(os.environ.get("MONGODB_URI", "mongodb://localhost:27017"))["spatialhub"]
random.seed(8103)
here = os.path.dirname(os.path.abspath(__file__))
os.makedirs(os.path.join(here, "sample-documents"), exist_ok=True)


def show(title):
    print("\n" + "=" * 70 + f"\n{title}\n" + "=" * 70)


def dump(name, doc):
    with open(os.path.join(here, "sample-documents", name), "w") as f:
        f.write(json_util.dumps(doc, indent=2))


# --------------------------------------------------------------------- Q1
show("Q1. Load the 'Lagos Heritage AR Trail' scene in a single read")
scene = db.experiences.find_one({"title": "Lagos Heritage AR Trail"})
print(f"title={scene['title']!r}, tags={scene['tags']}, creator={scene['creator']['username']}")
for a in scene["anchors"]:
    print(f"  anchor {a['anchor_id']}: {a['asset']['title']:<35} {a['asset']['format']}  "
          f"at {a['location']['coordinates']}  radius={a['activation_radius_m']} m")
print("-> relational version needs a 5-table join (experience, user, tags, anchors, assets)")
dump("experience_lagos_heritage_trail.json", scene)

# --------------------------------------------------------------------- Q2
show("Q2. Anchors within 300 m of a user in Yaba, Lagos ($near + 2dsphere)")
user_pos = {"type": "Point", "coordinates": [3.3792, 6.5095]}
query = {"location": {"$near": {"$geometry": user_pos, "$maxDistance": 300}}}
near = list(db.anchors.find(query).limit(20))
print(f"{len(near)} anchors returned (nearest first). First 3:")
for d in near[:3]:
    print(f"  anchor {d['_id']} experience {d['experience_id']} at {d['location']['coordinates']}")
plan = db.anchors.find(query).limit(20).explain()
stats = plan["executionStats"]
def stages(p):
    out = [p.get("stage")]
    for k in ("inputStage",):
        if k in p: out += stages(p[k])
    for c in p.get("inputStages", []): out += stages(c)
    return out
print(f"winning plan stages: {' <- '.join(s for s in stages(plan['queryPlanner']['winningPlan']) if s)}")
print(f"docs examined: {stats['totalDocsExamined']} of {db.anchors.estimated_document_count()}, "
      f"keys examined: {stats['totalKeysExamined']}, time: {stats['executionTimeMillis']} ms")
dump("anchor_example.json", near[0])

# --------------------------------------------------------------------- Q3
show("Q3. Experiences tagged 'heritage' (multikey index on an array)")
for e in db.experiences.find({"tags": "heritage"}, {"title": 1, "tags": 1}):
    print(f"  {e['title']}: {e['tags']}")
p = db.experiences.find({"tags": "heritage"}).explain()["queryPlanner"]["winningPlan"]
print(f"plan: {' <- '.join(s for s in stages(p) if s)}")

# --------------------------------------------------------------------- Q4
show("Q4. Time-series telemetry with a flexible schema (headset vs phone)")
db.telemetry.drop()
db.create_collection("telemetry", timeseries={
    "timeField": "ts", "metaField": "meta", "granularity": "seconds"})
start = datetime(2026, 11, 1, 16, 0, tzinfo=timezone.utc)
docs = []
devices = [("webxr_browser", 3), ("android_arcore", 4), ("ios_arkit", 5), ("headset", 4)]
for session_id, (device, user) in enumerate(devices * 25, start=1):
    for i in range(120):                          # 120 samples = 1 minute at 2 Hz
        d = {"ts": start + timedelta(minutes=session_id, seconds=i / 2),
             "meta": {"session_id": session_id, "user_id": user, "device": device, "experience_id": 1},
             "fps": round(random.gauss({"headset": 88, "ios_arkit": 58, "android_arcore": 50,
                                        "webxr_browser": 42}[device], 6), 1),
             "head_pose": {"pos": [round(random.uniform(-2, 2), 2), round(random.uniform(1.4, 1.8), 2),
                                   round(random.uniform(-2, 2), 2)],
                           "rot": [round(random.uniform(-1, 1), 3) for _ in range(4)]}}
        if device == "headset":                   # only headsets have eye tracking + controllers
            d["eye_gaze"] = {"dir": [round(random.uniform(-1, 1), 3) for _ in range(3)],
                             "fixated_anchor": random.choice([1, 2, 3, None])}
            d["controllers"] = {"left_trigger": round(random.random(), 2), "right_trigger": round(random.random(), 2)}
        else:                                     # phones report AR lighting + tracking state
            d["light_estimate_lux"] = round(random.uniform(200, 20000))
            d["tracking_state"] = random.choice(["normal", "normal", "normal", "limited"])
        docs.append(d)
db.telemetry.insert_many(docs)
print(f"inserted {db.telemetry.count_documents({})} telemetry samples from {len(devices) * 25} sessions")
hs = db.telemetry.find_one({"meta.device": "headset"}, {"_id": 0})
ph = db.telemetry.find_one({"meta.device": "android_arcore"}, {"_id": 0})
print("headset sample keys:", sorted(hs.keys()))
print("phone   sample keys:", sorted(ph.keys()))
dump("telemetry_headset_sample.json", hs)
dump("telemetry_phone_sample.json", ph)

# --------------------------------------------------------------------- Q5
show("Q5. Aggregation: frame-rate quality per device (comfort threshold)")
pipeline = [
    {"$group": {"_id": "$meta.device",
                "samples": {"$sum": 1},
                "avg_fps": {"$avg": "$fps"},
                "min_fps": {"$min": "$fps"},
                "below_threshold": {"$sum": {"$cond": [
                    {"$lt": ["$fps", {"$cond": [{"$eq": ["$meta.device", "headset"]}, 72, 30]}]}, 1, 0]}}}},
    {"$project": {"samples": 1, "avg_fps": {"$round": ["$avg_fps", 1]}, "min_fps": 1,
                  "pct_below": {"$round": [{"$multiply": [{"$divide": ["$below_threshold", "$samples"]}, 100]}, 2]}}},
    {"$sort": {"avg_fps": -1}}]
print(f"{'device':<16}{'samples':>8}{'avg fps':>9}{'min fps':>9}{'% below comfort':>17}")
for r in db.telemetry.aggregate(pipeline):
    print(f"{r['_id']:<16}{r['samples']:>8}{r['avg_fps']:>9}{r['min_fps']:>9}{r['pct_below']:>16}%")
print("(comfort threshold: 72 fps for headsets, 30 fps for phones/browsers)")

# --------------------------------------------------------------------- Q6
show("Q6. Atomic single-document update: add an anchor to the scene")
new_anchor = {"anchor_id": 900001, "venue": "Freedom Park Lagos",
              "location": {"type": "Point", "coordinates": [3.39365, 6.45135]},
              "altitude_m": 0.0, "heading_deg": 45.0, "scale": 1.0, "activation_radius_m": 20.0,
              "asset": {"asset_id": 4, "title": "Holographic Guide Avatar", "format": "usdz",
                        "url": "https://cdn.spatialhub.test/assets/guide.usdz", "polygons": 60000}}
db.experiences.update_one({"_id": 1, "anchors.anchor_id": {"$ne": 900001}},
                          {"$push": {"anchors": new_anchor}})
print(f"anchors in scene now: {len(db.experiences.find_one({'_id': 1})['anchors'])}")
db.experiences.update_one({"_id": 1}, {"$pull": {"anchors": {"anchor_id": 900001}}})   # undo for re-runs

# --------------------------------------------------------------------- Q7
show("Q7. Schema validation: insert an experience with an invalid status")
try:
    db.experiences.insert_one({"_id": 999, "title": "Bad", "status": "live",
                               "creator": {"user_id": 1}, "anchors": []})
except WriteError as e:
    print(f"REJECTED (code {e.code}): {e.details.get('errmsg')}")
print("\nDone.")
