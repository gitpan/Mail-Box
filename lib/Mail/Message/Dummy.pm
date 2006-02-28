
use strict;

package Mail::Message::Dummy;
use vars '$VERSION';
$VERSION = '2.064';
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
 
#-------------------------------------------

sub isDummy()    { 1 }

#-------------------------------------------


sub head()
{    shift->log(ERROR => "You cannot take the head of a dummy message");
     ();
}

#-------------------------------------------

sub body()
{    shift->log(ERROR => "You cannot take the body of a dummy message");
     ();
}

#-------------------------------------------

1;
