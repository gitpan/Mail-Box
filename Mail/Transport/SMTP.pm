use strict;
use warnings;

package Mail::Transport::SMTP;
our $VERSION = 2.021;  # Part of Mail::Box
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

    $args->{via} = 'smtp';

    $self->SUPER::init($args);

    my $helo = $args->{helo}
      || eval { require Net::Config; $Net::Config::inet_domain }
      || eval { require Net::Domain; Net::Domain::hostfqdn() };

    $self->{MTS_net_smtp_opts}
       = { Hello   => $helo
         , Debug   => ($args->{debug} || 0)
         };

    $self;
}

sub trySend($@)
{   my ($self, $message, %args) = @_;

    # From whom is this message.
    my $from = $args{from} || $message->from;
    $from = $from->address if ref $from;

    # Who are the destinations.
    my $to   = $args{to}   || [$message->destinations];
    my @to   = ref $to eq 'ARRAY' ? @$to : ($to);
    foreach (@to)
    {   $_ = $_->address if ref $_ && $_->isa('Mail::Address');
    }

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
# next if $args{ignore_erroneous_desinations}
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
# next if $args{ignore_erroneous_desinations}
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

    my ($interval, $count, $timeout) = $self->retry;
    my ($host, $username, $password) = $self->remoteHost;
    my @hosts = ref $host ? @$host : $host;

    foreach my $host (@hosts)
    {   my $server = $self->tryConnectTo
         ( $host
         , %{$self->{MTS_net_smtp_opts}}, Timeout => $timeout
         );

        defined $server or next;

        $self->log(PROGRESS => "Opened SMTP connection to $host.\n");
        return $server;
    }

    undef;
}

sub tryConnectTo($@)
{   my ($self, $host) = (shift, shift);
    Net::SMTP->new($host, @_);
}

1;
