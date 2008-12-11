# Copyrights 2001-2008 by Mark Overmeer.
#  For other contributors see ChangeLog.
# See the manual pages for details on the licensing terms.
# Pod stripped from pm file by OODoc 1.05.

package MailBox::Test::54search::Definition;
use vars '$VERSION';
$VERSION = '2.086';


sub name     {"Mail::Box::Search; searching folders"}
sub critical {0}

sub skip     {undef}  # run tests even without Mail::SpamAssassin

1;
