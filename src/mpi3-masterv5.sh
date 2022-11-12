#!/bin/bash

# Checks if program is running as root
if [ "$EUID" -ne 0 ]; then
    echo "Please run this program as root"
    exit
fi

version="0.5"
config_file="../etc/auto-mpi.conf"
backup_folder="../backup/"
tmp_folder="../tmp/"
etc_folder="../etc/"
head_ip=$( ip route get 8.8.8.8 | awk -F"src " 'NR==1{split($2,a," ");print a[1]}' )
cluster_names=()
cluster_ips=()

# Checks for debug arguments if the argument is -r then it only regenerates config file.
# If the argument is -d then deletes the entire program structure as if it were a fresh install
# If you would like to delete the user that the script creates for you, run with the second
# argument as the username
if [ "$1" == "-r" ] || [ "$1" == "-d" ]; then
    
    sudo rm $config_file
    
    if [ ! -z $2 ]; then
        sudo deluser --remove-home $2 > /dev/null
    fi
    
    if [ "$1" == "-d" ]; then
        
        sudo rm -r $backup_folder
        sudo rm -r $etc_folder
        sudo rm -r $tmp_folder
        
    fi
fi

# If it cannot find the config folder, it will assume that the program structure has
# not yet been created. If the etc folder has been created it clears the tmp directory
if [ ! -d $etc_folder ]; then
    
    mkdir $etc_folder
    mkdir $tmp_folder
    mkdir $backup_folder
    
else
    
    sudo rm -r $tmp_folder
    mkdir $tmp_folder
    
fi

# Generates an empty config file to /etc/mpi-config, if run with -r paramter it removes
# the config file and generates a new one
function generate_config() {
    
    if [ "$1" == "-r" ]; then
        
        sudo rm $config_file
        
    fi
    
    sudo touch $config_file
    
    sudo echo "version=$version" >> $config_file
    sudo echo "setup_started=1"  >> $config_file
    sudo echo "installed_dependencies=0"  >> $config_file
    sudo echo "cluster_name=''"  >> $config_file
    sudo echo "cluster_size=" >> $config_file
    sudo echo "mpi_distribution=''" >> $config_file
    sudo echo "master=''" >> $config_file
    sudo echo "mpi_username=''" >> $config_file
    sudo echo "secret=''" >> $config_file
    sudo echo "node_names=''" >> $config_file
    sudo echo "node_ips=''" >> $config_file
    sudo echo "input_set=0" >> $config_file
    sudo echo "user_created=0" >> $config_file
    sudo echo "nfs_mounted=0" >> $config_file
    sudo echo "ssh_secured=0" >> $config_file
    sudo echo "mpi_installed=0" >> $config_file
    sudo echo "changed_fstab=0" >> $config_file
    sudo echo "changed_hosts=0" >> $config_file
    sudo echo "changed_exports=0" >> $config_file
    sudo echo "directory_set=0" >> $config_file
    sudo echo "default_port=1000" >> $config_file
    sudo echo "setup_complete=0" >> $config_file
    sudo echo "setup_working=0" >> $config_file
    sudo echo "#" >> $config_file
    
    sleep 0.5
    
    source $config_file
    
    echo -e "Empty master config file generated!"
}

# Function to write config file
function write_config(){
    sudo sed -i "s/^\($1\s*=\s*\).*\$/\1$2/" $config_file
    source "$config_file"
}

# Checks if a config file has been generated by program,
# if not it generates an empty one to /etc/mpi-config.conf
if [ ! -f "$config_file" ]; then
    echo "Generating new config file..."
    sleep 0.5
    generate_config
fi
# Calls the config file and sources its variables
source "$config_file"

if [ -d $etc_folder ] && [ -d $backup_folder ] && [ -d $tmp_folder ] && test -f $config_file; then
    
    write_config directory_set "1"
    
else
    echo "Unknown error, could not create directory for program"
    exit 10
fi

