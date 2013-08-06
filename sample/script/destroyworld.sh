#!/bin/sh

usage() {
    echo "Usage: $CMDNAME [-c CLUSTER_FILE] [-u USER_NAME]" 1>&2
}

while getopts c:u: OPT
do
    case $OPT in
        "c" ) FLAG_C="TRUE" ; VALUE_C="$OPTARG" ;;
        "u" ) FLAG_U="TRUE" ; VALUE_U="$OPTARG" ;;
          * ) usage
              exit 1 ;;
    esac
done

if [ "$FLAG_C" != "TRUE" ]; then
    usage
    exit 2
fi

if [ "$FLAG_U" != "TRUE" ]; then
    usage
    exit 3
fi

if [ ! -f $VALUE_C ]; then
    usage
    exit 4
fi

while read line
do
    echo $line
    echo "ssh -f $VALUE_U@$line \"kill -KILL \`ps -ef | grep bin/executor | grep -v grep | awk '{ print \$2; }'\`\""
    ssh -f $VALUE_U@$line "kill -KILL \`ps -ef | grep bin/executor | grep -v grep | awk '{ print \$2; }'\`"
    echo "ssh -f $VALUE_U@line \"killall ruby\""
    ssh -f $VALUE_U@$line "killall ruby"
done < $VALUE_C
