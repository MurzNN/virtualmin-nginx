do 'virtualmin-nginx-lib.pl';
$input_name = $module_name;
$input_name =~ s/[^A-Za-z0-9]/_/g;

use File::Copy;
use Data::Dumper;
use Date::Parse;

our ($conf_dir, $sites_avaliable_dir, $sites_enabled_dir, $log_dir);

#TODO if $conf_dir, $sites_avaliable_dir, $sites_enabled_dir come from user put trail slash
#TODO Config set by user not working, only default values

if($config{'conf_dir'} eq "")
{
  $conf_dir = '/etc/nginx/';
}

if($config{'sites_available_dir'} eq "")
{
  $sites_available_dir = 'sites-available/';
}

if($config{'sites_enabled_dir'} eq "")
{
  $sites_enabled_dir = 'sites-enabled/';
}



sub feature_always_links
{
  
}

sub feature_backup
{
  
}

sub feature_bandwidth
{
  my ($d, $start, $bwhash) = @_;

  if($d->{'alias'} gt 0) {
    return; # return if here is alias of domain
  }

  if($d->{'virtualmin-nginx'} ne 0) {
    return; # return if nginx is not enabled
  }

  local $tmpl = &virtual_server::get_template($_[0]->{'template'});
  if(!$tmpl->{$input_name.'_enable'}) {
    return; # return if nginx for this template disabled
  }
  
  $conffile="$conf_dir$sites_available_dir$d->{'dom'}.conf";
  
  open(FILE,$conffile);

  while($line=<FILE>) {
    if($line =~ /^[^#]*access_log\s([^;^\s]+)[\s;]/) {
      $file = $1;
      break;
    }
  }
  if(!$file) {
    print STDERR "nginx: can't find log file $file for domain $d->{'dom'} file $conffile";
#     print Dumper($d);
  }
  open(LOG,$file);

  while($line=<LOG>) {
    @line_spl = split(/ /,$line);
  
    $line =~ m/\[([^\]]+)\]/;
    $date = $1;
  
    $time=str2time($date);
  
    $bwtime = int($time/86400);
    
    $line =~ m/(\d+) "[\d\.\-]+"/;
    $in = $1;
    
    $out = $line_spl[10];
    if($time>$start) {
      $bwhash->{'web_'.$bwtime} += ($in+$out);
      $bwhash->{'nginx_'.$bwtime} += ($in+$out);
    }
  }

  return $time;
}

sub feature_check
{
  my $conf_file = $conf_dir . "nginx.conf";
  
  unless(-r $conf_file)
  {
    return "Nginx needs to be installed.";
  }
  
  unless (-d $conf_dir . $sites_available_dir)
  {
    mkdir($conf_dir . $sites_available_dir);
  }
  
  unless (-d $conf_dir . $sites_enabled_dir)
  {
    mkdir($conf_dir . $sites_enabled_dir);
  }

  
  open(CONF, $conf_file);
  
  local $/ = undef;
  my $filestring = <CONF>;
  close(CONF);
  
  #TODO: check if include directive not comment "# include /etc/nginx/sites-enabled/*;"
  my $pattern = "include " . $conf_dir . $sites_enabled_dir . "\\*;";
  
  unless ($filestring =~ /$pattern/) 
  {
    
    chop($filestring);
    
    $filestring .= "\tinclude " . $conf_dir . $sites_enabled_dir . "*;\n}"; 
    
    open(CONF,  ">", $conf_file);
    
    print(CONF $filestring);
    
    close(CONF);
    
  }
    
  return undef;
  
}

sub feature_clash
{
  return undef;
}

sub feature_delete
{
  my ($d) = @_;
  
  if($d->{'alias'}) 
  {
    &$virtual_server::first_print("Nginx alias mode");
    
    $d_parent = &virtual_server::get_domain($d->{'parent'});
    
    feature_delete_alias($d_parent,$d);
    
    return;
  }
  
  &$virtual_server::first_print("Deleting Nginx site ..");
  
  unlink($conf_dir . $sites_enabled_dir . $d->{'dom'} . ".conf");
  unlink($conf_dir . $sites_available_dir . $d->{'dom'} . ".conf");
  
  reload_nginx();
  
  &$virtual_server::second_print(".. done");
  
}

