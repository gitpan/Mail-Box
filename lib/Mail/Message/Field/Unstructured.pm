use strict;
use warnings;

package Mail::Message::Field::Unstructured;
use vars '$VERSION';
$VERSION = '2.057';
use base 'Mail::Message::Field::Full';


sub init($)
{   my ($self, $args) = @_;

    if($args->{body} && ($args->{encoding} || $args->{charset}))
    {   $args->{body} = $self->encode($args->{body}, %$args);
    }

    $self->SUPER::init($args) or return;

    $self->log(WARNING=>"Attributes are not supported for unstructured fields")
        if defined $args->{attributes};

    $self->log(WARNING => "No extras for unstructured fields")
        if defined $args->{extra};

    $self;
}

#------------------------------------------




1;
