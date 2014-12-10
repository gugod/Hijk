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

if($ENV{http_proxy}) {
    plan skip_all => "http_proxy is set. We cannot test when proxy is required to visit google.com";
}

my %args = (
    host => "google.com",
    port => "80",
    method => "GET",
);

subtest "timeout and cache" => sub {
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
        cmp_ok $res->{body}, "ne", "", "We a body with a GET requests";
    } "We could make the request";

    lives_ok {
        my %socket_cache;
        my $res = Hijk::request({
            method => "HEAD",
            host => 'google.com',
            port => 80,
            timeout => 0,
            socket_cache => undef,
        });

        ok !exists($res->{error}), '$res->{error} does not exist, because we do not expect connect timeout to happen';
        cmp_ok scalar(keys %{$Hijk::SOCKET_CACHE}), '==', 0, "We have nothing in the global socket cache";
        cmp_ok $res->{body}, "eq", "", "We have no body from HEAD requests";
    } "We could make the request";
};

subtest "with 1ms timeout limit, expect an exception." => sub {
    lives_ok {
        my $res = Hijk::request({%args, timeout => 0.001});

        ok exists $res->{error};
        is $res->{error}, Hijk::Error::CONNECT_TIMEOUT;
    };
};

subtest "with 10s timeout limit, do not expect an exception." => sub {
    lives_ok {
        my $res = Hijk::request({%args, timeout => 10});
        diag substr($res->{body}, 0, 80);
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
