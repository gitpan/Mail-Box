use strict;
use warnings;

package Mail::Message;
use vars '$VERSION';
$VERSION = '2.049';
use base 'Mail::Reporter';

use Mail::Message::Part;
use Mail::Message::Head::Complete;
use Mail::Message::Construct;

use Mail::Message::Body::Lines;
use Mail::Message::Body::Multipart;
use Mail::Message::Body::Nested;

use Carp;


our $crlf_platform;
BEGIN { $crlf_platform = $^O =~ m/win32|cygwin/i }

#------------------------------------------


sub init($)
{   my ($self, $args) = @_;
    $self->SUPER::init($args);

    # Field initializations also in coerce()
    $self->{MM_modified}  = $args->{modified}  || 0;
    $self->{MM_trusted}   = $args->{trusted}   || 0;
    $self->{MM_labels}    = {};

    # Set the header

    my $head;
    if(defined($head = $args->{head})) { $self->head($head) }
    elsif(my $msgid = $args->{messageId} || $args->{messageID})
    {   $self->takeMessageId($msgid);
    }

    # Set the body
    if(my $body = $args->{body})
    {   $self->{MM_body} = $body;
        $body->message($self);
    }

    $self->{MM_body_type} = $args->{body_type}
       if defined $args->{body_type};

    $self->{MM_head_type} = $args->{head_type}
       if defined $args->{head_type};

    $self->{MM_field_type} = $args->{field_type}
       if defined $args->{field_type};

    my $labels = $args->{labels} || [];
    $self->{MM_labels} = { ref $labels eq 'ARRAY' ? @$labels : %$labels };

    $self;
}

#------------------------------------------


my $mail_internet_converter;
my $mime_entity_converter;

sub coerce($)
{   my ($class, $message) = @_;

    return bless $message, $class
        if $message->isa(__PACKAGE__);

    if($message->isa('MIME::Entity'))
    {   unless($mime_entity_converter)
        {   eval {require Mail::Message::Convert::MimeEntity};
                confess "Install MIME::Entity" if $@;

            $mime_entity_converter = Mail::Message::Convert::MailInternet->new;
        }

        $message = $mime_entity_converter->from($message)
            or return;
    }

    elsif($message->isa('Mail::Internet'))
    {   unless($mail_internet_converter)
        {   eval {require Mail::Message::Convert::MailInternet};
            confess "Install Mail::Internet" if $@;

            $mail_internet_converter = Mail::Message::Convert::MimeEntity->new;
        }

        $message = $mail_internet_converter->from($message)
            or return;
    }

    else
    {   my $what = ref $message ? 'a'.ref($message).' object' : 'text';
        confess "Cannot coerce $what into a ". __PACKAGE__." object.\n";
    }

    $message->{MM_modified}  ||= 0;

    bless $message, $class;
}

#------------------------------------------


sub clone()
{   my $self  = shift;

    # First clone body, which may trigger head load as well.  If head is
    # triggered first, then it may be decided to be lazy on the body at
    # moment.  And then the body would be triggered.

    my $clone = Mail::Message->new
     ( body  => $self->body->clone
     , head  => $self->head->clone
     , $self->logSettings
     );

    my %labels = %{$self->{MM_labels}};
    $clone->{MM_labels} = \%labels;
    $clone;
}

#------------------------------------------


sub messageId() { $_[0]->{MM_message_id} || $_[0]->takeMessageId}
sub messageID() {shift->messageId}   # compatibility

#------------------------------------------


sub container() { undef } # overridden by Mail::Message::Part

#------------------------------------------


sub isPart() { 0 } # overridden by Mail::Message::Part

#------------------------------------------


sub toplevel() { shift } # overridden by Mail::Message::Part

#------------------------------------------


sub isDummy() { 0 }

#------------------------------------------


sub print(;$)
{   my $self = shift;
    my $out  = shift || select;

    $self->head->print($out);
    $self->body->print($out);
    $self;
}

#------------------------------------------


sub write(;$)
{   my $self = shift;
    my $out  = shift || select;

    $self->head->print($out);
    $self->body->print($out);
    $self;
}