sub feature_depends
{
  return undef;
}

sub feature_disable
{
  my ($d) = @_;
  local $tmpl = &virtual_server::get_template($_[0]->{'template'});
#   if(!$tmpl->{'virtualmin-nginx_enable'}) {
#     return; # return if nginx for this template disabled
#   }
  
  &$virtual_server::first_print("Disabling Nginx website ..");
  unlink($conf_dir . $sites_enabled_dir . $d->{'dom'} . ".conf");
  reload_nginx();
  &$virtual_server::second_print(".. done");
}

sub feature_disname
{
  return "Nginx website";
}

sub feature_enable
{
  local $tmpl = &virtual_server::get_template($_[0]->{'template'});
  if(!$tmpl->{$input_name.'_enable'}) {
    return; # return if nginx for this template disabled
  }
  
  my ($d) = @_;
  &$virtual_server::first_print("Re-enabling Nginx website ..");
  symlink($conf_dir . $sites_available_dir . $d->{'dom'} . ".conf", $conf_dir . $sites_enabled_dir . $d->{'dom'} . ".conf");
  reload_nginx();
  &$virtual_server::second_print(".. done");
  
  
}

sub feature_import
{
  
}

sub feature_label
{
  return "Setup Nginx website for domain?";
}

sub feature_links
{
  
}

sub feature_losing
{
  return "The Nginx config file for this website will be deleted.";
}

