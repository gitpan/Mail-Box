use strict;
use warnings;

package Mail::Message::Head::Complete;
our $VERSION = 2.034;  # Part of Mail::Box
use base 'Mail::Message::Head';

use Mail::Box::Parser;

use Carp;
use Scalar::Util 'weaken';
use List::Util 'sum';

sub isDelayed() {0}

sub clone(;@)
{   my $self   = shift;
    my $copy   = ref($self)->new($self->logSettings);

    $copy->addNoRealize($_->clone) foreach $self->orderedFields;
    $copy->modified(1);
    $copy;
}

sub add(@)
{   my $self = shift;

    # Create object for this field.

    my $field
      = @_==1 && ref $_[0] ? shift     # A fully qualified field is added.
      : ($self->{MMH_field_type} || 'Mail::Message::Field::Fast')->new(@_);

    $field->setWrapLength;

    # Put it in place.

    my $known = $self->{MMH_fields};
    my $name  = $field->name;  # is already lower-cased

    $self->addOrderedFields($field);

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
    $self->{MMH_modified}++;

    # Create object for this field.
    my $field = @_==1 && ref $_[0] ? shift->clone : $type->new(@_);

    my $name  = $field->name;         # is already lower-cased
    my $known = $self->{MMH_fields};

    # Internally, non-existing content-info are in the body stored as 'none'
    # The header will not contain these lines.

    if($skip_none{$name} && $field->body eq 'none')
    {   delete $known->{$name};
        return $field;
    }

    $field->setWrapLength;
    $known->{$name} = $field;

    $self->addOrderedFields($field);
    $field;
}

sub reset($@)
{   my ($self, $name) = (shift, lc shift);

    my $known = $self->{MMH_fields};

    if(@_==0)
    {   $self->{MMH_modified}++ if delete $known->{$name};
        return ();
    }

    $self->{MMH_modified}++;

    # Cloning required, otherwise double registrations will not be
    # removed from the ordered list: that's controled by 'weaken'

    my @fields = map {$_->clone} @_;

    if(@_==1) { $known->{$name} = $fields[0] }
    else      { $known->{$name} = [@fields]  }

    $self->addOrderedFields(@fields);
    $self;
}

sub delete($) { $_[0]->reset($_[1]) }

sub removeField($)
{   my ($self, $field) = @_;
    my $name = $field->name;

    my $known = $self->{MMH_fields};

    if(!defined $known->{$name})
    { ; }  # complain
    elsif(ref $known->{$name} eq 'ARRAY')
    {    for(my $i=0; $i < @{$known->{$name}}; $i++)
         {
             return splice @{$known->{$name}}, $i, 1
                 if $known->{$name}[$i] eq $field;
         }
    }
    elsif($known->{$name} eq $field)
    {    return delete $known->{$name};
    }

    $self->log(WARNING =>
        "Could not remove field $name from header: not found.");

    return;
}

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
    {   # I love this trick:
        local $" = ')|(?:';
        $take    = qr/^(?:(?:@take))/i;
    }

    grep {$_->Name =~ $take} $self->orderedFields;
}

sub print(;$)
{   my $self  = shift;
    my $fh    = shift || select;

    $_->print($fh)
        foreach $self->orderedFields;

    $fh->print("\n");

    $self;
}

sub printUndisclosed($)
{   my ($self, $fh) = @_;

    $_->print($fh)
       foreach grep {$_->toDisclose} $self->orderedFields;

    $fh->print("\n");

    $self;
}

sub toString() {shift->string}
sub string()
{   my $self  = shift;

    my @lines = map {$_->string} $self->orderedFields;
    push @lines, "\n";

    wantarray ? @lines : join('', @lines);
}

sub nrLines() { sum 1, map { $_->nrLines } shift->orderedFields }

sub size() { sum 1, map {$_->size} shift->orderedFields }

sub timestamp() {shift->guessTimestamp || time}

sub guessTimestamp()
{   my $self = shift;
    return $self->{MMH_timestamp} if $self->{MMH_timestamp};

    my $stamp;
    if(my $date = $self->get('date'))
    {   $stamp = Mail::Message::Field->dateToTimestamp($date);
    }

    unless($stamp)
    {   foreach (reverse $self->get('received'))
        {   $stamp = Mail::Message::Field->dateToTimestamp($_->comment);
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

sub resentGroups()
{   my $self = shift;
    my (@groups, $return_path, $delivered_to, @fields);
    require Mail::Message::Head::ResentGroup;

    foreach my $field ($self->orderedFields)
    {   my $name = $field->name;
        if($name eq 'return-path')              { $return_path = $field }
        elsif($name eq 'delivered-to')          { $delivered_to = $field }
        elsif(substr($name, 0, 7) eq 'resent-') { push @fields, $field }
        elsif($name eq 'received')
        {   push @groups, Mail::Message::Head::ResentGroup->new
               (@fields, head => $self)
                   if @fields;

            @fields = $field;
            unshift @fields, $delivered_to if defined $delivered_to;
            undef $delivered_to;

            unshift @fields, $return_path  if defined $return_path;
            undef $return_path;
        }
    }

    push @groups, Mail::Message::Head::ResentGroup->new(@fields, head => $self)
          if @fields;

    @groups;
}

sub addResentGroup(@)
{   my $self  = shift;

    require Mail::Message::Head::ResentGroup;
    my $rg = @_==1 ? (shift)
      : Mail::Message::Head::ResentGroup->new(@_, head => $self);

    my @fields = $rg->orderedFields;
    my $order  = $self->{MMH_order};

    my $i;
    for($i=0; $i < @$order; $i++)
    {   next unless defined $order->[$i];
        last if $order->[$i]->name =~ m!^(?:received|return-path|resent-)!;
    }

    my $known = $self->{MMH_fields};
    while(@fields)
    {   my $f    = pop @fields;
        splice @$order, $i, 0, $f;
        weaken( $order->[$i] );
        my $name = $f->name;

        # Adds *before* in the list.
           if(!defined $known->{$name})      {$known->{$name} = $f}
        elsif(ref $known->{$name} eq 'ARRAY'){unshift @{$known->{$name}},$f}
        else                       {$known->{$name} = [$f, $known->{$name}]}
    }

    $self->modified(1);
    $rg;
}

sub createFromLine()
{   my $self   = shift;

    my $from   = $self->get('from') || '';
    my $stamp  = $self->timestamp;
    my $sender = $from =~ m/\<.*?\>/ ? $& : 'unknown';
    "From $sender ".(gmtime $stamp)."\n";
}

my $unique_id     = time;

sub createMessageId() { shift->messageIdPrefix . '-' . $unique_id++ }

our $unique_prefix;

sub messageIdPrefix(;$)
{   my $self = shift;
    return $unique_prefix if !@_ && defined $unique_prefix;

    my $prefix = shift;
    unless(defined $prefix)
    {   require Sys::Hostname;
        $prefix = 'mailbox-'.Sys::Hostname::hostname().'-'.$$;
    }

    $unique_prefix = $prefix;
}

1;
