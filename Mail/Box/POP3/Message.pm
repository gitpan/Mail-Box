
use strict;
use warnings;

package Mail::Box::POP3::Message;
use vars '$VERSION';
$VERSION = '2.042';
use base 'Mail::Box::Net::Message';

use File::Copy;
use Carp;


sub init($)
{   my ($self, $args) = @_;

    $args->{body_type} ||= 'Mail::Message::Body::Lines';

    $self->SUPER::init($args);
    $self;
}

#-------------------------------------------


sub size($)
{   my $self = shift;
    
    return $self->SUPER::size
        unless $self->isDelayed;

    $self->folder->popClient->messageSize($self->unique);
}

#-------------------------------------------

sub delete()
{   my $self = shift;
    $self->folder->popClient->deleted(1, $self->unique);
    $self->SUPER::delete;
}

#-------------------------------------------

sub deleted(;$)
{   my $self   = shift;
    return $self->SUPER::deleted unless @_;

    my $set    = shift;
    $self->folder->popClient->deleted(0, $self->unique)
       unless $set;

    $self->SUPER::deleted($set);
}

#-------------------------------------------


sub loadHead()
{   my $self     = shift;
    my $head     = $self->head;
    return $head unless $head->isDelayed;

    $self->head($self->folder->getHead($self));
}

#-------------------------------------------

sub loadBody()
{   my $self     = shift;

    my $body     = $self->body;
    return $body unless $body->isDelayed;

    (my $head, $body) = $self->folder->getHeadAndBody($self);
    $self->head($head) if $head->isDelayed;
    $self->storeBody($body);
}

#-------------------------------------------

1;
