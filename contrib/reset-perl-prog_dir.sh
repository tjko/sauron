#!/usr/bin/env bash
#
#

prog=$(basename $0)

help() {
    cat <<-EOF
	NAME
	 $prog - A simple helper tool changing perl hasbang lines.
	
	SYNOPSIS
	
	 $prog [options] { -perl '#!hasbang-line-spec' directory }
	 
	OPTIONS:
	 -help	          this help.
	 -perl '#!line'   change all perl hasbang lines 
	
	NOTICE

	 * Use this script only after you have made the
	   working backup of your files first !
	
	EXAMPLE:
	
	 $ $prog -perl '#!/usr/bin/perl -I /foo/bar' directory

	AUTHORS
	 Riku Meskanen <mesrik@iki.fi>, 2024
	
	VERSION
	 \$Id$
	
	COPYING
	 This script is free software. It can be distributed 
	 by the same license with the perl itself.
	EOF
}


# parse arguments
while [[ $1 =~ ^-(-)? ]]; do
    opt=$(echo $1 | sed 's/^--/-/')
    shift
    case $opt in
        -h|-help)  
            help
            exit 0
            ;;
        -perl)
            if [ $# -lt 1 ]; then
                echo -e "$prog: \"#! line \" missing\n" 
                exit 1
            else
                hb_line="$1"
            fi
            shift
            ;;
	*)  echo -e "\a$prog: invalid option: -$opt \n" >&2
	    help
            exit 1
            ;;
    esac
done

# sanity check
if [ -z "$hb_line" ]; then
    echo "$prog: -perl \"#! hasbang line spec\" missing."
    exit 1
fi

if [ $(echo "$hb_line" |  grep -c "^#!.*perl") -ne 1 ] ; then
    echo "$prog: invalid -perl \"$hb_line\""
    exit 1
fi    


if [ -d $1 ]; then

    all_files=(
	$(find $1 -type f)
    )

    for fn in ${all_files[@]}; do
	[[ $fn =~ \.git/ ]] && continue

	if [ $(head -1 $fn | grep -Ec '^#![[:blank:]]*[/[:alnum:]]+/perl[[:blank:]]+-I[/[:alnum:]]+') -ne 0 ]; then
	    echo "Fixing: $fn"
	    echo "Before: $(head -1 $fn | grep -E '^#![[:blank:]]*[/[:alnum:]]+/perl[[:blank:]]+-I[/[:alnum:]]+')"
	    perl -pi -e "s:^#!.*/perl.*/sauron:$hb_line:g;" $fn
	    echo "After:  $(head -1 $fn | grep -E '^#![[:blank:]]*/usr/bin/perl[[:blank:]]+-I/')"
	fi
    done

else
    echo "$prog: no such director: $1"
    exit 1
fi

# eof
