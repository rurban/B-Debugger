package B::Debugger;

our $VERSION = '0.01_01';
our $XS_VERSION = $VERSION;
$VERSION = eval $VERSION;

=pod

=head1 NAME

B::Debugger - optree debugger

=head1 SYNOPSIS

  perl -MB::Debugger programm.pl
  B::Debugger 0.01 - optree debugger. h for help
  op 0 enter
  > n
  op 1 nextstate
  > h
  Usage:
  n     next op         d Debug of op
  c <n> continue        F Flags of op
  b <n> break at step   C Concise of op
  l <n> list            sv1,cv1,...
  x ..  execute         [SAHPICG]V<n> inspect n-th global variable
  h     help
  q     quit
  > b 5
  breakpoint 5 added
  > l
  -  <0> enter ->-
  -  <;> nextstate(main 111 test.pl:5) v:{ ->-
  -  <0> pushmark sM ->-  > c
  > q
  quit
  executing...

=head1 DESCRIPTION

  Start an optree inspector before the runtime execution begins, similar to
  the perl debugger, but only at the internal optree level, not the source
  level. Kind of interactive B::Concise.

  The ops are numbered and in exec order, starting from 0.

=head1 OPTIONS

None yet.

Planned:

  -exec      switch exec order
  -skip      skip BEGIN blocks (use modules, ...)
  -check     hook into CHECK block (Default, at B)
  -unit      hook into UNITCHECK block (after B)
  -init      hook into INIT block (before B)

=head1 COMMANDS

  n     goto the next op in current execution order
  n <n> skip over the next n ops
  s     step into kid if not next
  sib   step to next sibling
  c <n> continue. Optionally until op n
  l <x-y> list n ops or from x to y.
  h     help
  q     quit debugger, start execution
  F     list B::Flags op
  C     list B::Concise op
  D     list B::Debug op
  [sahpicg]v<n> inspect n-th global variable. eg. sv1

=head1 AUTHOR

Reini Urban C<rurban@cpan.org>

=cut

use Devel::Hook;
use B qw(main_start class);
use B::Utils qw(carp croak);
use B::Debug;
use B::Flags;
use B::Concise;

use constant DBG_SAME => 1;
use constant DBG_CONT => 2;
use constant DBG_NEXT => 3;
use constant DBG_QUIT => 4;
our ($next_op, %break_op);
my $Debug = 0;

sub debugger_banner {
  print "\nB::Debugger $VERSION - optree debugger. h for help\n";
}
sub debugger_help {
    print "Usage:\n";
    print "n <n> next op         d Debug   op\n";
    print "c <n> continue        F,Flags   op\n";
    print "b <n> break at step   C,Concise op\n";
    print "s     step into kids  l x-y list\n";
    print "sib   goto sibling    [sahpicg]v<n> inspect n-th global variable\n";
    print "u     up              x expr    evaluate expression\n";
    print "q     quit            h     help\n";
# todo: pad vars, sv1
}

sub debugger_prompt {
  my $op = shift;
  print "op $opidx ",$op->name,"\n"; # Todo: more concise
  print "> ";
  my $in = readline(*STDIN);
  chomp $in;
  if ($in =~ /^h|help$/) { debugger_help; return DBG_SAME; }
  elsif ($in =~ /^q|quit$/) { print "quit\nexecuting...\n"; return DBG_QUIT; }
  elsif ($in =~ /^(x|eval)\s+(.+)$/) { print (eval "$2")."\n"; return DBG_SAME; }
  elsif ($in =~ /^(n|next)\s*(.*)$/) {
    $next_op = $2 ? $2 : undef; # next number of steps. really this magic break?
    print "..next_op: $next_op\n" if $Debug;
    return DBG_NEXT;
  }
  elsif ($in =~ /^(b|break)\s*(.+)$/) { # opidx or name?
    # check valid breakpoint? opmax. Na, ignore this.
    if (exists $break_op{$2}) { undef $break_op{$2};
				print "breakpoint $2 removed\n"; }
    else { $break_op{$2} = 1; print "breakpoint $2 added\n"; }
    return DBG_SAME;
  }
  elsif ($in =~ /^(c|cont)\s*(.*)$/) { # arg <opidx> or next matching name?
    if ($2) { $break_op{$2} = 1; }
    return DBG_CONT;
  }
  elsif ($in =~ /^(s|step)$/) {
    if ($op->flags & OPf_KIDS) {
      print "..step into kids: $op->first\n" if $Debug;
      return debugger_walkoptree($op->first, \&debugger_prompt, [ $op->first ])
    } else {
      print "no kids\n";
      return DBG_SAME;
    }
  }
  elsif ($in =~ /^(i|sib)$/) {
    print "..sibling: $op->sibling\n" if $Debug;
    return debugger_walkoptree($op->sibling, \&debugger_prompt, [ $op->sibling ])
  }
  elsif ($in =~ /^(l|list)\s*(.*)/) { # arg <count>, todo: from-to
    my $count = ($2 and ($2 =~ /^\d$/) ? $2 : 10);
    print "list $count\n";
    debugger_walkoptree($op, \&debugger_listop, [ $op, $count+$opidx ] );
    return DBG_SAME;
  }
  elsif ($in =~ /^(d|D|Debug)\s*(.*)$/) { # <count>
    print "debug\n";
    debugger_debugop($op, $2 ? $2 : 1);
    return DBG_SAME;
  }
  elsif ($in =~ /^(F|f|Flags)\s*(.*)$/) { # opidx ignored
    print "op $opidx ",$op->name;
    print "  Flags: ",$op->flagspv,"\n";
    return DBG_SAME;
  }
  elsif ($in =~ /^(o|C|Concise)\s*(.*)$/) { # opidx ignored
    debugger_listop($op,1);
    return DBG_SAME;
  }
  else { print "unknown command \"$in\"\n"; return DBG_SAME; }
}

sub debugger_listop {
  my $op = shift;
  my $until = shift;
  print "..op ".&$pos." ".$op." ".$op->name.", until: $until\n" if $Debug;
  my $style = "#hyphseq2 (*(   (x( ;)x))*)<#classsym> #exname#arg(?([#targarglife])?)"
    . "~#flags(?(/#private)?)(?(:#hints)?)(x(;~->#next)x)\n";
  print B::Concise::concise_op($op, 0, $style);
  return ($opidx >= $until) ? DBG_QUIT : DBG_NEXT;
}

sub debugger_debugop {
  my $op = shift;
  my $until = shift;
  print "..op ".$opidx." ".$op." ".$op->name.", until: $until\n";
  $op->debug;
  return ($opidx >= $until) ? DBG_SAME : DBG_NEXT;
}

our ($file, $line, $opidx) = ("dbg>", 0, 0);
sub debugger_walkoptree {
  my ($op, $callback, $data) = @_;
  print "..walkoptree - op:", $op,", callback:",$callback,", data:",$data,"\n" if $Debug;
  ($file, $line) = ($op->file, $op->line) if $op->isa("B::COP");
  return unless $$op;
  while (($dbg_state = $callback->($op, $data)) == DBG_SAME) {
    print "..walkoptree SAME - op:", $op,"\n" if $Debug;
  }
  print "..walkoptree => $dbg_state\n" if $Debug;
  return if $dbg_state == DBG_QUIT;
  if ($op->flags & OPf_KIDS) {
    print "..walkoptree kids", $$op, $op->flags if $Debug;
    my $kid;
    for ($kid = $op->first; $$kid; $kid = $kid->sibling) {
      print "..walkoptree - $opidx, kid:",$kid,' $kid:',$$kid,"\n" if $Debug;
      $opidx++;
      if ($break_op{$opidx}) {
	print "break at $opidx:\n";
	while (($dbg_state = $callback->($op, $data)) == DBG_SAME) {
	  print "..walkoptree SAME - op:", $op,"\n" if $Debug;
	}
	return if $dbg_state == DBG_QUIT;
      }
      debugger_walkoptree($kid, $callback, [ $kid ])
	unless $dbg_state == DBG_CONT;
    }
  } elsif ($op->next) {
    print "..walkoptree next\n" if $Debug;
    $opidx++;
    if ($break_op{$opidx}) {
      print "break at $opidx:\n";
      while (($dbg_state = $callback->($op, $data)) == DBG_SAME) {
	print "..walkoptree SAME - op:", $op,"\n" if $Debug;
      }
      return if $dbg_state == DBG_QUIT;
    } else {
      debugger_walkoptree($op->next, $callback, [ $op->next ])
	unless $dbg_state == DBG_CONT;
    }
  }
}

# exchange walkop loop with ours to check the walk state?
sub debugger_initloop {
  print "..initloop ".main_start." ".main_start->name."\n" if $Debug;
  debugger_walkoptree(main_start, \&debugger_prompt, [ main_start ]);
}

BEGIN {
  my $dbg_state = DBG_SAME;
  # before B starts
  Devel::Hook->unshift_CHECK_hook( \&debugger_banner );
  # after B is finished
  Devel::Hook->push_CHECK_hook( \&debugger_initloop );
}

#eval {
#    require XSLoader;
#    XSLoader::load('B::Debugger', $XS_VERSION);
#    1;
#}
#or do {
#    require DynaLoader;
#    local @ISA = qw(DynaLoader);
#    bootstrap B::Debugger $XS_VERSION ;
#};
1;
