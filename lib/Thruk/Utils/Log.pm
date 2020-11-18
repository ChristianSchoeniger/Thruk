package Thruk::Utils::Log;

=head1 NAME

Thruk::Utils::Log - command line logging utils

=head1 DESCRIPTION

Utilities Collection for CLI logging

=cut

use warnings;
use strict;
use Cwd qw/abs_path/;
use Data::Dumper qw/Dumper/;
use Time::HiRes ();
use POSIX ();
use File::Slurp qw(read_file);

use Thruk::Base ();

use Exporter 'import';
our @EXPORT_OK = qw(_fatal _error _warn _info _infos _infoc
                    _debug _debug2 _debugs _debugc _trace _audit_log
                    );
our %EXPORT_TAGS = ( all => \@EXPORT_OK );

##############################################

our $logger;
our $filelogger;
our $screenlogger;
our $layouts = {};
our $cwd = Cwd::getcwd;

##############################################

=head2 log

    log returns the current logger object

=cut
sub log {
    _init_logging() unless $logger;
    return($logger);
}

##############################################
sub _fatal {
    _log('ERROR', \@_);
    exit(3);
}

##############################################
sub _error {
    return _log('ERROR', \@_);
}

##############################################
sub _warn {
    return _log('WARNING', \@_);
}

##############################################
sub _info {
    return _log('INFO', \@_);
}

##############################################
# start info entry, but do not add newline
sub _infos {
    return _log('INFO', \@_, { newline => 0 });
}

##############################################
# continue info entry, still do not add newline and simply append given text
sub _infoc {
    return _log('INFO', \@_, { append => 1 });
}

##############################################
sub _trace {
    return _log('TRACE', \@_);
}

##############################################
sub _debug {
    return _log('DEBUG', \@_);
}

##############################################
# start debug entry, but do not add newline
sub _debugs {
    return _log('DEBUG', \@_, { newline => 0 });
}

##############################################
# continue debug entry, still do not add newline and simply append given text
sub _debugc {
    return _log('DEBUG', \@_, { append => 1 });
}

##############################################
sub _debug2 {
    return _log('DEBUG2', \@_);
}

##############################################
sub _log {
    my($lvl, $data, $options) = @_;
    my $line = shift @{$data};
    return unless defined $line;
    $lvl = 'DEBUG' unless defined $lvl;
    if(Thruk::Base::quiet()) {
        return if($lvl ne 'WARN' && $lvl ne 'ERROR');
    } else {
        return if($lvl eq 'TRACE'  && !Thruk::Base::trace());
        return if($lvl eq 'DEBUG'  && !Thruk::Base::verbose());
        return if($lvl eq 'DEBUG2' && !Thruk::Base::debug());
    }
    if(defined $ENV{'THRUK_TEST_NO_LOG'}) {
        $ENV{'THRUK_TEST_NO_LOG'} .= $line."\n";
        return;
    }
    _init_logging() unless $logger;
    if(ref $line) {
        return _log($lvl, Dumper([$line, @{$data}]), $options);
    } elsif(scalar @{$data} > 0) {
        $line = sprintf($line, @{$data});
    }
    my $appender_changed;
    our $last_was_plain;
    if(defined $options->{'newline'} && !$options->{'newline'}) {
        # skip newline from format
        my $appenders = Log::Log4perl::appenders();
        for my $appender (values %{$appenders}) {
            $layouts->{'original'} = $appender->layout() unless $layouts->{'original'};
            $appender->layout($layouts->{'no_newline'});
        }
        $last_was_plain = 1;
        $appender_changed = 1;
    }
    elsif($options->{'append'}) {
        # skip newline and timestamp
        my $appenders = Log::Log4perl::appenders();
        for my $appender (values %{$appenders}) {
            $layouts->{'original'} = $appender->layout() unless $layouts->{'original'};
            $appender->layout($layouts->{'plain'});
        }
        $last_was_plain = 1;
        $appender_changed = 1;
    }
    elsif($last_was_plain) {
        # skip newline and timestamp
        my $appenders = Log::Log4perl::appenders();
        for my $appender (values %{$appenders}) {
            $layouts->{'original'} = $appender->layout() unless $layouts->{'original'};
            $appender->layout($layouts->{'plain_nl'});
        }
        $appender_changed = 1;
        $last_was_plain  = undef;
    }
    local $Log::Log4perl::caller_depth = $Log::Log4perl::caller_depth+2;
    for my $l (split/\n/mx, $line) {
        if(   $lvl eq 'ERROR')   { $logger->error($l); }
        elsif($lvl eq 'WARNING') { $logger->warn($l);  }
        elsif($lvl eq 'INFO')    { $logger->info($l);  }
        else                     { $logger->debug($l); }
    }
    if($appender_changed) {
        # skip newline and timestamp
        my $appenders = Log::Log4perl::appenders();
        for my $appender (values %{$appenders}) {
            $appender->layout($layouts->{'original'});
        }
    }
    my $config = _config();
    &reset_logging unless $config; # do not store logger if we are not fully initialized yet
    return;
}

###################################################

