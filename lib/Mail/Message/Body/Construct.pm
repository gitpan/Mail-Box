use strict;
use warnings;

# Mail::Message::Body::Construct adds functionality to Mail::Message::Body

package Mail::Message::Body;
use vars '$VERSION';
$VERSION = '2.062';

use Carp;
use Mail::Message::Body::String;
use Mail::Message::Body::Lines;


sub foreachLine($)
{   my ($self, $code) = @_;
    my $changes = 0;
    my @result;

    foreach ($self->lines)
    {   my $becomes = $code->();
        if(defined $becomes)
        {   push @result, $becomes;
            $changes++ if $becomes ne $_;
        }
        else {$changes++}
     }
      
     return $self unless $changes;

     ref($self)->new
      ( based_on => $self
      , data     => \@result
      );
}

#------------------------------------------


sub concatenate(@)
{   my $self = shift;

    my @bodies;
    foreach (@_)
    {   next unless defined $_;
        push @bodies
         , !ref $_           ? Mail::Message::Body::String->new(data => $_)
         : ref $_ eq 'ARRAY' ? Mail::Message::Body::Lines->new(data => $_)
         : $_->isa('Mail::Message')       ? $_->body
         : $_->isa('Mail::Message::Body') ? $_
         : carp "Cannot concatenate element ".@bodies;
    }

    my @unified;

    my $changes  = 0;
    foreach my $body (@bodies)
    {   my $unified = $self->unify($body);
        if(defined $unified)
        {   $changes++ unless $unified==$body;
            push @unified, $unified;
        }
        elsif($body->mimeType->mediaType eq 'text')
        {   # Text stuff can be unified anyhow, although we do not want to
            # include postscript or such.
            push @unified, $body;
        }
        else { $changes++ }
    }

    return $self if @bodies==1 && $bodies[0]==$self;  # unmodified, and single

    ref($self)->new
      ( based_on => $self
      , data     => [ map {$_->lines} @unified ]
      );
}

#------------------------------------------


sub attach(@)
{   my $self  = shift;

    my @parts;
    push @parts, shift while @_ && ref $_[0];

    return $self unless @parts;
    unshift @parts,
      ( $self->isNested    ? $self->nested
      : $self->isMultipart ? $self->parts
      : $self
      );

    return $parts[0] if @parts==1;
    Mail::Message::Body::Multipart->new(parts => \@parts, @_);
}

#------------------------------------------


# tests in t/51stripsig.t

sub stripSignature($@)
{   my ($self, %args) = @_;

    return $self if $self->mimeType->isBinary;

    my $pattern = !defined $args{pattern} ? qr/^--\s?$/
                : !ref $args{pattern}     ? qr/^\Q${args{pattern}}/
                :                           $args{pattern};
 
    my $lines   = $self->lines;   # no copy!
    my $stop    = defined $args{max_lines}? @$lines - $args{max_lines}
                : exists $args{max_lines} ? 0 
                :                           @$lines-10;

    $stop = 0 if $stop < 0;
    my ($sigstart, $found);
 
    if(ref $pattern eq 'CODE')
    {   for($sigstart = $#$lines; $sigstart >= $stop; $sigstart--)
        {   next unless $pattern->($lines->[$sigstart]);
            $found = 1;
            last;
        }
    }
    else
    {   for($sigstart = $#$lines; $sigstart >= $stop; $sigstart--)
        {   next unless $lines->[$sigstart] =~ $pattern;
            $found = 1;
            last;
        }
    }
 
    return $self unless $found;
 
    my $bodytype = $args{result_type} || ref $self;

    my $stripped = $bodytype->new
      ( based_on => $self
      , data     => [ @$lines[0..$sigstart-1] ]
      );

    return $stripped unless wantarray;

    my $sig      = $bodytype->new
      ( based_on => $self
      , data     => [ @$lines[$sigstart..$#$lines] ]
      );
      
    ($stripped, $sig);
}

#------------------------------------------

1;
