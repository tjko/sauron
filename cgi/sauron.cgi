#!/usr/bin/perl
#
# sauron.cgi
# $Id$
#
# Copyright (c) Timo Kokkonen <tjko@iki.fi>, 2000.
# All Rights Reserved.
#
use CGI qw/:standard *table/;
use CGI::Carp 'fatalsToBrowser'; # debug stuff
use Digest::MD5;

$CGI::DISABLE_UPLOADS =1; # no uploads
$CGI::POST_MAX = 10000; # max 100k posts

$debug_mode = 1;

if (-f "/etc/sauron/config") { 
  $conf_dir='/etc/sauron'; 
} 
elsif (-f "/opt/etc/sauron/config") { 
  $conf_dir='/opt/etc/sauron'; 
} 
elsif (-f "/usr/local/etc/sauron/config") { 
  $conf_dir='/usr/local/etc/sauron'; 
}
else {
  print STDERR "cannot find configuration file!\n";
  exit(-1);
}

do "$conf_dir/config" || error("cannot load configuration!");

do "$PROG_DIR/util.pl";
do "$PROG_DIR/db.pl";
do "$PROG_DIR/back_end.pl";

error("invalid directory configuration") 
  unless (-d $CGI_STATE_PATH && -w $CGI_STATE_PATH);


%server_form = ( 
 data=>[
  {ftype=>0, name=>'Server' },  
  {ftype=>1, tag=>'name', name=>'Server name', type=>'text', len=>20},
  {ftype=>1, tag=>'comment', name=>'Comments',  type=>'text', len=>60,
   empty=>1},
  {ftype=>0, name=>'DNS'},
  {ftype=>1, tag=>'hostmaster', name=>'Hostmaster', type=>'fqdn', len=>30,
   default=>'hostmaster.my.domain.'},
  {ftype=>1, tag=>'hostname', name=>'Hostname',type=>'fqdn', len=>30,
   default=>'ns.my.domain.'},
  {ftype=>1, tag=>'pzone_path', name=>'Primary zone-file path', type=>'path',
   len=>30, empty=>1},
  {ftype=>1, tag=>'szone_path', name=>'Slave zone-file path', type=>'path',
   len=>30, empty=>1, default=>'NS2/'},
  {ftype=>1, tag=>'named_ca', name=> 'Root-server file', type=>'text', len=>30,
   default=>'named.ca'},
  {ftype=>2, tag=>'allow_transfer', name=>'Allow-transfer', fields=>2,
   type=>['cidr','text'], len=>[20,30], empty=>[0,1], 
   elabels=>['IP','comment']},
  {ftype=>0, name=>'DHCP'},
  {ftype=>2, tag=>'dhcp', name=>'Global DHCP', type=>['text','text'], 
   fields=>2, len=>[35,20], empty=>[0,1],elabels=>['dhcptab line','comment']} 
 ],
 bgcolor=>'#00ffff',
 border=>'0',		
 width=>'100%',
 nwidth=>'30%',
 heading_bg=>'#aaaaff'
);



#####################################################################

db_connect2() || error("Cannot estabilish connection with database");

$frame_mode=0;
$pathinfo = path_info();
$script_name = script_name();
$s_url = script_name();
$selfurl = $s_url . $pathinfo;
$menu=param('menu');
$menu='login' unless ($menu);

$scookie = cookie(-name=>'sauron');
if ($scookie) {
  unless (load_state($scookie)) { 
    undef $scookie;
  }
}

unless ($scookie) {
  $new_cookie=make_cookie();
  print header(-cookie=>$new_cookie,-target=>'_top'),
        start_html(-title=>"Sauron Login",-BGCOLOR=>'white');
  login_form("Welcome",$ncookie);
}

if ($state{'mode'} eq 'auth' && param('login') eq 'yes') {
  print header(-target=>'_top'),
        start_html(-title=>"Sauron Login",-BGCOLOR=>'white');
  login_auth(); 
}

if ($state{'auth'} ne 'yes' || $pathinfo eq '/login') {
  print header(-target=>'_top'),
        start_html(-title=>"Sauron Login",-BGCOLOR=>'white');
  login_form("Welcome",$scookie);
}

error("Unauthorized Access denied!") 
  if ($ENV{'REMOTE_ADDR'} != $state{'addr'}) ;



