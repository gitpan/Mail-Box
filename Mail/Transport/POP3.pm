use strict;
use warnings;

package Mail::Transport::POP3;
our $VERSION = 2.029;  # Part of Mail::Box
use base 'Mail::Transport::Receive';

use IO::Socket  ();
use Digest::MD5 ();

sub init($)
{   my ($self, $args) = @_;
    $args->{via} = 'pop3';
    $self->SUPER::init($args);

    $self->{MTP_auth}    = $args->{authenticate} || 'AUTO';
    return unless $self->socket;   # establish connection

    $self;
}

sub url(;$)
{   my ($host, $port, $user, $pwd) = shift->remoteHost;
    "pop3://$user:$pwd\@$host:$port";
}

sub ids(;@)
{   my $self = shift;
    return unless $self->socket;
    wantarray ? @{$self->{MTP_n2uidl}} : $self->{MTP_n2uidl};
}

sub messages()
{   my $self = shift;

    $self->log(INTERNAL => "Cannot get the messages via pop3 this way."), return ()
       if wantarray;

    $self->{MTP_messages};
}

sub folderSize() { shift->{MTP_total} }

sub header($;$)
{   my ($self, $uidl) = (shift, shift);
    return unless $uidl;
    my $bodylines = shift || 0;;

    my $socket    = $self->socket      or return;
    my $n         = $self->id2n($uidl) or return;

    $self->sendList($socket, "TOP $n $bodylines\n");
}

sub message($;$)
{   my ($self, $uidl) = @_;
    return unless $uidl;

    my $socket  = $self->socket      or return;
    my $n       = $self->id2n($uidl) or return;
    my $message = $self->sendList($socket, "RETR $n\n");

    return unless $message;

    # Some POP3 servers add a trailing empty line
    pop @$message if @$message && $message->[-1] =~ m/^[\012\015]*$/;

    return if exists $self->{MTP_nouidl};

    $self->{MTP_fetched}{$uidl} = undef; # mark this ID as fetched
    $message;
}

sub messageSize($)
{   my ($self, $uidl) = @_;
    return unless $uidl;

    my $list;
    unless($list = $self->{MTP_n2length})
    {   my $socket = $self->socket or return;
        my $raw = $self->sendList($socket, "LIST\n") or return;
        my @n2length;
        foreach (@$raw)
        {   m#^(\d+) (\d+)#;
            $n2length[$1] = $2;
        }
        $self->{MTP_n2length} = $list = \@n2length;
    }

    my $n = $self->id2n($uidl) or return;
    $list->[$n];
}

sub deleted($@)
{   my $dele = shift->{MTP_dele} ||= {};
    (shift) ? @$dele{ @_ } = () : delete @$dele{ @_ };
}

sub deleteFetched()
{   my $self = shift;
    $self->deleted(1, keys %{$self->{MTP_fetched}});
}

sub disconnect()
{   my $self = shift;

    my $quit;
    if($self->{MTP_socket}) # can only disconnect once
    {   if(my $socket = $self->socket)
        {   my $dele  = $self->{MTP_dele} || {};
            while(my $uidl = each %$dele)
            {   my $n = $self->id2n($uidl) or next;
                $self->send($socket, "DELE $n\n") or last;
            }

            $quit = $self->send($socket, "QUIT\n");
            close $socket;
        }
    }

    delete @$self{ qw(
     MTP_socket
     MTP_dele
     MTP_uidl2n
     MTP_n2uidl
     MTP_n2length
     MTP_fetched
    ) };

    OK($quit);
}

sub fetched(;$)
{   my $self = shift;
    return if exists $self->{MTP_nouidl};
    $self->{MTP_fetched};
}

sub id2n($;$) { shift->{MTP_uidl2n}{shift()} }

sub socket(;$)
{   my $self = shift;

    my $socket = $self->_connection;
    return $socket if $socket;

    return unless $self->_reconnectok;
    return unless $socket = $self->_login;
    return unless $self->_status( $socket );

# Save socket in the object and return it

    $self->{MTP_socket} = $socket;
}

sub send($$)
{   my $self = shift;
    my $socket = shift;
    my $response;

    if(eval {print $socket @_})
    {   $response = <$socket>;
        $self->log(ERROR => "Could not read from socket: $!")
	 unless defined $response;
    }
    else
    {   $self->log(ERROR => "Could not write to socket: $@");
    }
    $response;
}

sub sendList($$)
{   my $self     = shift;
    my $socket   = shift;
    my $response = $self->send($socket, @_) or return;

    return unless OK($response);

    my @list;
    local $_; # make sure we don't spoil it for the outside world
    while(<$socket>)
    {   last if m#^\.\r?\n#s;
        s#^\.##;
	push @list, $_;
    }

    \@list;
}

sub DESTROY()
{   my $self = shift;
    $self->SUPER::DESTROY;
    $self->disconnect if $self->{MTP_socket}; # only do if not already done
}

sub OK($;$) { substr(shift || '', 0, 3) eq '+OK' }

