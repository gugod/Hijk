#!/usr/bin/env perl

use strict;
use warnings;
use Hijk;
use Time::HiRes ();

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

subtest "with 1ms timeout limit, expect an exception." => sub {
    lives_ok {
        my $res = Hijk::request({%args, timeout => 0.001});

        ok exists $res->{error};
        is $res->{error}, Hijk::Error::CONNECT_TIMEOUT;
    };
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

subtest "Test the on_connect callback" => sub {
    lives_ok {
        my $connect_time = -Time::HiRes::time();
        my $read_time;
        my $res = Hijk::request({
            %args,
            timeout => 10,
            socket_cache => undef,
            on_connect => sub {
                $connect_time += Time::HiRes::time();
                $read_time = -Time::HiRes::time();
                return;
            },
        });
        $read_time += Time::HiRes::time();
        ok($connect_time, "Managed to connect in $connect_time");
        ok($read_time, "Managed to read in $read_time");
    };
};

done_testing;
