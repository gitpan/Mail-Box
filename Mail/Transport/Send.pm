use strict;
use warnings;

package Mail::Transport::Send;
our $VERSION = 2.027;  # Part of Mail::Box
use base 'Mail::Transport';

use Carp;
use File::Spec;
use Errno 'EAGAIN';

sub new(@)
{   my $class = shift;
    $class->SUPER::new(via => 'sendmail', @_);
}

sub send($@)
{   my ($self, $message) = (shift, shift);

    unless($message->isa('Mail::Message'))  # avoid rebless.
    {   $message = Mail::Message->coerce($message);
        confess "Unable to coerce object into Mail::Message."
            unless defined $message;
    }

    return 1 if $self->trySend($message);
    return 0 unless $?==EAGAIN;

    my %args     = @_;
    my ($interval, $retry) = $self->retry;
    $interval = $args{interval} if exists $args{interval};
    $retry    = $args{retry}    if exists $args{retry};

    while($retry!=0)
    {   sleep $interval;
        return 1 if $self->trySend($message);
        return 0 unless $?==EAGAIN;
        $retry--;
    }

    0;
}

sub trySend($@)
{   my $self = shift;
    $self->log(ERROR => "Transporters of type ".ref($self). " cannot send.");
}

sub putContent($$@)
{   my ($self, $message, $fh, %args) = @_;

       if($args{body_only}) { $message->body->print($fh) }
    elsif($args{undisclosed})
    {    $message->head->printUndisclosed($fh);
         $message->body->print($fh);
    }
    else { $message->Mail::Message::print($fh) }

    $self;
}

1;
