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
peer_name="<PEER NAME DEFAULT>"
peer_ip="<PEER IP DEFAULT>"
server_subnet="<SERVER SUBNET DEFAULT>"
server_ip="<SERVER IP DEFAULT>"
server_port="<SERVER PORT DEFAULT>"
server_interface="<SERVER INTERFACE DEFAULT>"
allowed_ips="<ALLOWED IPS DEFAULT>"


# loop question: restart wireguard
_var1func(){
read -p ""${read_question}"Do you want to restart wireguard? This will temporarily disconnect all wireguard connections (y|n): "${read_reset}"" var1
if [[ "${var1}" == "y" ]]
then
	echo -e ""${text_yes}"Restarting wireguard..."${text_reset}""
	$(wg-quick down "${server_interface}" || :)
    wg-quick up "${server_interface}"
elif [[ "${var1}" == "n" ]]
then
	echo -e ""${text_no}"Not restarting wireguard"${text_reset}""
else
	_var1func
fi
}

# loop question: generate server keys
_var2func(){
read -p ""${read_question}"Couldn't find any server keys. Do you want to generate new ones? (They will NOT get updated in any pre existing config files) (y|n): "${read_reset}"" var2
if [[ "${var2}" == "y" ]]
then
	echo -e ""${text_yes}"Generating server keys..."${text_reset}""
	touch server_"${server_interface}"_private.key
    touch server_"${server_interface}"_public.key
    touch server_"${server_interface}"_preshared.key
    chown root:root -f *.key
    chmod 770 -f *.key
    # generate peer keys
    wg genkey | tee server_"${server_interface}"_private.key | wg pubkey > server_"${server_interface}"_public.key
    wg genpsk > server_"${server_interface}"_preshared.key
elif [[ "${var2}" == "n" ]]
then
	echo -e ""${text_no}"Not generating server keys.\nAs we can't find any server keys, exiting ..."${text_reset}""
else
	_var2func
fi
}

# loop question: delete local copies of peer keys
_var3func(){
read -p ""${read_question}"Do you want to delete local copies of peer key files? They are no longer needed if you have copied the peer config from above. (y|n): "${read_reset}"" var3
if [[ "${var3}" == "y" ]]
then
	echo -e ""${text_yes}"Deleting local copies of peer key files..."${text_reset}""
	rm peer_"${server_interface}"_"${peer_name}"_private.key
    rm peer_"${server_interface}"_"${peer_name}"_public.key
    rm peer_"${server_interface}"_"${peer_name}"_preshared.key
elif [[ "${var3}" == "n" ]]
then
	echo -e ""${text_no}"Not deleting local copies of peer key files."${text_reset}""
else
	_var3func
fi
}

# loop question: AllowedIPs
_var4func(){
echo -e ""${read_question}"Which (peer) IP range should be routed through the wireguard tunnel:\n 0: 0.0.0.0/0 (Route all traffic through wireguard)\n 1: "${server_subnet}" (Route local traffic through wireguard)\n c: Enter a custom subnet"${read_reset}""
read -p "" var4
if [[ "${var4}" == "0" ]]
then
	echo -e ""${text_yes}"Setting 0.0.0.0/0 as AllowedIPs..."${text_reset}""
	allowed_ips="0.0.0.0/0"
elif [[ "${var4}" == "1" ]]
then
	echo -e ""${text_yes}"Setting "${server_subnet}" as AllowedIPs..."${text_reset}""
    allowed_ips="${server_subnet}"
elif [[ "${var4}" == "c" ]]
then
    read -p ""${read_question}"Enter IP range for wireguard routing (e.g. 192.168.50.0/24): "${read_reset}"" allowed_ips
else
	_var4func
fi
}

# loop question: build initial server config
_var5func(){
read -p ""${read_question}"Couldn't find a server config for interface "${server_interface}". Do you want to generate a new config at '/etc/wireguard/"${server_interface}".conf'? (y|n): "${read_reset}"" var5
if [[ "${var5}" == "y" ]]
then
    ip -br a
    echo ""
    read -p ""${read_question}"Enter the network interface over which the wireguard server should connect to the internet (e.g. eth0): "${read_reset}"" server5_interface
    read -p ""${read_question}"Enter the network address & range the server should be reachable at in the wireguard network (e.g. 192.168.11.1/24): "${read_reset}"" server5_address
	echo -e ""${text_info}"Generating new server config..."${text_reset}""
	echo "[Interface]
Address = "${server5_address}"
SaveConfig = false
PostUp = iptables -A FORWARD -i "${server_interface}" -j ACCEPT; iptables -A FORWARD -o "${server_interface}" -j ACCEPT; iptables -t nat -A POSTROUTING -o "${server5_interface}" -j MASQUERADE
PostDown = iptables -D FORWARD -i "${server_interface}" -j ACCEPT; iptables -D FORWARD -o "${server_interface}" -j ACCEPT; iptables -t nat -D POSTROUTING -o "${server5_interface}" -j MASQUERADE
ListenPort = "${server_port}"
PrivateKey = "$(cat server_"${server_interface}"_private.key)"" > /etc/wireguard/"${server_interface}".conf
elif [[ "${var5}" == "n" ]]
then
	echo -e ""${text_no}"Not generating a new server config."${text_reset}""
else
	_var5func
fi
}


