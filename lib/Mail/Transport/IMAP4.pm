
use strict;
use warnings;

package Mail::Transport::IMAP4;
use vars '$VERSION';
$VERSION = '2.050';
use base 'Mail::Transport::Receive';

my $CRLF = $^O eq 'MSWin32' ? "\n" : "\015\012";


sub init($)
{   my ($self, $args) = @_;
    $args->{via}    = 'imap4';
    $args->{port} ||= 143;

    $self->SUPER::init($args) or return;

    my $auth = $self->{MTI_auth} = $args->{authenticate} || 'AUTO';
    eval "require Authen::NTML";
    $self->log(ERROR => 'module Authen::NTLM is not installed')
       if $auth eq 'NTLM' && $@;

    return unless $self->socket;   # establish connection

    $self;
}

#------------------------------------------


sub url()
{   my $self = shift;
    my ($host, $port, $user, $pwd) = $self->remoteHost;
    my $name = $self->folderName;
    "imap4://$user:$pwd\@$host:$port$name";
}

#------------------------------------------


sub ids(;@)
{   my $self = shift;
    return unless $self->socket;
    wantarray ? @{$self->{MTI_n2uidl}} : $self->{MTI_n2uidl};
}

#------------------------------------------


sub messages()
{   my $self = shift;

    $self->log(ERROR =>"Cannot get the messages of imap4 via messages()."), return ()
       if wantarray;

    $self->{MTI_messages};
}

#------------------------------------------


sub folderSize() { shift->{MTI_total} }

#------------------------------------------


sub header($;$)
{   my ($self, $uidl) = (shift, shift);
    return unless $uidl;
    my $bodylines = shift || 0;;

    my $socket    = $self->socket      or return;
    my $n         = $self->id2n($uidl) or return;

    $self->sendList($socket, "TOP $n $bodylines$CRLF");
}

#------------------------------------------


sub message($;$)
{   my ($self, $uidl) = @_;
    return unless $uidl;

    my $socket  = $self->socket      or return;
    my $n       = $self->id2n($uidl) or return;
    my $message = $self->sendList($socket, "RETR $n$CRLF");

    return unless $message;

    # Some IMAP4 servers add a trailing empty line
    pop @$message if @$message && $message->[-1] =~ m/^[\012\015]*$/;

    return if exists $self->{MTI_nouidl};

    $self->{MTI_fetched}{$uidl} = undef; # mark this ID as fetched
    $message;
}

#------------------------------------------


sub messageSize($)
{   my ($self, $uidl) = @_;
    return unless $uidl;

    my $list;
    unless($list = $self->{MTI_n2length})
    {   my $socket = $self->socket or return;
        my $raw = $self->sendList($socket, "LIST$CRLF") or return;
        my @n2length;
        foreach (@$raw)
        {   m#^(\d+) (\d+)#;
            $n2length[$1] = $2;
        }   
        $self->{MTI_n2length} = $list = \@n2length;
    }

    my $n = $self->id2n($uidl) or return;
    $list->[$n];
}

#------------------------------------------


sub deleted($@)
{   my $dele = shift->{MTI_dele} ||= {};
    (shift) ? @$dele{ @_ } = () : delete @$dele{ @_ };
}


#------------------------------------------


sub deleteFetched()
{   my $self = shift;
    $self->deleted(1, keys %{$self->{MTI_fetched}});
}

#------------------------------------------


sub disconnect()
{   my $self = shift;
}

#------------------------------------------


sub fetched(;$)
{   my $self = shift;
    return if exists $self->{MTI_nouidl};
    $self->{MTI_fetched};
}

#------------------------------------------


sub id2n($;$) { shift->{MTI_uidl2n}{shift()} }

#------------------------------------------


#------------------------------------------


sub socket(;$)
{   my $self = shift;

    my $socket = $self->_connection;
    return $socket if $socket;

    unless(exists $self->{MTI_nouidl})
    {   $self->log(ERROR =>
           "Can not re-connect reliably to server which doesn't support UIDL");
        return;
    }

    return unless $socket = $self->login;
    return unless $self->_status( $socket );

# Save socket in the object and return it

    $self->{MTI_socket} = $socket;
}

#------------------------------------------


sub send($$)
{   my $self = shift;
    my $socket = shift;
    my $response;
   
    if(eval {print $socket @_})
    {   $response = <$socket>;
        $self->log(ERROR => "Cannot read IMAP4 from socket: $!")
	   unless defined $response;
    }
    else
    {   $self->log(ERROR => "Cannot write IMAP4 to socket: $@");
    }
    $response;
}

#------------------------------------------


sub sendList($$)
{   my $self     = shift;
    my $socket   = shift;
    my $response = $self->send($socket, @_) or return;

    return unless OK($response);

    my @list;
    local $_; # make sure we don't spoil it for the outside world
    while(<$socket>)
    {   last if m#^\.\r?$CRLF#s;
        s#^\.##;
	push @list, $_;
    }

    \@list;
}

#------------------------------------------

sub OK($;$) { substr(shift || '', 0, 3) eq '+OK' }

#------------------------------------------

sub _connection(;$)
{   my $self = shift;
   my $socket = $self->{MTI_socket} or return undef;

    # Check if we (still) got a connection
    eval {print $socket "NOOP$CRLF"};
    if($@ || ! <$socket> )
    {   delete $self->{MTP_socket};
        return undef;
    }

    $socket;
}

