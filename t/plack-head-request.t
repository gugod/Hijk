#!/usr/bin/env perl

use strict;
use warnings;
use FindBin;

use Hijk;
use Test::More;

my $port = 10000 + int rand(5000);

my $pid = fork;
die "Fail to fork then start a plack server" unless defined $pid;

if ($pid == 0) {
    exec($^X, "t/bin/nsh-head-request.pl", $port);
}

sleep 2; # hopfully this is enough to launch that daemon.

my %args = (
    timeout => 1,
    host    => "localhost",
    port    => $port,
    method  => "HEAD",
);

subtest "expect HEAD response with a Content-Length" => sub {
    my $res = Hijk::request({%args, query_string => "gimme_content_length=1"});
    ok !exists $res->{error}, '$res->{error} should not exist because this request should have been successful';
    ok defined($res->{head}->{"Content-length"}), "Got a Content-Length";

    cmp_ok $res->{body}, "eq", "", "Got no body even though we had a Content-Length header";

    if ($res->{head}->{"Content-length"} == 0) {
        pass 'Content-Length: 0, looks OK because this response has no http body';
    } elsif ($res->{head}->{"Content-length"} == 11) {
        pass 'Content-Length: 11, looks OK because it is the length of body should this be a GET request';
    } else {
        fail "Content-Length: " . $res->{head}->{'Content-length'} . ' does not look like a legit value.';
    }
};

subtest "expect HEAD response without a Content-Length" => sub {
    my $res = Hijk::request({%args, query_string => "gimme_content_length="});
    ok !exists $res->{error}, '$res->{error} should not exist because this request should have been successful';
    ok !exists $res->{head}->{"Content-length"}, "We should get no Content-Length";
    cmp_ok $res->{body}, "eq", "", "Got no body wit the HEAD response, also have no Content-Length";
};

END { kill INT => $pid if $pid }

done_testing;
