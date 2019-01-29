#!/bin/bash

set -ex

NIC="eth0"
IP="192.168.1.2"
NETMASK="255.255.255.0"

NTOPNG_PORT="44444"
PIHOLE_PORT="55555"

PI_USER_PASSWORD="bananas999"
PIHOLE_WEB_ADMIN_PASSWORD="admin"

HOSTNAME="pi-firewall"

##########################################################
### IT'S UNUSUAL TO NEED TO MODIFY ANYTHING BELOW HERE ###
##########################################################

NTOPNG_CONF_FILE="/etc/ntopng/ntopng.conf"

PIHOLE_URL="https://install.pi-hole.net"
PIHOLE_CONF_DIR="/etc/pihole"
PIHOLE_CONF_FILE="${PIHOLE_CONF_DIR}/setupVars.conf"

########################################
### DON'T MODIFY ANYTHING BELOW HERE ###
########################################

function log {
  set +x
  echo -e "\n$1\n"
  set -x
}

# Lock down the pi account
function set_pi_user_password {
  log "Setting password of user pi to $PI_USER_PASSWORD"
  echo "pi:${PI_USER_PASSWORD}" | chpasswd
}

# Add ntopng repo
function add_ntopng_repo {
  log "Configuring ntopng apt repo"
  wget http://packages.ntop.org/apt/ntop.key
  apt-key add ntop.key
  rm -f ntop.key
  echo "deb http://apt.ntop.org/stretch_pi armhf/" > /etc/apt/sources.list.d/ntop.list
  echo "deb http://apt.ntop.org/stretch_pi all/" >> /etc/apt/sources.list.d/ntop.list
}

# Install packages
function add_and_update_packages {
  log "Updating packages & installing dependencies"
  apt-get update
  apt-get upgrade -y
  apt-get install -y vim htop ntopng ufw
  apt autoremove
}

# Configure network & servics
function configure_network_and_services {
  # Set the hostname
  hostnamectl set-hostname $HOSTNAME
  echo "$IP $HOSTNAME" >> /etc/hosts

  # Configure ntopng interface & port
  log "Configuring ntopng to bind to port $NTOPNG_PORT on interface $NIC"
  echo "-i=$NIC" >> $NTOPNG_CONF_FILE
  echo "-w=$NTOPNG_PORT" >> $NTOPNG_CONF_FILE
  echo "--commmunity" >> $NTOPNG_CONF_FILE

  # Define network configuration
  log "Configuring interface $NIC in /etc/network/interfaces"
cat << EOF >> /etc/network/interfaces
auto lo $NIC

iface lo inet loopback

allow hot-plug $NIC
iface $NIC inet static
        address $IP
        netmask $NETMASK
        dns-nameservers $IP
EOF

  # Disable DHCP
  log "Disabling DHCP daemomn"
  systemctl disable dhcpcd.service
  systemctl stop dhcpcd.service
}

# Cycle network and services to pick up config changes
function restart_networking_and_services {
  # Restart networking
  log "Restarting networking"
  /etc/init.d/networking restart

  # Ensure services are enabled at boot
  log "Configuring ssh, ufw & ntopng to start at boot"
  systemctl enable ssh
  systemctl enable ntopng
}

function install_pihole {
  # Define pihole configuration
  log "Configuring pihole install configuration file $PIHOLE_CONF_FILE"
  mkdir -p $PIHOLE_CONF_DIR
cat << EOF >> $PIHOLE_CONF_FILE
PIHOLE_INTERFACE=$NIC
IPV4_ADDRESS=$IP/24
QUERY_LOGGING=true
INSTALL_WEB_SERVER=true
INSTALL_WEB_INTERFACE=true
LIGHTTPD_ENABLED=true
BLOCKING_ENABLED=true
WEBPASSWORD=998ed4d621742d0c2d85ed84173db569afa194d4597686cae947324aa58ab4bb
DNSMASQ_LISTENING=single
PIHOLE_DNS_1=8.8.8.8
PIHOLE_DNS_2=8.8.4.4
PIHOLE_DNS_3=208.67.222.222
PIHOLE_DNS_4=208.67.220.220
DNS_FQDN_REQUIRED=true
DNS_BOGUS_PRIV=true
DNSSEC=true
CONDITIONAL_FORWARDING=false
DHCP_ACTIVE=false
EOF

  # Install pihole
  log "Installing pihole"
  curl -L $PIHOLE_URL | bash /dev/stdin --unattended
  pihole -g
  pihole -a -p $PIHOLE_WEB_ADMIN_PASSWORD
  sed -i -e "s/= 80/= $PIHOLE_URL/g" /etc/lighttpd/lighttpd.conf
}

# main script
set_pi_user_password
add_ntopng_repo
add_and_update_packages
configure_network_and_services
restart_networking_and_services
install_pihole

set +x
echo "ntopng web admin portal: https://$IP:$NTOPNG_PORT (exposed only on $NIC)"
echo "pihole web admin portal: http://$IP:$PIHOLE_PORT/admin (exposed only on $NIC)"

echo -e "\nYou can check on the status of ntopng by running: systemctl status ntopng"
echo "You can check on the status of pihole by running: pihole status"

echo -e "\nInstallation has finished.  You can reboot your system by running 'reboot'."
