use strict;
use warnings;

package Mail::Transport::Sendmail;
our $VERSION = 2.026;  # Part of Mail::Box
use base 'Mail::Transport::Send';

use Carp;

sub init($)
{   my ($self, $args) = @_;

    $args->{via} = 'sendmail';

    $self->SUPER::init($args);

    $self->{MTS_program}
      = $args->{proxy}
     || $self->findBinary('sendmail')
     || return;

    $self;
}

sub trySend($@)
{   my ($self, $message, %args) = @_;

    my $program = $self->{MTS_program};
    if(open(MAILER, '|-')==0)
    {   { exec $program, '-t'; }  # {} to avoid warning
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