if ($pathinfo ne '') {
  logout() if ($pathinfo eq '/logout');
  frame_set() if ($pathinfo eq '/frames');
  frame_set2() if ($pathinfo eq '/frames2');
  frame_1() if ($pathinfo eq '/frame1');
  frame_2() if ($pathinfo =~ /^\/frame2/);
  $frame_mode=1 if ($pathinfo =~ /^\/frame3/);
}


print header,
      start_html(-title=>"Sauron $VER",-BGCOLOR=>'white'),
      "\n\n<!-- Sauron $VER -->\n",
      "\n<!-- Copyright (c) Timo Kokkonen <tjko\@iki.fi>  2000. -->\n\n";

unless ($frame_mode) {
  top_menu(0);
  print "<TABLE bgcolor=\"green\" border=\"0\" cellspacing=\"5\" " .
          "width=\"100%\">\n" .
        "<TR><TD align=\"left\" valign=\"top\" bgcolor=\"white\" " .
          "width=\"15%\">\n";
  left_menu(0);
  print "<TD align=\"left\" valign=\"top\" bgcolor=\"white\">\n";
}



if ($menu eq 'servers') { servers(); }
elsif ($menu eq 'zones') { zones(); }
elsif ($menu eq 'login') { login(); }
else {
  print p,"unknown menu '$menu'";
}


if ($debug_mode) {
  print "<hr><FONT size=-1><p>script name: " . script_name() ." $formmode\n";
  print "<br>extra path: " . path_info() ."<br>framemode=$frame_mode\n",
         "<br>cookie='$scookie'\n",
        "<br>s_url='$s_url' '$selfurl'\n",
        "<br>url()=" . url(),
 #       "<p>self_url()=" . self_url(),
        "<p>";
  @names = param();
  foreach $var (@names) {
    print "$var = '" . param($var) . "'<br>\n";
  }

  print "<hr>state vars<p>\n";
  foreach $key (keys %state) {
    print " $key=" . $state{$key} . "<br>";
  }
  print "<hr><p>\n";
  foreach $key (keys %server_form) {
    print "$key,";
  }
}
 
print "</TABLE> <!-- end of page -->\n" unless ($frame_mode);
print "<p><hr>Sauron";
print end_html();

exit;


#####################################################################
sub servers() {
  $sub=param('sub');

  if ($sub eq 'add') {
    print p,"add...";
  }
  elsif ($sub eq 'del') {
    print p,"del...";
  }
  elsif ($sub eq 'edit') {
    $server=$state{'server'};
    $serverid=$state{'serverid'};
    if ($serverid eq '') {
      print p,"Server not selected";
      goto select_server;
    }

    if (param('srv_submit') ne '') {
      get_server($serverid,\%serv);
      unless (form_check_form('srv',\%serv,\%server_form)) {
	$res=update_server(\%serv);
	if ($res < 0) {
	  print "<FONT color=\"red\">",h1("Server record update failed!"),
	        "</FONT>";
	  print p,"server update result code=$res";
	} else {
	  print h2("Server record succesfully updated:");
	}
	get_server($serverid,\%serv);
	display_form(\%serv,\%server_form);
	return;
      }
      print "<FONT color=\"red\">",
            h2('Invalid data in form!'),
            "</FONT>";
    }

    unless (param('srv_re_edit') eq '1') {
      get_server($serverid,\%serv);
    }
    
    print h2("Edit server: $server"),p,
            startform(-method=>'POST',-action=>$selfurl),
            hidden('menu','servers'),hidden('sub','edit');
    form_magic('srv',\%serv,\%server_form);
    print submit(-name=>'srv_submit',-value=>'Make changes'),end_form;
    
  }
  else {
    $server=param('server_list');
    $server=$state{'server'} unless ($server);
    if ($server && $sub ne 'select') {
      #display selected server info
      $serverid=get_server_id($server);
      if ($serverid < 1) {
	print h3("Cannot select server!"),p;
	goto select_server;
      }
      print h2("Selected server: $server"),p;
      get_server($serverid,\%serv);
      if ($state{'serverid'} ne $serverid) {
	delete $state{'zone'};
	delete $state{'zoneid'};
	$state{'server'}=$server;
	$state{'serverid'}=$serverid;
	save_state($scookie);
      }
      display_form(\%serv,\%server_form); # display server record 
    }
    else {
     select_server:
      #display server selection dialig
      $list=get_server_list();
      for $i (0 .. $#{$list}) {
	push @l,$$list[$i][0];
      }
      print h2("Select server:"),p,
            startform(-method=>'POST',-action=>$selfurl),
            hidden('menu','servers'),p,
            "Available servers:",p,
            scrolling_list(-width=>'100%',-name=>'server_list',
			   -size=>'10',-values=>\@l),
            br,submit,end_form;
    }
  }
}

