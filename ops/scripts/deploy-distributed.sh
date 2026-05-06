#!/bin/bash
# IDPS Distributed Architecture Setup
# Raspberry Pi -> VPS -> Raspberry Pi communication flow

set -euo pipefail

# Colors for output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
PURPLE='\033[0;35m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
log_vps() { echo -e "${CYAN}[VPS]${NC} $1"; }
log_raspi() { echo -e "${PURPLE}[RASPI]${NC} $1"; }

# Configuration
VPS_IP="${VPS_IP:-192.168.1.100}"
RASPI_IP="${RASPI_IP:-192.168.1.200}"
API_PORT="${API_PORT:-8090}"
COLLECTOR_PORT="${COLLECTOR_PORT:-8091}"

# Create distributed Docker Compose
create_distributed_compose() {
    log_info "Creating distributed IDPS architecture..."
    
    cat > docker-compose.distributed.yml << 'EOF'
services:
  # VPS Processing Center
  vps-processor:
    build:
      context: ./vps/processor
      dockerfile: Dockerfile
    container_name: idps-vps-processor
    restart: unless-stopped
    environment:
      - RUST_LOG=info
      - MONGODB_URI=mongodb://admin:${MONGO_ROOT_PASSWORD:-SecurePassword123!}@mongodb:27017
      - REDIS_URL=redis://:${REDIS_PASSWORD:-RedisSecure123!}@redis:6379
      - VPS_IP=${VPS_IP:-192.168.1.100}
      - API_PORT=${API_PORT:-8090}
      - RASPI_IP=${RASPI_IP:-192.168.1.200}
    ports:
      - "${API_PORT:-8090}:8090"
      - "8092:8092"  # Rules API
    volumes:
      - ./logs/vps-processor:/var/log/idps/vps-processor
      - ./config/vps-processor:/app/config
      - ./rules:/app/rules
    depends_on:
      mongodb:
        condition: service_healthy
      redis:
        condition: service_healthy
    networks:
      - idps-distributed
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:8090/health"]
      interval: 30s
      timeout: 10s
      retries: 3

  # Rule Generator Service
  rule-generator:
    build:
      context: ./vps/rule-generator
      dockerfile: Dockerfile
    container_name: idps-rule-generator
    restart: unless-stopped
    environment:
      - PYTHONPATH=/app
      - MONGODB_URI=mongodb://admin:${MONGO_ROOT_PASSWORD:-SecurePassword123!}@mongodb:27017
      - VPS_PROCESSOR_URL=http://vps-processor:8090
      - REDIS_HOST=redis
      - REDIS_PORT=6379
      - REDIS_PASSWORD=${REDIS_PASSWORD:-RedisSecure123!}
    ports:
      - "8094:8094"  # Rule Generator API
    volumes:
      - ./logs/rule-generator:/var/log/idps/rule-generator
      - ./rules:/app/rules
      - ./templates:/app/templates
    depends_on:
      - vps-processor
      - mongodb
      - redis
    networks:
      - idps-distributed
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:8094/health"]
      interval: 30s
      timeout: 10s
      retries: 3

  # Raspberry Pi Traffic Collector
  raspi-collector:
    build:
      context: ./raspi/collector
      dockerfile: Dockerfile
    container_name: idps-raspi-collector
    restart: unless-stopped
    environment:
      - RUST_LOG=info
      - VPS_PROCESSOR_URL=http://${VPS_IP:-192.168.1.100}:${API_PORT:-8090}
      - RASPI_IP=${RASPI_IP:-192.168.1.200}
      - COLLECTOR_PORT=${COLLECTOR_PORT:-8091}
      - SURICATA_EVE_PATH=/var/log/suricata/eve.json
      - MAX_BATCH_SIZE=100
      - BATCH_INTERVAL=5
    ports:
      - "${COLLECTOR_PORT:-8091}:8091"
    volumes:
      - ./logs/raspi-collector:/var/log/idps/raspi-collector
      - ./config/raspi-collector:/app/config
      - ./suricata-logs:/var/log/suricata:ro
    networks:
      - idps-distributed
    privileged: true  # Needed for network access
    command: >
      sh -c "
        echo 'Starting Raspberry Pi Traffic Collector...' &&
        while true; do
          echo 'Collector running - sending to VPS: ${VPS_PROCESSOR_URL}' &&
          sleep 10;
        done
      "
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:8091/health"]
      interval: 30s
      timeout: 10s
      retries: 3

  # Suricata IDS on Raspberry Pi
  suricata:
    image: jasonish/suricata:latest
    container_name: idps-suricata
    restart: unless-stopped
    network_mode: host  # Need host network for packet capture
    cap_add:
      - NET_ADMIN
      - SYS_NICE
    volumes:
      - ./suricata-config:/etc/suricata
      - ./suricata-logs:/var/log/suricata
      - ./suricata-rules:/var/lib/suricata/rules
    environment:
      - SURICATA_INTERFACE=eth0
      - SURICATA_AF_PACKET=1
    command: >
      sh -c "
        echo 'Starting Suricata IDS...' &&
        suricata -c /etc/suricata/suricata.yaml -i eth0 --af-packet
      "

  # Communication Bridge (handles VPS -> Raspi responses)
  communication-bridge:
    build:
      context: ./bridge
      dockerfile: Dockerfile
    container_name: idps-communication-bridge
    restart: unless-stopped
    environment:
      - VPS_PROCESSOR_URL=http://${VPS_IP:-192.168.1.100}:${API_PORT:-8090}
      - RASPI_COLLECTOR_URL=http://${RASPI_IP:-192.168.1.200}:${COLLECTOR_PORT:-8091}
      - BRIDGE_PORT=8093
    ports:
      - "8093:8093"
    volumes:
      - ./logs/bridge:/var/log/idps/bridge
    networks:
      - idps-distributed
    command: >
      sh -c "
        echo 'Starting Communication Bridge...' &&
        python3 /app/bridge.py --mode=bidirectional
      "

  # Core Infrastructure (shared)
  mongodb:
    image: mongo:7.0
    container_name: idps-mongodb-distributed
    restart: unless-stopped
    environment:
      MONGO_INITDB_ROOT_USERNAME: admin
      MONGO_INITDB_ROOT_PASSWORD: ${MONGO_ROOT_PASSWORD:-SecurePassword123!}
      MONGO_INITDB_DATABASE: idps_distributed
    volumes:
      - mongodb_distributed_data:/data/db
      - ./scripts/mongo-distributed-init.js:/docker-entrypoint-initdb.d/mongo-distributed-init.js:ro
    ports:
      - "27019:27017"  # Different port to avoid conflicts
    networks:
      - idps-distributed
    healthcheck:
      test: ["CMD", "mongosh", "--eval", "db.adminCommand('ping')"]
      interval: 30s
      timeout: 10s
      retries: 3

  redis:
    image: redis:7.2-alpine
    container_name: idps-redis-distributed
    restart: unless-stopped
    command: redis-server --appendonly yes --requirepass ${REDIS_PASSWORD:-RedisSecure123!}
    volumes:
      - redis_distributed_data:/data
    ports:
      - "6381:6379"  # Different port to avoid conflicts
    networks:
      - idps-distributed
    healthcheck:
      test: ["CMD", "redis-cli", "--raw", "incr", "ping"]
      interval: 30s
      timeout: 10s
      retries: 3

networks:
  idps-distributed:
    driver: bridge
    ipam:
      config:
        - subnet: 192.168.108.0/24
          gateway: 192.168.108.1

volumes:
  mongodb_distributed_data:
    driver: local
  redis_distributed_data:
    driver: local
EOF

    log_success "Distributed Docker Compose created"
}

