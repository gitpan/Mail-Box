# Copyrights 2001-2014 by [Mark Overmeer].
#  For other contributors see ChangeLog.
# See the manual pages for details on the licensing terms.
# Pod stripped from pm file by OODoc 2.01.
use strict;
use warnings;

package Mail::Transport::Receive;
our $VERSION = '2.111';

use base 'Mail::Transport';


sub receive(@) {shift->notImplemented}

#------------------------------------------


1;
