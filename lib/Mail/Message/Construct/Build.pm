
use strict;

package Mail::Message;
use vars '$VERSION';
$VERSION = '2.053';

use Mail::Message::Head::Complete;
use Mail::Message::Body::Lines;
use Mail::Message::Body::Multipart;
use Mail::Message::Field;

use Mail::Address;
use Carp;
use Scalar::Util 'blessed';
use IO::Lines;


sub build(@)
{   my $class = shift;

    my @parts
      = ! ref $_[0] ? ()
      : $_[0]->isa('Mail::Message')       ? shift
      : $_[0]->isa('Mail::Message::Body') ? shift
      :               ();

    my ($head, $type, @headerlines);
    while(@_)
    {   my $key = shift;
        if(ref $key && $key->isa('Mail::Message::Field'))
        {   if($key->name eq 'content-type') { $type = $key }
            else { push @headerlines, $key }
            next;
        }

        my $value = shift;
        next unless defined $value;

        my @data;

        if($key eq 'head')
        {   $head = $value }
        elsif($key eq 'data')
        {   @data = Mail::Message::Body->new(data => $value) }
        elsif($key eq 'file')
        {   @data = Mail::Message::Body->new(file => $value) }
        elsif($key eq 'files')
        {   @data = map {Mail::Message::Body->new(file => $_) } @$value }
        elsif($key eq 'attach')
        {   @data = ref $value eq 'ARRAY' ? @$value : $value }
        elsif(lc $key eq 'content-type')
        {   $type = Mail::Message::Field->new($key, $value) }
        elsif($key =~ m/^[A-Z]/)
        {   push @headerlines, $key, $value }
        else
        {   croak "Skipped unknown key $key in build." } 

        push @parts, grep {defined $_} @data if @data;
    }

    my $body
       = @parts==0 ? Mail::Message::Body::Lines->new()
       : @parts==1 ? $parts[0]
       : Mail::Message::Body::Multipart->new(parts => \@parts);

    # Setting the type explicitly, only after the body object is finalized
    $body->type($type) if defined $type;

    $class->buildFromBody($body, $head, @headerlines);
}

#------------------------------------------


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

    $message->body($body);

    # be sure the message-id is actually stored in the header.
    $head->add('Message-Id' => '<'.$message->messageId.'>')
        unless defined $head->get('message-id');

    $head->add(Date => Mail::Message::Field->toDate)
        unless defined $head->get('Date');

    $head->add('MIME-Version' => '1.0')  # required by rfc2045
        unless defined $head->get('MIME-Version');

    $message;
}

1;