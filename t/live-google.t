#!/usr/bin/env perl

use strict;
use Hijk;

use Test::More;
use Test::Exception;

unless ($ENV{TEST_LIVE}) {
    plan skip_all => "Enable live testing by setting env: TEST_LIVE=1";
}

my %args = (
    host => "google.com",
    port => "80",
    method => "GET",
);

subtest "expect timeout" => sub {
    throws_ok {
        my $res = Hijk::request({%args, timeout => 1});
    } qr/timeout/i;
};

subtest "do not expect timeout" => sub {
    lives_ok {
        my $res = Hijk::request({%args, timeout => 10_000});
    } 'google.com send back something within 10s';
};


done_testing;
