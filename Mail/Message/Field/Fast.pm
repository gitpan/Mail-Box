use strict;
use warnings;

package Mail::Message::Field::Fast;
our $VERSION = 2.025;  # Part of Mail::Box
use base 'Mail::Message::Field';

use Carp;

#
# The DATA is stored as:   [ NAME, FOLDED-BODY ]
# The body is kept in a folded fashion, where each line starts with
# a single blank.

sub new($;$@)
{   my $class = shift;

    my ($name, $body) = $class->consume(@_==1 ? (shift) : (shift, shift));
    return () unless defined $body;

    my $self = bless [$name, $body], $class;

    # Attributes
    $self->comment(shift)             if @_==1;   # one attribute line
    $self->attribute(shift, shift) while @_ > 1;  # attribute pairs

    $self;
}

sub clone()
{   my $self = shift;
    bless [ @$self ], ref $self;
}

sub length()
{   my $self = shift;
    length($self->[0]) + 1 + length($self->[1]);
}

sub name() { lc shift->[0] }

sub Name() { shift->[0] }

sub folded()
{   my $self = shift;
    return $self->[0].':'.$self->[1]
        unless wantarray;

    my @lines = $self->folded_body;
    my $first = $self->[0]. ':'. shift @lines;
    ($first, @lines);
}

sub unfolded_body($;@)
{   my $self = shift;

    $self->[1] = $self->fold($self->[0], @_)
       if @_;

    $self->unfold($self->[1]);
}

sub folded_body($)
{   my ($self, $body) = @_;
    if(@_==2) { $self->[1] = $body }
    else      { $body = $self->[1] }

    wantarray ? split(m!(?<=\n)!, $body) : $body;
}

# For performance only

sub print(;$)
{   my $self = shift;
    (shift || select)->print($self->[0].':'.$self->[1]);
}

1;
