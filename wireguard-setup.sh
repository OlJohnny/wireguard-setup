#!/usr/bin/env bash
# github.com/OlJohnny | 2021
set -e            # exit immediately if a command exits with a non-zero status
set -u            # treat unset variables as an error when substituting
set -o pipefail   # return value of pipeline is status of last command to exit with a non-zero status
# set -o xtrace   # uncomment the previous statement for debugging

# environment
SCRIPT_FULL=$(realpath -s $0)     # stackoverflow.com/a/11114547
SCRIPT_PATH=$(dirname $(realpath -s $0))
SCRIPT_NAME=$(basename $(realpath -s $0))

# text colors
text_info="\e[96m"
text_yes="\e[92m"
text_no="\e[91m"
text_reset="\e[0m"
read_question=$'\e[93m'
read_reset=$'\e[0m'

# check for root privileges
if [[ "${EUID}" -ne 0 ]]
then
    echo -e ""${text_no}"Please run as root."${text_reset}""
    echo -e "Exiting..."
    exit 1
fi

# check if instance of script is already running, stackoverflow.com/a/45429634
if ps ax | grep ${SCRIPT_NAME} | grep --invert-match $$ | grep bash | grep --invert-match grep > /dev/null
then
    echo -e ""${text_no}"Another instance of this script is already running."${text_reset}""
    echo -e "Exiting..."
    exit 1
fi


## global variables
peer_name="<PEER NAME>"
peer_ip="<PEER IP>"
server_subnet="<SERVER SUBNET>"
server_ip="<SERVER IP>"
server_port="<SERVER PORT>"
server_interface"<SERVER INTERFACE>"


# loop question: restart wireguard
_var1func(){
read -p ""${read_question}"Do you want to restart wireguard? This will temporarily disconnect all wg connections (y|n): "${read_reset}"" var1
if [[ "${var1}" == "y" ]]
then
	echo -e ""${text_yes}"Restarting wireguard..."${text_reset}""
	$(wg-quick down wg0 || :)
    wg-quick up wg0
elif [[ "${var1}" == "n" ]]
then
	echo -e ""${text_no}"Not restarting wireguard"${text_reset}""
else
	_var1func
fi
}


# TODO: check if system is running on some kind of debian
# TODO: confirm existing wireguard installation & setup & link to installation guide: https://www.wireguard.com/install/


# get server information
echo ""
read -p ""${read_question}"Enter server IP/Domain: "${read_reset}"" server_ip
read -p ""${read_question}"Enter server Wireguard port: "${read_reset}"" server_port
read -p ""${read_question}"Enter server wireguard interface (eg. wg0): "${read_reset}"" server_interface
read -p ""${read_question}"Enter wireguard subnet (as CIDR, eg. 192.168.11.0/24): "${read_reset}"" server_subnet


# get peer information
echo ""
read -p ""${read_question}"Enter peer IP (local Wireguard network, eg 192.168.11.5): "${read_reset}"" peer_ip
read -p ""${read_question}"Enter peer name (for key naming, no spaces & '/'): "${read_reset}"" peer_name


# generate keys
echo -e "\n"${text_info}"Generating peer keys in '"${SCRIPT_PATH}"/wireguard-keys'..."${text_reset}""
# if wireguard folder in home directory doesnt exist, create it
if [[ ! -d ""${SCRIPT_PATH}"/wireguard-keys" ]]
then
	mkdir "${SCRIPT_PATH}"/wireguard-keys
fi
cd "${SCRIPT_PATH}"/wireguard-keys
wg genkey | tee peer_"${server_interface}"_"${peer_name}"_private.key | wg pubkey > peer_"${server_interface}"_"${peer_name}"_public.key
wg genpsk > peer_"${server_interface}"_"${peer_name}"_preshared.key
chown root:root -f *.key
chmod 770 -f *.key


# append server config
echo -e "\n"${text_info}"Adding new peer to server config..."${text_reset}""
echo "
# peer_"${peer_name}":
[Peer]
PublicKey = "$(cat peer_"${server_interface}"_"${peer_name}"_public.key)"
PresharedKey = "$(cat peer_"${server_interface}"_"${peer_name}"_preshared.key)"
AllowedIPs = "${peer_ip}"/32" >> /etc/wireguard/"${server_interface}".conf


# ask to restart wireguard
echo ""
_var1func


# TODO: ask which 'AllowedIPs' to use: 0.0.0.0/0, 192.168.11.0/24, custom


# print peer config
echo -e "\n"${text_info}"Use the following configuration for your new peer:"${text_reset}""
echo "[Interface]
Address = "${peer_ip}"/24
Privatekey = "$(cat peer_"${server_interface}"_"${peer_name}"_private.key)"\n

[Peer]
PublicKey = "$(cat server_"{$server_interface}"_public.key)"
PresharedKey = "$(cat peer_"${server_interface}"_"${peer_name}"_preshared.key)"
AllowedIPs = "${server_subnet}"
PersistentKeepalive = 30
Endpoint = "${server_ip}":"${server_port}""


## exiting
echo -e "\n"${text_info}"Finished\nExiting..."${text_reset}""
