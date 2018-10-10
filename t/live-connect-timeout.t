#!/usr/bin/env perl
use strict;
use warnings;
use Test::More;

use Net::Ping;
use Hijk;

unless ($ENV{TEST_LIVE}) {
    plan skip_all => "Enable live testing by setting env: TEST_LIVE=1";
}

# find a ip and confirm it is not reachable.
my $pinger = Net::Ping->new("tcp", 2);
$pinger->port_number(80);

my $ip;
my $iter = 10;
do {
    $ip = join ".", 172, (int(rand()*15+16)), int(rand()*250+1),  int(rand()*255+1);
} while($iter-- > 0 && $pinger->ping($ip));

if ($iter == 0) {
    plan skip_all => "Cannot randomly generate an unreachable IP."
}

pass "ip generated = $ip";

my ($res, $exception);

eval {
    $res = Hijk::request({
        host => $ip,
        port => 80,
        timeout => 1 # seconds
    });
    1;
}
or do {
    $exception = $@ || "unknown error.";
    $exception =~ s/\n//g;
};

if ($exception) {
    pass "On $^O, we have exception trying to connect to an unreachable IP: $exception";
    is(scalar(keys %{$Hijk::SOCKET_CACHE}), 0, "We have nothing in the socket cache after the connect exception.");
} else {
    ok exists $res->{error}, "On $^O, ".'$res->{error} exists because we expect error to happen.';
    is $res->{error}, Hijk::Error::CONNECT_TIMEOUT, '$res->{error} contiain the value of Hijk::Error::CONNECT_TIMEOUT, indicating that it timed-out when establishing connection';
    is(scalar(keys %{$Hijk::SOCKET_CACHE}), 0, "We have nothing in the socket cache after a timeout");
}

done_testing;
