# Sauron::CGI::Utils.pm
#
# Copyright (c) Timo Kokkonen <tjko@iki.fi>  2003.
# $Id$
#
package Sauron::CGI::Utils;
require Exporter;
use CGI qw/:standard *table -no_xhtml/;
use Digest::MD5;
use Sauron::CGIutil;
use Sauron::BackEnd;
use Sauron::Sauron;
use strict;
use vars qw($VERSION @ISA @EXPORT);

$VERSION = '$Id$ ';

@ISA = qw(Exporter); # Inherit from Exporter
@EXPORT = qw(
	     check_perms
	     make_cookie
	     add_default_zones
	     run_ping_sweep
	     add_magic
	     delete_magic
	     edit_magic

	     %check_names_enum
	     %yes_no_enum
	     %boolean_enum
	     %host_types
	    );


our %check_names_enum;
our %yes_no_enum;
our %boolean_enum;
our %host_types;

%check_names_enum = (D=>'Default',W=>'Warn',F=>'Fail',I=>'Ignore');
%yes_no_enum = (D=>'Default',Y=>'Yes', N=>'No');
%boolean_enum = (f=>'No',t=>'Yes');
%host_types=(0=>'Any type',1=>'Host',2=>'Delegation',3=>'Plain MX',
	     4=>'Alias',5=>'Printer',6=>'Glue record',7=>'AREC Alias',
	     8=>'SRV record',9=>'DHCP only',10=>'zone',
	     101=>'Host reservation');


sub check_perms {
  my($type,$rule,$quiet) = @_;
  my($i,$re,@n,$s,$e,$ip);

  my %state = %main::state;
  my %perms = %main::perms;

  my $serverid = $state{serverid};
  my $zoneid = $state{zoneid};

  return 0 if ($state{superuser} eq 'yes');

  if ($type eq 'superuser') {
    return 1 if ($quiet);
    alert1("Access denied: administrator priviliges required.");
    return 1;
  }
  elsif ($type eq 'level') {
    return 0 if ($perms{alevel} >= $rule);
    alert1("Higher authorization level required") unless($quiet);
    return 1;
  }
  elsif ($type eq 'server') {
    return 0 if ($perms{server}->{$serverid} =~ /$rule/);
  }
  elsif ($type eq 'zone') {
    return 0 if ($main::SAURON_PRIVILEGE_MODE==0 &&
		 $perms{server}->{$serverid} =~ /$rule/);
    return 0 if ($perms{zone}->{$zoneid} =~ /$rule/);
  }
  elsif ($type eq 'host' || $type eq 'delhost') {
    return 0  if ($perms{server}->{$serverid} =~ /RW/);
    if ($perms{zone}->{$zoneid} =~ /RW/) {
      return 0 if (@{$perms{hostname}} == 0);

      for $i (0..$#{$perms{hostname}}) {
	$re=$perms{hostname}[$i];
	return 0 if ($rule =~ /$re/);
      }

      if ($type eq 'delhost') {
	for $i (0..$#{$perms{delmask}}) {
	  $re=$perms{delmask}[$i];
	  return 0 if ($rule =~ /$re/);
	}
      }
    }

    alert1("You are not authorized to modify this host record")
      unless ($quiet);
    return 1;
  }
  elsif ($type eq 'ip') {
    @n=keys %{$perms{net}};
    return 0  if (@n < 1 && @{$perms{ipmask}} < 1);
    $ip=ip2int($rule); #print "<br>ip=$rule ($ip)";

    for $i (0..$#n) {
      $s=ip2int($perms{net}->{$n[$i]}[0]);
      $e=ip2int($perms{net}->{$n[$i]}[1]);
      if (($s > 0) && ($e > 0)) {
	#print "<br>$i $n[$i] $s,$e : $ip";
	return 0 if (($s <= $ip) && ($ip <= $e));
      }
    }
    for $i (0..$#{$perms{ipmask}}) {
	$re=$perms{ipmask}[$i];
	#print p,"regexp='$re' '$rule'";
	return 0 if (check_ipmask($re,$rule));
    }

    alert1("Invalid IP (IP is outsize allowed net(s))") unless ($quiet);
    return 1;
  }
  elsif ($type eq 'tmplmask') {
    for $i (0..$#{$perms{tmplmask}}) {
      $re=$perms{tmplmask}[$i];
      return 0 if ($rule =~ /$re/);
    }
    alert1("You are not authorized to modify this template") unless ($quiet);
    return 1;
  }
  elsif ($type eq 'grpmask') {
    for $i (0..$#{$perms{grpmask}}) {
      $re=$perms{grpmask}[$i];
      return 0 if ($rule =~ /$re/);
    }
    alert1("You are not authorized to modify this group") unless ($quiet);
    return 1;
  }
  elsif ($type eq 'flags') {
    return 0 if ($perms{flags}->{$rule});
    alert1("Your are not authorized to add/modify: $rule") unless ($quiet);
    return 1;
  }

  alert1("Access to $type denied") unless ($quiet);
  return 1;
}


