#!/bin/bash
# Configuration files and port range
GSCONNECT_DEFAULT_PORTS="1714:1764"
TRUSTED_NETWORKS_FILE="/etc/NetworkManager/gsconnect_trusted_networks.conf"
LOG_FILE="/var/log/gsconnect_firewall.log"

# Logging Function
log_message() {
    local message="$1"
    local log_level="${2:-INFO}"
    if ! [ -f "$LOG_FILE" ]; then
        touch "$LOG_FILE" && chmod 640 "$LOG_FILE"
    fi
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $log_level - $message" >> "$LOG_FILE"
}

# Command Running Function
run_as_user() {
    # Local configuration currently hardcoded
    local USER_NAME=""
    local USER_ID=""
    local USER_DISPLAY=""
    local USER_DBUS_ADDRESS=""
    local USER_XAUTHORITY=""

    sudo -u "$USER_NAME" \
         DISPLAY="$USER_DISPLAY" \
         DBUS_SESSION_BUS_ADDRESS="$USER_DBUS_ADDRESS" \
         XAUTHORITY="$USER_XAUTHORITY" \
         "$@"
}

# Firewall Rule Management

# Opening Ports
enable_firewall_rules() {
    local conn_id="$1"
    local ports="$2"
    local iface="$3"
    local comment="GSConnect-auto for ${conn_id}"
    log_message "ENABLING rules for trusted network '$conn_id' on '$iface'"
    ufw allow in on "$iface" proto tcp to any port "$ports" comment "$comment"
    ufw allow in on "$iface" proto udp to any port "$ports" comment "$comment"
}

# Closing Ports
disable_firewall_rules() {
    log_message "Disabling all GSConnect-auto rules"
    while IFS= read -r rule_num; do
        echo "y" | ufw delete "$rule_num" >/dev/null 2>&1
    done < <(ufw status numbered | grep -oP '\[\s*(\d+)\].*GSConnect-auto' | grep -oP '\d+' | sort -rn)
}

# Network Trust and Verification
verify_network() {
    local conn_id="$1"
    local iface="$2"
    local trusted_line
    trusted_line=$(grep "^${conn_id}:" "$TRUSTED_NETWORKS_FILE" 2>/dev/null)

    if iw dev "$iface" link &>/dev/null; then # Wi-Fi
        local current_mac=$(iw dev "$iface" link | awk '/Connected to/ {print $3}' | tr -d ':')
        if [ -z "$current_mac" ]; then return 3; fi # Cannot get MAC
        if [ -z "$trusted_line" ]; then return 2; fi # Not trusted
        
        local saved_mac=$(echo "$trusted_line" | cut -d':' -f2)
        if [ "$saved_mac" = "$current_mac" ]; then
             return 0 # Trusted
        else
             return 1 # MAC Mismatch
        fi
    else # Ethernet
        if [ -n "$trusted_line" ]; then
            return 0 # Trusted
        else
            return 2 # Not trusted
        fi
    fi
}

# Saving Trusted Network and MAC Address
save_trusted_network() {
    local conn_id="$1"
    local iface="$2"
    local mac_to_save="none"

    if iw dev "$iface" link &>/dev/null; then
        mac_to_save=$(iw dev "$iface" link | awk '/Connected to/ {print $3}' | tr -d ':')
        if [ -z "$mac_to_save" ]; then return 1; fi
    fi

    local temp_file=$(mktemp)
    trap 'rm -f "$temp_file"' EXIT
    if [ -f "$TRUSTED_NETWORKS_FILE" ]; then
        grep -v "^${conn_id}:" "$TRUSTED_NETWORKS_FILE" > "$temp_file"
    fi
    
    echo "${conn_id}:${mac_to_save}" >> "$temp_file"
    chown root:root "$temp_file" && chmod 600 "$temp_file" && mv -f "$temp_file" "$TRUSTED_NETWORKS_FILE"
    trap - EXIT
    log_message "Saved '$conn_id' to trusted list"
}

# Main Logic
if [ "$(id -u)" -ne 0 ]; then exit 1; fi
if ! ufw status | grep -q "Status: active"; then exit 1; fi

IFACE="$1"
ACTION="$2"
CONN_ID="${CONNECTION_ID}"

log_message "--- Script called with: IFACE=$IFACE, ACTION=$ACTION, CONN_ID=$CONN_ID ---"

if [[ "$ACTION" == "down" || "$ACTION" == "pre-down" ]]; then
    disable_firewall_rules
    exit 0
fi

if [[ "$ACTION" == "up" ]]; then
    INTERFACE_TO_CHECK="${DEVICE_IFACE:-$IFACE}"
    if [ -z "$CONN_ID" ]; then exit 0; fi

    disable_firewall_rules
    
    verify_network "$CONN_ID" "$INTERFACE_TO_CHECK"
    network_status=$?

    case $network_status in
        0) # Trusted
            log_message "Network '$CONN_ID' is trusted. Enabling rules."
            enable_firewall_rules "$CONN_ID" "$GSCONNECT_DEFAULT_PORTS" "$INTERFACE_TO_CHECK"
            ;;
        1) # MAC Mismatch
            log_message "MAC MISMATCH for '$CONN_ID'. Ports will remain closed." "WARNING"
            run_as_user zenity --warning --title="GSConnect Security Warning" --text="The Wi-Fi network <b>$CONN_ID</b> is known, but its hardware address has changed.\n\nFor your security, ports will remain closed." --timeout="60" &
            ;;
        2) # Not Trusted
            log_message "Prompting user to trust new network '$CONN_ID'."
            if run_as_user zenity --question --title="GSConnect Network Trust" --text="Do you want to allow GSConnect on the network <b>$CONN_ID</b>?\n\nChoosing 'Allow and Trust' will save this network for future automatic connections." --ok-label="Allow and Trust" --cancel-label="Block" --timeout="60"; then
                log_message "User chose to trust '$CONN_ID'."
                save_trusted_network "$CONN_ID" "$INTERFACE_TO_CHECK"
                enable_firewall_rules "$CONN_ID" "$GSCONNECT_DEFAULT_PORTS" "$INTERFACE_TO_CHECK"
            else
                log_message "User chose to block network '$CONN_ID'."
            fi
            ;;
        3) # Could not read MAC
            log_message "Could not get MAC for '$CONN_ID'. Ports will remain closed." "ERROR"
            run_as_user zenity --error --title="GSConnect Security Error" --text="Could not verify the hardware address for the Wi-Fi network <b>$CONN_ID</b>.\n\nPorts will remain closed." --timeout="60" &
            ;;
    esac
fi

exit 0
