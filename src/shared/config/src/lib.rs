//! Configuration management for IDPS services
//!
//! This module provides centralized configuration management
//! with validation, type safety, and environment variable support.

use anyhow::{Context, Result};
use serde::{Deserialize, Serialize};
use std::fs;
use std::path::Path;

pub use loader::*;
pub use parser::*;
pub use validator::*;

/// Configuration for edge services (Raspberry Pi)
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct EdgeConfig {
    /// Network interface for packet capture
    pub pcap_interface: String,

    /// WebSocket URL for VPS communication
    pub vps_ws_url: String,

    /// URL for network filter service
    pub network_filter_url: String,

    /// URL for rule engine service
    pub rule_engine_url: String,

    /// MongoDB connection URI
    pub mongodb_uri: String,

    /// Redis connection URL
    pub redis_url: String,

    /// VPS packet streaming WebSocket URL
    pub vps_packets_ws_url: String,

    /// Default block duration in hours
    pub default_block_duration_hours: u32,

    /// Log level for the service
    pub log_level: String,

    /// Service port for HTTP API
    pub service_port: u16,
}

impl Default for EdgeConfig {
    fn default() -> Self {
        Self {
            pcap_interface: "eth0".to_string(),
            vps_ws_url: "ws://localhost:8080/ws/raspi".to_string(),
            network_filter_url: "http://localhost:8092/api/v1".to_string(),
            rule_engine_url: "http://localhost:8094/api/v1".to_string(),
            mongodb_uri: "mongodb://localhost:27017".to_string(),
            redis_url: "redis://localhost:6379".to_string(),
            vps_packets_ws_url: "ws://localhost:8080/ws/packets".to_string(),
            default_block_duration_hours: 24,
            log_level: "info".to_string(),
            service_port: 8091,
        }
    }
}

impl EdgeConfig {
    /// Load edge configuration from environment variables
    pub fn from_env() -> Result<Self> {
        let config = Self {
            pcap_interface: std::env::var("PCAP_INTERFACE").unwrap_or_else(|_| "eth0".to_string()),
            vps_ws_url: std::env::var("VPS_WS_URL")
                .unwrap_or_else(|_| "ws://localhost:8080/ws/raspi".to_string()),
            network_filter_url: std::env::var("NETWORK_FILTER_URL")
                .unwrap_or_else(|_| "http://localhost:8092/api/v1".to_string()),
            rule_engine_url: std::env::var("RULE_ENGINE_URL")
                .unwrap_or_else(|_| "http://localhost:8094/api/v1".to_string()),
            mongodb_uri: std::env::var("MONGODB_URI")
                .unwrap_or_else(|_| "mongodb://localhost:27017".to_string()),
            redis_url: std::env::var("REDIS_URL")
                .unwrap_or_else(|_| "redis://localhost:6379".to_string()),
            vps_packets_ws_url: std::env::var("VPS_PACKETS_WS_URL")
                .unwrap_or_else(|_| "ws://localhost:8080/ws/packets".to_string()),
            default_block_duration_hours: std::env::var("DEFAULT_BLOCK_DURATION_HOURS")
                .ok()
                .and_then(|s| s.parse().ok())
                .unwrap_or(24),
            log_level: std::env::var("LOG_LEVEL").unwrap_or_else(|_| "info".to_string()),
            service_port: std::env::var("SERVICE_PORT")
                .ok()
                .and_then(|s| s.parse().ok())
                .unwrap_or(8091),
        };

        config.validate()?;
        Ok(config)
    }

    /// Load edge configuration from YAML file
    pub fn from_yaml_file<P: AsRef<Path>>(path: P) -> Result<Self> {
        let content = fs::read_to_string(path).context("Failed to read configuration file")?;
        let config: Self =
            serde_yaml::from_str(&content).context("Failed to parse YAML configuration")?;
        config.validate()?;
        Ok(config)
    }

    /// Load edge configuration with fallback: try YAML file first, then environment
    pub fn load_with_fallback<P: AsRef<Path>>(yaml_path: P) -> Result<Self> {
        match Self::from_yaml_file(&yaml_path) {
            Ok(config) => {
                log::info!(
                    "Loaded configuration from YAML file: {}",
                    yaml_path.as_ref().display()
                );
                Ok(config)
            }
            Err(e) => {
                log::warn!(
                    "Failed to load YAML config ({}), falling back to environment variables",
                    e
                );
                Self::from_env()
            }
        }
    }

