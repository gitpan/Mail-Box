use strict;
use warnings;

package Mail::Message::Part;
our $VERSION = 2.019;  # Part of Mail::Box
use base 'Mail::Message';

use Carp;

sub init($)
{   my ($self, $args) = @_;
    $self->SUPER::init($args);

    $self->{MMP_parent} = $args->{parent}
        or confess "No parent specified for part.\n";

    $self;
}

sub coerce($@)
{   my ($class, $message, $parent) = @_;

    my $part = $class->SUPER::coerce($message);
    $part->{MMP_parent} = $parent;

    $part;
}

sub delete() {shift->deleted(1)}

sub deleted(;$)
{   my $self = shift;
    return $self->{MMP_deleted} unless @_;

    $self->toplevel->modified(1);
    $self->{MMP_deleted} = shift;
}

sub parent() { shift->{MMP_parent} }

sub toplevel() { shift->parent->toplevel }

sub isPart() { 1 }

1;
