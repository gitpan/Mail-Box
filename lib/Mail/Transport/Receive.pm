# Copyrights 2001-2012 by [Mark Overmeer].
#  For other contributors see ChangeLog.
# See the manual pages for details on the licensing terms.
# Pod stripped from pm file by OODoc 2.00.
use strict;
use warnings;

package Mail::Transport::Receive;
use vars '$VERSION';
$VERSION = '2.106';

use base 'Mail::Transport';


sub receive(@) {shift->notImplemented}

#------------------------------------------


1;