    /// Validate configuration values
    pub fn validate(&self) -> Result<()> {
        if self.pcap_interface.is_empty() {
            return Err(anyhow::anyhow!("PCAP interface cannot be empty"));
        }

        if !self.vps_ws_url.starts_with("ws://") && !self.vps_ws_url.starts_with("wss://") {
            return Err(anyhow::anyhow!(
                "VPS WebSocket URL must start with ws:// or wss://"
            ));
        }

        if !self.vps_packets_ws_url.starts_with("ws://")
            && !self.vps_packets_ws_url.starts_with("wss://")
        {
            return Err(anyhow::anyhow!(
                "VPS packets WebSocket URL must start with ws:// or wss://"
            ));
        }

        if !self.network_filter_url.starts_with("http://")
            && !self.network_filter_url.starts_with("https://")
        {
            return Err(anyhow::anyhow!(
                "Network filter URL must start with http:// or https://"
            ));
        }

        if !self.rule_engine_url.starts_with("http://")
            && !self.rule_engine_url.starts_with("https://")
        {
            return Err(anyhow::anyhow!(
                "Rule engine URL must start with http:// or https://"
            ));
        }

        if self.mongodb_uri.is_empty() {
            return Err(anyhow::anyhow!("MongoDB URI cannot be empty"));
        }

        if self.redis_url.is_empty() {
            return Err(anyhow::anyhow!("Redis URL cannot be empty"));
        }

        if self.default_block_duration_hours == 0 {
            return Err(anyhow::anyhow!(
                "Default block duration must be greater than 0"
            ));
        }

        if self.service_port == 0 {
            return Err(anyhow::anyhow!("Service port must be greater than 0"));
        }

        Ok(())
    }
}

/// Configuration for cloud services (VPS)
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CloudConfig {
    /// MongoDB connection URI
    pub mongodb_uri: String,

    /// Redis connection URL
    pub redis_url: String,

    /// Whether automatic blocking is enabled
    pub auto_block_enabled: bool,

    /// Threat intelligence feed URL (optional)
    pub threat_intel_url: Option<String>,

    /// API key for authentication (optional)
    pub api_key: Option<String>,

    /// Log level for the service
    pub log_level: String,

    /// Service port for HTTP API
    pub service_port: u16,

    /// WebSocket port for real-time communication
    pub websocket_port: u16,

    /// Maximum packets per second per connection
    pub max_packets_per_second: u32,

    /// Rate limiting enablement
    pub rate_limiting_enabled: bool,

    /// TLS certificate path (optional)
    pub tls_cert_path: Option<String>,

    /// TLS private key path (optional)
    pub tls_key_path: Option<String>,
}

impl Default for CloudConfig {
    fn default() -> Self {
        Self {
            mongodb_uri: "mongodb://localhost:27017".to_string(),
            redis_url: "redis://localhost:6379".to_string(),
            auto_block_enabled: false,
            threat_intel_url: None,
            api_key: None,
            log_level: "info".to_string(),
            service_port: 8080,
            websocket_port: 8080,
            max_packets_per_second: 10000,
            rate_limiting_enabled: true,
            tls_cert_path: None,
            tls_key_path: None,
        }
    }
}

impl CloudConfig {
    /// Load cloud configuration from environment variables
    pub fn from_env() -> Result<Self> {
        let config = Self {
            mongodb_uri: std::env::var("MONGODB_URI")
                .unwrap_or_else(|_| "mongodb://localhost:27017".to_string()),
            redis_url: std::env::var("REDIS_URL")
                .unwrap_or_else(|_| "redis://localhost:6379".to_string()),
            auto_block_enabled: std::env::var("AUTO_BLOCK_ENABLED")
                .ok()
                .and_then(|s| s.parse().ok())
                .unwrap_or(false),
            threat_intel_url: std::env::var("THREAT_INTEL_URL").ok(),
            api_key: std::env::var("API_KEY").ok(),
            log_level: std::env::var("LOG_LEVEL").unwrap_or_else(|_| "info".to_string()),
            service_port: std::env::var("SERVICE_PORT")
                .ok()
                .and_then(|s| s.parse().ok())
                .unwrap_or(8080),
            websocket_port: std::env::var("WEBSOCKET_PORT")
                .ok()
                .and_then(|s| s.parse().ok())
                .unwrap_or(8080),
            max_packets_per_second: std::env::var("MAX_PACKETS_PER_SECOND")
                .ok()
                .and_then(|s| s.parse().ok())
                .unwrap_or(10000),
            rate_limiting_enabled: std::env::var("RATE_LIMITING_ENABLED")
                .ok()
                .and_then(|s| s.parse().ok())
                .unwrap_or(true),
            tls_cert_path: std::env::var("TLS_CERT_PATH").ok(),
            tls_key_path: std::env::var("TLS_KEY_PATH").ok(),
        };

        config.validate()?;
        Ok(config)
    }