sub make_cookie($$) {
  my($path,$ref) = @_;

  my($val,$ctx,%state);
  my $remote_addr = $ENV{'REMOTE_ADDR'};

  $val=rand 100000;

  $ctx=new Digest::MD5;
  $ctx->add($val);
  $ctx->add($$);
  $ctx->add(time);
  $ctx->add(rand 1000000);
  $val=$ctx->hexdigest;

  undef %state;
  $state{auth}='no';
  #$state{'host'}=remote_host();
  $state{addr}=($remote_addr ? $remote_addr : '0.0.0.0');
  save_state($val,\%state);
  $$ref=$val;
  return cookie(-name=>"sauron-$main::SERVER_ID",-expires=>'+7d',
		-value=>$val,-path=>$path,
		-secure=>($main::SAURON_SECURE_COOKIES ? 1 :0));
}



sub add_default_zones($$) {
  my($serverid,$verbose) = @_;

  my($id,%zone,%host);


  %zone=(name=>'localhost',type=>'M',reverse=>'f',server=>$serverid,
	 ns=>[[0,'localhost.','']],ip=>[[0,'127.0.0.1','t','t','']]);
  print "Adding zone: $zone{name}...";
  if (($id=add_zone(\%zone)) < 0) {
    print "failed (zone already exists? $id)\n";
  } else {
    print "OK (id=$id)\n";
  }

  %zone=(name=>'127.in-addr.arpa',type=>'M',reverse=>'t',server=>$serverid,
	ns=>[[0,'localhost.','']]);
  print "Adding zone: $zone{name}...";
  if (($id=add_zone(\%zone)) < 0) {
    print "failed (zone already exists? $id)\n";
  } else {
    print "OK (id=$id)\n";
  }

  %zone=(name=>'0.in-addr.arpa',type=>'M',reverse=>'t',server=>$serverid,
	ns=>[[0,'localhost.','']]);
  print "Adding zone: $zone{name}...";
  if (($id=add_zone(\%zone)) < 0) {
    print "failed (zone already exists? $id)\n";
  } else {
    print "OK (id=$id)\n";
  }

  %zone=(name=>'255.in-addr.arpa',type=>'M',reverse=>'t',server=>$serverid,
	ns=>[[0,'localhost.','']]);
  print "Adding zone: $zone{name}...";
  if (($id=add_zone(\%zone)) < 0) {
    print "failed (zone already exists? $id)\n";
  } else {
    print "OK (id=$id)\n";
  }

}			