sub feature_modify
{
  
  &$virtual_server::first_print("modifying Nginx site ..");
  my ($d, $oldd) = @_;

#   &$virtual_server::first_print("$d->{'ip'} ne $oldd->{'ip'}");
#   &$virtual_server::first_print(Dumper($d));
#   &$virtual_server::first_print(Dumper($oldd));


  local $tmpl = &virtual_server::get_template($d->{'template'});
  if($d->{'template'}!=$oldd->{'template'}) {
    local $old_tmpl = &virtual_server::get_template($oldd->{'template'});
    if($tmpl->{$input_name.'_enable'} && !$old_tmpl->{$input_name.'_enable'}) { #in new template nginx are enabled 
      &$virtual_server::first_print('in new template nginx are enabled');
      &feature_setup($d);
      return;
    } elsif(!$tmpl->{$input_name.'_enable'} && $old_tmpl->{$input_name.'_enable'}) { #in new template nginx are disabled
      &$virtual_server::first_print('in new template nginx are disabled');
      &feature_disable($d);
      return;
    }
  }
  if(!$tmpl->{$input_name.'_enable'}) {
    return; # return if nginx for this template disabled
  }
  
  if($d->{'alias'}) 
  {
    &$virtual_server::first_print("nginx feature_modify: Nginx alias mode - don't create separate conf file.");
    
    $d_parent = &virtual_server::get_domain($d->{'parent'});
    
    if($d->{'dom'} eq $oldd->{'dom'}) {
      &$virtual_server::second_print("nginx feature_modify: alias don't changed, do nothing.");
      return;
    }
    
  open(CONFFILE, "<" . $conf_dir . $sites_available_dir . $d_parent->{'dom'} . ".conf");
  @conf=<CONFFILE>;
  close(CONFFILE);
  
  $conf=join("",@conf);
  
  $conf =~ s/\s$oldd->{'dom'}(?>[\s;])/$d->{'dom'}/gi;
  $conf =~ s/\swww\.$oldd->{'dom'}(?>[\s;])/$d->{'dom'}/gi;

  open(CONFFILE, ">" . $conf_dir . $sites_available_dir . $d_parent->{'dom'} . ".conf");
  print(CONFFILE $conf);
  close(CONFFILE);
  
  reload_nginx();    


    return;
  }
  
  if ($d->{'dom'} ne $oldd->{'dom'} || $d->{'home'} ne $oldd->{'home'} || $d->{'dns_ip'} ne $oldd->{'dns_ip'} || $d->{'ip'} ne $oldd->{'ip'} ) {
    &$virtual_server::first_print('changing config file');
    
    if($config{'log_dir'} eq "")
    {
      $log_dir = "$d->{'home'}/logs/";
      $old_log_dir = "$oldd->{'home'}/logs/";
    }
    &$virtual_server::first_print("nginx Changing conf files from $oldd->{'dom'} to $d->{'dom'}");
    
    open(CONFFILE, "<" . $conf_dir . $sites_available_dir . $oldd->{'dom'} . ".conf");
    @conf=<CONFFILE>;
    close(CONFFILE);
  
    $conf=join("",@conf);
  
    $conf =~ s/(server_name.*\s)$oldd->{'dom'}/$1$d->{'dom'}/gi;
    $conf =~ s/(server_name.*\s)www\.$oldd->{'dom'}/$1www.$d->{'dom'}/gi;

    local $ip_old=$oldd->{'dns_ip'}?$oldd->{'dns_ip'}:$oldd->{'ip'};
    local $ip_new=$d->{'dns_ip'}?$d->{'dns_ip'}:$d->{'ip'};
#     &$virtual_server::first_print("$ip_old ne $ip_new");
    
    if($ip_old ne $ip_new) {
      $conf =~ s/listen\s+$ip_old:/listen $ip_new:/gi;
    }


    $conf =~ s/(access_log\s+)$old_log_dir$oldd->{'dom'}\.access\.log/$1$log_dir$d->{'dom'}\.access\.log/gi;
    $conf =~ s/(error_log\s+)$old_log_dir$oldd->{'dom'}\.error\.log/$1$log_dir$d->{'dom'}\.error\.log/gi;
    
    open(CONFFILE, ">" . $conf_dir . $sites_available_dir . $oldd->{'dom'} . ".conf");
    print(CONFFILE $conf);
    close(CONFFILE);
    
    unlink($conf_dir . $sites_enabled_dir . $oldd->{'dom'} . ".conf");
    rename($conf_dir . $sites_available_dir . $oldd->{'dom'} . ".conf", $conf_dir . $sites_available_dir . $d->{'dom'} . ".conf");
    symlink($conf_dir . $sites_available_dir . $d->{'dom'} . ".conf", $conf_dir . $sites_enabled_dir . $d->{'dom'} . ".conf");
  
    reload_nginx();
  }
  
  &$virtual_server::second_print(".. done");
}

sub feature_name
{
  return "Nginx website";
}

sub feature_restore
{
  
}

