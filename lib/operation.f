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
host=$1
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
    return $?
else
    echo -e "Skipped execution on Host $host as it is disconnectd\n"
    exit 1
fi
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

configtmp(){
cat << EOF
[local]
svc_only                = false
enable_pmcc             = true
enable_pmi              = true 
enable_ldc              = false
best_lic                = 120
max_lic                 = 140
report_lb               = false
report_arm              = true
max_audio_time          = 60
resource_dir            = /opt/IPS/ats/resource
use_max_best_lic        = true
nif_filter              = docker
audio_check             = true
aufmt_convert                   = true

[vad]
speech_chgap = 1000

[arm]
arm_addr        = $ips
rp_interval     = 5

[rmq]
server   = 192.168.81.5:10600;192.168.81.6:10600;192.168.81.7:10600 
topic    = msp_psr_txt_bj
tag      = hf,gz

[acous_cache]
db_path = ./acmod_cache
init_read = true
max_open_file = 10

[cssp]
cssp_enable =
address =
access_id = de5be11cfba9459c81f2b6067aec3b68 
access_pwd = 8adbc061965f47d981f39ae7a90fc265
download_threads= 
timeout = 
retry =

[logger]
file            = /log/engine/ats-sms.log
title           = iFLY Auto Transcribe Service
level           = 71
output          = 1
flush           = 1
maxsize         = 
overwrite       = 0
maxfile         = 1
perfthres       = 200

[iatp]
server_addr             =
server_port             = 
keep_alive              = true
trans_timeout           = 10

[engine]
beam = 140
hist = 4000

[acous_model]
acous_model1    = anhui;HMM_16K;/opt/IPS/ats/resource/$mod1;all
acous_model2    = anhui;HMM_8KTele;/opt/IPS/ats/resource/$mod2;all

[lang_model]
lang_model1 = sms;WFST;/opt/IPS/ats/resource/$mod3;all
lang_model2 = sms;LM;/opt/IPS/ats/resource/$mod4;all
lang_model3 = sms;RLM;/opt/IPS/ats/resource/$mod5;all

[personal_model]
max_model = 70000

[idss]
ds_enable = true
cfg_path  = ./ahsc.cfg

[cslog]
cs_enable               = true
host_name               = 127.0.0.1
port                    = 4545
EOF
}

replaceConfig(){
local ips change
ips=${target//;/ }
mod1=`ls $modtmp|grep 16KRnn`
mod2=`ls $modtmp|grep 8KTele`
mod3=`ls $modtmp|grep wfst`
mod4=`ls $modtmp|grep gram`
mod5=`ls $modtmp|grep nextg`
configtmp > /tmp/$configshort
change=$1
if [ "$change" = yes ]
then
    vi /tmp/$configshort
fi
}

stopAts(){
execCmdOnly $host "ps -ef" | grep "$cmd" | grep -v grep > /tmp/exsit_proce.$PID
if cat /tmp/exsit_proce.$PID|grep "$cmd" > /dev/null 2>&1
then
    echo "Found process of ATS is running,will kill processes first"
    cat /tmp/exsit_proce.$PID
    echo $pid
    pid=`cat /tmp/exsit_proce.$PID|awk '{print $2}'|sort -n|sort -u|xargs -n10`
    execCmdOnly $host "kill -9 $pid"
    if [ $? -eq 0 ]
    then
        echo "Succesful to stop $module for $host"
    else
        echo "Failed to stop $module for $host"
        exit 1
    fi
fi
}            

startAts(){
echo "Starting process of ATS for $host"
echo "Checking the process of ATS for $host"
execCmdOnly $host "cd $cmdbase ;nohup ./$cmd > /dev/null 2>&1 &"
execCmdOnly $host "ps -ef"|grep -v grep |grep -v /tmp/aeop|grep "$cmd" 
}

deployTarget(){
local module hostcontent host target
args="$*"
module=ats
hostcontent=`cat $hostpath`
atsbase=/opt/IPS/ats
cmdbase=/opt/IPS/ats/ats-sms/bin/
cmd="ats -d"
bin=`ls -lrt $poolbase|grep tar$|awk '{print "'$poolbase'/" $NF}'`
binshort=ats.tar
modtmp=`ls -lrt $poolbase|grep resource$|awk '{print "'$poolbase'/" $NF}'`
modtarget=$atsbase/resource
configshort=ats.cfg
configlong=/opt/IPS/ats/ats-sms/bin/ats.cfg

if echo "$args"|grep -oP " -init" > /dev/null 2>&1
then
    args=${args%-init}
    getArg "$args" host
    target=${ARGVS[0]}
    for host in ${target//,/ }
    do
        ! echo "$hostcontent"|grep -w $host > /dev/null 2>&1 && echo -e "\nPlease add host $host to AE first.\n" && exit 1
        echo "Delivering binary and module files to $host..."
        execCmdOnly $host "mkdir -p /opt/IPS"
        scp -rp $bin $host:/tmp/  > /dev/null 2>&1
        execCmdOnly $host "tar -xvpf /tmp/$binshort -C /opt/IPS" > /dev/null 2>&1
        echo "Generating config file..."
        replaceConfig
        scp -p /tmp/$configshort $host:$configlong > /dev/null 2>&1
        startAts
    done
    
elif echo "$args"|grep -oP " -update" > /dev/null 2>&1
then
    getArg "$args" host,update
    target=${ARGVS[0]}
    element=${ARGVS[1]}
    host0=`echo ${target//,/ }|awk '{print $1}'`
    if execCmdOnly $host0 "ls /opt/IPS"|grep ats > /dev/null 2>&1
    then
        :
    else
        echo "ATS has not been deployed yet."
        exit 1
    fi
    if [ $element = bin ]
    then
        for host in ${target//,/ }
        do
            execCmdOnly $host "cp -p $configlong /tmp/"
            stopAts
            echo "Updating binary..."
            execCmdOnly $host "rm -rf $atsbase"
            scp -rp $bin $host:/tmp/ > /dev/null 2>&1
            execCmdOnly $host "tar -xvpf /tmp/$binshort -C /opt/IPS" > /dev/null 2>&1
            echo "Replacing config file..."
            execCmdOnly $host "rm -f $configlong;cp -p /tmp/$configshort $configlong"
            startAts
        done
    elif [ $element = mod ]
    then
        ! [ -f $inst_mod ] && echo "Missing module file." && exit 1
        for host in ${target//,/ }
        do
            stopAts
            execCmdOnly $host "rm -rf $modtarget"
            scp -rp $modtmp $host:$modtarget > /dev/null 2>&1
            replaceConfig
            echo "Generating config file..."
            scp -p /tmp/$configshort $host:$configlong > /dev/null 2>&1
            startAts
        done
    else
        for host in ${target//,/ }
        do
            stopAts
        done
        host0=`echo ${target//,/ }|awk '{print $1}'`
        scp -p $host0:$configlong /tmp/ > /dev/null 2>&1
        vi /tmp/$configshort
        for host in ${target//,/ }
        do
            scp -p /tmp/$configshort $host0:$configlong > /dev/null 2>&1
            startAts
        done
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
