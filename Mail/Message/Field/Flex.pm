use strict;
use warnings;

package Mail::Message::Field::Flex;
our $VERSION = 2.029;  # Part of Mail::Box
use base 'Mail::Message::Field';

use Carp;

sub new($;$$@)
{   my $class  = shift;
    my $args   = @_ <= 2 || ! ref $_[-1] ? {}
                : ref $_[-1] eq 'ARRAY'  ? { @{pop @_} }
                :                          pop @_;

    my ($name, $body) = $class->consume(@_==1 ? (shift) : (shift, shift));
    return () unless defined $body;

    # Attributes preferably stored in array to protect order.
    my $attr   = $args->{attributes};
    $attr      = [ %$attr ] if defined $attr && ref $attr eq 'HASH';
    push @$attr, @_;

    $class->SUPER::new(%$args, name => $name, body => $body,
         attributes => $attr);
}

sub init($)
{   my ($self, $args) = @_;

    @$self{ qw/MMF_name MMF_body/ } = @$args{ qw/name body/ };

    $self->comment($args->{comment})
        if exists $args->{comment};

    my $attr = $args->{attributes};
    $self->attribute(shift @$attr, shift @$attr)
        while @$attr;

    $self;
}

sub clone()
{   my $self = shift;
    (ref $self)->new($self->Name, $self->body);
}

sub length()
{   my $self = shift;
    length($self->{MMF_name}) + 1 + length($self->{MMF_body});
}

sub name() { lc shift->{MMF_name}}

sub Name() { shift->{MMF_name}}

sub folded(;$)
{   my $self = shift;
    return $self->{MMF_name}.':'.$self->{MMF_body}
        unless wantarray;

    my @lines = $self->folded_body;
    my $first = $self->{MMF_name}. ':'. shift @lines;
    ($first, @lines);
}

sub unfolded_body($;@)
{   my $self = shift;
    $self->{MMF_body} = $self->fold($self->{MMF_name}, @_)
       if @_;

    $self->unfold($self->{MMF_body});
}

sub folded_body($)
{   my ($self, $body) = @_;
    if(@_==2) { $self->{MMF_body} = $body }
    else      { $body = $self->{MMF_body} }

    wantarray ? (split /^/, $body) : $body;
}

1;
