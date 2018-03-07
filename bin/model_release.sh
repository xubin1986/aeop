#!/bin/bash

getArg(){
#example: getArg "$args" add,delete [1,1],1 means the value could be empty
local j opt opts args opts_exp opts_data args_data isempty
unset ARGVS
args=$1
opts=$2
isempty=$3
isempty=(${isempty//,/ })
opts_exp="-`echo "$opts"|sed -r "s/,/ |-/g"` "
args_data=`echo "$args "|sed -r "s/$opts_exp/\n&/g"|grep -vP "^$"`
opts_data=`echo $opts|sed "s/,/ /g"`
j=0
for opt in $opts_data
do
    ! echo "$args_data"|grep -P "\-$opt$|\-$opt " > /dev/null 2>&1 && usage && exit 1
    ARGVS[$j]=`echo "$args_data"|grep -oP "(?<=-$opt$|-$opt ).*"|sed -r "s/\s+/ /g;s/^\s|\s$//g"`   
    [ -z "${ARGVS[$j]}" -a "${isempty[$j]}" != 1 ] && echo -e "\nValue of Option -$opt could not be empty!\n" && usage && exit 1
    j=$[$j+1] 
done
}

usage(){
cat << EOF
Error!
Usage:
        model_release -ip IP -port Port -user User -pw Password -store Remote_Path -file Local_Path
        
EOF
}

#main code

! uname|grep -w Linux > /dev/null 2>&1 && echo -e "\nmode_release could be only executed by linux os.\n" && exit 1
! which expect > /dev/null 2>&1 && echo -e "\nPlease install expect first!\n" && exit 1

getArg "$*" ip,port,user,pw,store,file
TIMEOUT=3600
step1=10.146.2.220
password1='1qaz.2wsx'
step2=10.146.18.55
password2='1qaz.2wsx'
step3=10.146.26.103
password3='1qaz.2wsx'
ip="${ARGVS[0]}"
port="${ARGVS[1]}"
user="${ARGVS[2]}"
pw="${ARGVS[3]}"
store="${ARGVS[4]}"
file="${ARGVS[5]}"
tfile=`basename $file`
cache1=/disk1/ftpcache/$tfile
cache2=/data/ftpcache/$tfile
cache3=/data/ftpcache/$tfile

expect << EOF
set timeout $TIMEOUT
spawn scp -p $file $step1:$cache1
expect {
    "(yes/no)?" { send "yes\r";exp_continue}
    "word" {send "$password1\r"}
}
expect {
    "100%" {puts "info:file is on $step1"}
    timeout {exit 1}
}
expect eof
EOF
[ $? -eq 1 ] && exit 1

expect << EOF
set timeout $TIMEOUT
spawn ssh $step1
expect {
    "(yes/no)?" { send "yes\r";exp_continue}
    "word" {send "$password1\r"}
}
expect "*#"
send "ifconfig bond0;scp -p $cache1 $step2:$cache2\r"
expect {
    "(yes/no)?" { send "yes\r";exp_continue}
    "word" {send "$password2\r"}
}
expect {
    "100%" {puts "info:file is on $step2"}
    timeout {exit 1}
}
expect "*#"
send "rm -rf $cache1;ssh $step2\r"
expect {
    "(yes/no)?" { send "yes\r";exp_continue}
    "word" {send "$password2\r"}
}
expect "*#"
send "ifconfig bond0;scp -p $cache2 $step3:$cache3\r"
expect {
    "(yes/no)?" { send "yes\r";exp_continue}
    "word" {send "$password3\r"}
}
expect {
    "100%" {puts "info:file is on $step3"}
    timeout {exit 1}
}
expect "*#"
send "rm -rf $cache2;ssh $step3\r"
expect {
    "(yes/no)?" { send "yes\r";exp_continue}
    "word" {send "$password3\r"}
}
expect "*#"
send "ftpupload.sh $ip $port $user '$pw' $store $tfile\r"
expect {
    -re "-rw.*$tfile" {puts "\ninfo:file is on ftpserver $ip\n"}
    timeout {exit 1}
}
expect "*#"
send "rm -rf $cache3;ifconfig bond0;exit\r"
expect "*#"
send "ifconfig bond0;exit\r"
expect "*#"
send "ifconfig bond0;exit\r"
expect eof
EOF