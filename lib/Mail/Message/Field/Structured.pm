use strict;
use warnings;

package Mail::Message::Field::Structured;
use vars '$VERSION';
$VERSION = '2.054';
use base 'Mail::Message::Field::Full';

use Mail::Message::Field::Attribute;


sub init($)
{   my ($self, $args) = @_;

    $self->SUPER::init($args);

    $self->addExtra($args->{extra})
        if exists $args->{extra};

    my $attr = $args->{attributes} || [];
    $attr    = [ %$attr ] if ref $attr eq 'HASH';

    while(@$attr)
    {   my $name = shift @$attr;
        if(ref $name) { $self->attribute($name) }
        else          { $self->attribute($name, shift @$attr) }
    }

    $self->{MMFS_attrs} = {};
    $self->{MMFS_extra} = ();
    $self;
}

#------------------------------------------

sub clone() { dclone(shift) }

#------------------------------------------


sub attribute($;$)
{   my ($self, $attr) = (shift, shift);
    my $name;
    if(ref $attr) { $name = $attr->name }
    elsif( !@_ )  { return $self->{MMFS_attrs}{lc $attr} }
    else
    {   $name = $attr;
        $attr = Mail::Message::Field::Attribute->new($name, @_);
    }

    delete $self->{MMFF_body};
    if(my $old =  $self->{MMFS_attrs}{$name})
    {   $old->mergeComponent($attr);
        return $old;
    }
    else
    {   $self->{MMFS_attrs}{$name} = $attr;
        return $attr;
    }
}

#------------------------------------------


sub attributes() { values %{shift->{MMFS_attrs}} }

#------------------------------------------

sub beautify() { delete shift->{MMFF_body} }

#------------------------------------------

1;
