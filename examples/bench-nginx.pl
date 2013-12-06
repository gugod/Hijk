#!/usr/bin/env perl
use strict;
use warnings;
use Benchmark ':all';
use Hijk;
use Hijk::HTTP::XS;
use HTTP::Tiny;
use LWP::UserAgent;
use HTTP::Request;


#                  Rate 1k.img lwp____ 1k.img tiny___ 1k.img hijk pp 1k.img hijk xs
#1k.img lwp____   820/s             --           -54%           -94%           -95%
#1k.img tiny___  1776/s           117%             --           -86%           -90%
#1k.img hijk pp 12821/s          1464%           622%             --           -29%
#1k.img hijk xs 18182/s          2118%           924%            42%             --

#                   Rate 10k.img lwp____ 10k.img tiny___ 10k.img hijk pp 10k.img hijk xs
#10k.img lwp____   781/s              --            -54%            -93%            -95%
#10k.img tiny___  1692/s            117%              --            -85%            -89%
#10k.img hijk pp 11364/s           1355%            572%              --            -27%
#10k.img hijk xs 15625/s           1900%            823%             37%              --

#                   Rate 100k.img lwp____ 100k.img tiny___ 100k.img hijk pp 100k.img hijk xs
#100k.img lwp____  452/s               --             -62%             -93%             -95%
#100k.img tiny___ 1179/s             161%               --             -83%             -86%
#100k.img hijk pp 6944/s            1436%             489%               --             -16%
#100k.img hijk xs 8264/s            1728%             601%              19%               --

foreach my $f(qw(1k.img 10k.img 100k.img)) {
    my $tiny = HTTP::Tiny->new();
    my $req = HTTP::Request->new('GET',"http://localhost:8080/$f");
    my $lwp = LWP::UserAgent->new();
    cmpthese(10_000,{
        $f. ' tiny___' => sub {
            my $res = $tiny->get("http://localhost:8080/$f");
        },
        $f . ' hijk xs' => sub {
            my $res = Hijk::request({path => "/$f",
                                     host => 'localhost',
                                     port => 8080,
                                     fetch => \&Hijk::HTTP::XS::fetch,
                                     method => 'GET'});
        },
        $f . ' hijk pp' => sub {
            my $res = Hijk::request({path => "/$f",
                                     host => 'localhost',
                                     port => 8080,
                                     method => 'GET'});
        },
        $f . ' lwp____' => sub {
            my $res = $lwp->request($req);
        },
    });
}