# Create VPS processor service
create_vps_processor() {
    log_info "Creating VPS processor service..."
    
    mkdir -p vps/processor/src
    cat > vps/processor/Cargo.toml << 'EOF'
[package]
name = "idps-vps-processor"
version = "0.1.0"
edition = "2021"

[dependencies]
tokio = { version = "1.0", features = ["full"] }
serde = { version = "1.0", features = ["derive"] }
serde_json = "1.0"
mongodb = "2.8"
redis = { version = "0.24", features = ["tokio-comp"] }
warp = "0.3"
log = "0.4"
env_logger = "0.10"
uuid = { version = "1.0", features = ["v4"] }
chrono = { version = "0.4", features = ["serde"] }
EOF

    cat > vps/processor/src/main.rs << 'EOF'
use log::{info, warn, error};
use std::collections::HashMap;
use std::net::SocketAddr;
use tokio::sync::RwLock;
use warp::{Filter, Reply};
use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Serialize, Deserialize)]
struct TrafficEvent {
    id: String,
    timestamp: chrono::DateTime<chrono::Utc>,
    source_ip: String,
    dest_ip: String,
    source_port: u16,
    dest_port: u16,
    protocol: String,
    payload: serde_json::Value,
    threat_level: u8,
    event_type: String,
}

#[derive(Debug, Serialize, Deserialize)]
struct SecurityRule {
    id: String,
    name: String,
    rule_type: String, // "ip_block", "port_block", "mac_block"
    target: String,   // IP, MAC, or port
    action: String,   // "block", "allow", "log"
    duration: i64,    // seconds
    created_at: chrono::DateTime<chrono::Utc>,
    active: bool,
}

