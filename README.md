# SSH over OTG for ArkOS
 
This script enables SSH/SFTP access to your ArkOS device via USB OTG connection.
It configures a USB gadget that creates a network interface and provides DHCP service for automatic IP assignment to connected devices.

# Features:
- Creates USB RNDIS/ECM network gadget
- Assigns static IP to device (192.168.7.1)
- Provides DHCP service to connected clients (range: 192.168.7.100-200)
- Starts SSH service for remote access
- Supports gamepad controls via gptokeyb

# Uasge:
Place this script to /opt/system/Tools or /roms/ports and run it in your device.

# Credit：
Based on work by AlternativeRoom4499
https://www.reddit.com/r/R36S/comments/1kzwn5d/ssh_over_otg_on_arkos_installed_r36sc/
