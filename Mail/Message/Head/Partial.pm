
use strict;

package Mail::Message::Head::Partial;
use vars '$VERSION';
$VERSION = '2.043';
use base 'Mail::Message::Head::Complete';

use Scalar::Util 'weaken';


sub removeFields(@)
{   my $self  = shift;
    my $known = $self->{MMH_fields};

    foreach my $match (@_)
    {
        if(ref $match)
        {   $_ =~ $match && delete $known->{$_} foreach keys %$known;
        }
        else { delete $known->{lc $match} }
    }

    $self->cleanupOrderedFields;
}

#------------------------------------------


sub removeFieldsExcept(@)
{   my $self   = shift;
    my $known  = $self->{MMH_fields};
    my %remove = map { ($_ => 1) } keys %$known;

    foreach my $match (@_)
    {   if(ref $match)
        {   $_ =~ $match && delete $remove{$_} foreach keys %remove;
        }
        else { delete $remove{lc $match} }
    }

    delete @$known{ keys %remove };

    $self->cleanupOrderedFields;
}

#------------------------------------------


sub removeResentGroups()
{   my $self = shift;
    require Mail::Message::Head::ResentGroup;
    
    my $known = $self->{MMH_fields};
    foreach my $name (keys %$known)
    {   delete $known->{$_}
           if $name =~ $Mail::Message::Head::ResentGroup::resent_field_names
    }

    $self->cleanupOrderedFields;
}

#------------------------------------------


sub cleanupOrderedFields()
{   my $self = shift;
    my @take = grep { defined $_ } @{$self->{MMH_order}};
    weaken($_) foreach @take;
    $self->{MMH_order} = \@take;
    $self;
}

#------------------------------------------

1;
