# wireguard-setup
Simple script that helps with the generation of configs and keys for peers in an existing wireguard installation.

This script needs to be run on the wireguard server as root.

## Installation
Get this script via:
<pre>sudo wget https://raw.githubusercontent.com/OlJohnny/wireguard-setup/master/wireguard-setup.sh -O ./wireguard-setup.sh | sudo chmod +x ./wireguard-setup.sh</pre>

## Usage
* Execure script on server
* Copy & Paste generated config (output in terminal) to the client
* Execute the following commands on the client:
  * <code>sudo chmod -Rf 770 /etc/wireguard</code> Config Readability limited to root
  * <code>sudo systemctl enable wg-quick@wg0</code> Enable Wireguard Tunnel at system startup