=head2 _audit_log

    _audit_log logs something with info log level and
    in case screen logger is active, logs it also to the logfile.

=cut
sub _audit_log {
    my($category, $msg, $user, $sessionid, $print) = @_;
    my $config = _config();
    $print = $print // 1;

    if(!$user) {
        $user = '?';
        if(defined $Thruk::Request::c) {
            my $c = $Thruk::Request::c;
            $user = $c->stash->{'remote_user'} // '?';
        }
    }

    if(!$sessionid) {
        if(defined $Thruk::Request::c) {
            my $c = $Thruk::Request::c;
            if($c->{'session'}) {
                $sessionid = $c->{'session'}->{'hashed_key'};
            }
        }
    }
    if(!$sessionid) {
        if(Thruk::Base::mode() eq 'CLI') {
            $sessionid = 'command line';
        }
    }
    if(!$sessionid) {
        $sessionid = '?';
    }

    $msg = sprintf("[%s][%s][%s] %s", $category, $user, $sessionid, $msg);
    if($ENV{'THRUK_TEST_NO_AUDIT_LOG'}) {
        $ENV{'THRUK_TEST_NO_AUDIT_LOG'} .= "\n".$msg;
        return;
    }

    if(defined $config->{'audit_logs'}->{$category} && !$config->{'audit_logs'}->{$category}) {
        # audit log disabled for this category
        _debug($msg);
        return;
    }

    # log to thruk.log and print to screen
    _init_logging() unless $logger;
    $filelogger->info($msg) if $filelogger;
    _info($msg) if($print || !$filelogger);

    if(defined $config->{'audit_logs'} && $config->{'audit_logs'}->{'logfile'}) {
        my $file = $config->{'audit_logs'}->{'logfile'};
        my(undef, $microseconds) = Time::HiRes::gettimeofday();
        my $milliseconds = substr(sprintf("%06s", $microseconds), 0, 3);
        my @localtime = localtime;
        my $log = sprintf("[%s,%s][%s]%s\n",
            POSIX::strftime("%Y-%m-%d %H:%M:%S", @localtime),
            $milliseconds,
            $Thruk::HOSTNAME,
            $msg,
        );
        $log =~ s/\n*$//gmx;
        $file = POSIX::strftime($file, @localtime) if $file =~ m/%/gmx;
        require Thruk::Utils::IO;
        Thruk::Utils::IO::write($file, $log."\n", undef, 1);
    }

    return;
}

##############################################

=head2 wrap_stdout2log

    wrap stdout to info logger. everything printed to stdout will be logged
    with info level to stderr.

=cut
sub wrap_stdout2log {
    my($capture, $tmp);
    ## no critic
    open($capture, '>', \$tmp) or die("cannot open stdout capture: $!");
    tie *$capture, 'Thruk::Utils::Log', (*STDOUT);
    select $capture;
    $|=1;
    ## use critic
    return($capture);
}

##############################################

=head2 wrap_stdout2log_stop

    stop wrapping stdout

=cut
sub wrap_stdout2log_stop {
    ## no critic
    select *STDOUT;
    ## use critic
    return;
}

##############################################
sub TIEHANDLE {
    my($class, $fh) = @_;
    my $self = {
        fh      => $fh,
        newline => 1,
    };
    bless $self, $class;
    return($self);
}

##############################################
sub BINMODE {
    my($self, $mode) = @_;
    return binmode $self->{'fh'}, $mode;
}

##############################################
sub PRINTF {
    my($self, $fmt, @data) = @_;
    return($self->PRINT(sprintf($fmt, @data)));
}

##############################################
sub PRINT {
    my($self, @data) = @_;

    my $last_newline = $self->{'newline'};
    $self->{'newline'} = (join("", @data) =~ m/\n$/mx) ? 1 : 0;

    if(!$last_newline && !$self->{'newline'}) {
        _infoc(@data);
    }
    elsif(!$self->{'newline'}) {
        _infos(@data);
    }
    else {
        _info(@data);
    }
    return;
}

