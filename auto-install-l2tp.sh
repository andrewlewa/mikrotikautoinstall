#!/bin/bash

# Check if script is run as root
if [ "$EUID" -ne 0 ]; then
  echo "This script must be run as root. Use sudo."
  exit 1
fi

# Install required packages
apt update
apt install -y network-manager network-manager-l2tp xl2tpd

# Prompt for VPN details
read -p "Enter VPN Server IP: " vpn_server
read -p "Enter VPN Username: " vpn_user
read -s -p "Enter VPN Password: " vpn_pass
echo

# Stop NetworkManager to configure
systemctl stop NetworkManager

# Create L2TP connection using nmcli
nmcli connection add type vpn ifname l2tp-vpn con-name l2tp-vpn vpn-type l2tp \
  vpn.data "gateway=$vpn_server, user=$vpn_user, password-flags=0, ipsec-enabled=no, refuse-eap=yes, refuse-pap=yes, refuse-chap=yes, refuse-mschap=yes, refuse-protocols=mschap, require-mppe=yes"

# Store VPN password securely
echo "vpn.secrets.password:$vpn_pass" > /etc/NetworkManager/system-connections/l2tp-vpn.nmconnection
chmod 600 /etc/NetworkManager/system-connections/l2tp-vpn.nmconnection

# Configure xl2tpd
cat > /etc/xl2tpd/xl2tpd.conf << EOL
[global]
access control = no

[lac l2tp-vpn]
lns = $vpn_server
ppp debug = yes
pppoptfile = /etc/ppp/options.l2tp
length bit = yes
redial = yes
redial timeout = 5
max redials = 0
EOL

# Configure PPP options for L2TP
cat > /etc/ppp/options.l2tp << EOL
ipcp-accept-local
ipcp-accept-remote
noccp
noauth
crtscts
mtu 1410
mru 1410
nodefaultroute
lock
connect-delay 5000
name $vpn_user
password $vpn_pass
EOL

# Set permissions for PPP options
chmod 600 /etc/ppp/options.l2tp

# Configure routing to use VPN
cat > /etc/NetworkManager/dispatcher.d/99-vpn-routes.sh << EOL
#!/bin/bash
if [ "\$1" = "l2tp-vpn" ] && [ "\$2" = "up" ]; then
  ip route add default dev ppp0
fi
if [ "\$1" = "l2tp-vpn" ] && [ "\$2" = "down" ]; then
  ip route del default dev ppp0
fi
EOL

chmod +x /etc/NetworkManager/dispatcher.d/99-vpn-routes.sh

# Enable and start services
systemctl enable xl2tpd
systemctl start xl2tpd
systemctl enable NetworkManager
systemctl start NetworkManager

# Enable auto-connect for the VPN
nmcli connection modify l2tp-vpn connection.autoconnect yes

# Connect to VPN
nmcli connection up l2tp-vpn

echo "L2TP VPN setup complete. Configured to auto-connect on boot and reconnect immediately."
echo "VPN connection 'l2tp-vpn' is now active. Routes are set to use the VPN."
