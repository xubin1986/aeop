#!/bin/bash
file=./aeop
echo "#!/bin/bash" > $file
cat ../lib/* >> $file
echo >> $file
if [ "$1" = -d ]
then
    echo -e "\n\nset -x" >>  $file
fi
cat << EOF >> $file
AEPATH=~/.ae
hostpath=\$AEPATH/data/hosts/default
groupbase=\$AEPATH/data/hosts
flowbase=\$AEPATH/data/flow
poolbase=$AEPATH/data/pool
deploybase=\$AEPATH/data/deploy
PID=\$\$
TIMEOUT_SSH=60
TIMEOUT_EXPECT=5
mkdir -p \$groupbase \$flowbase \$deploybase \$poolbase
touch \$hostpath
EOF
cat aeop.sh|grep -A 10000 "MAIN CODE" >> $file
cat $file|wc -l
shc -T -r -f $file
rm -rf $file $file.x.c
mv $file.x $file
chmod 111 $file
echo "Generate executable file $file."
