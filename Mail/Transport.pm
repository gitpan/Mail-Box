use strict;
use warnings;

package Mail::Transport;
our $VERSION = 2.031;  # Part of Mail::Box
use base 'Mail::Reporter';

use Carp;
use File::Spec;

my %mailers =
 ( mail     => 'Mail::Transport::Mailx'
 , mailx    => 'Mail::Transport::Mailx'
 , sendmail => 'Mail::Transport::Sendmail'
 , smtp     => 'Mail::Transport::SMTP'
 , pop      => 'Mail::Transport::POP3'
 , pop3     => 'Mail::Transport::POP3'
 );

sub new(@)
{   my $class = shift;

    return $class->SUPER::new(@_)
        unless $class eq __PACKAGE__ || $class eq "Mail::Transport::Send";

    #
    # auto restart by creating the right transporter.
    #

    my %args  = @_;
    my $via   = lc($args{via} || '')
        or croak "No transport protocol provided.\n";

    $via      = $mailers{$via} if exists $mailers{$via};

    eval "require $via";
    return undef if $@;

    $via->new(@_);
}

sub init($)
{   my ($self, $args) = @_;

    $self->SUPER::init($args);

    $self->{MT_hostname}
       = defined $args->{hostname} ? $args->{hostname} : 'localhost';

    $self->{MT_port}     = $args->{port};
    $self->{MT_username} = $args->{username};
    $self->{MT_password} = $args->{password};
    $self->{MT_interval} = $args->{interval} || 30;
    $self->{MT_retry}    = $args->{retry}    || -1;
    $self->{MT_timeout}  = $args->{timeout}  || 120;
    $self->{MT_proxy}    = $args->{proxy};

    $self;
}

sub remoteHost()
{   my $self = shift;
    @$self{ qw/MT_hostname MT_port MT_username MT_password/ };
}

sub retry()
{   my $self = shift;
    @$self{ qw/MT_interval MT_retry MT_timeout/ };
}

my @safe_directories = qw(/usr/local/bin /usr/bin /bin
   /sbin /usr/sbin /usr/lib);

sub findBinary($@)
{   my ($self, $name) = (shift, shift);

    foreach (@safe_directories, @_)
    {   my $fullname = File::Spec->catfile($_, $name);
        return $fullname if -x $fullname;
    }

    undef;
}

1;
