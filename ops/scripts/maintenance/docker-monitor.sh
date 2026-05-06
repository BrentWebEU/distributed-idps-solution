#!/bin/bash

# Docker Resource Monitor and Auto-Recovery Script
# Monitors Docker containers and automatically recovers from resource exhaustion

LOG_FILE="/var/log/docker-monitor.log"
ALERT_THRESHOLD_CPU=80
ALERT_THRESHOLD_MEM=85
ALERT_THRESHOLD_CONN=1000

echo "🐳 Docker Resource Monitor started at $(date)" >> $LOG_FILE

while true; do
    # Check if Docker daemon is running
    if ! docker info >/dev/null 2>&1; then
        echo "⚠️ Docker daemon not running, attempting restart..." >> $LOG_FILE
        sudo systemctl restart docker
        sleep 30
        continue
    fi

    # Monitor container resource usage
    for container in suricata-vps api-vps mongo angular-admin; do
        if docker ps --format "table {{.Names}}" | grep -q "^$container$"; then
            # Get container stats
            stats=$(docker stats --no-stream --format "table {{.CPUPerc}}\t{{.MemPerc}}\t{{.NetIO}}" $container 2>/dev/null | tail -n1)
            
            if [ ! -z "$stats" ]; then
                cpu_percent=$(echo $stats | awk '{print $1}' | sed 's/%//')
                mem_percent=$(echo $stats | awk '{print $2}' | sed 's/%//')
                
                # Check CPU threshold
                if (( $(echo "$cpu_percent > $ALERT_THRESHOLD_CPU" | bc -l) )); then
                    echo "🔥 HIGH CPU ALERT: $container at ${cpu_percent}% CPU" >> $LOG_FILE
                    # Log top processes inside container
                    docker exec $container top -b -n1 | head -20 >> $LOG_FILE
                fi
                
                # Check Memory threshold
                if (( $(echo "$mem_percent > $ALERT_THRESHOLD_MEM" | bc -l) )); then
                    echo "💾 HIGH MEMORY ALERT: $container at ${mem_percent}% Memory" >> $LOG_FILE
                    # Check for memory leaks
                    docker exec $container cat /proc/meminfo >> $LOG_FILE
                fi
            fi
        else
            echo "❌ Container $container is not running" >> $LOG_FILE
            # Attempt to restart critical containers
            if [[ "$container" == "suricata-vps" || "$container" == "api-vps" || "$container" == "mongo" ]]; then
                echo "🔄 Attempting to restart critical container: $container" >> $LOG_FILE
                docker start $container 2>/dev/null
            fi
        fi
    done

    # Check system connection count
    conn_count=$(netstat -an | grep -E "(ESTABLISHED|TIME_WAIT)" | wc -l)
    if [ "$conn_count" -gt "$ALERT_THRESHOLD_CONN" ]; then
        echo "🌐 HIGH CONNECTION COUNT: $conn_count active connections" >> $LOG_FILE
        
        # Log top connection sources
        netstat -an | grep ESTABLISHED | awk '{print $5}' | cut -d: -f1 | sort | uniq -c | sort -nr | head -10 >> $LOG_FILE
    fi

    # Check system load
    load_avg=$(uptime | awk -F'load average:' '{print $2}' | awk '{print $1}' | sed 's/,//')
    if (( $(echo "$load_avg > 2.0" | bc -l) )); then
        echo "⚖️ HIGH SYSTEM LOAD: $load_avg" >> $LOG_FILE
        # Log top processes
        ps aux --sort=-%cpu | head -10 >> $LOG_FILE
    fi

    # Check disk space
    disk_usage=$(df / | awk 'NR==2 {print $5}' | sed 's/%//')
    if [ "$disk_usage" -gt 90 ]; then
        echo "💿 HIGH DISK USAGE: ${disk_usage}%" >> $LOG_FILE
        # Clean up Docker logs
        docker system prune -f --volumes >> $LOG_FILE
    fi

    # Check for DDoS patterns in logs
    if [ -f "/var/log/suricata/eve.json" ]; then
        recent_alerts=$(tail -1000 /var/log/suricata/eve.json | jq -r '.event_type' | grep -c "alert" 2>/dev/null || echo "0")
        if [ "$recent_alerts" -gt 100 ]; then
            echo "🚨 HIGH ALERT RATE: $recent_alerts alerts in recent logs" >> $LOG_FILE
        fi
    fi

    echo "✅ Monitor check completed at $(date)" >> $LOG_FILE
    sleep 60  # Check every minute
done