sub feature_setup
{
  my ($d) = @_;
  &$virtual_server::first_print("Setting up Nginx site ..");
  
  local $tmpl = &virtual_server::get_template($d->{'template'});
#   print Dumper($tmpl);
  if(!$tmpl->{$input_name.'_enable'}) {
    &$virtual_server::first_print("Nginx site for this template (".$tmpl->{'name'}.") is disabled, skipping creating nginx site. You can enable nginx site creation in Server Templates > Edit Server Template > Plugin options.");
    return; # return if nginx for this template disabled
  }
  
  
  my $file;
  
  if($config{'log_dir'} eq "")
  {
    $log_dir = "$d->{'home'}/logs/";
  }
  
  if($d->{'alias'}>0) 
  {
    &$virtual_server::first_print("nginx feature_setup: Nginx alias mode - don't create separate conf file.");

    $d_parent = &virtual_server::get_domain($d->{'parent'});
    
    open(CONFFILE, "<" . $conf_dir . $sites_available_dir . $d_parent->{'dom'} . ".conf");
    @conf=<CONFFILE>;
    close(CONFFILE);
    
    $conf=join("",@conf);
    
    if( $conf =~ m/server_name(\s.*)?\s$d->{'dom'}/mi ) { # find exist record for this alias
      &$virtual_server::second_print("nginx feature_modify: found record for this alias, not creating new one.");
    } else {
      &$virtual_server::first_print("nginx feature_modify: can't find record for this alias, creating new one.");
      feature_setup_alias($d_parent,$d);
      reload_nginx();    
    }
    
    return;
  }
  
  
  open($file, ">" . $conf_dir . $sites_available_dir . $d->{'dom'} . ".conf");
  #TODO in config.info add nginx config template with default value conf_tmpl=nginx config template,9,server{ listen $d->{'ip'}:80;} or get it from nginx_conf.tpl and parse
  #TODO Determine subdomain and dont put rewrite ^/(.*) http://www.$d->{'dom'} permanent;

  if($config{'nginx_conf_tpl'} eq "") {
    open(CONFFILE, "<" . "../virtualmin-nginx/nginx-default.conf");
    &$virtual_server::first_print("Using default config file nginx-default.conf");
    @conf=<CONFFILE>;
    close(CONFFILE);
    $conf=join("",@conf);
  } else {
    &$virtual_server::first_print("Using custom config file");
    $conf=$config{'nginx_conf_tpl'};
  }

  $conf_v_nginx_ip = $config{'nginx_ip'} ? ($config{'nginx_ip'} eq 'dns_ip'?($d->{'dns_ip'}?$d->{'dns_ip'}:$d->{'ip'}):$config{'nginx_ip'}) : $d->{'ip'};
  $conf_v_nginx_port = $config{'nginx_port'} ? $config{'nginx_port'} : '80';
  $conf_v_proxy_ip = $config{'proxy_ip'} ? $config{'proxy_ip'} : '127.0.0.1';
  $conf_v_proxy_port = $config{'proxy_port'} ? $config{'proxy_port'} : '81';

  $conf =~ s/\t/\n/g;

  %conf_vars= (
    '${DOM}' => $d->{'dom'},
    '${IP}' => $conf_v_nginx_ip,
    '${PORT}' => $conf_v_nginx_port,
    '${PROXY_IP}' => $conf_v_proxy_ip,
    '${PROXY_PORT}' => $conf_v_proxy_port,
    '${HOME}' => $d->{'home'},
    '${PUBLIC_HTML_PATH}' => $d->{'public_html_path'},
  );
  
  while(($key,$value) = each %conf_vars) {
    $key = quotemeta($key);
    $conf =~ s/$key/$value/g;
  }
  
  print($file $conf);
  
  close $file;
  
  symlink($conf_dir . $sites_available_dir . $d->{'dom'} . ".conf", $conf_dir . $sites_enabled_dir . $d->{'dom'} . ".conf");
  
  reload_nginx();
  
  &$virtual_server::second_print(".. done");
}

# feature_setup_alias(&domain, &alias)
# Called when an alias of this domain is created, to perform any required
# configuration changes. Only useful when the plugin itself does not implement
# an alias feature.
sub feature_setup_alias
{
  local ($d, $alias) = @_;
  &$virtual_server::first_print("Setting up Nginx alias site ..");
  
  open(CONFFILE, "<" . $conf_dir . $sites_available_dir . $d->{'dom'} . ".conf");
  @conf=<CONFFILE>;
  close(CONFFILE);
  
  $conf=join("",@conf);

  if( $conf =~ m/server_name(\s.*)?\s$alias->{'dom'}/mi ) { # find exist record for this alias
      &$virtual_server::first_print("nginx feature_setup_alias: alias ".$alias->{'dom'}." already exists for domain ".$d->{'dom'});
  } else {
    $conf =~ s/(server_name(\s.*?)?\s$d->{'dom'} www\.$d->{'dom'})/$1 $alias->{'dom'} www\.$alias->{'dom'}/gi;
      &$virtual_server::first_print("nginx feature_setup_alias: alias ".$alias->{'dom'}." added for domain ".$d->{'dom'});
  }

  open(CONFFILE, ">" . $conf_dir . $sites_available_dir . $d->{'dom'} . ".conf");
  print(CONFFILE $conf);
  close(CONFFILE);
  
  reload_nginx();
  
  &$virtual_server::second_print(".. done");
}

