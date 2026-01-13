#!/bin/bash
# SSH over OTG for ArkOS
# 
# This script enables SSH/SFTP access to your ArkOS device via USB OTG connection.
# It configures a USB gadget that creates a network interface and provides DHCP service for automatic IP assignment to connected devices.
#
# Features:
# - Creates USB RNDIS/ECM network gadget
# - Assigns static IP to device (192.168.7.1)
# - Provides DHCP service to connected clients (range: 192.168.7.100-200)
# - Starts SSH service for remote access
# - Supports gamepad controls via gptokeyb
#
# Uasge:
# Place this script to /opt/system/Tools or /roms/ports and run it in your device.
#
# Based on work by AlternativeRoom4499
# https://www.reddit.com/r/R36S/comments/1kzwn5d/ssh_over_otg_on_arkos_installed_r36sc/
# Modified by: carrothu-cn
# Version: 1.0

set -euo pipefail  # Enable strict error handling mode

# Configuration variables - Using readonly to declare constants
readonly SCRIPT_NAME=$(basename "$0")  # Script filename
readonly CURR_TTY="/dev/tty1"  # Current terminal device
readonly GADGET_DIR="/sys/kernel/config/usb_gadget/arkos_ssh"  # USB gadget configuration directory
readonly DEVICE_IP="192.168.7.1"  # Device IP address
readonly DHCP_START="192.168.7.100"  # DHCP assignment start IP
readonly DHCP_END="192.168.7.200"  # DHCP assignment end IP
readonly DHCP_SUBNET="255.255.255.0"  # Subnet mask
RUN_LOG="log message:"  # Log recording variable

# Set locale environment variables
export LANG=C.UTF-8  # Set language environment to UTF-8
export LC_ALL=C.UTF-8  # Set localization environment
export TERM=linux  # Set terminal type
unset FBTERM  # Unset FBTERM environment variable

# Add log recording function
add_run_log() {
    RUN_LOG+="\n$1"  # Append message to log variable
}

# Initialize terminal display function
init_terminal() {
    printf "\033c\e[?25l" > "$CURR_TTY"  # Clear screen and hide cursor
    # Set font, if font file exists then set, otherwise ignore errors
    setfont /usr/share/consolefonts/Lat7-Terminus16.psf.gz 2>/dev/null || true
    printf "\033cSSH over OTG for ArkOS loading, please wait..."> "$CURR_TTY"  # Display loading information
    sleep 1  # Wait 1 second
}

# Safe dialog message box function - Prevents errors from interrupting
safe_msgbox() {
    # Display titled message box, output to current TTY, ignore if fails
    dialog --backtitle "SSH over OTG for ArkOS by AlternativeRoom4499 & carrothu-cn" --title "SSH over OTG for ArkOS" --msgbox "${1:-Done.}" "${2:-6}" "${3:-40}" > "$CURR_TTY" || true
}

