use strict;
use warnings;

package Mail::Message::Body::Multipart;
use vars '$VERSION';
$VERSION = '2.045';
use base 'Mail::Message::Body';

use Mail::Message::Body::Lines;
use Mail::Message::Part;

use Mail::Box::FastScalar;


#------------------------------------------

sub init($)
{   my ($self, $args) = @_;
    my $based = $args->{based_on};
    $args->{mime_type} ||=
        defined $based ? $based->mimeType : 'multipart/mixed';

    $self->SUPER::init($args);

    my @parts;
    if($args->{parts})
    {   foreach my $raw (@{$args->{parts}})
        {   next unless defined $raw;
            my $cooked = Mail::Message::Part->coerce($raw, $self);

            $self->log(ERROR => 'Data not convertible to a message (type is '
                      , ref $raw,")\n"), next unless defined $cooked;

            push @parts, $cooked;
        }
    }

    my $preamble = $args->{preamble};
    $preamble    = Mail::Message::Body->new(data => $preamble)
       if defined $preamble && ! ref $preamble;
    
    my $epilogue = $args->{epilogue};
    $epilogue    = Mail::Message::Body->new(data => $epilogue)
       if defined $epilogue && ! ref $epilogue;
    
    if($based)
    {   $self->boundary($args->{boundary} || $based->boundary);
        $self->{MMBM_preamble}
            = defined $preamble ? $preamble : $based->preamble;

        $self->{MMBM_parts}
            = @parts              ? \@parts
            : $based->isMultipart ? [ $based->parts('ACTIVE') ]
            : [];

        $self->{MMBM_epilogue}
            = defined $epilogue ? $epilogue : $based->epilogue;
    }
    else
    {   $self->boundary($args->{boundary} ||$self->type->attribute('boundary'));
        $self->{MMBM_preamble} = $preamble;
        $self->{MMBM_parts}    = \@parts;
        $self->{MMBM_epilogue} = $epilogue;
    }

    $self;
}

#------------------------------------------

sub isMultipart() {1}

#------------------------------------------

# A multipart body is never binary itself.  The parts may be.
sub isBinary() {0}

#------------------------------------------

sub clone()
{   my $self     = shift;
    my $preamble = $self->preamble;
    my $epilogue = $self->epilogue;

    my $body     = ref($self)->new
     ( $self->logSettings
     , based_on => $self
     , preamble => ($preamble ? $preamble->clone : undef)
     , epilogue => ($epilogue ? $epilogue->clone : undef)
     , parts    => [ map {$_->clone} $self->parts('ACTIVE') ]
     );

}

#------------------------------------------

sub nrLines()
{   my $self   = shift;
    my $nr     = 1;     # trailing boundary

    if(my $preamble = $self->preamble) { $nr += $preamble->nrLines }
    $nr += 2 + $_->nrLines foreach $self->parts('ACTIVE');
    if(my $epilogue = $self->epilogue) { $nr += $epilogue->nrLines }
    $nr;
}

#------------------------------------------

sub size()
{   my $self   = shift;
    my $bbytes = length($self->boundary) +3;

    my $bytes  = 0;
    if(my $preamble = $self->preamble) { $bytes += $preamble->size }
    $bytes     += $bbytes + 2;  # last boundary
    $bytes += $bbytes + 1 + $_->size foreach $self->parts('ACTIVE');
    if(my $epilogue = $self->epilogue) { $bytes += $epilogue->size }

    $bytes;
}

#------------------------------------------

sub string() { join '', shift->lines }

#------------------------------------------

sub lines()
{   my $self     = shift;

    my $boundary = $self->boundary;
    my @lines;

    my $preamble = $self->preamble;
    push @lines, $preamble->lines if $preamble;

    push @lines, "--$boundary\n", $_->lines
        foreach $self->parts('ACTIVE');

    push @lines, "\n--$boundary--\n";

    my $epilogue = $self->epilogue;
    push @lines, $epilogue->lines if $epilogue;

    wantarray ? @lines : \@lines;
}

#------------------------------------------

sub file()                    # It may be possible to speed-improve the next
{   my $self   = shift;       # code, which first produces a full print of
    my $text;                 # the message in memory...
    my $dump   = Mail::Box::FastScalar->new(\$text);
    $self->print($dump);
    $dump->seek(0,0);
    $dump;
}

#------------------------------------------

sub print(;$)
{   my $self = shift;
    my $out  = shift || select;

    my $boundary = $self->boundary;
    if(my $preamble = $self->preamble) { $preamble->print($out) }

    if(ref $out eq 'GLOB')
    {   foreach my $part ($self->parts('ACTIVE'))
        {   print $out "--$boundary\n";
            $part->print($out);
            print $out "\n";
        }
        print $out "--$boundary--\n";
    }
    else
    {   foreach my $part ($self->parts('ACTIVE'))
        {   $out->print("--$boundary\n");
            $part->print($out);
            $out->print("\n");
        }
        $out->print("--$boundary--\n");
    }

    if(my $epilogue = $self->epilogue) { $epilogue->print($out) }

    $self;
}

#------------------------------------------

sub printEscapedFrom($)
{   my ($self, $out) = @_;

    my $boundary = $self->boundary;
    if(my $preamble = $self->preamble) { $preamble->printEscapedFrom($out) }

    if(ref $out eq 'GLOB')
    {   foreach my $part ($self->parts('ACTIVE'))
        {   print $out "--$boundary\n";
            $part->printEscapedFrom($out);
            print $out "\n";
        }
        print $out "--$boundary--\n";
    }
    else
    {   foreach my $part ($self->parts('ACTIVE'))
        {   $out->print("--$boundary\n");
            $part->printEscapedFrom($out);
            $out->print("\n");
        }
        $out->print("--$boundary--\n");
    }

    if(my $epilogue = $self->epilogue) { $epilogue->printEscapedFrom($out) }

    $self;
}

