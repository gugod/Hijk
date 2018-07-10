#!/usr/bin/env perl

use strict;
use warnings;

use Hijk;
use Test::More;

if ($ENV{TRAVIS} && $ENV{TRAVIS_OS_NAME} eq 'osx') {
    plan skip_all => "No elasticsearch service in this environment at the moment.";
}

unless ($ENV{TEST_LIVE}) {
    plan skip_all => "Enable live testing by setting env: TEST_LIVE=1";
}

unless ($ENV{TEST_ELASTICSEARCH}) {
    plan skip_all => "Enable live ElasticSearch testing by setting env: TEST_ELASTICSEARCH=1";
}

my %args = (
    host => $ENV{TEST_HOST} || "localhost",
    port => "9200",
    method => "GET",
);

my @tests = (
    [ path => "/_stats" ],
    [ path => "/_search", body => q!{"query":{"match_all":{}}}! ],
    [ path => "/_search", query_string => "search_type=count", body => q!{"query":{"match_all":{}}}! ],
);

for ((@tests) x (300)) {

    my $a = {%args, @$_ };
    my $res = Hijk::request($a);
    if ($res->{error}) {
        fail "Error happened when requesting $a->{path}: $res->{error}";
    }
    else {
        my $res_body = $res->{body};
        my $test_name = "$a->{path}\t". substr($res_body, 0, 60)."...\n";
        if (substr($res_body, 0, 1) eq '{' && substr($res_body, -1, 1) eq '}' ) {
            pass $test_name;
        }
        else {
            fail $test_name;
        }
    }
}

done_testing;
