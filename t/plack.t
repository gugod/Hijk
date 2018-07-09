#!/usr/bin/env perl

use strict;
use warnings;
use FindBin;

use Hijk;

use Test::More;
use Test::Exception;

my $port = 10000 + int rand(5000);

my $pid = fork;
die "Fail to fork then start a plack server" unless defined $pid;

if ($pid == 0) {
    require Plack::Runner;
    my $runner = Plack::Runner->new;
    $runner->parse_options("--port", $port, "$FindBin::Bin/bin/it-takes-time.psgi");
    $runner->run;
    exit;
}

sleep 10; # hopfully this is enough to launch that psgi.

my %args = (
    host => "localhost",
    port => $port,
    query_string => "t=5",
    method => "GET",
);

subtest "expect connection failure (mismatching port number)" => sub {
    dies_ok {
        my $port_wrong = $port;
        while ($port_wrong == $port) {
            $port_wrong = int( 15001+rand()*3000 );
        }
        diag "Connecting to a wrong port: $port";
        my $res = Hijk::request({%args, port => $port_wrong, timeout => 10});
    } 'We connect to wrong port so, as expected, the connection cannot be established.';
    diag "Dying message: $@";
};

subtest "expect read timeout" => sub {
    lives_ok {
        my $res = Hijk::request({%args, timeout => 1});
        ok exists $res->{error}, '$res->{error} should exist becasue a read timeout is expected.';
        is $res->{error}, Hijk::Error::READ_TIMEOUT, '$res->{error} == Hijk::Error::READ_TIMEOUT';
    };
};

subtest "do not expect timeout" => sub {
    lives_ok {
        my $res = Hijk::request({%args, timeout => 10});
    } 'local plack send back something within 10s';
};

END { kill INT => $pid if $pid }

done_testing;