#------------------------------------------

sub check()
{   my $self = shift;
    $self->foreachComponent( sub {$_[1]->check} );
}

#------------------------------------------

sub encode(@)
{   my ($self, %args) = @_;
    $self->foreachComponent( sub {$_[1]->encode(%args)} );
}

#------------------------------------------

sub encoded()
{   my $self = shift;
    $self->foreachComponent( sub {$_[1]->encoded} );
}

#------------------------------------------

sub read($$$$)
{   my ($self, $parser, $head, $bodytype) = @_;

    my $boundary = $self->boundary;

    $parser->pushSeparator("--$boundary");
    my @msgopts  = ($self->logSettings);

    my @sloppyopts = 
      ( mime_type         => 'text/plain'
      , transfer_encoding => ($head->get('Content-Transfer-Encoding') || undef)
      );

    # Get preamble.
    my $headtype = ref $head;

    my $begin    = $parser->filePosition;
    my $preamble = Mail::Message::Body::Lines->new(@msgopts, @sloppyopts)
       ->read($parser, $head);

    $self->{MMBM_preamble} = $preamble if defined $preamble;

    # Get the parts.

    my @parts;
    while(my $sep = $parser->readSeparator)
    {   last if $sep eq "--$boundary--\n";

        my $part = Mail::Message::Part->new
         ( @msgopts
         , container => $self
         );

        last unless $part->readFromParser($parser, $bodytype);
        push @parts, $part;
    }
    $self->{MMBM_parts} = \@parts;

    # Get epilogue

    $parser->popSeparator;
    my $epilogue = Mail::Message::Body::Lines->new(@msgopts, @sloppyopts)
        ->read($parser, $head);

    $self->{MMBM_epilogue} = $epilogue if defined $epilogue;
    my $end = defined $epilogue ? ($epilogue->fileLocation)[1]
            : @parts            ? ($parts[-1]->fileLocation)[1]
            : defined $preamble ? ($preamble->fileLocation)[1]
            :                      $begin;

    $self->fileLocation($begin, $end);

    $self;
}

#------------------------------------------


sub foreachComponent($)
{   my ($self, $code) = @_;
    my $changes  = 0;

    my $new_preamble;
    if(my $preamble = $self->preamble)
    {   $new_preamble = $code->($self, $preamble);
        $changes++ unless $preamble == $new_preamble;
    }

    my $new_epilogue;
    if(my $epilogue = $self->epilogue)
    {   $new_epilogue = $code->($self, $epilogue);
        $changes++ unless $epilogue == $new_epilogue;
    }

    my @new_bodies;
    foreach my $part ($self->parts('ACTIVE'))
    {   my $part_body = $part->body;
        my $new_body  = $code->($self, $part_body);

        $changes++ if $new_body != $part_body;
        push @new_bodies, [$part, $new_body];
    }

    return $self unless $changes;

    my @new_parts;
    foreach (@new_bodies)
    {   my ($part, $body) = @$_;
        my $new_part = Mail::Message::Part->new
           ( head      => $part->head->clone,
             container => undef
           );
        $new_part->body($body);
        push @new_parts, $new_part;
    }

    my $constructed = (ref $self)->new
      ( preamble => $new_preamble
      , parts    => \@new_parts
      , epilogue => $new_epilogue
      , based_on => $self
      );

    $_->container($constructed)
       foreach @new_parts;

    $constructed;
}

#------------------------------------------


sub attach(@)
{   my $self  = shift;
    my $new   = ref($self)->new
      ( based_on => $self
      , parts    => [$self->parts, @_]
      );
}

#-------------------------------------------


sub stripSignature(@)
{   my $self  = shift;

    my @allparts = $self->parts;
    my @parts    = grep {$_->body->mimeType->isSignature} @allparts;

    @allparts==@parts ? $self
    : (ref $self)->new(based_on => $self, parts => \@parts);
}

#------------------------------------------


sub preamble() {shift->{MMBM_preamble}}

#------------------------------------------


sub epilogue() {shift->{MMBM_epilogue}}

#------------------------------------------


sub parts(;$)
{   my $self  = shift;
    return @{$self->{MMBM_parts}} unless @_;

    my $what  = shift;
    my @parts = @{$self->{MMBM_parts}};

      $what eq 'RECURSE' ? (map {$_->parts('RECURSE')} @parts)
    : $what eq 'ALL'     ? @parts
    : $what eq 'DELETED' ? (grep {$_->isDeleted} @parts)
    : $what eq 'ACTIVE'  ? (grep {not $_->isDeleted} @parts)
    : ref $what eq 'CODE'? (grep {$what->($_)} @parts)
    : ($self->log(ERROR => "Unknown criterium $what to select parts."), return ());
}

#-------------------------------------------


sub part($) { shift->{MMBM_parts}[shift] }

#-------------------------------------------


my $unique_boundary = time;

sub boundary(;$)
{   my $self  = shift;
    my $mime  = $self->type;

    unless(@_)
    {   my $boundary = $mime->attribute('boundary');
        return $boundary if defined $boundary;
    }

    my $boundary = @_ && defined $_[0] ? (shift) : "boundary-".$unique_boundary++;
    $self->type->attribute(boundary => $boundary);
}

#-------------------------------------------


1;
