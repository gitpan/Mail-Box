use strict;
use warnings;

package Mail::Transport::Receive;
use vars '$VERSION';
$VERSION = '2.052';
use base 'Mail::Transport';


sub receive(@) {shift->notImplemented}

#------------------------------------------


1;
