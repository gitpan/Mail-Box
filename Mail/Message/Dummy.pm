use strict;

package Mail::Message::Dummy;
our $VERSION = 2.040;  # Part of Mail::Box
use base 'Mail::Message';

use Carp;

sub init($)
{   my ($self, $args) = @_;

    @$args{ qw/modified trusted/ } = (0, 1);
    $self->SUPER::init($args);

    $self->log(ERROR => "Message-Id is required for a dummy.")
       unless exists $args->{messageId};

    $self;
}

sub isDummy()    { 1 }

sub head()
{    shift->log(INTERNAL => "You cannot take the head of a dummy");
     ();
}

sub body()
{    shift->log(INTERNAL => "You cannot take the body of a dummy");
     ();
}

1;
