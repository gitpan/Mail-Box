use strict;
use warnings;

package Mail::Transport::Sendmail;
use vars '$VERSION';
$VERSION = '2.053';
use base 'Mail::Transport::Send';

use Carp;


sub init($)
{   my ($self, $args) = @_;

    $args->{via} = 'sendmail';

    $self->SUPER::init($args) or return;

    $self->{MTS_program}
      = $args->{proxy}
     || $self->findBinary('sendmail')
     || return;

    $self->{MTS_opts} = $args->{sendmail_options} || [];
    $self;
}

#------------------------------------------


sub trySend($@)
{   my ($self, $message, %args) = @_;

    my $program = $self->{MTS_program};
    if(open(MAILER, '|-')==0)
    {   my $options = $args{sendmail_options} || [];
        { exec $program, '-it', @{$self->{MTS_opts}}; }  # {} to avoid warning
        $self->log(NOTICE => "Errors when opening pipe to $program: $!");
        return 0;
    }
 
    $self->putContent($message, \*MAILER, undisclosed => 1);

    unless(close MAILER)
    {   $self->log(NOTICE => "Errors when closing sendmail mailer $program: $!");
        $? ||= $!;
        return 0;
    }

    1;
}

#------------------------------------------

1;