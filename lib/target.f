listHost(){
local host
host=$1
if [ "$host" = host ]
then
    cat $hostpath|sort -n|awk '{printf "%-20s %-9s %-20s\n",$1,$2,$3}'
else
    :
fi
}
listGroup(){
local group host_exp
group=$1
if [ "$group" = "group" ]
then
    ls $AEPATH/data/hosts|grep -v default
else
    if [ -f $groupbase/$group ]
    then
        host_exp=`cat $groupbase/$group|xargs -n10000|sed -r "s/ / |^/g"`
        cat $hostpath|sort -n|grep -P "^$host_exp "|awk '{printf "%-20s %-20s\n",$1,$3}'
    else
        echo -e "\nThe group you input doesn't exist!\n"
        exit 1
    fi
fi
}
listTarget(){
local args
args="$*"
if [ "$args" = host ]
then
    listHost host
else
    listGroup $args
fi
}
getUserPassword(){
if [[ "$args" =~ -samepassword ]] 
then
    while [ -z $user ]
    do
        read -p "Please input the user for above hosts you will add to AE: "  user
    done
    while [ -z $password ]
    do
        read -p "Please input the password matched to user $user of the hosts you will add to AE : "  password
    done
else   
    unset user password
    while [ -z $user ]
    do
        read -p "Please input the user of the host $host you will add to AE: "  user
    done
    while [ -z $password ]
    do
        read -p "Please input the password matched to user $user of the host $host you will add to AE : "  password
    done
    echo
fi
}
addHost(){
local host
host=$1
cat $hostpath|grep "^$host " > /dev/null 2>&1 && echo -e "\nThe Host $host input exists in AE!" && return 1
getUserPassword
setAuth $host $user $password
if [ $? -eq 0 ]
then
    echo "$host $user connected $password" >> $hostpath
    return 0
else
    echo -e "\nFailed to add $host\n"
    return 1
fi
}
addHosts(){
local host hosts
hosts=$1
for host in ${hosts//,/ }
do
    addHost $host
done
}
addGroup(){
local group hosts
group=$1
hosts=$2
if [ -f $groupbase/$group ]
then
    echo -e "\nthe group you input exists.\n"
    exit 1
else
    touch $groupbase/$group
fi
[ -z "$hosts" ] && return 0
for host in ${hosts//,/ }
do
    cat $hostpath|grep "^$host " > /dev/null 2>&1 && echo "$host" >> $groupbase/$group || addHost $host
done   
}
addTarget(){
local args user password
args="$*"
if [[ "$args" =~ -group ]]
then
    [[ "$args" =~ -host ]] && getArg "$args" group,host || getArg "$args" group
    addGroup ${ARGVS[0]} ${ARGVS[1]}
elif [[ "$args" =~ -host ]]
then
    getArg "$args" host
    addHosts ${ARGVS[0]}
else
    usage
    exit 1
fi
}
renameGroup(){
local name
name=$1
if [ -f $groupbase/$group ]
then
    mv $groupbase/$group $groupbase/$name
else
    echo -e "\nThe group you input doesn't exist\n"
    exit 1
fi
}
chgGroup(){
local ops hosts
ops=$1
hosts=$2
if [ ! -f $groupbase/$group ]
then
    echo -e "\nThe group you input doesn't exist\n"
    exit 1
fi
! listHost host |grep -P "$host " > /dev/null 2>&1 && echo -e "\nThe host you input doesn't exist.\n" && exit 1
if [ $ops = add ]
then
    for host in ${hosts//,/ }
    do
        ! cat $hostpath|grep -P "^$host " > /dev/null 2>&1 && echo -e "\nPlease add host $host to AE first\n" && return 1
        cat $groupbase/$group|grep -P "^$host$" > /dev/null 2>&1 && echo -e "\nThe host $host you input already added into group $group.\n" || echo $host >> $groupbase/$group
    done
else
    for host in ${hosts//,/ }
    do
        cat $groupbase/$group|grep -P "^$host$" > /dev/null 2>&1 && sed -i -r "/^$host$/"d $groupbase/$group || echo -e "\nThe host $host you input doesn't belong to group $group\n"
    done
fi
}

chgTarget(){
local args group user password
args="$*"
group=`echo "$args"|awk '{print $1}'`
if [[ "$args" =~ -rename ]]
then
    getArg "$args" rename
    renameGroup ${ARGVS[0]}
elif [[ "$args" =~ -add ]]
then
    getArg "$args" add
    chgGroup add ${ARGVS[0]}   
elif [[ "$args" =~ -rm ]]
then
    getArg "$args" rm
    chgGroup rm ${ARGVS[0]}    
else
    usage
    exit 1
fi
}
delHosts(){
local host hosts
hosts=$1
for host in ${hosts//,/ }
do
    sed -i -r "/^$host|^$host /"d $groupbase/*
done
}
delGroup(){
local group delhost hosts 
unset delhost
group=$1
[ "$group" = default ] && echo -e "\nThe group default couldn't be deleted!\n" && exit 1
! listGroup group|grep -w $group > /dev/null 2>&1 && echo -e "\nThe group you input doesn't exist!\n" && exit 1
hosts=`cat $groupbase/$group`
rm -f $groupbase/$group
if [ `echo "$hosts"|wc -l` -gt 0 ]
then
    while [ "$delhost" != yes -a "$delhost" != no ]
    do
        read -p "The group you input includes hosts,will you delete them from AE at this time! (yes or no)? " delhost
    done
    [ "$delhost" = yes ] && delHosts "$hosts"
fi
}
delTarget(){
local args hosts host
args="$*"
if [[ "$args" =~ -host ]]
then
    getArg "$args" host
    delHosts ${ARGVS[0]}
elif [[ "$args" =~ -group ]]
then
    getArg "$args" group
    delGroup ${ARGVS[0]}
else
    usage
    exit 1
fi
}

checkHost(){
local host user
host=$1
user=`echo "$hostcontent"|grep -P "(^| )$host( |$)"|awk '{print $2}'`
[ -z "$user" ] && echo -e "\nThe host $host you input doesn't exist!\n" && return 1
checkAuth $host $user
if [ $? -eq 0 ]
then
    sed -i -r "/^$host/s/(connected|disconnected)/connected/" $hostpath
else
    sed -i -r "/^$host/s/(connected|disconnected)/disconnected/" $hostpath
fi
}
checkTarget(){
local args group host hostcontent
args="$*"
hostcontent=`cat $hostpath`
if [[ "$args" =~ -group ]]
then
    getArg "$args" group
    for host in `cat $groupbase/${ARGVS[0]}`
    do
        checkHost $host
    done
    listGroup ${ARGVS[0]}
elif [[ "$args" =~ -host ]]
then
    getArg "$args" host
    for host in ${ARGVS[0]//,/ }
    do
        checkHost $host
        listHost host|grep -P "^$host "
    done
else
    usage
    exit 1
fi  
}

recoverTarget(){
local args group host hosts user password
args="$*"
if [[ "$args" =~ all-lost ]]
then
    hosts=`cat $hostpath|grep disconnected|awk '{print $1}'`
elif [[ "$args" =~ -host ]]
then
    getArg "$args" host
    hosts=${ARGVS[0]//,/ }
else
    usage
    exit 1
fi

for host in $hosts
do
    ! cat $hostpath|grep -P "^$host " > /dev/null 2>&1 && echo -e "\nThe host $host you input doesn't exist!\n" && return 1
    getUserPassword
    setAuth $host $user $password
    if [ $? -eq 0 ]
    then
        echo -e "\nHave built connection to host $host\n"
        sed -i -r "/^$host/s/disconnected/connected/" $hostpath
    fi
done
}
