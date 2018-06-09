usageDetail(){
local script
script=`basename $0`
cat << EOF

ERROR! Usage:

    $script -help
        Show the detail usage of $script.

    $script -list <group|host|Group>
        Show all the hosts and groups or group member if you specified group name.
        
    $script -add <-group Group [-host Host1,Host2...]|-host Host1,Host2...> [-samepassword]
        Add a group with hosts or group only
        Add hosts to AE,separated by , if multi hosts.
        all the hosts you input will use the same user and password to setup the credential if you specify -samepassword
        
    $script -chg Group -add Host1,Host2... 
                    -rm Host1,Host2...
                    -rename NewName
        Change a group by renaming name or modifying group member(member could be separated by , if multi).
        
    $script -del <-group Group|-host Host1,Host2...>
        Delete Hosts from AE,separated by , if multi hosts.
        
    $script -check <-group Group|-host Host1,Host2...>
        Check hosts connection by specified group name or hosts (hosts could be separated by , if multi).
    
    $script -copyfile -source Source -target Target
        Distribute files from Source to Target.Source file could be local file or file on a remote system.
        Target could be a host or a group.
        
    $script -login Host
        Login Host and do interaction
        
    $script -recover <all-lost|-host Host1,Host2...> [-samepassword]
        Recover hosts connection by specified all-lost or hosts (hosts could be separated by , if multi).
        all the hosts you input will use the same user and password to setup the credential if you specify -samepassword
        
    $script -host Host1,Host2... <-cmd CMD|-script File>
        Execute command or script on Host(s) (hosts could be separated by , if multi).
    
    $script -group Group <-cmd CMD|-script File> 
        Execute command or script on Group.
        
    $script -deploy Application (-setup|-host Host1[,Host2,Host3...] (-init|-update Element))
        Setup the properties of an application
        Clean install an application to host.
        Update(upgrade or downgrade ) the application
        
    $script -flow Flow
        Execute flow if the flow exists.
        Make a Flow if the flow doesn't exist.
            how to develope a new flow?
            The content shoud include two parts: Hosts and commands
                1)Hosts and Command should be separated by ,,,
                2)Host(s) could be separated by , if multi
                3)Hosts could be replaced by a group name as well.
            
EOF
}
usage(){
local script
script=`basename $0`
echo 
usageDetail|grep -P "ERROR|^    $script|-rm|-rename"
echo 
}
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

checkAuth(){
local host user
host=$1
user=$2
expect << EOF > /dev/null 2>&1  
set timeout $TIMEOUT_EXPECT
spawn ssh $user@$host "hostname"
expect {
    "connect to host" {exit 2}
    "word" {exit 1}
    eof {exit 0}
    timeout {exit 2}
}
expect eof
EOF
return $?
}

setAuth(){
local host user  password
host=$1
user=$2
password=$3
[ ! -f ~/.ssh/id_rsa.pub ] && echo -e "\nPlease generate ssh rsa key first!\n" && return 1
expect << EOF > /dev/null 2>&1
set timeout $TIMEOUT_EXPECT
spawn ssh-copy-id $user@$host
expect {
    "(yes/no)?" { send "yes\r";exp_continue}
    "ERROR" {exit 1}
    "word:" { send "$password\r"}
    "already exist" {exit 0}
}
expect {
    "added" {exit 0}
    "word:" {exit 1}
    eof {exit 2}
    timeout {exit 3}
}
expect eof
EOF
return $?
}