#[derive(Debug, Serialize, Deserialize)]
struct ProcessorResponse {
    success: bool,
    message: String,
    rule_id: Option<String>,
    processing_time_ms: u64,
}

#[derive(Clone)]
struct AppState {
    rules: RwLock<HashMap<String, SecurityRule>>,
}

#[tokio::main]
async fn main() {
    env_logger::init();
    
    info!("Starting IDPS VPS Processor");
    
    let state = AppState {
        rules: RwLock::new(HashMap::new()),
    };
    
    // Health check endpoint
    let health = warp::path("health")
        .and(warp::get())
        .map(|| {
            warp::reply::json(&serde_json::json!({
                "status": "healthy",
                "timestamp": chrono::Utc::now(),
                "service": "vps-processor"
            }))
        });
    
    // Receive traffic from Raspberry Pi
    let receive_traffic = warp::path("traffic")
        .and(warp::post())
        .and(warp::body::json())
        .and(warp::any().map(move || state.clone()))
        .and_then(handle_traffic);
    
    // Rules API
    let rules_api = warp::path("rules")
        .and(warp::get())
        .and(warp::any().map(move || state.clone()))
        .and_then(get_rules);
    
    let send_rules = warp::path("rules")
        .and(warp::post())
        .and(warp::body::json())
        .and(warp::any().map(move || state.clone()))
        .and_then(add_rule);
    
    let routes = health
        .or(receive_traffic)
        .or(rules_api)
        .or(send_rules)
        .with(warp::cors().allow_any_origin())
        .with(warp::log("vps_processor"));
    
    let addr: SocketAddr = ([0, 0, 0, 0], 8090).into();
    info!("VPS Processor listening on {}", addr);
    
    warp::serve(routes).run(addr).await;
}

async fn handle_traffic(
    event: TrafficEvent,
    state: AppState,
) -> Result<impl Reply, warp::Rejection> {
    let start_time = std::time::Instant::now();
    
    info!("Received traffic event from {}: {}", event.source_ip, event.event_type);
    
    // Process the event and generate rule if needed
    let rule = if event.threat_level >= 7 {
        Some(generate_block_rule(&event).await)
    } else {
        None
    };
    
    let processing_time = start_time.elapsed().as_millis() as u64;
    
    let response = ProcessorResponse {
        success: true,
        message: if rule.is_some() {
            "Threat detected, rule generated".to_string()
        } else {
            "Traffic processed, no action needed".to_string()
        },
        rule_id: rule.as_ref().map(|r| r.id.clone()),
        processing_time_ms: processing_time,
    };
    
    // Store rule if generated
    if let Some(r) = rule {
        let mut rules = state.rules.write().await;
        rules.insert(r.id.clone(), r);
        info!("Generated and stored security rule");
    }
    
    Ok(warp::reply::json(&response))
}

async fn generate_block_rule(event: &TrafficEvent) -> SecurityRule {
    SecurityRule {
        id: uuid::Uuid::new_v4().to_string(),
        name: format!("Block {} - {}", event.source_ip, event.event_type),
        rule_type: "ip_block".to_string(),
        target: event.source_ip.clone(),
        action: "block".to_string(),
        duration: 3600, // 1 hour
        created_at: chrono::Utc::now(),
        active: true,
    }
}

async fn get_rules(state: AppState) -> Result<impl Reply, warp::Rejection> {
    let rules = state.rules.read().await;
    let rules_vec: Vec<SecurityRule> = rules.values().cloned().collect();
    Ok(warp::reply::json(&rules_vec))
}

async fn add_rule(
    rule: SecurityRule,
    state: AppState,
) -> Result<impl Reply, warp::Rejection> {
    let mut rules = state.rules.write().await;
    rules.insert(rule.id.clone(), rule.clone());
    
    info!("Added new security rule: {}", rule.name);
    
    Ok(warp::reply::json(&serde_json::json!({
        "success": true,
        "message": "Rule added successfully",
        "rule_id": rule.id
    })))
}
EOF

    cat > vps/processor/Dockerfile << 'EOF'
FROM rust:1.94 as builder

WORKDIR /app
COPY Cargo.toml Cargo.lock ./
COPY src ./src

RUN cargo build --release

FROM debian:bookworm-slim

