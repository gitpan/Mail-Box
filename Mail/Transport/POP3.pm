use strict;
use warnings;

package Mail::Transport::POP3;
our $VERSION = 2.021;  # Part of Mail::Box
use base 'Mail::Transport::Receive';

sub init($)
{   my ($self, $args) = @_;
    $args->{via} = 'pop3';
    $self->SUPER::init($args);

    $self->{MTP_auth} = $self->{authenticate} || 'LOGIN';
    $self;
}

sub messages()
{   my $self = shift;

    my $server = $self->contactServer;

    $self->{MTP_msgs} = { reverse $server->send('UIDL') }
        unless exists $self->{MTP_msgs};

    keys %{$self->{MTP_msgs}};
}

sub uidl2seqnr($)
{   my ($self, $uidl) = @_;

    exists $self->{MTP_msgs} || $self->message || return;
    $self->{MTP_msgs}{$uidl};
}

sub header($;$)
{   my ($self, $uidl, $bodylines) = (shift, shift || 0);

    my $server = $self->contactServer
       or return [];

    my $seqnr  = $self->uidl2seqnr($uidl);
    return [] unless defined $seqnr;

    my @header = $server->send(TOP => $seqnr, $bodylines);
    \@header;
}

# When the size() is called for the first time, POP3 method list() should
# be called and all sizes collected.  Those values should be cached for
# performance reasons.

sub size($)
{   my ($self, $uidl) = @_;

    return $self->{MTP_sizes}{$uidl}
        if exists $self->{MTP_sizes};

    $self->messages or return;  # be sure we have messages
    my %uidl_of = reverse %{$self->{MTP_msgs}};

    my $server  = $self->contactServer or return;
    my $sizes   = $self->{MTP_sizes} = {};

    my @sizes = $server->send('UIDL');
    foreach (@sizes)
    {   my ($seqnr, $size) = @_;
        my $id = $uidl_of{$seqnr};
        $sizes->{$id} = $size if defined $id;
    }

    return $self->{MTP_sizes}{$uidl};
}

sub stat()
{   my $self = shift;

    my $server = $self->contactServer
        or return (0,0);

    my ($nr, $size) = split " ", $server->send('STAT');
    ($nr, $size);
}

sub delete(@)
{   my $self = shift;

    my $server = $self->contactServer or return;

    $server->send(DELE => $self->uidl2seqnr($_))
       foreach @_;
}

sub contactServer()
{   my $self = shift;

    my $server;
    if($server = $self->{MTP_server} && !$server->alive)
    {    undef $server;
         delete $self->{MTP_server};
         delete $self->{MTP_msgs};
         delete $self->{MTP_sizes};
    }

    return $server if defined $server;

    my ($interval, $retries, $timeout)   = $self->retry;
    my ($hostname, $port, $username, $password) = $self->remoteHost;

# Create a connection to the server and login.

    $server;
}

sub disconnect()
{   my $self = shift;
}

sub url()
{   my $self = shift;
    my ($host, $port, $user, $pwd) = $self->remoteHost;
    "pop3://$user:$pwd\@$host:$port";
}

sub DESTROY()
{   my $self = shift;
    $self->SUPER::DESTROY;
    $self->disconnect;
}

1;
