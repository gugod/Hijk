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
    require Plack::Runner;
    my $runner = Plack::Runner->new;
    $runner->parse_options("--port", $port, "$FindBin::Bin/bin/head-request.psgi");
    $runner->run;
    exit;
}

sleep 10; # hopfully this is enough to launch that psgi.

my %args = (
    timeout => 1,
    host    => "localhost",
    port    => $port,
    method  => "HEAD",
);

subtest "expect HEAD response with a Content-Length" => sub {
    my $res = Hijk::request({%args, query_string => "gimme_content_length=1"});
    ok !exists $res->{error}, '$res->{error} should not exist because this request should have been successful';
    cmp_ok $res->{head}->{"Content-Length"}, "==", 11, "Got a Content-Length";
    cmp_ok $res->{body}, "eq", "", "Got no body even though we had a Content-Length";
};

subtest "expect HEAD response without a Content-Length" => sub {
    my $res = Hijk::request({%args, query_string => "gimme_content_length="});
    ok !exists $res->{error}, '$res->{error} should not exist because this request should have been successful';
    TODO: {
        local $TODO = "I can't figure out how to get plackup(1) not to implicitly add Content-Length";
        ok !exists $res->{head}->{"Content-Length"}, "We should get no Content-Length";
    }
    cmp_ok $res->{body}, "eq", "", "Got no body wit the HEAD response, also have no Content-Length";
};

END { kill INT => $pid if $pid }

done_testing;
