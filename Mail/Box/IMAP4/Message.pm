use strict;
use warnings;

package Mail::Box::IMAP4::Message;
our $VERSION = 2.036;  # Part of Mail::Box
use base 'Mail::Box::Net::Message';

use File::Copy;
use Carp;

sub init($)
{   my ($self, $args) = @_;

    $args->{body_type} ||= 'Mail::Message::Body::Lines';

    $self->SUPER::init($args);
    $self;
}

sub size($)
{   my $self = shift;

    return $self->SUPER::size
        unless $self->isDelayed;

    $self->folder->imapClient->messageSize($self->unique);
}

sub deleted(;$)
{   my $self   = shift;
    return $self->SUPER::deleted unless @_;

    my $set    = shift;
    $self->folder->imapClient->deleted($set, $self->unique);
    $self->SUPER::deleted($set);
}

sub label(@)
{   my $self = shift;
    my $imap = $self->folder->imapClient or return;

    return $imap->getFlag($self->unique, shift)
       if @_ == 1;

    $imap->setFlags($self->unique, @_);
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

    (my $head, $body) = $self->folder->getHeadAndBody($self);
    $self->head($head) if $head->isDelayed;
    $self->storeBody($body);
}

1;
