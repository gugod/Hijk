#!/usr/bin/env perl
use strict;
use warnings;
use Test::More;

use Hijk;
use URI;
use Time::HiRes 'time';

plan skip_all => "Enable live testing by setting env: TEST_LIVE=1" unless $ENV{TEST_LIVE};
plan skip_all => "Enable live CouchDB testing by setting env: TEST_COUCHDB=http://localhost:5984/" unless $ENV{TEST_COUCHDB};

my $uri = URI->new($ENV{TEST_COUCHDB});

plan skip_all => "Fail to parse the value of TEST_COUCHDB: $ENV{TEST_COUCHDB}" unless $uri->isa("URI::http");

subtest "get the welcome message" => sub {
    my $rd = { host => $uri->host,  port => $uri->port };
    my $res;

    my $t0 = time;
    my $count = my $total = 1000;
    my $ok = 0;
    while ($count--) {
        $res = Hijk::request($rd);
        $ok++ if $res->{status} eq '200';
    }
    my $t1 = time;

    is $ok, $total, sprintf("spent %f s", $t1 - $t0);
};

subtest "create database, then delete it." => sub {
    my $db_name = "hijk_test_$$";
    my $rd = {
        host   => $uri->host,
        port   => $uri->port,
        path   => "/${db_name}",
        method => "PUT",
    };

    my $res = Hijk::request($rd);

    if ($res->{status} eq '412') {
        pass "db $db_name already exists (unexpected, but it is fine): $res->{body}";
    } else {
        pass "db $db_name created";
        is $res->{status}, '201', "status = 201. see http://docs.couchdb.org/en/latest/intro/api.html#databases";
        
        my $res2 = Hijk::request($rd);
        if ($res2->{status} eq '412') {
            pass "The 2nd creation request is done with error (expected): $res->{body}";
        } else {
            fail "The 2nd request is done without error, that is unexpected. http_status = $res2->{status}, $res2->{body}";
        }
    }

    $rd->{method} = "GET";
    $res = Hijk::request($rd);
    is $res->{status}, '200', "$db_name exists. res_body = $res->{body}";

    $rd->{method} = "DELETE";
    $res = Hijk::request($rd);
    is $res->{status}, '200', "$db_name is deleted. res_body = $res->{body}";
};

done_testing;