    /// Load cloud configuration from YAML file
    pub fn from_yaml_file<P: AsRef<Path>>(path: P) -> Result<Self> {
        let content = fs::read_to_string(path).context("Failed to read configuration file")?;
        let config: Self =
            serde_yaml::from_str(&content).context("Failed to parse YAML configuration")?;
        config.validate()?;
        Ok(config)
    }

    /// Load cloud configuration with fallback: try YAML file first, then environment
    pub fn load_with_fallback<P: AsRef<Path>>(yaml_path: P) -> Result<Self> {
        match Self::from_yaml_file(&yaml_path) {
            Ok(config) => {
                log::info!(
                    "Loaded configuration from YAML file: {}",
                    yaml_path.as_ref().display()
                );
                Ok(config)
            }
            Err(e) => {
                log::warn!(
                    "Failed to load YAML config ({}), falling back to environment variables",
                    e
                );
                Self::from_env()
            }
        }
    }

    /// Validate configuration values
    pub fn validate(&self) -> Result<()> {
        if self.mongodb_uri.is_empty() {
            return Err(anyhow::anyhow!("MongoDB URI cannot be empty"));
        }

        if self.redis_url.is_empty() {
            return Err(anyhow::anyhow!("Redis URL cannot be empty"));
        }

        if self.service_port == 0 {
            return Err(anyhow::anyhow!("Service port must be greater than 0"));
        }

        if self.websocket_port == 0 {
            return Err(anyhow::anyhow!("WebSocket port must be greater than 0"));
        }

        if self.max_packets_per_second == 0 {
            return Err(anyhow::anyhow!(
                "Max packets per second must be greater than 0"
            ));
        }

        // Check TLS configuration consistency
        let tls_has_cert = self.tls_cert_path.is_some();
        let tls_has_key = self.tls_key_path.is_some();

        if tls_has_cert != tls_has_key {
            return Err(anyhow::anyhow!(
                "Both TLS certificate and key must be provided, or neither"
            ));
        }

        Ok(())
    }

    /// Check if TLS is enabled
    pub fn tls_enabled(&self) -> bool {
        self.tls_cert_path.is_some() && self.tls_key_path.is_some()
    }
}

/// Configuration parser utilities
pub mod parser {
    use super::*;

    /// Parse log level string to log::LevelFilter
    pub fn parse_log_level(level: &str) -> Result<log::LevelFilter> {
        match level.to_lowercase().as_str() {
            "error" => Ok(log::LevelFilter::Error),
            "warn" => Ok(log::LevelFilter::Warn),
            "info" => Ok(log::LevelFilter::Info),
            "debug" => Ok(log::LevelFilter::Debug),
            "trace" => Ok(log::LevelFilter::Trace),
            _ => Err(anyhow::anyhow!("Invalid log level: {}", level)),
        }
    }

    /// Parse duration string to seconds
    pub fn parse_duration_seconds(duration: &str) -> Result<u64> {
        // Support formats like "24h", "30m", "60s"
        let duration = duration.trim().to_lowercase();

        if let Some(num_str) = duration.strip_suffix('h') {
            let hours: u64 = num_str.parse().context("Invalid hour format")?;
            Ok(hours * 3600)
        } else if let Some(num_str) = duration.strip_suffix('m') {
            let minutes: u64 = num_str.parse().context("Invalid minute format")?;
            Ok(minutes * 60)
        } else if let Some(num_str) = duration.strip_suffix('s') {
            let seconds: u64 = num_str.parse().context("Invalid second format")?;
            Ok(seconds)
        } else {
            // Assume it's already in seconds
            let seconds: u64 = duration.parse().context("Invalid duration format")?;
            Ok(seconds)
        }
    }
}

/// Configuration validation utilities
pub mod validator {
    use super::*;

    /// Validate URL format
    pub fn validate_url(url: &str, schemes: &[&str]) -> Result<()> {
        if url.is_empty() {
            return Err(anyhow::anyhow!("URL cannot be empty"));
        }

        let valid_scheme = schemes.iter().any(|&scheme| url.starts_with(scheme));
        if !valid_scheme {
            return Err(anyhow::anyhow!(
                "URL must start with one of: {}",
                schemes.join(", ")
            ));
        }

        Ok(())
    }

