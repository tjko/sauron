# Sauron::DB.pm  -- Sauron database interface routines using DBI
#
# $Id:$
#
package Sauron::DB;
require Exporter;
use Time::Local;
use DBI;
use Sauron::Util;
use strict;
use vars qw($VERSION @ISA @EXPORT);

use Sys::Syslog qw(:DEFAULT setlogsock);
Sys::Syslog::setlogsock('unix');

$VERSION = '$Id:$ ';

@ISA = qw(Exporter); # Inherit from Exporter
@EXPORT = qw(
	     db_connect
	     db_connect2
	     db_exec
	     db_query
	     db_lastid
	     db_errormsg
	     db_lasterrormsg
	     db_debug
	     db_vacuum
	     db_begin
	     db_commit
	     db_rollback
	     db_ignore_begin_and_commit
	     db_encode_str
	     db_build_list_str
	     db_encode_list_str
	     db_decode_list_str
	     db_timestamp_str
	     db_timestr_time
	     db_insert
	    );

#	     db_lastoid # ** Replaced by db_lastid 2018-09-25 TVu

sub write2log
{
  #my $priority  = shift;
  my $msg       = shift;
  my $filename  = File::Basename::basename($0);

  Sys::Syslog::openlog($filename, "cons,pid", "debug");
  Sys::Syslog::syslog("info", "$msg");
  Sys::Syslog::closelog();
} # End of write2log

my $dbh = 0;
my $db_last_result = 0;
my $db_debug_flag = 0;
my $db_last_error_msg = '';
# my $db_last_oid = 0; # ** Removed 2018-09-25 TVu
my $db_last_id = 0; # ** Added 2018-09-25 TVu
my $db_ignore_begin_and_commit_flag = 0;

sub db_connect2() {
  my($dsn,$user,$password);
  $dsn = ($main::DB_DSN ? $main::DB_DSN : '');
  $user = ($main::DB_USER ? $main::DB_USER : '');
  $password = ($main::DB_PASSWORD ? $main::DB_PASSWORD : '');

  $dbh = DBI->connect($dsn,$user,$password);
  unless ($dbh) {
    error("db_connect() failed: " . $DBI::errstr);
    return 0;
  }

  return 1;
}


sub db_connect() {
  exit(1) unless (db_connect2());
  return 1;
}


sub db_exec($) {
  my($sqlstr) = @_;
  my($sth,$rows);

  unless ($sth = $dbh->prepare($sqlstr)) {
    $db_last_error_msg=$dbh->errstr;
    return -1;
  }

  unless ($sth->execute()) {
    $db_last_error_msg=$dbh->errstr;
    return -2;
  }

  $rows = $sth->rows;

# $db_last_oid=$sth->{pg_oid_status}; # ** Removed 2018-09-25 TVu
# eval { $db_last_id = $sth->fetch()->[0]; }; # ** Added 2018-09-25 TVu
  eval { # ** Added 2018-10-01 TVu
      $db_last_id = $sqlstr =~ /returning/i ? $sth->fetch()->[0] : -1;
  };

  return ($rows > 0 ? $rows : 0);
}


sub db_query($$) {
  my ($sqlstr,$aref) = @_;
  my ($sth,@row,$types,$i);

  undef @{$aref};

  unless ($sth = $dbh->prepare($sqlstr)) {
    $db_last_error_msg=$dbh->errstr;
    return -1;
  }

  unless ($sth->execute()) {
    $db_last_error_msg=$dbh->errstr;
    return -2;
  }

  $types = $sth->{TYPE};

  while (@row = $sth->fetchrow_array) {
    for $i (0..$#row) {
      # fix values in boolean type columns
      $row[$i]=($row[$i] ? 't':'f') if ($$types[$i] == 16);
    }
    push @{$aref}, [@row];
  }
  $sth->finish;
  return 0;
}


# sub db_lastoid() { # ** Removed 2018-09-25 TVu
#   return $db_last_oid;
# }

