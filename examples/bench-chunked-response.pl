#!/usr/bin/env perl

use strict;
use warnings;
use Benchmark ':all';
use Hijk;
use HTTP::Tiny;
use LWP::UserAgent;
use HTTP::Request;
my $req = HTTP::Request->new('GET','http://localhost:5000/');
my $tiny = HTTP::Tiny->new();
my $lwp = LWP::UserAgent->new();

cmpthese(10_000,{
    'lwp____' => sub {
        my $res = $lwp->request($req);
    },
    'tiny___' => sub {
        my $res = $tiny->get('http://localhost:5000/');
    },
    'hijk pp' => sub {
        my $res = Hijk::request({
            path => "/",
            host => 'localhost',
            port => 5000,
            method => 'GET'
        });
    }
});
