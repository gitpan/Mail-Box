
use strict;

package Mail::Message;
use vars '$VERSION';
$VERSION = '2.042';

use Mail::Message::Head::Complete;
use Mail::Message::Body::Lines;
use Mail::Message::Body::Multipart;

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
    $message->statusToLabels;

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