#------------------------------------------


my $default_mailer;

sub send(@)
{   my ($self, @options) = @_;

    require Mail::Transport::Send;

    my $mailer
       = (ref $_[0] && $_[0]->isa('Mail::Transport::Send')) ? shift
       : (!@options && defined $default_mailer)             ? $default_mailer
       : ($default_mailer = Mail::Transport::Send->new(@options));

    $self->log(ERROR => "No default mailer found to send message."), return
        unless defined $mailer;

    $mailer->send($self, @options);
}

#------------------------------------------


sub size()
{   my $self = shift;
    $self->head->size + $self->body->size;
}

#------------------------------------------


sub head(;$)
{   my $self = shift;
    return $self->{MM_head} unless @_;

    my $head = shift;
    unless(defined $head)
    {   delete $self->{MM_head};
        return undef;
    }

    $self->log(INTERNAL => "wrong type of head for $self")
        unless ref $head && $head->isa('Mail::Message::Head');

    $head->message($self);

    if(my $old = $self->{MM_head})
    {   $self->{MM_modified}++ unless $old->isDelayed;
    }

    $self->{MM_head} = $head;

    $self->takeMessageId unless $head->isDelayed;

    $head;
}

#------------------------------------------


sub get($)
{   my $field = shift->head->get(shift) || return undef;
    $field->body;
}

#------------------------------------------


sub study($)
{  my $head = shift->head or return;
   scalar $head->study(@_);    # return only last
}

#-------------------------------------------


sub from() { map {$_->addresses} shift->head->get('From') }

#-------------------------------------------


sub sender()
{   my $self   = shift;
    my $sender = $self->head->get('Sender') || $self->head->get('From')
               || return ();

    ($sender->addresses)[0];                 # first specified address
}

#-------------------------------------------


sub to() { map {$_->addresses} shift->head->get('To') }

#-------------------------------------------


sub cc() { map {$_->addresses} shift->head->get('Cc') }

#-------------------------------------------


sub bcc() { map {$_->addresses} shift->head->get('Bcc') }

#-------------------------------------------


sub date() { shift->head->get('Date') }

#-------------------------------------------


sub destinations()
{   my $self = shift;
    my %to = map { (lc($_->address) => $_) }
                  $self->to, $self->cc, $self->bcc;
    values %to;
}

#-------------------------------------------


sub subject()
{   my $subject = shift->get('subject');
    defined $subject ? $subject : '';
}

#-------------------------------------------


sub guessTimestamp() {shift->head->guessTimestamp}

#-------------------------------------------


sub timestamp() {shift->head->timestamp}

#------------------------------------------


sub nrLines()
{   my $self = shift;
    $self->head->nrLines + $self->body->nrLines;
}

#-------------------------------------------

  
sub body(;$@)
{   my $self = shift;
    return $self->{MM_body} unless @_;

    my $head = $self->head;
    $head->removeContentInfo if defined $head;

    my ($rawbody, %args) = @_;
    unless(defined $rawbody)
    {   # Disconnect body from message.
        my $body = delete $self->{MM_body};
        $body->message(undef) if defined $body;
        return $body;
    }

    $self->log(INTERNAL => "wrong type of body for $rawbody")
        unless ref $rawbody && $rawbody->isa('Mail::Message::Body');

    # Bodies of real messages must be encoded for safe transmission.
    # Message parts will get encoded on the moment the whole multipart
    # is transformed into a real message.
    my $body = $self->isPart ? $rawbody : $rawbody->encoded;
    $body->contentInfoTo($self->head);

    my $oldbody = $self->{MM_body};
    return $body if defined $oldbody && $body==$oldbody;

    $body->message($self);
    $body->modified(1) if defined $oldbody;

    $self->{MM_body} = $body;
}

#------------------------------------------


sub decoded(@)
{   my ($self, %args) = @_;

    return $self->{MB_decoded} if $self->{MB_decoded};

    my $body    = $self->body->load or return;
    my $decoded = $body->decoded(result_type => $args{result_type});

    $self->{MB_decoded} = $decoded if $args{keep};
    $decoded;
}

