use strict;

# file Mail::Message::Construct extends functionalities from Mail::Message

package Mail::Message;
our $VERSION = 2.021;  # Part of Mail::Box

use Mail::Message::Head::Complete;
use Mail::Message::Body::Lines;
use Mail::Message::Body::Multipart;

use Mail::Address;
use Carp;
use Scalar::Util 'blessed';
use IO::Lines;

sub read($@)
{   my ($class, $from) = (shift, shift);
    my ($filename, $file);
    my $ref       = ref $from;

    require IO::Scalar;
    require IO::ScalarArray;

    if(!$ref)
    {   $filename = 'scalar';
        $file     = IO::Scalar->new(\$from);
    }
    elsif($ref eq 'SCALAR')
    {   $filename = 'ref scalar';
        $file     = IO::Scalar->new($from);
    }
    elsif($ref eq 'ARRAY')
    {   $filename = 'array of lines';
        $file     = IO::ScalarArray->new($from);
    }
    elsif($ref eq 'GLOB')
    {   $filename = 'file (GLOB)';
        $file     = IO::ScalarArray->new( [ <$from> ] );
    }
    elsif($ref && $from->isa('IO::Handle'))
    {   $filename = 'file ('.ref($from).')';
        $file     = IO::ScalarArray->new( [ $from->getlines ] );
    }
    else
    {   croak "Cannot read from $from";
    }

    require Mail::Box::Parser::Perl;  # not parseable by C parser
    my $parser = Mail::Box::Parser::Perl->new
     ( filename  => $filename
     , file      => $file
     , trusted   => 1
     );

    my $self = $class->new(@_);
    $self->readFromParser($parser);
    $parser->stop;

    my $head = $self->head;
    $head->set('Message-ID' => $self->messageId)
        unless $head->get('Message-ID');

    $self;
}

# tests in t/55reply1r.t, demo in the examples/ directory

