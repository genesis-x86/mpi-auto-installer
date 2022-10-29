#!/bin/bash

# Checks if netcat is installed, if not it installs it. Skips if ran with -i argument
if [ "$#" == "-i" ]; then
    if [ "$(dpkg-query -W --showformat='${Status}\n' netcat|grep "install ok installed" )" == "install ok installed" ]; then
        
        echo -e "Installing dependencies..."
        sudo apt-get update -y >/dev/null
        sudo apt-get install netcat -y >/dev/null
        echo "Done!"
        
    fi
    
    # Checks if nfs-common is installed, if not it installs is
    if [ "$(dpkg-query -W --showformat='${Status}\n' nfs-common|grep "install ok installed" )" == "install ok installed" ]; then
        
        echo -e "Installing dependencies..."
        sudo apt-get update -y >/dev/null
        sudo apt-get install nfs-common -y >/dev/null
        echo "Done!"
        
    fi
fi

# Creates a backup folder for all files being replaced
if [ ! -d "./backup" ]; then
    mkdir backup
fi

# Function to copy and move a specific file to /backup folder and put
# another file in its place
function move_file(){
    sudo mv $1 ./backup/$2
    sudo mv $3 $4
}

if [ "$1" == "-ng" ] && [ -n $2 ] && [ -n $3 ]; then
    
    ping -w 1 -c 1 $2 > /dev/null
    SUCCESS=$?

    # echo $SUCCESS
    
    if [ "$SUCCESS" != "0" ]; then
        echo "Error: IP cannot be reached"
        exit
    fi
    
    echo "Listening..."
    
    sudo netcat -l $3
    
    
else
    
    echo -e "Welcome to Pleiades Node installer version 0.3! \n"
    
    read -p "Enter the IP of your Master node: " IP
    
    echo "Pinging..."
    ping -c1 $slave_ip 1>/dev/null 2>/dev/null
    SUCCESS=$?
    # echo $SUCCESS
    
    while [ $SUCCESS -eq 0 ]
    do
        
        echo "Ping from $IP was not successful, please try again"
        read -p "Enter the IP of your Master node: " IP
        
        ping -c2 $slave_ip 1>/dev/null 2>/dev/null
        SUCCESS=$?
        
    done
    
    echo -e "Ping from $IP successful! \n"
    read -p "Enter the port that the Master is transmitting on[1000]: " PORT
    
    echo "Listening..."
    sudo netcat -l $PORT
    sudo netcat -l $PORT

fi

cat /etc/mpi-config.conf

if test -f ./hosts; then
    
    rm ./backup/hosts > /dev/null
    move_file /etc/hosts hosts "hosts" /etc/
    source "/etc/mpi-config.conf"
    echo -e "\nSuccessfully copied configuration from MASTER!"
fi

echo "sudo mount ${node_names[1]}:/home/$mpi_username"

exit




if [ "$1" == "-d" ]; then
    
    sudo apt-get purge nfs-common -y
    
fi
