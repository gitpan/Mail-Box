
use strict;
use warnings;

package Mail::Transport::IMAP4;
use vars '$VERSION';
$VERSION = '2.053';
use base 'Mail::Transport::Receive';

use Digest::HMAC_MD5;   # only availability check for CRAM_MD5
use Mail::IMAPClient;


sub init($)
{   my ($self, $args) = @_;

    my $imap = $args->{imap_client} || 'Mail::IMAPClient';
    if(ref $imap)
    {   $args->{port}     = $imap->Port;
        $args->{hostname} = $imap->Server;
	$args->{username} = $imap->User;
	$args->{password} = $imap->Password;
    }
    else
    {   $args->{port}   ||= 143;
    }

    $args->{via}          = 'imap4';

    $self->SUPER::init($args) or return;

    $self->authentication($args->{authenticate} || 'AUTO');
    $self->{MTI_domain} = $args->{domain};

    unless(ref $imap)
    {   $imap = $self->createImapClient($imap) or return undef;
    }
 
    $self->imapClient($imap);
    $self->login or return undef;
}

#------------------------------------------


sub url()
{   my $self = shift;
    my ($host, $port, $user, $pwd) = $self->remoteHost;
    my $name = $self->folderName;
    "imap4://$user:$pwd\@$host:$port$name";
}

#------------------------------------------


our $ntml_installed;

sub authentication(@)
{   my ($self, @types) = @_;
    return @{$self->{MTI_auth}} unless @types;

    unless(defined $ntml_installed)
    {   eval "require Authen::NTML";
        die "NTML errors:\n$@" if $@ && $@ !~ /Can't locate/;
        $ntml_installed = ! $@;
    }

    if(@types == 1 && $types[0] eq 'AUTO')
    {   @types = ('CRAM-MD5', ($ntml_installed ? 'NTLM' : ()), 'PLAIN');
    }

    my @auth;
    foreach my $auth (@types)
    {   push @auth,
             ref $auth eq 'ARRAY' ? $auth
           : $auth eq 'NTLM'      ? [NTLM  => \&Authen::NTLM::ntlm ]
           :                        [$auth => undef];
    }

    $self->log(WARNING => 'module Authen::NTLM is not installed')
        if grep { !ref $_ &&  $_ eq 'NTLM' } @auth;

    $self->{MTI_auth} = \@auth;
}

#------------------------------------------


sub domain(;$)
{   my $self = shift;
    return $self->{MTI_domain} = shift if @_;
    $self->{MTI_domain} || ($self->remoteHost)[0];
}

#------------------------------------------


#------------------------------------------


sub imapClient(;$)
{   my $self = shift;
    @_ ? ($self->{MTI_client} = shift) : $self->{MTI_client};
}

#------------------------------------------


sub createImapClient($)
{   my ($self, $class) = @_;

    my ($host, $port) = $self->remoteHost;

    my $debug_level = $self->logPriority('DEBUG')+0;
    my @debug;
    if($self->log <= $debug_level || $self->trace <= $debug_level)
    {   tie *dh, 'Mail::IMAPClient::Debug', $self;
        @debug = (Debug => 1, Debug_fh => \*dh);
    }

    my $client = $class->new
     ( Server => $host, Port => $port
     , User   => undef, Password => undef   # disable auto-login
     , Uid    => 1                          # Safer
     , Peek   => 1                          # Don't set \Seen automaticly
     , @debug
     );

    $self->log(ERROR => $@), return undef if $@;
    $client;
}

#------------------------------------------


sub login(;$)
{   my $self = shift;
    my $imap = $self->imapClient;

    return $self if $imap->IsAuthenticated;

    my ($interval, $retries, $timeout) = $self->retry;

    my ($host, $port, $username, $password) = $self->remoteHost;
    unless(defined $username)
    {   $self->log(ERROR => "IMAP4 requires a username and password");
        return;
    }
    unless(defined $password)
    {   $self->log(ERROR => "IMAP4 username $username requires a password");
        return;
    }

    while(1)
    {
        foreach my $auth ($self->authentication)
        {   my ($mechanism, $challange) = @$auth;

            $imap->User(undef);
            $imap->Password(undef);
            $imap->Authmechanism(undef);   # disable auto-login
            $imap->Authcallback(undef);

            unless($imap->connect)
	    {   $self->log(ERROR => "IMAP cannot connect to $host: "
	                          , $imap->LastError);
		return undef;
	    }

            if($mechanism eq 'NTLM')
            {   Authen::NTLM::ntlm_reset();
                Authen::NTLM::ntlm_user($username);
                Authen::NTLM::ntlm_domain($self->domain);
                Authen::NTLM::ntlm_password($password);
            }

            $imap->User($username);
            $imap->Password($password);
            $imap->Authmechanism($mechanism) unless $mechanism eq 'PLAIN';
            $imap->Authcallback($challange) if defined $challange;

            if($imap->login)
            {
	       $self->log(NOTICE =>
        "IMAP4 authenication $mechanism to $username\@$host:$port successful");
                return $self;
            }
        }

        $self->log(ERROR => "Couldn't contact to $username\@$host:$port")
            , return undef if $retries > 0 && --$retries == 0;

        sleep $interval if $interval;
    }

    undef;
}

#------------------------------------------


sub folder(;$)
{   my $self = shift;
    return $self->{MTI_folder} unless @_;

    my $name = shift;
    return $name if $name eq ($self->{MTI_folder} || '/');

    my $imap = $self->imapClient or return;
    $imap->select($name)         or return;
    $self->{MTI_folder} = $name;
    $imap;
}

#------------------------------------------


sub folders(;$)
{   my $self = shift;
    my $imap = $self->imapClient or return ();
    my @top  = @_ && $_[0] eq '/' ? () : shift;
    $imap->folders(@top);
}

