#!/bin/bash
###################################################
## PURPOSE: Created by Cloud 66. Script reports  ##
## system information to the endpoint supplied.  ##
## Bash is required / IPv4 supported only.       ##
##                                               ##
## IMPORTANT: this script is time-locked to only ##
## work for a limited time window once generated ##
###################################################

# endpoint definition
secret_key='342c7cb620e30f4a63ee7d351b3011ff17356af7'
auth_key='cc9a3d73a8c344d6bdb738e5c706a083'

# tags
tags=''

# ensure we can sudo (otherwise we can not create a sudoer user for deployments)
sudo ls / >/dev/null 2>&1
if [ $? -ne 0 ]; then
    echo "Aborted; This script must be run as a user who is a sudoer. This is to allow a new sudoer user to be created for deployment"
    exit 1
fi
ls /etc/cloud66/ppx/ppx.yml >/dev/null 2>&1
if [ $? -eq 0 ]; then
    echo "Aborted; This server is already in use as a Cloud 66 server"
    exit 1
fi

# Detect distro
distro=$(cat /etc/lsb-release | tr '\n' '|' | tr -d '"')
# basic validation
echo "$distro" | grep 'DISTRIB_ID=Ubuntu|DISTRIB_RELEASE=1\(4\|6\|8\).04' >/dev/null 2>&1
if [ $? -ne 0 ]; then
    echo 'Aborted; only Ubuntu 14.04, Ubuntu 16.04 and Ubuntu 18.04 are currently supported'
    exit 1
fi

# Detect the CPU architecture
cpu_architecture=$(getconf LONG_BIT | tr -d '"')
# basic validation
echo "$cpu_architecture" | grep '64' >/dev/null 2>&1
if [ $? -ne 0 ]; then
    echo 'Aborted; only 64bit CPU architecture is currently supported'
    exit 1
fi

# Read or generate unique ID for this server
if sudo [ -e '/etc/cloud66/registered_server/unique_id' ]; then
    read -r unique_id < <(sudo cat '/etc/cloud66/registered_server/unique_id')
else
    unique_id='b03f2aba-81aa-4e7a-89cc-40d8cb5e085b'
    sudo mkdir -p '/etc/cloud66/registered_server'
    printf "%s" "${unique_id}" | sudo tee '/etc/cloud66/registered_server/unique_id' >/dev/null 2>&1
fi

# Detect kernel
kernel=$(uname -r | tr -d '"')
# Detect hostname:
hostname=$(hostname | tr -d '"')
# Detect CPU info
cpus=$(cat /proc/cpuinfo | tr '\n' '|' | tr -d '"' | tr '\t' ' ')
# Detect mem info
memory=$(cat /proc/meminfo | tr '\n' '|' | tr -d '"')
# Detect internal IP address:
local_ips=$(ifconfig | grep -E '^(eth|ens)[[:digit:]]{1,}' | head -1 | awk '{print $1}' | xargs -I {} ifconfig {} | grep -Eo 'inet (addr:)?([0-9]*\.){3}[0-9]*' | grep -Eo '([0-9]*\.){3}[0-9]*' | tr '\n' '|')
# Detect disk space info
disk_space=$(df -H | grep -E '\s/$' | awk '{print $2"|"$5}')
# Detect disk inodes info
disk_inodes=$(df -iH | grep -E '\s/$' | awk '{print $2"|"$5}')

