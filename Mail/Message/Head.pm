use strict;
use warnings;

package Mail::Message::Head;
our $VERSION = 2.019;  # Part of Mail::Box
use base 'Mail::Reporter';

use Mail::Message::Head::Complete;
use Mail::Message::Field::Fast;
use Mail::Box::Parser;

use Carp;
use Scalar::Util 'weaken';
use FileHandle;

use overload qq("") => 'toString'
           , bool   => 'isEmpty';

sub new(@)
{   my $class = shift;

    return Mail::Message::Head::Complete->new(@_)
       if $class eq __PACKAGE__;

    $class->SUPER::new(@_);
}

sub init($)
{   my ($self, $args) = @_;

    $self->SUPER::init($args);

    $self->{MMH_field_type} = $args->{field_type}
        if $args->{field_type};

    if(defined $args->{message})
    {   $self->{MMH_message} = $args->{message};
        weaken($self->{MMH_message});
    }

    $self->{MMH_wrap_length} = $args->{wrap_length}
        ? ($args->{wrap_length} > 0 ? $args->{wrap_length} : 0)
        : 72;

    $self->{MMH_fields}     = {};
    $self->{MMH_order}      = [];
    $self->{MMH_modified}   = $args->{modified} || 0;
    $self;
}

sub build(@)
{   my $self = shift;
    my $head = $self->new;
    $head->add(shift, shift) while @_;
    $head;
}

sub isDelayed { 1 }

sub isMultipart()
{   my $type = shift->get('Content-Type');
    $type && $type->body =~ m[^(multipart/)|(message/rfc822)]i;
}

sub modified(;$)
{   my $self = shift;
    @_ ? $self->{MMH_modified} = shift : $self->{MMH_modified};
}

sub isResent() { defined shift->get('resent-message-id') }

sub isEmpty { scalar keys %{shift->{MMH_fields}} }

sub message(;$)
{   my $self = shift;
    if(@_)
    {    $self->{MMH_message} = shift;
         weaken($self->{MMH_message});
    }

    $self->{MMH_message};
}

sub setField($$) {shift->add(@_)} # compatibility

sub get($;$)
{   my $known = shift->{MMH_fields};
    my $value = $known->{lc shift};
    my $index = shift;

    if(defined $index)
    {   return ! defined $value      ? undef
             : ref $value eq 'ARRAY' ? $value->[$index]
             : $index == 0           ? $value
             :                         undef;
    }
    elsif(wantarray)
    {   return ! defined $value      ? ()
             : ref $value eq 'ARRAY' ? @$value
             :                         ($value);
    }
    else
    {   return ! defined $value      ? undef
             : ref $value eq 'ARRAY' ? $value->[-1]
             :                         $value;
    }
}

sub get_all(@) { my @all = shift->get(@_) }   # compatibility, force list

sub knownNames() { @{shift->{MMH_order}} }

# To satisfy overload in static resolving.

sub toString() { shift->load->toString }

sub read($)
{   my ($self, $parser) = @_;

    my @fields    = $parser->readHeader($self->{MMH_wrap_length});
    @$self{ qw/MMH_begin MMH_end/ } = (shift @fields, shift @fields);

    $parser->defaultParserType(ref $parser);

    my $known     = $self->{MMH_fields};
    my $fieldtype = $self->{MMH_field_type} || 'Mail::Message::Field::Fast';

    foreach (@fields)
    {   my $field = $fieldtype->newNoCheck( @$_ );
        my $name  = $field->name;

        push @{$self->{MMH_order}}, $name
            unless exists $known->{$name};

        if(defined $known->{$name})
        {   if(ref $known->{$name} eq 'ARRAY')
                 { push @{$known->{$name}}, $field }
            else { $known->{$name} = [ $known->{$name}, $field ] }
        }
        else
        {   $known->{$name} = $field;
        }
    }

    $self;
}

sub load($) {shift}

sub fileLocation()
{   my $self = shift;
    @$self{ qw/MMH_begin MMH_end/ };
}

sub moveLocation($)
{   my ($self, $dist) = @_;
    $self->{MMH_begin} -= $dist;
    $self->{MMH_end}   -= $dist;
    $self;
}

sub createMessageId()
{  shift->log(INTERNAL =>
       "You didn't check well enough for a msg-id: header should be realized.");
}

sub wrapLength(;$)
{   my $self = shift;
    return $self->{MMH_wrap_length} unless @_;

    my $wrap = shift;
    return $wrap if $wrap==$self->{MMH_wrap_length};

    foreach my $name ($self->names)
    {   $_->setWrapLength($wrap) foreach $self->get($name);
    }

    $self->{MMH_wrap_length} = $wrap;
}

sub setNoRealize($)
{   my ($self, $field) = @_;

    my $known = $self->{MMH_fields};
    my $name  = $field->name;

    push @{$self->{MMH_order}}, $name
        unless exists $known->{$name};

    $known->{$name} = $field;
    $field;
}

sub addNoRealize($)
{   my ($self, $field) = @_;

    my $known = $self->{MMH_fields};
    my $name  = $field->name;

    push @{$self->{MMH_order}}, $name
        unless exists $known->{$name};

    if(defined $known->{$name})
    {   if(ref $known->{$name} eq 'ARRAY') { push @{$known->{$name}}, $field }
        else { $known->{$name} = [ $known->{$name}, $field ] }
    }
    else
    {   $known->{$name} = $field;
    }

    $field;
}

1;
