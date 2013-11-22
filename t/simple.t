#!/usr/bin/env perl

use strict;
use Hijk;

# use JSON;
use Test::More;

my %args = (
    host => $ENV{TEST_HOST} || "localhost",
    port => "9200",
    method => "GET",
);

my @tests = (
    [ path => "/_stats" ],
    [ path => "/_search", body => q!{"query":{"match_all":{}}}! ],
);

for ((@tests) x (300)) {
    my $a = {%args, @$_ };
    my $res = Hijk::request($a);

    my $test_name = "$a->{path}\t". substr($res, 0, 60)."...\n";
    if (substr($res, 0, 1) eq '{' && substr($res, -1, 1) eq '}' ) {
        pass $test_name;
    }
    else {
        fail $test_name;
    }
}

done_testing;
