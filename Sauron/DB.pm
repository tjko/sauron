# Sauron::DB.pm  -- Sauron database interface routines
#
# $Id$
#
package Sauron::DB;
require Exporter;

@ISA = qw(Exporter); # Inherit from Exporter
@EXPORT = qw(
	     db_connect
	     db_connect2
	     db_exec
	     db_query
	     db_getvalue
	     db_status
	     db_lastoid
	     db_errormsg
	     db_lasterrormsg
	     db_debug
	     db_print_result
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

use Time::Local;
use Pg;
use strict;

sub sql_print_result($) {
  my($res)=@_;

  my %t = ( 0, 'PGRES_EMPTY_QUERY',
	 1, 'PGRES_COMMAND_OK',
	 2, 'PGRES_TUPLES_OK',
	 3, 'PGRES_COPY_OUT',
	 4, 'PGRES_COPY_IN',
	 5, 'PGRES_BAD_RESPONSE',
	 6, 'PGRES_NONFATAL_ERROR',
	 7, 'PGRES_FATAL_ERROR'
       );

  print "status= ".$res->resultStatus . " (" . $t{$res->resultStatus} . ")\n";
  print "cmdstatus='" . $res->cmdStatus . "'  oid=". $res->oidStatus . "\n";
  print "ntuples=" . $res->ntuples . "   nfields=" . $res->nfields . "\n";
  #print $res->getvalue(0,0) . "\n";
  #print $res->getvalue(0,1) . "\n";

}

my $db_connection_handle = 0;
my $db_last_result = 0;
my $db_debug_flag = 0;
my $db_last_error_msg = '';
my $db_ignore_begin_and_commit_flag = 0;

sub db_connect($) {
  my ($DB_CONNECT) = @_;

  $db_connection_handle = Pg::connectdb($DB_CONNECT);
  die($0 . ": ". $db_connection_handle->errorMessage) 
         if ($db_connection_handle->status != PGRES_CONNECTION_OK);
  return 1;
}

sub db_connect2($) {
  my ($DB_CONNECT) = @_;

  $db_connection_handle = Pg::connectdb($DB_CONNECT);
  if ($db_connection_handle->status != PGRES_CONNECTION_OK) {
    warn($0 . ": ". $db_connection_handle->errorMessage);
    return 0;
  }
  return 1;
}




sub db_exec($) {
  my($sqlstr) = @_;
  my($s);

  $db_last_result = $db_connection_handle->exec($sqlstr);
  $s = $db_last_result->resultStatus;

  if ( $s != PGRES_COMMAND_OK && $s != PGRES_TUPLES_OK ) { 
    printf ("db_exec(%s) result:\n", $sqlstr) if ($db_debug_flag > 0);
    sql_print_result($db_last_result) if ($db_debug_flag > 0);
    $db_last_error_msg=$db_connection_handle->errorMessage;
    return -1;
  }

  return $db_last_result->ntuples if $s == PGRES_TUPLES_OK;
  return 0;
}


sub db_query($$) {
  my ($sqlstr,$aref) = @_;
  my ($result, $status, $i, $j);

  undef @{$aref};

  if ($result = $db_connection_handle->exec($sqlstr)) {
    if (($status = $result->resultStatus) == 2) {
      for $i (0..$result->ntuples - 1) {
	for $j (0..$result->nfields - 1) {
	  $$aref[$i][$j] = $result->getvalue($i,$j);
	}
      }
    }
  }

}


sub db_getvalue($$) {
  my($row,$col) = @_;

  return $db_last_result->getvalue($row,$col);
}

sub db_status() {
  return $db_last_result->cmdStatus();
}

sub db_lastoid() {
  return $db_last_result->oidStatus();
}

sub db_errormsg() {
  return $db_connection_handle->errorMessage();
}

sub db_lasterrormsg() {
  return $db_last_error_msg;
}

sub db_debug($) {
  my($flag) = @_;

  if ($flag > 0) {
    $db_debug_flag=1;
  } else {
    $db_debug_flag=0;
  }
}

sub db_print_result() {
  sql_print_result($db_last_result);
}

sub db_vacuum() {
  return db_exec("VACUUM ANALYZE;");
}

sub db_begin() {
  return if ($db_ignore_begin_and_commit_flag == 1);
  return db_exec("BEGIN;");
}

sub db_commit() {
  return if ($db_ignore_begin_and_commit_flag == 1);
  return db_exec("COMMIT;");
}

sub db_rollback() {
  return if ($db_ignore_begin_and_commit_flag == 1);
  return db_exec("ROLLBACK;");
}

sub db_ignore_begin_and_commit($) {
  my($i) = @_;
  $db_ignore_begin_and_commit_flag = ($i == 1  ? 1 : 0);
}



sub db_encode_str($) {
  my($str) = @_;

  return "NULL" if ($str eq '');
  $str =~ s/\\/\\\\/g;
  $str =~ s/\'/\\\'/g;
  return "'" . $str . "'";
}


sub db_build_list_str($) {
  my($list) = @_;
  my ($tmp,$f);

  return "NULL" unless ($list);

  foreach $f (@{$list}) {
    $tmp.="," if ($tmp);
    $f =~ s/\'/\\\'/g;
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


  $c=0;
  for $i (0..$#{$data}) {
    $row=$$data[$i]; $flag=0;
    $str.="INSERT INTO $table ($fields) VALUES(";
    for $j (0..$#{$row}) {
      $str.="," if ($flag);
      $str.=db_encode_str($$row[$j]);
      $flag=1;
    }
    $str.=");\n";
    $c++;
    if ($c > 25) {
      $c=0;
      #print "BLOCK: $str\n";
      $res=db_exec($str);
      return -1 if ($res < 0);
      $str='';
    }
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
