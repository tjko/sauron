#!/usr/bin/perl
#
# makesvr4pkg.pl -- simple SVR4 packakge building tool
#
# Copyright (c) Timo Kokkonen <tjko@iki.fi> 2003.
# $Id$
#
use File::Path;
use Getopt::Long;

my @SYS_DIRS = qw#
    /etc 
    /etc/init.d
    /etc/rc.\.d
    /etc/opt
    /opt
    /opt/bin
    /usr
    /usr/(bin|sbin|lib|share|local)
    /usr/share/(man|man/man.)
    /usr/local/(etc|bin|doc|sbin|libexec|man|man/man.|share|lib)
    /var
    /var/(opt|run|tmp)
    /tmp
    #;


sub fatal($) {
    my($msg) = @_;
    my($prg) = ($0 =~ /\/(.*)$/);
    print STDERR "$prg: $msg\n";
    exit;
}

chomp($HOST = `hostname`);
chomp($UNAME_S = `uname -s`);
chomp($UNAME_R = `uname -r`);
chomp($ARCH = `uname -p`);
$USER = (getpwuid($<))[0];

GetOptions("base=s","email=s","name=s","vendor=s","arch=s","desc=s",
	   "classes=s","category=s","help|h","pstamp=s","verbose","build");

$PKG=shift;
$VERSION=shift;
$dir=shift;
$targetdir=shift;

unless ($PKG && $VERSION && $dir || $opt_help) {
    print "syntax: $0 [OPTIONS] <pkgname> <version> <directory> [<targetdir>]\n\n",
          "options:\n",
          " --name=<package name>\n",
          " --desc=<package description>\n",
          " --vendor=<vendor name>\n",
          " --email=<email>\n",
          " --arch=<architecture>\n",
          " --pstamp=<pstamp>\n",
          " --email=<email>\n",
          " --category=<category>\n",
          " --basedir=<basedir>\n",
          " --classes=<classes>\n\n";
    exit;
}


fatal("invalid package name: $PKG") unless ($PKG =~ /^[a-zA-Z0-9]+$/);
fatal("invalid version: $VERSION") unless ($VERSION =~ /^[a-zA-Z0-9,=_\.\-]+$/);
$dir =~ s/\/\s*$//;
fatal("package directory does not exist: $dir") unless (-d $dir);

chomp($targetdir=`pwd`) unless ($targetdir);
chdir($targetdir) || fatal("cannot change to targetdir: $targetdir");

fatal("basedir option not supported yet") if ($opt_basedir);

$opt_name = "$PKG for $UNAME_S" unless ($opt_name);
$opt_desc = "Automatically generated package (by makeSVR4pkg)" 
    unless ($opt_desc);
$opt_vendor = "N/A" unless ($opt_vendor);
$opt_arch = $ARCH unless ($opt_arch);
$opt_category = 'application' unless ($opt_category);
$opt_basedir = '/' unless ($opt_basedir);
$opt_classes = 'none' unless ($opt_classes);
@l = localtime(time);
$opt_pstamp = sprintf("%s\@%s%04d%02d%02d%02d%02d%02d",
		      $USER,$HOST,$l[5]+1900,$l[4]+1,$l[3],$l[2],$l[1],$l[0])
    unless ($opt_pstamp);
fatal("invalid basedir: $opt_basedir") unless ($opt_basedir =~ /^\/.*$/);

$pkginfo =  "PKG=$PKG\n" .
      "NAME=\"$opt_name\"\n" .
      "DESC=\"$opt_desc\"\n" .
      "VENDOR=\"$opt_vendor\"\n" .
      "ARCH=$opt_arch\n" .
      "VERSION=\"$VERSION\"\n" .
      ($opt_email ? "EMAIL=\"$opt_email\"\n" : '') .
      "PSTAMP=\"$opt_pstamp\"\n" .
      "CATEGORY=\"$opt_category\"\n" .
      "BASEDIR=$opt_basedir\n" .
      "CLASSES=\"$opt_classes\"\n";


print "$pkginfo\nsource dir: $dir\ntarget dir: $targetdir\n";

umask(022);
chdir($dir) || fatal("failed to chdir to: $dir");

# remove existing package dir if it exists
if (-d "$dir/$PKG") {
    rmtree("$dir/$PKG");
    fatal("failed to remove pkg dir: $dir/$PKG")
	if (-d "$dir/$PKG");
}

if (-f "$dir/build.sh") {
    fatal("failed to remove build.sh") if (unlink("$dir/build.sh") < 1);
}

# create pkginfo file

print "Building pkginfo...\n";
open(FILE,">pkginfo") || fatal("failed to create: pkginfo");
print FILE $pkginfo;
close(FILE);


# create prototype file...

print "Building prototype file...";

$count=0;
open(FILE,">prototype") || fatal("failed to create: prototype");
print FILE "i pkginfo\n";

open(PIPE,"find . | sort | pkgproto |") || fatal("pipe failed");
while(<PIPE>) {
    chomp;
    next if /^f\s+\S+\s+(prototype|pkginfo)\s/;
    my @l = split(/\s+/);
    $l[4]='root';
    $l[5]='sys';
    my $tmp = $opt_basedir . $l[2];
    foreach $sysdir (@SYS_DIRS) {
	if ($tmp =~ /^($sysdir)$/) { $l[3]='?'; $l[4]='?'; $l[5]='?'; }
    }

    print FILE "$l[0] $l[1] $l[2] $l[3] $l[4] $l[5]\n";
    $count++;
}
close(PIPE);

print "found $count file(s)\n";


# create build script

print "Creating build script...\n";

$cmd1="pkgmk -d $dir -f $dir/prototype -r $dir -o";
$cmd2="echo | pkgtrans -os $dir $targetdir/$PKG-$UNAME_S-$UNAME_R-$ARCH-$VERSION.pkg";

open(FILE,">build.sh") || fatal("failed to create: build.sh");
print FILE "#!/bin/sh\n",
           "$cmd1\n",
           "[ \$? -eq 0 ] || exit 1\n",
           "$cmd2\n",
           "[ \$? -eq 0 ] || exit 2\n",
           "\n\n";
close(FILE);

if ($opt_build) {
    fatal("build.sh failed") if (system("sh $dir/build.sh") != 0);
}
else {
    print "\nto build package use: $dir/build.sh\n";
}
 
# eof