#------------------------------------------


sub ids($)
{   my $self = shift;
    my $imap = $self->imapClient or return ();
    $imap->messages;
}

#------------------------------------------


# Explanation in Mail::Box::IMAP4::Message chapter DETAILS
my %flags2labels =
 ( '\Seen'     => [seen     => 1]
 , '\Answered' => [replied  => 1]
 , '\Flagged'  => [flagged  => 1]
 , '\Deleted'  => [deleted  => 1]
 , '\Draft'    => [draft    => 1]
 , '\Recent'   => [old      => 0]
 );

my %labels2flags;
while(my ($k, $v) = each %flags2labels)
{  $labels2flags{$v->[0]} = [ $k => $v->[1] ];
}

# where IMAP4 supports requests for multiple flags at once, we here only
# request one set of flags a time (which will be slower)

sub getFlags($$)
{   my ($self, $id) = @_;
    my $imap  = $self->imapClient or return ();

    my %flags;
    $flags{$_}++ foreach $imap->flags($id);

    my @labels;
    while(my ($k, $v) = each %flags2labels)
    {   my ($label, $positive) = @$v;
        push @labels, $label => (exists $flags{$k} ? $positive : !$positive);
    }

    @labels;
}

#------------------------------------------


# Mail::IMAPClient can only set one value a time, however we do more...
sub setFlags($@)
{   my ($self, $id) = (shift, shift);

    my $imap = $self->imapClient or return ();
    my (@set, @unset, @nonstandard);

    while(@_)
    {   my ($label, $value) = (shift, shift);
        if(my $r = $labels2flags{$label})
        {   my $flag = $r->[0];
            $value = $value ? $r->[1] : !$r->[1];
	        # exor can not be used, because value may be string
            $value ? (push @set, $flag) : (push @unset, $flag);
        }
	else
	{   push @nonstandard, ($label => $value);
        }
    }

    $imap->set_flag($_, $id)   foreach @set;
    $imap->unset_flag($_, $id) foreach @unset;

    @nonstandard;
}

#------------------------------------------


sub labelsToFlags(@)
{   my $thing = shift;
    my @set;
    if(@_==1)
    {   my $labels = shift;
        while(my ($label, $value) = each %$labels)
        {   if(my $r = $labels2flags{$label})
            {   push @set, $r->[0] if ($value ? $r->[1] : !$r->[1]);
            }
        }
    }
    else
    {   while(@_)
        {   my ($label, $value) = (shift, shift);
            if(my $r = $labels2flags{$label})
            {   push @set, $r->[0] if ($value ? $r->[1] : !$r->[1]);
            }
        }
    }

    join(" ", @set);
}

#------------------------------------------


sub getFields($@)
{   my ($self, $id) = (shift, shift);
    my $imap   = $self->imapClient or return ();
    my $parsed = $imap->parse_headers($id, @_) or return ();

    my @fields;
    while(my($n,$c) = each %$parsed)
    {   push @fields, map { Mail::Message::Field::Fast->new($n, $_) } @$c;
    }

    @fields;
}

#------------------------------------------


sub getMessageAsString($)
{   my $imap = shift->imapClient or return;
    my $uid = ref $_[0] ? shift->unique : shift;
    $imap->message_string($uid);
}

#------------------------------------------


sub fetch($@)
{   my ($self, $msgs, @info) = @_;
    return () unless @$msgs;
    my $imap   = $self->imapClient or return ();

    my %msgs   = map { ($_->unique => {message => $_} ) } @$msgs;
    my $lines  = $imap->fetch( [keys %msgs], @info );

    # It's a pity that Mail::IMAPClient::fetch_hash cannot be used for
    # single messages... now I had to reimplement the decoding...
    while(@$lines)
    {   my $line = shift @$lines;
        next unless $line =~ /\(.*?UID\s+(\d+)/i;
	my $id   = $+;
	my $info = $msgs{$id} or next;  # wrong uid

        if($line =~ s/^[^(]* \( \s* //x )
        {   while($line =~ s/(\S+)   # field
	                     \s+
                             (?:     # value
                                 \" ( (?:\\.|[^"])+ ) \"
                               | \( ( (?:\\.|[^)])+ ) \)
                               |  (\w+)
                             )//xi)
            {   $info->{uc $1} = $+;
            }

	    if( $line =~ m/^\s* (\S+) [ ]*$/x )
	    {   # Text block expected
	        my ($key, $value) = (uc $1, '');
	        while(@$lines)
		{   my $extra = shift @$lines;
		    $extra =~ s/\r\n$/\n/;
		    last if $extra eq ")\n";
		    $value .= $extra;
		}
		$info->{$key} = $value;
            }
        }

    }

    values %msgs;
}

#------------------------------------------


sub appendMessage($$)
{   my ($self, $message, $foldername) = @_;
    my $imap   = $self->imapClient or return ();

    $imap->append_string
     ( $foldername, $message->string
     , $self->labelsToFlags($message->labels)
     );
}

#------------------------------------------


sub destroyDeleted()
{   my $imap = shift->imapClient or return ();
    $imap->expunge;
}

#------------------------------------------


sub DESTROY()
{   my $self = shift;
    my $imap = $self->imapClient;

    $self->SUPER::DESTROY;
    $imap->logout if defined $imap;
}

#------------------------------------------

package Mail::IMAPClient::Debug;
use vars '$VERSION';
$VERSION = '2.053';

# Tied filehandle translates IMAP's debug system into Mail::Reporter
# calls.
sub TIEHANDLE($)
{   my ($class, $logger) = @_;
    bless \$logger, $class;
}

sub PRINT(@)
{   my $logger = ${ (shift) };
    $logger->log(DEBUG => @_);
}

1;
