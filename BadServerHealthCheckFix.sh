#!/usr/bin/env bash

# Exit immediately if any command fails or if we hit an unset variable
set -euo pipefail

# ==============================================================================
# CONFIGURATION & THRESHOLDS
# ==============================================================================
LOGFILE="/home/jeff/server_health.log"
CPU_THRESHOLD=85
MEM_THRESHOLD=85
DISK_THRESHOLD=85

# ==============================================================================
# FUNCTIONS
# ==============================================================================

write_header() {
    # Fresh report, wipe out whatever was in the log last time
    {
        echo "--------------------------------------------------"
        echo "Server Health Report - $(date)"
        echo "--------------------------------------------------"
    } > "$LOGFILE"
}

check_cpu() {
    echo "Checking CPU..." >> "$LOGFILE"
    
    local cpu_idle cpu_usage
    # Grab the idle percentage from top
    cpu_idle=$(top -bn1 | grep -E "(Cpu\(s\):|%Cpu)" | awk '{for(i=1;i<=NF;i++) if($i=="id") print $(i-1)}')
    
    # Fallback parsing just in case top's output format is a bit weird on this distro
    if [[ -z "${cpu_idle:-}" ]]; then
        cpu_usage=$(top -bn1 | awk '/%?Cpu\(s\):/ {print 100 - $8}')
    else
        cpu_usage=$(awk "BEGIN {print 100 - $cpu_idle}")
    fi

    echo "CPU Usage: ${cpu_usage}%" >> "$LOGFILE"

    # Flag a warning if we're running hot past our threshold
    if awk "BEGIN {exit !($cpu_usage > $CPU_THRESHOLD)}"; then
        echo "WARNING: CPU usage is above ${CPU_THRESHOLD}%." >> "$LOGFILE"
    else
        echo "CPU usage is normal." >> "$LOGFILE"
    fi
    echo "" >> "$LOGFILE"
}

check_memory() {
    echo "Checking memory..." >> "$LOGFILE"
    local mem total perc

    # Pull used and total memory numbers in megabytes via free
    mem=$(free -m | awk '/Mem:/ {print $3}')
    total=$(free -m | awk '/Mem:/ {print $2}')

    # Calculate percentage safely, avoiding division by zero
    if [[ "$total" -gt 0 ]]; then
        perc=$(awk "BEGIN {printf \"%.2f\", ($mem / $total) * 100}")
    else
        perc="0.00"
    fi

    echo "Memory in use: ${perc}%" >> "$LOGFILE"

    # Complain if memory is getting eaten up past our limit
    if awk "BEGIN {exit !($perc > $MEM_THRESHOLD)}"; then
        echo "WARNING: Memory usage is above ${MEM_THRESHOLD}%." >> "$LOGFILE"
    else
        echo "Memory usage is normal." >> "$LOGFILE"
    fi
    echo "" >> "$LOGFILE"
}

check_disk() {
    echo "Checking disk usage..."

    # Check mounted drives, ignore virtual pseudo-filesystems, and flag full partitions
    df -h -x tmpfs -x devtmpfs | awk -v thresh="$DISK_THRESHOLD" 'NR>1 {
        use=$5; gsub("%","",use);
        print "Disk:", $1, "Used:", $5, "Mount:", $6;
        if (use+0 > thresh) {
            print "  -> WARNING: Partition " $6 " (" $1 ") exceeds " thresh "% capacity."
        }
    }' >> "$LOGFILE"
    echo "" >> "$LOGFILE"
}

check_network() {
    echo "Pinging google.com to test network..." >> "$LOGFILE"

    # Send one ping and check if we got a reply back
    if ping -c 1 -W 2 google.com &>/dev/null; then
        echo "Network is reachable." >> "$LOGFILE"
    else
        echo "WARNING: 100% packet loss to google.com. No response received. Check internet connection, DNS configuration, or local gateway." >> "$LOGFILE"
    fi
    echo "" >> "$LOGFILE"
}

summarize() {
    echo "Health check complete. Log saved to $LOGFILE" >> "$LOGFILE"
    echo "--------------------------------------------------"
    # Print the final report right to standard output
    cat "$LOGFILE"
}

main() {
    # Run through all the checks in order
    write_header
    check_cpu
    check_memory
    check_disk
    check_network
    summarize
}

# Kick things off
main
exit 0
