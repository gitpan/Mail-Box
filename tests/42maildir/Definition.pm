# Copyrights 2001-2013 by [Mark Overmeer].
#  For other contributors see ChangeLog.
# See the manual pages for details on the licensing terms.
# Pod stripped from pm file by OODoc 2.01.

package MailBox::Test::42maildir::Definition;
use vars '$VERSION';
$VERSION = '2.109';


use Tools    qw/$windows/;

sub name     {"Mail::Box::Maildir; maildir folders"}
sub critical { 0 }
sub skip()
{
      $windows
    ? 'Maildir filenames are not compatible with Windows.'
    : undef;
}

1;
