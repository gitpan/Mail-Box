use strict;
use warnings;

package Mail::Box::POP3::Message;
our $VERSION = 2.024;  # Part of Mail::Box
use base 'Mail::Box::Net::Message';

use File::Copy;
use Carp;

sub init($)
{   my ($self, $args) = @_;

    $args->{body_type} ||= 'Mail::Message::Body::Lines';

    $self->SUPER::init($args);
    $self;
}

sub loadHead()
{   my $self     = shift;
    my $head     = $self->head;
    return $head unless $head->isDelayed;

    $self->head($self->folder->getHead($self));
}

sub loadBody()
{   my $self     = shift;

    my $body     = $self->body;
    return $body unless $body->isDelayed;

    my ($head, $newbody) = $self->folder->getHeadAndBody($self);
    $self->head($head) if defined $head;
    $self->body($newbody);
}

1;
