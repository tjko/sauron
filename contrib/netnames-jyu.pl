#!/usr/bin/perl
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


getopts("h");

if (@ARGV < 2 || $opt_h) {
  print "syntax: $0 [-h] <servername> <.hosts-filename ...>\n";
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
  db_query("SELECT id FROM nets WHERE server=$serverid AND net >>= '$net';",
	  \@q);
  unless ($#q > 0) {
    print "No matching net found for: $net = $hash{$net}\n";
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


# eof
