#!/usr/bin/env perl

use strict;
use Hijk;

use Test::More;
use Test::Exception;

unless ($ENV{TEST_LIVE}) {
    plan skip_all => "Enable live testing by setting env: TEST_LIVE=1";
}

my %args = (
    ($ENV{HIJK_XS} ? (fetch => do { require Hijk::HTTP::XS; \&Hijk::HTTP::XS::fetch; }) : ()),
    host => "google.com",
    port => "80",
    method => "GET",
);

subtest "with 1ms timeout limit, expect an exception." => sub {
    throws_ok {
        my $res = Hijk::request({%args, timeout => 0.001});
    } qr/timeout/i;
};

subtest "with 1s timeout limit, do not expect an exception." => sub {
    lives_ok {
        my $res = Hijk::request({%args, timeout => 10});
    } 'google.com send back something within 10s';
};

subtest "without timeout, do not expect an exception." => sub {
    lives_ok {
        my $res = Hijk::request({%args, timeout => 0});
    } 'google.com send back something without timeout';
};

done_testing;