sub zones() {
  $sub=param('sub');
  $server=$state{'server'};
  $serverid=$state{'serverid'};
  if ($server eq '') { 
    print h2("Server not selected!");
    return;
  }

  if ($sub eq 'add') {
    print p,"add...";
  }
  elsif ($sub eq 'del') {
    print p,"del...";
  }
  elsif ($sub eq 'edit') {
    print p,"edit...";
  }
  else {
    $zone=param('selected_zone');
    $zone=$state{'zone'} unless ($zone);
    if ($zone && $sub ne 'select') {
      #display selected zone info
      $zoneid=get_zone_id($zone,$serverid);
      if ($zoneid < 1) {
	print h3("Cannot select zone '$zone'!"),p;
	goto select_zone;
      }
      print h2("Selected zone: $zone"),p;
      get_zone($zoneid,\%zn);
      $state{'zone'}=$zone;
      $state{'zoneid'}=$zoneid;
      save_state($scookie);
      
      $type=$zn{'type'};
      if ($type eq 'M') { $type='Master'; $color='#f0f000'; }
      elsif ($type eq 'S') { $type='Slave'; $color='#a0a0f0'; }
      $rev='No';
      $rev='Yes' if ($zn{'reverse'} eq 't');

      print "<TABLE bgcolor=$color width=\"100%\">",
         Tr,"<TH align=left width=30% bgcolor=white>Zone<TH>",
         Tr,td(['Zone name',$zn{'name'}]),
         Tr,td(['Zone Id',$zn{'id'}]),
         Tr,td(['Comments',$zn{'comment'}]),
         Tr,td(['Type',$type]),
         Tr,td(['Reverse',$zn{'reverse'}]),
         Tr,
         Tr,td(['Class',"\U$zn{'class'}"]);
      if ($type eq 'Master') {
	print 
         Tr,td(['Hostmaster',$zn{'hostmaster'}]),
         Tr,td(['Serial',$zn{'serial'}]),
         Tr,td(['Refresh',$zn{'refresh'}]),
         Tr,td(['Retry',$zn{'retry'}]),
         Tr,td(['Expire',$zn{'expire'}]),
         Tr,td(['Minimum',$zn{'minimum'}]),
         Tr,td(['TTL',$zn{'ttl'}]),
	 Tr,td("Name servers (NS)"),td;
	$list=$zn{'ns'};
	for $i (0 .. $#{$list}) {
	  print $$list[$i],"<br>";
	}
	if ($rev eq 'Yes') {
	  print Tr,td(['Reversenet',$zn{'reversenet'}]),
	        Tr,td("Zones used to build reverse"),td;
	  $list2=get_zone_list($serverid);
	  $list=$zn{'reverses'};
	  for $i (0 .. $#{$list}) {
	    $name='N/A';
	    for $j (0 .. $#{$list2}) {
	      $name=$$list2[$j][0] if ($$list[$i] eq $$list2[$j][1]);
	    }
	    print $$list[$i]," ($name)<br>";
	  }
	} else {
	  print Tr,td("Mail exchanges (MX)"),td;
	  $list=$zn{'mx'};
	  for $i (0 .. $#{$list}) {
	    print $$list[$i],"<br>";
	  }
	  print Tr,td("Info (TXT)"),td;
	  $list=$zn{'txt'};
	  for $i (0 .. $#{$list}) {
	    print $$list[$i],"<br>";
	  }
	  print Tr,td("DHCP"),td;
	  $list=$zn{'dhcp'};
	  for $i (0 .. $#{$list}) {
	    print $$list[$i],"<br>";
	  }
	}
      } else {
	print Tr,td("Masters"),td;
	$list=$zn{'masters'};
	for $i (0 .. $#{$list}) {
	  print $$list[$i],"<br>";
	}
      }
      
      #         Tr,Tr,"<TH align=left width=30% bgcolor=white>BIND",
#         Tr,td(['Hostmaster',$serv{'hostmaster'}]),
#         Tr,td(['Hostname',$serv{'hostname'}]),
#         Tr,td(['Directory',$serv{'directory'}]),
#         Tr,td(['Primary zone-file path',$serv{'pzone_path'}]),
#         Tr,td(['Slave zone-file path',$serv{'szone_path'}]),
#         Tr,td(['Root-server file',$serv{'named_ca'}]),
#         Tr,td('Allow transfer'),td;
#      $at=$serv{'allow_transfer'};
#      for $i (0 .. $#{$at}) {
#	print $$at[$i] . "<br>";
#      }
#      print Tr,Tr,"<TH align=left width=30% bgcolor=white>DHCP",
#            Tr,td('Global settings'),td;
#      $dh=$serv{'dhcp'};
#      for $i (0 .. $#{$dh}) {
#	print $$dh[$i] . "<br>";
#      }

      print "</TABLE>";
    }
    else {
     select_zone:
      #display zone selection list
      print h2("Zones for server: $server"),
            p,"<TABLE width=90% bgcolor=white border=0>",
            Tr,th(['Zone','Id','Type','Reverse']);
            
      $list=get_zone_list($serverid);
      for $i (0 .. $#{$list}) {
	$type=$$list[$i][2];
	if ($type eq 'M') { $type='Master'; $color='#f0f000'; }
	elsif ($type eq 'S') { $type='Slave'; $color='#a0a0f0'; }
	$rev='No';
	$rev='Yes' if ($$list[$i][3] eq 't');
	$id=$$list[$i][1];
	$name=$$list[$i][0];
	
	print "<TR bgcolor=$color>",td([
	  "<a href=\"$selfurl?menu=zones&selected_zone=$name\">$name</a>",
					$id,$type,$rev]);
      }
      
      print "</TABLE>";

    }
  }
}


