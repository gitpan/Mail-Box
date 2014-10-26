use strict;
use warnings;

package Mail::Message::Convert::HtmlFormatPS;
our $VERSION = 2.027;  # Part of Mail::Box
use base 'Mail::Message::Convert';

use Mail::Message::Body::String;

use HTML::TreeBuilder 3.13;
use HTML::FormatText;

sub init($)
{   my ($self, $args)  = @_;

    my @formopts = map { ($_ => delete $args->{$_} ) }
                       grep m/^[A-Z]/, keys %$args;

    $self->SUPER::init($args);

    $self->{MMCH_formatter} = HTML::FormatPS->new(@formopts);
    $self;
}

sub format($)
{   my ($self, $body) = @_;

    my $dec  = $body->encode(transfer_encoding => 'none');
    my $tree = HTML::TreeBuilder->new_from_file($dec->file);

    (ref $body)->new
      ( based_on  => $body
      , mime_type => 'application/postscript'
      , data     => [ $self->{MMCH_formatter}->format($tree) ]
      );
}

1;
