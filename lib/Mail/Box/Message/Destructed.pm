
use strict;

package Mail::Box::Message::Destructed;
use vars '$VERSION';
$VERSION = '2.053';
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

   $message->label(deleted => 1);
   $message->body(undef);
   $message->head(undef);

   bless $message, $class;
}

#-------------------------------------------


sub label($;@)
{  my $self = shift;

   if(@_==1)
   {   my $label = shift;
       return 1 if $label eq 'deleted';
       $self->log(ERROR => "Destructed message has no labels except 'deleted', requested is $label");
       return 0;
   }

   my %flags = @_;
   unless(keys %flags==1 && exists $flags{deleted})
   {   $self->log(ERROR => "Destructed message has no labels except 'deleted', trying to set @{[ keys %flags ]}");
       return;
   }

   $self->log(ERROR => "Destructed messages can not be undeleted")
      unless $flags{deleted};

   1;
}

#-------------------------------------------

sub labels() { wantarray ? ('deleted') : { deleted => 1 } }

1;