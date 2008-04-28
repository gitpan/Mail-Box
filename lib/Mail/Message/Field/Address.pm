# Copyrights 2001-2008 by Mark Overmeer.
#  For other contributors see ChangeLog.
# See the manual pages for details on the licensing terms.
# Pod stripped from pm file by OODoc 1.04.
use strict;
use warnings;

package Mail::Message::Field::Address;
use vars '$VERSION';
$VERSION = '2.082';

use base 'Mail::Identity';

use Mail::Message::Field::Addresses;
use Mail::Message::Field::Full;
my $format = 'Mail::Message::Field::Full';


use overload '""' => 'string'
           , bool => sub {1}
           ;

#------------------------------------------


sub coerce($@)
{  my ($class, $addr, %args) = @_;
   return () unless defined $addr;

   return $class->parse($addr) unless ref $addr;

   return $addr if $addr->isa($class);

   my $from = $class->from($addr);

   Mail::Reporter->log(ERROR => "Cannot coerce a ".ref($addr)." into a $class"),
      return () unless defined $from;

   bless $from, $class;
}

#------------------------------------------


sub parse($)
{   my $self   = shift;
    my $parsed = Mail::Message::Field::Addresses->new('To' => shift);
    defined $parsed ? ($parsed->addresses)[0] : ();
}

#------------------------------------------


sub string()
{   my $self  = shift;
    my @opts  = (charset => $self->charset); # language => $self->language

    my @parts;
    my $name    = $self->phrase;
    push @parts, $format->createPhrase($name, @opts) if defined $name;

    my $address = $self->address;
    push @parts, @parts ? '<'.$address.'>' : $address;

    my $comment = $self->comment;
    push @parts, $format->createComment($comment, @opts) if defined $comment;

    join ' ', @parts;
}

#------------------------------------------

1;
