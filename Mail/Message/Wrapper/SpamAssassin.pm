use strict;
use warnings;

package Mail::Message::Wrapper::SpamAssassin;
our $VERSION = 2.035;  # Part of Mail::Box
use base 'Mail::SpamAssassin::Message';

use Carp;
use Mail::Message::Body::Lines;

sub new(@)
{   my ($class, $message, %args) = @_;
    $class->SUPER::new($message)->init(\%args);
}

sub init($)
{   my ($self, $args) = @_;
    $self;
}

sub create_new() {croak "Should not be used"}

sub get($) { $_[0]->get_header($_[1]) }

sub get_header($)
{   my ($self, $name) = @_;
    my $field = $self->get_mail_object->head->get($name);
    defined $field ? $field->unfoldedBody : undef;
}

sub put_header($$)
{   my ($self, $name, $value) = @_;
    my $head = $self->get_mail_object->head;
    $value =~ s/\s{2,}/ /g;
    return if $value =~ s/^\s*$//;
    $head->add($name => $value);
}

sub get_all_headers($)
{   my $head = shift->get_mail_object->head;
    "$head";
}

sub replace_header($$)
{   my $head = shift->get_mail_object->head;
    my ($name, $value) = @_;
    $head->set($name, $value);
}

sub delete_header($)
{   my $head = shift->get_mail_object->head;
    my $name = shift;
    $head->delete($name);
}

sub get_body() {shift->get_mail_object->body->lines }

sub replace_body($)
{   my ($self, $data) = @_;
    my $body = Mail::Message::Body::Lines->new(data => $data);
    $self->get_mail_object->storeBody($body);
}

1;
