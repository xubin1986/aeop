#!/bin/bash

#check global path

if [ -z $AEPATH ]
then
    echo "Error!Please define base path AEPATH in environment first!"
    echo "example:echo 'export AEPATH=/root/code/aeop' >> /root/.bash_profile"
    exit 1
fi


#define global path
hostpath=$AEPATH/data/hosts/default
groupbase=$AEPATH/data/hosts
flowbase=$AEPATH/data/flow
PID=$$

#import config
. $AEPATH/etc/aeop.cfg

#import functions
for func in `ls $AEPATH/lib/*`
do
    . $func
done



#MAIN CODE
#checking

! uname|grep -w Linux > /dev/null 2>&1 && echo -e "\naeop could be only executed by linux os.\n" && exit 1
! which expect > /dev/null 2>&1 && echo -e "\nPlease install expect first!\n" && exit 1

args="$*"
[ -z "$1" ] && usage && exit 1
[ "$1" = -help ] && usageDetail|grep -v ERROR && exit 0
args=`echo "$args"|sed -r "s/$1\s+//"`
case $1 in 
    -list)
        listTarget "$args"
        ;;
    -add)
        addTarget "$args"
        ;;
    -chg)
        chgTarget "$args"
        ;;
    -del)
        delTarget "$args"
        ;;  
    -check)
        checkTarget "$args"
        ;;
    -login)
        login "$args"
        ;;
    -copyfile)
        distribute "$args"
        ;;
    -recover)
        recoverTarget "$args"
        ;;
    -host|-group)
        opsTarget "$args"
        ;;
    -deploy)
        deployTarget "$args"
        ;;
    -flow)
        flowTarget "$args"
        ;;
    *)
        usage
        exit 1
esac
