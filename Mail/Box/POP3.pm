package Mail::Box::POP3;
our $VERSION = 2.035;  # Part of Mail::Box
use base 'Mail::Box::Net';

use strict;
use warnings;

use Mail::Box::POP3::Message;
use Mail::Box::Parser::Perl;

use IO::File;
use File::Spec;
use File::Basename;
use Carp;

sub init($)
{   my ($self, $args) = @_;

    $args->{server_port} ||= 110;

    $self->SUPER::init($args);

    $self->{MBP_client}    = $args->{pop_client};
    $self->{MBP_auth}      = $args->{authenticate} || 'AUTO';

    $self;
}

sub create($@) { undef }         # fails

sub foundIn(@)
{   my $self = shift;
    unshift @_, 'folder' if @_ % 2;
    my %options = @_;

       (exists $options{type}   && lc $options{type} eq 'pop3')
    || (exists $options{folder} && $options{folder} =~ m/^pop/);
}

sub addMessage($)
{   my ($self, $message) = @_;

    $self->log(ERROR => "You cannot write a message to a pop server (yet)")
       if defined $message;

    undef;
}

sub addMessages(@)
{   my $self = shift;

    $self->log(ERROR => "You cannot write messages to a pop server")
        if @_;

    ();
}

sub type() {'pop3'}

sub close()
{   my $self = shift;

    my $pop  = $self->popClient;
    $pop->disconnect if defined $pop;

    $self->SUPER::close;
}

sub delete()
{   my $self = shift;
    $self->log(NOTICE => "You cannot delete a POP3 folder remotely.");

    $_->deleted(1) foreach $self->messages;
    $self;
}

sub listSubFolders(@) { () }     # no

sub openSubFolder($@) { undef }  # fails

sub update() {shift->notImplemented}

sub popClient()
{   my $self = shift;

    return $self->{MBP_client}
        if defined $self->{MBP_client};

    my $auth = $self->{auth};

    require Mail::Transport::POP3;
    my $client  = Mail::Transport::POP3->new
      ( username     => $self->{MBN_username}
      , password     => $self->{MBN_password}
      , hostname     => $self->{MBN_hostname}
      , port         => $self->{MBN_port}
      , authenticate => $self->{MBP_auth}
      );

    $self->log(ERROR => "Cannot create POP3 client ".$self->url)
       unless defined $client;

    $self->{MBP_client} = $client;
}

sub readMessages(@)
{   my ($self, %args) = @_;

    my $pop   = $self->popClient;
    my @log   = $self->logSettings;
    my $seqnr = 0;

    foreach my $id ($pop->ids)
    {   my $message = $args{message_type}->new
         ( head      => $args{head_delayed_type}->new(@log)
         , unique    => $id
         , folder    => $self
         , seqnr     => $seqnr++
         );

        my $body    = $args{body_delayed_type}->new(@log, message => $message);
        $message->storeBody($body);

        $self->storeMessage($message);
    }

    $self;
}

sub getHead($)
{   my ($self, $message) = @_;
    my $pop   = $self->popClient or return;

    my $uidl  = $message->unique;
    my $lines = $pop->header($uidl);

    unless(defined $lines)
    {   $lines = [];
        $self->log(WARNING  => "Message $uidl disappeared.");
     }

    my $parser = Mail::Box::Parser::Perl->new   # not parseable by C parser
     ( filename  => "$pop"
     , file      => IO::ScalarArray->new($lines)
     );

    $self->lazyPermitted(1);

    my $head     = $message->readHead($parser);
    $parser->stop;

    $self->lazyPermitted(0);

    $self->log(PROGRESS => "Loaded head of $uidl.");
    $head;
}

sub getHeadAndBody($)
{   my ($self, $message) = @_;
    my $pop   = $self->popClient or return;

    my $uidl  = $message->unique;
    my $lines = $pop->message($uidl);

    unless(defined $lines)
    {   $lines = [];
        $self->log(WARNING  => "Message $uidl disappeared.");
     }

    my $parser = Mail::Box::Parser::Perl->new   # not parseable by C parser
     ( filename  => "$pop"
     , file      => IO::ScalarArray->new($lines)
     );

    my $head = $message->readHead($parser);
    unless(defined $head)
    {   $self->log(WARNING => "Cannot find head back for $uidl");
        $parser->stop;
        return undef;
    }

    my $body = $message->readBody($parser, $head);
    unless(defined $body)
    {   $self->log(ERROR => "Cannot read body for $uidl");
        $parser->stop;
        return undef;
    }

    $parser->stop;

    $self->log(PROGRESS => "Loaded message $uidl.");
    ($head, $body);
}

sub writeMessages($@)
{   my ($self, $args) = @_;

    if(my $modifications = grep {$_->modified} @{$args->{messages}})
    {   $self->log(WARNING =>
           "Update of $modifications messages ignored for pop3 folder $self.");
    }

    $self;
}

1;
