use strict;
use warnings;

package Mail::Transport::Receive;
our $VERSION = 2.036;  # Part of Mail::Box
use base 'Mail::Transport';

sub receive(@) {shift->notImplemented}

1;