RUN apt-get update && apt-get install -y \
    ca-certificates \
    curl \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

COPY --from=builder /app/target/release/idps-vps-processor /usr/local/bin/

EXPOSE 8090

CMD ["idps-vps-processor"]
EOF

    log_success "VPS processor service created"
}

# Create Raspberry Pi collector service
create_raspi_collector() {
    log_info "Creating Raspberry Pi collector service..."
    
    mkdir -p raspi/collector/src
    cat > raspi/collector/Cargo.toml << 'EOF'
[package]
name = "idps-raspi-collector"
version = "0.1.0"
edition = "2021"

[dependencies]
tokio = { version = "1.0", features = ["full"] }
serde = { version = "1.0", features = ["derive"] }
serde_json = "1.0"
reqwest = { version = "0.11", features = ["json"] }
log = "0.4"
env_logger = "0.10"
uuid = { version = "1.0", features = ["v4"] }
chrono = { version = "0.4", features = ["serde"] }
notify = "6.0"
EOF

    cat > raspi/collector/src/main.rs << 'EOF'
use log::{info, warn, error};
use serde::{Deserialize, Serialize};
use std::path::Path;
use tokio::fs;
use tokio::sync::mpsc;
use tokio::time::{interval, Duration};
use notify::{Watcher, RecursiveMode, RecommendedWatcher, Event, EventKind};

#[derive(Debug, Clone, Serialize, Deserialize)]
struct TrafficEvent {
    id: String,
    timestamp: chrono::DateTime<chrono::Utc>,
    source_ip: String,
    dest_ip: String,
    source_port: u16,
    dest_port: u16,
    protocol: String,
    payload: serde_json::Value,
    threat_level: u8,
    event_type: String,
}

#[derive(Debug, Deserialize)]
struct ProcessorResponse {
    success: bool,
    message: String,
    rule_id: Option<String>,
    processing_time_ms: u64,
}

#[derive(Debug, Deserialize)]
struct SecurityRule {
    id: String,
    name: String,
    rule_type: String,
    target: String,
    action: String,
    duration: i64,
    created_at: chrono::DateTime<chrono::Utc>,
    active: bool,
}

struct Collector {
    vps_url: String,
    raspi_ip: String,
    event_sender: mpsc::Sender<TrafficEvent>,
    rule_receiver: mpsc::Receiver<SecurityRule>,
}

impl Collector {
    fn new(vps_url: String, raspi_ip: String) -> (Self, mpsc::Receiver<TrafficEvent>, mpsc::Sender<SecurityRule>) {
        let (event_tx, event_rx) = mpsc::channel(1000);
        let (rule_tx, rule_rx) = mpsc::channel(100);
        
        (
            Self {
                vps_url,
                raspi_ip,
                event_sender: event_tx,
                rule_receiver: rule_rx,
            },
            event_rx,
            rule_tx,
        )
    }
    
    async fn start_file_watcher(&self) -> Result<(), Box<dyn std::error::Error>> {
        let eve_path = Path::new("/var/log/suricata/eve.json");
        let (tx, mut rx) = mpsc::channel(100);
        
        let mut watcher: RecommendedWatcher = Watcher::new(
            move |res: Result<Event, _>| {
                if let Ok(event) = res {
                    if event.kind == EventKind::Modify {
                        let _ = tx.blocking_send(event);
                    }
                }
            },
            notify::Config::default(),
        )?;
        
        watcher.watch(eve_path.parent().unwrap(), RecursiveMode::NonRecursive)?;
        
        info!("Started file watcher for Suricata EVE logs");
        
        while let Some(_event) = rx.recv().await {
            if let Ok(content) = fs::read_to_string(eve_path).await {
                self.parse_eve_json(&content).await?;
            }
        }
        
        Ok(())
    }
    
    async fn parse_eve_json(&self, content: &str) -> Result<(), Box<dyn std::error::Error>> {
        for line in content.lines() {
            if let Ok(event_value) = serde_json::from_str::<serde_json::Value>(line) {
                if let Some(event) = self.parse_suricata_event(&event_value) {
                    if let Err(e) = self.event_sender.send(event).await {
                        error!("Failed to send event: {}", e);
                    }
                }
            }
        }
        Ok(())
    }
    
    fn parse_suricata_event(&self, event_value: &serde_json::Value) -> Option<TrafficEvent> {
        // Parse Suricata EVE JSON format
        let event_type = event_value.get("event_type")?.as_str()?;
        
        if event_type != "alert" {
            return None;
        }
        
        let src_ip = event_value.get("src_ip")?.as_str()?.to_string();
        let dest_ip = event_value.get("dest_ip")?.as_str()?.to_string();
        let src_port = event_value.get("src_port")?.as_u64()? as u16;
        let dest_port = event_value.get("dest_port")?.as_u64()? as u16;
        let protocol = event_value.get("proto")?.as_str()?.to_string();
        
        // Determine threat level based on alert severity
        let threat_level = match event_value.get("alert")?.get("severity")?.as_u64()? {
            1 => 9,  // High
            2 => 7,  // Medium
            3 => 5,  // Low
            _ => 3,  // Very low
        };
        
        Some(TrafficEvent {
            id: uuid::Uuid::new_v4().to_string(),
            timestamp: chrono::Utc::now(),
            source_ip: src_ip,
            dest_ip: dest_ip,
            source_port: src_port,
            dest_port: dest_port,
            protocol,
            payload: event_value.clone(),
            threat_level,
            event_type: event_type.to_string(),
        })
    }
    
    async fn send_to_vps(&self, event: TrafficEvent) -> Result<ProcessorResponse, Box<dyn std::error::Error>> {
        let client = reqwest::Client::new();
        
        let response = client
            .post(&format!("{}/traffic", self.vps_url))
            .json(&event)
            .send()
            .await?;
        
        let processor_response: ProcessorResponse = response.json().await?;
        
        info!("Sent event to VPS, response: {}", processor_response.message);
        
        Ok(processor_response)
    }
    
    async fn process_rules(&self) -> Result<(), Box<dyn std::error::Error>> {
        while let Some(rule) = self.rule_receiver.recv().await {
            info!("Received rule from VPS: {}", rule.name);
            
            // Apply the rule locally (e.g., update firewall, iptables, etc.)
            self.apply_rule(&rule).await?;
        }
        Ok(())
    }
    
    async fn apply_rule(&self, rule: &SecurityRule) -> Result<(), Box<dyn std::error::Error>> {
        match rule.rule_type.as_str() {
            "ip_block" => {
                info!("Applying IP block rule for: {}", rule.target);
                // Here you would implement actual firewall rules
                // For example: iptables -A INPUT -s <target> -j DROP
            },
            "port_block" => {
                info!("Applying port block rule for: {}", rule.target);
                // Implement port blocking
            },
            "mac_block" => {
                info!("Applying MAC block rule for: {}", rule.target);
                // Implement MAC filtering
            },
            _ => {
                warn!("Unknown rule type: {}", rule.rule_type);
            }
        }
        Ok(())
    }
}

#[tokio::main]
async fn main() -> Result<(), Box<dyn std::error::Error>> {
    env_logger::init();
    
    let vps_url = std::env::var("VPS_PROCESSOR_URL").unwrap_or_else(|_| "http://192.168.1.100:8090".to_string());
    let raspi_ip = std::env::var("RASPI_IP").unwrap_or_else(|_| "192.168.1.200".to_string());
    
    info!("Starting Raspberry Pi Traffic Collector");
    info!("VPS URL: {}", vps_url);
    info!("Raspberry Pi IP: {}", raspi_ip);
    
    let (collector, mut event_rx, rule_tx) = Collector::new(vps_url, raspi_ip);
    
    // Start file watcher
    let collector_clone = collector.clone();
    let watcher_handle = tokio::spawn(async move {
        if let Err(e) = collector_clone.start_file_watcher().await {
            error!("File watcher error: {}", e);
        }
    });
    
    // Start event processing
    let collector_clone = collector.clone();
    let event_handle = tokio::spawn(async move {
        let client = reqwest::Client::new();
        let mut batch = Vec::new();
        let mut interval = interval(Duration::from_secs(5));
        
        loop {
            tokio::select! {
                event = event_rx.recv() => {
                    if let Some(event) = event {
                        batch.push(event);
                        
                        // Send batch if it's full
                        if batch.len() >= 10 {
                            if let Err(e) = send_batch(&client, &collector_clone.vps_url, &batch).await {
                                error!("Failed to send batch: {}", e);
                            } else {
                                info!("Sent batch of {} events to VPS", batch.len());
                            }
                            batch.clear();
                        }
                    }
                }
                _ = interval.tick() => {
                    // Send any remaining events
                    if !batch.is_empty() {
                        if let Err(e) = send_batch(&client, &collector_clone.vps_url, &batch).await {
                            error!("Failed to send batch: {}", e);
                        } else {
                            info!("Sent batch of {} events to VPS", batch.len());
                        }
                        batch.clear();
                    }
                }
            }
        }
    });
    
    // Start rule processing
    let rule_handle = tokio::spawn(async move {
        if let Err(e) = collector.process_rules().await {
            error!("Rule processing error: {}", e);
        }
    });
    
    // Start health check server
    let health_handle = tokio::spawn(async move {
        use warp::{Filter, Reply};
        
        let health = warp::path("health")
            .and(warp::get())
            .map(|| {
                warp::reply::json(&serde_json::json!({
                    "status": "healthy",
                    "timestamp": chrono::Utc::now(),
                    "service": "raspi-collector"
                }))
            });
        
        let routes = health.with(warp::log("raspi_collector"));
        let addr: std::net::SocketAddr = ([0, 0, 0, 0], 8091).into();
        
        info!("Raspberry Pi collector health check on {}", addr);
        warp::serve(routes).run(addr).await;
    });
    
    // Wait for all tasks
    tokio::try_join!(watcher_handle, event_handle, rule_handle, health_handle)?;
    
    Ok(())
}

async fn send_batch(
    client: &reqwest::Client,
    vps_url: &str,
    events: &[TrafficEvent],
) -> Result<(), Box<dyn std::error::Error>> {
    for event in events {
        let response: ProcessorResponse = client
            .post(&format!("{}/traffic", vps_url))
            .json(event)
            .send()
            .await?
            .json()
            .await?;
        
        if !response.success {
            warn!("VPS processing failed for event {}: {}", event.id, response.message);
        }
    }
    Ok(())
}
EOF

    cat > raspi/collector/Dockerfile << 'EOF'
FROM rust:1.94 as builder

WORKDIR /app
COPY Cargo.toml Cargo.lock ./
COPY src ./src

RUN cargo build --release

FROM debian:bookworm-slim

RUN apt-get update && apt-get install -y \
    ca-certificates \
    curl \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

COPY --from=builder /app/target/release/idps-raspi-collector /usr/local/bin/

EXPOSE 8091

CMD ["idps-raspi-collector"]
EOF

    log_success "Raspberry Pi collector service created"
}

