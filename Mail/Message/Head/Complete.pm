use strict;
use warnings;

package Mail::Message::Head::Complete;
our $VERSION = 2.019;  # Part of Mail::Box
use base 'Mail::Message::Head';

use Mail::Box::Parser;

use Carp;
use Date::Parse;

sub isDelayed() {0}

sub clone(;@)
{   my $self   = shift;
    my $copy   = ref($self)->new($self->logSettings);

    foreach my $name ($self->grepNames(@_))
    {   $copy->add($_->clone) foreach $self->get($name);
    }

    $copy;
}

sub add(@)
{   my $self = shift;
    my $type = $self->{MMH_field_type} || 'Mail::Message::Field::Fast';

    # Create object for this field.

    my $field;
    if(@_==1 && ref $_[0])   # A fully qualified field is added.
    {   $field = shift;
        confess "Add field to header requires $type but got ".ref($field)."\n"
            unless $field->isa($type);
    }
    else { $field = $type->new(@_) }

    $field->setWrapLength($self->{MMH_wrap_length});

    # Put it in place.

    my $known = $self->{MMH_fields};
    my $name  = $field->name;  # is already lower-cased

    push @{$self->{MMH_order}}, $name
        unless exists $known->{$name};

    if(defined $known->{$name})
    {   if(ref $known->{$name} eq 'ARRAY') { push @{$known->{$name}}, $field }
        else { $known->{$name} = [ $known->{$name}, $field ] }
    }
    else
    {   $known->{$name} = $field;
    }

    $self->{MMH_modified}++;
    $field;
}

my @skip_none = qw/content-transfer-encoding content-disposition/;
my %skip_none = map { ($_ => 1) } @skip_none;

sub set(@)
{   my $self = shift;
    my $type = $self->{MMH_field_type} || 'Mail::Message::Field::Fast';

    # Create object for this field.

    my $field;
    if(@_==1 && ref $_[0])   # A fully qualified field is added.
    {   $field = shift;
        confess "Add field to header requires $type but got ".ref($field)."\n"
            unless $field->isa($type);
    }
    else
    {   $field = $type->new(@_);
    }

    my $name  = $field->name;         # is already lower-cased
    my $known = $self->{MMH_fields};

    # Internally, non-existing content-info are in the body stored as 'none'
    # The header will not contain these lines.

    if($skip_none{$name} && $field->body eq 'none')
    {   delete $known->{$name};
        return $field;
    }

    # Put it in place.

    $field->setWrapLength($self->{MMH_wrap_length});

    push @{$self->{MMH_order}}, $name
        unless exists $known->{$name};

    $known->{$name} = $field;
    $self->{MMH_modified}++;

    $field;
}

sub reset($@)
{   my ($self, $name) = (shift, lc shift);
    my $known = $self->{MMH_fields};

    if(@_==0)    { undef $known->{$name}  }
    elsif(@_==1) { $known->{$name} = shift }
    else         { $known->{$name} = [@_]  }

    $self->{MMH_modified}++;
    $self;
}

sub delete($) { $_[0]->reset($_[1]) }

sub count($)
{   my $known = shift->{MMH_fields};
    my $value = $known->{lc shift};

      ! defined $value ? 0
    : ref $value       ? @$value
    :                    1;
}

sub names() {shift->knownNames}

sub grepNames(@)
{   my $self = shift;
    my @take;
    push @take, (ref $_ eq 'ARRAY' ? @$_ : $_) foreach @_;

    return $self->names unless @take;

    my $take;
    if(@take==1 && ref $take[0] eq 'Regexp')
    {   $take    = $take[0];   # one regexp prepared already
    }
    else
    {   # I love this tric:
        local $" = ')|(?:';
        $take    = qr/^(?:(?:@take))/i;
    }

    grep {$_ =~ $take} $self->names;
}

sub print(;$)
{   my $self  = shift;
    my $fh    = shift || select;

    my $known = $self->{MMH_fields};

    foreach my $name (@{$self->{MMH_order}})
    {   my $this = $known->{$name} or next;
        my @this = ref $this eq 'ARRAY' ? @$this : $this;
        $_->print($fh) foreach @this;
    }

    $fh->print("\n");

    $self;
}

sub printUndisclosed($)
{   my ($self, $fh) = @_;

    my $known = $self->{MMH_fields};
    foreach my $name (@{$self->{MMH_order}})
    {   next if $name eq 'Resent-Bcc' || $name eq 'Bcc';
        my $this = $known->{$name} or next;
        my @this = ref $this eq 'ARRAY' ? @$this : $this;
        $_->print($fh) foreach @this;
    }

    $fh->print("\n");
    $self;
}

sub toString()
{   my $self  = shift;
    my $known = $self->{MMH_fields};

    my @lines;
    foreach my $name (@{$self->{MMH_order}})
    {   my $this = $known->{$name} or next;
        my @this = ref $this eq 'ARRAY' ? @$this : $this;
        push @lines, $_->toString foreach @this;
    }

    push @lines, "\n";
    wantarray ? @lines : join('', @lines);
}

sub nrLines()
{   my $self = shift;
    my $nr   = 1;  # trailing

    foreach my $name ($self->names)
    {   $nr += $_->nrLines foreach $self->get($name);
    }

    $nr;
}

sub size()
{   my $self  = shift;
    my $bytes = 1;  # trailing blank
    foreach my $name ($self->names)
    {   $bytes += $_->size foreach $self->get($name);
    }
    $bytes;
}

sub timestamp() {shift->guessTimestamp || time}

sub guessTimestamp()
{   my $self = shift;
    return $self->{MMH_timestamp} if $self->{MMH_timestamp};

    my $stamp;
    if(my $date = $self->get('date'))
    {   $stamp = str2time($date, 'GMT');
    }

    unless($stamp)
    {   foreach (reverse $self->get('received'))
        {   $stamp = str2time($_, 'GMT');
            last if $stamp;
        }
    }

    $self->{MBM_timestamp} = $stamp;
}

sub guessBodySize()
{   my $self = shift;

    my $cl = $self->get('Content-Length');
    return $1 if defined $cl && $cl =~ m/(\d+)/;

    my $lines = $self->get('Lines');   # 40 chars per lines
    return $1 * 40   if defined $lines && $lines =~ m/(\d+)/;

    undef;
}

sub createFromLine()
{   my $self   = shift;

    my $from   = $self->get('from') || '';
    my $stamp  = $self->timestamp;
    my $sender = $from =~ m/\<.*?\>/ ? $& : 'unknown';
    "From $sender ".(gmtime $stamp)."\n";
}

my $unique_id = time;

sub createMessageId() { 'mailbox-'.$unique_id++ }

1;
