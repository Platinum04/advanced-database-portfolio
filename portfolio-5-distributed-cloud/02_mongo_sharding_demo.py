"""
SpatialHub - Portfolio 5B: geo-partitioned sharding with MongoDB zones
File: 02_mongo_sharding_demo.py

Starts a small sharded cluster on one machine:
  config server replica set  cfg          port 27101
  shard "shardAfrica"        (Lagos DC)   port 27201  -> zone africa-west
  shard "shardEurope"        (London DC)  port 27301  -> zone europe-west
  mongos router                           port 27400
Then shards the anchors collection on {region, _id}, pins each region to
its own shard (data residency + low latency), loads 200k anchors and
shows targeted vs scatter-gather queries.

Needs: mongod and mongos binaries on PATH (or MONGO_BIN), pip install pymongo
"""
import os
import random
import shutil
import subprocess
import time

from bson import MinKey, MaxKey
from pymongo import MongoClient, InsertOne

BIN = os.environ.get("MONGO_BIN", "")
BASE = os.environ.get("BASE", "/tmp/spatialhub-shard")
random.seed(8103)


def run(*args):
    subprocess.run(list(args), check=True, stdout=subprocess.DEVNULL)


def start_mongod(name, port, *extra):
    path = f"{BASE}/{name}"
    os.makedirs(path, exist_ok=True)
    run(os.path.join(BIN, "mongod"), "--dbpath", path, "--port", str(port), "--bind_ip", "127.0.0.1",
        "--fork", "--logpath", f"{path}.log", *extra)


def init_rs(port, rs, configsvr=False):
    c = MongoClient(f"mongodb://127.0.0.1:{port}", directConnection=True)
    cfg = {"_id": rs, "members": [{"_id": 0, "host": f"127.0.0.1:{port}"}]}
    if configsvr:
        cfg["configsvr"] = True
    c.admin.command("replSetInitiate", cfg)
    for _ in range(60):
        if c.admin.command("hello").get("isWritablePrimary"):
            return
        time.sleep(0.5)


def stop_cluster():
    """Stop every process of this demo and wait until they have really exited."""
    subprocess.run(["pkill", "-f", BASE], stderr=subprocess.DEVNULL)
    for _ in range(60):
        if subprocess.run(["pgrep", "-f", BASE], stdout=subprocess.DEVNULL).returncode != 0:
            return
        time.sleep(0.5)
    subprocess.run(["pkill", "-9", "-f", BASE], stderr=subprocess.DEVNULL)
    time.sleep(1)


def section(t):
    print("\n" + "=" * 70 + f"\n{t}\n" + "=" * 70)


def stages(p):
    out = [p.get("stage")]
    if "inputStage" in p: out += stages(p["inputStage"])
    for c in p.get("inputStages", []): out += stages(c)
    return out


