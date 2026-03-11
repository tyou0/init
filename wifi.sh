#!/bin/bash

# wifi-cli.sh - A CLI tool to manage WiFi on macOS

AIRPORT="/System/Library/PrivateFrameworks/Apple80211.framework/Versions/Current/Resources/airport"
INTERFACE="en0"

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

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
    echo ""
}

wifi_status() {
    local power
    power=$(networksetup -getairportpower "$INTERFACE" 2>/dev/null)

    if echo "$power" | grep -q "On"; then
        echo -e "WiFi Power: ${GREEN}On${NC}"
        local ssid
        ssid=$(networksetup -getairportnetwork "$INTERFACE" 2>/dev/null | sed 's/Current Wi-Fi Network: //')
        if [ -n "$ssid" ] && [ "$ssid" != "You are not associated with an AirPort network." ]; then
            echo -e "Connected to: ${GREEN}${ssid}${NC}"
            local ip
            ip=$(ipconfig getifaddr "$INTERFACE" 2>/dev/null)
            if [ -n "$ip" ]; then
                echo -e "IP Address: ${CYAN}${ip}${NC}"
            fi
        else
            echo -e "Connected to: ${RED}Not connected${NC}"
        fi
    else
        echo -e "WiFi Power: ${RED}Off${NC}"
    fi
}

wifi_on() {
    echo "Turning WiFi on..."
    networksetup -setairportpower "$INTERFACE" on
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}WiFi is now on${NC}"
    else
        echo -e "${RED}Failed to turn on WiFi${NC}"
        exit 1
    fi
}

wifi_off() {
    echo "Turning WiFi off..."
    networksetup -setairportpower "$INTERFACE" off
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}WiFi is now off${NC}"
    else
        echo -e "${RED}Failed to turn off WiFi${NC}"
        exit 1
    fi
}

wifi_scan() {
    echo -e "${CYAN}Scanning for networks...${NC}"
    echo ""

    # Try the modern approach first (macOS Ventura+)
    if command -v wdutil &>/dev/null; then
        "$AIRPORT" -s 2>/dev/null || {
            echo -e "${YELLOW}Using system_profiler fallback...${NC}"
            system_profiler SPAirPortDataType 2>/dev/null | grep -A 2 "Other Local Wi-Fi Networks" || \
            networksetup -listpreferredwirelessnetworks "$INTERFACE" 2>/dev/null
        }
    else
        "$AIRPORT" -s 2>/dev/null || {
            echo -e "${YELLOW}Airport utility not available. Using networksetup...${NC}"
            networksetup -listpreferredwirelessnetworks "$INTERFACE" 2>/dev/null
        }
    fi
}

wifi_connect() {
    local ssid="$1"
    local password="$2"

    if [ -z "$ssid" ]; then
        echo -e "${RED}Error: Please provide a network name (SSID)${NC}"
        echo "Usage: $(basename "$0") connect <SSID> [password]"
        exit 1
    fi

    # Ensure WiFi is on
    local power
    power=$(networksetup -getairportpower "$INTERFACE" 2>/dev/null)
    if echo "$power" | grep -q "Off"; then
        echo "WiFi is off. Turning it on..."
        networksetup -setairportpower "$INTERFACE" on
        sleep 2
    fi

    # If no password provided, prompt for it
    if [ -z "$password" ]; then
        echo -n "Enter password for '${ssid}' (leave empty for open network): "
        read -s password
        echo ""
    fi

    echo -e "Connecting to ${CYAN}${ssid}${NC}..."

    if [ -z "$password" ]; then
        networksetup -setairportnetwork "$INTERFACE" "$ssid" 2>/dev/null
    else
        networksetup -setairportnetwork "$INTERFACE" "$ssid" "$password" 2>/dev/null
    fi

    if [ $? -eq 0 ]; then
        # Verify connection
        sleep 2
        local current_ssid
        current_ssid=$(networksetup -getairportnetwork "$INTERFACE" 2>/dev/null | sed 's/Current Wi-Fi Network: //')
        if [ "$current_ssid" = "$ssid" ]; then
            echo -e "${GREEN}Successfully connected to '${ssid}'${NC}"
            local ip
            ip=$(ipconfig getifaddr "$INTERFACE" 2>/dev/null)
            if [ -n "$ip" ]; then
                echo -e "IP Address: ${CYAN}${ip}${NC}"
            fi
        else
            echo -e "${RED}Connection may have failed. Current network: ${current_ssid}${NC}"
            exit 1
        fi
    else
        echo -e "${RED}Failed to connect to '${ssid}'${NC}"
        echo "Check your password and network name."
        exit 1
    fi
}

wifi_disconnect() {
    echo "Disconnecting from WiFi..."
    sudo "$AIRPORT" -z 2>/dev/null || {
        # Fallback: turn off and on
        networksetup -setairportpower "$INTERFACE" off
        sleep 1
        networksetup -setairportpower "$INTERFACE" on
    }
    echo -e "${GREEN}Disconnected${NC}"
}

wifi_info() {
    echo -e "${CYAN}=== WiFi Details ===${NC}"
    echo ""
    wifi_status
    echo ""

    echo -e "${CYAN}--- Network Details ---${NC}"
    "$AIRPORT" -I 2>/dev/null || {
        echo "Interface: $INTERFACE"
        networksetup -getairportnetwork "$INTERFACE" 2>/dev/null
        echo "DNS Servers:"
        networksetup -getdnsservers Wi-Fi 2>/dev/null
        echo "Proxy Settings:"
        networksetup -getwebproxy Wi-Fi 2>/dev/null
    }

    echo ""
    echo -e "${CYAN}--- Hardware Address ---${NC}"
    networksetup -getmacaddress "$INTERFACE" 2>/dev/null
}

wifi_saved() {
    echo -e "${CYAN}Saved/Preferred Networks:${NC}"
    echo ""
    networksetup -listpreferredwirelessnetworks "$INTERFACE" 2>/dev/null
}

wifi_forget() {
    local ssid="$1"
    if [ -z "$ssid" ]; then
        echo -e "${RED}Error: Please provide a network name (SSID) to forget${NC}"
        exit 1
    fi

    echo -e "Forgetting network '${YELLOW}${ssid}${NC}'..."
    sudo networksetup -removepreferredwirelessnetwork "$INTERFACE" "$ssid" 2>/dev/null

    if [ $? -eq 0 ]; then
        echo -e "${GREEN}Successfully removed '${ssid}' from saved networks${NC}"
    else
        echo -e "${RED}Failed to remove '${ssid}'. You may need sudo.${NC}"
        exit 1
    fi
}

# --- Main ---
case "${1}" in
    status)
        wifi_status
        ;;
    on)
        wifi_on
        ;;
    off)
        wifi_off
        ;;
    scan)
        wifi_scan
        ;;
    connect)
        wifi_connect "$2" "$3"
        ;;
    disconnect)
        wifi_disconnect
        ;;
    info)
        wifi_info
        ;;
    saved)
        wifi_saved
        ;;
    forget)
        wifi_forget "$2"
        ;;
    help|--help|-h|"")
        usage
        ;;
    *)
        echo -e "${RED}Unknown command: ${1}${NC}"
        echo ""
        usage
        exit 1
        ;;
esac
