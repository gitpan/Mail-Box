use strict;
use warnings;

package Mail::Transport::Send;
use vars '$VERSION';
$VERSION = '2.047';
use base 'Mail::Transport';

use Carp;
use File::Spec;
use Errno 'EAGAIN';


sub new(@)
{   my $class = shift;
    $class->SUPER::new(via => 'sendmail', @_);
}

#------------------------------------------


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

#------------------------------------------


sub trySend($@)
{   my $self = shift;
    $self->log(ERROR => "Transporters of type ".ref($self). " cannot send.");
}

#------------------------------------------


sub putContent($$@)
{   my ($self, $message, $fh, %args) = @_;

       if($args{body_only})   { $message->body->print($fh) }
    elsif($args{undisclosed}) { $message->Mail::Message::print($fh) }
    else
    {   $message->head->printUndisclosed($fh);
        $message->body->print($fh);
    }

    $self;
}

#------------------------------------------


sub destinations($;$)
{   my ($self, $message, $overrule) = @_;
    my @to;

    if(defined $overrule)      # Destinations overruled by user.
    {   my @addr = ref $overrule eq 'ARRAY' ? @$overrule : ($overrule);
        @to = map { ref $_ && $_->isa('Mail::Address') ? ($_)
                    : Mail::Address->parse($_) } @addr;
    }
    elsif(my @rgs = $message->head->resentGroups)
    {   @to = $rgs[0]->destinations;
        $self->log(ERROR => "Resent group does not specify a destination"), return ()
            unless @to;
    }
    else
    {   @to = $message->destinations;
        $self->log(ERROR => "Message has no destination"), return ()
            unless @to;
    }

    @to;
}

#------------------------------------------


1;
