use strict;
use warnings;

package Mail::Message::Body::Nested;
our $VERSION = 2.033;  # Part of Mail::Box
use base 'Mail::Message::Body';

use Mail::Message::Body::Lines;
use Mail::Message::Part;

use Carp;

sub init($)
{   my ($self, $args) = @_;
    $args->{mime_type} ||= 'message/rfc822';

    $self->SUPER::init($args);

    my $nested;
    if(my $raw = $args->{nested})
    {   $nested = Mail::Message::Part->coerce($raw, $self);

        croak 'Data not convertible to a message (type is ', ref $raw,")\n"
            unless defined $nested;
    }

    my $based = $args->{based_on};

    $self->{MMBN_nested}
       = !$based || defined $nested  ? $nested
       : $based->isNested            ? $based->nested
       : undef;

    $self;
}

sub isNested() {1}

sub isBinary() {shift->nested->isBinary}

sub clone()
{   my $self     = shift;

    my $body     = ref($self)->new
     ( $self->logSettings
     , based_on => $self
     , nested   => $self->nested->clone
     );

}

sub nrLines() { shift->nested->nrLines }

sub size()    { shift->nested->size }

sub nested() { shift->{MMBN_nested} }

sub string()
{    my $nested = shift->nested;
     defined $nested ? $nested->string : '';
}

sub lines()
{    my $nested = shift->nested;
     defined $nested ? $nested->lines : ();
}

sub file()
{    my $nested = shift->nested;
     defined $nested ? $nested->file : undef;
}

sub print(;$)
{   my $self = shift;
    $self->nested->print(shift || select);
    $self;
}

sub forNested($)
{   my ($self, $code) = @_;
    my $nested    = $self->nested;
    my $body      = $nested->body;
    my $new_body  = $code->($self, $body);

    return $self if $new_body == $body;

    my $new_nested  = Mail::Message::Part->new
       ( head      => $nested->head->clone
       , container => undef
       );

    $new_nested->body($new_body);

    my $created = (ref $self)->new
      ( based_on => $self
      , nested   => $new_nested
      );

    $new_nested->container($created);
    $created;
}

sub check() { shift->forNested( sub {$_[1]->check} ) }

sub encode(@)
{   my ($self, %args) = @_;
    $self->forNested( sub {$_[1]->encode(%args)} );
}

sub encoded() { shift->forNested( sub {$_[1]->encoded} ) }

sub read($$$$)
{   my ($self, $parser, $head, $bodytype) = @_;

    my $raw = Mail::Message->new;
    $raw->readFromParser($parser, $bodytype)
       or return;

    my $cooked = Mail::Message::Part->coerce($raw, $self);
    $self->{MMBN_nested} = $cooked;
    $self;
}

sub fileLocation(;$$) { shift->{MMBN_nested}->fileLocation(@_) }

1;
