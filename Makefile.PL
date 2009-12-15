use ExtUtils::MakeMaker;

WriteMakefile
  (
   NAME	            => "B::Debugger",
   VERSION_FROM     => "Debugger.pm",
   PREREQ_PM 	    => {
			'Devel::Hook' => 0,
			'B::Concise' => '0.66',
			'B::Flags'   => '0.02',
			'B::Utils'   => '0.05',
			'B' 	     => '1.09',
		       },
    SIGN  => 1,
   ($ExtUtils::MakeMaker::VERSION gt '6.30'?
    ('LICENSE'                => 'perl', ) : ()),
   ($] >= 5.005 ?
    ('AUTHOR' => 'Reini Urban <rurban@cpan.org>',
     'ABSTRACT_FROM' => 'Debugger.pm') : ()),
  );

#sub MY::depend { "\nDebugger.c : Debugger.xs Makefile\n"; }
