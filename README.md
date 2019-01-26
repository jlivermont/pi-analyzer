# pi-firewall

## Introduction

The pi-firewall is a collection of tools for protecting and monitoring a small home network.  It installs the latest community edition of [ntop](https://www.ntop.org/products/traffic-analysis/ntop/) for monitoring and anlyzing the home network.  It also configures the [UFW](https://wiki.ubuntu.com/UncomplicatedFirewall) firewall and enables [NAT](https://en.wikipedia.org/wiki/Network_address_translation).
TBD

## Installation

### Installing Pi

This tutorial is based on Raspbian (specifically, Raspbian Lite).  Raspbian download images can be found [here](https://www.raspberrypi.org/downloads/raspbian/).  Additional information for installing Raspbian can be found [here](https://www.raspberrypi.org/documentation/installation/installing-images/).  This tutorial assumes that the user is starting with a fresh install of Raspbian on a Pi (ideally a Pi 2 or 3).

### Getting the install script

The install script can be downloaded from GitHub with wget:

```bash
$ wget https://raw.githubusercontent.com/jlivermont/pi-firewall/master/install.sh
```

### Configuring the install script

At the top of the install script, there are a number of variables that you should define with values that make sense for your system and network.  If correct values are set in these variables, no code or logic will need to be touched further below in the script.

Once the script is downloaded and configured, you can run it:

```bash
$ /bin/bash install.sh
```
