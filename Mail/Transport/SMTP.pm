use strict;
use warnings;

package Mail::Transport::SMTP;
our $VERSION = 2.035;  # Part of Mail::Box
use base 'Mail::Transport::Send';

use Net::SMTP;

sub init($)
{   my ($self, $args) = @_;

    my $hosts   = $args->{hostname};
    unless($hosts)
    {   require Net::Config;
        $hosts  = $Net::Config::NetConfig{smtp_hosts};
        undef $hosts unless @$hosts;
        $args->{hostname} = $hosts;
    }

    $args->{via}  ||= 'smtp';
    $args->{port} ||= '25';

    $self->SUPER::init($args) or return;

    my $helo = $args->{helo}
      || eval { require Net::Config; $Net::Config::inet_domain }
      || eval { require Net::Domain; Net::Domain::hostfqdn() };

    $self->{MTS_net_smtp_opts}
       = { Hello   => $helo
         , Debug   => ($args->{smtp_debug} || 0)
         };

    $self;
}

sub trySend($@)
{   my ($self, $message, %args) = @_;

    # From whom is this message.
    my $from = $args{from} || $message->sender;
    $from = $from->address if $from->isa('Mail::Address');

    # Who are the destinations.
    $self->log(ERROR =>
        "Use option `to' to overrule the destination: `To' would refer to a field")
            if defined $args{To};

    my @to = map {$_->address} $self->destinations($message, $args{to});

    # Prepare the header
    my @header;
    require IO::Lines;
    my $lines = IO::Lines->new(\@header);
    $message->head->printUndisclosed($lines);

    #
    # Send
    #

    if(wantarray)
    {   # In LIST context
        my $server;
        return (0, 500, "Connection Failed", "CONNECT", 0)
            unless $server = $self->contactAnyServer;

        return (0, $server->code, $server->message, 'FROM', $server->quit)
            unless $server->mail($from);

        foreach (@to)
        {     next if $server->to($_);
# must we be able to disable this?
# next if $args{ignore_erroneous_destinations}
              return (0, $server->code, $server->message,"To $_",$server->quit);
        }

        $server->data;
        $server->datasend($_) foreach @header;
        my $bodydata = $message->body->file;
        $server->datasend($_) while <$bodydata>;

        return (0, $server->code, $server->message, 'DATA', $server->quit)
            unless $server->dataend;

        return ($server->quit, $server->code, $server->message, 'QUIT',
                $server->code);
    }

    # in SCALAR context
    my $server;
    return 0 unless $server = $self->contactAnyServer;

    $server->quit, return 0
        unless $server->mail($from);

    foreach (@to)
    {     next if $server->to($_);
# must we be able to disable this?
# next if $args{ignore_erroneous_destinations}
          $server->quit;
          return 0;
    }

    $server->data;
    $server->datasend($_) foreach @header;
    my $bodydata = $message->body->file;
    $server->datasend($_) while <$bodydata>;

    $server->quit, return 0
        unless $server->dataend;

    $server->quit;
}

sub contactAnyServer()
{   my $self = shift;

    my ($enterval, $count, $timeout) = $self->retry;
    my ($host, $port, $username, $password) = $self->remoteHost;
    my @hosts = ref $host ? @$host : $host;

    foreach my $host (@hosts)
    {   my $server = $self->tryConnectTo
         ( $host, Port => $port,
         , %{$self->{MTS_net_smtp_opts}}, Timeout => $timeout
         );

        defined $server or next;

        $self->log(PROGRESS => "Opened SMTP connection to $host.\n");

        if(defined $username)
        {   if($server->auth($username, $password))
            {    $self->log(PROGRESS => "$host: Authentication succeeded.\n");
            }
            else
            {    $self->log(ERROR => "Authentication failed.\n");
                 return undef;
            }
        }

        return $server;
    }

    undef;
}

sub tryConnectTo($@)
{   my ($self, $host) = (shift, shift);
    Net::SMTP->new($host, @_);
}

sub destinations($;$)
{   my ($self, $message, $overrule) = @_;
    my @to;

    if(defined $overrule)      # Destinations overruled by user.
    {   my @addr = ref $overrule eq 'ARRAY' ? @$overrule : ($overrule);
        @to = map { ref $_ && $_->isa('Mail::Address') ? ($_)
                    : Mail::Address->parse($_) } @addr;
    }
    elsif(my @rgs = $message->head->resentGroups)
    {   @to = $rgs[0]->destinations;
        $self->log(ERROR => "Resent group does not define destinations"), return ()
            unless @to;
    }
    else
    {   @to = $message->destinations;
        $self->log(ERROR => "Message has no destinations"), return ()
            unless @to;
    }

    @to;
}

1;
