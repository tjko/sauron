#!/usr/bin/perl
#
# Updates subnet names in given server. Subnet names are extracted from
# files given as parameters on command line.
#
# This script looks for lines containing following pattern:
#  Net <CIDR> <subnet name>
#
# For example:
#  Net 192.168  Testing network
#  Net 192.168.1.0/27  Testing network...
#
# $Id$
#
use Net::Netmask;
use Getopt::Std;

my ($PG_DIR,$PG_NAME) = ($0 =~ /^(.*\/)(.*)$/);
$0 = $PG_NAME;

if (-r "/etc/sauron/config") {
  $config_file="/etc/sauron/config";
} elsif (-r "/usr/local/etc/sauron/config") {
  $config_file="/usr/local/etc/sauron/config"; 
} else {
  die("cannot find config file in /etc/sauron or /usr/local/etc/sauron");
}

do "$config_file" || die("cannot load config");
do "$PROG_DIR/util.pl";
do "$PROG_DIR/db.pl";


getopts("hr");

if (@ARGV < 2 || $opt_h) {
  print "syntax: $0 [-h] [-r] <servername> <.hosts-filename ...>\n";
  exit(1);
}

$server=shift;


db_connect() || die("cannot connect to database");

db_query("SELECT id FROM servers WHERE name='$server';",\@q);
if ($#q < 0) {
  die("cannot find given server");
}
$serverid=$q[0][0];
$fail=0;
$count=0;


while (<>) {
  next unless /Net\s+(\d{1,3}(\.\d{1,3}(\.\d{1,3}(\.\d{1,3})?)?)?(\/\d{1,2})?)\s+(\S.*)\s*$/;
  #print "$1 '$6'\n";
  
  $net=$1;
  $desc=$6;
  $n = new Net::Netmask($1);
  $hash{$n->desc()}=$desc;
}


foreach $net (sort keys %hash) {
  undef @q;
  db_query("SELECT id FROM nets WHERE server=$serverid " .
	   " AND net = '$net';",\@q);
  unless (@q > 0) {
    print "No matching net found for: $net = $hash{$net} $q[0][0]\n";
    next;
  }
  $id=$q[0][0];
  $name=$hash{$net};

  if (db_exec("UPDATE nets SET name='$name' WHERE id=$id;") < 0) {
    warn("cannot update net $net") ;
    $fail++;
  } else {
    $count++;
  }
}


print "Updated names for $count nets ($fail updates failed)\n";


exit(0) unless ($opt_r);

# fix auto assign address ranges in nets... if -r option was used

print "Fixing auto assign address ranges in nets table...\n";

undef @q;
db_query("SELECT n.id,n.net,a.domain,b.ip FROM hosts a, rr_a b, nets n " .
	 "WHERE b.host=a.id AND a.router > 0 AND n.server=$serverid " .
	 " AND n.net >> b.ip ORDER BY n.net;",\@q);

$count=0;
for $i (0..$#q) {
  next unless ($q[$i][1] =~ /\/24$/);
  #print "$q[$i][1] $q[$i][3] ";
  $count++;
  $n = new Net::Netmask($q[$i][1]);

  if ($q[$i][3] =~ /\.1\/32$/) {
    $sql="UPDATE nets SET range_start='".$n->nth(25)."' WHERE id=$q[$i][0];";
  } else {
    $sql="UPDATE nets SET range_end='".$n->nth(-16)."' WHERE id=$q[$i][0];";
  }
  #print "$sql\n";
  warn("cannot update range for net $q[$i][1]") if (db_exec($sql) < 0);
}


# eof
