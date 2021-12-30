#!/usr/bin/env perl

# create combined javascript/css files
BEGIN {
    $ENV{'THRUK_MODE'} = 'CLI';

    # do we want compression at all?
    if(-e 'Makefile') {
        chomp(my $compress = `grep THRUKCOMPRESS Makefile | awk '{print \$3}'`);
        $ENV{THRUK_SKIP_COMPRESS} = 1 if $compress eq 'disabled';
    }
};
use warnings;
use strict;

use lib 'lib';

use lib 'plugins/plugins-available/panorama/lib';

use Thruk::Config 'noautoload';

my($dos2unix);
for my $p (reverse split/:/, $ENV{'PATH'}) {
    $dos2unix = $p.'/dos2unix'       if -x $p.'/dos2unix';
    $dos2unix = $p.'/fromdos'        if -x $p.'/fromdos';
}

#################################################
# directly use config, otherwise user would be switched when called as root from the Makefile.PL
my $config   = Thruk::Config::get_base_config();
die('no config') unless $config->{'all_in_one_javascript'};
die('no config') unless $config->{'fileversion'};
my $fileversion = $config->{'fileversion'};
my @themes  = qw/Thruk Thruk2/;

#################################################
# check if update is required
my $newest = 0;
for my $file (@{$config->{'all_in_one_javascript'}}) {
    my @s   = stat('root/thruk/'.$file) or die('root/thruk/'.$file.": ".$!);
    $newest = $s[9] if $newest < $s[9];
}
my $js_required = 1;
if(-e 'root/thruk/cache/thruk-'.$fileversion.'.js') {
    my @s = stat('root/thruk/cache/thruk-'.$fileversion.'.js');
    if($s[9] >= $newest) {
        $js_required = 0;
    }
}

$newest = 0;
# TODO: check
for my $theme (@themes) {
    for my $file (@{$config->{'all_in_one_css_frames'}->{$theme}}) {
        my @s   = stat('themes/themes-available/'.$theme.'/stylesheets/'.$file);
        $newest = $s[9] if $newest < $s[9];
    }
}
my $css_required = 0;
for my $theme (@themes) {
    if(!-e 'root/thruk/cache/'.$theme.'-noframes-'.$fileversion.'.css') {
        $css_required = 1;
    } else {
        my @s = stat('root/thruk/cache/'.$theme.'-noframes-'.$fileversion.'.css');
        if($s[9] < $newest) {
            $css_required = 1;
        }
    }
}

my @panorama_files;
$newest = 0;
require Thruk::Utils::Panorama;
for my $file (@{$config->{'all_in_one_javascript_panorama'}}, @{Thruk::Utils::Panorama::get_static_panorama_files({plugin_path => 'plugins/'})}) {
    my @s;
    if($file =~ m/^plugins\//mx) {
        my $tmp = $file;
        $tmp =~ s|plugins/panorama/|plugins/plugins-available/panorama/root/|gmx;
        @s = stat($tmp);
        push @panorama_files, $tmp;
        -f $tmp || die($tmp.": ".$!);
    } else {
        @s = stat('root/thruk/'.$file);
        push @panorama_files, 'root/thruk/'.$file;
    }
    $newest = $s[9] if (@s && $newest < $s[9]);
}
my $panorama_required   = 1;
my $all_in_one_panorama = 'root/thruk/cache/thruk-panorama-'.$fileversion.'.js';
if(-e $all_in_one_panorama) {
    my @s = stat($all_in_one_panorama);
    if($s[9] >= $newest) {
        $panorama_required = 0;
    }
}

if(!$js_required && !$css_required && !$panorama_required && (!$ARGV[0] or $ARGV[0] ne '-f')) {
    print STDERR "no update necessary\n";
    exit;
}
mkdir('root/thruk/cache');

#################################################
my $cmds = [
    'rm -f cache/*',
    'cd root/thruk/ && cat '.join(' ', @{$config->{'all_in_one_javascript'}}).' > cache/thruk-'.$fileversion.'.js',
    'cat '.join(' ', @panorama_files).' > '.$all_in_one_panorama,
];
for my $theme (@themes) {
    push @{$cmds},
        'cd themes/themes-available/'.$theme.'/stylesheets/  && cat '.join(' ', @{$config->{'all_in_one_css_noframes'}->{$theme}}).' > ../../../../root/thruk/cache/'.$theme.'-noframes-'.$fileversion.'.css';
    push @{$cmds},
        'cd themes/themes-available/'.$theme.'/stylesheets/  && cat '.join(' ', @{$config->{'all_in_one_css_frames'}->{$theme}}).' > ../../../../root/thruk/cache/'.$theme.'-'.$fileversion.'.css';
    push @{$cmds},
        'sed -e "s/\((\'\?\"\?\)\.\.\/\(images\|fonts\)\//\1..\/themes\/'.$theme.'\/\2\//g"'
          .' -e "s/\((\'\?\"\?\)\.\.\/\.\.\/\.\.\/images\//\1..\/images\//g"'
          .' -i root/thruk/cache/'.$theme.'-*.css',
}
if($dos2unix) {
    push @{$cmds}, 'cd root/thruk/cache && '.$dos2unix.' thruk-'.$fileversion.'.js';
    push @{$cmds}, $dos2unix.' '.$all_in_one_panorama;
}
for my $cmd (@{$cmds}) {
    print `$cmd`;
    exit 1 if $? != 0;
}

exit 0;
