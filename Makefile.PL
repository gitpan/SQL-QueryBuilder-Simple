
require 5.006;

use ExtUtils::MakeMaker;

WriteMakefile(
    'NAME'		=> 'SQL::QueryBuilder::Simple',
    'VERSION_FROM'	=> 'Simple.pm',
    'PREREQ_PM'		=> {
      'warnings::register' => 0,
    },
    ($] >= 5.005 ?    ## Add these new keywords supported since 5.005
      (ABSTRACT   => 'Generate simple SQL queries',
       AUTHOR     => 'Robert Rothenberg <rrwo@cpan.org>') : ()),
);
