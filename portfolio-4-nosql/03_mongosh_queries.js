// SpatialHub - Portfolio 4: the same key queries in mongosh syntax
// (paste into mongosh, MongoDB Compass "Mongosh" tab, or Atlas shell)
use("spatialhub");

// Q1 whole scene in one read
db.experiences.findOne({ title: "Lagos Heritage AR Trail" });

// Q2 anchors within 300 m of a user in Yaba, Lagos, nearest first
db.anchors.find({
  location: { $near: { $geometry: { type: "Point", coordinates: [3.3792, 6.5095] }, $maxDistance: 300 } }
}).limit(20);

// Q2 plan
db.anchors.find({
  location: { $near: { $geometry: { type: "Point", coordinates: [3.3792, 6.5095] }, $maxDistance: 300 } }
}).limit(20).explain("executionStats");

// Q3 multikey index on tags
db.experiences.find({ tags: "heritage" }, { title: 1, tags: 1 });

// Q5 frame-rate report per device
db.telemetry.aggregate([
  { $group: { _id: "$meta.device", samples: { $sum: 1 }, avg_fps: { $avg: "$fps" }, min_fps: { $min: "$fps" } } },
  { $sort: { avg_fps: -1 } }
]);
