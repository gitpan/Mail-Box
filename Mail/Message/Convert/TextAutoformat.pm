use strict;
use warnings;

package Mail::Message::Convert::TextAutoformat;
our $VERSION = 2.019;  # Part of Mail::Box
use base 'Mail::Message::Convert';

use Mail::Message::Body::String;
use Text::Autoformat;

sub init($)
{   my ($self, $args)  = @_;

    $self->SUPER::init($args);

    $self->{MMCA_options} = $args->{autoformat} || { all => 1 };
    $self;
}

sub autoformatBody($)
{   my ($self, $body) = @_;

    ref($body)->new
       ( based_on => $body
       , data     => autoformat($body->string, $self->{MMCA_options})
       );
}

1;