sub run_ping_sweep($$$)
{
  my($iplist,$resulthash,$user) = @_;
  my($i,$r,$ip);
  my($nmap_file,$nmap_log);

  undef %{$resulthash};

  unless (-d $main::SAURON_NMAP_TMPDIR && -w $main::SAURON_NMAP_TMPDIR) {
    logmsg("notice","SAURON_NMAP_TMPDIR misconfigured");
    return -1;
  }
  $nmap_file = "$main::SAURON_NMAP_TMPDIR/nmap-$$.input";
  $nmap_log = "$main::SAURON_NMAP_TMPDIR/nmap-$$.log";

  # print h3("Please wait...Running Ping sweep.");
  logmsg("notice","running nmap (ping sweep): $user");

  unless (open(FILE,">$nmap_file")) {
    logmsg("notice","cannot write tmp file for nmap: $nmap_file");
    return -2;
  }
  for $i (0..$#{$iplist}) {
    $ip=$$iplist[$i];
    next unless (is_cidr($ip));
    print FILE "$ip\n";
  }
  close(FILE);

  $main::SAURON_NMAP_ARGS = '-n -sP' unless ($main::SAURON_NMAP_ARGS);
  $r = run_command_quiet($main::SAURON_NMAP_PROG,
			 [split(/\s+/,$main::SAURON_NMAP_ARGS),
			 '-oG',$nmap_log,'-iL',$nmap_file],
			 $main::SAURON_NMAP_TIMEOUT);
  unlink($nmap_file);
  unless ($r == 0) {
    return 1 if (($r & 255) == 14);
    return -3;
  }

  unless (open(FILE,"$nmap_log")) {
    logmsg("notice","failed to read nmap output file: $nmap_log");
    return -4;
  }

  while (<FILE>) {
    next if (/^\#/);
    next unless (/^\s*Host:\s+(\d+\.\d+\.\d+\.\d+)\s.*(Status:\s+(\S+))/);
    $resulthash->{$1}=$3;
  }
  close(FILE);
  unlink($nmap_log);

  return 0;
}



sub edit_magic($$$$$$$) {
  my($prefix,$name,$menu,$form,$get_func,$update_func,$id) = @_;
  my(%h,$res);
  my $selfurl = script_name() . path_info();

  if (($id eq '') || ($id < 1)) {
    print h2("$name id not specified!");
    return -1;
  }

  if (param($prefix . '_cancel') ne '') {
    print h2("No changes made to $name record.");
    return 2;
  }

  if (param($prefix . '_submit') ne '') {
    if(&$get_func($id,\%h) < 0) {
      print h2("Cannot find $name record anymore! ($id)");
      return -2;
    }
    unless (($res=form_check_form($prefix,\%h,$form))) {
      $res=&$update_func(\%h);
      if ($res < 0) {
	print "<FONT color=\"red\">",h1("$name record update failed! ($res)"),
	      "</FONT>";
      } else {
	print h2("$name record successfully updated");
	#&$get_func($id,\%h);
	#display_form(\%h,$form);
	return 1;
      }
    } else {
      print "<FONT color=\"red\">",h2("Invalid data in form!"),"</FONT>";
    }
  }

  unless (param($prefix . '_re_edit') eq '1') {
    if (&$get_func($id,\%h)) {
      print h2("Cannot get $name record (id=$id)!");
      return -3;
    }
  }

  print h2("Edit $name:"),p,
          startform(-method=>'POST',-action=>$selfurl),
          hidden('menu',$menu),hidden('sub','Edit');
  form_magic($prefix,\%h,$form);
  print submit(-name=>$prefix . '_submit',-value=>'Make changes'), "  ",
        submit(-name=>$prefix . '_cancel',-value=>'Cancel'),
        end_form;

  return 0;
}

sub add_magic($$$$$$) {
  my($prefix,$name,$menu,$form,$add_func,$data) = @_;
  my(%h,$res);
  my $selfurl = script_name() . path_info();

  if (param($prefix . '_cancel')) {
    print h2("$name record not created!");
    return -1;
  }

  if (param($prefix . '_submit') ne '') {
    unless (($res=form_check_form($prefix,$data,$form))) {
      $res=&$add_func($data);
      if ($res < 0) {
	print "<FONT color=\"red\">",h1("Adding $name record failed! ($res)"),
	      "</FONT>";
      } else {
	print h3("$name record successfully added");
	return $res;
      }
    } else {
      print "<FONT color=\"red\">",h2("Invalid data in form!"),"</FONT>";
    }
  }

  print h2("New $name:"),p,
          startform(-method=>'POST',-action=>$selfurl),
          hidden('menu',$menu),hidden('sub',$prefix);
  form_magic($prefix,$data,$form);
  print submit(-name=>$prefix . '_submit',-value=>"Create $name")," ",
        submit(-name=>$prefix . '_cancel',-value=>"Cancel"),end_form;
  return 0;
}

sub delete_magic($$$$$$$) {
  my($prefix,$name,$menu,$form,$get_func,$del_func,$id) = @_;
  my(%h,$res);
  my $selfurl = script_name() . path_info();

  if (($id eq '') || ($id < 1)) {
    print h2("$name id not specified!");
    return -1;
  }

  if (param($prefix . '_cancel') ne '') {
    print h2("$name record not deleted.");
    return 2;
  }

  if (param($prefix . '_confirm') ne '') {
    if(&$get_func($id,\%h) < 0) {
      print h2("Cannot find $name record anymore! ($id)");
      return -2;
    }

    $res=&$del_func($id);
    if ($res < 0) {
      print "<FONT color=\"red\">",h1("$name record delete failed!"),
      "<br>result code=$res</FONT>";
      return -10;
    } else {
      print h2("$name record successfully deleted");
      return 1;
    }
  }


  if (&$get_func($id,\%h)) {
    print h2("Cannot get $name record (id=$id)!");
    return -3;
  }

  print h2("Delete $name:"),p,
          startform(-method=>'POST',-action=>$selfurl),
          hidden('menu',$menu),hidden('sub','Delete'),
          hidden($prefix . "_id",$id);
  print submit(-name=>$prefix . '_confirm',-value=>'Delete'),"  ",
        submit(-name=>$prefix . '_cancel',-value=>'Cancel'),end_form;
  display_form(\%h,$form);
  return 0;
}




1;
# eof