sub login() {
  $sub=param('sub');

  if ($sub eq 'login') {
    print h2("Login as another user?"),p,
          "Click <a href=\"$s_url/login\">here</a> ",
          "if you want to login as another user.";
  }
  elsif ($sub eq 'logout') {
    print h2("Logout from the system?"),p,
          "Click <a href=\"$s_url/logout\">here</a> ",
          "if you want to logout.";
  }
  elsif ($sub eq 'passwd') {
    print h2("Change password"),p,
          "Click <a href=\"$s_url/logout\">here</a> ",
          "if you want to logout.";
  }
  else {
    print p,"Unknown menu selection!";
  }
}

#####################################################################

sub logout() {
  my($c);
  $c=cookie(-name=>'sauron',-value=>'',-expires=>'0s');
  remove_state($scookie);
  print header(-target=>'_top',-cookie=>$c),
        start_html(-title=>"Sauron Logout",-BGCOLOR=>'white'),
        h1("Sauron"),p,p,"You are now logged out...",
        end_html();
  exit;
}

sub login_form($$) {
  my($msg,$c)=@_;
  print start_form,h2($msg),p,
        "Login: ",textfield(-name=>'login_name',-maxlength=>'8'),p,
        "Password: ",password_field(-name=>'login_pwd',-maxlength=>'30'),p,
        hidden(-name=>'login',-default=>'yes'),
        submit,end_form;

  #print "</TABLE>\n" unless($frame_mode);
  print end_html();
  $state{'mode'}='auth';
  $state{'auth'}='no';
  save_state($c);
  exit;      
}