###################################################
sub _init_logging {
    require Log::Log4perl;

    my $config = _config();
    delete $config->{'log4perl_logfile_in_use'};

    my($log4perl_conf);
    if(Thruk::Base::mode() eq 'FASTCGI' || $ENV{'THRUK_JOB_DIR'} || $ENV{'THRUK_CRON'}) {
        if(defined $config->{'log4perl_conf'} && ! -s $config->{'log4perl_conf'} ) {
            die("\n\n*****\nfailed to load log4perl config: ".$config->{'log4perl_conf'}.": ".$!."\n*****\n\n");
        }
        $log4perl_conf = $config->{'log4perl_conf'} || ($config->{'home'}//Thruk::Config::home()).'/log4perl.conf';
    }

    if(defined $log4perl_conf && -s $log4perl_conf) {
        $logger = _get_file_logger($log4perl_conf, $config);
    } else {
        $logger = _get_screen_logger($config);
    }

    if(Thruk::Base::verbose()) {
        _debug("logging initialized with loglevel ".Thruk::Base::verbose());
    }

    return;
}

###################################################
sub _get_file_logger {
    my($log4perl_conf, $config) = @_;
    return($filelogger) if $filelogger;

    $log4perl_conf = read_file($log4perl_conf);
    if($log4perl_conf =~ m/log4perl\.appender\..*\.filename=(.*)\s*$/mx) {
        $config->{'log4perl_logfile_in_use'} = $1;
    }
    $log4perl_conf =~ s/\.Threshold=INFO/.Threshold=DEBUG/gmx if Thruk::Base::debug();
    Log::Log4perl::init(\$log4perl_conf);
    $filelogger = Log::Log4perl::get_logger("thruk.log");
    return($filelogger);
}

###################################################
sub _get_screen_logger {
    my($config) = @_;
    return($screenlogger) if $screenlogger;

    # since we log to stderr, check if stderr is attached to a terminal
    ## no critic
    my $use_color = -t STDERR;
    ## use critic
    if($use_color) {
        require Term::ANSIColor;
        $use_color = 0 if $@;
    }

    my $format = '[%d{ABSOLUTE}][%p] %m{chomp}';
    if($ENV{'TEST_AUTHOR'} || $config->{'thruk_author'} || Thruk::Base::debug()) {
        $format = '[%d{ABSOLUTE}]['.($use_color ? '%p{1}' : '%p').'][%-30Z] %m{chomp}';
        Log::Log4perl::Layout::PatternLayout::add_global_cspec('Z', \&_striped_caller_information);
    }

    my($pre, $post) = ("", "");
    if($use_color) {
        $pre  = '%Y';
        $post = Term::ANSIColor::color("reset");
        Log::Log4perl::Layout::PatternLayout::add_global_cspec('Y', \&_color_by_level);
    }

    Log::Log4perl::Layout::PatternLayout::add_global_cspec('Q', \&_priority_error_warn_only);
    if(!Thruk::Base::verbose() || Thruk::Base::quiet()) {
        $format = '%Q%m{chomp}';
    }

    $layouts->{'no_newline'} = Log::Log4perl::Layout::PatternLayout->new($pre.$format.$post);
    $layouts->{'plain'}      = Log::Log4perl::Layout::PatternLayout->new($pre.'%m{chomp}'.$post);
    $layouts->{'plain_nl'}   = Log::Log4perl::Layout::PatternLayout->new($pre.'%m{chomp}%n'.$post);
    $format = $pre.$format.$post."%n";

    my $log_conf = "
    log4perl.logger                    = DEBUG, Screen
    log4perl.appender.Screen           = Log::Log4perl::Appender::Screen
    log4perl.appender.Screen.Threshold = DEBUG
    log4perl.appender.Screen.layout    = Log::Log4perl::Layout::PatternLayout
    log4perl.appender.Screen.layout.ConversionPattern = $format
    ";
    Log::Log4perl::init(\$log_conf);
    $screenlogger = Log::Log4perl->get_logger("thruk.screen");
    return($screenlogger);
}

###################################################

=head2 reset_logging

    reset logging system, for example after starting child processes

=cut
sub reset_logging {
    return unless $logger;

    Log::Log4perl->remove_logger($logger);
    Log::Log4perl->remove_logger($filelogger)   if $filelogger;
    Log::Log4perl->remove_logger($screenlogger) if $screenlogger;

    $logger       = undef;
    $filelogger   = undef;
    $screenlogger = undef;
    $layouts      = {};

    my $config = _config();
    delete $config->{'log4perl_logfile_in_use'} if $config;
    return;
}

##############################################
sub _striped_caller_information {
    my($layout, $message, $category, $priority, $caller_level) = @_;
    my @caller = caller($caller_level);
    while($caller[0] =~ m/Thruk::Utils::Log/mx) {
        $caller_level++;
        @caller = caller($caller_level);
    }
    my $path = abs_path($caller[1]) || $caller[1];
    $path =~ s%^$cwd/%./%gmx;
    $path =~ s%^/opt/omd/versions/.*?/share/thruk/%./%gmx;
    $path =~ s%/plugins/plugins-available/%/plug/%gmx;
    $path =~ s%^\./%%gmx;
    my $str = sprintf("%s:%d", $path, $caller[2]);
    if(length $str > 30) {
        $str = "...".substr($str, -27);
    }
    return($str);
}

##############################################
sub _color_by_level {
    my($layout, $message, $category, $priority) = @_;
    return("") if $ENV{'THRUK_NO_COLOR'};
    if($priority eq 'DEBUG') { return(Term::ANSIColor::color("FAINT")); }
    if($priority eq 'ERROR') { return(Term::ANSIColor::color("BRIGHT_RED")); }
    if($priority eq 'WARN')  { return(Term::ANSIColor::color("BRIGHT_YELLOW")); }
    return("");
}

##############################################
sub _priority_error_warn_only {
    my($layout, $message, $category, $priority) = @_;
    if($priority eq 'ERROR') { return("[".$priority."] "); }
    if($priority eq 'WARN')  { return("[".$priority."] "); }
    return("");
}

##############################################
sub _config {
    return($Thruk::Config::config);
}

##############################################

1;
