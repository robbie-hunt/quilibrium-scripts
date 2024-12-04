#!/bin/bash

# Get the machine's IP address
machine_ip="100.116.194.114"

# Find the number of workers associated with the machine's IP
workers_found=$(awk '/dataWorkerMultiaddrs:/ {in_section=1; next} in_section && $0 ~ /\/ip4\// {sub(/.*\/ip4\//, ""); sub(/\/.*/, ""); print}' ~/ceremonyclient/node/.config/config.yml | grep -c "$machine_ip")

# Extract the master's IP address
master_ip=$(awk '/dataWorkerMultiaddrs:/ {found=1; next} found && $0 !~ /^#/ && $0 ~ /\/ip4\// {split($0, arr, "/"); if (arr[3] ~ /^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$/) {print arr[3]; found=0; exit}}' ~/ceremonyclient/node/.config/config.yml)

# Count the current connections to the master
connections=$(ss -an | grep -c "$master_ip")

# Output the number of workers found for this machine
echo -e "Workers found for this Machine: $workers_found"

# Compare the number of connections with the number of workers found
if [ "$connections" -lt "$workers_found" ]; then
    echo -e "Established connections: $connections"
else
    echo -e "Established connections: $connections"
fi

# Check if all workers are connected
if [ "$connections" -eq "$workers_found" ]; then
    echo -e "All workers are connected!"
else
    difference=$((workers_found - connections))
    echo -e "$difference workers are not connected to the Master"
fi