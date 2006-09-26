use strict;
use warnings;

package Mail::Message::Convert::HtmlFormatText;
use vars '$VERSION';
$VERSION = '2.068';
use base 'Mail::Message::Convert';

use Mail::Message::Body::String;

use HTML::TreeBuilder;
use HTML::FormatText;


sub init($)
{   my ($self, $args)  = @_;

    $self->SUPER::init($args);

    $self->{MMCH_formatter} = HTML::FormatText->new
     ( leftmargin  => (defined $args->{leftmargin}  ? $args->{leftmargin}  : 3)
     , rightmargin => (defined $args->{rightmargin} ? $args->{rightmargin} : 72)
     );
      
    $self;
}

#------------------------------------------


sub format($)
{   my ($self, $body) = @_;

    my $dec  = $body->encode(transfer_encoding => 'none');
    my $tree = HTML::TreeBuilder->new_from_file($dec->file);

    (ref $body)->new
      ( based_on  => $body
      , mime_type => 'text/plain'
      , charset   => 'iso-8859-1'
      , data     => [ $self->{MMCH_formatter}->format($tree) ]
      );
}

#------------------------------------------

1;
