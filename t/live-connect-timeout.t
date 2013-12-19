#!/usr/bin/env perl
use strict;
use warnings;
use Test::More;
use Test::Exception;

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

lives_ok {
    my $res = Hijk::request({
        host => $ip,
        port => 80,
        timeout => 1            # seconds
    });

    ok exists $res->{error}, '$res->{error} exists because we expect error to happen.';
    is $res->{error}, Hijk::Error::CONNECT_TIMEOUT, '$res->{error} contiain the value of Hijk::Error::CONNECT_TIMEOUT, indicating that it timed-out when establishing connection';
} "We could make the request";
is(scalar(keys %{$Hijk::SOCKET_CACHE}), 0, "We have nothing in the socket cache after a timeout");

lives_ok {
    my $res = Hijk::request({
        host => 'google.com',
        port => 80,
        timeout => 0
    });

    ok !exists($res->{error}), '$res->{error} does not exist, because we do not expect connect timeout to happen';
    cmp_ok scalar(keys %{$Hijk::SOCKET_CACHE}), '==', 1, "We have an entry in the global socket cache";
    %{$Hijk::SOCKET_CACHE} = ();
} "We could make the request";

lives_ok {
    my %socket_cache;
    my $res = Hijk::request({
        host => 'google.com',
        port => 80,
        timeout => 0,
        socket_cache => \%socket_cache,
    });

    ok !exists($res->{error}), '$res->{error} does not exist, because we do not expect connect timeout to happen';
    cmp_ok scalar(keys %{$Hijk::SOCKET_CACHE}), '==', 0, "We have nothing in the global socket cache...";
    cmp_ok scalar(keys %socket_cache), '==', 1, "...because we used our own cache";
} "We could make the request";

lives_ok {
    my %socket_cache;
    my $res = Hijk::request({
        host => 'google.com',
        port => 80,
        timeout => 0,
        socket_cache => undef,
    });

    ok !exists($res->{error}), '$res->{error} does not exist, because we do not expect connect timeout to happen';
    cmp_ok scalar(keys %{$Hijk::SOCKET_CACHE}), '==', 0, "We have nothing in the global socket cache";
} "We could make the request";

done_testing;

