#!/bin/bash

# DDoS Resilience System Optimization Script
# This script optimizes system parameters for DDoS resilience

echo "🔧 Applying DDoS resilience optimizations..."

# Backup current sysctl settings
sudo sysctl -a > /tmp/sysctl_backup_$(date +%Y%m%d_%H%M%S).txt

# Network stack optimizations for high connection loads
echo "📡 Optimizing network stack..."
sudo sysctl -w net.core.rmem_max=134217728
sudo sysctl -w net.core.wmem_max=134217728
sudo sysctl -w net.ipv4.tcp_rmem="4096 65536 134217728"
sudo sysctl -w net.ipv4.tcp_wmem="4096 65536 134217728"
sudo sysctl -w net.core.netdev_max_backlog=5000
sudo sysctl -w net.ipv4.tcp_max_syn_backlog=65536
sudo sysctl -w net.ipv4.tcp_syncookies=1
sudo sysctl -w net.ipv4.tcp_syn_retries=2
sudo sysctl -w net.ipv4.tcp_synack_retries=2
sudo sysctl -w net.ipv4.tcp_fin_timeout=15
sudo sysctl -w net.ipv4.tcp_keepalive_time=600
sudo sysctl -w net.ipv4.tcp_keepalive_probes=3
sudo sysctl -w net.ipv4.tcp_keepalive_intvl=15

# Connection tracking optimizations
echo "🔍 Optimizing connection tracking..."
sudo sysctl -w net.netfilter.nf_conntrack_max=1048576
sudo sysctl -w net.netfilter.nf_conntrack_tcp_timeout_established=7200
sudo sysctl -w net.netfilter.nf_conntrack_udp_timeout=30
sudo sysctl -w net.netfilter.nf_conntrack_udp_timeout_stream=180

# File descriptor and process limits
echo "📁 Optimizing file descriptors and process limits..."
echo "* soft nofile 1048576" | sudo tee -a /etc/security/limits.conf
echo "* hard nofile 2097152" | sudo tee -a /etc/security/limits.conf
echo "* soft nproc 32768" | sudo tee -a /etc/security/limits.conf
echo "* hard nproc 65536" | sudo tee -a /etc/security/limits.conf

# Kernel parameters for high load
echo "⚙️ Optimizing kernel parameters..."
sudo sysctl -w kernel.pid_max=4194303
sudo sysctl -w vm.swappiness=10
sudo sysctl -w vm.dirty_ratio=15
sudo sysctl -w vm.dirty_background_ratio=5

# Make sysctl settings persistent
echo "💾 Making settings persistent..."
cat << EOF | sudo tee /etc/sysctl.d/99-ddos-resilience.conf
# DDoS Resilience Configuration
net.core.rmem_max = 134217728
net.core.wmem_max = 134217728
net.ipv4.tcp_rmem = 4096 65536 134217728
net.ipv4.tcp_wmem = 4096 65536 134217728
net.core.netdev_max_backlog = 5000
net.ipv4.tcp_max_syn_backlog = 65536
net.ipv4.tcp_syncookies = 1
net.ipv4.tcp_syn_retries = 2
net.ipv4.tcp_synack_retries = 2
net.ipv4.tcp_fin_timeout = 15
net.ipv4.tcp_keepalive_time = 600
net.ipv4.tcp_keepalive_probes = 3
net.ipv4.tcp_keepalive_intvl = 15
net.netfilter.nf_conntrack_max = 1048576
net.netfilter.nf_conntrack_tcp_timeout_established = 7200
net.netfilter.nf_conntrack_udp_timeout = 30
net.netfilter.nf_conntrack_udp_timeout_stream = 180
kernel.pid_max = 4194303
vm.swappiness = 10
vm.dirty_ratio = 15
vm.dirty_background_ratio = 5
EOF

# Apply persistent settings
sudo sysctl -p /etc/sysctl.d/99-ddos-resilience.conf

echo "✅ DDoS resilience optimizations applied successfully!"
echo "🔄 System will need to be rebooted for all limits to take effect."
echo "📊 Current connection tracking table size: $(cat /proc/sys/net/netfilter/nf_conntrack_count)"
echo "🔧 Max connection tracking entries: $(cat /proc/sys/net/netfilter/nf_conntrack_max)"