sub reply(@)
{   my ($self, %args) = @_;

    my $include  = $args{include}   || 'INLINE';
    my $strip    = !exists $args{strip_signature} || $args{strip_signature};
    my $body     = defined $args{body} ? $args{body} : $self->body;

    if($include eq 'NO')
    {   # Throw away real body.
        $body    = (ref $self)->new
           (data => ["\n[The original message is not included]\n\n"])
               unless defined $args{body};
    }
    elsif($include eq 'INLINE' || $include eq 'ATTACH')
    {   my @stripopts =
         ( pattern     => $args{strip_signature}
         , max_lines   => $args{max_signature}
         );

        my $decoded  = $body->decoded;
        $body        = $strip ? $decoded->stripSignature(@stripopts) : $decoded;

        if($body->isMultipart && $body->parts==1)
        {   $decoded = $body->part(0)->decoded;
            $body    = $strip ? $decoded->stripSignature(@stripopts) : $decoded;
        }

        if($include eq 'INLINE' && $body->isMultipart) { $include = 'ATTACH' }
        elsif($include eq 'INLINE' && $body->isBinary)
        {   $include = 'ATTACH';
            $body    = Mail::Message::Body::Multipart->new(parts => [$body]);
        }

        if($include eq 'INLINE')
        {   my $quote
              = defined $args{quote} ? $args{quote}
              : exists $args{quote}  ? undef
              :                        '> ';

            if(defined $quote)
            {   my $quoting = ref $quote ? $quote : sub {$quote . $_};
                $body = $body->foreachLine($quoting);
            }
        }
    }
    else
    {   $self->log(ERROR => "Cannot include source as $include.");
        return;
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
    unless(defined $to)
    {   my $reply = $mainhead->get('reply-to');
        $to       = [ $reply->addresses ] if defined $reply;
    }
    $to  ||= $self->from || return;

    # Add Cc
    my $cc = $args{Cc};
    if(!defined $cc && $args{group_reply})
    {   my @cc = $self->cc;
        $cc    = [ $self->cc ] if @cc;
    }

    # Add Bcc
    my $bcc = $args{Bcc};

    # Create a subject
    my $subject = $args{Subject};
    if(!defined $subject) { $subject = $self->replySubject($subject) }
    elsif(ref $subject)   { $subject = $subject->($subject) }

    # Create a nice message-id
    my $msgid   = $args{'Message-ID'};
    $msgid      = "<$msgid>" if $msgid && $msgid !~ /^\s*\<.*\>\s*$/;

    # Thread information
    my $origid  = '<'.$self->messageId.'>';
    my $refs    = $mainhead->get('references');

    # Prelude
    my $prelude
      = defined $args{prelude} ? $args{prelude}
      : exists $args{prelude}  ? undef
      :                          [ $self->replyPrelude($to) ];

    $prelude     = Mail::Message::Body->new(data => $prelude)
        if defined $prelude && ! blessed $prelude;

    my $postlude = $args{postlude};
    $postlude    = Mail::Message::Body->new(data => $postlude)
        if defined $postlude && ! blessed $postlude;

    #
    # Create the message.
    #

    my $total;
    if($include eq 'NO') {$total = $body}
    elsif($include eq 'INLINE')
    {   my $signature = $args{signature};
        $signature = $signature->body
           if defined $signature && $signature->isa('Mail::Message');

        $total = $body->concatenate
          ( $prelude, $body, $postlude
          , (defined $signature ? "-- \n" : undef), $signature
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
      , From    => $from || '(undisclosed)'
      , To      => $to
      , Subject => $subject
      , 'In-Reply-To' => $origid
      , References    => ($refs ? "$origid $refs" : $origid)
      );

    my $newhead = $reply->head;
    $newhead->set(Cc  => $cc)  if $cc;
    $newhead->set(Bcc => $args{Bcc}) if $args{Bcc};
    $newhead->set('Message-ID'  => $msgid || $newhead->createMessageId);

    # Ready

    $self->log(PROGRESS => 'Reply created from '.$origid);
    $self->label(replied => 1);
    $reply;
}

# tests in t/35reply1rs.t

sub replySubject($)
{   my ($thing, $subject) = @_;
    $subject     = 'your mail' unless defined $subject && length $subject;
    my @subject  = split /\:/, $subject;
    my $re_count = 1;

    # Strip multiple Re's from the start.

    while(@subject)
    {   last if $subject[0] =~ /[A-QS-Za-qs-z][A-DF-Za-df-z]/;

        for(shift @subject)
        {   while( /\bRe(?:\[\s*(\d+)\s*\]|\b)/g )
            {   $re_count += defined $1 ? $1 : 1;
            }
        }
    }

    # Strip multiple Re's from the end.

    if(@subject)
    {   for($subject[-1])
        {   $re_count++ while s/\s*\(\s*(re|forw)\W*\)\s*$//i;
        }
    }

    # Create the new subject string.

    my $text = (join ':', @subject) || 'your mail';
    for($text)
    {  s/^\s+//;
       s/\s+$//;
    }

    $re_count==1 ? "Re: $text" : "Re[$re_count]: $text";
}

sub replyPrelude($)
{   my ($self, $who) = @_;

    my $user
     = !ref $who                         ? (Mail::Address->parse($who))[0]
     : $who->isa('Mail::Message::Field') ? ($who->addresses)[0]
     :                                     $who;

    my $from      = ref $user && $user->isa('Mail::Address')
     ? $user->name : 'someone';

    my $time      = gmtime $self->timestamp;
    "On $time, $from wrote:\n";
}

# tests in t/57forw1f.t

sub forward(@)
{   my ($self, %args) = @_;

    my $include  = $args{include} || 'INLINE';
    my $strip    = !exists $args{strip_signature} || $args{strip_signature};
    my $body     = defined $args{body} ? $args{body} : $self->body;

    unless($include eq 'INLINE' || $include eq 'ATTACH')
    {   $self->log(ERROR => "Cannot include source as $include.");
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
    my $to = $args{To}
      or croak "No address to forwarded to";

    # Create a subject
    my $subject = $args{Subject};
    if(!defined $subject) { $subject = $self->forwardSubject($subject) }
    elsif(ref $subject)   { $subject = $subject->($subject) }

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
      , References  => ($refs ? "$origid $refs" : $origid)
      );

    my $newhead = $reply->head;
    $newhead->set(Cc   => $args{Cc}  ) if $args{Cc};
    $newhead->set(Bcc  => $args{Bcc} ) if $args{Bcc};
    $newhead->set(Date => $args{Date}) if $args{Date};
    $newhead->set('Message-ID' => $msgid || $newhead->createMessageId);

    # Ready

    $self->log(PROGRESS => 'Forward created from '.$origid);
    $reply;
}

# tests in t/57forw0s.t

sub forwardSubject($)
{   my ($self, $subject) = @_;
    defined $subject && length $subject ? "Forw: $subject" : "Forwarded";
}

sub forwardPrelude()
{   my $head  = shift->head;

    my @lines = "---- BEGIN forwarded message\n";
    my $r     = $head->isResent ? 'resent-' : '';
    my $from  = $head->get($r.'from');
    my $to    = $head->get($r.'to');
    my $cc    = $head->get($r.'cc');
    my $date  = $head->get($r.'date');

    push @lines, $from->toString if defined $from;
    push @lines,   $to->toString if defined $to;
    push @lines,   $cc->toString if defined $cc;
    push @lines, $date->toString if defined $date;
    push @lines, "\n";

    \@lines;
}

sub forwardPostlude()
{   my $self = shift;
    my @lines = ("---- END forwarded message\n");
    \@lines;
}

sub build(@)
{   my $class = shift;

    my $head  = Mail::Message::Head::Complete->new;
    my @parts = @_ % 2 ? shift : ();

    while(@_)
    {   my ($key, $value) = (shift, shift);
        if($key eq 'data')
        {   push @parts, Mail::Message::Body->new(data => $value) }
        elsif($key eq 'file')
        {   push @parts, Mail::Message::Body->new(file => $value) }
        elsif($key eq 'attach')
        {   push @parts, ref $value eq 'ARRAY' ? @$value : $value }
        elsif($key =~ m/^[A-Z]/)
        {   $head->add($key => $value) }
        else
        {   croak "Skipped unknown key $key in build." }
    }

    my $message = $class->new(head => $head);
    my $body    = @parts==1 ? $parts[0]
       : Mail::Message::Body::Multipart->new(parts => \@parts);

    $message->body($body->check);
    $message->statusToLabels;

    $message;
}

sub buildFromBody(@)
{   my ($class, $body) = (shift, shift);
    my @log     = $body->logSettings;

    my $head    = Mail::Message::Head::Complete->new(@log);
    while(@_)
    {   if(ref $_[0]) {$head->add(shift)}
        else          {$head->add(shift, shift)}
    }

    carp "From and To fields are obligatory"
        unless defined $head->get('From') && defined $head->get('To');

    $head->set(Date => Mail::Message::Field->toDate(localtime))
        unless defined $head->get('Date');

    my $message = $class->new
     ( head => $head
     , @log
     );

    $message->body($body->check);
    $message->statusToLabels;
    $message;
}

sub bounce(@)
{   my ($self, %args) = @_;

    my $bounce = $self->clone;
    my $head   = $bounce->head;

    my $date   = $args{Date} || Mail::Message::Field->toDate(localtime);

    $head->add('Resent-From' => $args{From}) if $args{From};
    $head->add('Resent-To'   => $args{To}  ) if $args{To};
    $head->add('Resent-Cc'   => $args{Cc}  ) if $args{Cc};
    $head->add('Resent-Bcc'  => $args{Bcc} ) if $args{Bcc};
    $head->add('Resent-Date' => $date);
    $head->add('Resent-Reply-To' => $args{'Reply-To'}) if $args{'Reply-To'};

    unless(defined $head->get('Resent-Message-ID'))
    {   my $msgid  = $args{'Message-ID'} || $head->createMessageId;
        $msgid = "<$msgid>" unless $msgid =~ m/\<.*\>/;
        $head->add('Resent-Message-ID' => $msgid);
    }

    $bounce;
}

sub string() { join '', shift->lines }

sub lines()
{   my $self = shift;
    my @lines;
    my $file = IO::Lines->new(\@lines);
    $self->print($file);
    @lines;
}

sub file()
{   my $self = shift;
    my @lines;
    my $file = IO::Lines->new(\@lines);
    $self->print($file);
    $file->setpos(0,0);
    $file;
}

sub printStructure(;$)
{   my $self    = shift;
    my $indent  = shift || '';

    my $subject = $self->get('Subject') || '';
    $subject = ": $subject" if length $subject;

    my $type    = $self->get('Content-Type') || '';
    my $size    = $self->size;
    print "$indent$type$subject ($size bytes)\n";

    my $body    = $self->body;
    my @parts
      = $body->isMultipart ? $body->parts
      : $body->isNested    ? ($body->nested)
      :                      ();

    $_->printStructure($indent.'   ') foreach @parts;
}

1;
