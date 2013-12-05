use v5.14.2;
use ExtUtils::MakeMaker;
# See lib/ExtUtils/MakeMaker.pm for details of how to influence
# the contents of the Makefile that is written.
WriteMakefile(
    NAME              => 'Hijk::HTTP::XS',
    VERSION_FROM      => 'lib/Hijk/HTTP/XS.pm', # finds $VERSION
    PREREQ_PM         => { }, # e.g., Module::Name => 1.1
    ABSTRACT_FROM  => 'lib/Hijk/HTTP/XS.pm',
    AUTHOR         => 'Borislav Nikolov & Kang-min Liu',
    LIBS              => [''], # e.g., '-lm'
    DEFINE            => '', # e.g., '-DHAVE_SOMETHING'
    INC               => '-I.', # e.g., '-I. -I/usr/include/other'
	# Un-comment this if you add C files to link with later:
    OBJECT            => '$(O_FILES)', # link all the C files too
);
