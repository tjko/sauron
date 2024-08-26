#!/usr/bin/env bash
#
# BFMI Install Debian 12 Sauron required perl-libs - mesrik, 2024
#

prog=$(basename $0)

if [ $(id -u) -ne 0 ]; then
    echo "$prog: this script requires root privileges."
    exit 1
fi

apt-get update

# These perl moduleas are found std debian 12 repositories
install_deb=(
    libcgi-pm-perl
    libdate-manip-perl
    libdbd-pg-perl
    libdbi-perl
    libnet-dns-perl
    libnet-ip-perl
    libnetaddr-ip-perl
)
apt-get -y install ${install_deb[@]}

# Crypt::RC5 is not found debian12 repos and we need to check
# if we need to build .den and install it from CPAN <eh>

lib_rc5=$(dpkg -l libcrypt-rc5-perl | grep -Ec '^ii +libcrypt-rc5-perl 2.00-1')

if [ $lib_rc5 -ne 1 ]; then
    # Using autodeb tool that unfortunately brings large amount
    # of packages, wich we can be remove afterwards. Instructions
    # can be found down there after build.

    set -x
    apt-get -y install dh-make-perl

    tmpbuild=$(mktemp -d ${TMPDIR:=/var/tmp}/$prog.XXXXXX)

    savedir=$(pwd)

    [ -d $tmpbuild ] && cd $tmpbuild || exit 1

    if [ $(set | grep -Eic '^.*_proxy=http(|s)://') -ne 0 ]; then
	cat <<-MSG
	========================================================
	 Press <ENTER> to Username: and Password: if/when asked
	 if your proxy does not need credentials.
	========================================================
	 Press <ENTER> to continue when ready, please.
	MSG
	read dummy
    fi

    # Right, now start building the .deb package
    dh-make-perl --build --cpan Crypt::RC5

    # Expected deb file name
    debfile=libcrypt-rc5-perl_2.00-1_all.deb

    if [ -f $debfile ]; then
	# save copy where script started
	cp -av $debfile $savedir

	# install built package
	dpkg -i ./$debfile

	# making sure packages needed are also there if any
	apt-get install -f

	# step up one dir
	cd ..

	# saving build archive just in case
	yyyymmdd=$(date '+%Y-%m-%d')
	debname=$(basename $debfile .deb)

	# fix successful build name bit more proper
	tardir=$(dirname $tmpbuild)/$debname-$yyyymmdd
	mv $tmpbuild $tardir

	# archive file name
	archive_file=$savedir/$debname-$yyyymmdd.tar.gz

	tar cvzf $archive_file $tardir &&\
	    rm -rf $tardir

	# get back to where script was started
	cd $savedir

	cat <<-REPORT
	======================================================
	 Build deb:    $debfile
	 Build arcive: $(basename $archive_file)
	======================================================
	 If you rather purge what dh-make-perl perl build-tool
	 brought in and left in system. Save following lines
	 to a file or just cut/paste and then execute it as root.

	 -- 8< -- snip -- 8< --
	 #!/usr/bin/env bash
	 # clean up deb packets
	 apt-get -y remove dh-make-perl
	 apt-get -y autoremove
	 # cpan directories that were created
	 cpancleanup=(
	    ~/.cache/dh-make-perl
	    ~/.cache/cme_dpkg_dependency
	    ~/.local/share/.cpan
	 )
	 # cpan cleanup
	 for dir in \${cpancleanup[@]} ; do
	     [ -d \$dir ] && rm -rf \$dir
	 done
	 # purge just removed perl packages configs
	 dpkg --list | awk '/^rc .*-perl/ {print \$2}' | xargs -r dpkg --purge
	 # eof
	 -- 8< -- snip -- 8< --

	 These commands clean up build-tools imported packages and
	 leaves system wich preceeds build time with installed .deb
	 and tar.gz archive containing used build environment.

	 Cheers,

	 :-) riku
	REPORT

    else
	echo "$prog: $debfile build and install failed"
    fi
else
    apt-get install libcrypt-rc5-perl
fi

# eof
