#!/bin/sh

usage() {
    echo "Usage: $CMDNAME [-c CLUSTER_FILE] [-m MANAGER_ADDRESS] [-p PARALLEL] [-u USER_NAME]" 1>&2
}

while getopts c:m:p:u: OPT
do
    case $OPT in
        "c" ) FLAG_C="TRUE" ; VALUE_C="$OPTARG" ;;
        "m" ) FLAG_M="TRUE" ; VALUE_M="$OPTARG" ;;
        "p" ) FLAG_P="TRUE" ; VALUE_P="$OPTARG" ;;
        "u" ) FLAG_U="TRUE" ; VALUE_U="$OPTARG" ;;
          * ) usage
              exit 1 ;;
    esac
done

if [ "$FLAG_C" != "TRUE" ]; then
    usage
    exit 2
fi

if [ "$FLAG_M" != "TRUE" ]; then
    usage
    exit 3
fi

if [ "$FLAG_P" != "TRUE" ]; then
    usage
    exit 4
fi

if [ "$FLAG_U" != "TRUE" ]; then
    usage
    exit 5
fi

if [ ! -f $VALUE_C ]; then
    usage
    exit 6
fi

while read line
do
    echo $line
    echo "ssh -f $VALUE_U@$line 'cd prog/practis ; ruby bin/executor -m $VALUE_M -a $line -p $VALUE_P &> /tmp/executor$line.log &'"
    ssh -f $VALUE_U@$line "cd prog/practis ; ruby bin/executor -m $VALUE_M -a $line -p $VALUE_P &> /tmp/executor$line.log &"
done < $VALUE_C
