use strict;

package Mail::Message::Head::ResentGroup;
our $VERSION = 2.024;  # Part of Mail::Box
use base 'Mail::Reporter';

use Scalar::Util 'weaken';
use Mail::Message::Field::Fast;

my @ordered_field_names = qw/return_path received date from sender to
  cc bcc message_id/;

sub new(@)
{   my $class = shift;

    my @fields;
    push @fields, shift while ref $_[0];

    $class->SUPER::new(@_, fields => \@fields);
}

sub init($$)
{   my ($self, $args) = @_;
    $self->SUPER::init($args);

    my @fields = @{$args->{fields}};
    foreach my $name (grep m!^[A-Z]!, keys %$args)
    {   my $fn = $name =~ m!^(received|return\-path|resent\-\w*)$!i ? $name
               : "Resent-$name";

        push @fields, Mail::Message::Field::Fast->new($fn, $args->{$name});
    }

    foreach my $field (@fields)
    {   my $name = $field->name;
        $name =~ s/^resent\-//;
        $name =~ s/\-/_/g;
        $self->{ "MMHR_$name" } = $field;
    }

    my $head = $self->{MMHR_head} = $args->{head};
    $self->log(INTERNAL => "Message header required for ResentGroup")
       unless defined $head;

    weaken( $self->{MMHR_head} );

    $self->log(ERROR => "No `Received' field specified."), return
       unless defined $self->{MMHR_received};

    my $mf = 'Mail::Message::Field';

    $self->{MMHR_date}       ||= $mf->new('Resent-Date' => $mf->toDate);

    # Be sure the message-id is good
    my $msgid = defined $self->{MMHR_message_id}
              ? "$self->{MMHR_message_id}"
              : $head->createMessageId;

    $msgid = "<$msgid>" unless $msgid =~ m!^\<.*\>$!;
    $self->{MMHR_message_id} = $mf->new('Resent-Message-ID' => $msgid);

    $self;
}

sub delete()
{   my $self   = shift;
    my $head   = $self->{MMHR_head};
    my @fields = grep {ref $_ && $_->isa('Mail::Message::Field')}
                     values %$self;

    $head->removeField($_) foreach @fields;
    $self;
}

sub returnPath() { shift->{MMHR_return_path} }

sub received() { shift->{MMHR_received} }

sub receivedTimestamp()
{   my $received = shift->{MMHR_received} or return;
    my $comment  = $received->comment or return;
    Mail::Message::Field->dateToTimestamp($comment);
}

sub date($) { shift->{MMHR_date} }

sub dateTimestamp()
{   my $date = shift->{MMHR_date} or return;
    Mail::Message::Field->dateToTimestamp($date);
}

sub from()
{   my $from = shift->{MMHR_from} or return ();
    wantarray ? $from->addresses : $from;
}

sub sender()
{   my $sender = shift->{MMHR_sender} or return ();
    wantarray ? $sender->addresses : $sender;
}

sub to()
{   my $to = shift->{MMHR_to} or return ();
    wantarray ? $to->addresses : $to;
}

sub cc()
{   my $cc = shift->{MMHR_cc} or return ();
    wantarray ? $cc->addresses : $cc;
}

sub bcc()
{   my $bcc = shift->{MMHR_bcc} or return ();
    wantarray ? $bcc->addresses : $bcc;
}

sub messageId() { shift->{MMHR_message_id} }

sub orderedFields()
{   my $self   = shift;
    map { $self->{ "MMHR_$_" } || () } @ordered_field_names;
}

1;
