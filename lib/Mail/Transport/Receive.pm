use strict;
use warnings;

package Mail::Transport::Receive;
use vars '$VERSION';
$VERSION = '2.067';
use base 'Mail::Transport';


sub receive(@) {shift->notImplemented}

#------------------------------------------


1;
