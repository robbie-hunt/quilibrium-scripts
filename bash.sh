machine_ip=$(curl -s ifconfig.me | tr -d '\n')
workers_found=$(awk -v ip="$machine_ip" '$0 ~ "/ip4/" ip "/tcp/" {match($0, /\/tcp\/([0-9]+)/, arr); last_port=arr[1]} END {if (last_port) print last_port - 40000}' /root/ceremonyclient/node/.config/config.yml)
master_ip=$(awk '/dataWorkerMultiaddrs:/ {getline; if ($0 ~ /\/ip4\/([0-9]+\.[0-9]+\.[0-9]+\.[0-9]+)/) { match($0, /\/ip4\/([0-9]+\.[0-9]+\.[0-9]+\.[0-9]+)/, arr); print arr[1] } }' /root/ceremonyclient/node/.config/config.yml)
connections=$(ss -an | grep -c "$master_ip")

echo -e "\e[36mWorkers found for this Machine:\e[0m \e[32m$workers_found\e[0m"

if [ "$connections" -lt "$workers_found" ]; then
  echo -e "\e[36mEstablished connections:\e[0m \e[31m$connections\e[0m"
else
  echo -e "\e[36mEstablished connections:\e[0m \e[32m$connections\e[0m"
fi

if [ "$connections" -eq "$workers_found" ]; then
  echo -e "\e[32mAll workers are connected! ✅\e[0m"
else difference=$((workers_found - connections))
  echo -e "\e[31m$difference workers are not connected to the Master ⚠️\e[0m"
fi