# Only installs dependencies if config file says so
if [ "$installed_dependencies" != "1" ]; then
    echo -e "Updating apt..."
    sudo apt-get update -y >/dev/null
    
    # Checks if netcat and nfs-kernel-server is installed, if not it installs is
    if [ "$(dpkg-query -W --showformat='${Status}\n' netcat|grep "install ok installed" )" != "install ok installed" ]; then
        
        echo -e "Installing Netcat..."
        sudo apt-get install netcat -y >/dev/null
        echo "Done!"
        
        elif [ "$(dpkg-query -W --showformat='${Status}\n' nfs-kernel-server|grep "install ok installed")" != "install ok installed" ]; then
        
        echo "Installing NFS-server..."
        sudo apt-get install nfs-kernel-server -y >/dev/null
        echo "Done!"

        elif [ "$(dpkg-query -W --showformat='${Status}\n' ssh-server|grep "install ok installed")" != "install ok installed" ]; then 

        echo "Installing SSH server..."
        sudo apt-get install ssh-server -y >/dev/null
        echo "Done!"
        
    fi
    
    write_config installed_dependencies "1"
    
fi

# Function to join an array into one string
function join_array() {
    local IFS="$1"
    # shift
    echo "$*"
}

function parity_check(){
    
    echo "DEBUG :: $1 $2"
    
    node_names_array=(${node_names//,/ })
    echo "DEBUG :: NODE NAMES: ${node_names_array[@]}"
    
    
    A="$(cat $1)"
    
    for name in "${node_names_array[@]}"; do
        echo "DEBUG :: NAME: $name"
        
        if [ "$name" != $HOSTNAME ]; then
            
            sudo netcat -l $2 > /run/node-config.conf
            B="$(cat /run/node-config.conf)"
            
            
            if [ "$A" == "$B" ]; then
                
                echo -e "\nParity with $name achieved!"
                
            else
                
                echo -e "\nFiles are not the same"
                echo "DEBUG :: A: $A"
                echo "DEBUG :: B: $B"
                
            fi
            
        fi
        
    done
    
}

function check_nfs(){
    
    # Iterates through the node names and refernces netstat
    node_names_array=(${node_names//,/ })
    connected_nodes=()
    rogue_nodes=()
    
    for name in ${node_names_array[@]}; do
        
        if [ "$name" != "$HOSTNAME" ]; then
            
            if netstat | grep $name>/dev/null ; then
                
                echo "$name connected!"
                connected_nodes+=( "$name" )
                
            else
                
                echo "$name not connected!"
                rogue_nodes+=( "$name" )
                
            fi
            
        fi
        
    done
    
    
    if [ "${#connected_nodes[@]}" == "$cluster_size" ]; then
       
       echo -e "\nAll nodes connected to $HOSTNAME!"
       write_config nfs_mounted 1

    fi
    
    
    
}


clear

echo -e "Welcome to Pleiades MPI installer version 0.5! \n"

# Checks the config file to see if the user has completed any steps, if it has AND the config file
# has not marked off the completion of the process, THEN the user is prompted to choose whether
# to go back where they left off, OR start over with a new config file.
if [ "$input_set" == "1" ] && [ "$setup_complete" != "1" ]; then
    
    echo "Configuration started but not completed, continue setting up [$cluster_name] or start over? "
    echo "   1) Continue"
    echo "   2) Start over"
    echo "   3) Exit"
    read -p "Choose from selection[1]: " option
    
    if [ -z  "$option" ]; then
        
        option="1"
        
        elif [ "$option" == "3" ]; then
        
        exit
        
        elif [ "$option" == "2" ]; then
        
        generate_config -r
        
    fi
    
fi

# If there is data written in the variables that are set in the below loop
# AND $input_set is not equal to 1, then the program assumes the data is junk
while [ "$input_set" != "1" ] && [ "$setup_complete" != "1" ]; do
    
    # Sets master in config file
    write_config master $HOSTNAME
    
    # User inputs name for cluster
    read -p "Enter a name for your cluster: " name
    write_config cluster_name $name
    
    read -p "How many nodes would you like to connect?: " number_of_nodes
    echo
    
    re='^[0-9]+$'
    
    while [ -z $number_of_nodes ] || [[ ! $number_of_nodes =~ $re ]]; do
        
        echo "Error cannot be empty"
        read -p "How many nodes would you like to connect?: " number_of_nodes
        
    done
    
    
    # Sets config file variable
    write_config cluster_size $number_of_nodes
    
    # IP address user input loop, only as many as the user specified
    for ((i=1; i<=$number_of_nodes; i++))
    do
        # The first iteration must be the head node or localhost
        if [ $i -eq 1 ]; then
            
            while [ -z $head_ip ]
            do
                echo "Fatal error. Head node has no IP"
                exit 1
            done
            
            cluster_names+=($HOSTNAME)
            cluster_ips+=($head_ip)
            
        fi
        
        # User inputs node name
        read -p "Enter the name that will be associated to your node, no spaces: " slave_name
        while [ -z "$slave_name" ]; do
            echo "Error cannot be empty"
            read -p "Enter the identification that will be associated to your node: " slave_name
        done
        
        while [[ "$slave_name" =~ " " ]]; do
            echo "Error cannot have spaces"
            read -p "Enter the identification that will be associated to your node: " slave_name
        done
        
        
        # The next iterations must be the nodes that will connect to the localhost
        read -p "Enter the IP of your slave node number $i: " slave_ip
        
        while [ -z "$slave_ip" ]; do
            echo "Error cannot be empty"
            read -p "Enter the IP of your slave node number $i: " slave_ip
        done
        echo "Pinging..."
        ping -c1 $slave_ip 1>/dev/null 2>/dev/null
        SUCCESS=$?
        
        while [ $SUCCESS -ne 0 ]
        do
            
            echo "Ping from $IP was not successful, please try again"
            read -p "Enter the IP of your slave node number $i: " slave_ip
            
            ping -c1 $slave_ip 1>/dev/null 2>/dev/null
            SUCCESS=$?
            
        done
        
        echo "Ping from $slave_ip successful!"
        echo
        
        cluster_ips+=($slave_ip)
        cluster_names+=($slave_name)
        
    done
    
    
    # Joins the arrays with the cluster data, and serializes it to config file
    node_ips_string=$(join_array  ,"${cluster_ips[@]}")
    write_config node_ips "${node_ips_string:1}"
    node_names_string=$(join_array  ,"${cluster_names[@]}")
    write_config node_names "${node_names_string:1}"
    
    write_config input_set "1"
    
done

# Hosts loop, only runs if the config says so
while [ "$changed_hosts" != "1" ] && [ "$setup_complete" != "1" ]; do
    
    hosts_file="../tmp/hosts"
    
    # If a hosts file exists in the relative directory, but the hosts file has not
    # been changed, then delete it
    if [ -f "../backup/hosts" ]; then
        
        sudo rm ../backup/hosts
        
        elif [ -f "/etc/hosts" ]; then
        
        sudo mv /etc/hosts $backup_folder
        echo "Transferred old hosts file to backup!"
        
    fi
    
    # Generates a hosts file
    touch $hosts_file
    echo -e "127.0.0.1 \t localhost" >> $hosts_file
    
    for index in ${!cluster_names[*]}; do
        echo -e "${cluster_ips[$index]} \t ${cluster_names[$index]}" >> $hosts_file
    done
    
    echo -e "\n# The following lines are desirable for IPv6 capable hosts " >> $hosts_file
    echo "::1     ip6-localhost ip6-loopback" >> $hosts_file
    echo "fe00::0 ip6-localnet" >> $hosts_file
    echo "ff00::0 ip6-mcastprefix" >> $hosts_file
    echo "ff02::1 ip6-allnodes" >> $hosts_file
    echo "ff02::2 ip6-allrouters" >> $hosts_file
    
    sudo mv $hosts_file /etc/
    hosts_file="/etc/hosts"
    
    # Gives a timestamp for backup file
    datetime="$(date '+%Y-%m-%d %H:%M:%S')" | sudo sed -i "1s/^/Backup of hosts file created on $datetime\n/" ../backup/hosts
    echo -e "/etc/hosts file generated and updated! \n"
    
    write_config changed_hosts "1"
    
done

# MPI user creation loop
while [ "$user_created" != "1" ] && [ "$setup_complete" != "1" ]; do
    
    echo -e "Which profile name would you like to use for your mpi user? "
    echo -e "   1) mpiuser \n   2) $cluster_name \n   3) Other"
    
    read -p "Profile name selection[1]: " selection
    
    if [ -z "$selection" ]; then
        
        if [ ! -d "/home/mpiuser" ]; then
            write_config mpi_username "mpiuser"
            
        else
            
            echo "Error, user already exists. Enter a different name"
            selection="3"
        fi
        
        elif [ "$selection" == "2" ]; then
        
        write_config mpi_username $cluster_name
        
    fi
    
    if [ "$selection" == "3" ]; then
        
        read -p "Enter your preferred mpi profile name: " user_name
        while [ -z "$user_name" ]; do
            
            echo "Error cannot be empty"
            read -p "Enter your preferred mpi profile name, no spaces: " user_name
            
        done
        
        while [[ "$user_name" =~ " " ]]; do
            
            echo "Error cannot have spaces"
            read -p "Enter your preferred mpi profile name, no spaces: " user_name
            
        done
        
        while [ -d "$user_name" ]; do
            
            echo "Error, user already exists on this machine"
            read -p "Enter your preferred mpi profile name, no spaces: " user_name
            
        done
        
        write_config mpi_username $user_name
    fi
    
    read -s -p "Enter a password for your user: " user_password
    
    while [ -z $user_password ]; do
        
        echo -e "\nError, password for $mpi_username cannot be empty!"
        read -s -p "Enter a password for your user: " user_password
        
    done
    
    
    sudo useradd -m "$mpi_username" -s /bin/bash -u 1500
    echo "$mpi_username:$user_password" | sudo chpasswd
    write_config secret $user_password
    
    echo -e "\nUser [$mpi_username] created!"
    
    write_config user_created "1"
    
done

# Changes exports file, only if the config file says so
while [ "$changed_exports" != "1" ] && [ "$setup_complete" != "1" ]; do
    
    filename="../tmp/exports"
    touch $filename
    
    # Generates an exports file and replaces it with the default one
    for IP in ${cluster_ips[@]}; do
        if [ "$head_ip" != "$IP" ]; then
            sudo echo "/home/$mpi_username $IP(rw,sync,no_subtree_check)" >> $filename
        fi
    done
    
    # If exports exists then send it to backup
    if [ -f /etc/exports ]; then
        
        sudo mv /etc/exports $backup_folder
        
    fi
    
    sudo mv $filename /etc/
    
    # Timestamp does not work
    datetime="$(date '+%Y-%m-%d %H:%M:%S')"
    sudo sed -i "1s/^/Backup of hosts file created on $datetime\n/" ../backup/exports
    echo -e "Moved exports file to backup!"
    
    write_config changed_exports "1"
    
    echo -e "\nRestarting Service..."
    sudo exportfs -a
    sudo service nfs-kernel-server restart
    sleep 0.2
    echo -e "Done!\n"
    echo -e "NFS server for $HOSTNAME has been set up!"
    
done

# Tries to mount filesystem to nodes, only if config file says so
while [ "$nfs_mounted" != "1" ] && [ "$setup_complete" != "1" ]; do
    
    transfer_file="../tmp/transfer"
    
    # Port to transmit netcat data
    read -p "Enter the port to send transfer data to [1000]: " port
    
    if [ -z $port ]; then
        port="1000"
    else
        
        read -p "Keep this port [$port] as the default for node networking?[y/n]: " option
        if [ "$option" != "n" ]; then
            write_config default_port $port
        fi
        
    fi
    
    read -p "Run slave installer with \$(sudo mpi3 -ng $head_ip $port) NOW, before continuing..."
    echo -e "\nTransmitting packets from $head_ip on port $port"
    
    touch $transfer_file
    cat $config_file | sudo tee -a $transfer_file >/dev/null
    cat /etc/hosts | sudo tee -a $transfer_file >/dev/null
    
    transmit_time=1
    
    cluster_ips=(${node_ips//,/ })
    
    
    for IP in ${cluster_ips[@]}; do
        if [ "$head_ip" != "$IP" ]; then
            sudo netcat -w $transmit_time $IP $port < $transfer_file
        fi
    done
    
    echo -e "\nFiles transmitted"
    echo -e "\nWaiting for node confirmation..."
    # WAIT FOR EACH NODE CONFIRMATION
    
    # The main loop MUST run ONCE or else weird stuff happens
    break
done


while [ "$ssh_secured" != "1" ] && [ "$setup_complete" != "1" ]; do 

    
    sudo cd /home/$mpi_username
    read
    cd /home/$mpi_username
    read

    ssh-keygen

    ssh-copy-id localhost
    
    exit


done

exit 0
#EOF