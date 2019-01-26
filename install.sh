#!/bin/bash

PUBLIC_NIC="eth1"
INTERNAL_NIC="eth0"
INTERNAL_NIC_NETMASK="255.255.255.0"
INTERNAL_NETWORK_CIDR="192.168.1.0/24"

SSHD_PORT="45678"
NTOPNG_PORT="3000"
NAMESERVERS="8.8.8.8 192.168.1.1"

# Install packages
apt-get install -y vim htop ntopng ufw

# Configure ntopng interface & port
sed -i -e 's/^\s*-w=.*$/-i='"$INTERNAL_NIC"'\n-w='"$NTOPNG_PORT"'/g' /etc/ntopng.conf

# Define network configuration
cat << EOF >> /etc/network/interfaces
auto lo $PUBLIC_NIC $INTERNAL_NIC

iface lo inet loopback
iface $PUBLIC_NIC inet dhcp

iface eth0 inet static
        address $INTERNAL_NIC_IP
        netmask $INTERNAL_NIC_NETMASK
        dns-nameservers $NAMESERVERS
EOF

# Configure sshd port
sed -i -e 's/^\s*#Port.*$/Port '"$SSHD_PORT"'/g' /etc/ssh/sshd_config

# Configure firewall
ufw default deny incoming
ufw default allow outgoing

# Allow SSH
ufw allow in on $INTERNAL_NIC to any port $SSHD_PORT

# Allow ntopng
ufw allow in on $INTERNAL_NIC to any port $NTOPNG_PORT

# Enable packet forwarding
sed -i -e 's/^\s*DEFAULT_FORWARD_POLICY.*$/DEFAULT_FORWARD_POLICY="ACCEPT"/g' /etc/default/ufw
sed -i -e 's|^#\s*net/ipv4/ip_forward.*$|net/ipv4/ip_forward=1|g' /etc/ufw/sysctl.conf

# Configure the NAT table
sed -i -e 's/*filter/*nat\n:POSTROUTING ACCEPT [0:0]\n-A POSTROUTING -s '"$INTERNAL_NETWORK_CIDR"' -o $PUBLIC_NIC -j MASQUERADE\nCOMMIT\n\n*filter/g' /etc/ufw/before.rules

# Cycle the firewall
ufw disable
ufw enable

systemctl ssh restart
systemctl ufw restart
