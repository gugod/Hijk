#!/usr/bin/env perl

use strict;
use warnings;
use Hijk;
use Test::More;
use Test::Exception;

unless ($ENV{TEST_LIVE}) {
    plan skip_all => "Enable live testing by setting env: TEST_LIVE=1";
}

if($ENV{http_proxy}) {
    plan skip_all => "http_proxy is set. We cannot test when proxy is required to visit u.nix.is";
}

for my $i (1..1000) {
    lives_ok {
        my $res = Hijk::request({
            host            => 'u.nix.is',
            port            => 80,
            connect_timeout => 3,
            read_timeout    => 3,
            path            => "/?Hijk_test_nr=$i",
            head   => [
                "X-Request-Nr" => $i,
                "Referer" => "Hijk (file:" . __FILE__ . "; iteration: $i)",
            ],

        });

        ok !exists($res->{error}), '$res->{error} does not exist, because we do not expect connect timeout to happen';
        cmp_ok $res->{status}, '==', 200, "We got a 200 OK response";
        if (exists $res->{head}->{Connection} and $res->{head}->{Connection} eq 'close') {
            cmp_ok scalar(keys %{$Hijk::SOCKET_CACHE}), '==', 0, "We were told to close the connection. We should have no entry in the socket cache";
        } else {
            cmp_ok scalar(keys %{$Hijk::SOCKET_CACHE}), '==', 1, "We have an entry in the global socket cache";
        }
    } "We could make request number $i";
}

done_testing;
