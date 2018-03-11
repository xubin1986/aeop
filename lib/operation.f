display(){
cat << EOF
Host:             $host
Return Code:      $rc

STDOUT:
$out

STDERROR:
$error

EOF
}
displayFlow(){
cat << EOF
Host:             $host
Command:          $cmd
Return Code:      $rc

STDOUT:
$out

STDERROR:
$error

EOF
}
displayFormat(){
out=`echo $out`
cat << EOF
$host,,,$rc,,,$out,,,$error
EOF
}


int_exec(){
local file content ret password
touch $outfile $errorfile
file=/tmp/int_exec.$PID.$host
password=`cat $hostpath|grep -P "^$host "|awk '{print $4}'`
expect << EOF > $file 2>&1
set timeout $TIMEOUT_EXPECT
spawn ssh $user@$host
expect {
    "(yes/no)?" { send "yes\r";exp_continue}
    "word" {send "$password\r"}
}
expect {
    "#" {send "echo \"$cmd\" > /tmp/cmd.$host \&\& bash /tmp/cmd.$host;echo rc=\$? \&\& rm -f /tmp/cmd.$host;\r"}
    "word" {puts "\nrc=1002";exit 1}
    timeout {puts "\nrc=1003";exit 1}
}
expect "#"
send "exit\r"
expect eof
EOF

content=`cat $file`
rm -f $file
ret=`echo "$content"|grep -oP "(?<=rc=)[0-9]+"|tail -1`
content=`echo "$content"|grep -A 1000000 "/tmp/cmd.$PID"|grep -B 1000000 -P "^rc=[0-9]+"|sed '1d;$d'`
if [ "$ret" = 0 ]
then
    echo "$content" > $outfile
elif [ "$ret" = 1002 ]
then
    echo -e "\nThe password is wrong!\n" > $errorfile
elif [ "$ret" = 1003 ]
then
    echo -e "\nThe prompt shell is not supported!\n" > $errorfile
else
    echo "$content" > $errorfile
fi
return $ret
}

execCmdOnly(){
local cmd cmd0 host hosts rc out error depend user hostcontent ret profile
hosts=$1
cmd=$2
depend=$3
cmd0=". /etc/profile;$cmd"
hostcontent=`cat $hostpath`
outfile=/tmp/outfile.$PID
errorfile=/tmp/errorfile.$PID
user=`echo "$hostcontent"|grep -P "(^| )$host( |$)"|awk '{print $2}'`
#! echo "$hostcontent"|grep -P "^$host .* connected" > /dev/null 2>&1 && echo -e "Skipped execution on Host $host as it is disconnectd\n" && continue
checkAuth $host $user
ret=$?
if [ $ret -eq 0 ]
then
    echo "$cmd0" | ssh $user@$host "cat > /tmp/cmd.$PID && bash /tmp/cmd.$PID"
    rc=$?
else
    echo -e "Skipped execution on Host $host as it is disconnectd\n"
    exit 1
fi
return $rc
}

execCmd(){
local cmd cmd0 host hosts rc out error depend user hostcontent ret profile
hosts=$1
cmd=$2
depend=$3
cmd0=". /etc/profile;$cmd"
hostcontent=`cat $hostpath`
outfile=/tmp/outfile.$PID
errorfile=/tmp/errorfile.$PID
for host in $hosts
do
    user=`echo "$hostcontent"|grep -P "(^| )$host( |$)"|awk '{print $2}'`
    #! echo "$hostcontent"|grep -P "^$host .* connected" > /dev/null 2>&1 && echo -e "Skipped execution on Host $host as it is disconnectd\n" && continue
    checkAuth $host $user
    ret=$?
    if [ $ret -eq 0 ]
    then
        echo "$cmd0" | ssh $user@$host "cat > /tmp/cmd.$PID && bash /tmp/cmd.$PID;ret=\$? && rm -f /tmp/cmd.$PID;exit \$ret" 1>$outfile 2>$errorfile
        rc=$?
    elif [ $ret -eq 1 ]
    then
        int_exec
        rc=$?
    else
        echo -e "Skipped execution on Host $host as it is disconnectd\n"
        rc=1001
        continue
    fi
    out=`cat $outfile`
    error=`cat $errorfile`
    rm -f $outfile $errorfile
    if [ "$depend" = yes ]
    then
        displayFlow
    elif [ "$format" = yes ]
    then
        displayFormat
    else
        display
    fi
    [ "$depend" = yes -a $rc -ne 0 ] && return 1
done
return 0
}

