use strict;
use warnings;

package Mail::Transport::Exim;
our $VERSION = 2.036;  # Part of Mail::Box
use base 'Mail::Transport::Send';

use Carp;

sub init($)
{   my ($self, $args) = @_;

    $args->{via} = 'exim';

    $self->SUPER::init($args) or return;

    $self->{MTS_program}
      = $args->{proxy}
     || $self->findBinary('exim', '/usr/exim/bin')
     || return;

    $self;
}

sub trySend($@)
{   my ($self, $message, %args) = @_;

    my $from = $args{from} || $message->sender;
    $from    = $from->address if $from->isa('Mail::Address');
    my @to   = map {$_->address} $self->destinations($message, $args{to});

    my $program = $self->{MTS_program};
    if(open(MAILER, '|-')==0)
    {   { exec $program, '-f', $from, @to; }  # {} to avoid warning
        $self->log(NOTICE => "Errors when opening pipe to $program: $!");
        return 0;
    }

    $self->putContent($message, \*MAILER);

    unless(close MAILER)
    {   $self->log(NOTICE => "Errors when closing $program: $!");
        $? ||= $!;
        return 0;
    }

    1;
}

1;
