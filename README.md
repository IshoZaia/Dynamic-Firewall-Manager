# Open-Port---GSConnect WIP
This script is a NetworkManager dispatcher that simplifies the management of UFW firewall rules for GSConnect. It opens the necessary ports only when connected to a trusted network and closes them upon disconnection.

For Wi-Fi connections, it adds a layer of security by verifying the MAC address of the access point, protecting against potential SSID spoofing and evil twin attacks.
## Features

**Automatic Port Management**: Opens GSConnect ports (1714:1764) when you connect to a trusted network and closes them when you disconnect.

**Interactive Trust**: Prompts the user with a zenity dialog to trust or block unknown networks.

**Wi-Fi Security**: For Wi-Fi networks, it saves the access point's MAC address. If the MAC address changes for a known network, it issues a security warning and keeps the ports closed.

**Logging**: All actions are logged to /var/log/gsconnect_firewall.log.
## How it Works
This script is designed to be placed in the ```/etc/NetworkManager/dispatcher.d/``` directory.
NetworkManager executes scripts in this directory in response to network events.
1. **On Connection**:
- The script closes existing GSConnect firewall rules
- It checks the if the current network connection ID is in the trusted list
- When connected to Wi-Fi it compares the current MAC address with the saved one
- If the network is trusted the GSConnect ports are opened in UFW
- If the network is not trusted, it prompts the user to trust it. If the user trusts the network it along with the MAC address are stored in the trusted list and the ports are opened.
- If a MAC mismatch occurs for a trusted Wi-Fi network, a warning is displayed and the ports remain closed (Still testing)
2. **On Disconnection**:
- The script removes all firewall rules previously applied.

## Installation
1. Copy this script to the NetworkManager dispatcher directory ```/etc/NetworkManager/dispatcher.d```
- Recommended name would be *30-gsconnect-firewall.sh*
2. Make the file executable:
- ```sudo chmod +x /etc/NetworkManager/30-gsconnect-firewall.sh```
3. The current configuration does not automatically detect user variables, therefore these must be hardcoded to the run_as_user function
- To obtain the necessary values run these commands and copy the results to the run_as_user function:
  - USER_NAME: ```whoami```
  - USER_ID: ```id -u```
  - USER_DISPLAY: ```echo $DISPLAY```
  - USER_DBUS_ADDRESS: ```echo $DBUS_SESSION_BUS_ADDRESS```
  - USER_XAUTHORITY: ```echo $XAUTHORITY```

*Note on restart/reboot some of these variables will change breaking the script, currently working on this issue*
## Requirements
1. NetworkManager
2. Uncomplicated Firewall (ufw)
3. Zenity
4. iw
## To Be Completed
- Removing need for hardcoding, automatically detecting the necessary variables
- Ability to configure multiple ports to open on trusted networks
- UI for settings 
