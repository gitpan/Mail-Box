package Mail::Box::POP3;
our $VERSION = 2.024;  # Part of Mail::Box
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

    $args->{trusted}     ||= 0;
    $args->{server_port} ||= 110;

    my $client             = $args->{pop_client};
    $args->{foldername}  ||= defined $client ? $client->url : undef;

    $self->SUPER::init($args);

    $self->{MBP_client}    = $client;
    $self->{MBP_auth}      = $args->{authenticate} || 'LOGIN';

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

sub listSubFolders(@) { () }     # no

sub openSubFolder($@) { undef }  # fails

sub popClient()
{   my $self = shift;

    return $self->{MBP_client} if exists $self->{MBP_client};

    my $auth = $self->{auth};

    require Mail::Transport::POP3;
    my $client  = Mail::Transport::POP3->new
     ( username     => $self->{MBN_username}
     , password     => $self->{MBN_password}
     , hostname     => $self->{MBN_hostname}
     , port         => $self->{MBN_port}
     , authenticate => $self->{MBP_auth}
     );

    $self->{MBP_client} = $client;
}

sub readMessages(@)
{   my ($self, %args) = @_;

    my $directory = $self->directory;
    return unless -d $directory;

    my @msgnrs = $self->readMessageFilenames($directory);

    my @log    = $self->logSettings;
    foreach my $msgnr (@msgnrs)
    {
        my $msgfile = File::Spec->catfile($directory, $msgnr);

        my $head;
        $head     ||= $args{head_delayed_type}->new(@log);

        my $message = $args{message_type}->new
         ( head      => $head
         , filename  => $msgfile
         , folder    => $self
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

    my $uidl  = $message->uidl;
    my $lines = $pop->top($uidl, 0);

    unless(defined $lines)
    {   $lines = [];
        $self->log(WARNING  => "Message $uidl disappeared.");
     }

    my $parser = Mail::Box::Parser::Perl->new   # not parseable by C parser
     ( filename  => "$pop"
     , file      => IO::ScalarArray->new($lines)
     );

    my $head     = $self->readHead($parser);
    $parser->stop;

    $self->log(PROGRESS => "Loaded head $uidl.");
    $head;
}

sub getHeadAndBody($)
{   my ($self, $message) = @_;
    my $pop   = $self->popClient or return;

    my $uidl  = $message->uidl;
    my $lines = $pop->top($uidl);

    unless(defined $lines)
    {   $lines = [];
        $self->log(WARNING  => "Message $uidl disappeared.");
     }

    my $parser = Mail::Box::Parser::Perl->new   # not parseable by C parser
     ( filename  => "$pop"
     , file      => IO::ScalarArray->new($lines)
     );

    my $head     = $message->readHead($parser);
    my $body     = $message->readBody($parser, $head);

    $parser->stop;

    $self->log(PROGRESS => "Loaded head $uidl.");
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
