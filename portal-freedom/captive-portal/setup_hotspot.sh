#!/bin/bash
# setup_hotspot.sh — Configure macOS as a captive portal for Facebook Portal
#
# RISK LEVEL: LOW (creates WiFi network, modifies local DNS/firewall temporarily)
#
# WIFI-ONLY MODE: No wired/ethernet connection needed!
# The Portal doesn't need real internet — it just needs to connect to a WiFi
# network and hit our captive portal server. We intercept ALL DNS locally.
#
# Prerequisites:
#   - macOS with WiFi (Apple Silicon)
#   - Homebrew dnsmasq installed: brew install dnsmasq
#
# Setup (ONE-TIME, manual — macOS requires GUI):
#   System Settings > General > Sharing > Internet Sharing
#   - Share from: "Thunderbolt Bridge" (works even with nothing plugged in!)
#   - To: Wi-Fi (check the box)
#   - Click the (i) next to Wi-Fi to configure:
#     - Network Name: PortalNet
#     - Channel: Auto or 6
#     - Security: None (simplest) or WPA2/WPA3 Personal
#   - Toggle Internet Sharing ON
#   - This creates bridge100 interface + WiFi AP
#
# Then run: sudo ./setup_hotspot.sh
#
# Usage:
#   sudo ./setup_hotspot.sh          # Start everything
#   sudo ./setup_hotspot.sh --stop   # Stop everything
#   sudo ./setup_hotspot.sh --check  # Check prerequisites only
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DNSMASQ_CONF="${SCRIPT_DIR}/dnsmasq.conf"
PF_ANCHOR="/tmp/portal-captive-pf.conf"
DNSMASQ_PID_FILE="/tmp/dnsmasq-portal.pid"
SERVER_PORT=80
EXPLOIT_MODE=false

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

info()  { echo -e "${GREEN}[+]${NC} $*"; }
warn()  { echo -e "${YELLOW}[!]${NC} $*"; }
error() { echo -e "${RED}[X]${NC} $*"; }
header(){ echo -e "${CYAN}$*${NC}"; }

# -------------------------------------------------------------------
# Find the bridge/hotspot interface
# -------------------------------------------------------------------
find_bridge_interface() {
    # macOS Internet Sharing creates a bridge with member "ap1" (WiFi AP).
    # We must pick THAT bridge, not a VM bridge (member: vmenet0).
    # Check bridge100 through bridge105 for the one with "ap1" member.
    for iface in bridge100 bridge101 bridge102 bridge103 bridge104 bridge105; do
        if ifconfig "$iface" >/dev/null 2>&1; then
            # Only match bridges with "ap1" member (WiFi AP), skip VM bridges
            if ifconfig "$iface" | grep -q "member: ap1"; then
                local ip
                ip=$(ifconfig "$iface" | grep "inet " | awk '{print $2}')
                if [ -n "$ip" ]; then
                    echo "$iface:$ip"
                    return 0
                fi
            fi
        fi
    done
    # Fallback: any bridge with an IP (if no ap1 found)
    for iface in bridge100 bridge101 bridge102; do
        if ifconfig "$iface" >/dev/null 2>&1; then
            local ip
            ip=$(ifconfig "$iface" | grep "inet " | awk '{print $2}')
            if [ -n "$ip" ]; then
                echo "$iface:$ip"
                return 0
            fi
        fi
    done
    return 1
}

# -------------------------------------------------------------------
# Stop all services
# -------------------------------------------------------------------
stop_services() {
    info "Stopping captive portal services..."

    # Kill dnsmasq (our instance)
    if [ -f "$DNSMASQ_PID_FILE" ]; then
        kill "$(cat "$DNSMASQ_PID_FILE")" 2>/dev/null || true
        rm -f "$DNSMASQ_PID_FILE"
        info "Stopped dnsmasq"
    fi
    pkill -f "dnsmasq.*dnsmasq-portal" 2>/dev/null || true

    # Kill Python server
    pkill -f "python3.*server.py" 2>/dev/null || true
    info "Stopped HTTP server"

    # Remove pfctl rules
    if [ -f "$PF_ANCHOR" ]; then
        pfctl -F all 2>/dev/null || true
        rm -f "$PF_ANCHOR"
        info "Cleared firewall rules"
    fi

    # Flush DNS cache
    dscacheutil -flushcache 2>/dev/null || true
    killall -HUP mDNSResponder 2>/dev/null || true

    info "All services stopped."
    info "You can disable Internet Sharing in System Settings if desired."
    exit 0
}

