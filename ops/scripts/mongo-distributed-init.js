// MongoDB initialization for distributed IDPS
db = db.getSiblingDB('idps_distributed');

// Create collections for distributed processing
db.createCollection('traffic_events');
db.createCollection('security_rules');
db.createCollection('processing_stats');
db.createCollection('node_status');

// Create indexes for performance
db.traffic_events.createIndex({ "timestamp": 1 });
db.traffic_events.createIndex({ "source_ip": 1 });
db.traffic_events.createIndex({ "threat_level": 1 });
db.traffic_events.createIndex({ "event_type": 1 });

db.security_rules.createIndex({ "created_at": 1 });
db.security_rules.createIndex({ "target": 1 });
db.security_rules.createIndex({ "rule_type": 1 });
db.security_rules.createIndex({ "active": 1 });

db.processing_stats.createIndex({ "timestamp": 1 });
db.node_status.createIndex({ "node_id": 1 });
db.node_status.createIndex({ "last_seen": 1 });

// Create initial data
print("Distributed IDPS database initialized successfully");