# Configure USB gadget function - Creates USB network device
configure_usb_gadget() {
    # Load required USB composite modules
    modprobe libcomposite 2>/dev/null || { add_run_log "[ERROR] Could not load libcomposite"; return 1; }
    modprobe usb_f_rndis 2>/dev/null || { add_run_log "[ERROR] Could not load rndis"; return 1; }
    modprobe usb_f_ecm 2>/dev/null || { add_run_log "[ERROR] Could not load ecm"; return 1; }

    # Detect UDC device - USB Device Controller
    local udc_device=""
    if [ -d /sys/class/udc ]; then
        for udc in /sys/class/udc/*; do
            udc_device=$(basename "$udc")  # Get device name
            add_run_log "[INFO] Found UDC: $udc_device"  # Record found UDC device
            break  # Break after finding
        done
    else
        udc_device="ff300000.usb"  # Set default UDC device
        add_run_log "[INFO] Using default UDC: $udc_device"  # Record using default device
    fi

    # Clean previous configuration
    cleanup_usb_gadget

    # Create new USB gadget configuration
    mkdir -p "$GADGET_DIR" || { add_run_log "[ERROR] Could not create gadget dir"; return 1; }
    cd "$GADGET_DIR"  # Change to gadget directory

    # Set USB device identifiers
    echo 0x1d6b > idVendor  # Set vendor ID
    echo 0x0104 > idProduct  # Set product ID

    # Configure device strings - for device identification
    mkdir -p strings/0x409  # Create string directory
    echo "ArkOS$(date +%s)" > strings/0x409/serialnumber  # Serial number (timestamp)
    echo "ArkOS Team" > strings/0x409/manufacturer  # Manufacturer name
    echo "Gaming Console" > strings/0x409/product  # Product name

    # Create configuration descriptor
    mkdir -p configs/c.1/strings/0x409  # Create config string directory
    echo "SSH over OTG for ArkOS" > configs/c.1/strings/0x409/configuration  # Configuration name
    echo 500 > configs/c.1/MaxPower  # Maximum power

    # Select network function - Prefer RNDIS, fallback to ECM
    if mkdir -p functions/rndis.usb0 2>/dev/null; then
        ln -sf functions/rndis.usb0 configs/c.1/  # Create symbolic link to config
    elif mkdir -p functions/ecm.usb0 2>/dev/null; then
        ln -sf functions/ecm.usb0 configs/c.1/  # Create ECM symbolic link
    else
        add_run_log "[ERROR] Could not create USB network function"  # Network function creation failed
        return 1
    fi

    # Start USB gadget
    echo "$udc_device" > UDC 2>/dev/null || { add_run_log "[ERROR] Could not start USB gadget"; return 1; }
    sleep 3  # Wait 3 seconds for device to stabilize

    # Wait for network interface to appear
    local retry=0  # Retry counter
    while [ $retry -lt 10 ]; do  # Max 10 retries
        ip link show "usb0" >/dev/null 2>&1 && break  # Check if interface exists
        add_run_log "[WARNING] usb0 not ready (try $((retry+1))/10)"  # Record retry info
        sleep 2  # Wait 2 seconds before retry
        ((retry++))  # Increment retry count
    done
    [ $retry -eq 10 ] && { add_run_log "[ERROR] usb0 not found"; return 1; }  # Fail after max retries
    return 0
}

# Clean USB gadget configuration function
cleanup_usb_gadget() {
    [ -d "$GADGET_DIR" ] && {  # If gadget directory exists
        echo "" > "$GADGET_DIR/UDC" 2>/dev/null || true  # Stop gadget
        # Remove RNDIS and ECM links
        rm -f "$GADGET_DIR/configs/c.1/"{rndis,ecm}.usb0 2>/dev/null || true
        # Remove config and function directories
        rmdir "$GADGET_DIR"/{configs/c.1,functions/{rndis,ecm}.usb0} 2>/dev/null || true
        rmdir "$GADGET_DIR" 2>/dev/null || true  # Remove gadget directory
    }
    return 0
}

# Configure network interface function
configure_network() {
    ip link show "usb0" >/dev/null 2>&1 || { add_run_log "[ERROR] usb0 does not exist"; return 1; }  # Check if network interface exists
    
    # Prefer ip command for network configuration
    if command -v ip >/dev/null 2>&1; then
        ip addr flush dev "usb0" 2>/dev/null || true  # Flush interface addresses
        ip addr add "$DEVICE_IP/24" dev "usb0" 2>/dev/null || { add_run_log "[WARNING] Could not assign IP with ip"; return 1; }  # Add IP
        ip link set "usb0" up 2>/dev/null || { add_run_log "[WARNING] Could not bring up usb0 with ip"; return 1; }  # Bring up interface
        add_run_log "[INFO] interface usb0 brought up with ip"  # Record success info
    elif command -v ifconfig >/dev/null 2>&1; then  # If no ip command, use ifconfig
        ifconfig "usb0" "$DEVICE_IP" netmask "$DHCP_SUBNET" up 2>/dev/null || { add_run_log "[WARNING] Could not configure usb0 with ifconfig"; return 1; }  # Configure network
        add_run_log "[INFO] usb0 configured with ifconfig"  # Record success info
    else
        add_run_log "[ERROR] No ip or ifconfig found"  # Both commands don't exist
        return 1
    fi
    return 0
}

# Start DHCP service function
start_dhcp_service() {
    command -v dnsmasq >/dev/null 2>&1 || { add_run_log "[ERROR] Dnsmasq not found"; return 1; }  # Check if dnsmasq exists
    pkill -f "dnsmasq.*usb_dhcp.conf" 2>/dev/null || true  # Kill previous dnsmasq instances
    
    local config="/tmp/usb_dhcp.conf"  # Create config file path
    # Create dnsmasq configuration file
    cat > "$config" << EOF
port=0
interface=usb0
dhcp-range=$DHCP_START,$DHCP_END,12h
dhcp-option=3,$DEVICE_IP
dhcp-option=6,$DEVICE_IP
EOF

    dnsmasq -C "$config" 2>/dev/null &  # Start dnsmasq in background
    local pid=$!  # Get process ID
    
    # Check if process is actually running
    kill -0 $pid 2>/dev/null && add_run_log "[INFO] DHCP started (PID: $pid)" || { add_run_log "[ERROR] dnsmasq failed to start"; return 1; }  # Check if process is alive
    return 0
}

# Stop DHCP service function
stop_dhcp_service() {
    pkill -f "dnsmasq.*usb_dhcp.conf" 2>/dev/null || true  # Kill matching dnsmasq processes
    rm -f "/tmp/usb_*.conf" 2>/dev/null || true  # Delete temporary config files
    return 0
}

# Start SSH service function
start_ssh_service() {
    local ssh_running=false  # SSH running status variable
    # Check if SSH service is already running
    for svc in sshd ssh; do
        pgrep -x "$svc" >/dev/null && ssh_running=true && add_run_log "[INFO] SSH ($svc) already running"  # Check sshd process
        systemctl is-active --quiet "$svc" 2>/dev/null && ssh_running=true && add_run_log "[INFO] SSH ($svc) already running"  # Check service status
    done

    # If SSH not running, try to start it
    if [ "$ssh_running" = false ]; then
        # Try different startup methods
        for cmd in "systemctl start ssh" "systemctl start sshd" "service ssh start" "service sshd start"; do
            if eval "$cmd" 2>/dev/null; then
                add_run_log "[INFO] SSH started via $cmd"  # Record successful startup method
                break  # Break after success
            fi
        done
        
        # If above methods fail, try starting sshd directly
        if [ "$ssh_running" = false ] && [ -f /usr/sbin/sshd ]; then
            /usr/sbin/sshd -D 2>/dev/null &  # Start sshd and run in background
            local pid=$!  # Get process ID
            if kill -0 $pid 2>/dev/null; then  # Check if process is alive
                add_run_log "[INFO] SSH started directly (PID: $pid)"  # Record direct startup success
                ssh_running=true
            else
                add_run_log "[ERROR] Could not start SSH daemon"  # Direct startup failed
                return 1
            fi
        fi
    fi

    sleep 2  # Wait 2 seconds for service to start
    # Verify SSH service is actually running
    pgrep -x sshd >/dev/null || systemctl is-active --quiet ssh 2>/dev/null || systemctl is-active --quiet sshd 2>/dev/null || { add_run_log "[WARNING] SSH may not be running"; return 1; }  # Check if SSH is running
    add_run_log "[INFO] SSH confirmed running"  # Record confirmation of running
    return 0
}

# Setup gamepad support function
setup_gamepad_support() {
    command -v /opt/inttools/gptokeyb &> /dev/null && {  # Check if gptokeyb exists
        [ -e /dev/uinput ] && chmod 666 /dev/uinput 2>/dev/null || add_run_log "[WARNING] Could not change /dev/uinput permissions"  # Set uinput device permissions
        export SDL_GAMECONTROLLERCONFIG_FILE="/opt/inttools/gamecontrollerdb.txt"  # Set game controller config file
        pkill -f "gptokeyb -1 $SCRIPT_NAME" 2>/dev/null || true  # Kill previous gptokeyb instance
        /opt/inttools/gptokeyb -1 $SCRIPT_NAME -c "/opt/inttools/keys.gptk" >/dev/null 2>&1 &  # Start gptokeyb
    } || add_run_log "[WARNING] Gamepad support disabled. gptokeyb not found."  # gptokeyb doesn't exist
    return 0
}

# Main execution function
main() {
    init_terminal  # Initialize terminal
    setup_gamepad_support  # Setup gamepad support
    
    # Configure various components
    configure_usb_gadget && add_run_log "[OK] USB Gadget configured" || add_run_log "[ERROR] USB Gadget configuration failed"  # Configure USB gadget
    configure_network && add_run_log "[OK] Network configured" || add_run_log "[ERROR] Network configuration failed"  # Configure network
    start_dhcp_service && add_run_log "[OK] DHCP service started" || add_run_log "[ERROR] DHCP service start failed"  # Start DHCP service
    start_ssh_service && add_run_log "[OK] SSH service started" || add_run_log "[ERROR] SSH service start failed"  # Start SSH service
    
    # Prepare connection information
    local connection_info="Plug the USB cable into OTG port and connect via SSH/SFTP:\nark@$DEVICE_IP (default password is: ark)\n\nIf auto-configuration fails, set your network adapter to:\nIP: 192.168.7.2, Netmask: 255.255.255.0\n\nOK to exit\n"
    safe_msgbox "$connection_info\n$RUN_LOG" 12 70  # Display connection info and logs
}

# Cleanup function - Execute when script exits
cleanup() {
    stop_dhcp_service  # Stop DHCP service
    cleanup_usb_gadget  # Clean USB gadget
    printf "\033c\e[?25h" > "$CURR_TTY"  # Clear screen and show cursor
    pkill -f "gptokeyb -1 $SCRIPT_NAME" 2>/dev/null || true  # Stop gamepad mapping
    return 0
}

# Check root permission
[ "$(id -u)" -ne 0 ] && exec sudo "$0" "$@"  # If not root user, use sudo to re-execute script

# Set signal handling - Execute cleanup function when receiving exit signal
trap cleanup EXIT SIGINT SIGTERM

# Execute main function
main