#------------------------------------------


sub encode(@)
{   my $body = shift->body->load;
    $body ? $body->encode(@_) : undef;
}

#-------------------------------------------


sub isMultipart() {shift->head->isMultipart}

#-------------------------------------------


sub isNested() {shift->body->isNested}

#-------------------------------------------


sub parts(;$)
{   my $self    = shift;
    my $what    = shift || 'ACTIVE';

    my $body    = $self->body;
    my $recurse = $what eq 'RECURSE' || ref $what;

    my @parts
     = $body->isNested     ? $body->nested->parts($what)
     : $body->isMultipart  ? $body->parts($recurse ? 'RECURSE' : ())
     :                       $self;

      ref $what eq 'CODE' ? (grep {$what->($_)} @parts)
    : $what eq 'ACTIVE'   ? (grep {not $_->isDeleted } @parts)
    : $what eq 'DELETED'  ? (grep { $_->isDeleted } @parts)
    : $what eq 'ALL'      ? @parts
    : $recurse            ? @parts
    : confess "Select parts via $what?";
}

#------------------------------------------


sub modified(;$)
{   my $self = shift;

    return $self->isModified unless @_;  # compatibility 2.036

    my $flag = shift;
    $self->{MM_modified} = $flag;
    my $head = $self->head;
    $head->modified($flag) if $head;
    my $body = $self->body;
    $body->modified($flag) if $body;

    $flag;
}

#------------------------------------------


sub isModified()
{   my $self = shift;
    return 1 if $self->{MM_modified};

    my $head = $self->head;
    if($head && $head->isModified)
    {   $self->{MM_modified}++;
        return 1;
    }

    my $body = $self->body;
    if($body && $body->isModified)
    {   $self->{MM_modified}++;
        return 1;
    }

    0;
}

#------------------------------------------


sub label($;$)
{   my $self   = shift;
    return $self->{MM_labels}{$_[0]} unless @_ > 1;
    my $return = $_[1];

    my %labels = @_;
    @{$self->{MM_labels}}{keys %labels} = values %labels;
    $return;
}

#------------------------------------------


sub labels()
{   my $self = shift;
    wantarray ? keys %{$self->{MM_labels}} : $self->{MM_labels};
}

#------------------------------------------


# needed for parts('ACTIVE'|'DELETED') on non-folder messages.
sub isDeleted() {0}

#-------------------------------------------


sub labelsToStatus()
{   my $self    = shift;
    my $head    = $self->head;
    my $labels  = $self->labels;

    my $status  = $head->get('status') || '';
    my $newstatus
      = $labels->{seen}    ? 'RO'
      : $labels->{old}     ? 'O'
      : '';

    $head->set(Status => $newstatus)
        if $newstatus ne $status;

    my $xstatus = $head->get('x-status') || '';
    my $newxstatus
      = ($labels->{replied} ? 'A' : '')
      . ($labels->{flagged} ? 'F' : '');

    $head->set('X-Status' => $newxstatus)
        if $newxstatus ne $xstatus;

    $self;
}

#-------------------------------------------


sub statusToLabels()
{   my $self    = shift;
    my $head    = $self->head;

    if(my $status  = $head->get('status'))
    {   $self->{MM_labels}{seen} = ($status  =~ /R/ ? 1 : 0);
        $self->{MM_labels}{old}  = ($status  =~ /O/ ? 1 : 0);
    }

    if(my $xstatus = $head->get('x-status'))
    {   $self->{MM_labels}{replied} = ($xstatus  =~ /A/ ? 1 : 0);
        $self->{MM_labels}{flagged} = ($xstatus  =~ /F/ ? 1 : 0);
    }

    $self;
}

#------------------------------------------


#------------------------------------------
# All next routines try to create compatibility with release < 2.0
sub isParsed()   { not shift->isDelayed }
sub headIsRead() { not shift->head->isa('Mail::Message::Delayed') }

#------------------------------------------