sub login_auth() {
  my($u,$p);  
  my(%user,$ctx,$salt,$pass,$digest);
  
  $state{'auth'}='no';
  delete $state{'mode'};
  $u=param('login_name');
  $p=param('login_pwd');
  $p=~s/\ \t\n//g;
  print "<P><BR><BR><BR><BR><CENTER>";
  if ($u eq '' || $p eq '') {
    print p,h1("Username or password empty!");
  } else {
    unless (get_user($u,\%user)) {
      $salt='';
      if ($user{'password'} =~ /^MD5:(\S+)\:(\S+)$/) {
	$salt=$1; 
      }
      #print p,h1("user ok<br>" . $user{'password'});
      if ($salt ne '') {
	$digest=pwd_crypt($p,$salt);
	if ($digest eq $user{'password'}) {
	  $state{'auth'}='yes';
	  $state{'user'}=$u;
	  print p,h1("Login ok!"),p,
	        "Come in... <a href=\"$s_url/frames\">frames version</a> ",
	        "or <a href=\"$s_url\">table version</a>";
	}
      }
    } 
  }

  print p,h1("Login failed."),p,"<a href=\"$selfurl\">try again</a>"
    unless ($state{'auth'} eq 'yes');

  print p,p,"</CENTER>";

  print "</TABLE>\n" unless ($frame_mode);
  print end_html();
  save_state($scookie);
  exit;
}

sub top_menu($) {
  my($mode)=@_;
  
  print '<TABLE bgcolor="white" border="0" cellspacing="0" width="100%">' .
        '<TR align="left" valign="bottom"><TD rowspan="2">' . 
	'<IMG src="' .$ICON_PATH . '/logo.png" alt="">';

  print "<TD>mode=$mode<TD>foo<TD>foo<TD>";
  print '<TR align="left" valign="bottom">';
  print "<TD><A HREF=\"$s_url?menu=servers\">servers</A>" .
        "<TD><A HREF=\"$s_url?menu=zones\">zones</A>" . 
	"<TD><A HREF=\"$s_url?menu=login\">login</A>";
  print "</TABLE>";
}

sub left_menu($) {
  my($mode)=@_;
  my($url);
    
  $url=$s_url;
  print h3("Menu:<br>$menu");
  #print "<p>mode=$mode";

  if ($menu eq 'servers') {
    $url.='?menu=servers';
    print p,"<a href=\"$url\">Current server</a><br>",
          "<a href=\"$url&sub=select\">Select server</a><br>",
          p,"<a href=\"$url&sub=add\">Add server</a><br>",
          "<a href=\"$url&sub=del\">Delete server</a><br>",
          "<a href=\"$url&sub=edit\">Edit server</a><br>";
  } elsif ($menu eq 'zones') {
    $url.='?menu=zones';
    print p,"<a href=\"$url\">Current zone</a><br>",
          p,"<a href=\"$url&sub=select\">Select zone</a><br>",
          p,"<a href=\"$url&sub=add\">Add zone</a><br>",
          "<a href=\"$url&sub=del\">Delete zone</a><br>",
          "<a href=\"$url&sub=edit\">Edit zone</a><br>";
  } elsif ($menu eq 'login') {
    $url.='?menu=login';
    print p,"<a href=\"$url&sub=login\">Login</a><br>",
          p,"<a href=\"$url&sub=logout\">Logout</a><br>",
          p,"<a href=\"$url&sub=passwd\">Change password</a><br>";
  } else {
    print "<p><p>empty menu\n";
  }
}

sub frame_set() {
  print header;
  
  print "<HTML><FRAMESET border=\"1\" rows=\"130,*\">\n" .
        "  <FRAME src=\"$script_name/frame1\" noresize>\n" .
        "  <FRAME src=\"$script_name/frames2\" name=\"bottom\">\n" .
        "  <NOFRAMES>\n" .
        "    Frame free version available \n" .
	"      <A HREF=\"$script_name\">here</A> \n" .
        "  </NOFRAMES>\n" .
        "</FRAMESET></HTML>\n";
  exit 0;
}

sub frame_set2() {
  print header;
  $menu="?menu=" . param('menu') if ($menu);
  
  print "<HTML>" .
        "<FRAMESET border=\"1\" cols=\"15%,85%\">\n" .
	"  <FRAME src=\"$script_name/frame2$menu\" name=\"menu\" noresize>\n" .
        "  <FRAME src=\"$script_name/frame3$menu\" name=\"main\">\n" .
        "  <NOFRAMES>\n" .
        "    Frame free version available \n" .
	"      <A HREF=\"$script_name\">here</A> \n" .
        "  </NOFRAMES>\n" .
        "</FRAMESET></HTML>\n";
  exit 0;
}


