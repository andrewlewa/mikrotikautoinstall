#!/bin/bash

# PPTP Server Auto-installation Script for Ubuntu Server 24.04
# This script installs and configures a PPTP VPN server with auto-reconnect and auto-start on boot

# Check if script is run as root
if [ "$(id -u)" -ne 0 ]; then
    echo "This script must be run as root" >&2
    exit 1
fi

echo "================================================="
echo "PPTP VPN Server Setup for Ubuntu Server 24.04"
echo "================================================="

# Install required packages
echo "Installing required packages..."
apt update -y
apt install -y pptpd net-tools iptables-persistent

# Prompt for server settings
echo "Please enter the server settings:"
read -p "Local IP (server internal IP, e.g. 192.168.0.1): " LOCAL_IP
read -p "Remote IP range (e.g. 192.168.0.200-230): " REMOTE_IP_RANGE
read -p "DNS1 (e.g. 8.8.8.8): " DNS1
read -p "DNS2 (e.g. 8.8.4.4): " DNS2

# Configure PPTP
echo "Configuring PPTP server..."
cat > /etc/pptpd.conf << EOF
option /etc/ppp/pptpd-options
logwtmp
localip $LOCAL_IP
remoteip $REMOTE_IP_RANGE
EOF

# Configure PPP options
cat > /etc/ppp/pptpd-options << EOF
name pptpd
refuse-pap
refuse-chap-md5
refuse-eap
require-mschap-v2
require-mppe-128
ms-dns $DNS1
ms-dns $DNS2
proxyarp
nodefaultroute
lock
nobsdcomp
novj
novjccomp
nologfd
EOF

# Prompt for user credentials
echo "Please enter user credentials for VPN access:"
read -p "Username: " VPN_USER
read -s -p "Password: " VPN_PASSWORD
echo

# Add VPN user
echo "$VPN_USER * $VPN_PASSWORD *" >> /etc/ppp/chap-secrets

# Enable IP forwarding
echo "Enabling IP forwarding..."
echo "net.ipv4.ip_forward = 1" > /etc/sysctl.d/60-pptp-vpn.conf
sysctl -p /etc/sysctl.d/60-pptp-vpn.conf

# Get primary network interface
PRIMARY_INTERFACE=$(ip -o -4 route show to default | awk '{print $5}' | head -1)
echo "Detected primary network interface: $PRIMARY_INTERFACE"

# Configure iptables for NAT
echo "Configuring iptables rules..."
iptables -t nat -A POSTROUTING -o $PRIMARY_INTERFACE -j MASQUERADE
iptables -A INPUT -p tcp --dport 1723 -j ACCEPT
iptables -A INPUT -p gre -j ACCEPT
iptables -A FORWARD -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --clamp-mss-to-pmtu

# Save iptables rules
echo "Saving iptables rules..."
iptables-save > /etc/iptables/rules.v4

# Create systemd service for auto-reconnect
echo "Creating auto-reconnect service..."
cat > /etc/systemd/system/pptp-monitor.service << EOF
[Unit]
Description=PPTP VPN Monitor Service
After=network.target pptpd.service

[Service]
Type=simple
ExecStart=/usr/local/bin/pptp-monitor.sh
Restart=always
RestartSec=10s

[Install]
WantedBy=multi-user.target
EOF

# Create the monitor script
cat > /usr/local/bin/pptp-monitor.sh << EOF
#!/bin/bash

while true; do
  if ! systemctl is-active --quiet pptpd; then
    echo "\$(date): PPTP service down, restarting..." >> /var/log/pptp-monitor.log
    systemctl restart pptpd
  fi
  sleep 60
done
EOF

# Make the monitor script executable
chmod +x /usr/local/bin/pptp-monitor.sh

# Enable services to start on boot
echo "Enabling services to start on boot..."
systemctl enable pptpd
systemctl enable pptp-monitor.service

# Start services
echo "Starting services..."
systemctl start pptpd
systemctl start pptp-monitor.service

# Verify service status
echo "Verifying service status..."
systemctl status pptpd --no-pager

echo "================================================="
echo "PPTP VPN Server Installation Complete"
echo "================================================="
echo "Server IP: $(hostname -I | awk '{print $1}')"
echo "Username: $VPN_USER"
echo "Password: [Hidden for security]"
echo "Local IP: $LOCAL_IP"
echo "Remote IP Range: $REMOTE_IP_RANGE"
echo "DNS Servers: $DNS1, $DNS2"
echo "================================================="
echo "To connect, use these settings on your VPN client:"
echo "- VPN Type: PPTP"
echo "- Server: $(hostname -I | awk '{print $1}')"
echo "- Username: $VPN_USER"
echo "- Password: [Your password]"
echo "================================================="