#------------------------------------------

sub _reconnectok
{   my $self = shift;

# See if we are allowed to reconnect

    0;
}

#------------------------------------------


sub login(;$)
{   my $self = shift;

# Check if we can make a TCP/IP connection

    local $_; # make sure we don't spoil it for the outside world
    my ($interval, $retries, $timeout) = $self->retry;
    my ($host, $port, $username, $password) = $self->remoteHost;
    unless($username and $password)
    {   $self->log(ERROR => "IMAP4 requires a username and password");
        return;
    }

    my $socket = eval {IO::Socket::INET->new("$host:$port")};
    unless($socket)
    {   $self->log(ERROR => "Cannot connect to $host:$port for IMAP4: $!");
        return;
    }

# Check if it looks like a POP server

    my $connected;
    my $authenticate = $self->{MTI_auth};
    my $welcome = <$socket>;
    unless(OK($welcome))
    {   $self->log(ERROR =>
           "Server at $host:$port does not seem to be talking IMAP4");
        return;
    }

# Check APOP login if automatic or APOP specifically requested

    if($authenticate eq 'AUTO' or $authenticate eq 'APOP')
    {   if($welcome =~ m#^\+OK (<\d+\.\d+\@[^>]+>)#)
        {   my $md5 = Digest::MD5::md5_hex($1.$password);
            my $response = $self->send($socket, "APOP $username $md5$CRLF")
	     or return;
            $connected = OK($response);
        }
    }

# Check USER/PASS login if automatic and failed or LOGIN specifically requested

    unless($connected)
    {   if($authenticate eq 'AUTO' or $authenticate eq 'LOGIN')
        {   my $response = $self->send($socket, "USER $username$CRLF") or return;
            if(OK($response))
	    {   $response = $self->send($socket, "PASS $password$CRLF") or return;
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

#------------------------------------------

sub _status($;$)
{   my ($self,$socket) = @_;

# Check if we can do a STAT

    my $stat = $self->send($socket, "STAT$CRLF") or return;
    if($stat =~ m#^\+OK (\d+) (\d+)#)
    {   @$self{qw(MTI_messages MTI_total)} = ($1,$2);
    }
    else
    {   delete $self->{MTI_messages};
        delete $self->{MTI_size};
        $self->log(ERROR => "Could not do a STAT");
        return;
    }

# Check if we can do a UIDL

    my $uidl = $self->send($socket, "UIDL$CRLF") or return;
    $self->{MTI_nouidl} = undef;
    delete $self->{MTI_uidl2n}; # lose the reverse lookup: UIDL -> number
    if(OK($uidl))
    {   my @n2uidl;
        $n2uidl[$self->{MTI_messages}] = undef; # optimization, sets right size
        while(<$socket>)
        {   last if substr($_, 0, 1) eq '.';
            s#\r?$CRLF$##; m#^(\d+) (.+)#;
            $n2uidl[$1] = $2;
        }
        shift @n2uidl; # make message 1 into index 0
        $self->{MTI_n2uidl} = \@n2uidl;
        delete $self->{MTI_n2length};
        delete $self->{MTI_nouidl};
    }

# We can't do UIDL, we need to fake it

    else
    {   my $list = $self->send($socket, "LIST$CRLF") or return;
        my @n2length;
        my @n2uidl;
        if(OK($list))
        {   my $messages = $self->{MTI_messages};
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
        $self->{MTI_n2length} = \@n2length;
        $self->{MTI_n2uidl} = \@n2uidl;
    }

    my $i = 1;
    my %uidl2n;
    foreach(@{$self->{MTI_n2uidl}})
    {   $uidl2n{$_} = $i++;
    }
    $self->{MTI_uidl2n} = \%uidl2n;
    1;
}

#------------------------------------------


sub askSubfolderSeparator()
{   my $self = shift;

    # $self->send(A000 LIST "" "")
    # receives:  * LIST (\Noselect) "/" ""
    #                                ^ $SEP
    # return $SEP    [exactly one character)

    $self->notImplemented;
}

#------------------------------------------


sub askSubfoldersOf($)
{   my ($self, $name) = @_;
    
    # $imap->send(LIST "$name" %)
    # receives multiple lines
    #     * LIST (.*?) NAME
    # return list of NAMEs

    $self->notImplemented;
}

#------------------------------------------


# Explanation in Mail::Box::IMAP::Message chapter DETAILS
my %systemflags =
 ( '\Seen'     => 'seen'
 , '\Answered' => 'replied'
 , '\Flagged'  => 'flagged'
 , '\Deleted'  => 'deleted'
 , '\Draft'    => 'draft'
 , '\Recent'   => 'old'       #  NOT old
 );

sub getLabel($$)
{   my ($self, $id, $label) = @_;

    $self->notImplemented;
}

#------------------------------------------


sub setFlags($@)
{   my ($self, $id) = (shift, shift);
    my @flags = @_;  # etc

    $self->notImplemented;
}

#------------------------------------------


sub DESTROY()
{   my $self = shift;
    $self->SUPER::DESTROY;
    $self->disconnect if $self->{MTI_socket}; # only do if not already done
}

1;
