package Mail::Box::IMAP4;
our $VERSION = 2.037;  # Part of Mail::Box
use base 'Mail::Box::Net';

use strict;
use warnings;

use Mail::Box::IMAP4::Message;
use Mail::Box::Parser::Perl;

use IO::File;
use File::Spec;
use File::Basename;
use Carp;

sub init($)
{   my ($self, $args) = @_;

    $args->{server_port} ||= 143;

    $self->SUPER::init($args);

    $self->{MBI_client}    = $args->{imap_client};
    $self->{MBI_auth}      = $args->{authenticate} || 'AUTO';

    my $imap               = $self->imapClient or return;
    $self->{MBI_subsep}    = $args->{sub_sep}      || $imap->askSubfolderSeparator;

    $self;
}

sub create($@)
{   my ($class, %args) =  @_;
    $class->log(INTERNAL => "Folder creation for IMAP4 not implemented yet");
    undef;
}

sub foundIn(@)
{   my $self = shift;
    unshift @_, 'folder' if @_ % 2;
    my %options = @_;

       (exists $options{type}   && $options{type}   =~ m/^imap/i)
    || (exists $options{folder} && $options{folder} =~ m/^imap/);
}

sub type() {'imap4'}

sub close()
{   my $self = shift;

    my $imap  = $self->imapClient;
    $imap->disconnect if defined $imap;

    $self->SUPER::close;
}

sub listSubFolders(@)
{   my ($thing, %args) = @_;

    my $self
     = ref $thing ? $thing                # instance method
     :              $thing->new(%args);   # class method

    return () unless defined $self;

    my $imap = $self->imapClient
        or return ();

    my $name      = $imap->folderName;
    $name         = "" if $name eq '/';

    $self->askSubfoldersOf("$name$self->{MBI_subsep}");
}

sub nameOfSubfolder($)
{   my ($self, $name) = @_;
    "$self" . $self->{MBI_subsep} . $name;
}

sub imapClient()
{   my $self = shift;

    return $self->{MBI_client}
        if defined $self->{MBI_client};

    my $auth = $self->{auth};

    require Mail::Transport::IMAP4;
    my $client  = Mail::Transport::IMAP4->new
      ( username     => $self->{MBN_username}
      , password     => $self->{MBN_password}
      , hostname     => $self->{MBN_hostname}
      , port         => $self->{MBN_port}
      , authenticate => $self->{MBI_auth}
      );

    $self->log(ERROR => "Cannot create IMAP4 client ".$self->url.'.')
       unless defined $client;

    $self->{MBI_client} = $client;
}

sub readMessages(@)
{   my ($self, %args) = @_;

    my $imap   = $self->imapClient;
    my @log   = $self->logSettings;
    my $seqnr = 0;

#### Things must be changed here...
    foreach my $id ($imap->ids)
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
    my $imap   = $self->imapClient or return;

    my $uidl  = $message->unique;
    my $lines = $imap->header($uidl);

    unless(defined $lines)
    {   $self->log(WARNING => "Message $uidl disappeared from $self.");
        return;
     }

    my $parser = Mail::Box::Parser::Perl->new   # not parseable by C parser
     ( filename  => "$imap"
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
    my $imap  = $self->imapClient or return;

    my $uidl  = $message->unique;
    my $lines = $imap->message($uidl);

    unless(defined $lines)
    {   $self->log(WARNING  => "Message $uidl disappeared from $self.");
        return ();
     }

    my $parser = Mail::Box::Parser::Perl->new   # not parseable by C parser
     ( filename  => "$imap"
     , file      => IO::ScalarArray->new($lines)
     );

    my $head = $message->readHead($parser);
    unless(defined $head)
    {   $self->log(WARNING => "Cannot find head back for $uidl in $self.");
        $parser->stop;
        return ();
    }

    my $body = $message->readBody($parser, $head);
    unless(defined $body)
    {   $self->log(WARNING => "Cannot read body for $uidl in $self.");
        $parser->stop;
        return ();
    }

    $parser->stop;

    $self->log(PROGRESS => "Loaded message $uidl.");
    ($head, $body);
}

sub writeMessages($@)
{   my ($self, $args) = @_;

    if(my $modifications = grep {$_->isModified} @{$args->{messages}})
    {
    }

    $self;
}

1;
