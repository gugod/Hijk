#!/usr/bin/env perl
use strict;
use Time::HiRes qw(sleep time);
use Plack::Request;
sub {
    my $env = shift;
    my $start_time = time;
    my $req = Plack::Request->new($env);
    my ($t) = $env->{QUERY_STRING} =~ m/\At=([0-9\.]+)\z/;
    $t ||= 1;
    sleep $t;
    return [200, [], [$start_time, ",", time]];
}
__END__
curl 'http://localhost:5000?t=2.5'
curl 'http://localhost:5000?t=17'
