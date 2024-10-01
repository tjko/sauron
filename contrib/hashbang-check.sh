#!/usr/bin/env bash
#
#
prog=$(basename $0)

if [ $# -lt 1 ]; then
    echo "Usage: $prog { a directory }"
    exit 1
fi

if [ -d $1 ]; then
    echo "[ $prog - entering directory $1 ]"
    cd $1 && grep -r '^#!' * | awk -F":" '{ printf "%-60s%s\n",$1,$2 }'
else
    echo "$prog: $1 - can't access the directory"
    exit 1
fi
# eof