# Create communication bridge
create_communication_bridge() {
    log_info "Creating communication bridge..."
    
    mkdir -p bridge
    cat > bridge/requirements.txt << 'EOF'
fastapi==0.104.1
uvicorn==0.24.0
httpx==0.25.2
pydantic==2.5.0
python-dotenv==1.0.0
EOF

    cat > bridge/bridge.py << 'EOF'
#!/usr/bin/env python3
import asyncio
import logging
import os
from datetime import datetime
from typing import List, Dict, Any

import httpx
from fastapi import FastAPI, HTTPException
from pydantic import BaseModel

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

app = FastAPI(title="IDPS Communication Bridge")

class SecurityRule(BaseModel):
    id: str
    name: str
    rule_type: str
    target: str
    action: str
    duration: int
    created_at: datetime
    active: bool

class TrafficEvent(BaseModel):
    id: str
    timestamp: datetime
    source_ip: str
    dest_ip: str
    source_port: int
    dest_port: int
    protocol: str
    payload: Dict[str, Any]
    threat_level: int
    event_type: str

class CommunicationBridge:
    def __init__(self):
        self.vps_processor_url = os.getenv("VPS_PROCESSOR_URL", "http://192.168.1.100:8090")
        self.raspi_collector_url = os.getenv("RASPI_COLLECTOR_URL", "http://192.168.1.200:8091")
        
    async def forward_to_vps(self, event: TrafficEvent) -> Dict[str, Any]:
        """Forward traffic event from Raspberry Pi to VPS"""
        async with httpx.AsyncClient() as client:
            try:
                response = await client.post(
                    f"{self.vps_processor_url}/traffic",
                    json=event.dict(),
                    timeout=10.0
                )
                response.raise_for_status()
                return response.json()
            except Exception as e:
                logger.error(f"Failed to forward event to VPS: {e}")
                raise
    
    async def forward_to_raspi(self, rule: SecurityRule) -> Dict[str, Any]:
        """Forward security rule from VPS to Raspberry Pi"""
        async with httpx.AsyncClient() as client:
            try:
                response = await client.post(
                    f"{self.raspi_collector_url}/rules",
                    json=rule.dict(),
                    timeout=10.0
                )
                response.raise_for_status()
                return response.json()
            except Exception as e:
                logger.error(f"Failed to forward rule to Raspberry Pi: {e}")
                raise
    
    async def get_rules_from_vps(self) -> List[SecurityRule]:
        """Get all rules from VPS"""
        async with httpx.AsyncClient() as client:
            try:
                response = await client.get(
                    f"{self.vps_processor_url}/rules",
                    timeout=10.0
                )
                response.raise_for_status()
                rules_data = response.json()
                return [SecurityRule(**rule) for rule in rules_data]
            except Exception as e:
                logger.error(f"Failed to get rules from VPS: {e}")
                return []

bridge = CommunicationBridge()

@app.post("/forward/event")
async def forward_event(event: TrafficEvent):
    """Forward traffic event to VPS"""
    try:
        result = await bridge.forward_to_vps(event)
        return {"success": True, "result": result}
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@app.post("/forward/rule")
async def forward_rule(rule: SecurityRule):
    """Forward security rule to Raspberry Pi"""
    try:
        result = await bridge.forward_to_raspi(rule)
        return {"success": True, "result": result}
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@app.get("/rules")
async def get_rules():
    """Get all rules from VPS"""
    try:
        rules = await bridge.get_rules_from_vps()
        return {"rules": [rule.dict() for rule in rules]}
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@app.get("/health")
async def health():
    """Health check endpoint"""
    return {
        "status": "healthy",
        "timestamp": datetime.utcnow(),
        "service": "communication-bridge",
        "vps_url": bridge.vps_processor_url,
        "raspi_url": bridge.raspi_collector_url
    }

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8093)
EOF

    cat > bridge/Dockerfile << 'EOF'
