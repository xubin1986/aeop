#!/bin/bash
# By Jason
#set -x
sendinfo(){
curl -k 'https://oapi.dingtalk.com/robot/send?access_token=6efdce2287061845fc08c63fc977aba2ba635b8d32874954d3e9f35273766eb8' -H 'Content-Type:application/json' -d "{\"msgtype\":\"text\",\"text\":{\"content\":\"任务名：移动支付刷卡监控\n处理结果：移动支付刷卡系统出错（严重）\n检查时间：$date_display\n服务器主机名：$host\n服务器IP地址：$ip\n刷卡失败数：$false_count\n请联系运维人员：@丁家盛、@张俊、@小关\"}}"
}

IPS=(nginx1 nginx2 nginx3 nginx4) 

date_check=`date +%Y%m%d -d '1 day ago'`
date_display=`date "+%Y-%m-%d %H:%M:%S"`

for host in ${IPS[*]}
do
    false_count=`salt-ssh $host -r 'cat /var/log/nginx/post_data_'$date_check'.log | grep false |wc -l'|xargs -n10000|grep -oP "(?<=stdout: )[0-9]+"`
    if [ -z "$false_count" ]
    then
        ip='Failed to get ip addr'
        false_count='Failed to get count of failed operation'
        sendinfo
        exit 1
    fi
    if [ "$false_count" = 0 ]
    then
        continue
    else
        if [ -n "$previous" ]
        then
            [ $previous -eq $false_count ] && continue
        fi
        previous=$false_count
        ip=`salt-ssh $host -r 'ifconfig -a'|xargs -n100000|grep -oP "(?<= addr:)[^ ]+"|grep -v 127.0`
        sendinfo
    fi
done