execCmd_parallel(){
local cmd cmd0 host hosts rc out error user hostcontent ret profile
hosts=$1
cmd=$2
cmd0=". /etc/profile;$cmd"
hostcontent=`cat $hostpath`
mkdir /tmp/$PID

#generate fifo file
fifo=/tmp/file
mkfifo $fifo
exec 6<>$fifo
rm -f $fifo
[ -z "$aeop_thread" ] && aeop_thread=20
for i in `seq $aeop_thread`
do
        echo 
done >&6

for host in $hosts
do
    read -u6
    {
        outfile=/tmp/$PID/outfile.$host
        errorfile=/tmp/$PID/errorfile.$host
        rcfile=/tmp/$PID/rc.$host
        user=`echo "$hostcontent"|grep -P "(^| )$host( |$)"|awk '{print $2}'`
        checkAuth $host $user
        ret=$?
        if [ $ret -eq 0 ]
        then
            echo "$cmd0" | ssh $user@$host "cat > /tmp/cmd.$host && bash /tmp/cmd.$host;ret=\$? && rm -f /tmp/cmd.$host;exit \$ret" 1>$outfile 2>$errorfile
            rc=$?
        elif [ $ret -eq 1 ]
        then
            int_exec
            $rc=$?
        else
            echo -e "Skipped execution on Host $host as it is disconnectd\n"
            rc=1001
        fi
        echo "$rc" > $rcfile
        echo >&6
    } &
done
wait
for host in $hosts
do
    out=`cat /tmp/$PID/outfile.$host`
    error=`cat /tmp/$PID/errorfile.$host`
    rc=`cat /tmp/$PID/rc.$host`
    if [ "$format" = yes ]
    then
        displayFormat
    else
        display
    fi
done
rm -rf /tmp/$PID
return 0
}

execFile(){
local script host hosts cmd
hosts=$1
script=$2
cmd=`cat $script|grep -v '#!'`
[ "$aeop_parallel" = yes ] && execCmd_parallel "$hosts" "$cmd" ||  execCmd "$hosts" "$cmd"
}

