use strict;
use warnings;

package Mail::Message::Field::Address;
use vars '$VERSION';
$VERSION = '2.041';
use base 'Mail::Reporter';

use Mail::Message::Field::Full;
my $format = 'Mail::Message::Field::Full';


sub init($)
{   my ($self, $args) = @_;

    $self->SUPER::init($args) or return;

    $self->{MMFA_name} = $args->{name};

    @$self{ qw/MMFA_local MMFA_domain/ }
     = defined $args->{address} ? (split /\@/, $args->{address}, 2)
     : (@$args{ qw/local domain/ });

    $self;
}

#------------------------------------------


sub name() { shift->{MMFA_name} }

#------------------------------------------


sub address()
{   my $self  = shift;
    my @parts = $self->{MMFA_local};

    push @parts, $format->createComment($self->{MMFA_loccomment})
       if exists $self->{MMFA_loccomment};

    push @parts, '@', $self->{MMFA_domain};

    push @parts, $format->createComment($self->{MMFA_domcomment})
       if exists $self->{MMFA_domcomment};
    
    join '', @parts;
}

#------------------------------------------


sub string()
{   my $self    = shift;
    my @parts;

    my $name    = $self->name;
    push @parts, $format->createPhrase($name) if defined $name;

    my $address = $self->address;
    push @parts, defined $name ? '<'.$address.'>' : $address;

    push @parts, $format->createComment($self->{MMFA_comment})
       if exists $self->{MMFA_comment};

    join ' ', @parts;
}

#------------------------------------------



1;