# post results
result=$(echo "{\"server_data\":{\"unique_id\":\"$unique_id\"," \
"\"kernel\":\"$kernel\"," \
"\"distro\":\"$distro\"," \
"\"hostname\":\"$hostname\"," \
"\"cpu_architecture\":\"$cpu_architecture\"," \
"\"cpus\":\"$cpus\"," \
"\"memory\":\"$memory\"," \
"\"local_ips\":\"$local_ips\"," \
"\"disk_space\":\"$disk_space\"," \
"\"disk_inodes\":\"$disk_inodes\"," \
"\"tags\":\"$tags\"}}" \
| curl -s -u $auth_key:X  -d @- -X POST --header "Content-Type:application/json"  https://app.cloud66.com/api/tooling/register/$secret_key.json)
if [ $? -ne 0 ]; then
    echo 'Command failed: Aborting, please contact your administrator for further help'
    echo "Error: $result"
    exit 1
fi
status=$(echo "$result" | grep -Po '(?<=result":")[^"]+')
if [ "$?" != "0" -o "$status" != "success" ]; then
    error_message=$(echo "$result" | grep -Po '(?<=error_message":")[^"]+')
    echo 'Command failed: Aborting, please contact your administrator for further help'
    echo "Error: $error_message"
    exit 1
fi
user_name=$(echo "$result" | grep -Po '(?<=user":")[^"]+')
if [ "$?" != "0" -o "$user_name" == "" ]; then
    error_message=$(echo "$result" | grep -Po '(?<=error_message":")[^"]+')
    echo 'Command failed: Aborting, please contact your administrator for further help'
    echo "Error: $error_message"
    exit 1
fi
user_id=$(echo "$result" | grep -Po '(?<=user_id":")[^"]+')
if [ "$?" != "0" -o "$user_id" == "" ]; then
    error_message=$(echo "$result" | grep -Po '(?<=error_message":")[^"]+')
    echo 'Command failed: Aborting, please contact your administrator for further help'
    echo "Error: $error_message"
    exit 1
fi
user_group_id=$(echo "$result" | grep -Po '(?<=user_group_id":")[^"]+')
if [ "$?" != "0" -o "$user_group_id" == "" ]; then
    error_message=$(echo "$result" | grep -Po '(?<=error_message":")[^"]+')
    echo 'Command failed: Aborting, please contact your administrator for further help'
    echo "Error: $error_message"
    exit 1
fi
ssh_public=$(echo "$result" | grep -Po '(?<=public":")[^"]+')
if [ $? -ne 0 -o "$ssh_public" == "" ]; then
    error_message=$(echo "$result" | grep -Po '(?<=error_message":")[^"]+')
    echo 'Command failed: Aborting, please contact your administrator for further help'
    echo "Error: $error_message"
    exit 1
fi

# add user if it doesn't already exist
sudo id -u "$user_name" >/dev/null 2>&1
if [ $? -ne 0 ]; then
    # define a end to the sequence
    start_id="$user_id"
    end_id=$(($start_id + 1000000))
    # find a user/group that doesn't exist
    # step in 1000s
    for i in $(seq "$start_id" 10000 "$end_id")
    do
      # check /etc/passwd for existence of ids
      # starting with a large number so not
      # worried about partial grep matches
      sudo grep "$i" /etc/passwd >/dev/null 2>&1
      user_res=$?
      # we want group AND user not present
      sudo grep "$i" /etc/group >/dev/null 2>&1
      group_res=$?
      if [ "$user_res" -ne 0 ] && [ "$group_res" -ne 0 ] ; then
        # we can use this user_id
        user_id="$i"
        # we know that the group id doesn't exist either
        user_group_id="$i"
        break
      fi
    done

    sudo groupadd --gid "$user_group_id" "$user_name"
    echo "$user_name group [CREATED]"
    sudo useradd --create-home --shell /bin/bash --uid "$user_id" --gid "$user_group_id" "$user_name" >/dev/null 2>&1
    sudo usermod -p * "$user_name" >/dev/null 2>&1
    echo "$user_name [CREATED]"
    sudo usermod -aG sudo "$user_name" >/dev/null 2>&1
    echo "$user_name ALL=(ALL:ALL) NOPASSWD:ALL" | sudo tee /etc/sudoers.d/"$user_name" >/dev/null 2>&1
    sudo chmod 0440 /etc/sudoers.d/"$user_name" >/dev/null 2>&1
    echo "$user_name [SUDO]"
else
    echo "$user_name [EXISTS]"
fi

# ensure that the /etc/cloud66 directory has the correct permissions
sudo chown -R "$user_name":"$user_name" '/etc/cloud66' >/dev/null 2>&1
# always ensure the authorized keys are correct
sudo mkdir -p /home/"$user_name"/.ssh >/dev/null 2>&1
echo "$ssh_public" | sudo tee /home/"$user_name"/.ssh/authorized_keys >/dev/null 2>&1
sudo chown -R "$user_name":"$user_name"  /home/"$user_name"/.ssh >/dev/null 2>&1
sudo chmod -R u=rwX /home/"$user_name"/.ssh >/dev/null 2>&1
echo "$user_name [CONFIGURED]"
echo "Done!"
