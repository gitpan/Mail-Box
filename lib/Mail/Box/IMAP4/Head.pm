
use strict;

package Mail::Box::IMAP4::Head;
use vars '$VERSION';
$VERSION = '2.062';
use base 'Mail::Message::Head';

use Date::Parse;


sub init($$)
{   my ($self, $args) = @_;
    $self->SUPER::init($args);

    $self->{MBIH_c_fields} = $args->{cache_fields};
    $self;
}

#------------------------------------------


sub get($;$)
{   my ($self, $name, $index) = @_;

       if(not $self->{MBIH_c_fields}) { ; }
    elsif(wantarray)
    {   my @values = $self->SUPER::get(@_);
        return @values if @values;
    }
    else
    {   my $value  = $self->SUPER::get(@_);
        return $value  if defined $value;
    }

    # Something here, playing with ENVELOPE, may improve the performance
    # as well.
    my $imap   = $self->folder->transporter;

    my @fields = $imap->getFields($name);

    if(@fields && $self->{MBIH_c_fields})
    {   $self->addNoRealize($_) for @fields
    }

      defined $index ? $fields[$index]
    : wantarray      ? @fields
    :                  $fields[0];
}

#------------------------------------------

sub guessBodySize() {undef}

#-------------------------------------------

sub guessTimestamp() {undef}

#------------------------------------------


1;