sub readFromParser($;$)
{   my ($self, $parser, $bodytype) = @_;

    my $head = $self->readHead($parser)
            || Mail::Message::Head::Complete->new
                 ( message     => $self
                 , field_type  => $self->{MM_field_type}
                 , $self->logSettings
                 );

    my $body = $self->readBody($parser, $head, $bodytype)
       or return;

    $self->head($head);
    $self->storeBody($body);
    $self;
}

#------------------------------------------


sub readHead($;$)
{   my ($self, $parser) = (shift, shift);

    my $headtype = shift
      || $self->{MM_head_type} || 'Mail::Message::Head::Complete';

    $headtype->new
      ( message     => $self
      , field_type  => $self->{MM_field_type}
      , $self->logSettings
      )->read($parser);
}

#------------------------------------------


my $mpbody = 'Mail::Message::Body::Multipart';
my $nbody  = 'Mail::Message::Body::Nested';
my $lbody  = 'Mail::Message::Body::Lines';

sub readBody($$;$$)
{   my ($self, $parser, $head, $getbodytype) = @_;

    my $bodytype
      = ! $getbodytype   ? ($self->{MM_body_type} || $lbody)
      : ref $getbodytype ? $getbodytype->($self, $head)
      :                    $getbodytype;

    my $body;
    if($bodytype->isDelayed)
    {   $body = $bodytype->new
          ( message           => $self
          , $self->logSettings
          );
    }
    else
    {   my $ct   = $head->get('Content-Type');
        my $type = defined $ct ? lc($ct->body) : 'text/plain';

        # Be sure you have acceptable bodies for multiparts and nested.
        if(substr($type, 0, 10) eq 'multipart/' && !$bodytype->isMultipart)
        {   $bodytype = $mpbody }
        elsif($type eq 'message/rfc822' && !$bodytype->isNested)
        {   $bodytype = $nbody  }

        $body = $bodytype->new
        ( message           => $self
        , checked           => $self->{MM_trusted}
        , $self->logSettings
        );
        $body->contentInfoFrom($head);
    }

    my $lines   = $head->get('Lines');
    my $size    = $head->guessBodySize;

    $body->read
      ( $parser, $head, $getbodytype,
      , $size, (defined $lines ? int $lines->body : undef)
      ) or return;
}

#------------------------------------------


sub storeBody($)
{   my ($self, $body) = @_;
    $self->{MM_body} = $body;
    $body->message($self);
    $body;
}

#-------------------------------------------


sub isDelayed()
{    my $body = shift->body;
     !$body || $body->isDelayed;
}

#------------------------------------------


sub takeMessageId(;$)
{   my $self  = shift;
    my $msgid = (@_ ? shift : $self->get('Message-ID')) || '';

    if($msgid =~ m/\<([^>]*)\>/s)
    {   $msgid = $1;
        $msgid =~ s/\s//gs;
    }
 
    $msgid = $self->head->createMessageId
        unless length $msgid;

    $self->{MM_message_id} = $msgid;
}

#------------------------------------------


sub shortSize(;$)
{   my $self = shift;
    my $size = shift;
    $size = $self->head->guessBodySize unless defined $size;

      !defined $size     ? '?'
    : $size < 1_000      ? sprintf "%3d "  , $size
    : $size < 10_000     ? sprintf "%3.1fK", $size/1024
    : $size < 1_000_000  ? sprintf "%3.0fK", $size/1024
    : $size < 10_000_000 ? sprintf "%3.1fM", $size/(1024*1024)
    :                      sprintf "%3.0fM", $size/(1024*1024);
}

#------------------------------------------


sub shortString()
{   my $self    = shift;
    my $subject = $self->head->get('subject') || '';
    chomp $subject;

    sprintf "%4s(%2d) %-30.30s", $self->shortSize, $subject;
}

#------------------------------------------


sub DESTROY()
{   my $self = shift;
    return if $self->inGlobalDestruction;

    $self->SUPER::DESTROY;
    $self->head(undef);
    $self->body(undef);
}

#------------------------------------------


sub destruct() { $_[0] = undef }

#------------------------------------------


1;
