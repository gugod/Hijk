#!/usr/bin/env perl
use strict;
use warnings;
use Dumbbench;

use Hijk;
use HTTP::Tiny;
use LWP::UserAgent;
use HTTP::Request;

my $url = shift;

my $uri = URI->new($url);
my $tiny = HTTP::Tiny->new();
my $req = HTTP::Request->new('GET',$url);
my $lwp = LWP::UserAgent->new();

my $hijk_req_arg = {
    path => $uri->path,
    host => $uri->host,
    port => $uri->port || 80,
    method => 'GET'
};

my $bench = Dumbbench->new(
  target_rel_precision => 0.005,
  initial_runs         => 1_000,
);

$bench->add_instances(
    Dumbbench::Instance::PerlSub->new(
        name => "hijk",
        code => sub {
            my $res = Hijk::request($hijk_req_arg);
        }
    ),
    Dumbbench::Instance::PerlSub->new(
        name => "httptiny",
        code => sub {
            my $res = $tiny->get($url);
        }
    ),
    Dumbbench::Instance::PerlSub->new(
        name => "lwpua",
        code => sub {
            my $res = $lwp->request($req);
        }
    ),
);

$bench->run;
$bench->report;
