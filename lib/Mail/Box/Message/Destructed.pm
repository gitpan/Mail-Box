
use strict;

package Mail::Box::Message::Destructed;
use vars '$VERSION';
$VERSION = '2.050';
use base 'Mail::Box::Message';

use Carp;


sub new(@)
{   my $class = shift;
    $class->log(ERROR => 'You cannot instantiate a destructed message');
    undef;
}
 
#-------------------------------------------

sub isDummy()    { 1 }

#-------------------------------------------


sub head(;$)
{    my $self = shift;
     return undef if @_ && !defined(shift);

     $self->log(ERROR => "You cannot take the head of a destructed message");
     undef;
}

#-------------------------------------------


sub body(;$)
{    my $self = shift;
     return undef if @_ && !defined(shift);

     $self->log(ERROR => "You cannot take the body of a destructed message");
     undef;
}

#-------------------------------------------


sub coerce($)
{  my ($class, $message) = @_;

   unless($message->isa('Mail::Box::Message'))
   {  $class->log(ERROR=>"Cannot coerce a ",ref($message), " into destruction");
      return ();
   }

   $message->delete;
   $message->body(undef);
   $message->head(undef);

   bless $message, $class;
}

#-------------------------------------------


sub deleted(;$)
{  my $self = shift;

   $self->log(ERROR => "Destructed messages can not be undeleted")
      if @_ && not $_[0];

   $self->delete;
}

1;
