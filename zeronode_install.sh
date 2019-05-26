#!/bin/bash

TMP_FOLDER='ZipTemp'
CONFIG_FILE='zero.conf'
CONFIGFOLDER='/root/.zero'
COIN_DAEMON='zerod'
COIN_CLI='zero-cli'
COIN_PATH='/usr/local/bin/'
COIN_REPO='https://github.com/zerocurrencycoin/zero.git'
COIN_ZIP16='https://github.com/zerocurrencycoin/Zero-Wallets/releases/download/NodeOnly/zero-ubuntu-16.04.zip'
COIN_ZIP18='https://github.com/zerocurrencycoin/Zero-Wallets/releases/download/NodeOnly/zero-ubuntu-18.04.zip'
COIN_TGZ=''
COIN_ZIP=''
COIN_NAME='Zero'
COIN_PORT=23801
RPC_PORT=23811
OLDKEY=''

NODEIP=$(curl -s4 icanhazip.com)

BLUE="\033[0;34m"
YELLOW="\033[0;33m"
CYAN="\033[0;36m"
PURPLE="\033[0;35m"
RED='\033[0;31m'
GREEN="\033[0;32m"
NC='\033[0m'
MAG='\e[1;35m'

purgeOldInstallation() {
    echo -e "${GREEN}Searching and removing old $COIN_NAME files and configurations${NC}"
    #kill wallet daemon
    systemctl stop $COIN_NAME.service > /dev/null 2>&1
    sudo killall $COIN_DAEMON > /dev/null 2>&1
	# Save Key
	OLDKEY=$(awk -F'=' '/zeronodeprivkey/ {print $2}' $CONFIGFOLDER/$CONFIG_FILE 2> /dev/null)
	if [ "$?" -eq "0" ]; then
    		echo -e "${CYAN}Saving Old Installation Genkey${NC}"
		echo -e $OLDKEY
	fi
    #remove old ufw port allow
    sudo ufw delete allow $COIN_PORT/tcp > /dev/null 2>&1
    #remove old files
    rm rm -- "$0" > /dev/null 2>&1
    sudo rm -rf $CONFIGFOLDER > /dev/null 2>&1
    sudo rm -rf /usr/local/bin/$COIN_CLI /usr/local/bin/$COIN_DAEMON> /dev/null 2>&1
    sudo rm -rf /usr/bin/$COIN_CLI /usr/bin/$COIN_DAEMON > /dev/null 2>&1
    sudo rm -rf /tmp/*
    echo -e "${GREEN}* Done${NONE}";
}

createSwapFile() {

  if [ ! -f /swapfile ]; then
    fallocate -l 4G /swapfile
    chmod 600 /swapfile
    mkswap /swapfile
    swapon /swapfile
    sh -c "echo '/swapfile none swap sw 0' >> /etc/fstab"
  fi

}


function download_node() {
  echo -e "${GREEN}Downloading and Installing VPS $COIN_NAME Daemon${NC}"
  cd ~ >/dev/null 2>&1
  mkdir $TMP_FOLDER >/dev/null 2>&1
  cd $TMP_FOLDER >/dev/null 2>&1

  if [[ $(lsb_release -d) == *16.04* ]]; then
    wget -q $COIN_ZIP16
    COIN_ZIP=$(echo $COIN_ZIP16 | awk -F'/' '{print $NF}')
  fi

  if [[ $(lsb_release -d) == *18.04* ]]; then
    wget -q $COIN_ZIP18
    COIN_ZIP=$(echo $COIN_ZIP18 | awk -F'/' '{print $NF}')
  fi

  compile_error
  unzip -o $COIN_ZIP >/dev/null 2>&1
  chmod +x $COIN_DAEMON $COIN_CLI
  cp $COIN_DAEMON $COIN_CLI $COIN_PATH
  cd ~ >/dev/null 2>&1
  rm -rf $TMP_FOLDER >/dev/null 2>&1
  clear
}

function configure_systemd() {
  cat << EOF > /etc/systemd/system/$COIN_NAME.service
[Unit]
Description=$COIN_NAME service
After=network.target

[Service]
User=root
Group=root

Type=forking
#PIDFile=$CONFIGFOLDER/$COIN_NAME.pid

ExecStart=$COIN_PATH$COIN_DAEMON -daemon -conf=$CONFIGFOLDER/$CONFIG_FILE -datadir=$CONFIGFOLDER
ExecStop=-$COIN_PATH$COIN_CLI -conf=$CONFIGFOLDER/$CONFIG_FILE -datadir=$CONFIGFOLDER stop

Restart=always
PrivateTmp=true
TimeoutStopSec=60s
TimeoutStartSec=10s
StartLimitInterval=120s
StartLimitBurst=5

[Install]
WantedBy=multi-user.target
EOF

  systemctl daemon-reload
  sleep 3
  systemctl start $COIN_NAME.service
  systemctl enable $COIN_NAME.service >/dev/null 2>&1

  if [[ -z "$(ps axo cmd:100 | egrep $COIN_DAEMON)" ]]; then
    echo -e "${RED}$COIN_NAME is not running${NC}, please investigate. You should start by running the following commands as root:"
    echo -e "${GREEN}systemctl start $COIN_NAME.service"
    echo -e "systemctl status $COIN_NAME.service"
    echo -e "less /var/log/syslog${NC}"
    exit 1
  fi
}


function create_config() {
  mkdir $CONFIGFOLDER >/dev/null 2>&1
  RPCUSER=$(tr -cd '[:alnum:]' < /dev/urandom | fold -w10 | head -n1)
  RPCPASSWORD=$(tr -cd '[:alnum:]' < /dev/urandom | fold -w22 | head -n1)
  cat << EOF > $CONFIGFOLDER/$CONFIG_FILE
rpcuser=$RPCUSER
rpcpassword=$RPCPASSWORD
rpcport=$RPC_PORT
rpcallowip=127.0.0.1
listen=1
server=1
daemon=1
txindex=1
port=$COIN_PORT
EOF
}

function create_key() {

  if [ "$OLDKEY" != "" ]; then
    echo -e "${GREEN}Do you want to use the old Zeronode Key? (yes or no)"
    read -i "yes" ZN
  fi

  if [ "$ZN" == "yes" ] || [ "$ZN" == "y" ]; then
      COINKEY=$OLDKEY
  else
    echo -e "${YELLOW}Enter your ${RED}$COIN_NAME Zeronode GEN Key${NC} or press enter to generate a new key."
    read -e COINKEY
    if [[ -z "$COINKEY" ]]; then
      $COIN_PATH$COIN_DAEMON -daemon
      sleep 30
      if [ -z "$(ps axo cmd:100 | grep $COIN_DAEMON)" ]; then
       echo -e "${RED}$COIN_NAME server could not start. Check /var/log/syslog for errors.{$NC}"
       exit 1
      fi
      COINKEY=$($COIN_PATH$COIN_CLI zeronode genkey)
      if [ "$?" -gt "0" ];
        then
        echo -e "${RED}Wallet not fully loaded. Let us wait and try again to generate the GEN Key${NC}"
        sleep 30
        COINKEY=$($COIN_PATH$COIN_CLI zeronode genkey)
      fi
      $COIN_PATH$COIN_CLI stop
    fi
  fi
clear
}

function update_config() {
  sed -i 's/daemon=1/daemon=0/' $CONFIGFOLDER/$CONFIG_FILE
  cat << EOF >> $CONFIGFOLDER/$CONFIG_FILE
logintimestamps=1
maxconnections=256
#bind=$NODEIP
zeronode=1
externalip=$NODEIP:$COIN_PORT
zeronodeprivkey=$COINKEY

EOF
}


function enable_firewall() {
  echo -e "Installing and setting up firewall to allow ingress on port ${GREEN}$COIN_PORT${NC}"
  ufw allow $COIN_PORT/tcp comment "$COIN_NAME ZN port" >/dev/null
  ufw allow ssh comment "SSH" >/dev/null 2>&1
  ufw limit ssh/tcp >/dev/null 2>&1
  ufw default allow outgoing >/dev/null 2>&1
  echo "y" | ufw enable >/dev/null 2>&1
}


function get_ip() {
  declare -a NODE_IPS
  for ips in $(netstat -i | awk '!/Kernel|Iface|lo/ {print $1," "}')
  do
    NODE_IPS+=($(curl --interface $ips --connect-timeout 2 -s4 icanhazip.com))
  done

  if [ ${#NODE_IPS[@]} -gt 1 ]
    then
      echo -e "${GREEN}More than one IP. Please type 0 to use the first IP, 1 for the second and so on...${NC}"
      INDEX=0
      for ip in "${NODE_IPS[@]}"
      do
        echo ${INDEX} $ip
        let INDEX=${INDEX}+1
      done
      read -e choose_ip
      NODEIP=${NODE_IPS[$choose_ip]}
  else
    NODEIP=${NODE_IPS[0]}
  fi
}


function compile_error() {
if [ "$?" -gt "0" ];
 then
  echo -e "${RED}Failed to compile $COIN_NAME. Please investigate.${NC}"
  exit 1
fi
}


function checks() {
if [[ $(lsb_release -d) != *16.04* ]] && [[ $(lsb_release -d) != *18.04* ]]; then
  echo -e "${RED}You are not running Ubuntu 16.04 or 18.04. Installation is cancelled.${NC}"
  exit 1
fi

if [[ $EUID -ne 0 ]]; then
   echo -e "${RED}$0 must be run as root.${NC}"
   exit 1
fi

if [ -n "$(pidof $COIN_DAEMON)" ] || [ -e "$COIN_DAEMOM" ] ; then
  echo -e "${RED}$COIN_NAME is already installed.${NC}"
  exit 1
fi
}

function prepare_system() {
echo -e "Preparing the VPS to setup. ${CYAN}$COIN_NAME${NC} ${RED}Zeronode${NC}"
DEBIAN_FRONTEND=noninteractive apt-get update
#> /dev/null 2>&1
DEBIAN_FRONTEND=noninteractive apt-get -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" -y -qq upgrade
#>/dev/null 2>&1

echo -e "Installing required packages, it may take some time to finish.${NC}"

apt-get install -y -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" build-essential pkg-config libc6-dev m4 g++-multilib \
autoconf libtool ncurses-dev unzip git python python-zmq zlib1g-dev wget bsdmainutils automake cmake curl
#>/dev/null 2>&1

if [ "$?" -gt "0" ]; then
    echo -e "${RED}Not all required packages were installed properly. Try to install them manually by running the following commands:${NC}\n"
    echo "apt-get update"
    echo "apt install -y build-essential pkg-config libc6-dev m4 g++-multilib \ "
    echo "autoconf libtool ncurses-dev unzip git python python-zmq zlib1g-dev \ "
    echo "wget bsdmainutils automake cmake curl"
    exit 1
fi

clear
}

function getParams() {

  cd
  #Folder Check
  clear
  echo -e "${GREEN}|--------------------------------------------|"
  echo -e "${GREEN}|--------------------------------------------|"
  echo -e "${GREEN}| Checking if params directory               |"
  echo -e "${GREEN}| exist, if not then it will be created.     |"
  echo -e "${GREEN}|--------------------------------------------|"
  echo -e "${GREEN}|--------------------------------------------|"

  if [ -d ~/.zcash-params ]
  then
  echo "-----------------------------------"
  echo "| Params directory already exists |"
  echo "-----------------------------------"

  else

  echo "---------------------------"
  echo "| Making params directory |"
  echo "---------------------------"

  mkdir .zcash-params
  fi

  #proving key
  clear
  echo -e "${GREEN}|-------------------------------------|"
  echo -e "${GREEN}|-------------------------------------|"
  echo -e "${GREEN}| Checking if proving key exist, if   |"
  echo -e "${GREEN}| not it will be downloaded now.      |"
  echo -e "${GREEN}|-------------------------------------|"
  echo -e "${GREEN}|-------------------------------------|"
  echo -e "${GREEN} "
  echo -e "${GREEN} "

  if [ -e ~/.zcash-params/sprout-proving.key ]
  then
  echo -e "${GREEN}|-------------------------------|"
  echo -e "${GREEN}| Proving key already present   |"
  echo -e "${GREEN}|-------------------------------|"

  else

  echo -e "${GREEN}|---------------------------------| "
  echo -e "${GREEN}| Downloading sprout-proving.key  |"
  echo -e "${GREEN}|---------------------------------|"

  wget -O .zcash-params/sprout-proving.key https://z.cash/downloads/sprout-proving.key
  fi

  #verifying key
  clear
  echo -e "${GREEN}|-------------------------------------|"
  echo -e "${GREEN}|-------------------------------------|"
  echo -e "${GREEN}| Checking if verifying key exist, if |"
  echo -e "${GREEN}| not it will be downloaded now.      |"
  echo -e "${GREEN}|-------------------------------------|"
  echo -e "${GREEN}|-------------------------------------|"
  echo -e "${GREEN} "
  echo -e "${GREEN} "

  if [ -e ~/.zcash-params/sprout-verifying.key ]
  then
  echo -e "${GREEN}|---------------------------------|"
  echo -e "${GREEN}| Verifying key already present   |"
  echo -e "${GREEN}|---------------------------------|"

  else

  echo -e "${GREEN}|------------------------------------|"
  echo -e "${GREEN}| Downloading sprout-verifying.key   |"
  echo -e "${GREEN}|------------------------------------|"

  wget -O .zcash-params/sprout-verifying.key https://z.cash/downloads/sprout-verifying.key
  fi

  #sapling spend key
  clear
  echo -e "${GREEN}|-------------------------------------------|"
  echo -e "${GREEN}|-------------------------------------------|"
  echo -e "${GREEN}| Checking if sapling spend key exist, if   |"
  echo -e "${GREEN}| not it will be downloaded now.            |"
  echo -e "${GREEN}|-------------------------------------------|"
  echo -e "${GREEN}|-------------------------------------------|"
  echo -e "${GREEN} "
  echo -e "${GREEN} "

  if [ -e ~/.zcash-params/sapling-spend.params ]
  then
  echo -e "${GREEN}|----------------------------------------|"
  echo -e "${GREEN}| Sapling Spend Params already present   |"
  echo -e "${GREEN}|----------------------------------------|"

  else

  echo -e "${GREEN}|------------------------------------|"
  echo -e "${GREEN}| Downloading sapling-spend.params   |"
  echo -e "${GREEN}|------------------------------------|"

  wget -O .zcash-params/sapling-spend.params https://z.cash/downloads/sapling-spend.params
  fi

  #sapling output key
  clear
  echo -e "${GREEN}|--------------------------------------------|"
  echo -e "${GREEN}|--------------------------------------------|"
  echo -e "${GREEN}| Checking if sapling output key exist, if   |"
  echo -e "${GREEN}| not it will be downloaded now.             |"
  echo -e "${GREEN}|--------------------------------------------|"
  echo -e "${GREEN}|--------------------------------------------|"
  echo -e "${GREEN} "
  echo -e "${GREEN} "

  if [ -e ~/.zcash-params/sapling-output.params ]
  then
  echo -e "${GREEN}|-----------------------------------------|"
  echo -e "${GREEN}| Sapling Output Params already present   |"
  echo -e "${GREEN}|-----------------------------------------|"

  else

  echo -e "${GREEN}|------------------------------------|"
  echo -e "${GREEN}| Downloading sapling-output.params  |"
  echo -e "${GREEN}|------------------------------------|"

  wget -O .zcash-params/sapling-output.params https://z.cash/downloads/sapling-output.params
  fi

  #sprout groth16 key
  clear
  echo -e "${GREEN}|--------------------------------------------|"
  echo -e "${GREEN}|--------------------------------------------|"
  echo -e "${GREEN}| Checking if groth16 key exist, if          |"
  echo -e "${GREEN}| not it will be downloaded now.             |"
  echo -e "${GREEN}|--------------------------------------------|"
  echo -e "${GREEN}|--------------------------------------------|"
  echo -e "${GREEN} "
  echo -e "${GREEN} "

  if [ -e ~/.zcash-params/sprout-groth16.params ]
  then
  echo -e "${GREEN}|----------------------------------|"
  echo -e "${GREEN}| Groth16 Params already present   |"
  echo -e "${GREEN}|----------------------------------|"

  else

  echo -e "${GREEN}|-------------------------------------|"
  echo -e "${GREEN}| Downloading sprout-groth16.params   |"
  echo -e "${GREEN}|-------------------------------------|"

  wget -O .zcash-params/sprout-groth16.params https://z.cash/downloads/sprout-groth16.params
  fi

  clear
}

function important_information() {
 echo
 echo -e "${BLUE}================================================================================================================================${NC}"
 echo -e "${PURPLE}Windows Wallet Guide. https://github.com/zerocurrencycoin/Zero-Wallets${NC}"
 echo -e "${BLUE}================================================================================================================================${NC}"
 echo -e "${GREEN}$COIN_NAME Zeronode is up and running listening on port ${NC}${PURPLE}$COIN_PORT${NC}."
 echo -e "${GREEN}Configuration file is:${NC}${RED}$CONFIGFOLDER/$CONFIG_FILE${NC}"
 echo -e "${GREEN}Start:${NC}${RED}systemctl start $COIN_NAME.service${NC}"
 echo -e "${GREEN}Stop:${NC}${RED}systemctl stop $COIN_NAME.service${NC}"
 echo -e "${GREEN}VPS_IP:${NC}${GREEN}$NODEIP:$COIN_PORT${NC}"
 echo -e "${GREEN}ZERONODE GENKEY is:${NC}${PURPLE}$COINKEY${NC}"
 echo -e "${BLUE}================================================================================================================================"
 echo -e "${CYAN}Follow twitter to stay updated.  https://twitter.com/ZeroCurrencies${NC}"
 echo -e "${BLUE}================================================================================================================================${NC}"
 echo -e "${CYAN}Ensure Node is fully SYNCED with BLOCKCHAIN before starting your Node :).${NC}"
 echo -e "${BLUE}================================================================================================================================${NC}"
 echo -e "${GREEN}Usage Commands.${NC}"
 echo -e "${GREEN}zero-cli zeronode status${NC}"
 echo -e "${GREEN}zero-cli getinfo.${NC}"
 echo -e "${BLUE}================================================================================================================================${NC}"
}

function setup_node() {
  get_ip
  create_config
  create_key
  update_config
  enable_firewall
  important_information
  configure_systemd
}


##### Main #####
clear

purgeOldInstallation
createSwapFile
checks
prepare_system
getParams
download_node
setup_node
