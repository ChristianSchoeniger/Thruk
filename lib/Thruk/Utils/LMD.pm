package Thruk::Utils::LMD;

=head1 NAME

Thruk::Utils::LMD - LMD Utilities Collection for Thruk

=head1 DESCRIPTION

LMD Utilities Collection for Thruk

=cut

use strict;
use warnings;
use File::Slurp qw/read_file/;
use Time::HiRes qw/sleep/;
use File::Copy qw/copy/;
use Thruk::Utils::External;
#use Thruk::Timer qw/timing_breakpoint/;

##########################################################
=head1 METHODS

=head2 check_proc

  check_proc($config, [$c], [$log_missing])

makes sure lmd process is running

=cut

sub check_proc {
    my($config, $c, $log_missing) = @_;

    my $lmd_dir = $config->{'tmp_path'}.'/lmd';
    my $logfile = $lmd_dir.'/lmd.log';
    my $size    = -s $logfile;
    if($size && $size > 20*1024*1024) { # rotate logfile if its more than 20mb
        copy($logfile.'.1', $logfile.'.2') if -e $logfile.'.1';
        copy($logfile, $logfile.'.1');
        Thruk::Utils::IO::write($logfile, '');
    }
    if(-e $lmd_dir.'/live.sock' && check_pid($lmd_dir.'/pid')) {
        return;
    }

    _write_lmd_config($config);

    $c->log->error("lmd not running, starting up...") if $log_missing;
    local $SIG{CHLD} = 'DEFAULT';
    my $cmd = ($config->{'lmd_core_bin'} || 'lmd')
              .' -pidfile '.$lmd_dir.'/pid'
              .' -config '.$lmd_dir.'/lmd.ini';
    if($config->{'lmd_core_config'}) {
        $cmd .= ' -config '.$config->{'lmd_core_config'};
    }
    $cmd .= ' >/dev/null 2>&1 &';

    my($rc, $output) = Thruk::Utils::IO::cmd($c, $cmd);
    $c->log->error(sprintf('starting lmd failed with rc %d: %s', $rc, $output)) if $rc != 0;

    #&timing_breakpoint('check_proc');
    return;
}

########################################

=head2 status

  status($config)

makes sure lmd process is running

=cut

sub status {
    my($config) = @_;

    my $status        = [];
    my $total_started = 0;
    my $started       = 0;
    my $pid;

    return($status, $total_started) unless $config->{'use_lmd_core'};

    my $lmd_dir = $config->{'tmp_path'}.'/lmd';
    if(-e $lmd_dir.'/live.sock' && check_pid($lmd_dir.'/pid')) {
        $total_started++;
        $started = 1;
        $pid     = read_file($lmd_dir.'/pid');
        chomp($pid);
    }
    push @{$status}, { status => $started, pid => $pid };
    return($status, $total_started);
}

########################################

=head2 restart

  restart($c, $config)

restart lmd process

=cut

sub restart {
    my($c, $config) = @_;

    shutdown_procs($config);

    # wait till its stopped
    my($status, $started) = (1, 1);
    for(my $x = 0; $x <= 20; $x++) {
        eval {
            ($status, $started) = status($config);
        };
        last if $started == 0;
        sleep 1;
    }

    check_proc($config, $c, 0);

    return;
}

########################################

=head2 shutdown_procs

  shutdown_procs($config)

stop all processes

=cut
sub shutdown_procs {
    my($config) = @_;
    return unless $config->{'use_lmd_core'};
    my $lmd_dir = $config->{'tmp_path'}.'/lmd';
    my $pidfile = $lmd_dir.'/pid';
    if(-s $pidfile) {
        my $pid = read_file($pidfile);
        kill(15, $pid);
    }
    return;
}

########################################

=head2 check_initial_start

  check_initial_start($c, $config)

do the initial start unless it has been started already or isn't used at all

=cut
sub check_initial_start {
    my($c, $config, $background) = @_;
    return if(!$config->{'use_lmd_core'});
    return if(!defined $ENV{'THRUK_SRC'} || ($ENV{'THRUK_SRC'} ne 'FastCGI' && $ENV{'THRUK_SRC'} ne 'DebugServer'));

    #&timing_breakpoint("lmd check_initial_start");

    if($background) {
        ## no critic
        $SIG{CHLD} = 'IGNORE';
        ## use critic
        my $pid = fork();
        if(!$pid) {
            Thruk::Utils::External::_do_child_stuff();
            ## no critic
            $SIG{CHLD} = 'DEFAULT';
            ## use critic
            check_proc($config, $c, 0);
            _check_changed_lmd_config($config);
            exit;
        }
    } else {
        check_proc($config, $c, 0);
        _check_changed_lmd_config($config);
    }

    #&timing_breakpoint("lmd check_initial_start done");

    return;
}


########################################

=head2 check_pid

  check_pid($file)

check if pidfile exists and contains a valid pid

