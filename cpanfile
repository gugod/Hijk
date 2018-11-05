requires "Time::HiRes";

on configure => sub {
   requires "Module::Build::Tiny";
};

on test => sub {
    requires "Test::More";
    requires "Test::Exception";
    requires "Plack";
    requires "HTTP::Server::Simple::PSGI";
    requires "Net::Ping", '2.41';
    requires 'Net::Server::HTTP';
};
