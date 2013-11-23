#!/usr/bin/env perl

use strict;
use Hijk;

use Test::More;

my %args = (
    host => $ENV{TEST_HOST} || "localhost",
    port => $ENV{TEST_PORT} || "80",
    method => "GET",
    path => "/",
);

my $res = Hijk::request(\%args);

ok exists($res->{status} ), "status code = $res->{status}";
ok exists( $res->{body} ), "body = " . substr($res->{body}, 0, 50);


done_testing;
