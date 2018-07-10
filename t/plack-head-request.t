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
    $runner->parse_options("--server", "HTTP::Server::Simple", "--port", $port, "$FindBin::Bin/bin/head-request.psgi");
    $runner->run;
    exit;
}

sleep 2; # hopfully this is enough to launch that psgi.

my %args = (
    timeout => 1,
    host    => "localhost",
    port    => $port,
    method  => "HEAD",
);

subtest "expect HEAD response with a Content-Length" => sub {
    my $res = Hijk::request({%args, query_string => "gimme_content_length=1"});
    ok !exists $res->{error}, '$res->{error} should not exist because this request should have been successful';
    ok defined($res->{head}->{"Content-Length"}), "Got a Content-Length";

    cmp_ok $res->{body}, "eq", "", "Got no body even though we had a Content-Length header";

    if ($res->{head}->{"Content-Length"} == 0) {
        pass 'Content-Length: 0, looks OK because this response has no http body';
    } elsif ($res->{head}->{"Content-Length"} == 11) {
        pass 'Content-Length: 11, looks OK because it is the length of body should this be a GET request';
    } else {
        fail "Content-Length: " . $res->{head}->{'Content-Length'} . ' does not look like a legit value.';
    }
};

subtest "expect HEAD response without a Content-Length" => sub {
    my $res = Hijk::request({%args, query_string => "gimme_content_length="});
    ok !exists $res->{error}, '$res->{error} should not exist because this request should have been successful';
    ok !exists $res->{head}->{"Content-Length"}, "We should get no Content-Length";
    cmp_ok $res->{body}, "eq", "", "Got no body wit the HEAD response, also have no Content-Length";
};

END { kill INT => $pid if $pid }

done_testing;
