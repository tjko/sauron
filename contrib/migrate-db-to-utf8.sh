#!/usr/bin/env bash
#
# BFMI tool to migrate LATIN1 encoded psql dump file to UTF8 encoding -- mesrik, 2015
#

prog="$(basename $0)"
usage="Usage: $prog { sauron-psql.dump }"

if [ $# -lt 1 ]; then
    echo $usage
    exit 1
fi

if [ ! -f $1 ]; then
    echo "$prog: $1 does not exist."
    exit 1
fi

sed "s/^SET client_encoding = 'LATIN1';/SET client_encoding = 'UTF8';/" $1 |\
iconv -f LATIN1 -t UTF-8 >$1.utf8

#eof
