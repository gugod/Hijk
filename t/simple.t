#!/usr/bin/env perl

use strict;
use JSON;
use Tijk;

use Test::More;

my $res = Tijk::get({
    host => "localhost",
    port => "9200",
    path => "/_stats",
});

my $parsed = JSON::decode_json($res);

is ref($parsed), "HASH";

done_testing;
