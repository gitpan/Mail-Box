# Copyrights 2001-2007 by Mark Overmeer.
#  For other contributors see ChangeLog.
# See the manual pages for details on the licensing terms.
# Pod stripped from pm file by OODoc 1.02.

package MailBox::Test::54search::Definition;
use vars '$VERSION';
$VERSION = '2.074';

sub name     {"Mail::Box::Search; searching folders"}
sub critical {0}

sub skip     {undef}  # run tests even without Mail::SpamAssassin

1;