# feature_delete_alias(&domain, &alias)
# Called when an alias of this domain is deleted, to perform any required
# configuration changes. Only useful when the plugin itself does not implement
# an alias feature.
sub feature_delete_alias
{
  local ($d, $alias) = @_;
  
  &$virtual_server::first_print("Deleting Nginx alias site ..");

  open(CONFFILE, "<" . $conf_dir . $sites_available_dir . $d->{'dom'} . ".conf");
  @conf=<CONFFILE>;
  close(CONFFILE);
  
  $conf=join("",@conf);
  
  $conf =~ s/(server_name(\s.*?)?)\s$alias->{'dom'}(?=[\s;])/$1/gmi;
  $conf =~ s/(server_name(\s.*?)?)\swww\.$alias->{'dom'}(?=[\s;])/$1/gmi;

  open(CONFFILE, ">" . $conf_dir . $sites_available_dir . $d->{'dom'} . ".conf");
  print(CONFFILE $conf);
  close(CONFFILE);
  
  reload_nginx();
  
  &$virtual_server::second_print(".. done");

}

# feature_modify_alias(&domain, &alias, &old-alias)
# Called when an alias of this domain is deleted, to perform any required
# configuration changes. Only useful when the plugin itself does not implement
# an alias feature.
sub feature_modify_alias
{
  &$virtual_server::first_print("Modifying Nginx alias site ..");
}


sub feature_suitable
{
  return 1;
}

sub feature_validate
{
  return undef;
}

sub feature_webmin
{
  
}

# template_input(&template)
# Returns HTML for editing per-template options for this plugin
sub template_input
{
local ($tmpl) = @_;
local $v = $tmpl->{$input_name."_enable"};
$v = 1 if (!defined($v) && $tmpl->{'default'});
# print Dumper($tmpl);
return &ui_table_row($text{'tmpl_nginx-enable'},
        &ui_radio($input_name."_enable", $v,
                  [ $tmpl->{'default'} ? ( ) : ( [ '', $text{'default'} ] ),
                    [ 1, $text{'yes'} ],
                    [ 0, $text{'no'} ] ]));
}

# template_parse(&template, &in)
# Updates the given template object by parsing the inputs generated by
# template_input. All template fields must start with the module name.
sub template_parse
{
local ($tmpl, $in) = @_;
# print Dumper($in);
$tmpl->{$input_name.'_enable'} = $in->{$input_name.'_enable'};
}


sub reload_nginx
{
  if($config{'nginx_pid'} eq "")
  {
    $nginx_pid = '/var/run/nginx.pid';
  }
  if($config{'nginx_path'} eq "")
  {
    $nginx_path = '/usr/sbin/nginx';
  }
  
  &$virtual_server::first_print("Testing new nginx config");
  $out=`$nginx_path -t 2>&1`;
  $result_num=$?;
  
  if($? == 0) {
    
    if($out =~ /\[(warn|emerg)]/g) {
      &$virtual_server::first_print($out);
    }
    &$virtual_server::first_print("Reloading nginx");
    my $pid = `cat $nginx_pid`;
    `kill -HUP $pid`;
  } else {
    &$virtual_server::second_print("..not restarting nginx, failed to test nginx config - result of '$nginx_path -t' is $?, output: $out");
  }
}

sub fix_perm
{
    # TODO nginx run as www-data, default perm on public_html in Virtualmin 0740 Sequrity alert if chmod 0755
    my ($dir) = @_;
    
    if($config{'public_html_perm'} eq "")
    {
        $public_html_perm = '0755';
    }
    chmod oct($public_html_perm), $dir;
}