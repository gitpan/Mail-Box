
use strict;

package Mail::Message;
use vars '$VERSION';
$VERSION = '2.047';

use Mail::Message::Body::Multipart;
use Mail::Address;
use Scalar::Util 'blessed';


# tests in t/57forw1f.t

sub forward(@)
{   my ($self, %args) = @_;

    my $include  = $args{include} || 'INLINE';
    my $strip    = !exists $args{strip_signature} || $args{strip_signature};
    my $body     = defined $args{body} ? $args{body} : $self->body;

    unless($include eq 'INLINE' || $include eq 'ATTACH')
    {   $self->log(ERROR => "Cannot include forward source as $include.");
        return;
    }

    my @stripopts =
     ( pattern     => $args{strip_signature}
     , max_lines   => $args{max_signature}
     );

    my $decoded  = $body->decoded;
    $body        = $strip ? $decoded->stripSignature(@stripopts) : $decoded;

    if($body->isMultipart && $body->parts==1)
    {   $decoded = $body->part(0)->decoded;
        $body    = $strip ? $decoded->stripSignature(@stripopts) : $decoded;
    }

    if($include eq 'INLINE' && $body->isMultipart)
    {    $include = 'ATTACH' }
    elsif($include eq 'INLINE' && $body->isBinary)
    {   $include = 'ATTACH';
        $body    = Mail::Message::Body::Multipart->new(parts => [$body]);
    }

    if($include eq 'INLINE')
    {   if(defined(my $quote = $args{quote}))
        {   my $quoting = ref $quote ? $quote : sub {$quote . $_};
            $body = $body->foreachLine($quoting);
        }
    }

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

    my $total;
    if($include eq 'INLINE')
    {   my $signature = $args{signature};
        $signature = $signature->body
           if defined $signature && $signature->isa('Mail::Message');

        $total = $body->concatenate
          ( $prelude, $body, $postlude
          , (defined $signature ? "--\n" : undef), $signature
          );
    }
    if($include eq 'ATTACH')
    {
         my $intro = $prelude->concatenate
           ( $prelude
           , [ "\n", "[Your message is attached]\n" ]
           , $postlude
           );

        $total = Mail::Message::Body::Multipart->new
         ( parts => [ $intro, $body, $args{signature} ]
        );
    }

    my $msgtype = $args{message_type} || 'Mail::Message';

    my $reply   = $msgtype->buildFromBody
      ( $total
      , From        => $from || '(undisclosed)'
      , To          => $to
      , Subject     => $subject
      , References  => ($refs ? "$refs $origid" : $origid)
      );

    my $newhead = $reply->head;
    $newhead->set(Cc   => $args{Cc}  ) if $args{Cc};
    $newhead->set(Bcc  => $args{Bcc} ) if $args{Bcc};
    $newhead->set(Date => $args{Date}) if $args{Date};

    # Ready

    $self->log(PROGRESS => 'Forward created from '.$origid);
    $reply;
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
 
1;
