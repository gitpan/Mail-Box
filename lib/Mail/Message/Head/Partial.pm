
use strict;

package Mail::Message::Head::Partial;
use vars '$VERSION';
$VERSION = '2.044';
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
    my $found = 0;
    foreach my $name (keys %$known)
    {   next if $name !~ $Mail::Message::Head::ResentGroup::resent_field_names;
        delete $known->{$name};
        $found++;
    }

    $self->cleanupOrderedFields;
    $self->modified(1) if $found;
    $found;
}

#------------------------------------------


sub removeListGroup()
{   my $self = shift;
    require Mail::Message::Head::ListGroup;

    my $known = $self->{MMH_fields};
    my $found = 0;
    foreach my $name (keys %$known)
    {   next unless $name =~ $Mail::Message::Head::ListGroup::list_field_names;
        delete $known->{$name};
	$found++;
    }

    $self->cleanupOrderedFields if $found;
    $self->modified(1) if $found;
    $found;
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


#------------------------------------------

1;
