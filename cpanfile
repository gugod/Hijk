requires "Time::HiRes";

on configure => sub {
   requires "Module::Build::Tiny";
};

on test => sub {
    requires "Test::More";
    requires "Test::Exception";
    requires "Plack";
    requires "Net::Ping", '2.41';
};