sub _connection(;$)
{   my $self = shift;

# Check if we (still) got a connection

    my $socket;
    my $wasconnected;

    if($wasconnected = $socket = $self->{MTP_socket})
    {   my $error = 1;
        if(eval {print $socket "NOOP\n"})
        {   my $response = <$socket>;
            $error = !defined($response); # anything will indicate it's alive
        }

        if($error)
	{   undef $socket;
            delete $self->{MTP_socket};
        }
    }
    return $socket if $socket;
}

sub _reconnectok
{   my $self = shift;

# See if we are allowed to reconnect

    return 1 unless exists $self->{MTP_nouidl};
    $self->log(ERROR =>
     "Can not re-connect reliably to server which doesn't support UIDL");
    0;
}

sub _login(;$)
{   my $self = shift;

# Check if we can make a TCP/IP connection

    local $_; # make sure we don't spoil it for the outside world
    my ($interval, $retries, $timeout) = $self->retry;
    my ($host, $port, $username, $password) = $self->remoteHost;
    unless($username and $password)
    {   $self->log(ERROR => "Must have specified username and password");
        return;
    }

    my $socket = eval {IO::Socket::INET->new("$host:$port")};
    unless($socket)
    {   $self->log(ERROR => "Could not connect to $host:$port: $!");
        return;
    }

# Check if it looks like a POP server

    my $connected;
    my $authenticate = $self->{MTP_auth};
    my $welcome = <$socket>;
    unless(OK($welcome))
    {   $self->log(ERROR =>
           "Server at $host:$port does not seem to be talking POP3");
        return;
    }

# Check APOP login if automatic or APOP specifically requested

    if($authenticate eq 'AUTO' or $authenticate eq 'APOP')
    {   if($welcome =~ m#^\+OK (<\d+\.\d+\@[^>]+>)#)
        {   my $md5 = Digest::MD5::md5_hex($1.$password);
            my $response = $self->send($socket, "APOP $username $md5\n")
	     or return;
            $connected = OK($response);
        }
    }

# Check USER/PASS login if automatic and failed or LOGIN specifically requested

    unless($connected)
    {   if($authenticate eq 'AUTO' or $authenticate eq 'LOGIN')
        {   my $response = $self->send($socket, "USER $username\n") or return;
            if(OK($response))
	    {   $response = $self->send($socket, "PASS $password\n") or return;
                $connected = OK($response);
            }
        }
    }

# If we're still not connected now, we have an error

    unless($connected)
    {   $self->log(ERROR => $authenticate eq 'AUTO' ?
         "Could not authenticate using any login method" :
         "Could not authenticate using '$authenticate' method");
        return;
    }
    $socket;
}

sub _status($;$)
{   my ($self,$socket) = @_;

# Check if we can do a STAT

    my $stat = $self->send($socket, "STAT\n") or return;
    if($stat =~ m#^\+OK (\d+) (\d+)#)
    {   @$self{qw(MTP_messages MTP_total)} = ($1,$2);
    }
    else
    {   delete $self->{MTP_messages};
        delete $self->{MTP_size};
        $self->log(ERROR => "Could not do a STAT");
        return;
    }

# Check if we can do a UIDL

    my $uidl = $self->send($socket, "UIDL\n") or return;
    $self->{MTP_nouidl} = undef;
    delete $self->{MTP_uidl2n}; # lose the reverse lookup: UIDL -> number
    if(OK($uidl))
    {   my @n2uidl;
        $n2uidl[$self->{MTP_messages}] = undef; # optimization, sets right size
        while(<$socket>)
        {   last if substr($_, 0, 1) eq '.';
            s#\r?\n$##; m#^(\d+) (.+)#;
            $n2uidl[$1] = $2;
        }
        shift @n2uidl; # make message 1 into index 0
        $self->{MTP_n2uidl} = \@n2uidl;
        delete $self->{MTP_n2length};
        delete $self->{MTP_nouidl};
    }

# We can't do UIDL, we need to fake it

    else
    {   my $list = $self->send($socket, "LIST\n") or return;
        my @n2length;
        my @n2uidl;
        if(OK($list))
        {   my $messages = $self->{MTP_messages};
            my ($host, $port) = $self->remoteHost;
            $n2length[$messages] = $n2uidl[$messages] = undef; # optimization
            while(<$socket>)
            {   last if substr($_, 0, 1) eq '.';
                m#^(\d+) (\d+)#;
                $n2length[$1] = $2;
                $n2uidl[$1] = "$host:$port:$1"; # fake UIDL, for id only
            }
            shift @n2length; shift @n2uidl; # make 1st message in index 0
        }
        $self->{MTP_n2length} = \@n2length;
        $self->{MTP_n2uidl} = \@n2uidl;
    }

    my $i = 1;
    my %uidl2n;
    foreach(@{$self->{MTP_n2uidl}})
    {   $uidl2n{$_} = $i++;
    }
    $self->{MTP_uidl2n} = \%uidl2n;
    1;
}

1;
