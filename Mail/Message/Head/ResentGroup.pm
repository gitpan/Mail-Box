
use strict;

package Mail::Message::Head::ResentGroup;
use vars '$VERSION';
$VERSION = '2.041';
use base 'Mail::Reporter';

use Scalar::Util 'weaken';
use Mail::Message::Field::Fast;

use Sys::Hostname;


my @ordered_field_names = qw/return_path delivered_to received date from
  sender to cc bcc message_id/;


sub new(@)
{   my $class = shift;

    my @fields;
    push @fields, shift while ref $_[0];

    $class->SUPER::new(@_, fields => \@fields);
}

sub init($$)
{   my ($self, $args) = @_;
    $self->SUPER::init($args);

    $self->set($_)                     # add specified object fields
        foreach @{$args->{fields}};

    $self->set($_, $args->{$_})        # add key-value paired fields
        foreach grep m/^[A-Z]/, keys %$args;

    my $head = $self->{MMHR_head} = $args->{head};
    $self->log(ERROR => "Message header required for creation of ResentGroup.")
       unless defined $head;

    weaken( $self->{MMHR_head} );

    $self->createReceived unless defined $self->{MMHR_received};
    $self;
}

#------------------------------------------


#------------------------------------------


sub delete()
{   my $self   = shift;
    my $head   = $self->{MMHR_head};
    my @fields = grep {ref $_ && $_->isa('Mail::Message::Field')}
                     values %$self;

    $head->removeField($_) foreach @fields;
    $self;
}


sub orderedFields()
{   my $self   = shift;
    map { $self->{ "MMHR_$_" } || () } @ordered_field_names;
}

#-------------------------------------------


sub print(;$)
{   my $self = shift;
    my $fh   = shift || select;
    $_->print($fh) foreach $self->orderedFields;
}

#------------------------------------------


sub set($$)
{   my $self  = shift;

    my ($field, $name, $value);
    if(@_==1) { $field = shift }
    else
    {   my ($fn, $value) = @_;
        $name  = $fn =~ m!^(received|return\-path|delivered\-to|resent\-\w*)$!i ? $fn
               : "Resent-$fn";

        $field = Mail::Message::Field::Fast->new($name, $value);
    }

    $name = $field->name;
    $name =~ s/^resent\-//;
    $name =~ s/\-/_/g;
    $self->{ "MMHR_$name" } = $field;
}

#------------------------------------------


sub returnPath() { shift->{MMHR_return_path} }

#------------------------------------------


sub deliveredTo() { shift->{MMHR_delivered_to} }

#------------------------------------------


sub received() { shift->{MMHR_received} }

#------------------------------------------


sub receivedTimestamp()
{   my $received = shift->{MMHR_received} or return;
    my $comment  = $received->comment or return;
    Mail::Message::Field->dateToTimestamp($comment);
}

#------------------------------------------


sub date($) { shift->{MMHR_date} }

#------------------------------------------


sub dateTimestamp()
{   my $date = shift->{MMHR_date} or return;
    Mail::Message::Field->dateToTimestamp($date);
}

#------------------------------------------


sub from()
{   my $from = shift->{MMHR_from} or return ();
    wantarray ? $from->addresses : $from;
}

#------------------------------------------


sub sender()
{   my $sender = shift->{MMHR_sender} or return ();
    wantarray ? $sender->addresses : $sender;
}

#------------------------------------------


sub to()
{   my $to = shift->{MMHR_to} or return ();
    wantarray ? $to->addresses : $to;
}

#------------------------------------------


sub cc()
{   my $cc = shift->{MMHR_cc} or return ();
    wantarray ? $cc->addresses : $cc;
}

#------------------------------------------


sub bcc()
{   my $bcc = shift->{MMHR_bcc} or return ();
    wantarray ? $bcc->addresses : $bcc;
}

#------------------------------------------


sub destinations()
{   my $self = shift;
    ($self->to, $self->cc, $self->bcc);
}

#------------------------------------------


sub messageId() { shift->{MMHR_message_id} }

#------------------------------------------


my $unique_received_id = 'rc'.time;

sub createReceived()
{   my $self   = shift;
    my $head   = $self->{MMHR_head};
    my $sender = $head->message->sender;

    my $received
      = 'from ' . $sender->format
      . ' by '  . hostname
      . ' with SMTP'
      . ' id '  . $unique_received_id++
      . ' for ' . $head->get('To')  # may be wrong
      . '; '. Mail::Message::Field->toDate;

    $self->set(Received => $received);
}

#-------------------------------------------


1;
