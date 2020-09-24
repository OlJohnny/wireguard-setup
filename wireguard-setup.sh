#!/usr/bin/env bash
# github.com/OlJohnny | 2020

set -o errexit
set -o pipefail
set -o nounset
# set -o xtrace		# uncomment the previous statement for debugging


## global variables
peer_name="<PEER NAME>"
peer_ip="<PEER IP>"
server_ip="<SERVER NAME>"
server_port="<SSH PORT>"


## text output colors
text_info="\e[96m"
text_yes="\e[92m"
text_no="\e[91m"
text_reset="\e[0m"
read_question=$'\e[93m'
read_reset=$'\e[0m'


# loop question: restart wireguard
_var1func(){
read -p ""${read_question}"Do you want to restart wireguard? This will temporarily disconnect all wg connections (y|n): "${read_reset}"" var1
if [[ "${var1}" == "y" ]]
then
	echo -e ""${text_yes}"Restarting wireguard..."${text_reset}""
	wg-quick down wg0
    wg-quick up wg0
elif [[ "${var1}" == "n" ]]
then
	echo -e ""${text_no}"Not restarting wireguard"${text_reset}""
else
	_var1func
fi
}


## check for root privilges
if [[ "${EUID}" != 0 ]]
then
	echo -e ""${text_no}"Please run as root. Root privileges are needed to create and modify configurations/files"${text_reset}""
	exit
fi


# TODO: confirm existing wireguard installation & setup


# get server information
echo ""
read -p ""${read_question}"Enter server IP/Domain: "${read_reset}"" server_ip
read -p ""${read_question}"Enter server Wireguard port: "${read_reset}"" server_port


# get peer information
echo ""
read -p ""${read_question}"Enter peer IP (local Wireguard network): "${read_reset}"" peer_ip
read -p ""${read_question}"Enter peer name (for key naming): "${read_reset}"" peer_name


# generate keys
echo ""
echo -e ""${text_info}"Generating peer keys..."${text_reset}""
# if wireguard folder in home directory doesnt exist, create it
if [[ ! -d "./wireguard" ]]
then
	mkdir ./wireguard
fi
cd wireguard
wg genkey | tee peer_"${peer_name}"_private.key | wg pubkey > peer_"${peer_name}"_public.key
wg genpsk > peer_"${peer_name}"_preshared.key
sudo chown root:root -f *.key
sudo chmod 770 -f *.key


# append server config
echo "
# peer_"${peer_name}":
[Peer]
PublicKey = "$(cat peer_"${peer_name}"_public.key)"
PresharedKey = "$(cat peer_"${peer_name}"_preshared.key)"
AllowedIPs = "${peer_ip}"/32" >> /etc/wireguard/wg0.conf


# ask to restart wireguard
echo ""
_var1func


# print peer config
echo ""
echo -e ""${text_info}"Use the following configuration for your new peer:"${text_reset}""
echo ""
echo "[Interface]
Address = "${peer_ip}"/24
Privatekey = "$(cat peer_"${peer_name}"_private.key)"
DNS = 8.8.8.8

[Peer]
PublicKey = "$(cat server_public.key)"
PresharedKey = "$(cat peer_"${peer_name}"_preshared.key)"
AllowedIPs = 192.168.11.0/24
PersistentKeepalive = 30
Endpoint = "${server_ip}":"${server_port}""


## exiting
echo ""
echo -e ""${text_info}"Finished\nExiting..."${text_reset}""
