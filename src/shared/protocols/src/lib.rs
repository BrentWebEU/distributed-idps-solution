//! Communication protocols for IDPS services
//!
//! Standardized WebSocket message types used between VPS ↔ Raspi and
//! VPS ↔ Dashboard connections.

use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use uuid::Uuid;

// ─── Message envelope ────────────────────────────────────────────────────────

/// Top-level WebSocket message envelope.
/// The `payload` field contains one of the typed variants below.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct WsMessage {
    pub id: String,
    pub timestamp: DateTime<Utc>,
    #[serde(flatten)]
    pub payload: WsPayload,
}

impl WsMessage {
    pub fn new(payload: WsPayload) -> Self {
        Self {
            id: Uuid::new_v4().to_string(),
            timestamp: Utc::now(),
            payload,
        }
    }
}

// ─── Payload variants ─────────────────────────────────────────────────────────

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(tag = "type", rename_all = "snake_case")]
pub enum WsPayload {
    /// VPS → Raspi: block a specific IP immediately
    BlockCommand(BlockCommand),
    /// VPS → Raspi: remove an existing block
    UnblockCommand(UnblockCommand),
    /// VPS → Raspi: install/update a Suricata or iptables rule
    RuleUpdate(RuleUpdate),
    /// Raspi → VPS: acknowledgement of a command
    CommandAck(CommandAck),
    /// VPS → Dashboard: a new security alert
    Alert(AlertNotification),
    /// VPS → Dashboard: system metrics snapshot
    Metrics(MetricsSnapshot),
    /// Either direction: keep-alive ping
    Ping(Heartbeat),
    /// Either direction: keep-alive pong
    Pong(Heartbeat),
}

// ─── VPS → Raspi messages ─────────────────────────────────────────────────────

/// Block a single IP on the Raspi (iptables DROP + optional Suricata rule).
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct BlockCommand {
    /// IP address to block
    pub ip: String,
    /// Human-readable reason (logged on Raspi)
    pub reason: String,
    /// How many seconds to keep the block; 0 = permanent until explicit unblock
    pub duration_secs: u64,
    /// Also generate a Suricata rule for this block
    pub apply_suricata_rule: bool,
    /// Severity 1-10 used to decide urgency
    pub severity: u8,
    /// Originating detection event ID (for correlation)
    pub detection_event_id: Option<String>,
}

/// Remove an existing IP block on the Raspi.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct UnblockCommand {
    pub ip: String,
    pub reason: String,
    /// Admin user who triggered the unblock (for audit log)
    pub unblocked_by: Option<String>,
}

/// Install or update a Suricata rule on the Raspi.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct RuleUpdate {
    pub rule_id: String,
    pub action: RuleAction,
    /// Suricata rule text (used when action = Add or Update)
    pub suricata_rule: Option<String>,
    /// iptables rule (used when action = Add or Update)
    pub iptables_rule: Option<String>,
    pub description: String,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
#[serde(rename_all = "snake_case")]
pub enum RuleAction {
    Add,
    Update,
    Remove,
}

// ─── Raspi → VPS messages ─────────────────────────────────────────────────────

/// Acknowledgement that a command was received and applied (or failed).
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CommandAck {
    /// ID of the WsMessage being acknowledged
    pub command_id: String,
    pub success: bool,
    pub error: Option<String>,
    /// Raspi device identifier
    pub raspi_id: String,
}

// ─── VPS → Dashboard messages ─────────────────────────────────────────────────

/// Real-time security alert broadcast to admin dashboard.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AlertNotification {
    pub event_id: String,
    pub severity: AlertSeverity,
    pub category: String,
    pub message: String,
    pub src_ip: String,
    pub dest_ip: Option<String>,
    pub src_port: Option<u16>,
    pub dest_port: Option<u16>,
    pub protocol: Option<String>,
    pub auto_blocked: bool,
    pub timestamp: DateTime<Utc>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
#[serde(rename_all = "lowercase")]
pub enum AlertSeverity {
    Critical,
    High,
    Medium,
    Low,
    Info,
}

impl AlertSeverity {
    pub fn from_threat_level(level: u8) -> Self {
        match level {
            9..=10 => AlertSeverity::Critical,
            7..=8 => AlertSeverity::High,
            5..=6 => AlertSeverity::Medium,
            3..=4 => AlertSeverity::Low,
            _ => AlertSeverity::Info,
        }
    }
}

/// System metrics snapshot sent to dashboard every few seconds.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct MetricsSnapshot {
    pub events_per_second: f64,
    pub alerts_per_minute: f64,
    pub blocked_ips_count: u64,
    pub cpu_usage_percent: f64,
    pub memory_usage_mb: f64,
    pub raspi_connected: bool,
    pub vps_processing_rate: f64,
}

// ─── Heartbeat ────────────────────────────────────────────────────────────────

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Heartbeat {
    pub sender_id: String,
}
