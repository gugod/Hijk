
use strict;

use Hijk::DEBUG;
use Hijk;

use Data::Dumper;

# use B::Deparse;
# my $deparse = B::Deparse->new("-p", "-sC");
# print $deparse->coderef2text(\&Hijk::request);

my $res = Hijk::request({
    host => "localhost",
    port => "9200",
    path => "/"
});

print Data::Dumper::Dumper($res);