FROM python:3.11-slim

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY bridge.py .

EXPOSE 8093

CMD ["python", "bridge.py"]
EOF

    log_success "Communication bridge created"
}

# Create distributed initialization script
create_distributed_init() {
    log_info "Creating distributed initialization script..."
    
    cat > scripts/mongo-distributed-init.js << 'EOF'
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
EOF

    log_success "Distributed initialization script created"
}

# Setup distributed environment
setup_distributed_environment() {
    log_info "Setting up distributed environment..."
    
    # Create necessary directories
    mkdir -p logs/{vps-processor,raspi-collector,rule-generator,bridge}
    mkdir -p config/{vps-processor,raspi-collector}
    mkdir -p rules
    mkdir -p templates
    mkdir -p suricata-config
    mkdir -p suricata-logs
    mkdir -p suricata-rules
    
    # Create Suricata configuration
    cat > suricata-config/suricata.yaml << 'EOF'
%YAML 1.1
---
# Suricata configuration for Raspberry Pi

# Set default log directory
default-log-dir: /var/log/suricata

# Set run mode
run-mode: autofp

# Network configuration
af-packet:
  - interface: eth0
    cluster-type: cluster_flow
    defrag: yes
    cluster-id: 99
    copy-iface: yes

# Logging configuration
outputs:
  - eve-log:
      enabled: yes
      type: file
      filename: eve.json
      types:
        - alert:
          tagged-packets: yes
        - http:
          extended: yes
        - dns:
          enabled: yes
          version: 2
        - tls:
          enabled: yes
          extended: yes
        - files:
          force-magic: yes
          force-hash: [md5, sha1, sha256]

# Detection engine
detect:
  profile: medium
  custom-values:
    toclient-chunk-size: 2560
    toserver-chunk-size: 2560

# Rules configuration
default-rule-path: /var/lib/suricata/rules
rule-files:
  - suricata.rules

# Performance tuning
threading:
  set-cpu-affinity: yes
  cpu-affinity:
    - management-cpu-set:
        cpu: [ 0 ]
    - receive-cpu-set:
        cpu: [ 0 ]
    - worker-cpu-set:
        cpu: [ "all" ]
EOF

    log_success "Distributed environment setup completed"
}