# -------------------------------------------------------------------
# Show setup instructions
# -------------------------------------------------------------------
show_setup_instructions() {
    echo ""
    header "╔══════════════════════════════════════════════════════════╗"
    header "║  macOS Internet Sharing Setup (WiFi-only, no ethernet)  ║"
    header "╚══════════════════════════════════════════════════════════╝"
    echo ""
    echo "  1. Open: System Settings > General > Sharing"
    echo "  2. Find 'Internet Sharing' (don't toggle it yet)"
    echo "  3. Click the (i) info button next to Internet Sharing"
    echo ""
    echo "  4. 'Share your connection from:'"
    echo "     Select: Thunderbolt Bridge"
    echo "     (This works even with nothing plugged into Thunderbolt!)"
    echo ""
    echo "  5. 'To computers using:'"
    echo "     Check: Wi-Fi"
    echo ""
    echo "  6. Click 'Wi-Fi Options...' and set:"
    echo "     Network Name: PortalNet"
    echo "     Channel:      Auto (or 6)"
    echo "     Security:     None"
    echo "     (None is simplest — the Portal only needs to connect briefly)"
    echo ""
    echo "  7. Toggle Internet Sharing ON"
    echo "     Confirm the dialog that appears"
    echo ""
    echo "  8. Wait 5 seconds, then run this script again:"
    echo "     sudo $0"
    echo ""
    echo "  Note: Your Mac's WiFi will disconnect from its current network."
    echo "  The Mac will act as a WiFi access point instead."
    echo "  To restore normal WiFi: turn off Internet Sharing."
    echo ""
}

# -------------------------------------------------------------------
# Main
# -------------------------------------------------------------------

# Parse --exploit flag (can be combined with other args)
for arg in "$@"; do
    if [ "$arg" = "--exploit" ]; then
        EXPLOIT_MODE=true
    fi
done

if [ "${1:-}" = "--stop" ]; then
    # --stop doesn't require root for the check, but does for killing
    if [ "$(id -u)" -ne 0 ]; then
        error "Stopping requires root. Run: sudo $0 --stop"
        exit 1
    fi
    stop_services
fi

if [ "${1:-}" = "--check" ]; then
    info "Checking prerequisites..."
    command -v dnsmasq >/dev/null 2>&1 && info "dnsmasq: OK" || error "dnsmasq: NOT FOUND (brew install dnsmasq)"
    command -v python3 >/dev/null 2>&1 && info "python3: OK" || error "python3: NOT FOUND"
    command -v pfctl >/dev/null 2>&1 && info "pfctl: OK" || error "pfctl: NOT FOUND"
    if find_bridge_interface >/dev/null 2>&1; then
        result=$(find_bridge_interface)
        info "Bridge interface: ${result%%:*} = ${result##*:}"
    else
        warn "No bridge interface found — enable Internet Sharing first"
        show_setup_instructions
    fi
    exit 0
fi

# Check root
if [ "$(id -u)" -ne 0 ]; then
    error "This script requires root. Run: sudo $0"
    exit 1
fi

echo ""
header "╔══════════════════════════════════════════════════════════╗"
header "║         Portal Captive Portal Setup                      ║"
header "║         (WiFi-only mode — no ethernet needed)            ║"
header "╚══════════════════════════════════════════════════════════╝"
echo ""

# Step 1: Check prerequisites
info "Checking prerequisites..."

if ! command -v dnsmasq >/dev/null 2>&1; then
    error "dnsmasq not installed. Run: brew install dnsmasq"
    exit 1
fi
info "dnsmasq: OK ($(dnsmasq --version | head -1 | awk '{print $3}'))"

if ! command -v python3 >/dev/null 2>&1; then
    error "python3 not found"
    exit 1
fi
info "python3: OK"

# Step 2: Find bridge interface (created by Internet Sharing)
info "Looking for hotspot bridge interface..."

if ! find_bridge_interface >/dev/null 2>&1; then
    warn "No bridge interface found!"
    echo ""
    warn "Internet Sharing must be enabled FIRST to create the WiFi hotspot."
    show_setup_instructions
    exit 1
fi

BRIDGE_RESULT=$(find_bridge_interface)
BRIDGE_IF="${BRIDGE_RESULT%%:*}"
BRIDGE_IP="${BRIDGE_RESULT##*:}"
info "Found bridge: $BRIDGE_IF = $BRIDGE_IP"

# Step 3: Stop any previous instances
info "Cleaning up previous instances..."
pkill -f "dnsmasq.*dnsmasq-portal" 2>/dev/null || true
sleep 0.5

# Step 4: Create dnsmasq config with correct IP
RUNTIME_DNSMASQ="/tmp/dnsmasq-portal.conf"
cat > "$RUNTIME_DNSMASQ" <<EOF
# Portal captive portal DNS — auto-generated
# Resolves ALL domains to $BRIDGE_IP