# TODO: check if system is running on some kind of debian


# check if wireguard is installed
if [[ $(dpkg-query --show --showformat='${Status}' wireguard 2>/dev/null | grep --count "ok installed") == 0 ]];
then
	echo -e ""${text_no}"Package 'wireguard' needs to be installed"${text_reset}""
    exit
fi

# check if wireguard-tools is installed
if [[ $(dpkg-query --show --showformat='${Status}' wireguard-tools 2>/dev/null | grep --count "ok installed") == 0 ]];
then
	echo -e ""${text_no}"Package 'wireguard-tools' needs to be installed"${text_reset}""
    exit
fi


# get server information
echo ""
read -p ""${read_question}"Enter Server IP/Domain: "${read_reset}"" server_ip
read -p ""${read_question}"Enter Server Wireguard Port: "${read_reset}"" server_port
read -p ""${read_question}"Enter Server Wireguard Interface (eg. wg0): "${read_reset}"" server_interface
read -p ""${read_question}"Enter Server Wireguard Subnet (as CIDR, eg. 192.168.11.0/24): "${read_reset}"" server_subnet
# get peer information
echo ""
read -p ""${read_question}"Enter Peer Name (for key naming, no spaces & '/'): "${read_reset}"" peer_name
read -p ""${read_question}"Enter Peer IP (local Wireguard network, eg 192.168.11.5): "${read_reset}"" peer_ip


# if wireguard folder in home directory doesnt exist, create it
if [[ ! -d ""${SCRIPT_PATH}"/wireguard-keys" ]]
then
	mkdir "${SCRIPT_PATH}"/wireguard-keys
fi
cd "${SCRIPT_PATH}"/wireguard-keys


# check for existing server keys
if [[ ! -f ""${SCRIPT_PATH}"/wireguard-keys/server_"${server_interface}"_private.key" ]] || [[ ! -f ""${SCRIPT_PATH}"/wireguard-keys/server_"${server_interface}"_public.key" ]] || [[ ! -f ""${SCRIPT_PATH}"/wireguard-keys/server_"${server_interface}"_preshared.key" ]]
then
    echo ""
    _var2func
fi


# check for existing wireguard config
if [[ ! -f "/etc/wireguard/"${server_interface}".conf" ]]
then
    echo ""
    _var5func
fi


# generate peer keys
echo -e "\n"${text_info}"Generating Peer keys in '"${SCRIPT_PATH}"/wireguard-keys'..."${text_reset}""
# touch key files and update permissions to prevent a warning message by wireguard
touch peer_"${server_interface}"_"${peer_name}"_private.key
touch peer_"${server_interface}"_"${peer_name}"_public.key
touch peer_"${server_interface}"_"${peer_name}"_preshared.key
chown root:root -f *.key
chmod 770 -f *.key
# generate peer keys
wg genkey | tee peer_"${server_interface}"_"${peer_name}"_private.key | wg pubkey > peer_"${server_interface}"_"${peer_name}"_public.key
wg genpsk > peer_"${server_interface}"_"${peer_name}"_preshared.key


# append server config
echo -e "\n"${text_info}"Adding new peer to server config..."${text_reset}""
echo "
# peer_"${peer_name}":
[Peer]
PublicKey = "$(cat peer_"${server_interface}"_"${peer_name}"_public.key)"
PresharedKey = "$(cat peer_"${server_interface}"_"${peer_name}"_preshared.key)"
AllowedIPs = "${peer_ip}"/32" >> /etc/wireguard/"${server_interface}".conf
chmod 770 /etc/wireguard/"${server_interface}".conf


# ask which 'AllowedIPs' to use
echo ""
_var4func


# ask to restart wireguard
echo ""
_var1func


# print peer config
echo -e "\n"${text_info}"Use the following configuration for your new peer:"${text_reset}""
echo "[Interface]
Address = "${peer_ip}"/24
Privatekey = "$(cat peer_"${server_interface}"_"${peer_name}"_private.key)"\n

[Peer]
PublicKey = "$(cat server_"${server_interface}"_public.key)"
PresharedKey = "$(cat peer_"${server_interface}"_"${peer_name}"_preshared.key)"
AllowedIPs = "${allowed_ips}"
PersistentKeepalive = 30
Endpoint = "${server_ip}":"${server_port}""
echo -e "\n"${text_info}"Tip: You can provide this config as a file to clients by pasting it into '"${peer_name}".conf'"${text_reset}""

# ask to delete local copies of peer keys
echo ""
_var3func

# exiting
echo -e "\n"${text_info}"Finished\nExiting..."${text_reset}""