=cut
sub check_pid {
    my($file) = @_;
    return 0 unless -s $file;
    my $pid = read_file($file);
    if($pid =~ m/^(\d+)\s*$/mx) {
        $pid = $1;
        if(-d '/proc/'.$pid) {
            my $cmd = read_file('/proc/'.$pid.'/cmdline');
            if($cmd =~ m/lmd/mxi) {
                return $pid;
            }
        }
    }
    return 0;
}

########################################

=head2 create_thread_dump

  create_thread_dump()

send sigusr1 to lmd to create a thread dump

=cut
sub create_thread_dump {
    my($c, $config) = @_;
    return if(!$config->{'use_lmd_core'});
    return if(!defined $ENV{'THRUK_SRC'} || ($ENV{'THRUK_SRC'} ne 'FastCGI' && $ENV{'THRUK_SRC'} ne 'DebugServer'));
    my $lmd_dir  = $config->{'tmp_path'}.'/lmd';
    my $pid_file = $lmd_dir.'/pid';
    my $pid = check_pid($pid_file);
    if($pid) {
        # send SIGUSR1
        kill(10, $pid);
    }
    return;
}

########################################

=head2 kill_if_not_responding

  kill_if_not_responding()

send test query and kill hard if it does not respond

=cut
sub kill_if_not_responding {
    my($c, $config) = @_;

    my $lmd_dir  = $config->{'tmp_path'}.'/lmd';
    my $pid_file = $lmd_dir.'/pid';
    my $lmd_pid  = check_pid($pid_file);
    return unless $lmd_pid;
    my $data;
    my $pid = fork();
    if($pid == -1) { die("fork failed: $!"); }

    if(!$pid) {
        Thruk::Utils::External::_do_child_stuff($c, 0, 0);
        alarm(2);
        eval {
            $data = $Thruk::Backend::Pool::lmd_peer->_raw_query("GET sites");
        };
        alarm(0);
        if($@) {
            $c->log->warn("lmd not responding, killing with force");
            kill(2, $lmd_pid);
            sleep(1);
            kill(9, $lmd_pid);
        }
        exit 0;
    }

    my $waited = 0;
    while(POSIX::waitpid($pid, POSIX::WNOHANG) == 0) {
        sleep(1);
        $waited++;
        last if $waited >= 2;
    }
    my $rc = $?;
    if($rc != 0) {
        $c->log->warn("lmd not responding, killing with force");
        kill(2, $pid);
        kill(2, $lmd_pid);
        sleep(1);
        kill(9, $lmd_pid);
        kill(9, $pid);
    }

    return;
}

########################################

=head2 _check_changed_lmd_config

  _check_changed_lmd_config($config)

check if the backends have changed and send a sighup to lmd if so

=cut
sub _check_changed_lmd_config {
    my($config) = @_;
    # return if it has not changed
    return unless _write_lmd_config($config);

    my $lmd_dir = $config->{'tmp_path'}.'/lmd';
    my $pidfile = $lmd_dir.'/pid';
    if(-s $pidfile) {
        my $pid = read_file($pidfile);
        kill(1, $pid);
    }
    return;
}

##############################################

=head2 _write_lmd_config

  _write_lmd_config($config)

write lmd.ini, returns true if file has changed or false otherwise

=cut
sub _write_lmd_config {
    my($config) = @_;
    my $lmd_dir = $config->{'tmp_path'}.'/lmd';

    # gather configs
    my $site_config = "Listen = ['".$lmd_dir."/live.sock']\n\n";

    $site_config .= "LogFile = '".$lmd_dir."/lmd.log'\n\n";
    $site_config .= "LogLevel = 'Warn'\n\n";

    if(!$config->{'ssl_verify_hostnames'}) {
        $site_config .= "SkipSSLCheck = 1\n\n";
    }

    for my $key (@{$Thruk::Backend::Pool::peer_order}) {
        my $peer = $Thruk::Backend::Pool::peers->{$key};
        $site_config .= "[[Connections]]\n";
        $site_config .= "name   = '".$peer->peer_name()."'\n";
        $site_config .= "id     = '".$key."'\n";
        $site_config .= "source = ['".join("', '", @{$peer->peer_list()})."']\n";
        if($peer->{'type'} eq 'http') {
            $site_config .= "auth = '".$peer->{'config'}->{'options'}->{'auth'}."'\n";
            $site_config .= "remote_name = '".$peer->{'config'}->{'options'}->{'remote_name'}."'\n" if $peer->{'config'}->{'options'}->{'remote_name'};
        }
        $site_config .= "\n";
    }

    eval {
        Thruk::Utils::IO::mkdir_r($lmd_dir) ;
    };
    die("could not create lmd ".$lmd_dir.': '.$@) if $@;

    if(-s $lmd_dir.'/lmd.ini') {
        my $old = read_file($lmd_dir.'/lmd.ini');
        if($old eq $site_config) {
            return(0);
        }
    }

    Thruk::Utils::IO::write($lmd_dir.'/lmd.ini',$site_config);
    return(1);
}

1;

__END__

=head1 AUTHOR

Sven Nierlein, 2009-present, <sven@nierlein.org>

=head1 LICENSE

This library is free software, you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut
