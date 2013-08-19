# Copyrights 2001-2013 by [Mark Overmeer].
#  For other contributors see ChangeLog.
# See the manual pages for details on the licensing terms.
# Pod stripped from pm file by OODoc 2.01.

package MailBox::Test::81bodyconv::Definition;
use vars '$VERSION';
$VERSION = '2.109';


sub name     {"Mail::Message::Convert; body type conversions"}
sub critical {0}
sub skip()   {undef}  # try even when some modules are not installed.

1;
