use warnings;
use strict;
use Test::More;

use Thruk::Utils::IO ();

plan skip_all => 'Author test. Set $ENV{TEST_AUTHOR} to a true value to run.' unless $ENV{TEST_AUTHOR};

open(my $ph, '-|', 'bash -c "find ./script ./lib ./plugins/plugins-available/*/lib -type f" 2>&1') or die('find failed: '.$!);
while(<$ph>) {
    my $line = $_;
    chomp($line);
    check_private_subs($line);
}
close($ph);
done_testing();


sub check_private_subs {
    my($file) = @_;
    my $now = time();

    return if $file =~ m|/lib/Monitoring/|mx;
    return if $file =~ m|script/phantomjs|mx;

    ok($file, $file);
    my $content = Thruk::Utils::IO::read($file);
    $content =~ s/^=head.*?^=cut//smgx;
    my $nr = 0;
    for my $line (split/\n/mx, $content) {
        $nr++;
        chomp($line);
        my $test = $line;
        $test =~ s/"[^"]*?"//gmx;
        $test =~ s/'[^']*?'//gmx;
        $test =~ s/\#.*//gmx;
        $test =~ s/Devel::Cycle::_//gmx;
        if($test =~ m/::_/mx) {
            fail("private sub used in ".$file.":$nr ".$line);
        }
    }
    return;
}