address=/#/$BRIDGE_IP
listen-address=$BRIDGE_IP
bind-interfaces
no-resolv
no-hosts
log-queries
log-facility=/tmp/dnsmasq-portal.log
port=53

# Also serve DHCP if macOS bootpd isn't handling it well
# (Internet Sharing normally runs bootpd for DHCP, but our DNS override
# needs to point clients to us. This DHCP range coexists with bootpd.)
# Uncomment if Portal doesn't get DNS from gateway:
# dhcp-range=$BRIDGE_IP,192.168.2.10,192.168.2.50,255.255.255.0,12h
# dhcp-option=option:dns-server,$BRIDGE_IP
# dhcp-option=option:router,$BRIDGE_IP
EOF

info "Created DNS config → all domains resolve to $BRIDGE_IP"

# Step 5: Start dnsmasq
info "Starting dnsmasq..."
dnsmasq -C "$RUNTIME_DNSMASQ" --no-daemon --log-queries --pid-file="$DNSMASQ_PID_FILE" &
DNSMASQ_PID=$!
sleep 1

if kill -0 "$DNSMASQ_PID" 2>/dev/null; then
    info "dnsmasq running (PID: $DNSMASQ_PID)"
else
    error "dnsmasq failed to start!"
    echo ""
    # Common issue: port 53 already in use
    warn "Checking port 53..."
    lsof -i :53 -P 2>/dev/null | head -5 || true
    echo ""
    warn "If mDNSResponder is on port 53, dnsmasq's bind-interfaces should avoid conflict."
    warn "If another dnsmasq is running, kill it first: sudo pkill dnsmasq"
    exit 1
fi

# Step 6: Configure pfctl to redirect traffic
info "Configuring firewall rules..."
cat > "$PF_ANCHOR" <<EOF
# Redirect HTTP/HTTPS from Portal to our captive portal server
rdr pass on $BRIDGE_IF proto tcp from any to any port 80 -> $BRIDGE_IP port $SERVER_PORT
rdr pass on $BRIDGE_IF proto tcp from any to any port 443 -> $BRIDGE_IP port $SERVER_PORT
EOF

pfctl -ef "$PF_ANCHOR" 2>/dev/null || {
    warn "pfctl may not have loaded perfectly (common on macOS, usually OK)"
}
info "Firewall: port 80/443 → $BRIDGE_IP:$SERVER_PORT"

# Step 7: Verify DNS is working
info "Testing DNS resolution..."
DIG_RESULT=$(dig +short @"$BRIDGE_IP" connectivitycheck.gstatic.com 2>/dev/null || echo "FAILED")
if [ "$DIG_RESULT" = "$BRIDGE_IP" ]; then
    info "DNS test PASSED: connectivitycheck.gstatic.com → $BRIDGE_IP"
else
    warn "DNS test returned: $DIG_RESULT (expected $BRIDGE_IP)"
    warn "This may still work — Portal might query gateway directly"
fi

# Step 8: Ready!
echo ""
echo "════════════════════════════════════════════════════════════"
echo ""
echo "  CAPTIVE PORTAL READY!"
echo ""
echo "  WiFi Hotspot:  (your Internet Sharing SSID, e.g. 'PortalNet')"
echo "  DNS:           $BRIDGE_IP:53 (all domains → $BRIDGE_IP)"
echo "  HTTP Server:   $BRIDGE_IP:$SERVER_PORT"
echo "  Firewall:      port 80/443 → server"
echo "  Logs:          ${SCRIPT_DIR}/logs/"
echo ""
echo "  HOW TO TEST:"
echo "  1. Boot Portal normally (hold nothing — just power on)"
echo "  2. In Portal settings, connect to your hotspot WiFi"
echo "     (or trigger WiFi setup if fresh/factory-reset)"
echo "  3. Portal detects captive portal → opens WebView"
echo "  4. Watch THIS CONSOLE for Chrome version"
echo ""
echo "  Server starting below. Press Ctrl+C to stop everything."
echo ""
echo "════════════════════════════════════════════════════════════"
echo ""

# Start HTTP server in foreground
cd "$SCRIPT_DIR"
if [ "$EXPLOIT_MODE" = true ]; then
    warn "EXPLOIT MODE — serving rce_chrome86.html to Portal WebView"
    python3 server.py --port "$SERVER_PORT" --bind "$BRIDGE_IP" --exploit || true
else
    python3 server.py --port "$SERVER_PORT" --bind "$BRIDGE_IP" || true
fi

# Cleanup on exit (Ctrl+C or server crash)
info "Server exited. Cleaning up..."
kill "$DNSMASQ_PID" 2>/dev/null || true
rm -f "$DNSMASQ_PID_FILE"
pfctl -F all 2>/dev/null || true
rm -f "$PF_ANCHOR"
info "All services stopped."
