use strict;

# file Mail::Message::Construct extends functionalities from Mail::Message

package Mail::Message;
our $VERSION = 2.037;  # Part of Mail::Box

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

    $self->statusToLabels;
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
    {   $self->log(ERROR => "Cannot include reply source as $include.");
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
    $to  ||= $self->sender || return;

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

    my $from
     = ref $user && $user->isa('Mail::Address')
     ? ($user->name || $user->address || $user->format)
     : 'someone';

    my $time = gmtime $self->timestamp;
    "On $time, $from wrote:\n";
}

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

sub forwardPostlude()
{   my $self = shift;
    my @lines = ("---- END forwarded message\n");
    \@lines;
}

sub build(@)
{   my $class = shift;

    my @parts
      = ! ref $_[0] ? ()
      : $_[0]->isa('Mail::Message')       ? shift
      : $_[0]->isa('Mail::Message::Body') ? shift
      :               ();

    my ($head, @headerlines);
    while(@_)
    {   my $key = shift;
        if(ref $key && $key->isa('Mail::Message::Field'))
        {   push @headerlines, $key;
            next;
        }

        my $value = shift;
        if($key eq 'head')
        {   $head = $value }
        elsif($key eq 'data')
        {   push @parts, Mail::Message::Body->new(data => $value) }
        elsif($key eq 'file')
        {   push @parts, Mail::Message::Body->new(file => $value) }
        elsif($key eq 'files')
        {   push @parts, map {Mail::Message::Body->new(file => $_) } @$value }
        elsif($key eq 'attach')
        {   push @parts, ref $value eq 'ARRAY' ? @$value : $value }
        elsif($key =~ m/^[A-Z]/)
        {   push @headerlines, $key, $value }
        else
        {   croak "Skipped unknown key $key in build." }
    }

    my $body
       = @parts==0 ? Mail::Message::Body::Lines->new()
       : @parts==1 ? $parts[0]
       : Mail::Message::Body::Multipart->new(parts => \@parts);

    $class->buildFromBody($body, $head, @headerlines);
}

sub buildFromBody(@)
{   my ($class, $body) = (shift, shift);
    my @log     = $body->logSettings;

    my $head;
    if(ref $_[0] && $_[0]->isa('Mail::Message::Head')) { $head = shift }
    else
    {   shift unless defined $_[0];   # undef as head
        $head = Mail::Message::Head::Complete->new(@log);
    }

    while(@_)
    {   if(ref $_[0]) {$head->add(shift)}
        else          {$head->add(shift, shift)}
    }

    my $message = $class->new
     ( head => $head
     , @log
     );

    $message->body($body->check);
    $message->statusToLabels;

    # be sure the mesasge-id is actually stored in the header.
    $head->add('Message-Id' => '<'.$message->messageId.'>')
        unless defined $head->get('message-id');

    $head->add(Date => Mail::Message::Field->toDate)
        unless defined $head->get('Date');

    $head->add('MIME-Version' => '1.0')  # required by rfc2045
        unless defined $head->get('MIME-Version');

    $message;
}

sub bounce(@)
{   my $self   = shift;
    my $bounce = $self->clone;
    my $head   = $bounce->head;

    if(@_==1 && ref $_[0] && $_[0]->isa('Mail::Message::Head::ResentGroup' ))
    {    $head->addResentGroup(shift);
         return $bounce;
    }

    my @rgs    = $head->resentGroups;  # No groups yet, then require Received
    my $rg     = $rgs[0];

    if(defined $rg)
    {   $rg->delete;     # Remove group to re-add it later: others field order
        while(@_)        #  in header would be disturbed.
        {   my $field = shift;
            ref $field ? $rg->set($field) : $rg->set($field, shift);
        }
    }
    else
    {   $rg = Mail::Message::Head::ResentGroup->new(@_, head => $head);
    }

    #
    # Add some nice extra fields.
    #

    $rg->set(Date => Mail::Message::Field->toDate)
        unless defined $rg->date;

    unless(defined $rg->messageId)
    {   my $msgid = $head->createMessageId;
        $rg->set('Message-ID' => "<$msgid>");
    }

    $head->addResentGroup($rg);
    $bounce;
}

sub string()
{   my $self = shift;
    $self->head->string . $self->body->string;
}

sub lines()
{   my $self = shift;
    my @lines;
    my $file = IO::Lines->new(\@lines);
    $self->print($file);
    wantarray ? @lines : \@lines;
}

sub file()
{   my $self = shift;
    my @lines;
    my $file = IO::Lines->new(\@lines);
    $self->print($file);
    $file->setpos(0,0);
    $file;
}

sub printStructure(;$$)
{   my $self    = shift;
    my $indent  = @_ && !ref $_[-1] && substr($_[-1], -1, 1) eq ' ' ? pop : '';
    my $fh      = @_ ? shift : select;

    my $subject = $self->get('Subject') || '';
    $subject    = ": $subject" if length $subject;

    my $type    = $self->get('Content-Type') || '';
    my $size    = $self->size;
    my $deleted = $self->can('isDeleted') && $self->isDeleted ? ', deleted' : '';

    $fh->print("$indent$type$subject ($size bytes$deleted)\n");

    my $body    = $self->body;
    my @parts
      = $body->isMultipart ? $body->parts
      : $body->isNested    ? ($body->nested)
      :                      ();

    $_->printStructure($fh, $indent.'   ') foreach @parts;
}

1;
