#!/usr/bin/env perl
use strict;
use warnings;
use Test::More;
use Test::Exception;

use Net::Ping;
use Hijk;

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

throws_ok {
    my $res = Hijk::request({
        ($ENV{HIJK_XS} ? (fetch => do { require Hijk::HTTP::XS; \&Hijk::HTTP::XS::fetch; }) : ()),
        host => $ip,
        port => 80,
        timeout => 1            # seconds
    });
} qr/CONNECT\s*TIMEOUT/i;

done_testing;

