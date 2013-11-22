#!/usr/bin/env perl

use strict;
use Hijk::HTTP::XS;

# use JSON;
use Test::More;
use Socket qw(PF_INET SOCK_STREAM sockaddr_in inet_aton $CRLF);

my %args = (
    method => "GET",
);

my @tests = (
    [ path => "/_stats" ],
    [ path => "/_search", body => q!{"query":{"match_all":{}}}! ],
);


$args{soc} = soc();
eval {
    close($args{soc});
    my $a = {%args, @tests[0]};
    my $res = request($a);
};
like ($@,qr/non-socket/);

$args{soc} = soc();
for my $reset((1,0)) {
    for ((@tests) x (100)) {
        $args{soc} = soc()
            if $reset;
        my $a = {%args, @$_ };
        my $res = request($a);

        my $test_name = "$a->{path}\t". substr($res, 0, 60)."...\n";
        if (substr($res, 0, 1) eq '{' && substr($res, -1, 1) eq '}' ) {
            pass $test_name;
        }
        else {
            fail $test_name;
        }
        close($args{soc})
            if $reset;
    }
}
done_testing();


# helpers
sub request {
    my $args = $_[0];
    syswrite($args{soc}, join(
        $CRLF,
        "GET $args->{path} HTTP/1.1",
        $args->{body} ? ("Content-Length: " . length($args->{body})) : (),
        "",
        $args->{body} ? $args->{body} : ()
    ) . $CRLF);
    my ($status,$body) = Hijk::HTTP::XS::fetch(fileno($args{soc}));
    die "$status: $body"
        unless $status == 200;
    return $body;
}

sub soc {
    my $soc;
    socket($soc, PF_INET, SOCK_STREAM, getprotobyname('tcp')) || die $!;
    connect($soc, sockaddr_in(9200, inet_aton($ENV{TEST_HOST} || "localhost"))) || die $!;
    $soc;
}