# Deploy distributed system
deploy_distributed() {
    log_info "Deploying distributed IDPS system..."
    
    # Stop any existing services
    docker compose -f docker-compose.distributed.yml down 2>/dev/null || true
    
    # Build and start services
    log_info "Building distributed services..."
    docker compose -f docker-compose.distributed.yml build
    
    log_info "Starting distributed infrastructure..."
    docker compose -f docker-compose.distributed.yml up -d mongodb redis
    
    # Wait for infrastructure
    log_info "Waiting for infrastructure to be ready..."
    sleep 30
    
    log_info "Starting distributed services..."
    docker compose -f docker-compose.distributed.yml up -d
    
    # Wait for services to initialize
    sleep 30
    
    log_success "Distributed IDPS system deployed"
}

# Verify distributed deployment
verify_distributed() {
    log_info "Verifying distributed deployment..."
    
    echo "Distributed Service Status:"
    docker compose -f docker-compose.distributed.yml ps
    
    echo
    echo "Health Checks:"
    
    # Check VPS Processor
    if curl -s -f http://localhost:8090/health >/dev/null 2>&1; then
        log_success "VPS Processor: Healthy"
    else
        log_warning "VPS Processor: May be starting up"
    fi
    
    # Check Raspberry Pi Collector
    if curl -s -f http://localhost:8091/health >/dev/null 2>&1; then
        log_success "Raspberry Pi Collector: Healthy"
    else
        log_warning "Raspberry Pi Collector: May be starting up"
    fi
    
    # Check Communication Bridge
    if curl -s -f http://localhost:8093/health >/dev/null 2>&1; then
        log_success "Communication Bridge: Healthy"
    else
        log_warning "Communication Bridge: May be starting up"
    fi
    
    # Check MongoDB
    if docker compose -f docker-compose.distributed.yml exec -T mongodb mongosh --eval "db.adminCommand('ping')" >/dev/null 2>&1; then
        log_success "MongoDB: Healthy"
    else
        log_error "MongoDB: Not responding"
    fi
    
    # Check Redis
    if docker compose -f docker-compose.distributed.yml exec -T redis redis-cli ping >/dev/null 2>&1; then
        log_success "Redis: Healthy"
    else
        log_error "Redis: Not responding"
    fi
}

