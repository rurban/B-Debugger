package Od;

our $VERSION = '0.01_01';

use B qw(main_root walkoptree_slow minus_c save_BEGINs);
use Carp;

package Od::Tree;
# Store the links to all other ops

sub add{
};

sub sibling {
  $_[0]->parent   = $_[1];
  $_[0]->sibling  = $_[2];
};

sub sibvisit {
    my ($parent, $child) = @_;
    while ($child->can("sibling") and ${$child->sibling}) {
        $child = $child->sibling;
        $t->sibling($parent, $child);
    }
}

package Od;

sub B::LISTOP::visit {
    my $self = shift;
    #$t->add({name => $$self, label => $self->name});
    my $node = $self->first;
    $g->next($self->next);
    sibvisit($self, $node);
}

sub B::BINOP::visit {
    my $self = shift;
    my $first = $self->first;
    my $last = $self->last;
    $g->add_node({name => $$self, label => $self->name});
    $g->add_edge({from => $$self, to => $$first});
    $g->add_edge({from => $$self, to => $$last});
}

sub B::UNOP::visit {
    my $self = shift;
    my $first = $self->first;
    $g->add_node({name => $$self, label => $self->name});
    $g->add_edge({from => $$self, to => $$first});
    Od::Tree::sibvisit($self, $first); # For nulls.
}

sub B::LOOP::visit {
    my $self = shift;
    if ($self->children) {
        B::LISTOP::visit($self);
    } else {
    $g->add_node({name => $$self, label => $self->name});
    }
}

sub B::OP::visit {
    my $self = shift;
    $g->add_node({name => $$self, label => $self->name});
}

sub B::PMOP::visit { # PMOPs think they're unary, but they aren't.
    my $self = shift;
    $g->add_node({name => $$self, label => $self->name});
}

sub import {
    my ($class, @options) = @_;
    my ($dump, $quiet, $veryquiet, $fh) = ('', 0, 0);
    if ($options[0] eq '-d') {
      shift @options;
      $dump = shift @options;
    }
    elsif ($options[0] =~ /-d=(.+)/) {
      $dump = $1;
      shift @options;
    }
    else {
      $dump = $options[$#options]; # the last arg
    }
    if ($options[0] eq '-q' || $options[0] eq '-qq') {
	$quiet = 1;
	open (SAVEOUT, ">&STDOUT");
	close STDOUT;
	open (STDOUT, ">", \$O::BEGIN_output);
	if ($options[0] eq '-qq') {
	    $veryquiet = 1;
	}
	shift @options;
    }
    $dump = 'Od.dump' unless $dump;
    my $backend = shift (@options);

    # Now decide in which stage we are.
    # If the file is a Perl source file, dump via Storable.
    my $src = $options[$#options];
    eval 'require Storable';
    if (! -e $src or Storable::file_magic($src)) {
      eval q[
	BEGIN {
	    minus_c;
	    save_BEGINs;
	}
	CHECK {
	    if ($quiet) {
		close STDOUT;
		open (STDOUT, ">&SAVEOUT");
		close SAVEOUT;
	    }
            eval 'require Storable';
	    Storable->import 'store_fd';
	    # $Storable::canonical = 1;
	    $fh = open '>', '].$dump.[';

            my $t = new Od::Tree;
	    walkoptree_slow(main_root, 'visit');
            close $fh;

            close STDERR if $veryquiet;
        }
      ];
      die $@ if $@;
    }
    # Else load it from Storable, recreate the optree starting with
    # main_root and start the Backend normally, but from INIT.
    else { # stage2

      eval 'require Storable';
      main_root = ${Storable::retrieve($dump)};

      eval "use B::$backend();";
      if ($@) {
	croak "use of backend $backend failed: $@";
      }

      my $compilesub = &{"B::${backend}::compile"}(@options);
      if (ref($compilesub) ne "CODE") {
	die $compilesub;
      }

      local $savebackslash = $\;
      local ($\,$",$,) = (undef,' ','');
      &$compilesub();

      #close STDERR if $veryquiet;
    }
}

1;

__END__

=head1 NAME

Od - Idea of a Perl Compiler dump and debug

=head1 SYNOPSIS

	perl -MOd=[-d=dump,]Backend[,OPTIONS] foo.pl
	perl -d -MOd=Backend[,OPTIONS] foo.dump

=head1 DESCRIPTION

This module should be used as debugging replacement to L<O>, the
B<Perl Compiler> frontend.

Debugging is done in two steps, first you store a optree dump in the
C<CHECK> stage into F<foo.dump>, or the dumpfile specified with the
C<-d=dump> option, and the Compiler backend is never called.

Then you load the dump into the C<INIT> stage and continue.

  perl -d -MOd=Backend[,OPTIONS] foo.dump

Loads the stored optree after the CHECK stage, sets up the
C<PL_main_root> to point to the loaded optree dump
and starts the debugger as specified via C<-d>.

=head1 PROBLEMS

But than the nasty head of Storable and B appeared. C<B::OP>s
are a tree of linked pointers. So we need a walkoptree
which stores all visited OPs into the Storable stream.

But then what to do in the 2nd thaw stage?
L<B> objects cannot be written to! All pointers are read-only.
L<Storable> hooks? Will fail on C<thaw>.
Looks like we need a C<B::OP::thaw> method which re-creates
blessed OPs and SVs with all its fields. Similar to L<Bytecode>.

Setting up a dummy B package just for debugging makes no
sense, as I want to debug the compiler which runs through a
real B optree.

Oh my, so I gave up on this for this year.

=head1 AUTHOR

Reini Urban, C<rurban@cpan.org> 2009

=cut
