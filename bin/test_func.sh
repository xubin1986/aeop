#!/bin/bash
file=$1
pid=$$
content=`cat ../lib/$file`
echo "$content"|grep -nP "^\w+\(\)|^}"|grep -oP "\d+"|xargs -n2|sed "s/ /,/"|while read lines
do
    echo "$content"|sed -n "$lines"p > /tmp/func.$pid
    source /tmp/func.$pid > /dev/null 2>&1
    if [ $? -ne 0 ]
    then
        func=`cat /tmp/func.$pid|head -1|grep -oP "\w+"`
        cp /tmp/func.$pid /tmp/func
        echo "Func $func syntax error"
    fi
done
rm -f /tmp/func.$pid
