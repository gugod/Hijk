#!/usr/bin/env perl

use strict;
use JSON;
use Tijk;

use Test::More;

my %args = (
    host => "localhost",
    port => "9200",
);

my @tests = (
    [ path => "/_stats" ],
    [ path => "/_search", body => q!{"query":{"match_all":{}}}! ],
);

for (@tests) {
    my $a = {%args, @$_};
    my $res = Tijk::get($a);
    my $parsed = JSON::decode_json($res);
    is ref($parsed), "HASH", "$a->{path}\t". substr($res, 0, 60)."...";
}


done_testing;
