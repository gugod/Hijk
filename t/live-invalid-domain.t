#!/usr/bin/env perl

use strict;
use warnings;
use Hijk;
use Test::More;

unless ($ENV{TEST_LIVE}) {
    plan skip_all => "Enable live testing by setting env: TEST_LIVE=1";
}

my $res = Hijk::request({
    method => "GET",
    host   => "hlagh.google.com",
    port   => "80",
});
ok exists $res->{error}, "We got an error back for this invalid domain";
is $res->{error}, Hijk::Error::CANNOT_RESOLVE, "We can't resolve the domain";

done_testing;
