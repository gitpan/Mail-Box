# Copyrights 2001-2008 by Mark Overmeer.
#  For other contributors see ChangeLog.
# See the manual pages for details on the licensing terms.
# Pod stripped from pm file by OODoc 1.03.
use strict;
use warnings;

package Mail::Transport::Receive;
use vars '$VERSION';
$VERSION = '2.081';
use base 'Mail::Transport';


sub receive(@) {shift->notImplemented}

#------------------------------------------


1;