sub frame_1() {
  print header,
        start_html(-title=>"sauron: top menu",-BGCOLOR=>'white',
		   -target=>'bottom');

  $s_url .= '/frames2';
  top_menu(1);

  print end_html();
  exit 0;
}

sub frame_2() {
  print header,
        start_html(-title=>"sauron: left menu",-BGCOLOR=>'white',
		   -target=>'main');

  $s_url .= '/frame3';
  left_menu(1);

  print end_html();
  exit 0;
}

#####################################################################
sub make_cookie() {
  my($val);
  my($ctx);

  $val=rand 1000;

  $ctx=new Digest::MD5;
  $ctx->add($val);
  $ctx->add(time);
  $val=$ctx->b64digest;
  
  undef %state;
  $state{'auth'}='no';
  $state{'host'}=remote_host();
  $state{'addr'}=$ENV{'REMOTE_ADDR'};
  save_state($val);
  $ncookie=$val;
  return cookie(-name=>'sauron',-expires=>'+1d',-value=>$val,-path=>$s_url);
}

sub save_state($id) {
  my($id)=@_;

  open(STATEFILE,">$CGI_STATE_PATH/$id") || error2("cannot save state $id");
  if (keys(%state) > 0) {
    foreach $key (keys %state) {
      print STATEFILE "$key=" . $state{$key} ."\n";
    }
  } else {
      print STATEFILE "auth=no\n";
  }
  close(STATEFILE);
}


sub load_state($) {
  my($id)=@_;
  undef %state;
  $state{'auth'}='no';
  open(STATEFILE,"$CGI_STATE_PATH/$id") || return 0;
  while (<STATEFILE>) {
    next if /^\#/;
    next unless /^\s*(\S+)\s*\=\s*(\S+)\s*$/;
    $state{$1}=$2;
  }
  close(STATEFILE);
  return 1;
}

sub remove_state($) {
  my($id) = @_;

  unlink("$CGI_STATE_PATH/$id");
  undef %state;
}

#####################################################################

sub param_array($$) {
  my($pref,$a) = @_;
  my($i);

  param($pref,scalar @{$a});
  for $i (0..$#{$a}) {
    param("$pref$i",$$a[$i]);
  }
}

sub form_array($$) {
  my($pref,$size) = @_;
  my($i,$count,$p,$o);

  $j=0;
  $count=param("$pref");
  for ($i=0;$i<$count;$i++) {
    $p=param("$pref$i");
    $p2="${pref}${i}del";
  
    if (param($p2) ne "delete") {
      param("$pref$j",$p);
      print textfield(-name=>"$pref$j",-size=>$size,-value=>"$p"),
            submit(-name=>"${pref}${j}del",-value=>"delete"),"<br>";
      $j++;
    }
  }

  param("$pref",$j);
  print hidden(-name=>$pref,-value=>$j);
  
}


#####################################################################
# form_check_field($field,$value,$n) 
#
# checks if given field in form contains valid data
#
sub form_check_field($$$) {
  my($field,$value,$n) = @_;
  my($type,$empty);
  
  if ($n > 0) { 
    $empty=${$field->{empty}}[$n-1]; 
    $type=${$field->{type}}[$n-1];
  }
  else { 
    $empty=$field->{empty}; 
    $type=$field->{type};
  }

  unless ($empty == 1) {
    return 'Empty field not allowed!' if ($value =~ /^\s*$/);
  }


  if ($type eq 'fqdn') {
    return 'FQDN required!' 
      unless (valid_domainname($value) && $value=~/\.$/);
  } elsif ($type eq 'path') {
    return 'valid pathname required!'
      unless ($value =~ /^(|\S+\/)$/);
  } elsif ($type eq 'cidr') {
    return 'valid CIDR (IP) required!' unless (is_cidr($value));
  } elsif ($type eq 'text') {
    return '';
  } else {
    return "unknown typecheck for form_check_field: $type !";
  }

  return '';
}


