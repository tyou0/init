#!/bin/bash

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

get_wifi_interface() {
    local iface
    iface=$(networksetup -listallhardwareports 2>/dev/null | awk '/Wi-Fi|AirPort/{getline; print $2}')
    echo "${iface:-en0}"
}

INTERFACE=$(get_wifi_interface)

get_current_ssid() {
    local ssid=""

    # Method 1: networksetup (works on older macOS)
    local raw
    raw=$(networksetup -getairportnetwork "$INTERFACE" 2>/dev/null)
    if ! echo "$raw" | grep -qi "not associated\|no network"; then
        ssid=$(echo "$raw" | sed 's/^.*: //')
    fi

    # Method 2: ipconfig getsummary (works on macOS Sonoma+)
    if [ -z "$ssid" ]; then
        ssid=$(ipconfig getsummary "$INTERFACE" 2>/dev/null | awk -F': ' '/  SSID : /{print $2}')
    fi

    # Method 3: system_profiler (slowest but most reliable)
    if [ -z "$ssid" ]; then
        ssid=$(system_profiler SPAirPortDataType 2>/dev/null | awk '/Current Network Information:/{getline; gsub(/^ +| *:$/,""); print; exit}')
    fi

    echo "$ssid"
}

get_ip_address() {
    ipconfig getifaddr "$INTERFACE" 2>/dev/null
}

usage() {
    echo -e "${CYAN}WiFi CLI for macOS${NC}"
    echo ""
    echo "Usage: $(basename "$0") <command> [options]"
    echo ""
    echo "Commands:"
    echo "  status              Show current WiFi status"
    echo "  on                  Turn WiFi on"
    echo "  off                 Turn WiFi off"
    echo "  scan                Scan for available networks"
    echo "  connect <SSID>      Connect to a network (prompts for password)"
    echo "  connect <SSID> <PW> Connect to a network with password"
    echo "  disconnect          Disconnect from current network"
    echo "  info                Show detailed connection info"
    echo "  saved               List saved/known networks"
    echo "  forget <SSID>       Forget a saved network"
    echo "  help                Show this help message"
}

wifi_status() {
    local power
    power=$(networksetup -getairportpower "$INTERFACE" 2>/dev/null)

    if echo "$power" | grep -q "On"; then
        echo -e "WiFi Power: ${GREEN}On${NC}"
        echo -e "Interface:  ${CYAN}${INTERFACE}${NC}"

        local ssid
        ssid=$(get_current_ssid)

        if [ -n "$ssid" ]; then
            echo -e "Connected:  ${GREEN}${ssid}${NC}"
            local ip
            ip=$(get_ip_address)
            if [ -n "$ip" ]; then
                echo -e "IP Address: ${CYAN}${ip}${NC}"
            fi
        else
            echo -e "Connected:  ${RED}Not connected${NC}"
        fi
    else
        echo -e "WiFi Power: ${RED}Off${NC}"
    fi
}

wifi_on() {
    echo "Turning WiFi on..."
    networksetup -setairportpower "$INTERFACE" on
    sleep 2
    echo -e "${GREEN}WiFi is on${NC}"
    wifi_status
}

wifi_off() {
    echo "Turning WiFi off..."
    networksetup -setairportpower "$INTERFACE" off
    sleep 1
    echo -e "${RED}WiFi is off${NC}"
}

wifi_scan() {
    echo -e "${CYAN}Scanning for networks...${NC}"
    echo ""

    local airport="/System/Library/PrivateFrameworks/Apple80211.framework/Versions/Current/Resources/airport"

    if [ -x "$airport" ]; then
        "$airport" -s 2>/dev/null
    else
        # Fallback: use system_profiler
        echo -e "${YELLOW}Note: Using system_profiler (slower). 'airport' tool not available.${NC}"
        echo ""
        system_profiler SPAirPortDataType 2>/dev/null | awk '
        /Other Local Wi-Fi Networks:/,0 {
            if (/^ {16}[^ ]/) {
                gsub(/^ +| *:$/, "")
                name=$0
            }
            if (/PHY Mode/) { phy=$NF }
            if (/Channel:/) { ch=$NF }
            if (/Signal \/ Noise/) {
                sig=$NF
                printf "%-35s  Channel: %-6s  Signal: %s  PHY: %s\n", name, ch, sig, phy
            }
        }'
    fi
}

