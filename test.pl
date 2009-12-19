#!perl
use blib;
use B::Debugger(@_);

BEGIN { print "1..3\n";
	print "# enter c to finish the test"; }
for (1,2,3) { print "ok $_\n" if /\d/ }