#####################################################################
# form_check_form($prefix,$data,$form)
# 
# checks if form contains valid data and updates 'data' hash 
#
sub form_check_form($$$) {
  my($prefix,$data,$form) = @_;
  my($formdata,$i,$j,$k,$type,$p,$p2,$tag,$list,$id,$ind,$f,$new);

  $formdata=$form->{data};
  for $i (0..$#{$formdata}) {
    $rec=$$formdata[$i];
    $type=$rec->{ftype};
    $tag=$rec->{tag};
    $p=$prefix."_".$tag;

    if ($type == 1) {
      return 1 if (form_check_field($rec,param($p),0) ne '');
      #print p,"$p changed!" if ($data->{$tag} ne param($p));
      $data->{$tag}=param($p);
    } elsif  ($type == 2) {
      $f=$rec->{fields};
      $a=param($p."_count");
      $a=0 if (!$a || $a < 0);
      for $j (1..$a) {
	next if (param($p."_".$j."_del") eq 'on'); # skip if 'delete' checked
	for $k (1..$f) {
	  return 1 
	    if (form_check_field($rec,param($p."_".$j."_".$k),$k) ne '');
	}
      }

      # if we get this far, check what records we need to add/update/delete
      $list=$data->{$tag};
      for $j (1..$a) {
	$p2=$p."_".$j;
	$id=param($p2."_id");
	if ($id) {
	  $ind=-1;
	  for $k (0..$#{$list}) {
	    if ($$list[$k][0] eq $id) { $ind=$k; last; }
	  }
	} else { $ind=-1; }
	#print p,"foo $p2 id=$id ind=$ind";

	if (param($p2."_del") eq 'on') {
	  if ($ind >= 0) {
	    $$list[$ind][$f+1]=-1;
	    #print p,"$p2 delete record";
	  }
	} else {
	  if ($ind < 0) {
	    #print p,"$p2 add new record";
	    $new=[];
	    $$new[$f+1]=2;
	    for $k (1..$f) { $$new[$k]=param($p2."_".$k); }
	    push @{$list}, $new;
	  } else {
	    for $k (1..$f) {
	      if (param($p2."_".$k) ne $$list[$ind][$k]) {
		$$list[$ind][$f+1]=1;
		$$list[$ind][$k]=param($p2."_".$k);
		#print p,"$p2 modified record (field $k)";
	      }
	    }
	  }
	}
      }

    }
  }

  return 0;
}