def main():
    stop_cluster()
    shutil.rmtree(BASE, ignore_errors=True)

    section("1. Start config server, two shards and the mongos router")
    start_mongod("cfg", 27101, "--configsvr", "--replSet", "cfgRS")
    start_mongod("africa", 27201, "--shardsvr", "--replSet", "shardAfrica")
    start_mongod("europe", 27301, "--shardsvr", "--replSet", "shardEurope")
    init_rs(27101, "cfgRS", configsvr=True)
    init_rs(27201, "shardAfrica")
    init_rs(27301, "shardEurope")
    run(os.path.join(BIN, "mongos"), "--configdb", "cfgRS/127.0.0.1:27101", "--port", "27400",
        "--bind_ip", "127.0.0.1", "--fork", "--logpath", f"{BASE}/mongos.log")
    m = MongoClient("mongodb://127.0.0.1:27400")
    m.admin.command("addShard", "shardAfrica/127.0.0.1:27201", name="shardAfrica")
    m.admin.command("addShard", "shardEurope/127.0.0.1:27301", name="shardEurope")
    for s in m.admin.command("listShards")["shards"]:
        print(f"  shard {s['_id']:<12} host {s['host']}")

    section("2. Zone sharding: pin each region to the data centre in that region")
    m.admin.command("addShardToZone", "shardAfrica", zone="africa-west")
    m.admin.command("addShardToZone", "shardEurope", zone="europe-west")
    m.admin.command("enableSharding", "spatialhub")
    m.admin.command("updateZoneKeyRange", "spatialhub.anchors",
                    min={"region": "africa-west", "_id": MinKey()},
                    max={"region": "africa-west", "_id": MaxKey()}, zone="africa-west")
    m.admin.command("updateZoneKeyRange", "spatialhub.anchors",
                    min={"region": "europe-west", "_id": MinKey()},
                    max={"region": "europe-west", "_id": MaxKey()}, zone="europe-west")
    # Zones are defined BEFORE sharding the empty collection, so MongoDB creates
    # the initial chunks already on the right shard (no balancer migration needed).
    m.admin.command("shardCollection", "spatialhub.anchors", key={"region": 1, "_id": 1})
    print("  shard key: { region: 1, _id: 1 }")
    print("  africa-west -> shardAfrica (Lagos/Abuja),  europe-west -> shardEurope (London)")

    section("3. Load 200,000 anchors through the router")
    cities = [("Lagos", "africa-west", 3.38, 6.50), ("Abuja", "africa-west", 7.49, 9.06),
              ("London", "europe-west", -0.12, 51.50)]
    ops = []
    for i in range(1, 200001):
        city, region, lon, lat = cities[i % 3]
        ops.append(InsertOne({"_id": i, "region": region, "city": city,
                              "location": {"type": "Point", "coordinates": [lon + (random.random() - .5) * .3,
                                                                            lat + (random.random() - .5) * .3]},
                              "experience_id": random.randint(1, 3000)}))
    t0 = time.time()
    m.spatialhub.anchors.bulk_write(ops, ordered=False)
    print(f"  inserted {m.spatialhub.anchors.estimated_document_count()} docs in {time.time() - t0:.1f} s")
    m.spatialhub.anchors.create_index([("region", 1), ("location", "2dsphere")])

    section("4. Where did the data go? (counted directly on each shard)")
    for name, port in (("shardAfrica", 27201), ("shardEurope", 27301)):
        c = MongoClient(f"mongodb://127.0.0.1:{port}", directConnection=True).spatialhub.anchors
        by_city = {d["_id"]: d["n"] for d in c.aggregate([{"$group": {"_id": "$city", "n": {"$sum": 1}}}])}
        print(f"  {name:<12} {sum(by_city.values()):>7} docs  {dict(sorted(by_city.items()))}")

    section("5. Targeted query vs scatter-gather (explain via mongos)")
    near_lagos = {"region": "africa-west",
                  "location": {"$geoWithin": {"$centerSphere": [[3.3792, 6.5095], 0.3 / 6378.1]}}}
    e = m.spatialhub.command("explain", {"find": "anchors", "filter": near_lagos}, verbosity="executionStats")
    wp = e["queryPlanner"]["winningPlan"]
    shards = [s["shardName"] for s in wp.get("shards", [])]
    print(f"  WITH shard key (region='africa-west'): stage={wp['stage']}, shards contacted={shards}, "
          f"returned={e['executionStats']['nReturned']}")
    no_key = {"experience_id": 42}
    e2 = m.spatialhub.command("explain", {"find": "anchors", "filter": no_key}, verbosity="executionStats")
    wp2 = e2["queryPlanner"]["winningPlan"]
    print(f"  WITHOUT shard key (experience_id=42):  stage={wp2['stage']}, "
          f"shards contacted={[s['shardName'] for s in wp2.get('shards', [])]}, "
          f"returned={e2['executionStats']['nReturned']}")

    section("6. Availability: what happens if the London shard goes down?")
    subprocess.run(["pkill", "-f", f"{BASE}/europe"], stderr=subprocess.DEVNULL)
    time.sleep(3)
    m2 = MongoClient("mongodb://127.0.0.1:27400", serverSelectionTimeoutMS=5000)
    n = m2.spatialhub.anchors.count_documents({"region": "africa-west"}, maxTimeMS=5000)
    print(f"  Lagos/Abuja query still works: {n} africa-west anchors (served by shardAfrica)")
    try:
        n2 = m2.spatialhub.anchors.count_documents({"region": "europe-west"}, maxTimeMS=5000)
        print(f"  London query returned {n2}")
    except Exception as ex:
        print(f"  London query fails: {type(ex).__name__} -> a shard needs its own replica set for HA")

    stop_cluster()
    print("\nCluster stopped. Done.")


if __name__ == "__main__":
    main()
