#  Compiler Pragma
#
use 5.006;
use strict  qw(vars);


#  External Modules
#
use ExtUtils::MakeMaker;


#  Get MakeMaker version - from Test::Simple Makefile.PL
#
my $mm_ver = $ExtUtils::MakeMaker::VERSION;
if ($mm_ver =~ /_/) { # dev version
    $mm_ver = eval $mm_ver;
    die $@ if $@;
}


#  All done, init finished
#
#------------------------------------------------------------------------------


#  Create the Makefile params, save in hash
#
my ($prereq_hr, $version_from_fn);
my %makefile=(

    NAME				    =>  'App::ASPEER::ofx2qif',
    VERSION_FROM			    =>  'bin/ofx2qif.pl',

    PREREQ_PM				    =>	do { $prereq_hr={

        'Finance::OFX::Parse'               =>  0,
        'Finance::QIF'                      =>  0,

       }; ($ENV{'PREREQ_PM'} eq '0') ? {} : $prereq_hr },

    CONFIGURE                               =>  sub { {

	PREREQ_PM			    =>  $prereq_hr

    } },

    EXE_FILES				    =>  [

	'bin/ofx2qif.pl',

       ],


    'dist'				    =>  {

	COMPRESS			    =>  'gzip -9f',
	SUFFIX				    =>  '.gz'

       },

    'depend'				    =>  {

	Makefile			    =>  '$(VERSION_FROM)'

       },

    'macro'				    =>  {

        COPYRIGHT			    =>  'Copyright (C) 2013 Andrew Speer, All rights reserved',
	LICENSE				    =>  'GPL: GNU General Public License',

       },

    ($] <  5.005 ? () : (

        ABSTRACT_FROM			    =>  $version_from_fn,    
        AUTHOR				    =>  'Andrew Speer <andrew@webdyne.org>',
        
    )),

    ($mm_ver < 6.31 ? () : (

        LICENSE                             =>  'gpl',

    )),
    
    ($mm_ver <= 6.45 ? () : (
        
        META_MERGE => { resources => {
            
            homepage                        =>  'http://webdyne.org',
            license                         =>  'http://www.gnu.org/licenses/gpl.html'
            
        }}
    )),

   );


WriteMakefile(%makefile);
