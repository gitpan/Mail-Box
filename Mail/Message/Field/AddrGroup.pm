use strict;
use warnings;

package Mail::Message::Field::AddrGroup;
use vars '$VERSION';
$VERSION = '2.043';
use base 'Mail::Reporter';


sub init($)
{   my ($self, $args) = @_;

    $self->SUPER::init($args) or return;

    $self->{MMFA_name} = defined $args->{name} ? $args->{name} : '';
    $self->{MMFA_addresses} = [];
    $self;
}

#------------------------------------------


sub name() { shift->{MMFA_name} }

#------------------------------------------


sub addAddress(@)
{   my $self  = shift;
    my $email = @_ && ref $_[0] ? shift
              : Mail::Message::Field::Address->new(@_);
    push @{$self->{MMFA_addresses}}, $email;
    $email;
}

#------------------------------------------


sub string()
{   my $self = shift;
    my $name = $self->name;
    $name .= ': ' if length $name;
    $name . join(', ', $self->addresses) . ';';
}

#------------------------------------------


sub addresses() { @{shift->{MMFA_addresses}} }

#------------------------------------------


1;
