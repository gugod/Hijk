use inc::Module::Install;
license('mit');
author('Kang-min Liu & Borislav Nikolov');
repository('https://github.com/gugod/Hijk');
all_from("lib/Hijk.pm");
cpanfile();
makemaker_args( NORECURS => 1 );
WriteAll();
