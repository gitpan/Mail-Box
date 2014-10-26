# Copyrights 2001-2012 by [Mark Overmeer].
#  For other contributors see ChangeLog.
# See the manual pages for details on the licensing terms.
# Pod stripped from pm file by OODoc 2.00.

package MailBox::Test::02dist::Definition;
use vars '$VERSION';
$VERSION = '2.106';


sub name     {"check distribution"}
sub critical {0}   # currently only man-pages
sub skip     { undef }

1;