    /// Validate port number
    pub fn validate_port(port: u16) -> Result<()> {
        if port == 0 {
            return Err(anyhow::anyhow!("Port cannot be 0"));
        }

        if port < 1024 {
            log::warn!("Using privileged port: {}", port);
        }

        Ok(())
    }

    /// Validate MongoDB URI
    pub fn validate_mongodb_uri(uri: &str) -> Result<()> {
        if uri.is_empty() {
            return Err(anyhow::anyhow!("MongoDB URI cannot be empty"));
        }

        if !uri.starts_with("mongodb://") && !uri.starts_with("mongodb+srv://") {
            return Err(anyhow::anyhow!(
                "MongoDB URI must start with mongodb:// or mongodb+srv://"
            ));
        }

        Ok(())
    }
}

/// Configuration loader utilities
pub mod loader {
    use super::*;

    /// Load configuration from multiple sources with precedence
    pub fn load_config<T: for<'de> Deserialize<'de> + Validate>(
        yaml_path: Option<&str>,
        env_fallback: bool,
    ) -> Result<T>
    where
        T: Default,
    {
        // Try YAML file first if provided
        if let Some(path) = yaml_path {
            match std::fs::read_to_string(path) {
                Ok(content) => {
                    let config: T = serde_yaml::from_str(&content)
                        .context("Failed to parse YAML configuration")?;
                    config.validate()?;
                    return Ok(config);
                }
                Err(e) => {
                    log::warn!("Failed to load YAML config from {}: {}", path, e);
                }
            }
        }

        // Fall back to environment variables or defaults
        if env_fallback {
            // This would need to be implemented per config type
            log::info!("Using environment variables for configuration");
        }

        // Use default configuration
        log::info!("Using default configuration");
        let config = T::default();
        config.validate()?;
        Ok(config)
    }
}

/// Trait for configuration validation
pub trait Validate {
    /// Validate the configuration
    fn validate(&self) -> Result<()>;
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::env;

    #[test]
    fn test_edge_config_default() {
        let config = EdgeConfig::default();
        assert_eq!(config.pcap_interface, "eth0");
        assert_eq!(config.default_block_duration_hours, 24);
        assert!(config.validate().is_ok());
    }

    #[test]
    fn test_cloud_config_default() {
        let config = CloudConfig::default();
        assert!(!config.auto_block_enabled);
        assert_eq!(config.service_port, 8080);
        assert!(config.validate().is_ok());
    }

    #[test]
    fn test_edge_config_validation() {
        let mut config = EdgeConfig::default();

        // Test invalid WebSocket URL
        config.vps_ws_url = "invalid-url".to_string();
        assert!(config.validate().is_err());

        // Test empty MongoDB URI
        config.vps_ws_url = "ws://localhost:8080/ws/raspi".to_string();
        config.mongodb_uri = "".to_string();
        assert!(config.validate().is_err());
    }

    #[test]
    fn test_cloud_config_validation() {
        let mut config = CloudConfig::default();

        // Test invalid MongoDB URI
        config.mongodb_uri = "invalid-uri".to_string();
        assert!(config.validate().is_err());

        // Test TLS inconsistency
        config.mongodb_uri = "mongodb://localhost:27017".to_string();
        config.tls_cert_path = Some("/path/to/cert.pem".to_string());
        config.tls_key_path = None;
        assert!(config.validate().is_err());
    }

    #[test]
    fn test_parser_utilities() {
        assert_eq!(
            parser::parse_log_level("info").unwrap(),
            log::LevelFilter::Info
        );
        assert_eq!(
            parser::parse_log_level("DEBUG").unwrap(),
            log::LevelFilter::Debug
        );
        assert!(parser::parse_log_level("invalid").is_err());

        assert_eq!(parser::parse_duration_seconds("24h").unwrap(), 86400);
        assert_eq!(parser::parse_duration_seconds("30m").unwrap(), 1800);
        assert_eq!(parser::parse_duration_seconds("60s").unwrap(), 60);
        assert_eq!(parser::parse_duration_seconds("120").unwrap(), 120);
    }

    #[test]
    fn test_validator_utilities() {
        assert!(validator::validate_url("http://localhost:8080", &["http://", "https://"]).is_ok());
        assert!(validator::validate_url("ftp://localhost", &["http://", "https://"]).is_err());

        assert!(validator::validate_port(8080).is_ok());
        assert!(validator::validate_port(0).is_err());

        assert!(validator::validate_mongodb_uri("mongodb://localhost:27017").is_ok());
        assert!(validator::validate_mongodb_uri("http://localhost:27017").is_err());
    }
}
