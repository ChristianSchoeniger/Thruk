use warnings;
use strict;
use Test::More 0.96;

use Thruk::Config 'noautoload';
use Thruk::Utils::IO ();

BEGIN {
  plan skip_all => 'local test only' if defined $ENV{'PLACK_TEST_EXTERNALSERVER_URI'};
  plan skip_all => 'Author test. Set $ENV{TEST_AUTHOR} to a true value to run.' unless $ENV{TEST_AUTHOR};
}

BEGIN {
    use lib('t');
    require TestUtils;
    import TestUtils;
}

my $BIN = defined $ENV{'THRUK_BIN'} ? $ENV{'THRUK_BIN'} : './script/thruk';
$BIN    = $BIN.' --local';

my $plugins = [
    { name => 'editor' },
    { name => 'omd' },
    { name => 'pansnaps' },
    { name => 'status-dashboard' },
    { name => 'woshsh' },
];
my $filter = $ARGV[0];
my $extra_tests = [
  't/083-xss.t',
  't/088-remove_after.t',
  't/092-todo.t',
  't/094-template_encoding.t',
  't/900-javascript_syntax.t',
];

TestUtils::test_command({
    cmd     => $BIN.' plugin search report -f',
    like    => ['/reports2/'],
    exit    => 0,
});

for my $p (@{$plugins}) {
    next if($filter && $p->{'name'} ne $filter);

    # install plugin or use existing if core plugin
    my $use_existing = 0;
    if(-e 'plugins/plugins-available/'.$p->{'name'}) {
      $use_existing = 1;
    } else {
      TestUtils::test_command({
          cmd     => $BIN.' plugin install '.$p->{'name'},
          like    => ['/Installed/',
                      '/successfully/'
                    ],
          exit    => 0,
      });
    }

    # enable additional test config
    if(-e 'plugins/plugins-available/'.$p->{'name'}.'/t/data/'.$p->{'name'}.'.conf') {
      mkdir('thruk_local.d');
      symlink('../plugins/plugins-available/'.$p->{'name'}.'/t/data/'.$p->{'name'}.'.conf', 'thruk_local.d/test-'.$p->{'name'}.'.conf');
    }

    # run plugin test files
    TestUtils::clear();
    for my $testfile (glob("plugins/plugins-available/".$p->{'name'}."/t/*.t"), @{$extra_tests}) {
        my $testsource = Thruk::Utils::IO::read($testfile);
        Thruk::Config::set_config_env();
        subtest $testfile => sub {
            # required for ex.: t/092-todo.t
            local @ARGV = (sprintf("plugins/plugins-available/%s", $p->{'name'}));
            $testsource =~ s/^\Quse warnings;\E//gmx;
            no warnings qw(redefine);
            eval("#line 1 $testfile\n".$testsource);
        };
    }

    # remove additional test config again
    if(-e 'plugins/plugins-available/'.$p->{'name'}.'/t/data/'.$p->{'name'}.'.conf') {
      unlink('thruk_local.d/test-'.$p->{'name'}.'.conf');
    }

    # uninstall plugin
    if(!$use_existing) {
      TestUtils::test_command({
          cmd     => $BIN.' plugin remove '.$p->{'name'},
          like    => ['/Removed plugin/',
                      '/successfully/'
                    ],
          exit    => 0,
      });
    }
}

done_testing();
