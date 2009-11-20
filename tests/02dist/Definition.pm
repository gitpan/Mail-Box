# Copyrights 2001-2009 by Mark Overmeer.
#  For other contributors see ChangeLog.
# See the manual pages for details on the licensing terms.
# Pod stripped from pm file by OODoc 1.06.

package MailBox::Test::02dist::Definition;
use vars '$VERSION';
$VERSION = '2.092';


sub name     {"check distribution"}
sub critical {0}   # currently only man-pages
sub skip     { undef }

1;