sub form_magic($$$) {
  my($prefix,$data,$form) = @_;
  my($i,$j,$k,$n,$key,$rec,$a,$formdata,$h_bg,$e_str,$p1,$p2);

  $formdata=$form->{data};
  if ($form->{heading_bg}) { $h_bg=$form->{heading_bg}; }
  else { $h_bg=$SAURON_BGCOLOR; }

  # initialize fields
  unless (param($prefix . "_re_edit") eq '1' || ! $data) {
    for $i (0..$#{$formdata}) {
      $rec=$$formdata[$i];
      if ($rec->{ftype} == 1) { 
	param($prefix."_".$rec->{tag},$data->{$rec->{tag}});
      }
      elsif ($rec->{ftype} == 2) {
	$a=$data->{$rec->{tag}};
	for $j (1..$#{$a}) {
	  param($prefix."_".$rec->{tag}."_".$j."_id",$$a[$j][0]);
	  for $k (1..$rec->{fields}) {
	    param($prefix."_".$rec->{tag}."_".$j."_".$k,$$a[$j][$k]);
	  }
	}
	param($prefix."_".$rec->{tag}."_count",$#{$a});
      }
      elsif ($rec->{ftype} == 0) {
      }
      else { error("internal error (form_magic)");  }
    }
  }   

  #generate form fields
  print hidden($prefix."_re_edit",1),"\n<TABLE ";
  print "BGCOLOR=\"" . $form->{bgcolor} . "\" " if ($form->{bgcolor});
  print "FGCOLOR=\"" . $form->{fgcolor} . "\" " if ($form->{fgcolor});
# netscape sekoilee muuten no-frame modessa...
#  print "WIDTH=\"" . $form->{width} . "\" " if ($form->{width});
  print "BORDER=\"" . $form->{border} . "\" " if ($form->{border});
  print ">\n";


  for $i (0..$#{$formdata}) {
    $rec=$$formdata[$i];
    $p1=$prefix."_".$rec->{tag};

    if ($rec->{ftype} == 0) {
      print "<TR><TH COLSPAN=2 ALIGN=\"left\" BGCOLOR=\"$h_bg\">",
             $rec->{name},"</TH>\n";
    } elsif ($rec->{ftype} == 1) {
      print Tr,td($rec->{name}),"<TD>",
            textfield(-name=>$p1,-size=>$rec->{len},-value=>param($p1));

      print "<FONT size=-1 color=\"red\"><BR> ",
            form_check_field($rec,param($p1),0),
            "</FONT></TD>";
    } elsif ($rec->{ftype} == 2) {
      print Tr,td($rec->{name}),"<TD><TABLE>",Tr;
      $a=param($p1."_count");
      if (param($p1."_add") ne '') {
	$a=$a+1;
	param($p1."_count",$a);
      }
      $a=0 if (!$a || $a < 0);
      #if ($a > 50) { $a = 50; }
      print hidden(-name=>$p1."_count",-value=>$a);
      for $k (1..$rec->{fields}) { 
	print "<TD>",${$rec->{elabels}}[$k-1],"</TD>"; 
      }
      for $j (1..$a) {
	$p2=$p1."_".$j;
	print Tr,hidden(-name=>$p2."_id",param($p2."_id"));
	for $k (1..$rec->{fields}) {
	  $n=$p2."_".$k;
	  print "<TD>",textfield(-name=>$n,-size=>${$rec->{len}}[$k-1],
	                         -value=>param($n));
	  print "<FONT size=-1 color=\"red\"><BR>",
              form_check_field($rec,param($n),$k),
              "</FONT></TD>";
        }
        print td(checkbox(-label=>' Delete',
	             -name=>$p2."_del",-checked=>param($p2."_del") ));
      }
      print Tr,Tr,Tr,Tr;
      $j=$a+1;
      for $k (1..$rec->{fields}) {
	$n=$prefix."_".$rec->{tag}."_".$j."_".$k;
	print td(textfield(-name=>$n,-size=>${$rec->{len}}[$k-1],
		 -value=>param($n)));
      }
      print td(submit(-name=>$prefix."_".$rec->{tag}."_add",-value=>'Add'));
      print "</TABLE></TD>\n";
    }
  }

  print "</TABLE>";
}

sub display_form($$) {
  my($data,$form) = @_;
  my($i,$j,$k,$a,$rec,$formdata,$h_bg);

  $formdata=$form->{data};

  print "<TABLE ";
  print "BGCOLOR=\"" . $form->{bgcolor} . "\" " if ($form->{bgcolor});
  print "FGCOLOR=\"" . $form->{fgcolor} . "\" " if ($form->{fgcolor});
  print "WIDTH=\"" . $form->{width} . "\" " if ($form->{width});
  print "BORDER=\"" . $form->{border} . "\" " if ($form->{border});
  print ">";

  for $i (0..$#{$formdata}) {
    $rec=$$formdata[$i];

    if ($form->{heading_bg}) { $h_bg=$form->{heading_bg}; }
    else { $h_bg=$SAURON_BGCOLOR; }

    if ($rec->{ftype} == 0) {
      print "<TR><TH COLSPAN=2 ALIGN=\"left\" ",
            "BGCOLOR=\"$h_bg\">",
            $rec->{name},"</TH>\n";
    } elsif ($rec->{ftype} == 1) {
      #print Tr,td([$rec->{name},$data->{$rec->{tag}}]);
      print Tr,"<TD WIDTH=\"",$form->{nwidth},"\">",$rec->{name},"</TD><TD>",
            $data->{$rec->{tag}},"</TD>\n";
    } elsif ($rec->{ftype} == 2) {
      print Tr,td($rec->{name}),"<TD><TABLE>",Tr;
      $a=$data->{$rec->{tag}};
      for $k (1..$rec->{fields}) { 
	#print "<TH>",$$a[0][$k-1],"</TH>"; 
      }
      for $j (1..$#{$a}) {
	print Tr;
	for $k (1..$rec->{fields}) { print td($$a[$j][$k]); }
      }
      print "</TABLE></TD>\n";
    } else {
      error("internal error (display_form)");
    }
  }

  print "</TABLE>";
}

#####################################################################
sub error($) {
  my($msg)=@_;
  
  print header,
        start_html("sauron: error"),
        h1("Error: $msg"),
        end_html();
  exit;
}


sub error2($) {
  my($msg)=@_;
  
  print h1("Error: $msg"),
        end_html();
  exit;
}