sub db_lastid() { # ** Added 2018-09-25 TVu
  return $db_last_id;
}

sub db_errormsg() {
  return $dbh->errstr;
}

sub db_lasterrormsg() {
  return $db_last_error_msg;
}

sub db_debug($) {
  my($flag) = @_;
  $db_debug_flag = ($flag > 0 ? 1 : 0);
}

sub db_vacuum() {
  return db_exec("VACUUM ANALYZE");
}

sub db_begin() {
  return if ($db_ignore_begin_and_commit_flag == 1);
  return $dbh->begin_work();
}

sub db_commit() {
  return if ($db_ignore_begin_and_commit_flag == 1);
  return $dbh->commit();
}

sub db_rollback() {
  return if ($db_ignore_begin_and_commit_flag == 1);
  return $dbh->rollback();
}

sub db_ignore_begin_and_commit($) {
  my($i) = @_;
  $db_ignore_begin_and_commit_flag = ($i == 1  ? 1 : 0);
}


sub db_encode_str($) {
  my ($str) = @_;

  return "NULL" if ($str eq '');
  $str =~ s/\\/\\\\/g;
  #$str =~ s/\'/\\\'/g;
  $str =~ s/\'/\'\'/g;
  return ($str =~ /\\/ ? 'e' : '') . "'" . $str . "'";
}


sub db_build_list_str($) {
  my($list) = @_;
  my ($tmp,$f);

  return "NULL" unless ($list);

  foreach $f (@{$list}) {
    $tmp.="," if ($tmp);
    #$f =~ s/\'/\\\'/g;
    $f =~ s/\'/\'\'/g;
    $f =~ s/\"/\\\\\"/g;
    $tmp.="\"$f\"";
  }

  return $tmp;
}

sub db_encode_list_str($) {
  my($list) = @_;

  return "NULL" unless ($list);
  return "NULL" if (@{$list}<1);
  return "'{" . db_build_list_str($list) . "}'";
}


sub db_decode_list_str($) {
  my($str) = @_;
  my($list,$c,$i);

  $list=[];
  return $list unless ($str =~ /^\{(\d|\d.+\d|\".+\")\}$/);

  if ($str =~ /^\{\d/) { 
    # number list
    $str =~ s/(^\{|\}$)//g;
    @{$list} = split(",",$str);
    $c=@{$list};
  }
  else {
    # string list
    $str =~ s/(^\{\"|\"\}$)//g;
    @{$list} = split("\",\"",$str);
    $c=@{$list};
  }

  for($i=0;$i < $c;$i++) {
    $$list[$i] =~ s/\\\"/\"/g;
  }

  return $list;
}


sub db_timestamp_str() {
  my($s);
  my($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime(time);

  $s = sprintf "%04d-%02d-%02d %02d:%02d:%02d",
               1900+$year,($mon+1),$mday,$hour,$min,$sec;
  return $s;
}

sub db_timestr_time($) {
  my($timestr)=@_;

  if ($timestr =~ 
      /^\s*(\d{2,4})-(\d\d)-(\d\d)\s+(\d{1,2}):(\d{1,2}):(\d{1,2})(\+(\d{1,2}))?\s*$/ ) {

	return timelocal($6,$5,$4,$3,$2-1,$1-1900);
      }

   return 0;
}


sub db_insert($$$) {
  my($table,$fields,$data) = @_;
  my($str,$i,$j,$c,$row,$flag,$res);

  for $i (0..$#{$data}) {
    $row=$$data[$i]; $flag=0;
    $str.="INSERT INTO $table ($fields) VALUES(";
    for $j (0..$#{$row}) {
      $str.="," if ($flag);
      $str.=db_encode_str($$row[$j]);
      $flag=1;
    }
    $str.=");\n";
    $res=db_exec($str);
    return -1 if ($res < 0);
    $str='';
  }

  if ($str ne '') {
    #print "LAST: $str\n";
    $res=db_exec($str);
    return -2 if ($res < 0);
  }

  return 0;
}

1;
# eof
