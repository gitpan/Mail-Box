use strict;
use warnings;

package Mail::Message::Part;
our $VERSION = 2.031;  # Part of Mail::Box
use base 'Mail::Message';

use Carp;

sub init($)
{   my ($self, $args) = @_;
    $self->SUPER::init($args);

    confess "No parent specified for part.\n"
        unless exists $args->{parent};

    $self->{MMP_parent} = $args->{parent};
    $self;
}

sub buildFromBody($$;@)
{   my ($class, $body, $parent) = (shift, shift, shift);
    my @log     = $body->logSettings;

    my $head    = Mail::Message::Head::Complete->new(@log);
    while(@_)
    {   if(ref $_[0]) {$head->add(shift)}
        else          {$head->add(shift, shift)}
    }

    my $part = $class->new
     ( head   => $head
     , parent => $parent
     , @log
     );

    $part->storeBody($body->check);
    $part->statusToLabels;
    $part;
}

sub coerce($@)
{   my ($class, $thing, $parent) = (shift, shift, shift);

    return $class->buildFromBody($thing, $parent, @_)
        if $thing->isa('Mail::Message::Body');

    my $message = $thing->isa('Mail::Box::Message') ? $thing->clone : $thing;

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

sub parent(;$)
{   my $self = shift;
    @_ ? $self->{MMP_parent} = shift : $self->{MMP_parent};
}

sub toplevel() { shift->parent->toplevel }

sub isPart() { 1 }

1;
