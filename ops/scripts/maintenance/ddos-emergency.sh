#!/bin/bash

# Emergency DDoS Response Script
# Automatically mitigates DDoS attacks and protects critical services

LOG_FILE="/var/log/ddos-response.log"
BLOCKED_IPS_FILE="/tmp/blocked_ips.txt"

echo "🚨 Emergency DDoS Response activated at $(date)" >> $LOG_FILE

# Function to block IP using iptables
block_ip() {
    local ip=$1
    if ! iptables -C INPUT -s $ip -j DROP 2>/dev/null; then
        iptables -A INPUT -s $ip -j DROP
        echo "$ip $(date)" >> $BLOCKED_IPS_FILE
        echo "🚫 Blocked IP: $ip" >> $LOG_FILE
    fi
}

# Function to detect high-rate IPs
detect_high_rate_ips() {
    # Analyze recent connections for suspicious patterns
    netstat -ntu | awk '{print $5}' | cut -d: -f1 | sort | uniq -c | sort -nr | head -20 > /tmp/conn_analysis.txt
    
    while read count ip; do
        # Block IPs with more than 100 connections
        if [ "$count" -gt 100 ]; then
            block_ip $ip
        fi
    done < /tmp/conn_analysis.txt
}

# Function to protect critical ports
protect_critical_ports() {
    # Rate limit SSH
    iptables -A INPUT -p tcp --dport 22 -m conntrack --ctstate NEW -m recent --set --name ssh_limit
    iptables -A INPUT -p tcp --dport 22 -m conntrack --ctstate NEW -m recent --update --seconds 60 --hitcount 4 --rttl --name ssh_limit -j DROP
    
    # Rate limit HTTP/HTTPS
    iptables -A INPUT -p tcp --dport 80 -m conntrack --ctstate NEW -m recent --set --name http_limit
    iptables -A INPUT -p tcp --dport 80 -m conntrack --ctstate NEW -m recent --update --seconds 10 --hitcount 20 --rttl --name http_limit -j DROP
    
    iptables -A INPUT -p tcp --dport 443 -m conntrack --ctstate NEW -m recent --set --name https_limit
    iptables -A INPUT -p tcp --dport 443 -m conntrack --ctstate NEW -m recent --update --seconds 10 --hitcount 20 --rttl --name https_limit -j DROP
    
    # Protect API ports
    iptables -A INPUT -p tcp --dport 8080 -m conntrack --ctstate NEW -m recent --set --name api_limit
    iptables -A INPUT -p tcp --dport 8080 -m conntrack --ctstate NEW -m recent --update --seconds 10 --hitcount 30 --rttl --name api_limit -j DROP
    
    iptables -A INPUT -p tcp --dport 8081 -m conntrack --ctstate NEW -m recent --set --name api_vps_limit
    iptables -A INPUT -p tcp --dport 8081 -m conntrack --ctstate NEW -m recent --update --seconds 10 --hitcount 30 --rttl --name api_vps_limit -j DROP
}

# Function to optimize system under attack
optimize_under_attack() {
    echo "⚡ Applying emergency optimizations..." >> $LOG_FILE
    
    # Increase connection tracking
    echo 1048576 > /proc/sys/net/netfilter/nf_conntrack_max
    
    # Reduce timeouts
    echo 30 > /proc/sys/net/netfilter/nf_conntrack_udp_timeout
    echo 300 > /proc/sys/net/netfilter/nf_conntrack_tcp_timeout_established
    
    # Enable SYN cookies
    echo 1 > /proc/sys/net/ipv4/tcp_syncookies
    
    # Reduce TCP timeouts
    echo 15 > /proc/sys/net/ipv4/tcp_fin_timeout
    echo 2 > /proc/sys/net/ipv4/tcp_syn_retries
    
    # Drop invalid packets
    iptables -A INPUT -m conntrack --ctstate INVALID -j DROP
    iptables -A FORWARD -m conntrack --ctstate INVALID -j DROP
}

# Function to protect Docker containers
protect_containers() {
    echo "🐳 Protecting Docker containers..." >> $LOG_FILE
    
    # Restart critical containers if they're failing
    for container in suricata-vps api-vps mongo; do
        if ! docker ps --format "table {{.Names}}" | grep -q "^$container$"; then
            echo "🔄 Restarting failed container: $container" >> $LOG_FILE
            docker start $container
        fi
    done
    
    # Limit container resource usage if under attack
    docker update --memory=1g --cpus=1.0 suricata-vps 2>/dev/null
    docker update --memory=512m --cpus=0.5 api-vps 2>/dev/null
}

# Main execution
echo "🛡️ Initializing DDoS protection measures..." >> $LOG_FILE

# Clear existing rate limits (if any)
iptables -F INPUT 2>/dev/null

# Apply protection measures
protect_critical_ports
optimize_under_attack
protect_containers

# Continuous monitoring loop
while true; do
    # Check system load
    load_avg=$(uptime | awk -F'load average:' '{print $2}' | awk '{print $1}' | sed 's/,//')
    if (( $(echo "$load_avg > 5.0" | bc -l) )); then
        echo "🔥 CRITICAL LOAD DETECTED: $load_avg" >> $LOG_FILE
        detect_high_rate_ips
    fi
    
    # Check connection count
    conn_count=$(netstat -an | grep -E "(ESTABLISHED|TIME_WAIT)" | wc -l)
    if [ "$conn_count" -gt 2000 ]; then
        echo "🌐 CRITICAL CONNECTION COUNT: $conn_count" >> $LOG_FILE
        detect_high_rate_ips
    fi
    
    # Check Suricata alerts
    if [ -f "/var/log/suricata/eve.json" ]; then
        recent_alerts=$(tail -100 /var/log/suricata/eve.json | jq -r '.event_type' | grep -c "alert" 2>/dev/null || echo "0")
        if [ "$recent_alerts" -gt 50 ]; then
            echo "🚨 CRITICAL ALERT RATE: $recent_alerts alerts" >> $LOG_FILE
            detect_high_rate_ips
        fi
    fi
    
    sleep 30  # Check every 30 seconds during attack
done
