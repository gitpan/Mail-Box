
use strict;

package Mail::Message;
use vars '$VERSION';
$VERSION = '2.048';

use Mail::Message::Body::Multipart;
use Mail::Message::Body::Nested;
use Scalar::Util 'blessed';


# tests in t/57forw1f.t

sub forward(@)
{   my $self    = shift;
    my %args    = @_;

    return $self->forwardNo(@_) if exists $args{body};

    my $include = $args{include} || 'INLINE';
    return $self->forwardInline(@_) if $include eq 'INLINE';

    # prelude and postlude are especially useful when the message
    # is INLINEd.  In all other cases, we would like to have one
    # preamble.  Let's create a preamble, it it is not present yet.

    my $preamble = $args{preamble};
    if(!defined $preamble)
    {   my $prelude = $args{prelude} || $self->forwardPrelude;
        $prelude    = Mail::Message::Body->new(data => $prelude)
            if defined $prelude && ! blessed $prelude;
        my @pieces  = ($prelude, [ "\n", "[Your message is attached]\n" ] );
 
        if(my $postlude = $args{postlude})
        {    $postlude = Mail::Message::Body->new(data => $postlude)
                 unless blessed $postlude;
             push @pieces, $postlude;
        }

        push @_, preamble => $prelude->concatenate(@pieces);
    }
    elsif(!ref $preamble)
    {   push @_, preamble => Mail::Message::Body->new(data => $preamble);
    }

    return $self->forwardAttach(@_)      if $include eq 'ATTACH';
    return $self->forwardEncapsulate(@_) if $include eq 'ENCAPSULATE';

    $self->log(ERROR => 'Cannot include forward source as $include.');
    undef;
}

#------------------------------------------


sub forwardNo(@)
{   my ($self, %args) = @_;

    my $body = $args{body};
    $self->log(INTERNAL => "No body supplied for forwardNo()")
       unless defined $body;

    #
    # Collect header info
    #

    my $mainhead = $self->toplevel->head;

    # Where it comes from
    my $from = $args{From};
    unless(defined $from)
    {   my @from = $self->to;
        $from    = \@from if @from;
    }

    # To whom to send
    my $to = $args{To};
    $self->log(ERROR => "No address to create forwarded to."), return
       unless $to;

    # Create a subject
    my $srcsub  = $args{Subject};
    my $subject
     = ! defined $srcsub ? $self->forwardSubject($self->subject)
     : ref $srcsub       ? $srcsub->($self->subject)
     :                     $srcsub;

    # Create a nice message-id
    my $msgid   = $args{'Message-ID'} || $mainhead->createMessageId;
    $msgid      = "<$msgid>" if $msgid && $msgid !~ /^\s*\<.*\>\s*$/;

    # Thread information
    my $origid  = '<'.$self->messageId.'>';
    my $refs    = $mainhead->get('references');

    my $forward = Mail::Message->buildFromBody
      ( $body
      , From        => ($from || '(undisclosed)')
      , To          => $to
      , Subject     => $subject
      , References  => ($refs ? "$refs $origid" : $origid)
      );

    my $newhead = $forward->head;
    $newhead->set(Cc   => $args{Cc}  ) if $args{Cc};
    $newhead->set(Bcc  => $args{Bcc} ) if $args{Bcc};
    $newhead->set(Date => $args{Date}) if $args{Date};

    # Ready

    $self->log(PROGRESS => "Forward created from $origid");
    $forward;
}

#------------------------------------------


sub forwardInline(@)
{   my ($self, %args) = @_;

    my $body     = $self->body;

    if($body->isMultipart)
    {   if($body->parts==1) { $body = $body->part(0) }
        else                { return $self->forwardAttach(%args) }
    }
    while($body->isNested)  { $body = $body->nested->body };

    return $self->forwardAttach(%args) if $body->isBinary;
    
    $body        = $body->decoded;
    my $strip    = (!exists $args{strip_signature} || $args{strip_signature})
                && !$body->isNested;

    $body        = $body->stripSignature
      ( pattern     => $args{strip_signature}
      , max_lines   => $args{max_signature}
      ) if $strip;

    if(defined(my $quote = $args{quote}))
    {   my $quoting = ref $quote ? $quote : sub {$quote . $_};
        $body = $body->foreachLine($quoting);
    }

    # Prelude
    my $prelude = exists $args{prelude} ? $args{prelude}
       : $self->forwardPrelude;

    $prelude     = Mail::Message::Body->new(data => $prelude)
        if defined $prelude && ! blessed $prelude;
 
    # Postlude
    my $postlude = exists $args{postlude} ? $args{postlude}
       : $self->forwardPostlude;

    $postlude    = Mail::Message::Body->new(data => $postlude)
        if defined $postlude && ! blessed $postlude;

    #
    # Create the message.
    #

    my $signature = $args{signature};
    $signature = $signature->body
        if defined $signature && $signature->isa('Mail::Message');

    my $composed  = $body->concatenate
      ( $prelude, $body, $postlude
      , (defined $signature ? "-- \n" : undef), $signature
      );

    $self->forwardNo(%args, body => $composed);
}

#------------------------------------------


sub forwardAttach(@)
{   my ($self, %args) = @_;

    my $body  = $self->body;
    my $strip = !exists $args{strip_signature} || $args{strip_signature};

    if($body->isMultipart)
    {   $body = $body->stripSignature if $strip;
        $body = $body->part(0)->body  if $body->parts == 1;
    }

    my $preamble = $args{preamble};
    $self->log(ERROR => 'forwardAttach requires a preamble object'), return
       unless ref $preamble;

    my @parts = ($preamble, $body);
    push @parts, $args{signature} if defined $args{signature};
    my $multi = Mail::Message::Body::Multipart->new(parts => \@parts);

    $self->forwardNo(%args, body => $multi);
}

#------------------------------------------


sub forwardEncapsulate(@)
{   my ($self, %args) = @_;

    my $preamble = $args{preamble};
    $self->log(ERROR => 'forwardEncapsulate requires a preamble object'), return
       unless ref $preamble;

    my $nested= Mail::Message::Body::Nested->new(nested => $self->clone);
    my @parts = ($preamble, $nested);
    push @parts, $args{signature} if defined $args{signature};

    my $multi = Mail::Message::Body::Multipart->new(parts => \@parts);

    $self->forwardNo(%args, body => $multi);
}

#------------------------------------------


# tests in t/57forw0s.t

sub forwardSubject($)
{   my ($self, $subject) = @_;
    defined $subject && length $subject ? "Forw: $subject" : "Forwarded";
}

#------------------------------------------


sub forwardPrelude()
{   my $head  = shift->head;

    my @lines = "---- BEGIN forwarded message\n";
    my $from  = $head->get('from');
    my $to    = $head->get('to');
    my $cc    = $head->get('cc');
    my $date  = $head->get('date');

    push @lines, $from->string if defined $from;
    push @lines,   $to->string if defined $to;
    push @lines,   $cc->string if defined $cc;
    push @lines, $date->string if defined $date;
    push @lines, "\n";

    \@lines;
}

#------------------------------------------


sub forwardPostlude()
{   my $self = shift;
    my @lines = ("---- END forwarded message\n");
    \@lines;
}

#------------------------------------------


#------------------------------------------
 
1;