opsTarget(){
local args target hosts host hostcontent format
args="$*"
target=`echo "$args"|awk '{print $1}'`
#get hosts which will be execute commands
if listGroup group|grep -w $target > /dev/null 2>&1
then
    hosts=`cat $groupbase/$target`
    echo -e "\nOperation for Group $target are as below:"
else
    hostcontent=`cat $hostpath`
    for host in ${target//,/ }
    do
        ! echo "$hostcontent"|grep -w $host > /dev/null 2>&1 && echo -e "\nPlease add host $host to AE first.\n" && exit 1
    done
    echo -e "\nOperation for Host(s) $target are as below:"
    hosts=${target//,/ }
fi
#check if format is defined
echo "$args"|grep -o " -format" > /dev/null 2>&1 && format=yes && args=${args%-format} || format=no

#being to do operations
if [[ "$args" =~ -cmd ]]
then
    getArg "$args" cmd
    echo -e "Command: ${ARGVS[0]}\n"
    [ "$aeop_parallel" = yes ] && execCmd_parallel "$hosts" "${ARGVS[0]}" || execCmd "$hosts" "${ARGVS[0]}"
elif [[ "$args" =~ -script ]]
then
    getArg "$args" script
    echo -e "Script: ${ARGVS[0]}\n"
    execFile "$hosts" "${ARGVS[0]}"
else
    usage
    exit 1
fi
}

replaceConfig(){
local module
module=$1
if [ $module = ats ]
then
    res="
[acous_model]
acous_model1    = anhui;HMM_16K;/opt/IPS/ats/resource/acmod_16KRnn_sms.bin;all
acous_model2    = anhui;HMM_8KTele;/opt/IPS/ats/resource/acmode_8KTele_sms.bin;all

[lang_model]
lang_model1 = sms;WFST;/opt/IPS/ats/resource/wfst.bin;all
lang_model2 = sms;LM;/opt/IPS/ats/resource/gram.bin;all
lang_model3 = sms;RLM;/opt/IPS/ats/resource/nextg.rnnlmwords.bin;all"


}

deployTarget(){
local module op base host target hostcontent inst_content inst_bin inst_start inst_start_folder inst_start_cmd inst_config inst_base 
args="$*"
module=`echo "$args"|awk '{print $1}'`
hostcontent=`cat $hostpath`
if echo "$args"|grep -oP " -setup" > /dev/null 2>&1
then
    cd $deploybase
    rm -rf $module
    touch $module
    read -p "where does the binary locate? " $base
    read -p "where does the config file locate? " $config_place
    read -p "sdsf? " $locate
    read -p "where does the binary locate? " $locate
elif echo "$args"|grep -oP " -init" > /dev/null 2>&1
then
    inst_content=`cat $deploybase/module`
    inst_bin=$poolbase/$module.deploy.tar
    inst_base=`echo "$inst_content"|grep ^bin|awk -F ',,,' '{print $2}'`
    inst_config=`echo "$inst_content"|grep ^config|awk -F ',,,' '{print "'$inst_base'"/$2}'`
    inst_config0=`basename $inst_config`
    inst_start=`echo "$inst_content"|grep ^bin|awk -F ',,,' '{print $3}'`
    inst_start_folder=`dirname "$inst_start"`
    inst_start_cmd=`echo "$inst_start"|awk -F '/' '{print $NF}'`
    
    args=${args%-init}
    getArg "$args" host
    target=${ARGVS[0]}
    for host in ${target//,/ }
    do
        ! echo "$hostcontent"|grep -w $host > /dev/null 2>&1 && echo -e "\nPlease add host $host to AE first.\n" && exit 1
        scp -rp $inst_bin $host:/tmp/ 
        execCmdOnly $host "tar -xvpf /tmp/$inst_bin -C /opt/IPS"
        #scp -p $inst_config /tmp/
        cp $poolbase/$inst_config0 /tmp/
        replaceConfig /tmp/$inst_config0 $module
        scp -p /tmp/$inst_config0 $host:$inst_config
        execCmdOnly $host "cd $inst_base/$inst_start_folder;nohup ./$inst_start_cmd > /dev/null 2>&1 &"
        execCmdOnly $host "ps -ef"|grep "$inst_start_cmd"
        done
elif echo "$args"|grep -oP " -update" > /dev/null 2>&1
then
    getArg "$args" host,update
    target=${ARGVS[0]}
    element=${ARGVS[1]}
    inst_content=`cat $deploybase/element`
    inst_bin=$poolbase/$module.deploy.tar
    inst_base=`echo "$inst_content"|grep ^bin|awk -F ',,,' '{print $2}'`
    ! echo "$inst_content"|grep ^$element > /dev/null 2>&1 && echo "Invalid element $element for application $module" && exit 1
    if [ $element = bin ]
    then
        inst_start=`echo "$inst_content"|grep ^bin|awk -F ',,,' '{print $3}'`
        inst_start_folder=`dirname "$inst_start"`
        inst_start_cmd=`echo "$inst_start"|awk -F '/' '{print $NF}'`
        for host in ${target//,/ }
        do
            execCmdOnly $host "cp -p $inst_config /tmp/"
            execCmdOnly $host "ps -ef"|grep "$inst_start_cmd" > /tmp/exsit_proce.$PID
            if cat /tmp/exsit_proce.$PID|grep "$inst_start_cmd" > /dev/null 2>&1
            then
                echo "Found process of $module is running,will kill processes first"
                cat /tmp/exsit_proce.$PID
                pid=`cat /tmp/exsit_proce.$PID`|awk '{print $2}'|sort -n|sort -u|xargs -n10`
                execCmdOnly $host "kill -9 $pid"
                if [ $? -eq 0 ]
                then
                    echo "Succesful to stop $module"
                else
                    echo "Failed to stop $module"
                    exit 1
                fi
            fi
            execCmdOnly "rm -rf $inst_base"
            scp -rp $inst_bin $host:/tmp/
            execCmdOnly $host "tar -xvpf /tmp/$inst_bin -C /opt/IPS"
            scp -p /tmp/$inst_config0 $host:$inst_config
            execCmdOnly $host "cd $inst_base/$inst_start_folder;nohup ./$inst_start_cmd > /dev/null 2>&1 &"
            execCmdOnly $host "ps -ef"|grep "$inst_start_cmd"            
    elif [ $element = mod ]
    then
        :
    else
        :
    fi
else
    usage
    exit 1
fi

}

flowTarget(){
local flow flow0 line host cmd flowpass
flow=`echo $1|sed "s/\.flow//"`
if [ -f $flowbase/$flow.flow ]
then
    echo
    while [ -z "$flowpass" ]
    do
        read -p "Please input the password of Flow $flow: " flowpass 
    done
    ! cat $groupbase/.flowpass|grep -P "$flow:$flowpass" > /dev/null 2>&1 && echo "Password is wrong,exiting..." && exit 1
    echo -e "\nOperation for Flow $flow are as below:\nFlow: $flow\n"
    flow0=$flowbase/$flow.flow
    #checking the syntax
    line=`awk -F ",,," '{print NF}' $flow0|sort -n|sort -u`
    [ $line -ne 2 ] && echo -e "\nPlease check the syntax in Flow $flow" && exit 1
    cat $flow0|while read line
    do
        echo "$line"|grep -P "^#|^$" > /dev/null 2>&1 && continue
        host=`echo "$line"|awk -F ",,," '{print $1}'`
        cmd=`echo "$line"|awk -F ",,," '{print $2}'`
        listGroup group|grep -w $host > /dev/null 2>&1 && host=`cat $groupbase/$host` || host="${host//,/ }"
        execCmd "$host" "$cmd" yes
        [ $? -ne 0 ] && echo "Flow $flow was stopped as above error." && exit 1
    done
else
    vi $flowbase/$flow.flow
    echo
    while [ -z "$flowpass" ]
    do
        read -p "Please set a password for Flow $flow: " flowpass 
    done
    echo "$flow:$flowpass" >> $groupbase/.flowpass
fi
}
distribute(){
local args sourcefile targetfile source targethost host hosts user
args="$*"
getArg "$args" source,target
source=${ARGVS[0]}
target=${ARGVS[1]}
sourcefile=/tmp/source.$PID
hostcontent=`cat $hostpath`
host=`echo "$source"|cut -d : -f 1`

#get source file
if [[ "$source" =~ [a-zA-Z0-9\._-]+:/ ]]
then
    user=`echo "$hostcontent"|grep -P "(^| )$host( |$)"|awk '{print $2}'`
    checkAuth $host $user &&
    ! echo "$hostcontent"|grep -w $host > /dev/null 2>&1 && echo -e "\nPlease add host $host to AE first.\n" && exit 1
    scp -rp $user@$source $sourcefile > /dev/null 2>&1
else
    cp -rp $source $sourcefile
fi
if [ $? -ne 0 ]
then
    echo -e "\nFailed to get source file.\n"
    exit 1
fi

#get target hosts
targethost=`echo ${target/:/ }|awk '{print $1}'`
targetfile=`echo "$target"|sed "s/$targethost://"`
if listGroup group|grep -w $targethost > /dev/null 2>&1
then
    hosts=`cat $groupbase/$targethost`
else
    hostcontent=`cat $hostpath`
    for host in ${targethost//,/ }
    do
        ! echo "$hostcontent"|grep -w $host > /dev/null 2>&1 && echo -e "\nPlease add host $host to AE first.\n" && exit 1
    done
    hosts=${targethost//,/ }
fi

#transfer file to targets
echo 
for host in $hosts
do
    user=`echo "$hostcontent"|grep -P "(^| )$host( |$)"|awk '{print $2}'`
    checkAuth $host $user &&
    scp -rp $sourcefile $user@$host:$targetfile > /dev/null 2>&1
    [ $? -ne 0 ] && echo -e "Failed to diliver file to $host with path $targetfile" || echo -e "Succesful to diliver file to $host with path $targetfile"
done
rm -rf $sourcefile
echo
}
login(){
local host user
host=$1
user=`cat $hostpath|grep -P "(^| )$host( |$)"|awk '{print $2}'`
[ -z "$user" ] && echo -e "\nPlease add host $host to AE first!\n" && exit 1
interact.exp $user $host
}