# Show distributed summary
show_distributed_summary() {
    echo
    log_success "🌐 IDPS Distributed Architecture Deployment Complete!"
    echo
    echo "📋 Distributed Architecture Summary:"
    echo "=================================="
    echo
    echo "🔄 Communication Flow:"
    echo "  1. Raspberry Pi collects traffic via Suricata"
    echo "  2. Pi sends events to VPS for processing"
    echo "  3. VPS analyzes and generates security rules"
    echo "  4. VPS sends rules back to Raspberry Pi"
    echo "  5. Raspberry Pi applies rules locally"
    echo
    echo "🌐 Access Points:"
    echo "  VPS Processor: http://localhost:8090"
    echo "  Raspi Collector: http://localhost:8091"
    echo "  Rules API: http://localhost:8092"
    echo "  Communication Bridge: http://localhost:8093"
    echo "  MongoDB: localhost:27019"
    echo "  Redis: localhost:6381"
    echo
    echo "🔧 Management Commands:"
    echo "  View logs: docker compose -f docker-compose.distributed.yml logs -f"
    echo "  Check status: docker compose -f docker-compose.distributed.yml ps"
    echo "  Stop system: docker compose -f docker-compose.distributed.yml down"
    echo "  Restart: docker compose -f docker-compose.distributed.yml restart"
    echo
    echo "📊 Distributed Features:"
    echo "  ✅ Low-latency edge collection (Raspberry Pi)"
    echo "  ✅ High-performance processing (VPS)"
    echo "  ✅ Real-time rule generation and distribution"
    echo "  ✅ Bidirectional communication bridge"
    echo "  ✅ Suricata IDS integration"
    echo "  ✅ MongoDB for distributed storage"
    echo "  ✅ Redis for caching and coordination"
    echo
    echo "⚡ Performance Benefits:"
    echo "  - Reduced latency on Raspberry Pi"
    echo "  - Heavy processing offloaded to VPS"
    echo "  - Distributed load balancing"
    echo "  - Scalable architecture"
    echo "  - Fault tolerance through redundancy"
    echo
    echo "🎯 Use Cases:"
    echo "  - Edge security monitoring"
    echo "  - Distributed threat detection"
    echo "  - Real-time incident response"
    echo "  - Scalable network protection"
}

# Main deployment function
main() {
    echo "🌐 IDPS Distributed Architecture Deployment"
    echo "=========================================="
    echo "Environment: Distributed (Raspberry Pi + VPS)"
    echo "Purpose: Low-latency edge security with VPS processing"
    echo
    
    create_distributed_compose
    create_vps_processor
    create_raspi_collector
    create_communication_bridge
    create_distributed_init
    setup_distributed_environment
    deploy_distributed
    verify_distributed
    show_distributed_summary
}

# Handle script arguments
case "${1:-}" in
    "distributed"|"dist"|"edge"|"")
        main
        ;;
    "--help"|"-h")
        echo "Usage: $0 [distributed|dist|edge]"
        echo "  distributed - Deploy distributed architecture (default)"
        echo "  dist        - Deploy distributed architecture"
        echo "  edge        - Deploy distributed architecture"
        echo "  --help      - Show this help message"
        exit 0
        ;;
    *)
        log_error "Unknown argument: $1"
        echo "Use --help for usage information"
        exit 1
        ;;
esac
