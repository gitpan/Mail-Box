
use strict;

package Mail::Box::IMAP4::DelayedHead;
use vars '$VERSION';
$VERSION = '2.052';
use base 'Mail::Message::Head::Delayed';

use Date::Parse;


sub init($$)
{   my ($self, $args) = @_;
    $self->SUPER::init($args);

    $self;
}

#------------------------------------------


sub get($;$)
{   my $self = shift;

# Something here, playing with ENVELOPE, may improve the performance.

    $self->load->get(@_);
}

#------------------------------------------


sub guessBodySize() {undef}

#-------------------------------------------


sub guessTimestamp() {undef}

#------------------------------------------


1;