wifi_connect() {
    local ssid="$1"
    local password="$2"

    if [ -z "$ssid" ]; then
        echo -e "${RED}Error: Provide an SSID${NC}"
        echo "Usage: wifi connect <SSID> [password]"
        exit 1
    fi

    if [ -z "$password" ]; then
        echo -n "Password for '${ssid}': "
        read -s password
        echo ""
    fi

    echo -e "Connecting to ${YELLOW}${ssid}${NC}..."
    networksetup -setairportnetwork "$INTERFACE" "$ssid" "$password" 2>/dev/null

    # Wait and retry detection multiple times
    local connected=""
    for i in 1 2 3 4 5; do
        sleep 2
        connected=$(get_current_ssid)
        if [ -n "$connected" ]; then
            break
        fi
    done

    if [ -n "$connected" ]; then
        echo -e "${GREEN}Connected to ${connected}${NC}"
        local ip
        ip=$(get_ip_address)
        if [ -n "$ip" ]; then
            echo -e "IP Address: ${CYAN}${ip}${NC}"
        fi
    else
        echo -e "${RED}Connection may have failed.${NC}"
        echo ""
        echo "Troubleshooting:"
        echo "  1. Check SSID and password are correct (case-sensitive)"
        echo "  2. wifi forget \"${ssid}\" && wifi connect \"${ssid}\""
        echo "  3. wifi off && sleep 2 && wifi on && sleep 3 && wifi connect \"${ssid}\""
        exit 1
    fi
}

wifi_disconnect() {
    echo "Disconnecting..."
    local airport="/System/Library/PrivateFrameworks/Apple80211.framework/Versions/Current/Resources/airport"
    if [ -x "$airport" ]; then
        sudo "$airport" -z 2>/dev/null
    else
        sudo networksetup -setairportpower "$INTERFACE" off
        sleep 1
        networksetup -setairportpower "$INTERFACE" on
    fi
    echo -e "${GREEN}Disconnected${NC}"
}

wifi_info() {
    echo -e "${CYAN}=== WiFi Details ===${NC}"
    echo ""
    wifi_status
    echo ""

    local ssid
    ssid=$(get_current_ssid)

    if [ -n "$ssid" ]; then
        echo -e "${CYAN}--- Connection Details ---${NC}"

        # Get extra info from ipconfig
        local summary
        summary=$(ipconfig getsummary "$INTERFACE" 2>/dev/null)

        if [ -n "$summary" ]; then
            local bssid channel security
            bssid=$(echo "$summary" | awk -F': ' '/  BSSID :/{print $2}')
            channel=$(echo "$summary" | awk -F': ' '/  Channel :/{print $2}')
            security=$(echo "$summary" | awk -F': ' '/  Security :/{print $2}')

            [ -n "$bssid" ] && echo -e "BSSID:      ${bssid}"
            [ -n "$channel" ] && echo -e "Channel:    ${channel}"
            [ -n "$security" ] && echo -e "Security:   ${security}"
        fi

        # Get signal info from system_profiler
        local signal
        signal=$(system_profiler SPAirPortDataType 2>/dev/null | awk '/Current Network Information:/,/Other Local Wi-Fi Networks:/' | grep "Signal / Noise" | awk -F': ' '{print $2}')
        [ -n "$signal" ] && echo -e "Signal:     ${signal}"

        echo ""
    fi

    echo -e "${CYAN}--- DNS ---${NC}"
    networksetup -getdnsservers Wi-Fi 2>/dev/null
    echo ""

    echo -e "${CYAN}--- MAC Address ---${NC}"
    networksetup -getmacaddress "$INTERFACE" 2>/dev/null
    echo ""

    echo -e "${CYAN}--- Gateway ---${NC}"
    netstat -rn 2>/dev/null | grep "^default.*${INTERFACE}" | head -1
}

wifi_saved() {
    echo -e "${CYAN}Saved/Preferred Networks:${NC}"
    networksetup -listpreferredwirelessnetworks "$INTERFACE" 2>/dev/null
}

wifi_forget() {
    local ssid="$1"
    if [ -z "$ssid" ]; then
        echo -e "${RED}Error: Provide SSID to forget${NC}"
        exit 1
    fi
    echo -e "Forgetting '${YELLOW}${ssid}${NC}'..."
    sudo networksetup -removepreferredwirelessnetwork "$INTERFACE" "$ssid" 2>/dev/null
    echo -e "${GREEN}Done${NC}"
}

case "${1}" in
    status)      wifi_status ;;
    on)          wifi_on ;;
    off)         wifi_off ;;
    scan)        wifi_scan ;;
    connect)     wifi_connect "$2" "$3" ;;
    disconnect)  wifi_disconnect ;;
    info)        wifi_info ;;
    saved)       wifi_saved ;;
    forget)      wifi_forget "$2" ;;
    help|--help|-h|"") usage ;;
    *)
        echo -e "${RED}Unknown command: ${1}${NC}"
        usage
        exit 1
        ;;
esac
