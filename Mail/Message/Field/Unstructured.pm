use strict;
use warnings;

package Mail::Message::Field::Unstructured;
use vars '$VERSION';
$VERSION = '2.041';
use base 'Mail::Message::Field::Full';


my %implementation;

sub init($)
{   my ($self, $args) = @_;

    my $name = $args->{name};

    if(my $body = $args->{body})
    {   my @body = ref $body eq 'ARRAY' ? @$body : ($body);
        return () unless @body;
        $args->{body} = $self->encode(join(", ", @body), %$args);
    }
    else
    {   ($name, my $body) = split /\s*\:/, $name, 2;
        $args->{name} = $name;
        return () unless defined $body;
        $args->{body} = $body;
    }

    $self->SUPER::init($args) or return;
    $self;
}

#------------------------------------------


1;
